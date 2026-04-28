-- 0020_realtime_chat_rooms_publication.sql
--
-- Adds public.chat_rooms to the supabase_realtime publication so the
-- iOS app can listen for chat-room mutations app-wide. The Chats tab's
-- ViewModel uses these events to refresh the chat list (and the latest
-- message preview) the moment a new message lands — without requiring
-- the user to open the chat or even be on the Chats tab.
--
-- We also flip replica identity to FULL so UPDATEs on rows that don't
-- change the primary key still carry user_a/user_b in the change
-- payload (the SDK uses those for its receiver/sender filters).

do $$
begin
  alter publication supabase_realtime add table public.chat_rooms;
exception when duplicate_object then
  null;
end $$;

alter table public.chat_rooms replica identity full;
