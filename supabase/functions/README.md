# Edge Functions

These are the placeholder implementations for the 17 Edge Functions defined
in [`docs/EDGE_FUNCTIONS.md`](../../docs/EDGE_FUNCTIONS.md).

Each folder currently contains an `index.ts` stub that returns
`NOT_IMPLEMENTED`. Replace the stub with the real implementation.

## Functions

| Folder                  | Purpose                                                  |
| ----------------------- | -------------------------------------------------------- |
| `sendLiveInvite`        | Create a 15-second live invite + active invite lock.     |
| `acceptLiveInvite`      | Accept a `live_pending` invite within 15 s. Creates room.|
| `declineInvite`         | Decline a live or missed invite.                         |
| `cancelLiveInvite`      | Sender cancels their own active live invite.             |
| `markLiveInviteMissed`  | Convert one expired live invite to `missed`.             |
| `expireLiveInvites`     | Cron: convert all expired live invites to `missed`.      |
| `acceptMissedInvite`    | Accept missed invite (consumes free quota if free user). |
| `expireMissedInvites`   | Cron: expire old missed invites.                         |
| `getDiscoveryFeed`      | Paginated discovery posts with filtering.                |
| `createChatMessage`     | Create text/media message after participant checks.      |
| `requestMediaUpload`    | Hand client a private upload path & metadata.            |
| `openViewOnceMedia`     | Mark view-once viewed and return short signed URL.       |
| `deleteExpiredMedia`    | Cron: clean up viewed/expired/orphaned media.            |
| `reportContent`         | Create a moderation report.                              |
| `blockUser`             | Block another user, cancel/move active invites & chats.  |
| `syncSubscriptionStatus`| Sync IAP / RevenueCat → `subscriptions` table.           |
| `sendPushNotification`  | APNs sender (invite events, messages, etc.).             |

## Conventions

* Stable JSON contract via `_shared/response.ts`:
  * Success: `{ ok: true, data }`
  * Error:   `{ ok: false, error_code, message }`
* Sensitive writes use the **service role** key (bypasses RLS) and must
  enforce all checks themselves. Never expose the service role key to
  clients.
* Cron functions (`expireLiveInvites`, `expireMissedInvites`,
  `deleteExpiredMedia`) are intended to be invoked from a Supabase
  scheduled trigger or external cron.

## Local Dev

```bash
supabase start
supabase functions serve sendLiveInvite --no-verify-jwt # for testing
```
