# Getalong Project Plan

## Vision

Getalong is a text-first social discovery app where people connect through small signals, user-created tags, real-time invitations, missed invite recovery, and private conversations.

The app should feel calmer and more intentional than swipe-based dating apps, less noisy than public social media, and safer than anonymous random chat.

## One-Sentence Pitch

Meet people through words, not photos.

## Product Pillars

1. **Words first**  
   Users express personality through short signals, optional tags, and conversation.

2. **Real-time intentional connection**  
   Users send 15-second live invitations instead of randomly matching or endlessly swiping.

3. **Missed invite recovery**  
   If a live invite is missed, the receiver can still find it later in their missed invite list.

4. **Progressive trust**  
   Deeper sharing happens after acceptance and conversation.

5. **Private media by design**  
   One-time-view image/GIF/video messages are server-enforced.

6. **Safety as core UX**  
   Blocking, reporting, invite locks, account identity, and moderation are MVP requirements.

## Target MVP User

A user who wants to meet or talk to new people without the pressure of showing photos first.

## Initial Market Recommendation

Start with one or two markets only:
- Hong Kong
- Japan

Reasons:
- The founder understands both markets.
- Text-first social behavior is familiar.
- Anonymous or semi-anonymous social apps can work, but need strong trust/safety.

## MVP Outcome

The MVP is successful if a user can:

1. Create an account.
2. Create a text-first profile (one-line signal).
3. Optionally add tags from Profile.
4. Post a short text card.
5. Discover other users through text posts and tags.
6. Send a 15-second live invitation.
7. Accept a live invitation within 15 seconds.
8. Create a chat immediately after live acceptance.
9. Miss an invite and see it in the missed invite list.
10. Accept a missed invite if the user's plan allows it.
11. Chat privately.
12. Send a one-time-view media message.
13. Block/report unsafe behavior.

## Correct Invite Model

### Live Invite

- A live invite lasts 15 seconds.
- If accepted within 15 seconds, chat starts immediately.
- Live acceptance does not consume missed-invite accept quota.
- Free/Silver users can have 1 active outgoing live invite at a time.
- Gold users can have 2 active outgoing live invites at a time.
- Live invite slots are released when the invite is accepted, cancelled, expired, or moved to missed.

### Missed Invite

- If not accepted within 15 seconds, the invite becomes missed.
- Missed invites appear in the receiver's invite list.
- Free users have limited missed-invite accepts per day.
- Paid users can accept missed invites instantly or with higher/no limits.
- Accepting a missed invite creates a chat.

## Product Roadmap

### Phase 0 — Foundation

- Finalize MVP scope.
- Create Supabase project.
- Create iOS project.
- Add documentation and agent files.
- Define schema and API contracts.

### Phase 1 — Auth & Onboarding

- Sign in with Apple / Google / X.
- Age gate (18+).
- Create profile (handle, display name, one-line signal).
- Account deletion.
- Tags are not required at sign-up. They are added later from Profile.

### Phase 2 — Discovery

- Create text post.
- User-created profile tags (managed from Profile, not at sign-up).
- Discovery feed.
- Profile preview.
- Feed filtering by tag / city / language.

### Phase 3 — 15-Second Live Invitations

- Send live invite.
- Receiver gets 15-second countdown.
- Accept live invite.
- Decline live invite.
- Auto-move expired live invite to missed list.
- Enforce concurrent live invite slots.
- Free/Silver: 1 outgoing live invite at a time.
- Gold: 2 outgoing live invites at a time.
- Chat room auto-created on live acceptance.

### Phase 4 — Missed Invites

- Missed invite list.
- Accept missed invite.
- Free missed-invite accept quota.
- Paid instant missed invite acceptance.
- Missed invite expiry.
- Active chat limit checks.

### Phase 5 — Chat

- Chat list.
- Chat room.
- Text messages.
- Realtime updates.
- Message pagination.
- Report/block from chat.

### Phase 6 — One-Time Media

- Image/GIF/video upload.
- Private Supabase Storage bucket.
- View-once toggle.
- Server-enforced open flow.
- Signed URL.
- Viewed state.
- Cleanup job.

### Phase 7 — Safety

- Report profile/post/message/media.
- Block user.
- Auto-hide reported content.
- Basic admin review using Supabase table.

### Phase 8 — Subscription

- Free/Gold plan limits (final values in `MONETIZATION_PLAN.md`).
  - Free: 1 outgoing live invite, 1 missed-invite accept/day, 5 active chats, 1 priority invite per 2 days.
  - Gold: 2 outgoing live invites, unlimited missed-invite accepts, unlimited active chats, 3 priority invites/day.
  - Tags stay capped at 3 for everyone.
- Backend enforcement only — client never trusts a cached plan.
- StoreKit 2 or RevenueCat decision deferred. Do not implement RevenueCat yet.
- Paywall UI deferred until plan limits show measurable conversion intent.
- No AdMob / Google Ads SDK in the binary.
- Google Ads / Apple Search Ads as external acquisition channels post-TestFlight.

### Phase 9 — TestFlight

- QA pass.
- App Store privacy labels.
- Screenshots.
- App metadata.
- Feedback loop.

## Important Business Risks

### Cold Start Risk

Social apps need active users. Start narrow:
- one city
- one language community
- one niche
- seeded prompts
- daily writing prompts

### Live Invite Timing Risk

A 15-second window is exciting but can be frustrating if push notifications are delayed.

Solution:
- show in-app live invite cards when user is active
- use push notifications when app is backgrounded
- move missed invites to a list after timeout
- do not make live accept consume missed-invite quota

### Abuse Risk

High-frequency sending can create spam.

Solution:
- concurrent live invite locks
- short cooldown after repeated ignored invites
- block/report
- rate limiting by IP/device/account
- ban logic

### Privacy Expectation Risk

One-time-view media cannot fully prevent screenshots.

Solution:
- Be honest in UX.
- Say: “Can only be opened once. Screenshots may still be possible.”
- Server-enforce access.

### Scope Risk

Do not build Android, group chat, or AI matching before the iOS MVP loop is validated.

## Taipei beta product adjustment (2026-05)

Profile identity for the Taipei beta is **one honest line + three lightweight "conversation fit" chips**. Tags stay capped at 3. Discovery sort uses the chips as a soft hint only; rows are never filtered out by chips. The chips give discovery enough context to disambiguate "what kind of chat is this" without turning the profile into a dating-app condition table.

The three chips (all optional, all settable later):

- **Connection intent** — `slow_chat`, `new_friends`, `dating_open`, `not_sure`
- **Lifestyle rhythm** — `early_bird`, `night_owl`, `weekend_person`, `flexible`
- **Conversation domain** — `daily_life`, `food_cafes`, `city_walks`, `music_films`, `work_study`, `travel`, `values`, `random`

A fourth column `opener_prompt` (≤120 chars, free text) is reserved for a future surface; the chat opener currently uses the partner's `conversation_domain` as its seed.

### Voice — deliberately excluded from phase 1

No voice messaging, no voice rooms, no mandatory voice intro. The product hypothesis is that the friction of voice deters the audience Taipei research surfaced (people wanting low-pressure text first). A future iteration may unlock voice notes **only after mutual interest + mutual opt-in** — never as an onboarding requirement or as a one-sided send.

### Safety / anti-off-platform copy

Quiet but visible safety copy lives in two places: the onboarding screen (`safety.taipei.onboarding`) and the new-chat opener card (`safety.taipei.chat`). Copy steers users to keep early conversation inside Getalong, avoid rushing LINE swaps or money topics, and use block/report when something feels off. No content moderation / auto-warning logic in this phase.
