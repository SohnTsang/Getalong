# Release Checklist

## Before TestFlight

- Supabase dev/staging/prod separation decided.
- RLS enabled on every table.
- Service role key not in app.
- Private storage bucket verified.
- Auth works.
- Account deletion works.
- Block/report works.
- One-time media tested.
- Crash logging added.
- Basic analytics added.
- App icon added.
- Launch screen added.

## App Store Review Risks

Check these carefully:

- User-generated content requires report/block.
- User-generated content requires moderation plan.
- Account deletion must be available.
- Subscription must clearly explain pricing.
- Privacy labels must match actual data use.
- One-time media copy must not overpromise screenshot prevention.

## Go/No-Go Criteria

Go only if:
- Core flow works end-to-end.
- No obvious RLS bypass.
- No public chat media.
- No crash on auth/feed/chat.
- Report/block available.
- Account deletion available.
