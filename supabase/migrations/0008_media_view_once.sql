-- Getalong: extend media_assets to support a robust upload + view-once flow.
--
-- New states:
--   pending_upload  – row created by requestMediaUpload, file not yet uploaded
--   active          – attached to a message, viewable by the recipient
--   viewed          – recipient has opened it once (terminal for view-once)
--   expired         – never opened in time (cleaned up by deleteExpiredMedia)
--   deleted         – storage object removed
--   quarantined     – held back (e.g. moderation; reserved for future use)
--
-- New columns:
--   uploaded_at         – set by createChatMessage when transitioning to active
--   attached_message_id – set by createChatMessage when the media gets attached

-- 1. Extend the status check constraint.
alter table public.media_assets
  drop constraint if exists media_assets_status_check;

alter table public.media_assets
  add constraint media_assets_status_check
  check (status in (
    'pending_upload',
    'active',
    'viewed',
    'expired',
    'deleted',
    'quarantined'
  ));

-- 2. New columns.
alter table public.media_assets
  add column if not exists uploaded_at timestamptz;

alter table public.media_assets
  add column if not exists attached_message_id uuid
    references public.messages(id) on delete set null;

-- 3. Helpful indexes for cleanup + lookup.
create index if not exists media_assets_status_created_idx
  on public.media_assets (status, created_at);

create index if not exists media_assets_expires_idx
  on public.media_assets (status, expires_at)
  where expires_at is not null;

create unique index if not exists media_assets_attached_message_unique_idx
  on public.media_assets (attached_message_id)
  where attached_message_id is not null;

-- 4. Storage bucket for view-once chat media. Keep it private.
--    Note: storage.objects RLS is owned by Supabase; we never grant
--    public read here. All access goes through signed URLs minted by
--    openViewOnceMedia.
insert into storage.buckets (id, name, public)
values ('chat-media-private', 'chat-media-private', false)
on conflict (id) do update set public = false;
