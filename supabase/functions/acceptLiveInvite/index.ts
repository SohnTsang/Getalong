// acceptLiveInvite — Getalong Edge Function.
// Body: { invite_id: uuid }

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, mapPgError, readJson } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const { invite_id } = await readJson<{ invite_id?: string }>(req);
  if (!invite_id) return fail("INVALID_INPUT", "invite_id required.", 400);

  const { data, error } = await admin().rpc("accept_live_invite", {
    p_user: userId,
    p_invite_id: invite_id,
  });
  if (error) {
    const m = mapPgError(error);
    return fail(m.code, m.message, m.code === "INTERNAL_ERROR" ? 500 : 400);
  }
  const row = Array.isArray(data) ? data[0] : data;
  return ok({ chat_room_id: row.chat_room_id, invite_id: row.invite_id });
});
