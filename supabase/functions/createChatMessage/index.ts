// createChatMessage — Getalong Edge Function.
//
// Two shapes:
//   text:  { room_id, body }
//   media: { room_id, media_id }   // body optional; for view-once media
//
// On success: { ok: true, data: { message: <messages row> } }

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";
import { pushToUser, PUSH_NEW_MESSAGE } from "../_shared/apns.ts";
import { MEDIA_BUCKET, messageTypeFromMime } from "../_shared/media.ts";

const MAX_MESSAGE_LENGTH = 1000;

interface Body {
  room_id?: string;
  body?: string;
  media_id?: string;
}

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const { room_id, body, media_id } = await readJson<Body>(req);
  if (!room_id) return fail("INVALID_INPUT", "room_id required.", 400);

  const text = (body ?? "").trim();
  const isMedia = !!media_id;

  if (!isMedia) {
    if (text.length === 0)
      return fail("EMPTY_MESSAGE", "Message cannot be empty.", 400);
    if (text.length > MAX_MESSAGE_LENGTH)
      return fail("MESSAGE_TOO_LONG", `Message must be ${MAX_MESSAGE_LENGTH} characters or fewer.`, 400);
  } else {
    if (text.length > MAX_MESSAGE_LENGTH)
      return fail("MESSAGE_TOO_LONG", `Caption too long.`, 400);
  }

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

  // 4a. Validate media if provided.
  let messageType: "text" | "image" | "gif" | "video" = "text";
  let mediaRow: {
    id: string; owner_id: string; room_id: string;
    storage_path: string; mime_type: string; status: string;
    attached_message_id: string | null;
  } | null = null;

  if (isMedia) {
    const { data: m, error: mErr } = await sb
      .from("media_assets")
      .select("id, owner_id, room_id, storage_path, mime_type, status, attached_message_id")
      .eq("id", media_id!)
      .maybeSingle();
    if (mErr) return fail("INTERNAL_ERROR", mErr.message, 500);
    if (!m)   return fail("MEDIA_NOT_FOUND", "Media not found.", 404);
    if (m.owner_id !== userId) return fail("MEDIA_NOT_OWNED", "Media is not yours.", 403);
    if (m.room_id  !== room_id) return fail("MEDIA_WRONG_ROOM", "Media not in this room.", 403);
    if (m.attached_message_id) return fail("MEDIA_ALREADY_ATTACHED", "Media already sent.", 409);
    if (m.status !== "pending_upload" && m.status !== "active")
      return fail("MEDIA_NOT_ACTIVE", "Media is not in a sendable state.", 409);

    // Verify that the storage object actually exists (uploaded).
    // storage.from(...).list with the file's basename inside its parent.
    const slash = m.storage_path.lastIndexOf("/");
    const dir   = slash >= 0 ? m.storage_path.slice(0, slash) : "";
    const name  = slash >= 0 ? m.storage_path.slice(slash + 1) : m.storage_path;
    const { data: list, error: lErr } = await sb
      .storage.from(MEDIA_BUCKET)
      .list(dir, { search: name, limit: 1 });
    if (lErr) return fail("STORAGE_ERROR", lErr.message, 500);
    if (!list || list.length === 0)
      return fail("MEDIA_NOT_UPLOADED", "Media has not been uploaded yet.", 409);

    const inferred = messageTypeFromMime(m.mime_type);
    if (!inferred) return fail("MEDIA_TYPE_NOT_ALLOWED", "Unsupported media type.", 400);
    messageType = inferred;
    mediaRow = m;
  }

  // 4b. Insert message.
  const { data: message, error: insErr } = await sb
    .from("messages")
    .insert({
      room_id,
      sender_id: userId,
      message_type: messageType,
      body: isMedia ? (text.length > 0 ? text : null) : text,
      media_id: media_id ?? null,
    })
    .select()
    .single();
  if (insErr) return fail("INSERT_FAILED", insErr.message, 500);

  // 4c. Mark media active + attach to message.
  if (mediaRow) {
    const nowIso = new Date().toISOString();
    const { error: aErr } = await sb
      .from("media_assets")
      .update({
        status: "active",
        uploaded_at: nowIso,
        attached_message_id: message.id,
      })
      .eq("id", mediaRow.id);
    if (aErr) {
      // Failure here means we have a message that points at a media row
      // that didn't transition. Soft-delete the message to keep state
      // consistent — the client treats this as send failure and can retry.
      await sb.from("messages").update({ is_deleted: true }).eq("id", message.id);
      return fail("INSERT_FAILED", aErr.message, 500);
    }
  }

  // 5. Bump last_message_at. Best-effort; failure here doesn't block the send.
  const { error: bumpErr } = await sb
    .from("chat_rooms")
    .update({ last_message_at: message.created_at })
    .eq("id", room_id);
  if (bumpErr) console.warn("last_message_at update failed:", bumpErr.message);

  // 6. Best-effort push to the other participant.
  pushToUser(partnerId, PUSH_NEW_MESSAGE, {
    data: {
      type: "new_message",
      room_id,
      message_id: message.id,
    },
    collapseId: `chat:${room_id}`,
    threadId:   `chat:${room_id}`,
  }).catch((e) => console.warn("createChatMessage push failed:", e));

  // Strip storage_path from the response: the client only needs message.
  return ok({ message });
});
