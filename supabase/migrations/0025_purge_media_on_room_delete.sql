-- 0025_purge_media_on_room_delete.sql
--
-- Immediate media purge when a chat room is left. Until now,
-- deleteConversation flipped chat_rooms.status to 'deleted' and the
-- room vanished from both participants' Chats lists, but any
-- unopened/unviewed media_assets rows in that room kept their
-- storage objects until the +7-day TTL expired or until the
-- cleanup cron next swept. That's a lot of "deleted" data
-- continuing to live in the bucket.
--
-- This trigger fires on the active → deleted transition and:
--   1. removes every storage object for media_assets in that room
--      whose storage_deleted_at is null (Supabase's storage stack
--      handles backend object removal as a side-effect of the
--      DELETE on storage.objects),
--   2. flips those media_assets rows to status='deleted' with a
--      stamp on storage_deleted_at so finalizeViewOnceMedia and
--      cleanup_expired_media skip them on subsequent passes.
--
-- Messages are kept as-is — they're audit/moderation data, hidden
-- from the user via the chat_rooms.status='active' filter on
-- fetchRooms, and never expose payload bytes (we never stored
-- bytes in messages, only the media_id reference).

create or replace function public.purge_media_on_room_delete()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'deleted' and (old.status is distinct from 'deleted') then
    -- 1. Remove the underlying storage objects.
    delete from storage.objects o
    using public.media_assets m
    where m.room_id = new.id
      and m.storage_deleted_at is null
      and o.bucket_id = 'chat-media-private'
      and o.name      = m.storage_path;

    -- 2. Mark the rows so the row state doesn't disagree with
    --    the bucket state.
    update public.media_assets
    set status = 'deleted',
        storage_deleted_at = now()
    where room_id = new.id
      and storage_deleted_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists purge_media_on_room_delete on public.chat_rooms;
create trigger purge_media_on_room_delete
  after update of status on public.chat_rooms
  for each row
  execute function public.purge_media_on_room_delete();
