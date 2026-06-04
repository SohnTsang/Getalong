// getDiscoveryFeed — Getalong Edge Function (Discovery v0).
//
// Body: {
//   tags?: string[],   // optional: prioritise candidates whose tags overlap
//   limit?: number,    // default 20, max 50
//   cursor?: string    // opaque cursor returned by a previous call
// }
//
// Returns:
// {
//   ok: true,
//   data: {
//     items: DiscoveryProfile[],
//     next_cursor: string | null,
//     has_more: boolean
//   }
// }
//
// Exclusion rules (HARD — these candidates never appear):
//   * self
//   * deleted / banned profiles
//   * profiles I have blocked
//   * profiles that have blocked me
//   * profiles with whom I have an active chat room (status = 'active')
//   * profiles with whom I have a live_pending invite either direction
//     (so the same user doesn't show up as sendable on a refresh while
//      the invite is still ticking down)
//
// Recently DELETED chat-room partners and already-seen profiles are
// NOT hard-excluded. They apply SOFT penalties that sum into a single
// `priorityBand`. Product rules:
//
//   * Fresh + unseen candidates rank highest.
//   * Recently / repeatedly shown candidates rank lower.
//   * Recently-left chat partners rank lower (but ABOVE repeated
//     recently-shown cards).
//   * No demotion is permanent — thin pools still surface penalized
//     candidates, and seen users naturally return as exposure ages.
//
// Seen memory is now SERVER-SIDE (table `discovery_exposures`), not the
// client. After each request we record one exposure row per returned
// profile; the next request reads the viewer's last-24h exposures to
// compute the penalty. This is production-stable across refreshes, app
// restarts, and sessions. The client's `exclude_ids` is downgraded to a
// best-effort SESSION HINT (the cards currently on screen) and only ever
// raises the penalty, never lowers it.
//
// Penalty components (per candidate; see constants below):
//   * deletedRoomPenalty — left-chat partner within 30 d → 8, else 0.
//   * exposurePenalty    — server exposure recency of the MOST RECENT
//                          shown_at: ≤10 min → 24, ≤1 h → 16,
//                          ≤24 h → 8, else 0.
//   * repeatPenalty      — (exposures in last 24 h − 1) × 4, capped 16.
//   * clientSeenPenalty  — in caller `exclude_ids` → 10, else 0 (hint).
//
//   seenPenalty   = max(clientSeenPenalty, exposurePenalty) + repeatPenalty
//   priorityBand  = deletedRoomPenalty + seenPenalty
//
// `max(...)` avoids double-counting the client hint against the server
// record (the client card is also a recent exposure). Representative
// ordering (lower = better):
//
//      0   fresh + unseen                          ← strongest
//      8   left-chat (≤30 d), never shown          ← above any shown card
//     10   shown only via client hint (exclude_ids)
//     24   shown once in last 10 min
//     32   shown twice in last 10 min (24 + 4×… capped) etc.
//
// A left-chat partner (8) therefore always outranks a repeatedly-shown
// card — the regression we proved against live data (the old strong
// 20-band buried a just-left partner below repeated seen cards).
//
// Fail-open: if the exposure read fails the feed still returns with
// exposure/repeat penalties = 0 (client hint still applies). If the
// exposure write fails the feed still returns. Exposure never causes an
// empty feed.
//
// Sort order (stable):
//   1. priorityBand asc — combined band is the primary key.
//   2. tag overlap desc — wavelength signal within a band.
//   3. fitScore desc — Taipei beta fit chips as tertiary signal.
//   4. jitter asc — per-request random tie-break for variety.
//
// We opt for offset pagination keyed by a small JSON cursor — simpler than
// keyset for v0 and cheap at expected sizes. The cursor is opaque to the
// client and base64url-encoded.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";

interface Body {
  tags?: string[];
  limit?: number;
  cursor?: string;
  /// SESSION HINT only — the IDs the iOS client is currently showing.
  /// Adds a small `clientSeenPenalty` (max'd with the server exposure
  /// penalty, never summed) so it can't double-count. The authoritative
  /// seen memory is the server `discovery_exposures` table, not this.
  /// Never hard-filtered.
  exclude_ids?: string[];
}

interface DiscoveryProfile {
  id: string;
  getalong_id: string;
  display_name: string;
  bio: string | null;
  city: string | null;
  country: string | null;
  gender: string | null;        // null when gender_visible = false
  plan: string;
  tags: string[];
  /// Internal-only hint — clients may show "you may get along over X" but
  /// must not render this as a percentage. Always included for parity with
  /// the iOS card's `sameWavelength` chip.
  shared_tags: string[];
  /// Taipei beta conversation-fit chips. Any of the three may be null
  /// (legacy rows / users who skipped during onboarding). These are
  /// SOFT context — used as a sort hint only, never to filter rows.
  connection_intent: string | null;
  lifestyle_rhythm: string | null;
  conversation_domain: string | null;
}

// Discovery returns 10 cards per page by default. Smaller pages mean the
// user sees fresher candidates after each refresh and the post-fetch
// tag-overlap sort runs over a smaller set (cheaper). Clients may
// override up to MAX_LIMIT for a denser scroll, but the iOS app uses
// the default.
const DEFAULT_LIMIT = 10;
const MAX_LIMIT     = 50;

// Deleted-chat-room soft penalty. A single flat band (no 7-day "strong"
// tier) so a left-chat partner sits at 8 — below fresh-unseen (0) but
// ABOVE any recently-/repeatedly-shown card. The old strong 20-band
// buried a just-left partner below repeated seen cards; that is the
// regression this design removes.
const DELETED_ROOM_PENALTY_DAYS = 30;
const DELETED_ROOM_PENALTY      = 8;
const MS_PER_DAY = 86_400_000;

// Server-side exposure history (`discovery_exposures`). The MOST RECENT
// shown_at picks the recency tier; the COUNT in the last 24 h drives the
// repeat penalty.
const EXPOSURE_LOOKBACK_MS    = 24 * 60 * 60 * 1000;
const EXPOSURE_PENALTY_10MIN  = 24;   // shown within 10 minutes
const EXPOSURE_PENALTY_1HOUR  = 16;   // shown within 1 hour
const EXPOSURE_PENALTY_24HOUR = 8;    // shown within 24 hours
const REPEAT_PENALTY_STEP     = 4;    // per additional exposure after the 1st
const REPEAT_PENALTY_CAP      = 16;   // max repeat contribution
// Skip re-inserting an exposure for a profile shown this recently, so a
// rapid manual refresh doesn't inflate the repeat count.
const EXPOSURE_DEDUP_MS       = 60_000;

// Client `exclude_ids` session hint. Max'd with the server exposure
// penalty (not summed) so the on-screen cards still rank below fresh
// candidates even on the very first session before any exposure row
// exists, without double-counting once the server record catches up.
const SEEN_CARD_PENALTY = 10;

function decodeCursor(cursor: string | undefined): { offset: number } {
  if (!cursor) return { offset: 0 };
  try {
    const padded = cursor + "===".slice((cursor.length + 3) % 4);
    const json = atob(padded.replace(/-/g, "+").replace(/_/g, "/"));
    const obj = JSON.parse(json) as { offset?: number };
    if (typeof obj.offset === "number" && obj.offset >= 0) {
      return { offset: Math.min(obj.offset, 10_000) };
    }
  } catch { /* ignore */ }
  return { offset: 0 };
}

function encodeCursor(offset: number): string {
  const json = JSON.stringify({ offset });
  return btoa(json).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const body = await readJson<Body>(req);
  const limit = clamp(Number(body.limit ?? DEFAULT_LIMIT), 1, MAX_LIMIT);
  const { offset } = decodeCursor(body.cursor);

  const sb = admin();

  // Caller must exist and not be banned/deleted. Also pull the caller's
  // own fit chips so we can compute the soft sort hint below.
  const { data: me, error: meErr } = await sb
    .from("profiles")
    .select("id, is_banned, deleted_at, connection_intent, lifestyle_rhythm, conversation_domain")
    .eq("id", userId)
    .maybeSingle();
  if (meErr) return fail("INTERNAL_ERROR", meErr.message, 500);
  if (!me)   return fail("PROFILE_NOT_FOUND", "Profile not found.", 404);
  if (me.is_banned || me.deleted_at !== null)
    return fail("USER_BANNED", "Account restricted.", 403);

  // 1. Build the set of user_ids to exclude.
  const excludeIds = new Set<string>([userId]);

  // Each side-channel query: log + ignore on error so a single bad
  // table query never tanks the whole feed. Worst case the user sees
  // a partner they've already blocked / chatted with — far better than
  // an empty feed with a generic error.
  {
    const { data, error } = await sb
      .from("blocks").select("blocked_id").eq("blocker_id", userId);
    if (error) console.warn("blocksOut:", error.message);
    for (const r of data ?? []) excludeIds.add(r.blocked_id);
  }
  {
    const { data, error } = await sb
      .from("blocks").select("blocker_id").eq("blocked_id", userId);
    if (error) console.warn("blocksIn:", error.message);
    for (const r of data ?? []) excludeIds.add(r.blocker_id);
  }
  {
    const { data, error } = await sb
      .from("chat_rooms")
      .select("user_a, user_b")
      .eq("status", "active")
      .or(`user_a.eq.${userId},user_b.eq.${userId}`);
    if (error) console.warn("active rooms:", error.message);
    for (const r of data ?? []) {
      excludeIds.add(r.user_a === userId ? r.user_b : r.user_a);
    }
  }

  // Live-pending invite partners (either direction). Discovery should
  // not surface the same user as sendable while a 15-second invite is
  // still ticking — otherwise tapping "Send invite", refreshing, and
  // tapping again would race against the in-flight invite. The Invite
  // tab is the right place to see live-pending counterparties.
  {
    const nowIso = new Date().toISOString();
    const { data, error } = await sb
      .from("invites")
      .select("sender_id, receiver_id")
      .eq("status", "live_pending")
      .gt("live_expires_at", nowIso)
      .or(`sender_id.eq.${userId},receiver_id.eq.${userId}`);
    if (error) console.warn("live_pending invites:", error.message);
    for (const r of data ?? []) {
      excludeIds.add(r.sender_id === userId ? r.receiver_id : r.sender_id);
    }
  }

  // Recently DELETED chat-room partners. NOT added to excludeIds — these
  // candidates remain eligible. We only build a map of partner_id ->
  // most-recent deleted_at so the enrichment step can apply a soft
  // ranking penalty. Scoped to the penalty window (30 d) because anything
  // older receives no penalty anyway; this keeps the query small as the
  // deleted-rooms table grows.
  const deletedRoomMap = new Map<string, string>();
  {
    const cutoffIso = new Date(
      Date.now() - DELETED_ROOM_PENALTY_DAYS * MS_PER_DAY
    ).toISOString();
    const { data, error } = await sb
      .from("chat_rooms")
      .select("user_a, user_b, deleted_at")
      .eq("status", "deleted")
      .not("deleted_at", "is", null)
      .gte("deleted_at", cutoffIso)
      .or(`user_a.eq.${userId},user_b.eq.${userId}`);
    if (error) console.warn("deleted rooms:", error.message);
    for (const r of data ?? []) {
      const partnerId = r.user_a === userId ? r.user_b : r.user_a;
      // Multiple deleted rooms with the same partner can exist over
      // time — keep the most recent so the penalty reflects how long
      // it's been since they last walked away.
      const prev = deletedRoomMap.get(partnerId);
      if (!prev || (r.deleted_at as string) > prev) {
        deletedRoomMap.set(partnerId, r.deleted_at as string);
      }
    }
  }

  // Server-side Discovery exposure history — the authoritative seen
  // memory. Pull this viewer's exposures in the last 24 h and aggregate
  // per shown profile into { count, latestMs }. FAIL-OPEN: on error we
  // leave the map empty (exposure/repeat penalties = 0) and still serve
  // the feed; the client `exclude_ids` hint still applies. Ordered newest
  // first and capped — the repeat penalty saturates at 5 exposures, so we
  // never need an unbounded scan.
  const exposureMap = new Map<string, { count: number; latestMs: number }>();
  {
    const sinceIso = new Date(Date.now() - EXPOSURE_LOOKBACK_MS).toISOString();
    const { data, error } = await sb
      .from("discovery_exposures")
      .select("profile_id, shown_at")
      .eq("viewer_id", userId)
      .gte("shown_at", sinceIso)
      .order("shown_at", { ascending: false })
      .limit(2000);
    if (error) {
      console.warn("discovery_exposures fetch (fail-open, seenPenalty=0):", error.message);
    } else {
      for (const r of data ?? []) {
        const ms = new Date(r.shown_at as string).getTime();
        const prev = exposureMap.get(r.profile_id);
        if (!prev) {
          exposureMap.set(r.profile_id, { count: 1, latestMs: ms });
        } else {
          prev.count += 1;
          if (ms > prev.latestMs) prev.latestMs = ms;
        }
      }
    }
  }

  // 2. Tag intent: caller-supplied filters take precedence; otherwise we
  //    use the caller's own tags so people see folks who share their
  //    wavelength.
  let intentNormalized: string[] = [];
  if (body.tags && body.tags.length > 0) {
    intentNormalized = body.tags
      .map(s => normalizeTag(s))
      .filter(s => s.length > 0)
      .slice(0, 20);
  } else {
    const { data: myTags } = await sb
      .from("profile_tags")
      .select("normalized_tag")
      .eq("profile_id", userId);
    intentNormalized = (myTags ?? []).map(r => r.normalized_tag);
  }

  // 3. Pull a generous page of candidate profiles. We over-fetch so that
  //    after exclusion + sorting we still have a stable page worth of
  //    results.
  const fetchSize = Math.min(MAX_LIMIT * 4, 200);

  // Client session hint: caller's currently-visible IDs become a small
  // `clientSeenPenalty` during enrichment below (max'd with the server
  // exposure penalty, not summed). They are NOT removed from the
  // candidate pool, so a thin pool still surfaces them. The server
  // `discovery_exposures` history is the authoritative seen-memory; this
  // hint just covers the on-screen cards before the next exposure read.
  const seenIds = new Set(
    Array.isArray(body.exclude_ids)
      ? body.exclude_ids.filter((s) => typeof s === "string").slice(0, 50)
      : []
  );
  const excludeArr = [...excludeIds];

  // Flat select — PostgREST tolerates whitespace, but we keep this
  // tight to avoid any client/SDK string-massaging surprises.
  const selectCols = "id,getalong_id,display_name,bio,city,country,"
    + "gender,gender_visible,plan,updated_at,created_at,"
    + "connection_intent,lifestyle_rhythm,conversation_domain,"
    + "profile_tags(tag,normalized_tag)";

  let q = sb
    .from("profiles")
    .select(selectCols)
    .eq("is_banned", false)
    .is("deleted_at", null)
    .order("created_at", { ascending: false })
    .range(offset, offset + fetchSize - 1);

  // not.in needs each UUID quoted with double-quotes inside the
  // PostgREST tuple to be parsed as a literal string. Without quotes,
  // a stray hyphen in a UUID has been observed to confuse the parser
  // on some Postgres / PostgREST versions.
  if (excludeArr.length > 0) {
    const quoted = excludeArr.map((u) => `"${u}"`).join(",");
    q = q.not("id", "in", `(${quoted})`);
  }

  const { data: rows, error } = await q;
  if (error) {
    console.error("profiles fetch:", error.message);
    return fail("INTERNAL_ERROR", error.message, 500);
  }

  type Row = {
    id: string;
    getalong_id: string;
    display_name: string;
    bio: string | null;
    city: string | null;
    country: string | null;
    gender: string | null;
    gender_visible: boolean;
    plan: string;
    updated_at: string | null;
    created_at: string;
    connection_intent: string | null;
    lifestyle_rhythm: string | null;
    conversation_domain: string | null;
    profile_tags: { tag: string; normalized_tag: string }[] | null;
  };

  const intent = new Set(intentNormalized);
  const myIntent = me.connection_intent  as string | null;
  const myRhythm = me.lifestyle_rhythm   as string | null;
  const myDomain = me.conversation_domain as string | null;
  const nowMs = Date.now();
  const enriched = ((rows ?? []) as unknown as Row[]).map((r) => {
    const tags = r.profile_tags ?? [];
    const sharedNormalized = intent.size === 0
      ? []
      : tags.filter(t => intent.has(t.normalized_tag));
    // Taipei beta soft ranking. NEVER a hard filter — any candidate
    // with score 0 still rides through; we only break ties in the
    // direction of "more compatible fit chips".
    //   +2 same conversation_domain
    //   +1 compatible lifestyle_rhythm (same, or either side flexible)
    //   +1 compatible connection_intent (same, or either side not_sure)
    let fitScore = 0;
    if (myDomain && r.conversation_domain && myDomain === r.conversation_domain) {
      fitScore += 2;
    }
    if (myRhythm && r.lifestyle_rhythm) {
      if (myRhythm === r.lifestyle_rhythm
          || myRhythm === "flexible"
          || r.lifestyle_rhythm === "flexible") {
        fitScore += 1;
      }
    }
    if (myIntent && r.connection_intent) {
      if (myIntent === r.connection_intent
          || myIntent === "not_sure"
          || r.connection_intent === "not_sure") {
        fitScore += 1;
      }
    }

    // Soft penalty for partners I recently left a chat with. Active
    // rooms are already hard-excluded above; this only sees rows where
    // status='deleted'. Flat band (8) — below fresh-unseen (0), above
    // any recently-/repeatedly-shown card.
    let deletedRoomPenalty = 0;
    const lastDeletedIso = deletedRoomMap.get(r.id);
    if (lastDeletedIso) {
      const ageDays = (nowMs - new Date(lastDeletedIso).getTime()) / MS_PER_DAY;
      if (ageDays <= DELETED_ROOM_PENALTY_DAYS) {
        deletedRoomPenalty = DELETED_ROOM_PENALTY;
      }
    }

    // Server exposure penalty. Recency tier from the MOST RECENT
    // shown_at; repeat penalty from the COUNT in the last 24 h.
    const exp = exposureMap.get(r.id);
    let exposurePenalty = 0;
    let repeatPenalty = 0;
    if (exp) {
      const ageMin = (nowMs - exp.latestMs) / 60_000;
      if (ageMin <= 10)        exposurePenalty = EXPOSURE_PENALTY_10MIN;
      else if (ageMin <= 60)   exposurePenalty = EXPOSURE_PENALTY_1HOUR;
      else if (ageMin <= 1440) exposurePenalty = EXPOSURE_PENALTY_24HOUR;
      repeatPenalty = Math.min(
        REPEAT_PENALTY_CAP,
        Math.max(0, exp.count - 1) * REPEAT_PENALTY_STEP,
      );
    }

    // Client `exclude_ids` session hint. Max'd with the server exposure
    // penalty (not summed) to avoid double-counting the same card, then
    // the repeat penalty is added. priorityBand is the primary sort key.
    const clientSeenPenalty = seenIds.has(r.id) ? SEEN_CARD_PENALTY : 0;
    const seenPenalty = Math.max(clientSeenPenalty, exposurePenalty) + repeatPenalty;
    const priorityBand = deletedRoomPenalty + seenPenalty;

    return {
      row: r,
      sharedTags: sharedNormalized.map(t => t.tag),
      overlap: sharedNormalized.length,
      fitScore,
      deletedRoomPenalty,
      exposurePenalty,
      repeatPenalty,
      clientSeenPenalty,
      seenPenalty,
      priorityBand,
      // Stable random tie-breaker per request, so two profiles with
      // identical scores don't always appear in the same order across
      // refreshes. Computed once here so the sort is stable.
      jitter: Math.random(),
    };
  });

  // 4. Stable sort. priorityBand (deletedRoomPenalty + seenPenalty,
  //    where seenPenalty = max(clientSeen, exposure) + repeat) ascending
  //    is the primary key. Within a band the usual overlap → fitScore →
  //    jitter ordering applies. We do NOT hard-filter anything past the
  //    hard-exclusion list — exposed and recently-left candidates remain
  //    eligible and just sort lower, so a thin pool always fills.
  enriched.sort((a, b) => {
    if (a.priorityBand !== b.priorityBand) return a.priorityBand - b.priorityBand;
    if (b.overlap      !== a.overlap)      return b.overlap      - a.overlap;
    if (b.fitScore     !== a.fitScore)     return b.fitScore     - a.fitScore;
    return a.jitter - b.jitter;
  });

  // Step 4a (refresh-diversity hard-ish filter) deliberately removed
  // — its split-and-fallback behavior caused the bug where a fresh
  // pool of repeats would still bury a recently-left partner. The
  // priorityBand above is now the only diversity mechanism.

  const page = enriched.slice(0, limit);
  const hasMore = enriched.length > limit
                || (rows?.length ?? 0) === fetchSize;

  // 5. Record exposures for the profiles we're about to return — the
  //    authoritative server seen-memory the next request reads. FAIL-OPEN:
  //    a write error is logged and the feed is still returned. Dedup: skip
  //    a profile shown within the last EXPOSURE_DEDUP_MS so a rapid manual
  //    refresh doesn't inflate the repeat count (we reuse exposureMap,
  //    already loaded for ranking — no extra query).
  if (page.length > 0) {
    const toInsert = page
      .filter(({ row }) => {
        const exp = exposureMap.get(row.id);
        return !exp || (nowMs - exp.latestMs) > EXPOSURE_DEDUP_MS;
      })
      .map(({ row }) => ({
        viewer_id:  userId,
        profile_id: row.id,
        source:     "discovery",
      }));
    if (toInsert.length > 0) {
      const { error: insErr } = await sb
        .from("discovery_exposures")
        .insert(toInsert);
      if (insErr) {
        console.warn(
          `discovery_exposures insert (fail-open) rows=${toInsert.length} ` +
          `message=${insErr.message ?? "-"} — feed still returned.`,
        );
      }
    }
  }

  const items: DiscoveryProfile[] = page.map(({ row, sharedTags }) => ({
    id:                  row.id,
    getalong_id:         row.getalong_id,
    display_name:        row.display_name,
    bio:                 row.bio,
    city:                row.city,
    country:             row.country,
    gender:              row.gender_visible ? row.gender : null,
    plan:                row.plan,
    tags:                (row.profile_tags ?? []).map(t => t.tag),
    shared_tags:         sharedTags,
    connection_intent:   row.connection_intent,
    lifestyle_rhythm:    row.lifestyle_rhythm,
    conversation_domain: row.conversation_domain,
  }));

  return ok({
    items,
    next_cursor: hasMore ? encodeCursor(offset + limit) : null,
    has_more:    hasMore,
  });
});

function clamp(n: number, lo: number, hi: number): number {
  if (!Number.isFinite(n)) return lo;
  return Math.max(lo, Math.min(hi, Math.floor(n)));
}

/// Mirrors the trigger that sets profile_tags.normalized_tag on insert.
function normalizeTag(s: string): string {
  return s.toLowerCase().trim().replace(/\s+/g, " ").slice(0, 30);
}
