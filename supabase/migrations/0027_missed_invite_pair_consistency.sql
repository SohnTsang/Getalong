-- 0027_missed_invite_pair_consistency.sql
--
-- Missed-invite consistency bug: a user could still see a Missed
-- Invite from someone they already had an active chat with, because
--
--   1. `accept_live_invite` (migration 0019) never cleared sibling
--      missed invites between the same pair — only `accept_missed_invite`
--      did. So if A had a `status='missed'` row to B from yesterday and
--      then sent a fresh live invite that B accepted, the chat was
--      created (or reused) but the old missed row lingered on B's tab.
--
--   2. The sibling cleanup in `accept_missed_invite` only touched one
--      direction (sender→receiver), missing the symmetric case where
--      the other party also has stale missed rows pointing at them.
--
--   3. Any rows inserted before this fix that match the pattern are
--      permanently visible until manually resolved.
--
-- This migration:
--   * Replaces `accept_live_invite` with a copy that runs the same
--     bidirectional sibling cleanup `accept_missed_invite` does.
--   * Replaces `accept_missed_invite` so its cleanup is bidirectional
--     too (clears `status='missed'` rows for either ordering of the
--     pair, not just receiver→sender).
--   * Backfills: closes every `status='missed'` invite that already has
--     an active chat room between the two parties.
--
-- Rows transition to `status='declined'` (existing terminal) so history
-- and moderation remain intact. No hard deletes.

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

  -- An active chat now exists between these two users. Close any other
  -- still-missed invite between them (in either direction) so the
  -- Missed tab can't surface stale rows from a pair that's already
  -- connected.
  update public.invites
     set status = 'declined'
   where status = 'missed'
     and id     <> v_invite.id
     and (
       (sender_id = v_invite.sender_id   and receiver_id = v_invite.receiver_id) or
       (sender_id = v_invite.receiver_id and receiver_id = v_invite.sender_id)
     );

  return query select v_room_id, v_invite.id;
end
$$;

-- =========================================================================
-- accept_missed_invite (bidirectional sibling cleanup)
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

  -- Close any other still-missed invite between these two users in
  -- either direction (previously this only cleared receiver=current
  -- user, sender=other). Both ways are stale now that a chat exists.
  update public.invites
     set status = 'declined'
   where status = 'missed'
     and id     <> v_invite.id
     and (
       (sender_id = v_invite.sender_id   and receiver_id = v_invite.receiver_id) or
       (sender_id = v_invite.receiver_id and receiver_id = v_invite.sender_id)
     );

  return query select v_room_id, v_invite.id;
end
$$;

-- =========================================================================
-- Backfill
-- =========================================================================
--
-- Any `status='missed'` invite that ALREADY has an active chat between
-- the same pair is stale. Resolve it now so existing users stop seeing
-- the ghost row. Idempotent — re-running the migration on a clean
-- database is a no-op.

update public.invites i
   set status = 'declined'
 where i.status = 'missed'
   and exists (
     select 1 from public.chat_rooms cr
      where cr.status = 'active'
        and ((cr.user_a = i.sender_id   and cr.user_b = i.receiver_id)
          or (cr.user_a = i.receiver_id and cr.user_b = i.sender_id))
   );
