-- Atomic invite RPCs.
--
-- These functions are the only thing that should mutate `invites`,
-- `active_invite_locks`, `missed_invite_accept_usage`, and `chat_rooms`.
-- Edge Functions are the trust boundary for auth; they call these
-- with the service role.
--
-- Errors raise SQLSTATE 'P0001' with a stable code in MESSAGE so the
-- Edge Function layer can translate to the JSON error contract.

-- =========================================================================
-- Constants & helpers
-- =========================================================================

create or replace function public._ga_live_seconds()
returns int language sql immutable as $$ select 15 $$;

create or replace function public._ga_missed_ttl()
returns interval language sql immutable as $$ select interval '7 days' $$;

create or replace function public._ga_concurrent_live_slots(p_plan text)
returns int
language sql
immutable
as $$
  select case p_plan
           when 'gold'   then 2
           when 'silver' then 1
           else 1
         end
$$;

create or replace function public._ga_missed_accept_quota(p_plan text)
returns int
language sql
immutable
as $$
  -- Returns daily quota. -1 means unlimited.
  select case p_plan
           when 'gold'   then -1
           when 'silver' then -1
           else 1
         end
$$;

-- Raise a stable error code that Edge Functions can map to the JSON contract.
create or replace function public._ga_raise(p_code text)
returns void language plpgsql as $$
begin
  raise exception '%', p_code using errcode = 'P0001';
end
$$;

-- =========================================================================
-- 1. send_live_invite
-- =========================================================================

create or replace function public.send_live_invite(
  p_sender   uuid,
  p_receiver uuid,
  p_post_id  uuid default null,
  p_message  text default null
)
returns table (
  invite_id        uuid,
  live_expires_at  timestamptz,
  duration_seconds int
)
language plpgsql
as $$
declare
  v_sender_plan       text;
  v_sender_banned     boolean;
  v_sender_deleted    timestamptz;
  v_receiver_banned   boolean;
  v_receiver_deleted  timestamptz;
  v_active_count      int;
  v_slot_limit        int;
  v_blocked           boolean;
  v_dup               int;
  v_invite            public.invites%rowtype;
begin
  if p_sender is null or p_receiver is null then
    perform public._ga_raise('AUTH_REQUIRED');
  end if;

  if p_sender = p_receiver then
    perform public._ga_raise('SELF_INVITE_NOT_ALLOWED');
  end if;

  -- Sender state
  select plan, is_banned, deleted_at
    into v_sender_plan, v_sender_banned, v_sender_deleted
    from public.profiles where id = p_sender;
  if v_sender_plan is null then
    perform public._ga_raise('PROFILE_NOT_FOUND');
  end if;
  if v_sender_banned or v_sender_deleted is not null then
    perform public._ga_raise('USER_BANNED');
  end if;

  -- Receiver state
  select is_banned, deleted_at
    into v_receiver_banned, v_receiver_deleted
    from public.profiles where id = p_receiver;
  if v_receiver_banned is null then
    perform public._ga_raise('PROFILE_NOT_FOUND');
  end if;
  if v_receiver_banned or v_receiver_deleted is not null then
    perform public._ga_raise('RECEIVER_BANNED');
  end if;

  -- Block relationship in either direction
  select exists (
    select 1 from public.blocks
    where (blocker_id = p_sender   and blocked_id = p_receiver)
       or (blocker_id = p_receiver and blocked_id = p_sender)
  ) into v_blocked;
  if v_blocked then
    perform public._ga_raise('BLOCKED_RELATIONSHIP');
  end if;

  -- Concurrent live slot enforcement
  v_slot_limit := public._ga_concurrent_live_slots(v_sender_plan);
  select count(*)
    into v_active_count
    from public.active_invite_locks
   where user_id = p_sender
     and locked_until > now();
  if v_active_count >= v_slot_limit then
    perform public._ga_raise('LIVE_INVITE_SLOT_FULL');
  end if;

  -- Duplicate live_pending to same receiver
  select count(*)
    into v_dup
    from public.invites
   where sender_id = p_sender
     and receiver_id = p_receiver
     and status = 'live_pending'
     and live_expires_at > now();
  if v_dup > 0 then
    perform public._ga_raise('DUPLICATE_LIVE_INVITE');
  end if;

  -- Create invite + lock
  insert into public.invites(
    sender_id, receiver_id, post_id, message,
    invite_type, delivery_mode, status,
    live_expires_at
  ) values (
    p_sender, p_receiver, p_post_id, p_message,
    'normal', 'live', 'live_pending',
    now() + (public._ga_live_seconds() || ' seconds')::interval
  )
  returning * into v_invite;

  insert into public.active_invite_locks(user_id, invite_id, locked_until)
  values (p_sender, v_invite.id, v_invite.live_expires_at);

  return query
    select v_invite.id, v_invite.live_expires_at, public._ga_live_seconds();
end
$$;

-- =========================================================================
-- 2. accept_live_invite
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

  -- Lock invite row to avoid races with mark_live_invite_missed / expire.
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

  -- Receiver banned check
  select is_banned, deleted_at
    into v_receiver_banned, v_receiver_deleted
    from public.profiles where id = p_user;
  if v_receiver_banned or v_receiver_deleted is not null then
    perform public._ga_raise('USER_BANNED');
  end if;

  -- Block relationship
  select exists (
    select 1 from public.blocks
    where (blocker_id = v_invite.sender_id   and blocked_id = v_invite.receiver_id)
       or (blocker_id = v_invite.receiver_id and blocked_id = v_invite.sender_id)
  ) into v_blocked;
  if v_blocked then
    perform public._ga_raise('BLOCKED_RELATIONSHIP');
  end if;

  -- TODO: enforce active_chat limit per plan once chat-limit rules ship.

  -- Flip invite -> accepted, create room, release lock.
  update public.invites
     set status      = 'live_accepted',
         accepted_at = now()
   where id = v_invite.id;

  insert into public.chat_rooms(invite_id, user_a, user_b)
  values (v_invite.id, v_invite.sender_id, v_invite.receiver_id)
  returning id into v_room_id;

  delete from public.active_invite_locks
   where invite_id = v_invite.id;

  -- Important: do NOT touch missed_invite_accept_usage on a live accept.

  return query select v_room_id, v_invite.id;
end
$$;

-- =========================================================================
-- 3. decline_invite
-- =========================================================================

create or replace function public.decline_invite(
  p_user      uuid,
  p_invite_id uuid
)
returns void
language plpgsql
as $$
declare
  v_invite public.invites%rowtype;
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
  if v_invite.status not in ('live_pending', 'missed') then
    perform public._ga_raise('INVITE_NOT_ACTIONABLE');
  end if;

  update public.invites set status = 'declined' where id = v_invite.id;

  if v_invite.status = 'live_pending' then
    delete from public.active_invite_locks where invite_id = v_invite.id;
  end if;
end
$$;

-- =========================================================================
-- 4. cancel_live_invite
-- =========================================================================

create or replace function public.cancel_live_invite(
  p_user      uuid,
  p_invite_id uuid
)
returns void
language plpgsql
as $$
declare
  v_invite public.invites%rowtype;
begin
  if p_user is null then
    perform public._ga_raise('AUTH_REQUIRED');
  end if;

  select * into v_invite from public.invites where id = p_invite_id for update;
  if v_invite.id is null then
    perform public._ga_raise('INVITE_NOT_FOUND');
  end if;
  if v_invite.sender_id <> p_user then
    perform public._ga_raise('INVITE_NOT_ACTIONABLE');
  end if;
  if v_invite.status <> 'live_pending' then
    perform public._ga_raise('INVITE_NOT_ACTIONABLE');
  end if;

  update public.invites set status = 'cancelled' where id = v_invite.id;
  delete from public.active_invite_locks where invite_id = v_invite.id;
end
$$;

-- =========================================================================
-- 5. mark_live_invite_missed (single invite — called from client at t=0)
-- =========================================================================

create or replace function public.mark_live_invite_missed(
  p_invite_id uuid
)
returns void
language plpgsql
as $$
declare
  v_invite public.invites%rowtype;
begin
  select * into v_invite from public.invites where id = p_invite_id for update;
  if v_invite.id is null then
    perform public._ga_raise('INVITE_NOT_FOUND');
  end if;

  -- Idempotent: if already missed/accepted/etc, no-op.
  if v_invite.status <> 'live_pending' then
    return;
  end if;
  if v_invite.live_expires_at > now() then
    perform public._ga_raise('INVITE_NOT_ACTIONABLE');
  end if;

  update public.invites
     set status            = 'missed',
         delivery_mode     = 'missed',
         missed_expires_at = now() + public._ga_missed_ttl()
   where id = v_invite.id;

  delete from public.active_invite_locks where invite_id = v_invite.id;
end
$$;

-- =========================================================================
-- 6. expire_live_invites (cron / safety net)
-- =========================================================================

create or replace function public.expire_live_invites()
returns int
language plpgsql
as $$
declare
  v_count int;
begin
  with expired as (
    update public.invites
       set status            = 'missed',
           delivery_mode     = 'missed',
           missed_expires_at = now() + public._ga_missed_ttl()
     where status = 'live_pending'
       and live_expires_at <= now()
    returning id
  )
  delete from public.active_invite_locks
   where invite_id in (select id from expired);

  get diagnostics v_count = row_count;
  return v_count;
end
$$;

-- =========================================================================
-- 7. accept_missed_invite
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

  -- Quota: only free users are gated. Silver/Gold pass through.
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

  -- TODO: enforce active_chat limit per plan once chat-limit rules ship.

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
-- 8. expire_missed_invites (cron)
-- =========================================================================

create or replace function public.expire_missed_invites()
returns int
language plpgsql
as $$
declare
  v_count int;
begin
  update public.invites
     set status = 'expired'
   where status = 'missed'
     and missed_expires_at is not null
     and missed_expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end
$$;

-- =========================================================================
-- Permissions
-- =========================================================================
-- Lock these RPCs to service role only. Edge Functions call them after
-- verifying the user JWT.

revoke all on function public.send_live_invite(uuid, uuid, uuid, text)        from public, anon, authenticated;
revoke all on function public.accept_live_invite(uuid, uuid)                  from public, anon, authenticated;
revoke all on function public.decline_invite(uuid, uuid)                      from public, anon, authenticated;
revoke all on function public.cancel_live_invite(uuid, uuid)                  from public, anon, authenticated;
revoke all on function public.mark_live_invite_missed(uuid)                   from public, anon, authenticated;
revoke all on function public.expire_live_invites()                           from public, anon, authenticated;
revoke all on function public.accept_missed_invite(uuid, uuid)                from public, anon, authenticated;
revoke all on function public.expire_missed_invites()                         from public, anon, authenticated;

grant execute on function public.send_live_invite(uuid, uuid, uuid, text)     to service_role;
grant execute on function public.accept_live_invite(uuid, uuid)               to service_role;
grant execute on function public.decline_invite(uuid, uuid)                   to service_role;
grant execute on function public.cancel_live_invite(uuid, uuid)               to service_role;
grant execute on function public.mark_live_invite_missed(uuid)                to service_role;
grant execute on function public.expire_live_invites()                        to service_role;
grant execute on function public.accept_missed_invite(uuid, uuid)             to service_role;
grant execute on function public.expire_missed_invites()                      to service_role;

-- =========================================================================
-- Schedule the safety-net cron (Supabase pg_cron extension)
-- =========================================================================
-- expire_live_invites runs every minute. Product does not depend on this
-- precision: clients call mark_live_invite_missed at t=0 and the server
-- rejects late acceptLiveInvite calls anyway. This is just a safety net.

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'getalong-expire-live-invites',
      '* * * * *',
      $cron$ select public.expire_live_invites(); $cron$
    );
    perform cron.schedule(
      'getalong-expire-missed-invites',
      '*/15 * * * *',
      $cron$ select public.expire_missed_invites(); $cron$
    );
  end if;
exception when others then
  raise notice 'pg_cron not enabled or scheduling failed: %', sqlerrm;
end
$$;
