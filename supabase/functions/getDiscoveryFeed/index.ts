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
//   * profiles already visible in the caller's current list
//     (best-effort, only if enough other candidates exist)
//
// Recently DELETED chat-room partners are NOT hard-excluded; they
// sort into a lower band. The product rule for early-beta liquidity
// is: don't show someone immediately after leaving a chat with them,
// but never let "deleted partners" empty the Discovery pool — if the
// available 0-penalty candidates are thin, deleted partners surface
// to fill the page.
//
// Penalty bands (see DELETED_ROOM_* constants below):
//   * deleted_at within 7 days  → 20 (strong band)
//   * deleted_at within 30 days → 8  (weak band)
//   * older than 30 days / none → 0  (fresh band)
//
// Sort order (stable):
//   1. deletedRoomPenalty asc — the penalty IS the primary sort key.
//      Any 0-penalty candidate ranks above every >0-penalty candidate
//      regardless of how strong their tag overlap or fit-chip match
//      would otherwise be. Recently deleted partners only surface
//      after the entire fresh band is exhausted on the page.
//   2. tag overlap desc — wavelength signal wins within a band.
//   3. fitScore desc — Taipei beta fit chips as tertiary signal.
//   4. jitter asc — per-request random tie-break for refresh variety.
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
  /// IDs the iOS client is currently displaying. Excluded for refresh
  /// diversity *only when there are enough other candidates* — if we'd
  /// run out of profiles, we relax this and let already-visible IDs
  /// come back.
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

// Deleted-chat-room soft penalty. Tuned so a strong-penalty candidate
// only beats a fresh candidate when the fresh candidate has zero tag
// overlap AND lower fitScore — i.e. they only resurface when the
// alternative is genuinely worse, or when there are no alternatives.
const DELETED_ROOM_STRONG_PENALTY_DAYS = 7;
const DELETED_ROOM_WEAK_PENALTY_DAYS   = 30;
const DELETED_ROOM_STRONG_PENALTY      = 20;
const DELETED_ROOM_WEAK_PENALTY        = 8;
const MS_PER_DAY = 86_400_000;

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
  // ranking penalty. Scoped to the weak-penalty window (30 d) because
  // anything older receives no penalty anyway; this keeps the query
  // small as the deleted-rooms table grows.
  const deletedRoomMap = new Map<string, string>();
  {
    const cutoffIso = new Date(
      Date.now() - DELETED_ROOM_WEAK_PENALTY_DAYS * MS_PER_DAY
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

  // Refresh-diversity exclude: caller's currently-visible IDs. Applied
  // *only* if removing them still leaves us with at least `limit`
  // candidates after the hard exclusions (self/blocks/active-rooms/
  // live-pending). When we'd otherwise return too few, we relax this
  // and let some already-seen profiles come back rather than hand
  // back an empty feed.
  const visibleIds = new Set(
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
  const enriched = (rows as Row[] | null ?? []).map((r) => {
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

    // Soft penalty BAND for partners I recently left a chat with.
    // Active rooms are already hard-excluded above; this only sees
    // rows where status='deleted'. The band — not a combined score —
    // is the primary sort key below, so any fresh (band-0) candidate
    // ranks above every band-8 or band-20 candidate regardless of
    // their tag overlap or fit-chip match.
    let deletedRoomPenalty = 0;
    const lastDeletedIso = deletedRoomMap.get(r.id);
    if (lastDeletedIso) {
      const ageDays = (nowMs - new Date(lastDeletedIso).getTime()) / MS_PER_DAY;
      if (ageDays <= DELETED_ROOM_STRONG_PENALTY_DAYS) {
        deletedRoomPenalty = DELETED_ROOM_STRONG_PENALTY;
      } else if (ageDays <= DELETED_ROOM_WEAK_PENALTY_DAYS) {
        deletedRoomPenalty = DELETED_ROOM_WEAK_PENALTY;
      }
    }

    return {
      row: r,
      sharedTags: sharedNormalized.map(t => t.tag),
      overlap: sharedNormalized.length,
      fitScore,
      deletedRoomPenalty,
      // Stable random tie-breaker per request, so two profiles with
      // identical scores don't always appear in the same order across
      // refreshes. Computed once here so the sort is stable.
      jitter: Math.random(),
    };
  });

  // 4. Stable sort. The deleted-room penalty is the *primary* sort key
  //    (ascending), so candidates partition cleanly into three bands —
  //    fresh (0) above weak (8) above strong (20). Within a band the
  //    usual overlap → fitScore → jitter ordering applies. This is
  //    stricter than a combined score: a recently-deleted partner with
  //    high tag overlap still ranks below every fresh stranger, which
  //    is the product rule for early-beta liquidity (fresh always wins
  //    when fresh exists; deleted only surfaces to fill thin pools).
  enriched.sort((a, b) => {
    if (a.deletedRoomPenalty !== b.deletedRoomPenalty) {
      return a.deletedRoomPenalty - b.deletedRoomPenalty;
    }
    if (b.overlap  !== a.overlap)  return b.overlap  - a.overlap;
    if (b.fitScore !== a.fitScore) return b.fitScore - a.fitScore;
    return a.jitter - b.jitter;
  });

  // 4a. Refresh-diversity step: if the caller passed exclude_ids and
  //     enough alternates exist, prefer fresh candidates over repeating
  //     last refresh's set. Otherwise fall through and include everyone.
  let candidates = enriched;
  if (visibleIds.size > 0) {
    const fresh  = enriched.filter((e) => !visibleIds.has(e.row.id));
    const repeat = enriched.filter((e) =>  visibleIds.has(e.row.id));
    if (fresh.length >= limit) {
      candidates = fresh;
    } else {
      // Not enough fresh candidates — top up with repeats so we still
      // return up to `limit` rather than returning an empty page.
      candidates = [...fresh, ...repeat];
    }
  }

  const page = candidates.slice(0, limit);
  const hasMore = candidates.length > limit
                || (rows?.length ?? 0) === fetchSize;

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
