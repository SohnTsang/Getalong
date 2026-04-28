# Claude Code Instructions for Getalong

You are working on Getalong, an iOS-first SwiftUI + Supabase social discovery app.

## Original Design Rule

Getalong must not copy Heymandi’s UI, branding, layout, colors, wording, or visual identity.

Use a custom Getalong design system with full light mode and dark mode support from MVP.

## Product Summary

Getalong is a text-first social discovery app where users connect through:
- short text posts
- user-created tags
- 15-second live invitations
- missed invitation recovery
- private one-to-one chat
- one-time-view image/GIF/video messages

The product is similar in category to Heymandi but must not copy it directly. The goal is a premium, safer, cleaner, business-grade implementation.

## Absolute Priorities

1. Ship iOS MVP first.
2. Use Supabase as the backend.
3. Keep Android planned but not implemented until iOS MVP is stable.
4. Protect private chat media.
5. Enforce one-time-view media server-side.
6. Keep scope small enough to ship.
7. Use the corrected 15-second live invite model.

## Correct Invite Model

Getalong uses a real-time live invitation system.

### Live Invite

- Sender sends a live invite to another user.
- Receiver has 15 seconds to accept.
- If receiver accepts within 15 seconds, a chat room is created immediately.
- A live accept does not consume the receiver's missed-invite accept quota.
- Free users can have only 1 outgoing live invite active at a time.
- Gold users can have 2 outgoing live invites active at a time.

### Missed Invite

- If the receiver does not accept within 15 seconds, the invite becomes a missed invite.
- Missed invites appear in the receiver's missed invite list.
- Free users have limited missed-invite accepts per day.
- Paid users can accept missed invites instantly or with higher/no limits.
- Accepting a missed invite creates a chat room.

### Do Not Use This Old Model

Do not implement the main invite mechanic as:
- 10 invites/day
- 30 invites/day
- simple daily sent-invite limits

Usage limits can exist for abuse prevention, but the core product mechanic is concurrent live invite slots + missed-invite accept limits.

## Required Reading Before Coding

Read these files first:

- `design-docs/PROJECT_PLAN.md`
- `design-docs/MVP_SCOPE.md`
- `design-docs/SYSTEM_ARCHITECTURE.md`
- `design-docs/DATABASE_SCHEMA.md`
- `design-docs/EDGE_FUNCTIONS.md`
- `design-docs/ONE_TIME_MEDIA_SECURITY.md`
- `design-docs/MONETIZATION_PLAN.md`
- `design-docs/QA_CHECKLIST.md`
- every file in `/agents`

Note: internal architecture / safety / business docs live in `/design-docs/`. The `/docs/` folder is reserved for the public GitHub Pages site (index.html + privacy/terms/support/assets only) and must not contain internal documents.

## Development Rules

- Do not expose Supabase service role key in any client app.
- Do not make chat media public.
- Do not rely on client-only security.
- Use Edge Functions for sensitive actions.
- Enable RLS on every table.
- Use typed models.
- Keep SwiftUI views thin.
- Put business logic in services/view models.
- Every feature must include loading, success, empty, and error states.
- Every backend feature must include test cases.
- Every API must return a stable JSON contract.
- Invites, invite locks, missed-invite accepts, and chat creation must be enforced server-side.

## First Implementation Task

Start with:

1. Supabase schema migration.
2. RLS enabled on all tables.
3. iOS SwiftUI project shell.
4. Tabs: Discover, Invites, Chats, Profile.
5. Placeholder Supabase client setup.
6. Correct invite tables for 15-second live invites.
7. No Android implementation yet.

## Plan Limits (final)

| | Free | Gold |
| --- | --- | --- |
| Outgoing live invite slots | 1 | 2 |
| Missed-invite accepts | 1/day | unlimited |
| Active chats | 5 | unlimited |
| Profile tags | 3 | 3 (no upsell) |
| Priority Invites | 1 / 2-day rolling | 3 / 1-day rolling |
| View-once media / safety | allowed | allowed |

Backend is the source of truth (`_ga_*` Postgres helpers + RPCs). Client never trusts a cached plan.

## Ads

- No AdMob SDK / Google Ads SDK / IDFA tracking in the app binary.
- No in-app ads in MVP.
- Google Ads / Apple Search Ads as **external** acquisition channels are allowed post-TestFlight (they don't change app code).

## Non-MVP Features

Do not build these unless explicitly approved:

- group chat
- video calls
- voice calls
- AI matching engine
- full admin dashboard
- web app
- public photo profile feed
- complex dating filters
