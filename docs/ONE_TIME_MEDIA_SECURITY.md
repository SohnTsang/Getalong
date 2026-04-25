# One-Time Media Security

## Goal

Users can send image/GIF/video messages that can only be opened once by the receiver.

## Important Truth

One-time-view media cannot fully prevent screenshots or external recording. The app must not promise screenshot-proof privacy.

Use this copy:

> This media can only be opened once. Screenshots or screen recording may still be possible.

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
7. Cleanup function deletes storage object.

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

## Testing Requirements

- Receiver opens once successfully.
- Receiver cannot reopen.
- Sender cannot open as receiver.
- Third user cannot open.
- Blocked user cannot open.
- Expired media cannot open.
- Poor network cannot double-open.
- Storage cleanup works.
