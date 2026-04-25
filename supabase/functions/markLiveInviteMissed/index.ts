// markLiveInviteMissed — Getalong Edge Function.
// Called by the receiver client when its live countdown reaches zero.
// Idempotent: if the invite is no longer live_pending, returns ok.
// Body: { invite_id: uuid }

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, mapPgError, readJson } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;

  const { invite_id } = await readJson<{ invite_id?: string }>(req);
  if (!invite_id) return fail("INVALID_INPUT", "invite_id required.", 400);

  const { error } = await admin().rpc("mark_live_invite_missed", {
    p_invite_id: invite_id,
  });
  if (error) {
    const m = mapPgError(error);
    return fail(m.code, m.message, m.code === "INTERNAL_ERROR" ? 500 : 400);
  }
  return ok({ invite_id });
});
