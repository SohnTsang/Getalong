-- Replace the pre-seeded "topics" taxonomy with user-created profile tags.
--
-- Product direction: Getalong does not force users into a fixed topic
-- taxonomy. Tags are optional profile signals, user-typed, editable
-- from the Profile page only. The 0003_topics_seed.sql migration is
-- left in place (idempotent), but the tables it depended on are dropped
-- below; Postgres handles ordering via `if exists … cascade`.

-- ---------------------------------------------------------------
-- 1. Drop the old taxonomy.
-- ---------------------------------------------------------------

drop table if exists public.profile_topics cascade;
drop table if exists public.post_topics    cascade;
drop table if exists public.topics         cascade;

-- ---------------------------------------------------------------
-- 2. Create profile_tags.
-- ---------------------------------------------------------------

create table if not exists public.profile_tags (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  tag             text not null,
  normalized_tag  text not null,
  created_at      timestamptz not null default now(),
  unique (profile_id, normalized_tag),
  check (char_length(tag)            between 1 and 30),
  check (char_length(normalized_tag) between 1 and 30)
);

create index if not exists profile_tags_profile_id_idx
  on public.profile_tags(profile_id);

create index if not exists profile_tags_normalized_tag_idx
  on public.profile_tags(normalized_tag);

-- ---------------------------------------------------------------
-- 3. RLS.
-- ---------------------------------------------------------------

alter table public.profile_tags enable row level security;

-- Read: anyone authenticated can read tags belonging to a non-deleted,
-- non-banned profile (so tags surface in Discovery once it ships).
create policy "profile_tags: read visible profiles"
  on public.profile_tags for select
  using (
    exists (
      select 1 from public.profiles p
      where p.id = profile_id
        and p.deleted_at is null
        and p.is_banned = false
    )
  );

-- Read: own tags always (bypasses the visibility check above).
create policy "profile_tags: read own"
  on public.profile_tags for select
  using (auth.uid() = profile_id);

-- Insert: only into your own profile.
create policy "profile_tags: insert own"
  on public.profile_tags for insert
  with check (auth.uid() = profile_id);

-- Update: only your own tags.
create policy "profile_tags: update own"
  on public.profile_tags for update
  using (auth.uid() = profile_id)
  with check (auth.uid() = profile_id);

-- Delete: only your own tags.
create policy "profile_tags: delete own"
  on public.profile_tags for delete
  using (auth.uid() = profile_id);

-- ---------------------------------------------------------------
-- 4. (Optional) cap of 10 tags per profile, enforced server-side.
-- ---------------------------------------------------------------
create or replace function public._ga_check_profile_tag_limit()
returns trigger language plpgsql as $$
declare v_count int;
begin
  select count(*) into v_count
    from public.profile_tags where profile_id = NEW.profile_id;
  if v_count >= 10 then
    raise exception 'TAG_LIMIT_REACHED' using errcode = 'P0001';
  end if;
  return NEW;
end
$$;

drop trigger if exists profile_tags_limit on public.profile_tags;
create trigger profile_tags_limit
  before insert on public.profile_tags
  for each row execute function public._ga_check_profile_tag_limit();
