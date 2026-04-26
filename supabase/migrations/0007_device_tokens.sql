-- Getalong: device_tokens for APNs push notifications.
-- Each row is one APNs device token belonging to one user. Edge Functions
-- (with the service role) write to this table when sending pushes; the
-- iOS client may also insert/update its own row via the registerDeviceToken
-- Edge Function. RLS keeps tokens scoped per-user.

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null default 'ios'
    check (platform in ('ios', 'android')),
  environment text not null default 'sandbox'
    check (environment in ('sandbox', 'production')),
  device_id text,
  app_version text,
  locale text,
  timezone text,
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, token)
);

create index if not exists device_tokens_user_active_idx
  on public.device_tokens (user_id, is_active);

create index if not exists device_tokens_token_idx
  on public.device_tokens (token);

alter table public.device_tokens enable row level security;

-- Read your own tokens (so the app can confirm registration if it wants).
drop policy if exists "device_tokens: read own" on public.device_tokens;
create policy "device_tokens: read own"
  on public.device_tokens for select
  using (auth.uid() = user_id);

-- Insert/update/delete your own tokens. Edge Functions with the service
-- role bypass RLS for cross-user reads (e.g. when sending a push to the
-- recipient).
drop policy if exists "device_tokens: insert own" on public.device_tokens;
create policy "device_tokens: insert own"
  on public.device_tokens for insert
  with check (auth.uid() = user_id);

drop policy if exists "device_tokens: update own" on public.device_tokens;
create policy "device_tokens: update own"
  on public.device_tokens for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "device_tokens: delete own" on public.device_tokens;
create policy "device_tokens: delete own"
  on public.device_tokens for delete
  using (auth.uid() = user_id);
