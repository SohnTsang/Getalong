-- 0032_block_user_closes_active_room.sql
--
-- Blocking a user must remove the active chat between the pair for
-- BOTH parties — not just hide it on the blocker's client. Today
-- blockUser only inserts the `blocks` row and cancels live_pending
-- invites; any active chat between the two users keeps existing and
-- both clients can still send messages until the next manual leave.
--
-- This migration adds a SECURITY DEFINER SQL function that does the
-- whole block flow in one transaction:
--
--   1. Insert into `blocks` (idempotent via ON CONFLICT) — captures
--      `already_blocked` for the response.
--   2. Soft-delete every active chat_room between the pair (in either
--      ordering) — flips status='deleted' with deleted_at/by stamped.
--      Reuses the existing `'deleted'` terminal status from migration
--      0016; no new state machine.
--   3. Cancel any live_pending invite between the pair so a stale
--      15-second timer can't surface on either side.
--   4. Flip the just-closed rooms' media_assets rows to
--      `status='deleted'` and stamp `retention_until = now()` so the
--      retention sweep picks them up (matches what
--      `deleteConversation` Edge Function does inline). Moderation-
--      held media is preserved.
--
-- Edge Function blockUser is updated in the same commit to call this
-- function via `rpc()` instead of doing four separate writes. Atomic:
-- a failure in any step rolls the entire block back, so the blocker's
-- client can't end up in a half-blocked state ("you're blocked but
-- the chat still exists").
--
-- Postcondition contract:
--   * `blocks` row exists.
--   * No `status='active'` chat_rooms row remains between the pair.
--   * No `status='live_pending'` invite remains between the pair.
--   * Any `media_assets` for the now-deleted rooms are queued for
--     byte cleanup (except moderation-held).
--   * Pre-existing chat_rooms in non-active state are untouched
--     (history preserved).
--   * Messages / reports / moderation rows are never hard-deleted.
--
-- Idempotent: a re-block of the same target returns
-- `already_blocked = true`, `rooms_closed = 0` (no active rooms left
-- to close on the second pass).

create or replace function public._ga_block_user_and_close_rooms(
  p_blocker uuid,
  p_blocked uuid
)
returns table (
  already_blocked boolean,
  rooms_closed    int
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_already       boolean := false;
  v_rooms_closed  int := 0;
  v_closed_ids    uuid[];
begin
  if p_blocker is null or p_blocked is null then
    raise exception 'AUTH_REQUIRED' using errcode = 'P0001';
  end if;
  if p_blocker = p_blocked then
    raise exception 'SELF_BLOCK_NOT_ALLOWED' using errcode = 'P0001';
  end if;

  -- 1. Block row (idempotent).
  insert into public.blocks (blocker_id, blocked_id)
  values (p_blocker, p_blocked)
  on conflict (blocker_id, blocked_id) do nothing;
  -- If no row got inserted, the row already existed.
  if not found then
    v_already := true;
  end if;

  -- 2. Soft-delete every active chat_room between the pair. The unique
  --    partial index from migration 0019 means there should be at most
  --    one row, but the WHERE clause covers both pair orderings and a
  --    defensive multi-row close in case legacy state leaked through.
  with closed as (
    update public.chat_rooms
       set status     = 'deleted',
           deleted_at = now(),
           deleted_by = p_blocker
     where status = 'active'
       and (
            (user_a = p_blocker and user_b = p_blocked) or
            (user_a = p_blocked and user_b = p_blocker)
           )
    returning id
  )
  select coalesce(array_agg(id), '{}'::uuid[]) into v_closed_ids from closed;
  v_rooms_closed := coalesce(array_length(v_closed_ids, 1), 0);

  -- 3. Cancel any in-flight live invite between the pair so neither
  --    side sees a 15-second countdown after the block lands.
  update public.invites
     set status = 'cancelled'
   where status = 'live_pending'
     and (
          (sender_id = p_blocker and receiver_id = p_blocked) or
          (sender_id = p_blocked and receiver_id = p_blocker)
         );

  -- 4. Mark each closed room's media for cleanup. Same pattern the
  --    deleteConversation Edge Function uses inline. Moderation-held
  --    rows are preserved.
  if v_rooms_closed > 0 then
    update public.media_assets
       set status          = 'deleted',
           retention_until = now()
     where room_id = any (v_closed_ids)
       and storage_deleted_at is null
       and moderation_hold_at is null;
  end if;

  return query select v_already, v_rooms_closed;
end;
$$;

revoke all on function public._ga_block_user_and_close_rooms(uuid, uuid) from public;
grant execute on function public._ga_block_user_and_close_rooms(uuid, uuid) to service_role;
