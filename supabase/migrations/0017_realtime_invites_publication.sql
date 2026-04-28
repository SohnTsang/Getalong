-- 0017_realtime_invites_publication.sql
--
-- Supabase Realtime fires postgres-changes events only for tables in
-- the `supabase_realtime` publication. Ours was never added, so the
-- iOS app's MissedInvitesTracker / InvitesViewModel listeners never
-- received insert/update events — the navbar accent tint and the
-- in-tab live-invite list only updated on poll/foreground/tab-switch.
--
-- This migration:
--   1. Adds `public.invites` to the `supabase_realtime` publication.
--   2. Sets REPLICA IDENTITY FULL so UPDATE rows include the previous
--      values, which the SDK uses for filter matching on receiver_id /
--      sender_id when the column hasn't changed (the default DEFAULT
--      identity only includes primary keys for unchanged rows).
--
-- Idempotent: ALTER PUBLICATION ADD TABLE errors if already present,
-- so we wrap in a DO block that swallows duplicate_object.

do $$
begin
  alter publication supabase_realtime add table public.invites;
exception when duplicate_object then
  -- Already in the publication; safe to ignore.
  null;
end $$;

alter table public.invites replica identity full;
