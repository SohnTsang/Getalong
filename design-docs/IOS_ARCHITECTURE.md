# iOS Architecture

## Tech Stack

- SwiftUI
- Swift Concurrency
- Supabase Swift client
- PhotosUI
- AVFoundation
- APNs
- StoreKit 2 or RevenueCat

## Folder Structure

```txt
Getalong/
  App/
    GetalongApp.swift
    AppRouter.swift

  Core/
    SupabaseClientProvider.swift
    SessionManager.swift
    RealtimeManager.swift
    PushNotificationManager.swift
    MediaUploadManager.swift
    Logger.swift

  Models/
    Profile.swift
    ProfileTag.swift
    Post.swift
    Invite.swift
    ChatRoom.swift
    Message.swift
    MediaAsset.swift
    SubscriptionPlan.swift

  Services/
    AuthService.swift
    ProfileService.swift
    ProfileTagService.swift
    DiscoveryService.swift
    InviteService.swift
    ChatService.swift
    MediaService.swift
    ReportService.swift
    SubscriptionService.swift

  Features/
    Onboarding/
    Discovery/
    Invites/
    Chat/
    Profile/
    Settings/
    Safety/
    Paywall/

  DesignSystem/
    Colors.swift
    Typography.swift
    Components/

  Utilities/
    DateFormatterFactory.swift
    Haptics.swift
    ImageCompressor.swift
    VideoCompressor.swift
```

## Architecture Rules

- Views should not directly call Supabase.
- ViewModels hold state and call Services.
- Services call Supabase or Edge Functions.
- Models must be typed.
- All network calls must handle errors.
- Every screen needs loading, empty, error, and success states.
- Sensitive actions must use Edge Functions.

## Main Tabs

1. Discover
2. Invites
3. Chats
4. Profile

## App State

Use `SessionManager` to determine:
- unauthenticated
- onboarding required
- authenticated and onboarded
- banned/deleted state
