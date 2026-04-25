-- Add an "interested in" preference for discovery filtering.
-- Optional. Values: 'male' | 'female' | 'everyone'.

alter table public.profiles
  add column if not exists interested_in_gender text
    check (interested_in_gender in ('male', 'female', 'everyone'));
