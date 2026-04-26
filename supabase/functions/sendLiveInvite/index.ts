// sendLiveInvite — Getalong Edge Function.
//
// Body: { receiver_id?: uuid, receiver_handle?: string, post_id?: uuid, message?: string }
// Looks up receiver by id or by `getalong_id`.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, mapPgError, readJson } from "../_shared/auth.ts";
import { pushToUser, PUSH_LIVE_SIGNAL_RECEIVED } from "../_shared/apns.ts";

interface Body {
  receiver_id?: string;
  receiver_handle?: string;
  post_id?: string;
  message?: string;
}

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const senderId = userOrErr;

  const body = await readJson<Body>(req);
  let receiverId = body.receiver_id;

  const sb = admin();

  if (!receiverId && body.receiver_handle) {
    const handle = body.receiver_handle.trim().toLowerCase();
    const { data, error } = await sb
      .from("profiles")
      .select("id")
      .eq("getalong_id", handle)
      .maybeSingle();
    if (error) return fail("INTERNAL_ERROR", error.message, 500);
    if (!data)  return fail("RECEIVER_NOT_FOUND", `No user with handle @${handle}.`, 404);
    receiverId = data.id;
  }

  if (!receiverId) return fail("INVALID_INPUT", "receiver_id or receiver_handle required.", 400);

  const { data, error } = await sb.rpc("send_live_invite", {
    p_sender:   senderId,
    p_receiver: receiverId,
    p_post_id:  body.post_id ?? null,
    p_message:  body.message ?? null,
  });

  if (error) {
    const m = mapPgError(error);
    return fail(m.code, m.message, m.code === "INTERNAL_ERROR" ? 500 : 400);
  }

  const row = Array.isArray(data) ? data[0] : data;

  // Best-effort push to the receiver. Never block the response on this.
  pushToUser(receiverId, PUSH_LIVE_SIGNAL_RECEIVED, {
    data: { type: "live_signal_received", invite_id: row.invite_id },
    collapseId: `invite:${row.invite_id}`,
    threadId:   "live-signals",
  }).catch((e) => console.warn("sendLiveInvite push failed:", e));

  return ok({
    invite_id:        row.invite_id,
    live_expires_at:  row.live_expires_at,
    duration_seconds: row.duration_seconds,
  });
});
