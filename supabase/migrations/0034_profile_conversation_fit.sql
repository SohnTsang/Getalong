-- 0034_profile_conversation_fit.sql
--
-- Taipei beta product adjustment: profile model = one honest line +
-- three lightweight fit chips. The three chips give discovery enough
-- context to disambiguate "what kind of chat is this" without the
-- profile becoming a dating-app condition table, and without forcing
-- the user to write multiple paragraphs.
--
-- Columns are all nullable so existing users are NEVER blocked or
-- forced through a broken re-onboarding. CHECK constraints guard the
-- allowed value sets; nulls bypass the CHECK (Postgres semantics), so
-- legacy rows remain valid.
--
-- The fourth column (`opener_prompt`) is a free-text hint the partner
-- can use as a conversation seed. Length-capped at 120 — opener UI is
-- intentionally tight; longer prose belongs in `bio`.
--
-- Discovery treats these as SOFT context only: they may shift sort
-- order, they NEVER filter rows out. See `getDiscoveryFeed`.

alter table public.profiles
  add column if not exists connection_intent     text,
  add column if not exists lifestyle_rhythm      text,
  add column if not exists conversation_domain   text,
  add column if not exists opener_prompt         text;

-- Drop-then-add the CHECKs so re-applying the migration after a value
-- set change is straightforward. `if exists` keeps it idempotent.
alter table public.profiles
  drop constraint if exists profiles_connection_intent_check;
alter table public.profiles
  add  constraint        profiles_connection_intent_check
       check (connection_intent is null or connection_intent in (
         'slow_chat', 'new_friends', 'dating_open', 'not_sure'
       ));

alter table public.profiles
  drop constraint if exists profiles_lifestyle_rhythm_check;
alter table public.profiles
  add  constraint        profiles_lifestyle_rhythm_check
       check (lifestyle_rhythm is null or lifestyle_rhythm in (
         'early_bird', 'night_owl', 'weekend_person', 'flexible'
       ));

alter table public.profiles
  drop constraint if exists profiles_conversation_domain_check;
alter table public.profiles
  add  constraint        profiles_conversation_domain_check
       check (conversation_domain is null or conversation_domain in (
         'daily_life', 'food_cafes', 'city_walks', 'music_films',
         'work_study', 'travel', 'values', 'random'
       ));

alter table public.profiles
  drop constraint if exists profiles_opener_prompt_length_check;
alter table public.profiles
  add  constraint        profiles_opener_prompt_length_check
       check (opener_prompt is null or char_length(opener_prompt) <= 120);

-- No new grants needed — `profiles` is from migration 0001 and keeps
-- the original auto-grant behaviour (Supabase's 2026-10-30 grant
-- change only affects newly created `public` tables, per CLAUDE.md).

-- profiles_lock_sensitive_columns (mig 0011) intentionally does NOT
-- protect the new columns: users update them via ProfilePatch.
