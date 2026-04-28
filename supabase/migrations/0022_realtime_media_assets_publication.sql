-- 0022_realtime_media_assets_publication.sql
--
-- Adds public.media_assets to the supabase_realtime publication so the
-- chat room view can react to status changes (active → viewed, storage
-- deletion, expiry) in real time. Without this, the sender's bubble
-- only learns the receiver opened a view-once photo on next manual
-- refresh / re-entry to the room.

do $$
begin
  alter publication supabase_realtime add table public.media_assets;
exception when duplicate_object then
  null;
end $$;

alter table public.media_assets replica identity full;
