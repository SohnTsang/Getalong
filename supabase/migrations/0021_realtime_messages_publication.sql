-- 0021_realtime_messages_publication.sql
--
-- Adds public.messages to the supabase_realtime publication so the
-- chat room view receives INSERT events for new messages in real time.
-- Without this, RealtimeChatManager.subscribe succeeds but no events
-- ever fire — the receiver only sees a new message after a manual
-- refresh / re-open of the room.
--
-- Replica identity FULL is set so UPDATE events (e.g. is_deleted) carry
-- enough context to be useful, mirroring what we did for invites and
-- chat_rooms in 0017 and 0020.

do $$
begin
  alter publication supabase_realtime add table public.messages;
exception when duplicate_object then
  -- Already in the publication; safe to ignore.
  null;
end $$;

alter table public.messages replica identity full;
