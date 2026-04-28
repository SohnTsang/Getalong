# Getalong

Getalong is an iOS-first, text-first social discovery app.

The app helps people connect through small signals, user-created tags, intentional invitations, and private one-to-one chat. It is similar in category to Heymandi, but the goal is not to clone it. Getalong should be positioned as a cleaner, safer, more premium, business-grade product with better trust, moderation, and one-time-view media.

## Core Product Direction

- Words before appearance
- Tag-based discovery
- Intentional invitations instead of random matching
- Private chat after invite acceptance
- One-time-view image/GIF/video messages
- Progressive trust and safety
- Supabase backend
- SwiftUI iOS app first
- Native Android later

## Tech Stack

### iOS MVP
- SwiftUI
- Supabase Auth
- Supabase Postgres
- Supabase Realtime
- Supabase Storage
- Supabase Edge Functions
- APNs
- StoreKit 2 or RevenueCat

### Android Later
- Kotlin
- Jetpack Compose
- Supabase Kotlin client
- FCM
- Google Play Billing or RevenueCat

## Folder Structure

```txt
getalong/
  README.md
  CLAUDE.md
  design-docs/   # internal architecture / business / safety docs (not public)
  docs/          # GitHub Pages site (index.html, privacy/, terms/, support/, assets/)
  agents/
  supabase/
  ios/
  android/
```

GitHub Pages serves from `main` branch, `/docs` folder. The `/docs` directory must contain only public site files; internal architecture, schema, and business documents live in `/design-docs`.

## How to Use This Pack with Claude Code

1. Put these files in your project root.
2. Open the folder in Claude Code.
3. Ask Claude Code to read `CLAUDE.md`, `design-docs/PROJECT_PLAN.md`, and all files in `/agents`.
4. Start with Supabase schema + iOS app shell.
5. Do not let Claude build Android until iOS MVP contracts are stable.
