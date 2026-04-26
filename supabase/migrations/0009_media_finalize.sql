-- Getalong: track storage object deletion separately from view state.
--
-- The product flow is "tap → open → close → delete object immediately."
-- Once the receiver closes the viewer, finalizeViewOnceMedia removes the
-- object from chat-media-private and stamps storage_deleted_at on the row.
-- The row itself stays at status = viewed so the bubble can keep showing
-- "Viewed" / "Opened" instead of flipping to "deleted" (which is for
-- expired or cleaned-up rows).
--
-- deleteExpiredMedia is a safety net: it deletes objects for viewed rows
-- where storage_deleted_at is still null after a short grace period.

alter table public.media_assets
  add column if not exists storage_deleted_at timestamptz;

create index if not exists media_assets_viewed_storage_idx
  on public.media_assets (status, viewed_at)
  where status = 'viewed' and storage_deleted_at is null;
