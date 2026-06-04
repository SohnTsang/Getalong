# Demo Data — Getalong Screenshot Seeding

This is the operator manual for `scripts/seed-demo-data.ts` and
`scripts/clear-demo-data.ts`. The scripts exist for **App Store / TestFlight
screenshots only** — they populate Discovery, Invites, Chats, and Profile
with believable Taiwan-friendly Traditional Chinese content so the
screenshots look like a real app, then clean themselves up.

## 1. Purpose

iOS App Store / TestFlight review needs screenshots that show the
product working. The seeder creates 14 clearly-fictional demo
profiles, hashtags, fit chips, missed/live invites, and chat
threads — enough to fill every screenshot we ship. The cleaner
removes everything the seeder added, and only what the seeder added.

Use this for:

- **Discovery** — 14 cards with hero line, 1–3 fit chips, plain
  hashtags, gender badges, light + dark.
- **Invites tab — Live** — 1 incoming live invite that ticks down
  for `LIVE_WINDOW_MINUTES` (default 5 min), giving you enough time
  to compose a screenshot before it lapses to "missed."
- **Invites tab — Missed** — 3 actionable missed invites already
  past their live window.
- **Chats** — 3 active chat rooms with the viewer, each with a
  short realistic conversation.
- **Profile** — viewer's own profile is **not** touched; seed your
  own line, tags, and fit chips through the app first if you want
  the profile screen populated.

## 2. Safety rules

Read this section before running against any environment.

- **No real people.** Display names are deliberately placeholder
  ("Sunset 04", "Riverwalk 02") so no one can be confused with a
  public user. No real photos, phone numbers, social handles, or
  PII. All 14 demo users are 18+ by construction (no age field is
  ever set below the production threshold).
- **No harmful content.** Bios and chat messages are curated
  Taiwan-friendly Traditional Chinese. Nothing NSFW, sexual,
  exploitative, scam-like, violent, or abusive.
- **Marker is the `getalong_id` prefix `demo_`.** Cleanup ONLY
  touches rows whose profile has `getalong_id LIKE 'demo_%'`. Real
  users never start with `demo_` because the production handle
  generator emits `u` + 8 random base36 chars.
- **Viewer is never deleted.** Pass `DEMO_VIEWER_USER_ID` and the
  cleanup script skips that id even if (somehow) its `getalong_id`
  matches the demo prefix.
- **Service-role only.** Both scripts read `SUPABASE_SERVICE_ROLE_KEY`
  from env. The key is never printed (only the last 6 chars as a
  digest tail) and never written to any file the repo would commit.
- **No media seeding.** View-once media bytes are produced by the
  live iOS app via the upload + finalize Edge Functions. Faking
  storage objects from outside that path would bypass the security
  contract documented in `ONE_TIME_MEDIA_SECURITY.md`. For media
  screenshots, take them manually from a TestFlight build.
- **No reports or blocks seeded.** Block / report UI screenshots
  should be exercised manually against a throwaway demo account.
- **No schema migrations.** Demo data is inserted at runtime via
  the service-role client. No migration adds demo rows.

## 3. Required environment variables

| Var | Required? | Purpose |
|---|---|---|
| `SUPABASE_URL` | yes | Project URL, e.g. `https://gdqyjewtfvkchglvktuj.supabase.co` |
| `SUPABASE_SERVICE_ROLE_KEY` | yes | Service-role secret. Read-write everywhere; never commit. |
| `DEMO_VIEWER_USER_ID` | optional | UUID of an existing real user that should receive invites + chats. Omit to seed only standalone Discovery profiles. |
| `LIVE_WINDOW_SECONDS` | optional (default `15`) | Window for the seeded live invite's `live_expires_at`. **Default 15 s matches production exactly.** Override only if you must (e.g. `LIVE_WINDOW_SECONDS=120` while you set up a screenshot) — a longer window misrepresents the real product on the App Store. The seeder prints a warning whenever this value is not 15. Only affects the column value on the one seeded invite; no production code path is changed. |

If a required var is missing the script prints `✖ <var> is required`
and exits non-zero.

## 4. How to seed

Once-only setup: install Deno (the scripts use the same runtime as
the Edge Functions — `https://esm.sh/@supabase/supabase-js`).

```sh
# From the repo root.
export SUPABASE_URL=https://<project-ref>.supabase.co
export SUPABASE_SERVICE_ROLE_KEY=sb_secret_…
export DEMO_VIEWER_USER_ID=<your test account's UUID>   # optional but recommended
export LIVE_WINDOW_SECONDS=15                           # optional (default 15 = production parity)

deno run --allow-env --allow-net scripts/seed-demo-data.ts
```

If demo data already exists the script refuses to add more (so you
don't accumulate duplicate `demo_NN` handles). Pass `--force` to
add on top, or run the cleanup first.

## 5. How to clear

Default is **dry-run**: prints a summary of what would be deleted,
deletes nothing. Pass `--confirm` to execute.

```sh
# Dry run.
SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… \
  deno run --allow-env --allow-net scripts/clear-demo-data.ts

# Actually delete.
SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… \
  DEMO_VIEWER_USER_ID=<your uuid> \
  deno run --allow-env --allow-net scripts/clear-demo-data.ts --confirm
```

The cleanup deletes `auth.users` rows for every demo profile; the
existing `ON DELETE CASCADE` foreign keys take care of the rest:

```
auth.users  ──cascade──▶  profiles
                            ├─▶ profile_tags
                            ├─▶ invites (as sender or receiver)
                            └─▶ chat_rooms (as user_a or user_b)
                                    └─▶ messages
```

The viewer's account is never touched, demo profiles whose id
matches `DEMO_VIEWER_USER_ID` are skipped, and any real user with a
random `u*` handle is filtered out by the `LIKE 'demo_%'` predicate.

After the cascade fires, the script does NOT trust it — it re-queries
each table and prints residual counts:

```
→ Verifying cleanup…
  profiles (getalong_id LIKE 'demo_%')   : 0
  profile_tags  (profile_id in demo)     : 0
  invites       (sender_id  in demo)     : 0
  invites       (receiver_id in demo)    : 0
  chat_rooms    (user_a     in demo)     : 0
  chat_rooms    (user_b     in demo)     : 0
  messages      (sender_id  in demo)     : 0

✓ Cleanup complete and verified — no residual demo rows.
```

If any residual rows survive (e.g. a future migration changes a FK
from `ON DELETE CASCADE` to `SET NULL`), the script prints a
per-table breakdown and exits non-zero. The viewer's id is always
excluded from the residual count so an exempted viewer with a
demo-prefix handle doesn't trigger a false failure.

## 6. Screenshot states the seed produces

| Screen | What you get |
|---|---|
| Discovery list | 14 profile cards, mix of intent / rhythm / domain chips, plain `#tag` hashtags, gender badges. Some cards have all 3 chips, some 2, some 1, so you can pick which composition looks best for the App Store grid. |
| Discovery card detail (via Block / Report sheets) | Reachable from any card's overflow menu. |
| Invites — Live tab | 1 incoming live invite from `demo_05`, ticking down for `LIVE_WINDOW_SECONDS` (default 15 s = production parity). |
| Invites — Missed tab | 3 missed invites from `demo_03`, `demo_09`, `demo_13`. |
| Chats list | **7 active chat rooms** with the viewer: 1 hero + 2 medium + 4 short. Total **~62 messages** across all rooms. `last_message_at` staggered so the list orders newest→oldest naturally (hero ~10 min ago, mediums 3–5 h ago, shorts spread across yesterday + 1.5 days ago). |
| Chat room | The hero chat (`demo_01`, **22 messages**, 2-min stagger) is the long screenshot-friendly thread — cafe / after-work / text-vs-performance theme. Mediums: `demo_08` (social-app fatigue, **10 msgs**), `demo_11` (weekend / exhibition, **10 msgs**). Shorts: `demo_14` (music, **6 msgs**), `demo_12` (work, **5 msgs**), `demo_02` (river / city walk, **5 msgs**), `demo_07` (bookstore / quiet, **4 msgs**). |
| Chat language | Natural Taipei / Taiwan written Mandarin throughout — short casual sentences (`對啊` / `蠻` / `不一定` / `慢慢來` / `先不要太趕` / `感覺` / `有空再說`), no Cantonese tokens (`搵 嘅 啱傾 傾偈 傾落去 錯過咗 用緊`), no Threads slang, no Mainland-style phrasing, no romantic / sexual / scam / abusive content. Safe for App Store screenshot review. |
| Profile (viewer) | Not seeded — set this up manually in the app first if you want a hero line + chips + tags. |

## 7. Why no media is seeded

View-once chat media is the security boundary of the app. The bytes
live in private storage and are produced by an upload + finalize
flow that:

1. Mints a signed URL on the server side (`requestMediaUpload`).
2. Stamps `retention_until = created_at + 24h` and a moderation
   hold pointer.
3. Allows the receiver to open exactly once, at which point the
   media row is flipped to `viewed` and the bytes are scheduled for
   deletion by the cleanup cron (see `ONE_TIME_MEDIA_SECURITY.md`).

Inserting fake storage objects from a script bypasses that path,
which would (a) violate the security model and (b) leave orphan
bytes the cleanup cron doesn't know how to handle. Take media
screenshots manually from a TestFlight build instead.

## 8. Production warning

The scripts target whichever project `SUPABASE_URL` points to. They
do NOT distinguish local vs. remote. **Verify the URL before
running.** Running the seed against production permanently while
TestFlight is live is fine for screenshot prep, as long as you run
the cleanup afterwards — but if you forget the cleanup, you'll have
14 demo cards visible in real users' Discovery feeds. The cleanup
script is idempotent; running it twice is safe.

When in doubt, run the cleanup dry-run first against the same URL
to confirm whether demo data is currently present.

## 9. Note on the Free plan active-chat cap

A Free-plan viewer is normally capped at 5 active chats by the
`_ga_assert_active_chat_room_capacity` SQL helper. That helper is
only called from the `accept_live_invite` / `accept_missed_invite`
RPCs — there is no DB trigger or CHECK constraint on `chat_rooms`,
so service-role inserts (this seeder) bypass the cap cleanly. The
iOS Chats tab has no client-side cap on display, so the seeded
7 active chats render fine even on a Free plan account. The cap
will start to bite the moment you try to accept an 8th invite
through the live app, which is the intended product behaviour.

If you would rather screenshot a viewer who is "naturally" at 7
chats (i.e. plan-consistent), promote the test account to Gold by
running:

```sql
update public.profiles set plan = 'gold' where id = '<viewer uuid>';
```

…before the seed, and revert it after. This is a one-line change
that doesn't touch the seeder.
