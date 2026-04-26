# Social SSO setup

Getalong uses three providers in the MVP: **Apple, Google, X**. Apple is
wired natively via `ASAuthorizationAppleIDProvider`. The other two use
Supabase's hosted OAuth flow opened inside `ASWebAuthenticationSession`.

> Facebook is intentionally **not** supported in the MVP. Do not enable
> the Facebook provider in the Supabase dashboard — leaving it disabled
> avoids exposing a non-functional code path.

The redirect URL shared by all providers is **`getalong://auth-callback`**.
It must be added in two places:

1. **Supabase dashboard** → Authentication → URL Configuration → **Additional
   redirect URLs** → add `getalong://auth-callback`.
2. **iOS Info.plist** → already registered as `CFBundleURLSchemes = ["getalong"]`.

## 1. Apple

Already done. `Sign in with Apple` capability is on, the entitlement is in
`Getalong.entitlements`, and the Apple sign-in button uses the native
flow (not the web flow).

In the Supabase dashboard you do **not** need to enable the Apple
provider — `signInWithIdToken` accepts the JWT directly. (Enabling it is
fine; just not required for native iOS.)

## 2. Google

1. https://console.cloud.google.com → APIs & Services → OAuth consent screen
   → fill in app name, support email, developer email. Add scopes:
   `openid`, `email`, `profile`.
2. Credentials → **Create credentials** → **OAuth client ID** → **Web
   application**. Add Authorized redirect URI:
   ```
   https://<YOUR-PROJECT-REF>.supabase.co/auth/v1/callback
   ```
3. Copy the **Client ID** and **Client Secret**.
4. Supabase dashboard → Authentication → Providers → **Google** → Enable,
   paste the Client ID and Client Secret, **Save**.

You don't need a separate iOS OAuth client — supabase-swift goes through
the web flow.

## 3. X (Twitter)

1. https://developer.twitter.com → Projects & Apps → **Create app** in a
   project. Use the OAuth 2.0 user-context flow.
2. App Settings → User authentication settings → Set up. Pick:
   - **App permissions**: Read.
   - **Type of App**: Web App.
   - **Callback URI**: `https://<YOUR-PROJECT-REF>.supabase.co/auth/v1/callback`
   - **Website URL**: any placeholder is fine for dev.
3. Copy the **Client ID** and **Client Secret** (OAuth 2.0).
4. Supabase dashboard → Authentication → Providers → **Twitter** → Enable,
   paste Client ID + Client Secret, **Save**.

## Test sequence

1. Build and run.
2. Tap **Continue with Apple** → simulator's iCloud account → confirm.
3. Sign out from Profile.
4. Tap **Continue with Google** → Google web sheet → consent → returns.
5. Repeat for X (test/dev users only until reviewed).
6. After each, the app should show the quick-start profile setup the
   first time, then the main tab app on subsequent runs.

## Common gotchas

- **`http://localhost:54321/auth/v1/callback`** is for `supabase start`
  local dev only. Hosted Supabase always uses your project URL.
- **The X Free tier does not include OAuth 2.0 user authentication** —
  upgrade to the **Basic** tier (or higher) for X SSO.
- **`com.googleusercontent.apps.<id>` URL scheme** — only required if
  you wire a native Google iOS SDK. With the web flow we use here, the
  only URL scheme you need on the iOS side is `getalong://`.
