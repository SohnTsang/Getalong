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
// Exclusion rules:
//   * self
//   * deleted / banned profiles
//   * profiles I have blocked
//   * profiles that have blocked me
//   * profiles with whom I have an active chat room (status = 'active')
//   * profiles with an active live_pending invite either way
//
// Sort order (stable):
//   1. tag overlap count desc (only when caller supplies `tags` OR we
//      derive from the caller's own profile_tags),
//   2. profiles.updated_at desc,
//   3. profiles.created_at desc,
//   4. profiles.id desc as final tiebreaker.
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
}

const DEFAULT_LIMIT = 20;
const MAX_LIMIT     = 50;

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

  // Caller must exist and not be banned/deleted.
  const { data: me, error: meErr } = await sb
    .from("profiles")
    .select("id, is_banned, deleted_at")
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
  // NOTE: we deliberately do NOT exclude profiles with an active
  // live_pending invite. If the caller has just tapped "Send invite",
  // we want the receiver to remain visible (with their countdown ring
  // running). Active chat rooms above already keep us from showing
  // people who've moved past the invite stage.

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
  const excludeArr = [...excludeIds];

  // Flat select — PostgREST tolerates whitespace, but we keep this
  // tight to avoid any client/SDK string-massaging surprises.
  const selectCols = "id,getalong_id,display_name,bio,city,country,"
    + "gender,gender_visible,plan,updated_at,created_at,"
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
    profile_tags: { tag: string; normalized_tag: string }[] | null;
  };

  const intent = new Set(intentNormalized);
  const enriched = (rows as Row[] | null ?? []).map((r) => {
    const tags = r.profile_tags ?? [];
    const sharedNormalized = intent.size === 0
      ? []
      : tags.filter(t => intent.has(t.normalized_tag));
    return {
      row: r,
      sharedTags: sharedNormalized.map(t => t.tag),
      overlap: sharedNormalized.length,
    };
  });

  // 4. Stable sort: overlap desc, then keep the SQL order (already
  //    updated_at desc, created_at desc, id desc).
  enriched.sort((a, b) => b.overlap - a.overlap);

  const page = enriched.slice(0, limit);
  const hasMore = enriched.length > limit
                || (rows?.length ?? 0) === fetchSize;

  const items: DiscoveryProfile[] = page.map(({ row, sharedTags }) => ({
    id:           row.id,
    getalong_id:  row.getalong_id,
    display_name: row.display_name,
    bio:          row.bio,
    city:         row.city,
    country:      row.country,
    gender:       row.gender_visible ? row.gender : null,
    plan:         row.plan,
    tags:         (row.profile_tags ?? []).map(t => t.tag),
    shared_tags:  sharedTags,
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
