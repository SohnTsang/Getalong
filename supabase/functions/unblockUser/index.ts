// unblockUser — Getalong Edge Function.
//
// Body: { blocked_user_id: uuid }
//
// Behaviour: deletes the (auth.uid(), blocked_user_id) row from
// public.blocks. Idempotent — if the row doesn't exist we still return ok.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";

interface Body { blocked_user_id?: string }

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const blockerId = userOrErr;

  const { blocked_user_id } = await readJson<Body>(req);
  const blockedId = (blocked_user_id ?? "").trim();
  if (!blockedId) return fail("INVALID_INPUT", "blocked_user_id required.", 400);

  const { error } = await admin()
    .from("blocks")
    .delete()
    .eq("blocker_id", blockerId)
    .eq("blocked_id", blockedId);
  if (error) return fail("INTERNAL_ERROR", error.message, 500);
  return ok({ blocked_user_id: blockedId });
});
