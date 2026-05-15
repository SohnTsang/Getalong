-- 0030_drop_purge_trigger_leave_chat_robust.sql
--
-- Leave-chat is still surfacing `DELETE_FAILED` even after 0029
-- (which dropped the SQL-level storage.objects DELETE from the
-- purge_media_on_room_delete trigger). The trigger pattern itself
-- is fragile: any future Postgres-level error inside the trigger
-- — a permissions change, a new check constraint, a realtime
-- publication quirk, a follow-up trigger added by the platform —
-- rolls back the chat_rooms UPDATE that fired it, and the user
-- ends up unable to leave their conversation with no actionable
-- error.
--
-- Architecture fix: the Edge Function owns the leave-chat path.
-- It marks chat_rooms as `deleted` first, and the related
-- media_assets state update happens explicitly from the Edge
-- Function afterwards (failures there are logged but do NOT
-- roll the room update back). The AFTER-UPDATE trigger is no
-- longer needed, so drop it.
--
-- The retention sweep (deleteExpiredMedia Edge Function) is still
-- the byte-cleanup path; rows whose `retention_until` is set to
-- `now()` by the Edge Function become immediately eligible.
-- Moderation-held rows are still untouched.
--
-- The function itself is left in place as a harmless no-op so any
-- pre-existing references / docs don't blow up; only the trigger
-- binding is removed.

drop trigger if exists purge_media_on_room_delete on public.chat_rooms;

create or replace function public.purge_media_on_room_delete()
returns trigger language plpgsql security definer as $$
begin
  -- Intentionally empty. The chat-room → media cleanup runs from
  -- the `deleteConversation` Edge Function now, where a failure
  -- in the secondary update cannot roll back the primary
  -- chat_rooms transition. See migration 0030 for rationale.
  return new;
end;
$$;
