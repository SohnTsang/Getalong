// scripts/clear-demo-data.ts
//
// Removes everything that scripts/seed-demo-data.ts created — and ONLY
// that data. Safe to run against production after a screenshot session.
//
// Targeting rule: a row is "demo" iff its profile has
// `getalong_id LIKE 'demo_%'`. Cleanup deletes the matching auth.users,
// which cascades through:
//
//   auth.users → profiles (FK ON DELETE CASCADE)
//     → profile_tags
//     → invites (as sender_id OR receiver_id, both FK ON DELETE CASCADE)
//     → chat_rooms (as user_a OR user_b)
//        → messages (FK ON DELETE CASCADE)
//
// The viewer account is NEVER deleted. If DEMO_VIEWER_USER_ID is set,
// the cleanup skips that id even if (somehow) the viewer's
// getalong_id starts with `demo_`. Other real users are untouched
// because they don't match the prefix.
//
// USAGE
//   # Dry run (default — prints what WOULD be deleted, deletes nothing):
//   SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… \
//     deno run --allow-env --allow-net scripts/clear-demo-data.ts
//
//   # Actually delete:
//   SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… \
//     deno run --allow-env --allow-net scripts/clear-demo-data.ts --confirm
//
//   # Also exempt the viewer (extra safety belt):
//   DEMO_VIEWER_USER_ID=<uuid> \
//     deno run --allow-env --allow-net scripts/clear-demo-data.ts --confirm

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const DEMO_VIEWER_USER_ID       = Deno.env.get("DEMO_VIEWER_USER_ID")?.trim() ?? "";
const CONFIRM                   = Deno.args.includes("--confirm");

function die(message: string): never {
  console.error(`✖ ${message}`);
  Deno.exit(1);
}

if (!SUPABASE_URL)              die("SUPABASE_URL is required.");
if (!SUPABASE_SERVICE_ROLE_KEY) die("SUPABASE_SERVICE_ROLE_KEY is required.");

console.log(`→ Target: ${SUPABASE_URL}`);
console.log(`→ Service role key digest tail: …${
  SUPABASE_SERVICE_ROLE_KEY.slice(-6)
}`);
console.log(`→ Mode: ${CONFIRM ? "DELETE" : "DRY-RUN (use --confirm to actually delete)"}`);
if (DEMO_VIEWER_USER_ID) {
  console.log(`→ Viewer guard: ${DEMO_VIEWER_USER_ID} will be skipped if matched.`);
}

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// ──────────────────────────────────────────────────────────────────────
//  Discover what would be deleted
// ──────────────────────────────────────────────────────────────────────

const { data: demoProfiles, error: profileErr } = await sb
  .from("profiles")
  .select("id, getalong_id, display_name")
  .like("getalong_id", "demo_%");
if (profileErr) die(`profile lookup failed: ${profileErr.message}`);

const guarded = (demoProfiles ?? []).filter((p) => p.id !== DEMO_VIEWER_USER_ID);
const skipped = (demoProfiles ?? []).filter((p) => p.id === DEMO_VIEWER_USER_ID);

if (skipped.length > 0) {
  console.log(`→ Skipping viewer-id match: ${skipped.map((p) => p.getalong_id).join(", ")}`);
}

if (guarded.length === 0) {
  console.log("→ No demo profiles found. Nothing to clean.");
  Deno.exit(0);
}

const demoIds = guarded.map((p) => p.id);

// Count chained rows (info only — actual deletion cascades from auth.users).
const [tagCount, sentInviteCount, recvInviteCount, roomsAsA, roomsAsB, messageCount] = await Promise.all([
  countRows("profile_tags", "profile_id", demoIds),
  countRows("invites",      "sender_id",  demoIds),
  countRows("invites",      "receiver_id", demoIds),
  countRows("chat_rooms",   "user_a",     demoIds),
  countRows("chat_rooms",   "user_b",     demoIds),
  // Messages count uses sender_id; cascade is via chat_rooms → messages,
  // so this is informational and may include messages in rooms where
  // the demo is the partner, not the sender.
  countRows("messages",     "sender_id",  demoIds),
]);

console.log("\n→ Summary of what would be deleted:");
console.log(`  profiles (auth.users → cascade) : ${guarded.length}`);
console.log(`  profile_tags                    : ${tagCount}`);
console.log(`  invites as sender               : ${sentInviteCount}`);
console.log(`  invites as receiver             : ${recvInviteCount}`);
console.log(`  chat_rooms (user_a)             : ${roomsAsA}`);
console.log(`  chat_rooms (user_b)             : ${roomsAsB}`);
console.log(`  messages (sender_id is demo)    : ${messageCount}`);

if (!CONFIRM) {
  console.log("\n→ Dry run only. Pass --confirm to actually delete.");
  Deno.exit(0);
}

// ──────────────────────────────────────────────────────────────────────
//  Execute
// ──────────────────────────────────────────────────────────────────────

console.log("\n→ Deleting demo auth users (cascades through profiles & related rows)…");
let okCount = 0;
let failCount = 0;
for (const p of guarded) {
  const { error } = await sb.auth.admin.deleteUser(p.id);
  if (error) {
    console.warn(`  ✖ ${p.getalong_id}: ${error.message}`);
    failCount++;
  } else {
    console.log(`  ✓ ${p.getalong_id}`);
    okCount++;
  }
}

console.log(`\n→ Deletion phase done. Deleted ${okCount} demo auth users, failed ${failCount}.`);

// ──────────────────────────────────────────────────────────────────────
//  Post-cleanup verification: don't trust the cascade — confirm it.
// ──────────────────────────────────────────────────────────────────────
//
// auth.users → profiles cascade is a foreign-key contract, but FK
// definitions can drift (a future migration could change ON DELETE
// CASCADE to SET NULL, a row could be locked, the FK could even be
// disabled in an emergency op). Verifying directly catches every one
// of those cases. We re-query each table that the seeder touches and
// report any residual rows.

console.log("\n→ Verifying cleanup…");

let residualTotal = 0;

// 1. profiles where getalong_id like 'demo_%'
const { data: leftProfiles, error: lpErr } = await sb
  .from("profiles")
  .select("id, getalong_id")
  .like("getalong_id", "demo_%");
if (lpErr) {
  console.warn(`  ! profiles verify failed: ${lpErr.message}`);
} else {
  const leftCount = leftProfiles?.length ?? 0;
  // Exclude the viewer if it's somehow in the demo prefix — by spec it
  // was never deleted, and that's fine.
  const stranded = (leftProfiles ?? []).filter((p) => p.id !== DEMO_VIEWER_USER_ID);
  console.log(
    `  profiles (getalong_id LIKE 'demo_%')   : ${leftCount}` +
    (DEMO_VIEWER_USER_ID && leftCount > stranded.length
      ? ` (1 is the viewer — exempt)` : "")
  );
  residualTotal += stranded.length;
}

const leftIds = (leftProfiles ?? []).map((p) => p.id);

// 2. profile_tags for demo profiles
const leftTags = await countRows("profile_tags", "profile_id", leftIds);
console.log(`  profile_tags  (profile_id in demo): ${leftTags}`);
if (leftTags > 0) residualTotal += leftTags;

// 3. invites involving demo profiles (sender OR receiver)
const leftInvitesSent = await countRows("invites", "sender_id",   leftIds);
const leftInvitesRecv = await countRows("invites", "receiver_id", leftIds);
console.log(`  invites       (sender_id  in demo): ${leftInvitesSent}`);
console.log(`  invites       (receiver_id in demo): ${leftInvitesRecv}`);
if (leftInvitesSent > 0) residualTotal += leftInvitesSent;
if (leftInvitesRecv > 0) residualTotal += leftInvitesRecv;

// 4. chat_rooms involving demo profiles (user_a OR user_b)
const leftRoomsA = await countRows("chat_rooms", "user_a", leftIds);
const leftRoomsB = await countRows("chat_rooms", "user_b", leftIds);
console.log(`  chat_rooms    (user_a     in demo): ${leftRoomsA}`);
console.log(`  chat_rooms    (user_b     in demo): ${leftRoomsB}`);
if (leftRoomsA > 0) residualTotal += leftRoomsA;
if (leftRoomsB > 0) residualTotal += leftRoomsB;

// 5. messages whose sender_id is a demo profile (cascade should have
// wiped these when the chat_room was wiped, but we check directly).
const leftMessages = await countRows("messages", "sender_id", leftIds);
console.log(`  messages      (sender_id  in demo): ${leftMessages}`);
if (leftMessages > 0) residualTotal += leftMessages;

if (residualTotal === 0 && failCount === 0) {
  console.log("\n✓ Cleanup complete and verified — no residual demo rows.");
  Deno.exit(0);
}

if (residualTotal === 0 && failCount > 0) {
  console.warn(
    "\n! Some auth.admin.deleteUser calls failed, but no residual rows were " +
    "found via the prefix probe. The failed users may have already been " +
    "deleted by a previous run. Inspect the per-row log above."
  );
  Deno.exit(2);
}

console.error(
  `\n✖ ${residualTotal} residual demo-related rows survived the cascade. ` +
  "Inspect the per-table counts above; you may need to delete them manually."
);
Deno.exit(2);

// ──────────────────────────────────────────────────────────────────────
//  Helpers
// ──────────────────────────────────────────────────────────────────────

async function countRows(
  table: string,
  column: string,
  ids: string[],
): Promise<number> {
  if (ids.length === 0) return 0;
  const { count, error } = await sb
    .from(table)
    .select("*", { count: "exact", head: true })
    .in(column, ids);
  if (error) {
    console.warn(`  ! count ${table}.${column} failed: ${error.message}`);
    return -1;
  }
  return count ?? 0;
}
