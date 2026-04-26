-- Track every tag a user has ever attached to their profile.
--
-- profile_tags is the *current* set; deleting a tag drops the row, so
-- we lose the history. profile_tag_history is append-only — populated
-- by a trigger on profile_tags INSERT — so the tag editor can show a
-- "Recent" list without needing a soft-delete on the live table.

create table if not exists public.profile_tag_history (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  tag             text not null,
  normalized_tag  text not null,
  added_at        timestamptz not null default now(),
  check (char_length(tag)            between 1 and 30),
  check (char_length(normalized_tag) between 1 and 30)
);

create index if not exists profile_tag_history_recent_idx
  on public.profile_tag_history (profile_id, added_at desc);

create index if not exists profile_tag_history_normalized_idx
  on public.profile_tag_history (profile_id, normalized_tag, added_at desc);

alter table public.profile_tag_history enable row level security;

-- The user can read their own history; nobody else can.
drop policy if exists "tag history: read own" on public.profile_tag_history;
create policy "tag history: read own"
  on public.profile_tag_history for select
  using (auth.uid() = profile_id);

-- Insert is via trigger only; we expose no client write path.
-- (No insert/update/delete policies = denied.)

create or replace function public.tg_record_profile_tag_history()
returns trigger
language plpgsql
as $$
begin
  insert into public.profile_tag_history (profile_id, tag, normalized_tag)
  values (new.profile_id, new.tag, new.normalized_tag);
  return new;
end;
$$;

drop trigger if exists profile_tags_record_history on public.profile_tags;
create trigger profile_tags_record_history
  after insert on public.profile_tags
  for each row execute function public.tg_record_profile_tag_history();
