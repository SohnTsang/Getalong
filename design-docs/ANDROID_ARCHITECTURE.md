# Android Architecture

Android is planned for later. Do not implement it before iOS MVP is stable.

## Tech Stack Later

- Kotlin
- Jetpack Compose
- Supabase Kotlin client
- Coroutines
- FCM
- Google Play Billing or RevenueCat

## Rule

Android must follow the same backend API contracts as iOS.

## Planned Structure

```txt
android/
  app/
  core/
    network/
    supabase/
    auth/
    realtime/
    media/
  feature/
    onboarding/
    discovery/
    invites/
    chat/
    profile/
    settings/
    safety/
    paywall/
  design/
```

## Do Not Do Yet

- Do not create full Android UI before iOS MVP.
- Do not create separate business rules.
- Do not fork API behavior.
