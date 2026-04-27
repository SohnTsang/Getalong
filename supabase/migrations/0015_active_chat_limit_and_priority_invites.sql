-- 0015_active_chat_limit_and_priority_invites.sql
--
-- Plan rules update:
--   * Free  → active chats max 5;     1 outgoing live invite slot;
--             missed-accept 1/day;    Priority Invite 1 / 2 days.
--   * Gold  → active chats unlimited; 2 outgoing live invite slots;
--             missed-accept unlimited; Priority Invite 3 / day.
--   * Tags cap stays at 3 for everyone (already enforced in 0014).
--
-- Implementation:
--   1. New helper `_ga_active_chat_limit(plan)` returning the cap (-1 = unlimited).
--   2. New helper `_ga_assert_active_chat_room_capacity(uid)` raising
--      `ACTIVE_CHAT_LIMIT_REACHED` when the user is at cap. Called from
--      `accept_live_invite` and `accept_missed_invite` for *both* sides
--      so a paid sender doesn't get blocked by a free receiver and a
--      free sender doesn't slip past their own cap.
--   3. New table `priority_invite_usage` + helpers `_ga_priority_quota` /
--      `_ga_priority_window` / `_ga_record_priority_invite`. No UI yet —
--      this lays the schema down so the send flow can plug in later.

-- =========================================================================
-- 1. Active-chat helpers
-- =========================================================================

create or replace function public._ga_active_chat_limit(p_plan text)
returns int
language sql
immutable
as $$
  select case p_plan
           when 'gold'   then -1
           when 'silver' then -1
           else 5
         end
$$;

create or replace function public._ga_count_active_chats(p_user uuid)
returns int
language sql
stable
as $$
  select count(*)::int
    from public.chat_rooms r
   where r.status = 'active'
     and (r.user_a = p_user or r.user_b = p_user)
$$;

-- Raises ACTIVE_CHAT_LIMIT_REACHED when adding one more active chat would
-- push the user above the plan cap. -1 means unlimited (Gold).
create or replace function public._ga_assert_active_chat_room_capacity(
  p_user uuid
)
returns void
language plpgsql
as $$
declare
  v_plan  text;
  v_limit int;
  v_count int;
begin
  select plan into v_plan from public.profiles where id = p_user;
  if v_plan is null then
    perform public._ga_raise('PROFILE_NOT_FOUND');
  end if;

  v_limit := public._ga_active_chat_limit(v_plan);
  if v_limit < 0 then return; end if;  -- unlimited (Gold)

  v_count := public._ga_count_active_chats(p_user);
  if v_count >= v_limit then
    perform public._ga_raise('ACTIVE_CHAT_LIMIT_REACHED');
  end if;
end
$$;

-- =========================================================================
-- 2. accept_live_invite — enforce cap for both sides
-- =========================================================================

create or replace function public.accept_live_invite(
  p_user      uuid,
  p_invite_id uuid
)
returns table (chat_room_id uuid, invite_id uuid)
language plpgsql
as $$
declare
  v_invite           public.invites%rowtype;
  v_room_id          uuid;
  v_receiver_banned  boolean;
  v_receiver_deleted timestamptz;
  v_blocked          boolean;
begin
  if p_user is null then
    perform public._ga_raise('AUTH_REQUIRED');
  end if;

  select * into v_invite
    from public.invites
   where id = p_invite_id
   for update;

  if v_invite.id is null then
    perform public._ga_raise('INVITE_NOT_FOUND');
  end if;
  if v_invite.receiver_id <> p_user then
    perform public._ga_raise('INVITE_NOT_ACTIONABLE');
  end if;
  if v_invite.status <> 'live_pending' then
    perform public._ga_raise('INVITE_NOT_ACTIONABLE');
  end if;
  if v_invite.live_expires_at <= now() then
    perform public._ga_raise('LIVE_INVITE_EXPIRED');
  end if;

  select is_banned, deleted_at
    into v_receiver_banned, v_receiver_deleted
    from public.profiles where id = p_user;
  if v_receiver_banned or v_receiver_deleted is not null then
    perform public._ga_raise('USER_BANNED');
  end if;

  select exists (
    select 1 from public.blocks
    where (blocker_id = v_invite.sender_id   and blocked_id = v_invite.receiver_id)
       or (blocker_id = v_invite.receiver_id and blocked_id = v_invite.sender_id)
  ) into v_blocked;
  if v_blocked then
    perform public._ga_raise('BLOCKED_RELATIONSHIP');
  end if;

  -- Active-chat caps. Receiver first (the user who tapped Accept) so the
  -- error message attaches to the actor; then sender so a free sender
  -- can't be pushed over by a Gold receiver.
  perform public._ga_assert_active_chat_room_capacity(v_invite.receiver_id);
  perform public._ga_assert_active_chat_room_capacity(v_invite.sender_id);

  update public.invites
     set status      = 'live_accepted',
         accepted_at = now()
   where id = v_invite.id;

  insert into public.chat_rooms(invite_id, user_a, user_b)
  values (v_invite.id, v_invite.sender_id, v_invite.receiver_id)
  returning id into v_room_id;

  delete from public.active_invite_locks locks
   where locks.invite_id = v_invite.id;

  return query select v_room_id, v_invite.id;
end
$$;

-- =========================================================================
-- 3. accept_missed_invite — enforce cap for both sides
-- =========================================================================

create or replace function public.accept_missed_invite(
  p_user      uuid,
  p_invite_id uuid
)
returns table (chat_room_id uuid, invite_id uuid)
language plpgsql
as $$
declare
  v_invite           public.invites%rowtype;
  v_room_id          uuid;
  v_receiver_plan    text;
  v_receiver_banned  boolean;
  v_receiver_deleted timestamptz;
  v_blocked          boolean;
  v_quota            int;
  v_used             int;
begin
  if p_user is null then
    perform public._ga_raise('AUTH_REQUIRED');
  end if;

  select * into v_invite from public.invites where id = p_invite_id for update;
  if v_invite.id is null then
    perform public._ga_raise('INVITE_NOT_FOUND');
  end if;
  if v_invite.receiver_id <> p_user then
    perform public._ga_raise('INVITE_NOT_ACTIONABLE');
  end if;
  if v_invite.status <> 'missed' then
    perform public._ga_raise('INVITE_NOT_ACTIONABLE');
  end if;
  if v_invite.missed_expires_at is not null
     and v_invite.missed_expires_at <= now() then
    perform public._ga_raise('MISSED_INVITE_EXPIRED');
  end if;

  select plan, is_banned, deleted_at
    into v_receiver_plan, v_receiver_banned, v_receiver_deleted
    from public.profiles where id = p_user;
  if v_receiver_plan is null then
    perform public._ga_raise('PROFILE_NOT_FOUND');
  end if;
  if v_receiver_banned or v_receiver_deleted is not null then
    perform public._ga_raise('USER_BANNED');
  end if;

  select exists (
    select 1 from public.blocks
    where (blocker_id = v_invite.sender_id   and blocked_id = v_invite.receiver_id)
       or (blocker_id = v_invite.receiver_id and blocked_id = v_invite.sender_id)
  ) into v_blocked;
  if v_blocked then
    perform public._ga_raise('BLOCKED_RELATIONSHIP');
  end if;

  v_quota := public._ga_missed_accept_quota(v_receiver_plan);
  if v_quota >= 0 then
    select coalesce(accepts_used, 0)
      into v_used
      from public.missed_invite_accept_usage
     where user_id = p_user and usage_date = current_date;
    if coalesce(v_used, 0) >= v_quota then
      perform public._ga_raise('MISSED_ACCEPT_LIMIT_REACHED');
    end if;

    insert into public.missed_invite_accept_usage(user_id, usage_date, accepts_used)
    values (p_user, current_date, 1)
    on conflict (user_id, usage_date)
      do update set accepts_used = public.missed_invite_accept_usage.accepts_used + 1;
  end if;

  perform public._ga_assert_active_chat_room_capacity(v_invite.receiver_id);
  perform public._ga_assert_active_chat_room_capacity(v_invite.sender_id);

  update public.invites
     set status      = 'missed_accepted',
         accepted_at = now()
   where id = v_invite.id;

  insert into public.chat_rooms(invite_id, user_a, user_b)
  values (v_invite.id, v_invite.sender_id, v_invite.receiver_id)
  returning id into v_room_id;

  return query select v_room_id, v_invite.id;
end
$$;

-- =========================================================================
-- 4. Priority Invites — schema + helpers (no send flow yet)
-- =========================================================================
-- Quotas:
--   Free → 1 priority invite per 2-day rolling window.
--   Gold → 3 priority invites per 1-day rolling window.
-- The window is a sliding interval ending "now", not a calendar bucket,
-- so usage feels stable across midnight in any user's timezone.

create or replace function public._ga_priority_quota(p_plan text)
returns int
language sql
immutable
as $$
  select case p_plan
           when 'gold'   then 3
           when 'silver' then 1
           else 1
         end
$$;

create or replace function public._ga_priority_window(p_plan text)
returns interval
language sql
immutable
as $$
  select case p_plan
           when 'gold'   then interval '1 day'
           when 'silver' then interval '2 days'
           else interval '2 days'
         end
$$;

create table if not exists public.priority_invite_usage (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  invite_id   uuid references public.invites(id) on delete set null,
  used_at     timestamptz not null default now(),
  created_at  timestamptz not null default now()
);

create index if not exists priority_invite_usage_user_used_idx
  on public.priority_invite_usage (user_id, used_at desc);

alter table public.priority_invite_usage enable row level security;

drop policy if exists "priority_invite_usage: read own" on public.priority_invite_usage;
create policy "priority_invite_usage: read own"
  on public.priority_invite_usage for select
  using (auth.uid() = user_id);

-- Inserts come from the (future) Priority Invite RPC running with
-- service_role; clients have no insert/update/delete policies.

-- Returns rolling-window count of priority invites the user has used.
create or replace function public._ga_priority_used_in_window(p_user uuid)
returns int
language plpgsql
stable
as $$
declare
  v_plan   text;
  v_window interval;
  v_count  int;
begin
  select plan into v_plan from public.profiles where id = p_user;
  if v_plan is null then return 0; end if;
  v_window := public._ga_priority_window(v_plan);
  select count(*)::int
    into v_count
    from public.priority_invite_usage
   where user_id = p_user
     and used_at > now() - v_window;
  return coalesce(v_count, 0);
end
$$;

-- Raises PRIORITY_INVITE_LIMIT_REACHED if the user has already used their
-- quota inside the rolling window for their plan. No-op for unlimited
-- (none currently — keeps the helper future-proof).
create or replace function public._ga_assert_priority_quota(p_user uuid)
returns void
language plpgsql
as $$
declare
  v_plan  text;
  v_quota int;
  v_used  int;
begin
  select plan into v_plan from public.profiles where id = p_user;
  if v_plan is null then
    perform public._ga_raise('PROFILE_NOT_FOUND');
  end if;
  v_quota := public._ga_priority_quota(v_plan);
  if v_quota < 0 then return; end if;
  v_used  := public._ga_priority_used_in_window(p_user);
  if v_used >= v_quota then
    perform public._ga_raise('PRIORITY_INVITE_LIMIT_REACHED');
  end if;
end
$$;

-- Records one priority invite usage. Idempotency is left to the caller —
-- the eventual send_priority_invite RPC should call assert + record in
-- the same transaction so a failure rolls both back.
create or replace function public._ga_record_priority_invite(
  p_user uuid,
  p_invite_id uuid default null
)
returns void
language plpgsql
as $$
begin
  insert into public.priority_invite_usage(user_id, invite_id)
  values (p_user, p_invite_id);
end
$$;

-- TODO: build send_priority_invite RPC + edge function. Likely 30-second
-- live window (vs 15 for normal) and a stronger visual treatment on the
-- receiver side. Do not change the normal send_live_invite flow.
