-- 1) Cap profile_tags at 3 per profile (was 10).
create or replace function public._ga_check_profile_tag_limit()
returns trigger language plpgsql as $$
declare v_count int;
begin
  select count(*) into v_count
    from public.profile_tags where profile_id = NEW.profile_id;
  if v_count >= 3 then
    raise exception 'TAG_LIMIT_REACHED' using errcode = 'P0001';
  end if;
  return NEW;
end
$$;

-- 2) Tag-history trigger function must run as definer so the insert
-- bypasses the (intentionally) policy-less profile_tag_history table.
-- Without this, every profile_tags insert fails with a "row violates
-- row-level security policy" error from the AFTER INSERT trigger.
create or replace function public.tg_record_profile_tag_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profile_tag_history (profile_id, tag, normalized_tag)
  values (new.profile_id, new.tag, new.normalized_tag);
  return new;
end;
$$;

-- Re-bind trigger so it picks up the new function definition.
drop trigger if exists profile_tags_record_history on public.profile_tags;
create trigger profile_tags_record_history
  after insert on public.profile_tags
  for each row execute function public.tg_record_profile_tag_history();
