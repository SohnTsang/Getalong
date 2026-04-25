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

Filters:
- not hidden
- not deleted
- not banned author
- not blocked relationship
- optional tag/city/language filters (tags are matched against
  `profile_tags.normalized_tag`)

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
- quota allowed

Returns:
- storage path
- upload token/metadata if needed

### openViewOnceMedia

Opens one-time-view media.

Checks:
- user is room participant
- user is not owner/sender
- media is active
- media has not been viewed
- message belongs to room

Behavior:
- mark media viewed before returning signed URL
- return short-lived signed URL
- schedule/delete media after view

### deleteExpiredMedia

Cron cleanup.

Deletes:
- viewed view-once media
- expired unviewed media
- orphaned media

### reportContent

Creates a report.

Checks:
- user authenticated
- valid target type
- target exists
- duplicate spam prevention

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
