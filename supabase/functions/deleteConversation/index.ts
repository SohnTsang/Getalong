// deleteConversation — Getalong Edge Function.
//
// Soft-deletes a chat_rooms row. The conversation disappears from both
// participants' chat lists and stops counting against the active-chat
// limit, but the row (and its messages/media/reports) is preserved for
// moderation and the cleanup cron.
//
// Body: { room_id: uuid }
//
// Behavior:
//   * Caller must be a participant.
//   * If the room is already 'deleted', returns ok (idempotent).
//   * Active rooms transition to 'deleted' with deleted_at/by stamped.
//   * Other terminal states (archived/blocked) are not promoted.
//
// Errors: AUTH_REQUIRED, INVALID_INPUT, ROOM_NOT_FOUND,
//         NOT_ROOM_PARTICIPANT, DELETE_FAILED.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";

interface Body { room_id?: string }

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const body = await readJson<Body>(req);
  const roomId = body.room_id?.trim();
  if (!roomId) return fail("INVALID_INPUT", "room_id required.", 400);

  const sb = admin();

  const { data: room, error: rErr } = await sb
    .from("chat_rooms")
    .select("id, user_a, user_b, status, deleted_at, deleted_by")
    .eq("id", roomId)
    .maybeSingle();

  if (rErr) return fail("DELETE_FAILED", rErr.message, 500);
  if (!room) return fail("ROOM_NOT_FOUND", "Chat room not found.", 404);
  if (room.user_a !== userId && room.user_b !== userId)
    return fail("NOT_ROOM_PARTICIPANT", "You are not a participant in this chat.", 403);

  // Idempotent: a second delete from the same user is a no-op.
  if (room.status === "deleted") {
    return ok({ room_id: room.id, deleted_at: room.deleted_at, already: true });
  }

  // We only escalate from 'active'. Archived/blocked rooms are left
  // alone so legacy state isn't quietly rewritten by this call.
  if (room.status !== "active") {
    return fail("ROOM_NOT_FOUND", "Chat room is not in a deletable state.", 409);
  }

  const nowIso = new Date().toISOString();
  const { data: updated, error: uErr } = await sb
    .from("chat_rooms")
    .update({
      status:     "deleted",
      deleted_at: nowIso,
      deleted_by: userId,
    })
    .eq("id", room.id)
    .eq("status", "active")  // optimistic guard against concurrent deletes
    .select("id, deleted_at")
    .maybeSingle();

  if (uErr) return fail("DELETE_FAILED", uErr.message, 500);
  if (!updated) {
    // Concurrent write or row vanished — re-read to decide.
    const { data: reread } = await sb
      .from("chat_rooms").select("id, status, deleted_at").eq("id", room.id).maybeSingle();
    if (reread?.status === "deleted") {
      return ok({ room_id: reread.id, deleted_at: reread.deleted_at, already: true });
    }
    return fail("DELETE_FAILED", "Could not delete the conversation.", 500);
  }

  return ok({ room_id: updated.id, deleted_at: updated.deleted_at, already: false });
});
