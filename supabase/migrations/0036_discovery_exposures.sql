-- 0036_discovery_exposures.sql
--
-- Server-side Discovery exposure history. Until now refresh diversity
-- relied entirely on the client sending `exclude_ids` (the cards iOS is
-- currently showing). That is not production-stable: it resets every
-- session, only knows the current screen, and cannot prevent the same
-- cards reappearing across refreshes or app restarts.
--
-- This table is the authoritative server memory of "who has user X
-- already been shown in Discovery, and how recently / how often". The
-- getDiscoveryFeed Edge Function reads it to SOFT-penalize recently /
-- repeatedly shown profiles and writes one row per returned card.
--
-- Design rules (do NOT regress):
--   * Exposure is a SOFT penalty, never a hard exclusion. A thin
--     candidate pool always fills — exposed users simply sort lower
--     and naturally resurface as their exposure ages out.
--   * Short retention only. Rows older than 14 days are deleted by
--     cleanup_old_discovery_exposures() (scheduled daily below). We do
--     NOT keep exposure history indefinitely.
--   * Service-role only. All reads/writes happen inside the Edge
--     Function via the service role (which bypasses RLS). The iOS
--     client never touches this table directly, so we add NO user
--     policies and grant NO table privileges to `authenticated` —
--     RLS-on with no policy is the most locked-down posture and keeps
--     one user from ever reading another's (or their own) exposure log
--     through PostgREST.

create table if not exists public.discovery_exposures (
  id         uuid primary key default gen_random_uuid(),
  viewer_id  uuid not null references public.profiles(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  shown_at   timestamptz not null default now(),
  source     text not null default 'discovery'
    check (source in ('discovery')),
  constraint discovery_exposures_no_self check (viewer_id <> profile_id)
);

-- Per-(viewer, profile) recency + count lookups (the ranking read).
create index if not exists discovery_exposures_viewer_profile_idx
  on public.discovery_exposures (viewer_id, profile_id, shown_at desc);

-- Per-viewer recent-window scan (load all of a viewer's last-24h rows).
create index if not exists discovery_exposures_viewer_shown_idx
  on public.discovery_exposures (viewer_id, shown_at desc);

-- Retention sweep (delete by age across all viewers).
create index if not exists discovery_exposures_shown_at_idx
  on public.discovery_exposures (shown_at);

alter table public.discovery_exposures enable row level security;

-- No user policies on purpose: only the service role (Edge Function)
-- reads/writes this table, and the service role bypasses RLS. With RLS
-- enabled and no policy, `authenticated`/`anon` get zero access even if
-- they somehow held a table grant.

-- Explicit grants. From 2026-10-30 Supabase no longer auto-grants on
-- newly created public tables, so the service role needs an explicit
-- grant or the Edge Function's PostgREST calls would 42501. We grant
-- ONLY service_role — the client has no direct access by design.
grant all on public.discovery_exposures to service_role;

-- Defense-in-depth. Before 2026-10-30, Supabase's default privileges
-- auto-grant anon/authenticated full table access at CREATE TABLE. RLS
-- (enabled above, no policy) already default-denies them every row, but
-- this is privacy-sensitive who-saw-whom data, so we don't want RLS to
-- be the ONLY gate. Revoke the auto-grants explicitly. (Harmless no-op
-- on post-cutoff projects where the auto-grant never happened.)
revoke all on public.discovery_exposures from anon;
revoke all on public.discovery_exposures from authenticated;

-- =========================================================================
-- Retention cleanup. 14-day window. Deletes in capped batches so a large
-- backlog never produces one giant delete. Returns the number of rows
-- removed for observability (cron logs / ad-hoc runs).
-- =========================================================================
create or replace function public.cleanup_old_discovery_exposures()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cutoff  timestamptz := now() - interval '14 days';
  removed integer;
begin
  delete from public.discovery_exposures
   where shown_at < cutoff;
  get diagnostics removed = row_count;
  return removed;
end;
$$;

revoke all on function public.cleanup_old_discovery_exposures() from public;
grant execute on function public.cleanup_old_discovery_exposures() to service_role;

-- Schedule daily at 03:17 UTC. Pure-SQL cron job (no HTTP / no Vault),
-- so it carries none of the risk of the http_post scheduler. Guarded so
-- the migration is a no-op where pg_cron isn't installed (local dev / CI)
-- and re-applying never duplicates the schedule.
do $$
declare
  job_name constant text := 'getalong_cleanup_old_discovery_exposures_daily';
begin
  if not exists (select 1 from pg_extension where extname = 'pg_cron') then
    raise notice 'pg_cron not installed; skipping discovery-exposure cleanup schedule.';
    return;
  end if;

  if exists (select 1 from cron.job where jobname = job_name) then
    perform cron.unschedule(job_name);
  end if;

  perform cron.schedule(
    job_name,
    '17 3 * * *',
    $cron$ select public.cleanup_old_discovery_exposures(); $cron$
  );
exception when others then
  raise notice 'discovery-exposure cleanup cron registration failed: %', sqlerrm;
end
$$;
