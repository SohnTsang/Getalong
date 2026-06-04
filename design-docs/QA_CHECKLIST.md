# QA Checklist

## Auth

- User can sign up.
- User can sign in.
- User can sign out.
- User can delete account.
- Deleted account cannot appear in feed.
- Banned user cannot post/invite/message.

## Onboarding

- Age gate works.
- Underage user cannot proceed.
- User can create profile.
- Required fields validate.
- Onboarding does not ask for tags. Tags are added later from Profile.

## Tags (Profile)

- User can open the tag editor from Profile.
- User can add a tag (1–30 chars).
- User cannot add a duplicate tag (case-insensitive normalization).
- User cannot exceed 3 tags per profile.
- User can remove a tag.
- Tags persist across launches.
- Tags are visible only on non-deleted, non-banned profiles.

## Discovery

- User can create post.
- User can see feed.
- Hidden posts do not appear.
- Deleted posts do not appear.
- Posts from blocked users do not appear.
- Pagination works.
- Empty feed state works.

### Discovery server-side exposure ranking (updated 2026-06)

Hard exclusions (never appear): self, banned/deleted, blocked either direction, **active** chat partners, **live `live_pending`** invite partners. Everything else is a SOFT penalty summing into `priorityBand` (ascending). Seen-memory is now SERVER-SIDE in `discovery_exposures` — refresh diversity survives app restarts and new sessions, not just the current screen.

Penalties: `deletedRoomPenalty` (8 if left ≤30 d, else 0); `exposurePenalty` (24 ≤10 min / 16 ≤1 h / 8 ≤24 h / else 0, from most recent `shown_at`); `repeatPenalty` ((24h-count − 1)×4, cap 16); `clientSeenPenalty` (10 for `exclude_ids` session hint). `seenPenalty = max(clientSeen, exposure) + repeat`; `priorityBand = deletedRoom + seenPenalty`. Representative ordering (lower = better): fresh-unseen `0` < left-chat `8` < client-hint-only `10` < shown-recently `24+`.

- A and B have an **active** chat room → B does NOT appear in A's Discovery (hard exclusion preserved).
- A blocks B → B remains hard-excluded.
- A has a live (un-expired) `live_pending` invite with B → B remains hard-excluded.
- A fetches Discovery → the 10 returned profiles each get a `discovery_exposures` row (`viewer_id=A`, `source='discovery'`).
- A refreshes seconds later → those 10 are now `exposurePenalty=24` and drop to the bottom; fresh unseen profiles (band 0) rise to the top.
- A profile shown on several refreshes accrues `repeatPenalty` (capped 16) and sinks further, but **still appears** when the pool is thin (never hard-excluded).
- A deletes the chat with B yesterday, never having been re-shown B → **B appears at band 8, ABOVE any recently-shown card (band ≥24) and above the client-hint-only cards (band 10).** This is the regression-fix bullet (the old strong-20 band buried B).
- A deleted the chat with B 40 days ago → band 0; B ranks identically to a fresh stranger.
- A refreshes 5 times with no new strangers entering the pool → previously-shown cards keep filling the page rather than the feed going empty.
- A seen profile naturally returns to band 0 once its exposures age past 24 h (and out of the table entirely after 14 d).
- `cleanup_old_discovery_exposures()` removes rows older than 14 days (daily cron `getalong_cleanup_old_discovery_exposures_daily`).
- **Fail-open:** if the exposure SELECT or INSERT fails, the feed still returns (exposure penalties default to 0). Exposure never empties the feed.
- Within a band, the existing `overlap → fitScore → jitter` tie-break still applies; the band itself is the primary key.
- No iOS UI change — exposure logic is entirely server-side. iOS still sends `exclude_ids` (now a session hint only) and does NOT persist seen history.

## 15-Second Live Invites

- User can send live invite.
- Live invite shows 15-second countdown.
- Receiver can accept within 15 seconds.
- Receiver can decline.
- Accepted live invite creates chat immediately.
- Accepted live invite does not consume missed-invite accept quota.
- Live invite cannot be accepted after 15 seconds.
- Expired live invite becomes missed.
- Sender's active invite lock is released after accept.
- Sender's active invite lock is released after decline.
- Sender's active invite lock is released after timeout.
- Free/Silver user cannot send second concurrent live invite.
- Gold user can send up to two concurrent live invites.
- Gold user cannot send third concurrent live invite.
- User cannot invite self.
- User cannot invite blocked user.
- Duplicate live invite to same receiver is blocked.
- Banned user cannot send live invite.

## Missed Invites

- Missed invite appears in receiver's missed invite list.
- Free user can accept missed invite within daily limit.
- Free user cannot accept missed invite after limit is reached.
- Paid user can accept missed invite instantly or within plan rules.
- Accepting missed invite creates chat.
- Missed invite cannot be accepted after expiry.
- Accepting missed invite consumes quota only for free users.
- Accepting live invite never consumes missed quota.

### Invite-card visual parity with Discovery (added 2026-06)

The Invite-tab user card now mirrors the Discovery card's profile-identity hierarchy. Mode-specific controls (countdown ring, Accept button, decline/menu, received timestamp) remain.

- Incoming **live** invite card renders: gender badge → one honest line → conversation-fit chips (if any) → plain `#tag #tag` hashtags (if any) → countdown ring trailing.
- **Missed** invite card renders the same hierarchy plus: received-relative timestamp footer + Accept button + 3-dot menu.
- Card with no conversation-fit chips (legacy profile) hides the chip row entirely — no empty space.
- Card with no tags hides the hashtag row entirely.
- Card with both empty falls back to gender badge + line only (no breakage).
- Shared hashtags (tags the caller also has) render in `GAColors.accent`; other tags render in `textTertiary`.
- The shared-tag intersection is case-insensitive and uses the same `ProfileTag.normalize` rule the backend uses (lowercase + collapsed whitespace, ≤30 chars), so `Coffee` on the sender side matches `coffee` on the caller side.
- Hashtags are plain text — no capsule, no border, no icon, no "Tags" label (same treatment as Discovery).
- Conversation-fit chips use the existing `GAColors.fit{Intent,Rhythm,Domain}{Text,Bg}` tokens — coral / sage / wheat — identical to Discovery.
- No raw enum strings (e.g. `slow_chat`) appear; chips show `localizedShort`.
- Existing live-invite countdown still ticks down based on `live_expires_at`.
- Existing Accept / Decline / report / block actions still work; no behavioural change.
- Existing missed-badge count still updates on accept / decline / dedupe.
- Existing payloads without `connection_intent` / `lifestyle_rhythm` / `conversation_domain` decode successfully (legacy senders just show no chip row).
- Light & dark modes render the fit chip palette correctly.

## Chat

- Chat list loads.
- Chat room opens.
- Text message sends.
- Realtime receive works.
- Message pagination works.
- Non-participant cannot read messages.
- Block stops future messages.

## One-Time Media

- Image sends.
- GIF sends.
- Video sends.
- Receiver opens once.
- Receiver cannot reopen.
- Sender cannot fake receiver view.
- Third user cannot open.
- Viewed placeholder appears.
- Expired media unavailable.
- Storage object remains immediately after the receiver closes the viewer (24-hour private retention).
- Cleanup cron deletes storage only after `retention_until` has elapsed.
- Cleanup cron skips rows with `moderation_hold_at IS NOT NULL`.
- `deleteExpiredMedia` cron (`getalong_delete_expired_media_every_2_minutes`) is registered and firing every 2 minutes (`cron.job` + `cron.job_run_details`).
- Calling `deleteExpiredMedia` with no auth fails 401.
- Calling `deleteExpiredMedia` with a wrong `x-cleanup-secret` fails 401.
- Calling `deleteExpiredMedia` with the correct scheduler secret succeeds and removes due bytes.
- Calling `deleteExpiredMedia` with the service-role Bearer still succeeds (ad-hoc / CI path).

## Safety

- Report profile works.
- Report post works.
- Report message works (preserves attached media as moderation hold).
- Report media works (puts media on moderation hold).
- Report chat_room works (puts every still-existing media row in that room on hold, in one UPDATE).
- Report user from chat with `context_room_id` preserves only that room's media; media in other rooms with the same user are still deleted by retention.
- Reporting already-deleted media still succeeds (no recovery, no error).
- Duplicate report still ensures the moderation hold is in place.
- Block user works.
- Blocked user cannot invite/message.
- Active invites between blocked users are cancelled or made unavailable.
- Auto-hide threshold works.

## Subscription

- Free live invite slot limit works.
- Silver live invite slot limit works.
- Gold two-live-invite benefit works.
- Free missed-invite accept quota works.
- Paid missed-invite acceptance works.
- Active chat limits work.
- Backend enforces limits.
- Paywall appears at correct moments.
- Subscription restore works.

## Release

- App does not expose service role key.
- RLS enabled on every table.
- Private media bucket is not public.
- Account deletion works.
- Privacy labels ready.

## Taipei beta (2026-05)

- New user can complete onboarding with the one-line input + chips.
- New user can skip any/all of the three fit chips.
- 18+ checkbox is required; "Continue" is disabled until ticked.
- Existing users are NOT forced through a broken re-onboarding (legacy NULL chip columns are valid).
- Profile page shows the new "Conversation fit" section.
- Tapping the fit section opens the edit sheet; saving persists the three chips.
- Tapping a selected chip in the edit sheet clears it (server receives explicit JSON null).
- Discovery card shows the honest line as hero text.
- Fit chips appear as capsule/badge elements (the only badge-style row).
- Hashtags appear as simple plain `#tag` text below the chips, no capsule, no border, no icon, no label.
- Hashtag row hides completely when the partner has no tags.
- Discovery card with chips + tags, with tags only (no chips), and with no chips + no tags all render without breaking.
- Empty fit fields don't crash or break Discovery cards.
- Discovery feed still returns the same 10-card batch behaviour.
- New empty chat shows the message composer directly — no "Start easy" / opener card / suggestion list / auto-fill.
- Existing chats continue to render messages, attachments, and the composer normally.
- Sending the first message works; realtime delivery to the partner unchanged.
- Block / report / view-once media still build and behave unchanged.
- No raw enum strings (e.g. `slow_chat`) appear anywhere in the UI.
- No new voice UI appears.
- Traditional Chinese strings contain no banned Cantonese tokens (搵, 嘅, 啱傾, 傾偈, 傾落去, 錯過咗, 用緊).
- `grep -r "chat\.opener\|safety\.taipei\.chat" ios/Getalong --include="*.swift"` returns no matches.
- Light and dark modes both render Discovery cards (hero + chips + hashtags) and the chat composer.
- `xcodebuild` succeeds for the Getalong scheme.
