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
Default page size is **10** profiles (`DEFAULT_LIMIT = 10`, max 50).
Smaller pages keep the post-fetch overlap sort cheap and let pull-to-
refresh surface fresh candidates faster.

**Exclusion rules** (every page excludes these user_ids):
- self
- deleted / banned profiles
- profiles I have blocked
- profiles that have blocked me
- partners with whom I have an `active` chat room

`live_pending` invite partners are intentionally **not** excluded — when
the caller has just sent an invite, the receiver should remain visible
with their countdown ring running. Once the chat room exists, the
active-room rule above takes over.

**Sort order** (deterministic — not random):
1. Tag-overlap count desc — caller-supplied filters take precedence,
   otherwise we use the caller's own `profile_tags`.
2. `profiles.updated_at` desc.
3. `profiles.created_at` desc.
4. `profiles.id` desc as final tiebreaker.

**No Gold boost today.** TODO: Gold may receive a small ranking boost
later, but it must not overpower tag relevance — the feed's value is
shared interests, not paid placement.

## Security Boundary

Client is not trusted.

The backend must enforce:
- user identity
- room membership
- invite limits
- media view-once rules
- subscription limits
- block/report behavior
