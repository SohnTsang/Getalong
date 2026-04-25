# Getalong iOS

SwiftUI iOS app. MVVM, services, Supabase Swift client, Edge Functions for
sensitive actions.

## Layout

```
ios/
  Getalong/
    project.yml                # XcodeGen spec
    Getalong/
      App/                     # GetalongApp, AppRouter
      Core/                    # Supabase client, session, realtime, push, logger
      Models/                  # Profile, Topic, Post, Invite, ChatRoom, Message, MediaAsset, SubscriptionPlan
      Services/                # Auth, Profile, Discovery, Invite, Chat, Media, Report, Subscription
      Features/                # Discovery, Invites, Chat, Profile, Onboarding, Settings, Safety, Paywall
      DesignSystem/            # GAColors, GATypography, GASpacing, GACornerRadius, GATheme
        Components/            # GAButton, GATextField, GACard, GAChip, GAEmptyState, GAErrorBanner, GALoadingView
      Utilities/               # DateFormatterFactory, Haptics
      Resources/               # Info.plist, Secrets.example.plist
```

## First-time setup

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen):
   ```bash
   brew install xcodegen
   ```
2. Copy the secrets template and fill in your Supabase values:
   ```bash
   cp Getalong/Resources/Secrets.example.plist Getalong/Resources/Secrets.plist
   ```
   Only the **anon** key goes in here. Never put the service role key
   anywhere in the iOS app.
3. Generate the Xcode project:
   ```bash
   cd ios/Getalong
   xcodegen generate
   open Getalong.xcodeproj
   ```
4. In Xcode, set your Apple Developer team in target → Signing & Capabilities.
5. Build & run on an iPhone simulator or device.

## Testing the app shell

After a successful run you should see a tab bar with **Discover**,
**Invites**, **Chats**, and **Profile**. Each tab shows a placeholder
empty state styled by the design system. Toggle **Profile → Appearance**
to verify light/dark mode swap.

## Architecture rules

- Views must not call Supabase directly.
- ViewModels hold state and call Services.
- Services call Supabase or Edge Functions.
- Every screen needs loading, success, empty, and error states.
- Sensitive invite/chat/media writes go through Edge Functions.

## What's not wired yet

- The Supabase Swift client is declared as an SPM dependency in
  `project.yml` but `SupabaseClientProvider` is still a stub. Replace its
  `// TODO` block with a real `SupabaseClient` once you've generated the
  Xcode project.
- Auth, sign-in-with-Apple, and onboarding flows are not built.
- Realtime, push notifications, IAP, and media upload paths are stubs.
- Full feature views (compose post, send invite, chat, paywall) are not
  built. Discovery/Invites/Chats/Profile are intentional empty-state
  placeholders.
