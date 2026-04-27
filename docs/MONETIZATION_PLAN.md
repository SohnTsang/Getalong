# Monetization Plan

## Recommendation

Use subscriptions first. **No in-app ads in MVP.** AdMob / Google Ads SDK
are explicitly out of scope. Google Ads as an external **acquisition**
channel (paid installs / brand search) is allowed *after* TestFlight, but
we add no advertising SDK to the binary.

## Correct Monetization Model

Getalong does not monetize by capping daily live invites sent. The model
is concurrent live-invite slots + missed-invite-accept quotas + active-chat
caps + Priority Invites.

## Plans (final)

### Free

| Limit | Value |
| --- | --- |
| Concurrent outgoing Live Invites | 1 |
| Missed-invite accepts | 1 / day |
| Active chats | **5 (cap)** |
| Profile tags | 3 (everyone) |
| Priority Invites | 1 / 2-day rolling window |
| Discovery visibility | standard |
| View-once media | allowed |
| Report / block / safety | allowed |

### Gold

| Limit | Value |
| --- | --- |
| Concurrent outgoing Live Invites | 2 |
| Missed-invite accepts | unlimited |
| Active chats | **unlimited** |
| Profile tags | 3 (same as Free) |
| Priority Invites | 3 / 1-day rolling window |
| Discovery visibility | standard today, mild boost later (TODO) |
| View-once media | allowed |
| Report / block / safety | allowed |

> Tags stay capped at 3 for everyone. Do not raise the Gold tag limit.
> Safety, basic chat after mutual connection, and view-once media are
> never paywalled.

A dormant `silver` plan tier still exists in helper functions for
forward compatibility but is not surfaced in the app.

## Backend Enforcement

The backend (Postgres RPCs called by Edge Functions with `service_role`)
is the source of truth for every plan limit. The client never trusts a
locally cached plan.

| Limit | Enforced by | Error code |
| --- | --- | --- |
| Concurrent live invite slots | `_ga_concurrent_live_slots(plan)` checked in `send_live_invite` | `LIVE_INVITE_SLOT_FULL` |
| Live invite expiry | `_ga_live_seconds()` + `expire_live_invites()` cron | `LIVE_INVITE_EXPIRED` |
| Missed-invite accept quota | `_ga_missed_accept_quota(plan)` checked in `accept_missed_invite` | `MISSED_ACCEPT_LIMIT_REACHED` |
| Active chat cap | `_ga_assert_active_chat_room_capacity(uid)` checked in `accept_live_invite` *and* `accept_missed_invite` for **both** sender and receiver | `ACTIVE_CHAT_LIMIT_REACHED` |
| Priority invite quota | `_ga_assert_priority_quota(uid)` (rolling window per plan) | `PRIORITY_INVITE_LIMIT_REACHED` |
| Tag cap (3) | `_ga_check_profile_tag_limit` BEFORE INSERT trigger | `TAG_LIMIT_REACHED` |

Plan helper functions live in `0005_invite_rpcs.sql` and
`0015_active_chat_limit_and_priority_invites.sql`.

## Priority Invites (schema only — no UI yet)

`priority_invite_usage` records every send for rolling-window accounting.
Helpers `_ga_priority_quota`, `_ga_priority_window`,
`_ga_priority_used_in_window`, `_ga_assert_priority_quota`, and
`_ga_record_priority_invite` are in place.

When the send flow ships:
- Likely 30-second live window instead of 15.
- Maybe a stronger receiver-side card treatment (no Heymandi copy).
- Use `_ga_assert_priority_quota` + `_ga_record_priority_invite` in the
  same transaction so a failure rolls both back.
- Do NOT change `send_live_invite`'s normal flow.

## Payment Stack

Decision deferred. Both StoreKit 2 and RevenueCat remain on the table.
**Do not add RevenueCat or StoreKit code yet** — backend rules in this
file are sufficient until the paywall feature is greenlit.

## Ads

- **No** AdMob SDK / Google Ads SDK / IDFA tracking in the binary.
- **No** in-app ads in MVP.
- Google Ads / Apple Search Ads as **external** acquisition channels
  (paid installs, brand search) may be used post-TestFlight. These are
  marketing spend; they do not change the app code.
