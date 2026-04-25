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

## Security Boundary

Client is not trusted.

The backend must enforce:
- user identity
- room membership
- invite limits
- media view-once rules
- subscription limits
- block/report behavior
