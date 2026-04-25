-- Getalong initial schema migration
-- Source of truth: docs/DATABASE_SCHEMA.md
-- Notes:
--   * RLS is enabled on every table.
--   * Starter policies are intentionally conservative. Sensitive writes
--     (invites, locks, missed-accept usage, chat rooms, media) must go
--     through Edge Functions using the service role.

create extension if not exists "pgcrypto";

-- =========================================================================
-- Tables
-- =========================================================================

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  getalong_id text unique not null,
  display_name text not null,
  bio text,
  gender text,
  gender_visible boolean not null default false,
  birth_year int,
  city text,
  country text,
  language_codes text[] not null default '{}',
  trust_score int not null default 0,
  plan text not null default 'free' check (plan in ('free', 'silver', 'gold')),
  is_banned boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.topics (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  name_en text not null,
  name_ja text,
  name_zh text,
  created_at timestamptz not null default now()
);

create table if not exists public.profile_topics (
  profile_id uuid references public.profiles(id) on delete cascade,
  topic_id uuid references public.topics(id) on delete cascade,
  primary key (profile_id, topic_id)
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) <= 500),
  mood text,
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  city text,
  country text,
  is_hidden boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.post_topics (
  post_id uuid references public.posts(id) on delete cascade,
  topic_id uuid references public.topics(id) on delete cascade,
  primary key (post_id, topic_id)
);

create table if not exists public.invites (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  post_id uuid references public.posts(id) on delete set null,

  message text check (char_length(message) <= 300),

  invite_type text not null default 'normal'
    check (invite_type in ('normal', 'super')),

  delivery_mode text not null default 'live'
    check (delivery_mode in ('live', 'missed')),

  status text not null default 'live_pending'
    check (status in (
      'live_pending',
      'live_accepted',
      'missed',
      'missed_accepted',
      'declined',
      'cancelled',
      'expired'
    )),

  live_expires_at timestamptz not null,
  missed_expires_at timestamptz,

  accepted_at timestamptz,
  created_at timestamptz not null default now(),

  constraint no_self_invite check (sender_id <> receiver_id)
);

create table if not exists public.active_invite_locks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  invite_id uuid not null references public.invites(id) on delete cascade,
  locked_until timestamptz not null,
  created_at timestamptz not null default now()
);

create table if not exists public.missed_invite_accept_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  usage_date date not null,
  accepts_used int not null default 0,
  primary key (user_id, usage_date)
);

create table if not exists public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  invite_id uuid unique references public.invites(id) on delete set null,
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'archived', 'blocked')),
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  constraint no_self_chat check (user_a <> user_b)
);

create table if not exists public.media_assets (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  storage_path text not null,
  mime_type text not null,
  size_bytes bigint not null,
  duration_seconds int,
  view_once boolean not null default false,
  viewed_by uuid references public.profiles(id) on delete set null,
  viewed_at timestamptz,
  status text not null default 'active' check (status in ('active', 'viewed', 'expired', 'deleted')),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message_type text not null check (message_type in ('text', 'image', 'gif', 'video', 'system')),
  body text,
  media_id uuid references public.media_assets(id) on delete set null,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('profile', 'post', 'message', 'media')),
  target_id uuid not null,
  reason text not null,
  details text,
  status text not null default 'open' check (status in ('open', 'reviewing', 'resolved', 'dismissed')),
  created_at timestamptz not null default now()
);

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null,
  plan text not null check (plan in ('free', 'silver', 'gold')),
  status text not null,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.daily_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  usage_date date not null,
  one_time_media_sent int not null default 0,
  abuse_limited_actions int not null default 0,
  primary key (user_id, usage_date)
);

-- =========================================================================
-- Indexes
-- =========================================================================

create index if not exists posts_created_at_idx on public.posts (created_at desc);
create index if not exists posts_author_id_idx  on public.posts (author_id);

create index if not exists invites_receiver_status_idx on public.invites (receiver_id, status, created_at desc);
create index if not exists invites_sender_status_idx   on public.invites (sender_id, status, created_at desc);
create index if not exists invites_live_expiry_idx     on public.invites (status, live_expires_at);
create index if not exists invites_missed_expiry_idx   on public.invites (status, missed_expires_at);

create index if not exists active_invite_locks_user_idx   on public.active_invite_locks (user_id, locked_until);
create index if not exists active_invite_locks_invite_idx on public.active_invite_locks (invite_id);

create index if not exists chat_rooms_user_a_idx on public.chat_rooms (user_a);
create index if not exists chat_rooms_user_b_idx on public.chat_rooms (user_b);

create index if not exists messages_room_created_idx on public.messages (room_id, created_at desc);
create index if not exists media_assets_room_idx    on public.media_assets (room_id);
create index if not exists reports_target_idx       on public.reports (target_type, target_id);

-- =========================================================================
-- RLS
-- =========================================================================

alter table public.profiles                     enable row level security;
alter table public.topics                       enable row level security;
alter table public.profile_topics               enable row level security;
alter table public.posts                        enable row level security;
alter table public.post_topics                  enable row level security;
alter table public.invites                      enable row level security;
alter table public.active_invite_locks          enable row level security;
alter table public.missed_invite_accept_usage   enable row level security;
alter table public.chat_rooms                   enable row level security;
alter table public.messages                     enable row level security;
alter table public.media_assets                 enable row level security;
alter table public.blocks                       enable row level security;
alter table public.reports                      enable row level security;
alter table public.subscriptions                enable row level security;
alter table public.daily_usage                  enable row level security;

-- =========================================================================
-- Starter Policies
-- =========================================================================
-- Principles:
--   * Users can read their own row, and only public fields of others where
--     a feature requires it (handled at the SELECT level for now).
--   * Sensitive writes (invites, locks, missed-accept usage, chat rooms,
--     messages, media_assets) are NOT writable by clients. They are written
--     by Edge Functions using the service role, which bypasses RLS.
--   * Anything not covered by an explicit policy below is denied by default.

-- profiles ---------------------------------------------------------------
create policy "profiles: read non-deleted, non-banned"
  on public.profiles for select
  using (deleted_at is null and is_banned = false);

create policy "profiles: read own row always"
  on public.profiles for select
  using (auth.uid() = id);

create policy "profiles: insert own row"
  on public.profiles for insert
  with check (auth.uid() = id);

create policy "profiles: update own row"
  on public.profiles for update
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- topics (read-only catalogue) -------------------------------------------
create policy "topics: read all"
  on public.topics for select
  using (true);

-- profile_topics ---------------------------------------------------------
create policy "profile_topics: read self"
  on public.profile_topics for select
  using (auth.uid() = profile_id);

create policy "profile_topics: read others (public)"
  on public.profile_topics for select
  using (
    exists (
      select 1 from public.profiles p
      where p.id = profile_id
        and p.deleted_at is null
        and p.is_banned = false
    )
  );

create policy "profile_topics: insert own"
  on public.profile_topics for insert
  with check (auth.uid() = profile_id);

create policy "profile_topics: delete own"
  on public.profile_topics for delete
  using (auth.uid() = profile_id);

-- posts ------------------------------------------------------------------
create policy "posts: read public visible"
  on public.posts for select
  using (
    is_hidden = false
    and deleted_at is null
    and visibility = 'public'
  );

create policy "posts: read own"
  on public.posts for select
  using (auth.uid() = author_id);

create policy "posts: insert own"
  on public.posts for insert
  with check (auth.uid() = author_id);

create policy "posts: update own"
  on public.posts for update
  using (auth.uid() = author_id)
  with check (auth.uid() = author_id);

create policy "posts: soft-delete own"
  on public.posts for delete
  using (auth.uid() = author_id);

-- post_topics ------------------------------------------------------------
create policy "post_topics: read with parent post visibility"
  on public.post_topics for select
  using (
    exists (
      select 1 from public.posts p
      where p.id = post_id
        and p.is_hidden = false
        and p.deleted_at is null
        and (p.visibility = 'public' or p.author_id = auth.uid())
    )
  );

create policy "post_topics: insert if owns post"
  on public.post_topics for insert
  with check (
    exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
  );

create policy "post_topics: delete if owns post"
  on public.post_topics for delete
  using (
    exists (select 1 from public.posts p where p.id = post_id and p.author_id = auth.uid())
  );

-- invites ----------------------------------------------------------------
-- Reads: sender or receiver. Writes: Edge Functions only (service role).
create policy "invites: read involved"
  on public.invites for select
  using (auth.uid() = sender_id or auth.uid() = receiver_id);

-- active_invite_locks ----------------------------------------------------
-- Read your own locks for UI; writes via service role only.
create policy "active_invite_locks: read own"
  on public.active_invite_locks for select
  using (auth.uid() = user_id);

-- missed_invite_accept_usage --------------------------------------------
create policy "missed_invite_accept_usage: read own"
  on public.missed_invite_accept_usage for select
  using (auth.uid() = user_id);

-- chat_rooms -------------------------------------------------------------
create policy "chat_rooms: read participants"
  on public.chat_rooms for select
  using (auth.uid() = user_a or auth.uid() = user_b);

-- messages ---------------------------------------------------------------
create policy "messages: read participants"
  on public.messages for select
  using (
    exists (
      select 1 from public.chat_rooms r
      where r.id = room_id
        and (r.user_a = auth.uid() or r.user_b = auth.uid())
    )
  );

-- media_assets -----------------------------------------------------------
-- Read metadata for own rooms; actual file access is via signed URLs from
-- Edge Functions only. View-once enforcement happens server-side.
create policy "media_assets: read participants"
  on public.media_assets for select
  using (
    exists (
      select 1 from public.chat_rooms r
      where r.id = room_id
        and (r.user_a = auth.uid() or r.user_b = auth.uid())
    )
  );

-- blocks -----------------------------------------------------------------
create policy "blocks: read own"
  on public.blocks for select
  using (auth.uid() = blocker_id);

create policy "blocks: insert own"
  on public.blocks for insert
  with check (auth.uid() = blocker_id);

create policy "blocks: delete own"
  on public.blocks for delete
  using (auth.uid() = blocker_id);

-- reports ----------------------------------------------------------------
create policy "reports: read own"
  on public.reports for select
  using (auth.uid() = reporter_id);

create policy "reports: insert own"
  on public.reports for insert
  with check (auth.uid() = reporter_id);

-- subscriptions ----------------------------------------------------------
create policy "subscriptions: read own"
  on public.subscriptions for select
  using (auth.uid() = user_id);

-- daily_usage ------------------------------------------------------------
create policy "daily_usage: read own"
  on public.daily_usage for select
  using (auth.uid() = user_id);

-- =========================================================================
-- Trigger: keep profiles.updated_at fresh
-- =========================================================================

create or replace function public.tg_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.tg_set_updated_at();

drop trigger if exists subscriptions_set_updated_at on public.subscriptions;
create trigger subscriptions_set_updated_at
  before update on public.subscriptions
  for each row execute function public.tg_set_updated_at();
