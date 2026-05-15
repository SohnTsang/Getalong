-- 0029_purge_trigger_no_storage_sql.sql
--
-- Supabase recently added a `storage.protect_delete()` BEFORE-DELETE
-- trigger on `storage.objects` that raises SQLSTATE 42501:
--
--   ERROR:  Direct deletion from storage tables is not allowed.
--   HINT:   Use the Storage API instead.
--
-- That broke our `purge_media_on_room_delete` trigger from migration
-- 0025 (refined in 0026): every "leave conversation" UPDATE on
-- `chat_rooms` cascaded into the trigger's
--   `DELETE FROM storage.objects o USING public.media_assets m WHERE …`
-- and was rejected by `storage.protect_delete()`. The Edge Function
-- caught the resulting Postgres error, returned `DELETE_FAILED`, and
-- the user saw "can't leave chat" with no other visible response.
--
-- Fix: drop the SQL DELETE on storage.objects from the trigger. The
-- trigger still does the row-level state work — mark the media rows
-- as `status='deleted'` and stamp `retention_until = now()` so the
-- bytes become immediately eligible under the existing Storage-API
-- cleanup path (the `deleteExpiredMedia` Edge Function — which uses
-- `sb.storage.from(MEDIA_BUCKET).remove([...])`, the proper Storage
-- API, and is not blocked by `protect_delete`).
--
-- Net behaviour:
--   * Leaving a chat works again.
--   * Media row state ("this conversation is gone for me") flips
--     synchronously.
--   * Storage object bytes are reclaimed asynchronously by the HTTP
--     cleanup path, not from SQL.
--   * Moderation-held rows are still untouched.
--
-- pg_cron is not enabled on this project, so `cleanup_expired_media`
-- from migration 0024 is dormant and isn't part of this bug. Its
-- definition still contains the same SQL DELETE pattern; leaving it
-- alone here scoped to the actual leave-chat failure. If pg_cron is
-- ever enabled, that function needs the same treatment in a separate
-- migration.

create or replace function public.purge_media_on_room_delete()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'deleted' and (old.status is distinct from 'deleted') then
    -- Row-level state only. Deliberately no `DELETE FROM
    -- storage.objects` here — Supabase's storage.protect_delete()
    -- blocks SQL-level deletes against that table. Setting
    -- `retention_until = now()` puts these rows into the immediate
    -- catchment of the deleteExpiredMedia HTTP function's retention
    -- sweep, which calls the Storage API to remove bytes safely.
    update public.media_assets
    set status          = 'deleted',
        retention_until = now()
    where room_id = new.id
      and storage_deleted_at is null
      and moderation_hold_at is null;
  end if;
  return new;
end;
$$;
