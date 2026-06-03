# Edge Functions

All sensitive actions must use Supabase Edge Functions.

## Standard Response Format

### Success

```json
{
  "ok": true,
  "data": {}
}
```

### Error

```json
{
  "ok": false,
  "error_code": "STRING_CODE",
  "message": "Human readable message"
}
```

## Required Functions

### sendLiveInvite

Creates a 15-second live invite.

Checks:
- user is authenticated
- sender is not banned
- receiver is not banned
- sender is not inviting self
- sender has not blocked receiver
- receiver has not blocked sender
- sender has available concurrent live invite slot
- Free/Silver: max 1 active outgoing live invite
- Gold: max 2 active outgoing live invites
- no duplicate live pending invite to the same receiver
- receiver can receive invite

Creates:
- invite with `status = live_pending`
- `delivery_mode = live`
- `live_expires_at = now() + 15 seconds`
- active invite lock until `live_expires_at`

Returns:
```json
{
  "ok": true,
  "data": {
    "invite_id": "uuid",
    "live_expires_at": "timestamp",
    "duration_seconds": 15
  }
}
```

### acceptLiveInvite

Accepts a live invite within the 15-second window.

Checks:
- user is authenticated
- user is the receiver
- invite status is `live_pending`
- current time is before `live_expires_at`
- users are not blocked
- receiver is not banned
- active chat limit allows chat creation

Behavior:
- set invite status to `live_accepted`
- set `accepted_at`
- create chat room
- release sender's active invite lock
- does not consume missed-invite accept quota

Returns:
```json
{
  "ok": true,
  "data": {
    "chat_room_id": "uuid",
    "invite_id": "uuid"
  }
}
```

### declineInvite

Declines a live or missed invite.

Checks:
- user is authenticated
- user is receiver
- invite is actionable

Behavior:
- set status to `declined`
- release active invite lock if it was live

### cancelLiveInvite

Allows sender to cancel their active live invite.

Checks:
- user is authenticated
- user is sender
- invite status is `live_pending`

Behavior:
- set status to `cancelled`
- release active invite lock

### markLiveInviteMissed

Moves expired live invites to missed status.

Can be called by:
- cron job
- client after countdown
- backend scheduled process

Checks:
- invite status is `live_pending`
- current time is after `live_expires_at`

Behavior:
- set `status = missed`
- set `delivery_mode = missed`
- set `missed_expires_at = now() + configured duration`
- release active invite lock

### expireLiveInvites

Cron function that marks all expired live invites as missed.

Behavior:
- find `live_pending` invites where `live_expires_at < now()`
- convert to missed
- release active invite locks

### acceptMissedInvite

Accepts an invite from the missed invite list.

Checks:
- user is authenticated
- user is receiver
- invite status is `missed`
- missed invite has not expired
- users are not blocked
- receiver is not banned
- active chat limit allows chat creation
- if plan is free, user has missed-invite accept quota remaining
- if paid, allow instant acceptance according to plan

Behavior:
- if free, increment `missed_invite_accept_usage`
- set invite status to `missed_accepted`
- set `accepted_at`
- create chat room

Important:
- This function is the only place where missed-invite accept quota is consumed.
- `acceptLiveInvite` must never consume missed-invite quota.

### expireMissedInvites

Cron function that expires old missed invites.

Behavior:
- find `missed` invites where `missed_expires_at < now()`
- set status to `expired`

### getDiscoveryFeed

Returns paginated discovery posts.

Hard exclusions (never appear):
- self
- not banned, not deleted
- profiles I have blocked, profiles that have blocked me
- profiles with an **active** chat room (`chat_rooms.status='active'`)
- profiles with a `live_pending` invite either direction
- profiles already visible in the caller's `exclude_ids` (best-effort,
  relaxed when too few alternatives exist)

Soft penalty band (deprioritized but still eligible):
- Profiles with a recently **deleted** chat room
  (`chat_rooms.status='deleted'`, `deleted_at` within the last 30 days).
  Per partner using the most recent `deleted_at`:
  - within 7 days → band 20 (strong)
  - within 30 days → band 8 (weak)
  - older than 30 days → band 0 (fresh, no penalty)
  Deliberately NOT a hard filter: during early-beta liquidity, an empty
  Discovery page is worse than briefly resurfacing a partner from a
  past chat. Deleted-room partners stay eligible and surface to fill
  thin pools — they just sort below every fresh candidate.

Sort order:
1. `deletedRoomPenalty` ascending — the penalty IS the primary key.
   Any band-0 (fresh) candidate ranks above every band-8 or band-20
   candidate, regardless of their tag overlap or fit-chip match.
   Deleted partners only surface after the fresh band is exhausted.
2. tag overlap desc (tie-break within a band on wavelength signal)
3. Taipei beta fit chip score desc (then on conversation-fit chips)
4. per-request random jitter asc (refresh variety)

This is stricter than the prior combined-score formula. A recently
deleted partner with strong tag overlap still ranks below every fresh
candidate, including fresh zero-overlap strangers. The product rule
for early-beta liquidity is: fresh always wins when fresh exists.

Optional `tags` body filter is matched against
`profile_tags.normalized_tag`.

### createChatMessage

Creates a text or media chat message.

Checks:
- user is chat participant
- room is active
- users are not blocked
- sender is not banned
- message is valid

### requestMediaUpload

Allows client to upload private chat media.

Checks:
- user is room participant
- MIME type allowed
- size allowed
- duration allowed
- quota allowed (5 unopened view-once cap)

Behavior:
- creates `media_assets` row with `status = pending_upload`, `view_once = true`, `retention_until = now() + 24h`, `moderation_hold_at = null`, `storage_deleted_at = null`.

Returns:
- storage path
- signed upload URL + token

### openViewOnceMedia

Opens one-time-view media.

Checks:
- user is room participant
- user is not owner/sender
- media is active
- media has not been viewed
- message belongs to room

Behavior:
- atomically marks media `viewed` before returning a signed URL
- returns a short-lived signed URL (60 seconds)
- never deletes storage (cleanup is the cron's job)

### finalizeViewOnceMedia

Called by the iOS viewer when the receiver closes a view-once preview.

Behavior:
- requires the caller to be `media.viewed_by`
- stamps `view_finalized_at = now()` if not already set
- backfills `retention_until = created_at + 24h` if missing
- does **not** delete storage (changed from previous behaviour)
- idempotent: returns `ok` for already-finalized, already-deleted, and moderation-held rows

### deleteExpiredMedia

The only path that actually removes storage bytes for view-once media. Uses the Storage API (`sb.storage.from(bucket).remove([...])`) — direct SQL deletes against `storage.objects` are blocked by Supabase's `storage.protect_delete()` trigger.

Auth — accepts either:
- `Authorization: Bearer <service-role>` for ad-hoc / CI invocation, or
- `x-cleanup-secret: <scheduler secret>` for the recurring cron (least-privilege path; secret stored in Vault as `getalong_delete_expired_media_scheduler_secret` and in the function env as `CLEANUP_SCHEDULER_SECRET`).

Gateway: this is the only Edge Function with `verify_jwt = false` (see `supabase/config.toml`). The gateway-level JWT check is disabled INTENTIONALLY because the cron path authenticates with a custom `x-cleanup-secret` header rather than a JWT bearer — without this override the Supabase gateway would reject every cron request before the handler runs. Disabling `verify_jwt` does NOT make this function public: the handler enforces application-level auth (scheduler secret OR service-role Bearer) and rejects everything else with 401. Any other function in this repo MUST keep `verify_jwt = true` (the default).

Deploy command: `supabase functions deploy deleteExpiredMedia --no-verify-jwt`. The CLI flag is required on every deploy (older CLI versions including v2.90.0 do not apply the `verify_jwt = false` value from `config.toml` on deploy — the flag is the canonical mechanism). If you deploy without the flag the gateway will revert to `verify_jwt = true` and the cron will start failing with `UNAUTHORIZED_NO_AUTH_HEADER`.

Scheduling — migration 0033 registers a pg_cron job `getalong_delete_expired_media_every_2_minutes` that POSTs here every 2 minutes via `net.http_post`. The URL is read from Vault (`getalong_project_url`); the scheduler secret is read from Vault. This is the authoritative recurring runner.

The companion SQL function `cleanup_expired_media()` (mig 0031) is metadata-only: it flips `pending_upload`/`active` rows to `expired` and emits retention-elapsed row ids for observability, but never touches `storage.objects` and never stamps `storage_deleted_at`.

Deletes:
- pending_upload rows older than 30 minutes (skip held)
- active rows past `expires_at` (skip held)
- any row where `retention_until` has elapsed and `storage_deleted_at IS NULL` (skip held)

Skips rows where `moderation_hold_at IS NOT NULL`. Idempotent and batched.

### reportContent

Creates a report and applies moderation holds.

Body: `target_type`, `target_id`, `reason`, optional `details`, optional `context_room_id` (only meaningful for `target_type = profile`).

Checks:
- user authenticated
- valid target type
- target exists
- reporter is a room participant for message/media/chat_room
- reporter is sender/receiver for invite

Moderation hold scope:
- `media`     → the one media row
- `message`   → that message's media (if any)
- `chat_room` → the room itself + every still-existing media row in that room (single UPDATE)
- `profile`   → only when `context_room_id` is supplied AND reporter is a participant; scoped to that room's media. Never room-less / app-wide.
- `invite`    → no media preservation

Stable behavior:
- already-deleted media (storage_deleted_at IS NOT NULL) is left alone — bytes are gone, the report still succeeds
- duplicate report (`ALREADY_REPORTED`) still re-applies the hold

### blockUser

Blocks another user.

Behavior:
- creates block record
- prevents future invites/messages
- optionally archives active chat
- cancels/moves active invites between the two users

### syncSubscriptionStatus

Updates backend subscription plan/status.

Use StoreKit 2 server verification or RevenueCat webhooks.

### sendPushNotification

Sends APNs push.

Use for:
- live invite received
- invite accepted
- missed invite created
- new message
- media viewed

## Invite Error Codes

Use stable error codes:

```txt
AUTH_REQUIRED
PROFILE_NOT_FOUND
USER_BANNED
RECEIVER_BANNED
SELF_INVITE_NOT_ALLOWED
BLOCKED_RELATIONSHIP
LIVE_INVITE_SLOT_FULL
DUPLICATE_LIVE_INVITE
INVITE_NOT_FOUND
INVITE_NOT_ACTIONABLE
LIVE_INVITE_EXPIRED
MISSED_INVITE_EXPIRED
MISSED_ACCEPT_LIMIT_REACHED
ACTIVE_CHAT_LIMIT_REACHED
CHAT_ALREADY_EXISTS
```
