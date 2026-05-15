-- 0031_cleanup_expired_media_sql_safety.sql
--
-- Rewrites `cleanup_expired_media()` to remove every direct SQL
-- DELETE against `storage.objects`. The function is dormant today
-- (pg_cron isn't installed on this project, so the */2 cron entry
-- from migration 0024 was a no-op `do` block), but the same pattern
-- that broke leave-chat (mig 0029 / 0030 — Supabase platform now
-- has `storage.protect_delete()` blocking SQL-level DELETEs against
-- `storage.objects`) is sitting in this function ready to silently
-- error every 2 minutes the moment pg_cron is enabled. Remove the
-- landmine now.
--
-- Authoritative architecture from this migration onward:
--
--   * SQL identifies and marks cleanup candidates.
--   * The `deleteExpiredMedia` Edge Function is the ONLY path that
--     removes storage bytes. It uses the Storage API
--     (`sb.storage.from(bucket).remove([...])`), which is the
--     platform's sanctioned path and is not blocked by
--     `protect_delete`.
--
-- Behavioural contract preserved:
--
--   * 24-hour view-once retention — Edge Function's retention sweep
--     queries `retention_until <= now() and storage_deleted_at is null
--     and moderation_hold_at is null` directly; this function still
--     emits the same rows for observability so an operator running
--     it manually can see what's queued.
--   * Moderation-held media is never touched (preserved across every
--     branch via the `moderation_hold_at is null` predicate).
--   * Reported-media retention beyond 24h — unchanged (the hold flag
--     gates eligibility identically).
--   * pending_upload expiry — still flipped to `status = 'expired'`
--     after 30 minutes so callers stop showing those rows as
--     in-flight uploads. The byte cleanup itself moves to the Edge
--     Function (which already has retention_until elapsed in its
--     sweep predicate; the row's retention_until was stamped at
--     upload request time per migration 0026's requestMediaUpload
--     contract).
--   * `storage_deleted_at` semantics — still only stamped by the
--     Edge Function after the actual storage remove() succeeds.
--     This function deliberately stops stamping it, because a stamp
--     without an actual delete would lie about byte state.
--
-- pg_cron is currently inactive on this project. The cron entry from
-- migration 0024 is conditionally registered inside a `do` block that
-- checks `pg_extension`, so this migration doesn't need to alter the
-- schedule. If pg_cron is enabled later, the new function body is
-- safe to run every 2 minutes — it does only metadata updates and
-- a status return, never touches storage.objects.
--
-- Long-term, the proper cleanup executor is the `deleteExpiredMedia`
-- Edge Function. Future scheduling should invoke it directly (e.g.
-- via pg_net + pg_cron POSTing to the function URL, or via an
-- external scheduler) rather than relying on SQL byte deletion.

create or replace function public.cleanup_expired_media()
returns table (
  id uuid,
  reason text
) language plpgsql security definer as $$
declare
  pending_cutoff timestamptz := now() - interval '30 minutes';
  batch_limit    int := 500;
begin
  -- 1. Pending uploads that never resolved → flip to 'expired'. The
  --    bytes (if any partial uploaded) are removed by the Edge
  --    Function's retention sweep, not from here. Skip moderation-held.
  return query
  with pending_target as (
    select m.id
    from public.media_assets m
    where m.status = 'pending_upload'
      and m.created_at <= pending_cutoff
      and m.storage_deleted_at is null
      and m.moderation_hold_at is null
    limit batch_limit
  ),
  stamped_pending as (
    update public.media_assets m
    set status = 'expired'
    from pending_target t
    where m.id = t.id
    returning m.id
  )
  select sp.id, 'pending_timeout'::text from stamped_pending sp;

  -- 2. Active rows past their 7-day TTL → flip to 'expired'. Same
  --    deal: byte removal happens via the Edge Function. Skip held.
  return query
  with expired_target as (
    select m.id
    from public.media_assets m
    where m.status = 'active'
      and m.expires_at is not null
      and m.expires_at <= now()
      and m.storage_deleted_at is null
      and m.moderation_hold_at is null
    limit batch_limit
  ),
  stamped_expired as (
    update public.media_assets m
    set status = 'expired'
    from expired_target t
    where m.id = t.id
    returning m.id
  )
  select se.id, 'ttl_expired'::text from stamped_expired se;

  -- 3. Rows whose 24-hour retention has elapsed but still have bytes.
  --    No row-state change is required here — `status` already
  --    reflects what the user sees ('viewed' / 'active' / 'expired')
  --    and `storage_deleted_at` must stay NULL until the Edge
  --    Function actually removes the bytes. We emit the ids purely
  --    for observability so an operator running this manually can
  --    see what's queued for byte removal.
  return query
    select m.id, 'retention_elapsed'::text
      from public.media_assets m
     where m.retention_until is not null
       and m.retention_until <= now()
       and m.storage_deleted_at is null
       and m.moderation_hold_at is null
     limit batch_limit;
end;
$$;

-- Permissions unchanged from migration 0024; re-grant for safety.
revoke all on function public.cleanup_expired_media from public;
grant execute on function public.cleanup_expired_media to service_role;
