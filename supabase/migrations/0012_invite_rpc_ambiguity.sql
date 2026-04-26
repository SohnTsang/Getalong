-- Fix ambiguous column references in send_live_invite + accept_live_invite.
--
-- Both functions use RETURNS TABLE (...) which declares OUT columns
-- (`live_expires_at`, `invite_id`) that PL/pgSQL also treats as visible
-- identifiers in the function body. When the body then references those
-- same names against the public.invites / public.active_invite_locks
-- tables, the planner can't disambiguate the OUT column from the table
-- column and raises:
--
--   ERROR  42702: column reference "live_expires_at" is ambiguous
--   ERROR  42702: column reference "invite_id" is ambiguous
--
-- Fix: qualify every offending site with a table alias.

-- =========================================================================
-- send_live_invite — line 141 referenced unqualified `live_expires_at`.
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

  select plan, is_banned, deleted_at
    into v_sender_plan, v_sender_banned, v_sender_deleted
    from public.profiles where id = p_sender;
  if v_sender_plan is null then
    perform public._ga_raise('PROFILE_NOT_FOUND');
  end if;
  if v_sender_banned or v_sender_deleted is not null then
    perform public._ga_raise('USER_BANNED');
  end if;

  select is_banned, deleted_at
    into v_receiver_banned, v_receiver_deleted
    from public.profiles where id = p_receiver;
  if v_receiver_banned is null then
    perform public._ga_raise('PROFILE_NOT_FOUND');
  end if;
  if v_receiver_banned or v_receiver_deleted is not null then
    perform public._ga_raise('RECEIVER_BANNED');
  end if;

  select exists (
    select 1 from public.blocks
    where (blocker_id = p_sender   and blocked_id = p_receiver)
       or (blocker_id = p_receiver and blocked_id = p_sender)
  ) into v_blocked;
  if v_blocked then
    perform public._ga_raise('BLOCKED_RELATIONSHIP');
  end if;

  v_slot_limit := public._ga_concurrent_live_slots(v_sender_plan);
  select count(*)
    into v_active_count
    from public.active_invite_locks
   where user_id = p_sender
     and locked_until > now();
  if v_active_count >= v_slot_limit then
    perform public._ga_raise('LIVE_INVITE_SLOT_FULL');
  end if;

  -- Aliased table reference disambiguates `live_expires_at` from the
  -- RETURNS TABLE OUT column of the same name.
  select count(*)
    into v_dup
    from public.invites i
   where i.sender_id   = p_sender
     and i.receiver_id = p_receiver
     and i.status      = 'live_pending'
     and i.live_expires_at > now();
  if v_dup > 0 then
    perform public._ga_raise('DUPLICATE_LIVE_INVITE');
  end if;

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
-- accept_live_invite — line 238 referenced unqualified `invite_id` against
-- public.active_invite_locks. The OUT column shadowed the table column.
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

  update public.invites
     set status      = 'live_accepted',
         accepted_at = now()
   where id = v_invite.id;

  insert into public.chat_rooms(invite_id, user_a, user_b)
  values (v_invite.id, v_invite.sender_id, v_invite.receiver_id)
  returning id into v_room_id;

  -- Aliased table reference: locks.invite_id is the column we want to
  -- match, not the OUT column of the same name on this function.
  delete from public.active_invite_locks locks
   where locks.invite_id = v_invite.id;

  return query select v_room_id, v_invite.id;
end
$$;
