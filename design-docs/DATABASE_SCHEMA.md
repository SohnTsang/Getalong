# Database Schema

## Required Tables

### profiles

Stores user profile and public identity.

Important fields:
- `id`
- `getalong_id`
- `display_name`
- `bio`
- `gender`
- `gender_visible`
- `city`
- `country`
- `language_codes`
- `trust_score`
- `plan`
- `is_banned`
- `deleted_at`

### profile_tags

User-created tags. Replaces the old `topics` / `profile_topics` /
`post_topics` taxonomy. Tags are optional, edited from the Profile
page only — never required during sign-up.

Important fields:
- `id`
- `profile_id`
- `tag` (display form, 1–30 chars)
- `normalized_tag` (lowercase, whitespace-collapsed; 1–30 chars)
- `created_at`

Constraints:
- `unique (profile_id, normalized_tag)` — no duplicate tags per profile
- length checks on `tag` and `normalized_tag`
- 3-tag-per-profile cap enforced via a `before insert` trigger

### posts

Short text posts used for discovery.

### invites

Tracks live and missed invitations.

Key rules:
- Live invite lasts 15 seconds.
- Accepted live invite creates chat and does not consume missed-invite accept quota.
- Expired live invite becomes missed.
- Missed invite can be accepted later depending on plan/quota.

Statuses:
- `live_pending`
- `live_accepted`
- `missed`
- `missed_accepted`
- `declined`
- `cancelled`
- `expired`

### active_invite_locks

Prevents users from sending more live invites than their plan allows.

Rules:
- Free/Silver: max 1 active outgoing live invite.
- Gold: max 2 active outgoing live invites.

### missed_invite_accept_usage

Tracks free users' missed-invite accept usage.

### chat_rooms

Created only after live or missed invite acceptance.

### messages

Stores chat messages.

Types:
- text
- image
- gif
- video
- system

### media_assets

Stores private media metadata.

Important fields:
- `storage_path`
- `mime_type`
- `view_once`
- `viewed_by`
- `viewed_at`
- `view_finalized_at` — set when receiver closes the viewer
- `status`
- `retention_until` — created_at + 24h for view-once media; cleanup deletes storage only after this elapses
- `storage_deleted_at` — stamped only after the storage object is actually removed
- `moderation_hold_at` / `moderation_hold_reason` / `moderation_hold_report_id` — set by reportContent; cleanup skips held rows
- `moderation_reviewed_at` / `moderation_review_status` — for future Trust & Safety review

### blocks

Tracks blocked user relationships.

### reports

Tracks reports for moderation. Filing a report against a media / message / chat_room / profile-with-context_room_id stamps `moderation_hold_at` on the relevant `media_assets` rows (and on `chat_rooms` for chat-room and user-from-chat reports) so the cleanup cron skips them. Held rows are preserved until manual review.

### moderation_access_logs

Audit table for any future reviewer access to held media. RLS-enabled, no client policy — only the service role can read or insert. Reserved for a future Trust & Safety tool that mints short-lived signed URLs against held media; that tool must write one row per access.

### subscriptions

Stores subscription state.

### daily_usage

Stores non-invite abuse-related daily usage counters.

Do not use this table for the main invite-send mechanic. The main invite mechanic is live invite locks + missed-invite accepts.

## Initial Migration SQL

```sql
create extension if not exists "pgcrypto";

create table public.profiles (
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
  plan text not null default 'free',
  is_banned boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.profile_tags (
  id              uuid primary key default gen_random_uuid(),
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  tag             text not null,
  normalized_tag  text not null,
  created_at      timestamptz not null default now(),
  unique (profile_id, normalized_tag),
  check (char_length(tag)            between 1 and 30),
  check (char_length(normalized_tag) between 1 and 30)
);

-- 3-tag-per-profile cap enforced server-side
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

create trigger profile_tags_limit
  before insert on public.profile_tags
  for each row execute function public._ga_check_profile_tag_limit();

create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) <= 500),
  mood text,
  visibility text not null default 'public',
  city text,
  country text,
  is_hidden boolean not null default false,
  deleted_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.invites (
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

create table public.active_invite_locks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  invite_id uuid not null references public.invites(id) on delete cascade,
  locked_until timestamptz not null,
  created_at timestamptz not null default now()
);

create table public.missed_invite_accept_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  usage_date date not null,
  accepts_used int not null default 0,
  primary key (user_id, usage_date)
);

create table public.chat_rooms (
  id uuid primary key default gen_random_uuid(),
  invite_id uuid unique references public.invites(id) on delete set null,
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  constraint no_self_chat check (user_a <> user_b)
);

create table public.media_assets (
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
  status text not null default 'active',
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.chat_rooms(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message_type text not null check (message_type in ('text', 'image', 'gif', 'video', 'system')),
  body text,
  media_id uuid references public.media_assets(id) on delete set null,
  is_deleted boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  constraint no_self_block check (blocker_id <> blocked_id)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  target_type text not null check (target_type in ('profile', 'post', 'message', 'media')),
  target_id uuid not null,
  reason text not null,
  details text,
  status text not null default 'open',
  created_at timestamptz not null default now()
);

create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider text not null,
  plan text not null check (plan in ('free', 'silver', 'gold')),
  status text not null,
  current_period_end timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.daily_usage (
  user_id uuid not null references public.profiles(id) on delete cascade,
  usage_date date not null,
  one_time_media_sent int not null default 0,
  abuse_limited_actions int not null default 0,
  primary key (user_id, usage_date)
);
```

## Required Indexes

```sql
create index posts_created_at_idx on public.posts (created_at desc);
create index posts_author_id_idx on public.posts (author_id);

create index invites_receiver_status_idx on public.invites (receiver_id, status, created_at desc);
create index invites_sender_status_idx on public.invites (sender_id, status, created_at desc);
create index invites_live_expiry_idx on public.invites (status, live_expires_at);
create index invites_missed_expiry_idx on public.invites (status, missed_expires_at);

create index active_invite_locks_user_idx on public.active_invite_locks (user_id, locked_until);
create index active_invite_locks_invite_idx on public.active_invite_locks (invite_id);

create index chat_rooms_user_a_idx on public.chat_rooms (user_a);
create index chat_rooms_user_b_idx on public.chat_rooms (user_b);

create index messages_room_created_idx on public.messages (room_id, created_at desc);
create index media_assets_room_idx on public.media_assets (room_id);
create index reports_target_idx on public.reports (target_type, target_id);

create index profile_tags_profile_id_idx     on public.profile_tags (profile_id);
create index profile_tags_normalized_tag_idx on public.profile_tags (normalized_tag);
```

## RLS Requirement

Enable RLS on every table.

```sql
alter table public.profiles enable row level security;
alter table public.profile_tags enable row level security;
alter table public.posts enable row level security;
alter table public.invites enable row level security;
alter table public.active_invite_locks enable row level security;
alter table public.missed_invite_accept_usage enable row level security;
alter table public.chat_rooms enable row level security;
alter table public.messages enable row level security;
alter table public.media_assets enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.subscriptions enable row level security;
alter table public.daily_usage enable row level security;
```

## Invite Enforcement Notes

Sensitive invite operations must be handled through Edge Functions:

- `sendLiveInvite`
- `acceptLiveInvite`
- `markLiveInviteMissed`
- `acceptMissedInvite`
- `cancelLiveInvite`

The client must not directly:
- create invite locks
- update invite status
- create chat rooms
- increment missed-invite usage
