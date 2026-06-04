// scripts/seed-demo-data.ts
//
// Repeatable demo-data seeder for Getalong. Creates a small batch of
// clearly-fictional demo profiles around an optional "viewer" user so
// the iOS app can be screenshot for App Store / TestFlight with
// Discovery, Invites, Chats, and Profile screens that look populated.
//
// SAFETY (read before running):
//   * All demo profiles carry `getalong_id LIKE 'demo_%'` and an
//     auth email `demo+NN@getalong.local`. The clear script targets
//     ONLY these markers — it will never touch a real user account.
//   * The viewer account (passed in via DEMO_VIEWER_USER_ID) is NEVER
//     modified or deleted by either script.
//   * No real names, photos, phone numbers, or social handles.
//   * Display names are deliberately abstract ("Sunset 04") so they
//     can't be mistaken for a real public user.
//   * No NSFW, sexual, exploitative, scam, or harmful content.
//   * Demo bios + messages are all fictional Taiwan-friendly Traditional
//     Chinese, drawn from the curated lists at the bottom of this file.
//   * No media is seeded (one-time-view bytes are produced by the live
//     app, not by this script). Media QA must be done manually.
//
// USAGE
//   SUPABASE_URL=https://<ref>.supabase.co \
//   SUPABASE_SERVICE_ROLE_KEY=sb_secret_... \
//   DEMO_VIEWER_USER_ID=<your-uuid>          # optional
//   LIVE_WINDOW_SECONDS=15                   # optional, default 15
//     deno run --allow-env --allow-net scripts/seed-demo-data.ts
//
// If DEMO_VIEWER_USER_ID is omitted the script only seeds standalone
// Discovery profiles — invites and chats are skipped (those need a
// counterparty).
//
// LIVE INVITE WINDOW
//   Default matches production exactly: 15 s. This means a screenshot
//   has to be ready before you run the seed, OR you bump
//   LIVE_WINDOW_SECONDS to (e.g.) 120 just while you set up the shot —
//   but be aware that a longer window misrepresents the real product
//   in the screenshot. The mark/expire cron will move the invite to
//   `missed` once `live_expires_at` passes. This setting only affects
//   the column value on the one seeded invite — no production code
//   path is changed.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";

// ──────────────────────────────────────────────────────────────────────
//  Env + client
// ──────────────────────────────────────────────────────────────────────

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL")?.trim() ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
const DEMO_VIEWER_USER_ID       = Deno.env.get("DEMO_VIEWER_USER_ID")?.trim() ?? "";
const LIVE_WINDOW_SECONDS       = Number(Deno.env.get("LIVE_WINDOW_SECONDS") ?? 15);

function die(message: string): never {
  console.error(`✖ ${message}`);
  Deno.exit(1);
}

if (!SUPABASE_URL)              die("SUPABASE_URL is required.");
if (!SUPABASE_SERVICE_ROLE_KEY) die("SUPABASE_SERVICE_ROLE_KEY is required.");
if (!Number.isFinite(LIVE_WINDOW_SECONDS) || LIVE_WINDOW_SECONDS < 1) {
  die("LIVE_WINDOW_SECONDS must be a positive integer.");
}

// Never log the service-role key. Print just the URL + a digest tail of
// the key so the operator can confirm which credentials are in use
// without leaking them into the terminal scrollback.
console.log(`→ Target: ${SUPABASE_URL}`);
console.log(`→ Service role key digest tail: …${
  SUPABASE_SERVICE_ROLE_KEY.slice(-6)
}`);
if (DEMO_VIEWER_USER_ID) {
  console.log(`→ Viewer: ${DEMO_VIEWER_USER_ID} (will receive invites + chats)`);
} else {
  console.log("→ Viewer: none (skipping invites + chats)");
}
console.log(
  `→ Live invite window: ${LIVE_WINDOW_SECONDS} s` +
  (LIVE_WINDOW_SECONDS === 15 ? "  (matches production)" : "  (DEMO override — does not match production 15 s)")
);

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

// ──────────────────────────────────────────────────────────────────────
//  Idempotency: refuse to double-seed unless --force
// ──────────────────────────────────────────────────────────────────────

const force = Deno.args.includes("--force");

{
  const { data, error } = await sb
    .from("profiles")
    .select("id, getalong_id")
    .like("getalong_id", "demo_%")
    .limit(1);
  if (error) die(`pre-check failed: ${error.message}`);
  if (data && data.length > 0 && !force) {
    die(
      "Demo data already present. Run scripts/clear-demo-data.ts --confirm " +
      "first, or pass --force to add more demo profiles on top.",
    );
  }
}

// ──────────────────────────────────────────────────────────────────────
//  Content (curated, fictional, Taiwan-friendly Traditional Chinese)
// ──────────────────────────────────────────────────────────────────────

interface SeedProfile {
  slug: string;             // demo_01 .. demo_14
  displayName: string;
  bio: string;
  gender: "male" | "female";
  connectionIntent: "slow_chat" | "new_friends" | "dating_open" | "not_sure";
  lifestyleRhythm:  "early_bird" | "night_owl" | "weekend_person" | "flexible";
  conversationDomain:
    | "daily_life" | "food_cafes" | "city_walks" | "music_films"
    | "work_study" | "travel" | "values" | "random";
  tags: string[];
}

// 14 profiles. Display names are deliberately non-human placeholders
// (no real person could be confused for them) but short enough to
// look like reasonable handles on a Discovery card.
const PROFILES: SeedProfile[] = [
  { slug: "demo_01", displayName: "Quiet 01", bio: "下班後喜歡找一間安靜咖啡店，把今天慢慢收好。",
    gender: "female", connectionIntent: "slow_chat", lifestyleRhythm: "night_owl",
    conversationDomain: "food_cafes", tags: ["台北", "咖啡", "安靜"] },
  { slug: "demo_02", displayName: "Riverwalk 02", bio: "週末如果沒有安排，通常會去河邊散步。",
    gender: "male", connectionIntent: "new_friends", lifestyleRhythm: "weekend_person",
    conversationDomain: "city_walks", tags: ["台北", "散步", "河邊"] },
  { slug: "demo_03", displayName: "Latenight 03", bio: "比起熱鬧派對，更喜歡可以慢慢聊天的晚上。",
    gender: "female", connectionIntent: "slow_chat", lifestyleRhythm: "night_owl",
    conversationDomain: "values", tags: ["夜貓", "安靜", "日常"] },
  { slug: "demo_04", displayName: "Sunset 04", bio: "最近想把生活過得簡單一點，但不要太無聊。",
    gender: "male", connectionIntent: "not_sure", lifestyleRhythm: "flexible",
    conversationDomain: "daily_life", tags: ["日常", "週末"] },
  { slug: "demo_05", displayName: "Listener 05", bio: "喜歡聽別人講他們真正喜歡的東西。",
    gender: "female", connectionIntent: "new_friends", lifestyleRhythm: "flexible",
    conversationDomain: "values", tags: ["音樂", "電影", "書店"] },
  { slug: "demo_06", displayName: "Walker 06", bio: "如果你也喜歡城市散步，我們應該會有話題。",
    gender: "male", connectionIntent: "dating_open", lifestyleRhythm: "weekend_person",
    conversationDomain: "city_walks", tags: ["台北", "散步", "週末"] },
  { slug: "demo_07", displayName: "Notebook 07", bio: "有時候一句很普通的話，反而最容易記住。",
    gender: "female", connectionIntent: "slow_chat", lifestyleRhythm: "early_bird",
    conversationDomain: "values", tags: ["日常", "書店"] },
  { slug: "demo_08", displayName: "Honest 08", bio: "想認識不用一直表演自己的人。",
    gender: "male", connectionIntent: "slow_chat", lifestyleRhythm: "flexible",
    conversationDomain: "values", tags: ["日常", "安靜", "工作後"] },
  { slug: "demo_09", displayName: "Filmclub 09", bio: "最近在重看一些老電影，想找人一起聊聊。",
    gender: "female", connectionIntent: "new_friends", lifestyleRhythm: "night_owl",
    conversationDomain: "music_films", tags: ["電影", "音樂", "夜貓"] },
  { slug: "demo_10", displayName: "Wanderer 10", bio: "下個季節想去一個沒去過的地方，慢慢走。",
    gender: "male", connectionIntent: "dating_open", lifestyleRhythm: "flexible",
    conversationDomain: "travel", tags: ["旅行", "散步", "週末"] },
  { slug: "demo_11", displayName: "Brewer 11", bio: "週末會自己沖一杯，邊喝邊看書。",
    gender: "female", connectionIntent: "slow_chat", lifestyleRhythm: "weekend_person",
    conversationDomain: "food_cafes", tags: ["咖啡", "書店", "週末"] },
  { slug: "demo_12", displayName: "Worker 12", bio: "工作很多的時候，反而想找人聊一點不工作的事。",
    gender: "male", connectionIntent: "not_sure", lifestyleRhythm: "early_bird",
    conversationDomain: "work_study", tags: ["工作後", "日常"] },
  { slug: "demo_13", displayName: "Gallery 13", bio: "最近喜歡逛小展覽，看別人怎麼看世界。",
    gender: "female", connectionIntent: "new_friends", lifestyleRhythm: "weekend_person",
    conversationDomain: "random", tags: ["展覽", "週末", "台北"] },
  { slug: "demo_14", displayName: "Kitchen 14", bio: "最近想學煮幾道簡單的菜，吃飯比較有儀式感。",
    gender: "male", connectionIntent: "slow_chat", lifestyleRhythm: "early_bird",
    conversationDomain: "food_cafes", tags: ["美食", "日常"] },
];

// Three demo chat scripts (sender labels A/B map to viewer/demo at runtime).
const CHAT_SCRIPTS: { partnerSlug: string; lines: { from: "viewer" | "demo"; body: string }[] }[] = [
  {
    partnerSlug: "demo_01",
    lines: [
      { from: "viewer", body: "你那句關於咖啡店的話很有畫面。" },
      { from: "demo",   body: "哈哈，因為我真的常常下班後去找安靜的地方。" },
      { from: "viewer", body: "台北有推薦的店嗎？" },
      { from: "demo",   body: "最近喜歡中山附近的小店，人不多的時候很舒服。" },
    ],
  },
  {
    partnerSlug: "demo_06",
    lines: [
      { from: "viewer", body: "城市散步聽起來很適合週末。" },
      { from: "demo",   body: "對，我喜歡沒有目的地走一段路。" },
      { from: "viewer", body: "我也是，尤其是晚上風比較舒服的時候。" },
    ],
  },
  {
    partnerSlug: "demo_08",
    lines: [
      { from: "viewer", body: "你說不想一直表演自己，這句很準。" },
      { from: "demo",   body: "現在很多社交 app 都像在做履歷。" },
      { from: "viewer", body: "所以一句自然的話反而比較真實。" },
    ],
  },
];

// Three missed invite scripts + one live-pending. Sender = demo, receiver = viewer.
const INCOMING_LIVE_FROM_SLUG = "demo_05";
const MISSED_FROM_SLUGS       = ["demo_03", "demo_09", "demo_13"];

// ──────────────────────────────────────────────────────────────────────
//  Helpers
// ──────────────────────────────────────────────────────────────────────

/// Mirror of the iOS / backend tag normalization used by Discovery's
/// shared-tag intersection. Lowercase + collapse whitespace + ≤30 chars.
function normalizeTag(raw: string): string {
  return raw.toLowerCase().trim().replace(/\s+/g, " ").slice(0, 30);
}

/// Create an auth user and matching profile row. Email-confirms so the
/// user is immediately usable. Returns the new profile id.
async function createDemoAuthUser(p: SeedProfile): Promise<string> {
  const email = `demo+${p.slug.replace("demo_", "")}@getalong.local`;
  const { data, error } = await sb.auth.admin.createUser({
    email,
    email_confirm: true,
    user_metadata: { demo_seed: true, slug: p.slug },
    // We never sign in as these users; password just satisfies the
    // Admin API contract.
    password: crypto.randomUUID() + crypto.randomUUID(),
  });
  if (error || !data.user) {
    throw new Error(`createUser ${p.slug} failed: ${error?.message ?? "no user returned"}`);
  }
  return data.user.id;
}

// ──────────────────────────────────────────────────────────────────────
//  Seed
// ──────────────────────────────────────────────────────────────────────

console.log("\n→ Seeding profiles…");

const slugToId = new Map<string, string>();

for (const p of PROFILES) {
  const id = await createDemoAuthUser(p);
  slugToId.set(p.slug, id);

  const { error: insertErr } = await sb.from("profiles").insert({
    id,
    getalong_id:         p.slug,
    display_name:        p.displayName,
    bio:                 p.bio,
    gender:              p.gender,
    gender_visible:      true,
    city:                "台北",
    country:             "台灣",
    language_codes:      ["zh-Hant"],
    connection_intent:   p.connectionIntent,
    lifestyle_rhythm:    p.lifestyleRhythm,
    conversation_domain: p.conversationDomain,
  });
  if (insertErr) {
    throw new Error(`insert profile ${p.slug} failed: ${insertErr.message}`);
  }

  // Tags. Normalize client-side because `normalized_tag` is NOT
  // auto-populated by a trigger — the column has a CHECK constraint
  // but the value is the caller's responsibility (see migration 0006).
  const tagRows = p.tags.map((tag) => ({
    profile_id:     id,
    tag,
    normalized_tag: normalizeTag(tag),
  }));
  if (tagRows.length > 0) {
    const { error: tagErr } = await sb.from("profile_tags").insert(tagRows);
    if (tagErr) {
      throw new Error(`insert tags ${p.slug} failed: ${tagErr.message}`);
    }
  }

  console.log(`  ✓ ${p.slug} (${p.displayName})`);
}

// ──────────────────────────────────────────────────────────────────────
//  Viewer-side: invites + chats (only when DEMO_VIEWER_USER_ID set)
// ──────────────────────────────────────────────────────────────────────

if (DEMO_VIEWER_USER_ID) {
  // Validate viewer exists and is a real (non-demo) profile.
  const { data: viewer, error: viewerErr } = await sb
    .from("profiles")
    .select("id, getalong_id")
    .eq("id", DEMO_VIEWER_USER_ID)
    .maybeSingle();
  if (viewerErr) die(`viewer lookup failed: ${viewerErr.message}`);
  if (!viewer)   die(`DEMO_VIEWER_USER_ID ${DEMO_VIEWER_USER_ID} not found in profiles.`);

  console.log(`\n→ Seeding 1 incoming live invite + ${MISSED_FROM_SLUGS.length} missed invites…`);

  const nowIso = new Date().toISOString();
  const liveExpiresIso = new Date(
    Date.now() + LIVE_WINDOW_SECONDS * 1_000
  ).toISOString();

  // 1 incoming live_pending invite — sender = demo_05, receiver = viewer.
  {
    const senderId = slugToId.get(INCOMING_LIVE_FROM_SLUG)!;
    const { error } = await sb.from("invites").insert({
      sender_id:        senderId,
      receiver_id:      DEMO_VIEWER_USER_ID,
      status:           "live_pending",
      invite_type:      "normal",
      delivery_mode:    "live",
      live_expires_at:  liveExpiresIso,
      created_at:       nowIso,
    });
    if (error) throw new Error(`insert live invite failed: ${error.message}`);
    console.log(`  ✓ live_pending from ${INCOMING_LIVE_FROM_SLUG} (expires in ${LIVE_WINDOW_SECONDS}s)`);
  }

  // Missed invites — set live_expires_at in the past, missed_expires_at
  // ~24h ahead so they're still actionable.
  for (const slug of MISSED_FROM_SLUGS) {
    const senderId      = slugToId.get(slug)!;
    const liveExpired   = new Date(Date.now() - 3_600_000).toISOString();   // 1h ago
    const missedExpires = new Date(Date.now() + 86_400_000).toISOString();  // 24h ahead
    const createdAt     = new Date(Date.now() - 3_600_000 - 60_000).toISOString();
    const { error } = await sb.from("invites").insert({
      sender_id:          senderId,
      receiver_id:        DEMO_VIEWER_USER_ID,
      status:             "missed",
      invite_type:        "normal",
      delivery_mode:      "live",
      live_expires_at:    liveExpired,
      missed_expires_at:  missedExpires,
      created_at:         createdAt,
    });
    if (error) throw new Error(`insert missed invite ${slug} failed: ${error.message}`);
    console.log(`  ✓ missed from ${slug}`);
  }

  // Chats — 3 active rooms with staggered timestamps so the chat list
  // sorts naturally (newest first).
  console.log(`\n→ Seeding ${CHAT_SCRIPTS.length} chat rooms…`);
  let chatOffsetMinutes = 0;
  for (const script of CHAT_SCRIPTS) {
    const partnerId = slugToId.get(script.partnerSlug)!;
    const roomCreated = new Date(
      Date.now() - (chatOffsetMinutes + 60) * 60_000
    ).toISOString();

    const { data: room, error: roomErr } = await sb
      .from("chat_rooms")
      .insert({
        user_a:          DEMO_VIEWER_USER_ID,
        user_b:          partnerId,
        status:          "active",
        created_at:      roomCreated,
        last_message_at: roomCreated,
      })
      .select("id")
      .single();
    if (roomErr || !room) {
      throw new Error(`insert chat_room with ${script.partnerSlug} failed: ${roomErr?.message ?? "no row"}`);
    }

    // Insert messages with staggered created_at (oldest first) so each
    // chat reads as a natural conversation. Step is 4 minutes per line.
    let lineOffset = script.lines.length * 4;
    let lastMessageAt = roomCreated;
    for (const line of script.lines) {
      const senderId = line.from === "viewer" ? DEMO_VIEWER_USER_ID : partnerId;
      const createdAt = new Date(
        Date.now() - (chatOffsetMinutes + lineOffset) * 60_000
      ).toISOString();
      const { error: msgErr } = await sb.from("messages").insert({
        room_id:      room.id,
        sender_id:    senderId,
        message_type: "text",
        body:         line.body,
        created_at:   createdAt,
      });
      if (msgErr) throw new Error(`insert message in ${script.partnerSlug} failed: ${msgErr.message}`);
      lastMessageAt = createdAt;
      lineOffset -= 4;
    }

    // Stamp the room's last_message_at to match the most recent message
    // so the chat list orders correctly.
    const { error: updErr } = await sb
      .from("chat_rooms")
      .update({ last_message_at: lastMessageAt })
      .eq("id", room.id);
    if (updErr) throw new Error(`stamp last_message_at ${script.partnerSlug} failed: ${updErr.message}`);

    console.log(`  ✓ chat with ${script.partnerSlug} (${script.lines.length} messages)`);
    chatOffsetMinutes += 30;
  }
} else {
  console.log("\n→ DEMO_VIEWER_USER_ID not set — skipping invites and chats.");
}

console.log("\n✓ Seed complete.");
console.log(
  `→ Cleanup: SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… ` +
  `deno run --allow-env --allow-net scripts/clear-demo-data.ts --confirm`
);
