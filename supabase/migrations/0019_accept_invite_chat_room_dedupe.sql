-- 0019_accept_invite_chat_room_dedupe.sql
--
-- Two related bugs the user hit:
--   1. Accepting a missed/live invite from someone you ALREADY have an
--      active chat with creates a second chat_rooms row, so the Chats
--      list shows the conversation twice.
--   2. After accepting a missed invite, the missed card sometimes
--      lingered because the now-extra row interfered with downstream
--      state.
--
-- Root cause: `accept_live_invite` and `accept_missed_invite` always
-- `INSERT` into chat_rooms without checking for an existing active row
-- between the two participants. Fix: look up an active room first; if
-- one exists, reuse it. If only deleted/archived/blocked rooms exist
-- between the two, create a fresh active row.
--
-- We also add a partial unique index as a belt-and-braces guard so the
-- database itself rejects a second active row even if a future caller
-- forgets to reuse. Pair-key uses LEAST/GREATEST so (A,B) and (B,A) are
-- treated as the same pair.

create unique index if not exists chat_rooms_one_active_per_pair_idx
  on public.chat_rooms (least(user_a, user_b), greatest(user_a, user_b))
  where status = 'active';

-- =========================================================================
-- accept_live_invite
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

  select * into v_invite from public.invites where id = p_invite_id for update;
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

  -- Reuse an existing active chat room with the same partner if one
  -- exists. Skip the cap check in that case — accepting an invite that
  -- merges into an already-counted chat doesn't push the user over.
  select id into v_room_id
    from public.chat_rooms
   where status = 'active'
     and ((user_a = v_invite.sender_id   and user_b = v_invite.receiver_id)
       or (user_a = v_invite.receiver_id and user_b = v_invite.sender_id))
   limit 1;

  if v_room_id is null then
    perform public._ga_assert_active_chat_room_capacity(v_invite.receiver_id);
    perform public._ga_assert_active_chat_room_capacity(v_invite.sender_id);

    insert into public.chat_rooms(invite_id, user_a, user_b)
    values (v_invite.id, v_invite.sender_id, v_invite.receiver_id)
    returning id into v_room_id;
  end if;

  update public.invites
     set status      = 'live_accepted',
         accepted_at = now()
   where id = v_invite.id;

  delete from public.active_invite_locks locks
   where locks.invite_id = v_invite.id;

  return query select v_room_id, v_invite.id;
end
$$;

-- =========================================================================
-- accept_missed_invite (also keeps sibling-clearing from migration 0018)
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

  -- Reuse an existing active chat room if there already is one between
  -- the same pair; otherwise create one (and check capacity for both).
  select id into v_room_id
    from public.chat_rooms
   where status = 'active'
     and ((user_a = v_invite.sender_id   and user_b = v_invite.receiver_id)
       or (user_a = v_invite.receiver_id and user_b = v_invite.sender_id))
   limit 1;

  if v_room_id is null then
    perform public._ga_assert_active_chat_room_capacity(v_invite.receiver_id);
    perform public._ga_assert_active_chat_room_capacity(v_invite.sender_id);

    insert into public.chat_rooms(invite_id, user_a, user_b)
    values (v_invite.id, v_invite.sender_id, v_invite.receiver_id)
    returning id into v_room_id;
  end if;

  update public.invites
     set status      = 'missed_accepted',
         accepted_at = now()
   where id = v_invite.id;

  -- Resolve any sibling missed invites from the same sender so the
  -- card doesn't reappear on refresh and the badge actually decrements.
  update public.invites
     set status = 'declined'
   where receiver_id = v_invite.receiver_id
     and sender_id   = v_invite.sender_id
     and status      = 'missed'
     and id          <> v_invite.id;

  return query select v_room_id, v_invite.id;
end
$$;
