-- 0026_media_retention_and_moderation_hold.sql
--
-- Shifts view-once media from "delete bytes the moment the receiver closes
-- the viewer" to a 24-hour private retention window with a moderation
-- hold escape hatch. The user-facing flow does not change: a view-once
-- item still opens exactly once, and the bubble still flips to "Opened" /
-- "No longer available" the instant the viewer closes. The bytes,
-- however, sit in the private bucket until either:
--
--   * `retention_until` (created_at + 24 hours) elapses, or
--   * a report is filed against the media / its message / its room / the
--     other party (with room context). In that case `moderation_hold_at`
--     is stamped and the cleanup cron skips the row indefinitely.
--
-- This migration:
--   1. Extends `media_assets` with retention + moderation columns and the
--      indexes the cleanup function needs to stay cheap.
--   2. Extends `chat_rooms` with a parallel moderation hold so a chat-room
--      report can be reasoned about even when the media rows are gone.
--   3. Rewrites `cleanup_expired_media` to honour `retention_until` and
--      `moderation_hold_at`.
--   4. Updates `purge_media_on_room_delete` so the leave-chat trigger does
--      *not* nuke moderation-held media. The reported room is what gets
--      preserved; the user's own ability to leave it is unchanged.
--   5. Adds a thin `moderation_access_logs` table so any future reviewer
--      tooling has an audit surface from day one.
--
-- We do not change RLS on media_assets in this migration. Writes to the
-- new columns (retention_until / moderation_hold_at / view_finalized_at /
-- storage_deleted_at / moderation_review_*) only happen via SECURITY
-- DEFINER functions or the service role used by Edge Functions; the
-- existing read-only-for-participants policy still applies, and
-- moderation_access_logs is service-role-only by default (no policy =
-- no client access under RLS).

-- 1. media_assets columns ----------------------------------------------------

alter table public.media_assets
  add column if not exists retention_until         timestamptz,
  add column if not exists view_finalized_at       timestamptz,
  add column if not exists moderation_hold_at      timestamptz,
  add column if not exists moderation_hold_reason  text,
  add column if not exists moderation_hold_report_id uuid
    references public.reports(id) on delete set null,
  add column if not exists moderation_reviewed_at  timestamptz,
  add column if not exists moderation_review_status text;

-- Backfill retention_until for existing rows so the new cleanup logic has
-- something to compare against. Anything created more than 24 hours ago
-- is given an immediate retention_until = now() — the cron will pick
-- those up on its next pass, matching the previous 2-minute viewed-grace
-- behaviour for all practical purposes (the previous regime would have
-- deleted them already; this just unblocks the new code path).
update public.media_assets
   set retention_until = greatest(
     now(),
     created_at + interval '24 hours'
   )
 where retention_until is null;

-- 2. media_assets indexes ----------------------------------------------------

-- Cleanup hot path: rows that are eligible for deletion. The partial
-- predicates keep this index tiny (only rows still needing work).
create index if not exists media_assets_retention_cleanup_idx
  on public.media_assets (retention_until)
  where storage_deleted_at is null
    and moderation_hold_at is null;

-- Moderation review queue: short list of rows currently held.
create index if not exists media_assets_moderation_hold_idx
  on public.media_assets (moderation_hold_at)
  where moderation_hold_at is not null;

-- Storage-already-deleted lookups (rare but useful in audit/reporting).
create index if not exists media_assets_storage_deleted_idx
  on public.media_assets (storage_deleted_at)
  where storage_deleted_at is not null;

-- 3. chat_rooms moderation hold ---------------------------------------------

alter table public.chat_rooms
  add column if not exists moderation_hold_at      timestamptz,
  add column if not exists moderation_hold_reason  text,
  add column if not exists moderation_hold_report_id uuid
    references public.reports(id) on delete set null;

create index if not exists chat_rooms_moderation_hold_idx
  on public.chat_rooms (moderation_hold_at)
  where moderation_hold_at is not null;

-- 4. cleanup_expired_media — retention + hold aware -------------------------
--
-- Replaces the previous viewed_grace cleanup. New rules:
--   * Pending uploads older than 30 minutes that are NOT on hold: delete
--     storage object (best-effort) and flip status='expired'.
--   * Active rows past expires_at that are NOT on hold: delete storage
--     and flip status='expired'.
--   * Any row past retention_until that is NOT on hold and whose bytes
--     have not been deleted yet: delete storage and stamp
--     storage_deleted_at. We deliberately keep status as-is (viewed /
--     active / expired) — the row is the audit trail, the byte-state is
--     the storage_deleted_at stamp.
--
-- Held rows (moderation_hold_at is not null) are never touched.
-- Idempotent: a second run that finds storage already gone proceeds to
-- stamp the row anyway, so retries close the loop instead of leaving
-- ghost rows.

create or replace function public.cleanup_expired_media()
returns table (
  id uuid,
  reason text
) language plpgsql security definer as $$
declare
  pending_cutoff timestamptz := now() - interval '30 minutes';
  batch_limit    int := 500;
begin
  -- 1. Pending uploads that never resolved (client crash, network drop
  --    after request but before upload). After 30 minutes we mark them
  --    expired and (best-effort) remove any partial object that might
  --    exist. Skip rows on moderation hold.
  return query
  with pending_target as (
    select m.id, m.storage_path
    from public.media_assets m
    where m.status = 'pending_upload'
      and m.created_at <= pending_cutoff
      and m.storage_deleted_at is null
      and m.moderation_hold_at is null
    limit batch_limit
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

  -- 2. Active rows past their TTL (the 7-day expires_at). Same pattern:
  --    delete bytes, stamp storage_deleted_at, flip status. Skip held.
  return query
  with expired_target as (
    select m.id, m.storage_path
    from public.media_assets m
    where m.status = 'active'
      and m.expires_at is not null
      and m.expires_at <= now()
      and m.storage_deleted_at is null
      and m.moderation_hold_at is null
    limit batch_limit
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

  -- 3. Any row whose 24-hour retention has elapsed. This is the new
  --    primary cleanup path for opened-and-closed view-once media.
  --    Status stays 'viewed' (or whatever it was) — we only stamp the
  --    storage_deleted_at column so the bubble keeps showing its
  --    correct user-facing state.
  return query
  with retention_target as (
    select m.id, m.storage_path
    from public.media_assets m
    where m.retention_until is not null
      and m.retention_until <= now()
      and m.storage_deleted_at is null
      and m.moderation_hold_at is null
    limit batch_limit
  ),
  removed_retention as (
    delete from storage.objects o
    using retention_target t
    where o.bucket_id = 'chat-media-private'
      and o.name = t.storage_path
    returning o.name
  ),
  stamped_retention as (
    update public.media_assets m
    set storage_deleted_at = now()
    from retention_target t
    where m.id = t.id
    returning m.id
  )
  select sr.id, 'retention_elapsed'::text from stamped_retention sr;
end;
$$;

revoke all on function public.cleanup_expired_media from public;
grant execute on function public.cleanup_expired_media to service_role;

-- 5. Leave-chat purge: respect moderation hold ------------------------------
--
-- The leave-chat trigger from migration 0025 wipes media bytes for the
-- room when the room flips to deleted. That's the right default for a
-- one-to-one chat the user wants to walk away from, but it must not
-- override a moderation hold — otherwise filing a report and then
-- leaving the chat would erase the very evidence we just preserved.

create or replace function public.purge_media_on_room_delete()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'deleted' and (old.status is distinct from 'deleted') then
    -- 1. Remove the underlying storage objects, but only for media
    --    rows that are *not* on moderation hold. (Moderation-held
    --    rows must survive a leave-chat to be reviewable.)
    delete from storage.objects o
    using public.media_assets m
    where m.room_id = new.id
      and m.storage_deleted_at is null
      and m.moderation_hold_at is null
      and o.bucket_id = 'chat-media-private'
      and o.name      = m.storage_path;

    -- 2. Stamp those rows so the row state matches the bucket state.
    update public.media_assets
    set status = 'deleted',
        storage_deleted_at = now()
    where room_id = new.id
      and storage_deleted_at is null
      and moderation_hold_at is null;
  end if;
  return new;
end;
$$;

-- 6. Reviewer access audit log ----------------------------------------------
--
-- No reviewer UI yet. This table exists so any future SECURITY DEFINER
-- function that mints a signed URL for a held media asset has somewhere
-- to write an audit row. RLS is enabled and intentionally empty — only
-- the service role bypasses RLS, which is what reviewer tooling will
-- run as.

create table if not exists public.moderation_access_logs (
  id          uuid primary key default gen_random_uuid(),
  reviewer_id uuid not null references public.profiles(id) on delete restrict,
  media_id    uuid references public.media_assets(id) on delete set null,
  report_id   uuid references public.reports(id)      on delete set null,
  action      text not null,
  created_at  timestamptz not null default now()
);

alter table public.moderation_access_logs enable row level security;

create index if not exists moderation_access_logs_reviewer_idx
  on public.moderation_access_logs (reviewer_id, created_at desc);
create index if not exists moderation_access_logs_media_idx
  on public.moderation_access_logs (media_id, created_at desc);
create index if not exists moderation_access_logs_report_idx
  on public.moderation_access_logs (report_id, created_at desc);
