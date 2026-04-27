// getTagSuggestions — Getalong Edge Function.
//
// Returns two lists for the tag editor:
//   * featured — top 20 normalised tags across the platform with their
//                use counts, ordered by count desc.
//   * recent   — the caller's last 20 tags from profile_tag_history,
//                deduped by normalized_tag, most-recent first.
//
// Only safe, aggregate data leaves the function (a tag string + a count;
// for recent, the user's own history). No other users' identities.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin } from "../_shared/auth.ts";

const FEATURED_LIMIT = 20;
const RECENT_LIMIT   = 20;

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST" && req.method !== "GET")
    return fail("INVALID_INPUT", "POST or GET required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const sb = admin();

  // --- Featured: top tags across all profiles ---------------------------
  // PostgREST doesn't aggregate well from the client, so we read a wide
  // page and tally in JS. With profile_tags capped at 3 per user this
  // stays cheap until we have tens of thousands of users; at that point
  // we'll move this to a materialised view.
  const featured: Array<{ tag: string; count: number }> = [];
  {
    const { data, error } = await sb
      .from("profile_tags")
      .select("tag, normalized_tag")
      .limit(2000);
    if (error) {
      console.warn("featured:", error.message);
    } else {
      const map = new Map<string, { tag: string; count: number }>();
      for (const r of (data ?? []) as { tag: string; normalized_tag: string }[]) {
        const key = r.normalized_tag;
        const slot = map.get(key);
        if (slot) {
          slot.count += 1;
        } else {
          map.set(key, { tag: r.tag, count: 1 });
        }
      }
      featured.push(
        ...[...map.values()]
          .sort((a, b) => b.count - a.count)
          .slice(0, FEATURED_LIMIT)
      );
    }
  }

  // --- Recent: caller's own history, deduped ---------------------------
  const recent: Array<{ tag: string; normalized_tag: string }> = [];
  {
    const { data, error } = await sb
      .from("profile_tag_history")
      .select("tag, normalized_tag, added_at")
      .eq("profile_id", userId)
      .order("added_at", { ascending: false })
      .limit(200);
    if (error) {
      console.warn("history:", error.message);
    } else {
      const seen = new Set<string>();
      for (const r of (data ?? []) as { tag: string; normalized_tag: string }[]) {
        if (seen.has(r.normalized_tag)) continue;
        seen.add(r.normalized_tag);
        recent.push({ tag: r.tag, normalized_tag: r.normalized_tag });
        if (recent.length >= RECENT_LIMIT) break;
      }
    }
  }

  return ok({ featured, recent });
});
