// createChatMessage — Getalong Edge Function (text only, MVP).
//
// Body: { room_id: uuid, body: string }
// On success: { ok: true, data: { message: <messages row> } }

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";

const MAX_MESSAGE_LENGTH = 1000;

interface Body { room_id?: string; body?: string }

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const { room_id, body } = await readJson<Body>(req);
  if (!room_id) return fail("INVALID_INPUT", "room_id required.", 400);

  const text = (body ?? "").trim();
  if (text.length === 0)            return fail("EMPTY_MESSAGE", "Message cannot be empty.", 400);
  if (text.length > MAX_MESSAGE_LENGTH)
    return fail("MESSAGE_TOO_LONG", `Message must be ${MAX_MESSAGE_LENGTH} characters or fewer.`, 400);

  const sb = admin();

  // 1. Room must exist, sender must be a participant, room must be active.
  const { data: room, error: roomErr } = await sb
    .from("chat_rooms")
    .select("id, user_a, user_b, status")
    .eq("id", room_id)
    .maybeSingle();
  if (roomErr) return fail("INTERNAL_ERROR", roomErr.message, 500);
  if (!room)   return fail("ROOM_NOT_FOUND", "Chat room not found.", 404);
  if (room.user_a !== userId && room.user_b !== userId)
    return fail("NOT_ROOM_PARTICIPANT", "You are not a participant in this chat.", 403);
  if (room.status !== "active")
    return fail("ROOM_NOT_ACTIVE", "This chat is not active.", 409);

  // 2. Sender must not be banned/deleted.
  const { data: sender, error: sErr } = await sb
    .from("profiles")
    .select("is_banned, deleted_at")
    .eq("id", userId)
    .maybeSingle();
  if (sErr) return fail("INTERNAL_ERROR", sErr.message, 500);
  if (!sender || sender.is_banned || sender.deleted_at !== null)
    return fail("USER_BANNED", "Your account is restricted.", 403);

  // 3. Block check (either direction).
  const partnerId = room.user_a === userId ? room.user_b : room.user_a;
  const { data: blocks, error: bErr } = await sb
    .from("blocks")
    .select("blocker_id")
    .or(`and(blocker_id.eq.${userId},blocked_id.eq.${partnerId}),and(blocker_id.eq.${partnerId},blocked_id.eq.${userId})`)
    .limit(1);
  if (bErr) return fail("INTERNAL_ERROR", bErr.message, 500);
  if ((blocks ?? []).length > 0)
    return fail("BLOCKED_RELATIONSHIP", "You can't reach this person.", 403);

  // 4. Insert message.
  const { data: message, error: insErr } = await sb
    .from("messages")
    .insert({
      room_id,
      sender_id: userId,
      message_type: "text",
      body: text,
    })
    .select()
    .single();
  if (insErr) return fail("INSERT_FAILED", insErr.message, 500);

  // 5. Bump last_message_at. Best-effort; failure here doesn't block the send.
  const { error: bumpErr } = await sb
    .from("chat_rooms")
    .update({ last_message_at: message.created_at })
    .eq("id", room_id);
  if (bumpErr) console.warn("last_message_at update failed:", bumpErr.message);

  return ok({ message });
});
