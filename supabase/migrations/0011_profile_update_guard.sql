-- Getalong: column-level guard on profile self-updates.
--
-- The "profiles: update own row" RLS policy lets a user update their own
-- row, but it does not constrain which columns they may change. A
-- malicious client could otherwise flip plan, is_banned, trust_score,
-- deleted_at, or created_at on their own profile.
--
-- This trigger silently reverts those fields to their OLD values when the
-- update is coming from a regular authenticated user (auth.uid() matches
-- the row owner). Service-role updates (Edge Functions, admin tools) run
-- with auth.uid() = NULL and pass through unchanged.

create or replace function public.tg_lock_sensitive_profile_columns()
returns trigger
language plpgsql
security definer
as $$
declare
  v_caller uuid := auth.uid();
begin
  -- Service role / SQL editor: pass through.
  if v_caller is null then
    return new;
  end if;

  -- Only enforce when the caller is the row's owner (matches the
  -- existing "profiles: update own row" RLS policy). For other paths the
  -- RLS denial fires before this trigger.
  if v_caller <> new.id then
    return new;
  end if;

  -- Lock sensitive columns to OLD values. Silent revert keeps onboarding
  -- and edit sheets working without surfacing a database error to the
  -- client.
  new.plan         := old.plan;
  new.is_banned    := old.is_banned;
  new.trust_score  := old.trust_score;
  new.deleted_at   := old.deleted_at;
  new.created_at   := old.created_at;
  -- id and getalong_id are also locked: id is the primary key (cannot
  -- change), and getalong_id is treated as immutable for v0 — it's the
  -- handle the rest of the system uses.
  new.id           := old.id;
  new.getalong_id  := old.getalong_id;

  return new;
end;
$$;

drop trigger if exists profiles_lock_sensitive_columns on public.profiles;
create trigger profiles_lock_sensitive_columns
  before update on public.profiles
  for each row execute function public.tg_lock_sensitive_profile_columns();
