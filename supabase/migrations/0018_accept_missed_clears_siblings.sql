-- 0018_accept_missed_clears_siblings.sql
--
-- When a user accepts a missed invite, also resolve any other still-
-- missed invites from the same sender. The Invite tab dedupes by
-- sender, so accepting one invite from a person who has sent several
-- previously made the card "come back" on refresh (the next sibling
-- got promoted) and the missed-count badge didn't decrement.
--
-- Behavior:
--   * accept_missed_invite still creates exactly one chat room.
--   * Sibling rows transition to 'declined' (terminal, won't reappear
--     in fetchMissedInvites). They aren't deleted — moderation /
--     reporting remain intact.
--   * Idempotent against re-runs; no change if there are no siblings.

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

  -- Resolve sibling missed invites from the same sender so the user
  -- doesn't see another card from this person on the next refresh and
  -- the missed-count badge actually decrements.
  update public.invites
     set status = 'declined'
   where receiver_id = v_invite.receiver_id
     and sender_id   = v_invite.sender_id
     and status      = 'missed'
     and id          <> v_invite.id;

  return query select v_room_id, v_invite.id;
end
$$;
