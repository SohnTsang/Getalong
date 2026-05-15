# One-Time Media Security

## Goal

Users can send image/GIF/video messages that can only be opened once by the receiver.

## Important Truth

One-time-view media cannot fully prevent screenshots or external recording. The app must not promise screenshot-proof privacy.

Use this copy:

> View-once media can only be opened once in the app. For safety, abuse prevention, and moderation purposes, view-once media may be retained privately for up to 24 hours after upload or viewing. Screenshots or screen recording may still be possible. If content, a conversation, or a user is reported, related content may be retained longer while we review the report.

## Storage Rule

Use a private Supabase Storage bucket only:

```txt
chat-media-private
```

Never make chat media public.

## Upload Flow

1. Sender chooses media.
2. Sender selects `View once`.
3. App compresses media.
4. App calls `requestMediaUpload`.
5. Edge Function validates:
   - auth
   - room membership
   - MIME type
   - file size
   - duration
   - usage quota
6. Client uploads to private bucket.
7. Client calls `createChatMessage`.
8. Message appears in chat.

## Open Flow

1. Receiver taps media bubble.
2. App calls `openViewOnceMedia(media_id)`.
3. Edge Function validates:
   - authenticated user
   - room participant
   - not sender
   - media is active
   - media not already viewed
4. DB transaction:
   - mark media as viewed
   - set `viewed_by`
   - set `viewed_at`
   - set `status = viewed`
5. Function returns a signed URL valid for 30–60 seconds.
6. Client displays media.
7. When the receiver closes the viewer, `finalizeViewOnceMedia` stamps `view_finalized_at`. The user-facing flow is over: the bubble flips to "Opened" / "No longer available" and the receiver cannot reopen it.
8. Storage bytes remain privately retained until either:
   - `retention_until` (created_at + 24 hours) elapses and the cleanup cron deletes them, or
   - a report against the media / message / room / user-from-chat puts the row on `moderation_hold_at`. Held rows are skipped by cleanup until manual review.

## Failure States

- Already viewed
- Expired
- Not room participant
- Sender trying to open as receiver
- Storage object missing
- Network lost after media marked viewed
- App killed while displaying

## UX Requirements

### Before sending

Show:
- Normal
- View once

### In chat before opening

Show:
- "View once photo"
- "View once GIF"
- "View once video"

### After opening

Show:
- "Viewed"

### If unavailable

Show:
- "This media is no longer available."

## Retention and Moderation Hold

- Normal view-once media is retained privately for up to 24 hours after upload (`retention_until = created_at + 24h`).
- After 24 hours, the `deleteExpiredMedia` Edge Function is the only path that actually deletes the storage bytes and stamps `storage_deleted_at` (via the Storage API, not SQL — Supabase's `storage.protect_delete()` trigger blocks direct SQL deletes against `storage.objects`). The companion SQL function `cleanup_expired_media()` only marks candidates (flips `pending_upload`/`active` rows to `expired` and emits the retention-elapsed row ids for observability); it deliberately never touches `storage.objects`.
- `deleteExpiredMedia` runs automatically every 2 minutes via pg_cron + pg_net (migration 0033, job `getalong_delete_expired_media_every_2_minutes`). The cron job reads the project URL and a dedicated scheduler secret from Supabase Vault (`getalong_project_url`, `getalong_delete_expired_media_scheduler_secret`) and POSTs to the function with the secret in the `x-cleanup-secret` header. The function rejects unauthenticated calls and calls bearing a wrong secret; the existing service-role Bearer path is preserved for ad-hoc / CI invocation. The service-role key is never used by the scheduler.
- `deleteExpiredMedia` is configured with `verify_jwt = false` in `supabase/config.toml`. This is intentional and required: the cron's `x-cleanup-secret` header is not a JWT, so leaving the gateway JWT check on would block every cron request before the handler ran. Application-level auth (scheduler secret or service-role Bearer) inside the function is the security boundary; the disabled gateway check does NOT make the function public. No other function in this repo disables `verify_jwt`.
- If a report is filed against the media, the message, the chat room, or the partner-from-chat (with `context_room_id`), the relevant media rows are stamped with `moderation_hold_at`. Held rows are never deleted by cleanup.
- `chat_rooms.moderation_hold_at` is also stamped for chat-room and user-from-chat reports so the hold survives even if the underlying media rows are gone.
- Already-deleted media (storage_deleted_at IS NOT NULL) cannot be recovered. Reports still succeed, but no bytes are preserved.
- Reviewer access is intentionally not built yet. `moderation_access_logs` exists as audit groundwork; any future reviewer tool must require service role / admin role, mint short-lived signed URLs, and write an audit row per access.

## Testing Requirements

- Receiver opens once successfully.
- Receiver cannot reopen.
- Sender cannot open as receiver.
- Third user cannot open.
- Blocked user cannot open.
- Expired media cannot open.
- Poor network cannot double-open.
- Storage cleanup deletes only after `retention_until` has elapsed.
- Cleanup skips rows where `moderation_hold_at IS NOT NULL`.
- Reporting media / message / chat_room / user-from-chat (with context_room_id) sets `moderation_hold_at` on the right rows.
- Reporting already-deleted media still succeeds.
- Duplicate report still re-applies the hold.
