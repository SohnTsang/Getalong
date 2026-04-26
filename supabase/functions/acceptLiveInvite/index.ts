// acceptLiveInvite — Getalong Edge Function.
// Body: { invite_id: uuid }

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, mapPgError, readJson } from "../_shared/auth.ts";
import { pushToUser, PUSH_CONVERSATION_STARTED } from "../_shared/apns.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const { invite_id } = await readJson<{ invite_id?: string }>(req);
  if (!invite_id) return fail("INVALID_INPUT", "invite_id required.", 400);

  const sb = admin();
  const { data, error } = await sb.rpc("accept_live_invite", {
    p_user: userId,
    p_invite_id: invite_id,
  });
  if (error) {
    const m = mapPgError(error);
    return fail(m.code, m.message, m.code === "INTERNAL_ERROR" ? 500 : 400);
  }
  const row = Array.isArray(data) ? data[0] : data;

  // Notify the sender that the conversation started. Best-effort.
  (async () => {
    try {
      const { data: invite } = await sb
        .from("invites")
        .select("sender_id")
        .eq("id", row.invite_id)
        .maybeSingle();
      if (invite?.sender_id) {
        await pushToUser(invite.sender_id, PUSH_CONVERSATION_STARTED, {
          data: {
            type: "conversation_started",
            invite_id: row.invite_id,
            chat_room_id: row.chat_room_id,
          },
          collapseId: `chat:${row.chat_room_id}`,
          threadId:   "conversations",
        });
      }
    } catch (e) {
      console.warn("acceptLiveInvite push failed:", e);
    }
  })();

  return ok({ chat_room_id: row.chat_room_id, invite_id: row.invite_id });
});
