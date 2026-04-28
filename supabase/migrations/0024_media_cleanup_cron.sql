-- 0024_media_cleanup_cron.sql
--
-- Adds the missing media-cleanup cron. Until now we relied on the
-- iOS viewer calling `finalizeViewOnceMedia` on close, which deletes
-- the storage object and stamps storage_deleted_at. That's
-- best-effort — if the network call fails, the app is force-quit,
-- or the receiver never opens, the bytes linger in the bucket.
-- Invite expiry already had a cron (migration 0005); media did not.
--
-- This migration:
--   1. Adds a SECURITY DEFINER function that finds media rows whose
--      bytes should be gone (viewed past grace period, expired past
--      TTL, or pending past upload window) and deletes from
--      storage.objects directly + stamps storage_deleted_at.
--   2. Schedules it every 2 minutes via pg_cron, mirroring the
--      pattern used for expire_live_invites.
--
-- Storage is removed by deleting from the storage.objects table —
-- Supabase's storage stack runs the underlying object removal as a
-- side-effect of that DELETE, so we don't need an HTTP call to the
-- storage REST API.

create or replace function public.cleanup_expired_media()
returns table (
  id uuid,
  reason text
) language plpgsql security definer as $$
declare
  pending_cutoff timestamptz := now() - interval '30 minutes';
  viewed_cutoff  timestamptz := now() - interval '2 minutes';
begin
  -- 1. Viewed rows where the client never finalized. After the
  --    2-minute grace period we delete the storage object and
  --    stamp storage_deleted_at; status stays 'viewed' (not
  --    'deleted') to preserve the audit trail.
  return query
  with viewed_target as (
    select m.id, m.storage_path
    from public.media_assets m
    where m.view_once = true
      and m.viewed_at is not null
      and m.viewed_at <= viewed_cutoff
      and m.storage_deleted_at is null
    limit 200
  ),
  removed_viewed as (
    delete from storage.objects o
    using viewed_target t
    where o.bucket_id = 'chat-media-private'
      and o.name = t.storage_path
    returning o.name
  ),
  stamped_viewed as (
    update public.media_assets m
    set storage_deleted_at = now()
    from viewed_target t
    where m.id = t.id
    returning m.id
  )
  select sv.id, 'viewed_grace'::text from stamped_viewed sv;

  -- 2. Pending uploads that never resolved (client crash, network
  --    drop after request but before upload). After 30 minutes
  --    we mark them deleted and (best-effort) remove any partial
  --    object that might exist.
  return query
  with pending_target as (
    select m.id, m.storage_path
    from public.media_assets m
    where m.status = 'pending_upload'
      and m.created_at <= pending_cutoff
      and m.storage_deleted_at is null
    limit 200
  ),
  removed_pending as (
    delete from storage.objects o
    using pending_target t
    where o.bucket_id = 'chat-media-private'
      and o.name = t.storage_path
    returning o.name
  ),
  stamped_pending as (
    update public.media_assets m
    set status = 'expired',
        storage_deleted_at = now()
    from pending_target t
    where m.id = t.id
    returning m.id
  )
  select sp.id, 'pending_timeout'::text from stamped_pending sp;

  -- 3. Active rows past their TTL (the 7-day expires_at). Same
  --    pattern: delete bytes, stamp deleted_at, flip status.
  return query
  with expired_target as (
    select m.id, m.storage_path
    from public.media_assets m
    where m.status = 'active'
      and m.expires_at is not null
      and m.expires_at <= now()
      and m.storage_deleted_at is null
    limit 200
  ),
  removed_expired as (
    delete from storage.objects o
    using expired_target t
    where o.bucket_id = 'chat-media-private'
      and o.name = t.storage_path
    returning o.name
  ),
  stamped_expired as (
    update public.media_assets m
    set status = 'expired',
        storage_deleted_at = now()
    from expired_target t
    where m.id = t.id
    returning m.id
  )
  select se.id, 'ttl_expired'::text from stamped_expired se;
end;
$$;

revoke all on function public.cleanup_expired_media from public;
grant execute on function public.cleanup_expired_media to service_role;

-- Schedule every 2 minutes. Same pg_cron pattern as the invite jobs
-- in 0005 — guarded so it's a no-op when pg_cron isn't installed.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    -- Drop any prior schedule with the same name so re-applying the
    -- migration doesn't error.
    perform cron.unschedule('getalong_cleanup_expired_media')
    where exists (
      select 1 from cron.job where jobname = 'getalong_cleanup_expired_media'
    );

    perform cron.schedule(
      'getalong_cleanup_expired_media',
      '*/2 * * * *',
      $cron$ select public.cleanup_expired_media(); $cron$
    );
  end if;
end $$;
