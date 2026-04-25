# MVP Scope

## MVP Must-Have

### Account

- Email login
- Sign in with Apple
- Age gate: 18+
- Create profile
- Delete account

### Profile

- Display name
- Unique public handle
- Short bio
- User-created tags (optional, edited from Profile — not required at sign-up)
- Optional gender
- Optional gender visibility
- Language/city/country
- Privacy controls

### Discovery

- Short text posts
- User-created tags
- Feed
- Basic filtering
- Profile preview
- Hide deleted/banned users
- Hide blocked users

### 15-Second Live Invitations

- Send live invite
- Live invite lasts 15 seconds
- Receiver can accept within 15 seconds
- Receiver can decline
- If accepted live, chat is created immediately
- Live accept does not consume missed-invite accept quota
- If not accepted in 15 seconds, invite becomes missed
- Free/Silver users can have 1 active outgoing live invite
- Gold users can have 2 active outgoing live invites
- Server-side invite lock enforcement

### Missed Invites

- Missed invite list
- Accept missed invite
- Free users have limited missed-invite accepts per day
- Paid users can accept missed invites instantly or with higher/no limits
- Missed invite expiry
- Chat created after missed invite acceptance

### Chat

- One-to-one only
- Text messages
- Realtime new messages
- Pagination
- Report message
- Block user

### One-Time Media

- Image
- GIF
- Short video
- Private upload
- View-once option
- Server-enforced open
- Viewed placeholder
- Cleanup job

### Safety

- Report profile
- Report post
- Report message
- Report media
- Block user
- Auto-hide threshold
- Banned users cannot post/invite/message

### Monetization

- Free missed-invite accept limit
- Silver paid missed-invite acceptance
- Gold two concurrent live invites
- Gold higher/unlimited active chats
- Backend-enforced plan limits

## Not MVP

- Android app implementation
- Group chat
- Voice calls
- Video calls
- AI matching
- Full admin dashboard
- Web app
- Public photo feed
- Complex dating filters
- Precise location
- Voice notes
- Stories
- Live streaming
- Crypto/payment wallet
- Event booking

## Old Invite Model to Avoid

Do not treat the main invite system as a simple daily send limit.

Avoid this as the primary model:
- Free: 10 invites/day
- Silver: 30 invites/day
- Gold: 60 invites/day

The correct model is:
- concurrent live invite slots
- 15-second live acceptance
- missed-invite accept limits

## MVP Success Criteria

A complete end-to-end flow works:

1. User A signs up.
2. User B signs up.
3. User A posts a text card.
4. User B discovers it.
5. User B sends a 15-second live invite.
6. User A accepts within 15 seconds.
7. Chat room is created immediately.
8. No missed-invite quota is consumed.
9. Users exchange messages.
10. User sends one-time-view media.
11. Receiver opens it once.
12. Receiver cannot reopen it.
13. If a live invite is missed, it appears in missed invites.
14. Free user can accept only within free missed-invite quota.
15. User can report/block.
