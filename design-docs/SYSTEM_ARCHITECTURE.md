# System Architecture

## Overview

Getalong uses a Supabase backend with native mobile clients.

```txt
iOS SwiftUI App
   |
   | Supabase Client + Edge Functions
   v
Supabase
   - Auth
   - Postgres
   - RLS
   - Realtime
   - Storage
   - Edge Functions
   - Cron Jobs
```

Android will later use the same backend contracts.

## Client Architecture

### iOS

Use MVVM with service layer.

```txt
Getalong/
  App/
  Core/
  Models/
  Services/
  Features/
  DesignSystem/
  Utilities/
```

### iOS Principles

- Views are thin.
- ViewModels manage screen state.
- Services call Supabase/Edge Functions.
- Models are typed.
- Sensitive actions go through Edge Functions.
- UI handles loading/empty/error states.

## Backend Architecture

### Supabase Auth

Used for:
- user registration
- sign in
- session
- account identity

### Postgres

Used for:
- profiles
- profile_tags
- posts
- invites
- chat rooms
- messages
- media assets
- reports
- blocks
- subscriptions
- usage limits

### RLS

Every table must have RLS enabled.

### Storage

Use private bucket:

```txt
chat-media-private
```

No public chat media bucket.

### Edge Functions

Required for:
- invite creation
- invite acceptance
- chat message creation
- media upload permission
- one-time media open
- reporting
- blocking
- subscription sync

### Realtime

Used only for:
- new chat messages
- invite received
- invite accepted
- media viewed state
- typing indicator later

Do not use Realtime for discovery feed.

## Discovery feed

The Discovery feed is served by the `getDiscoveryFeed` Edge Function.
**It is a 10-card batch, not an infinite feed.** The iOS client requests
`limit = 10`, never paginates with `cursor`, and replaces its entire
visible list on every refresh. There is no "load more", no last-card
paging, and no `next_cursor` consumption on iOS. The backend still
exposes `next_cursor` / `has_more` for completeness but the client
ignores them.

**Exclusion rules** (every batch excludes these user_ids):
- self
- deleted / banned profiles
- profiles I have blocked
- profiles that have blocked me
- partners with whom I have an `active` chat room
- partners with whom I have a `live_pending` invite in either direction
  (so the same user doesn't reappear as sendable while their countdown
  is still ticking; the Invite tab is the right place to see them)
- best-effort: profiles already visible in the caller's current list,
  passed up via `exclude_ids`. Applied **only** when enough alternates
  exist; the server falls back to repeats rather than returning an
  empty batch.

**Sort order** (deterministic — not random):
1. Tag-overlap count desc — caller-supplied filters take precedence,
   otherwise we use the caller's own `profile_tags`.
2. `profiles.updated_at` desc.
3. `profiles.created_at` desc.
4. `profiles.id` desc as final tiebreaker.

**No Gold boost today.** TODO: Gold may receive a small ranking boost
later, but it must not overpower tag relevance — the feed's value is
shared interests, not paid placement.

## Chat lifecycle

`chat_rooms.status` accepts `'active' | 'archived' | 'blocked' | 'deleted'`.
The `deleteConversation` Edge Function flips a participant-owned room
from `active` to `deleted` (idempotent), stamping `deleted_at` and
`deleted_by`. Soft-delete only — messages, media, and reports are
preserved for moderation and the cleanup cron.

A deleted room:
- disappears from `ChatService.fetchRooms()` (filters `status='active'`)
- stops counting against `_ga_count_active_chats` (also filters `'active'`),
  so the user gets their slot back under the Free 5-chat cap
- rejects new messages (`createChatMessage` requires `status='active'`)
- rejects new media uploads (`requestMediaUpload` requires `'active'`)
- rejects view-once unlocks (`openViewOnceMedia` requires `'active'`)

There is no archive feature. The user-facing action is "Delete
conversation"; the row-level state is shared between participants —
when one user deletes, the conversation disappears for both.

## Security Boundary

Client is not trusted.

The backend must enforce:
- user identity
- room membership
- invite limits
- media view-once rules
- subscription limits
- block/report behavior
