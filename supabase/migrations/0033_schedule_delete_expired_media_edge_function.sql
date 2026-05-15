-- 0033_schedule_delete_expired_media_edge_function.sql
--
-- Authoritative recurring schedule for storage-byte cleanup of expired
-- view-once media. Until this migration the byte-deletion path
-- (`supabase/functions/deleteExpiredMedia`) had no automatic runner —
-- migration 0031 deliberately removed the SQL-side DELETE against
-- `storage.objects` because Supabase now blocks raw SQL deletes there
-- (see migrations 0029/0030), but the replacement schedule (cron →
-- HTTP → Edge Function) was never wired up. This migration closes
-- that gap.
--
-- Architecture (do NOT regress):
--   * `cleanup_expired_media()` (SQL) is metadata-only. It marks rows
--     `expired` and emits `retention_elapsed` ids for observability;
--     it never deletes bytes.
--   * `deleteExpiredMedia` (Edge Function) is the SOLE storage-byte
--     deletion path. It uses the Storage API (`sb.storage.remove`),
--     not raw SQL.
--   * pg_cron + pg_net post to that function every 2 minutes.
--   * Auth: a dedicated scheduler secret (`x-cleanup-secret` header).
--     The function ALSO still accepts a service-role Bearer for
--     ad-hoc / CI invocation. The scheduler does not use the
--     service-role key — least privilege.
--   * Moderation-held rows (`moderation_hold_at is not null`) are
--     skipped indefinitely; only the manual review path clears them.
--
-- Required Supabase Vault secrets (create manually before this
-- migration is applied — see "Manual setup" below):
--
--   `getalong_project_url`
--     The Supabase project URL, e.g.
--     `https://<project-ref>.supabase.co`. No trailing slash.
--
--   `getalong_delete_expired_media_scheduler_secret`
--     The same value placed in the `CLEANUP_SCHEDULER_SECRET` Edge
--     Function env var. Generate with `openssl rand -hex 32`.
--
-- Manual setup (one-time, in the Supabase SQL editor as the project
-- owner — Vault writes require elevated permissions and cannot
-- safely happen inside a migration):
--
--   select vault.create_secret(
--     'https://<project-ref>.supabase.co',
--     'getalong_project_url',
--     'Project URL used by the deleteExpiredMedia cron scheduler.'
--   );
--   select vault.create_secret(
--     '<output of openssl rand -hex 32>',
--     'getalong_delete_expired_media_scheduler_secret',
--     'Shared secret between pg_cron and the deleteExpiredMedia Edge Function.'
--   );
--
-- Then set the same secret as an Edge Function env var:
--   supabase secrets set CLEANUP_SCHEDULER_SECRET=<same value>
--
-- If the Vault secrets do not exist at job-fire time, `net.http_post`
-- raises before any request is sent — the cron job logs the error in
-- `cron.job_run_details` and no insecure request goes out.

-- 1. Extensions. Use the Supabase-managed schemas (`extensions`) for
--    pg_net; pg_cron lives in its own `cron` schema by default. Both
--    creates are idempotent.
create extension if not exists pg_net   with schema extensions;
create extension if not exists pg_cron;

-- 2. Schedule the cron job. Wrapped so the migration is safe in
--    environments where pg_cron isn't actually installable (local
--    dev, ephemeral CI), and so re-applying doesn't error.
do $$
declare
  job_name constant text := 'getalong_delete_expired_media_every_2_minutes';
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed; skipping schedule registration.';
    return;
  end if;

  -- Drop any prior job with the same name so re-applying / renaming
  -- doesn't duplicate the schedule.
  if exists (select 1 from cron.job where jobname = job_name) then
    perform cron.unschedule(job_name);
  end if;

  perform cron.schedule(
    job_name,
    '*/2 * * * *',
    $cron$
      select
        net.http_post(
          url     := (
            select decrypted_secret
              from vault.decrypted_secrets
             where name = 'getalong_project_url'
          ) || '/functions/v1/deleteExpiredMedia',
          headers := jsonb_build_object(
            'Content-Type',     'application/json',
            'x-cleanup-secret', (
              select decrypted_secret
                from vault.decrypted_secrets
               where name = 'getalong_delete_expired_media_scheduler_secret'
            )
          ),
          body    := jsonb_build_object('source', 'cron'),
          timeout_milliseconds := 20000
        );
    $cron$
  );
exception when others then
  raise notice 'deleteExpiredMedia cron registration failed: %', sqlerrm;
end
$$;
