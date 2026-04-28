// requestMediaUpload — Getalong Edge Function.
//
// Body: {
//   room_id: uuid,
//   mime_type: string,         // image/jpeg | image/png | image/gif | video/mp4 | video/quicktime
//   size_bytes: number,
//   duration_seconds?: number  // required for videos
// }
//
// Behaviour:
//   * Verifies the user is a participant in an active chat room with no
//     blocks in either direction and not banned/deleted.
//   * Validates MIME, size, and (for video) duration against server limits.
//   * Creates a media_assets row with status = pending_upload, view_once = true.
//   * Issues a Supabase Storage signed upload URL pointing at the row's
//     storage_path. The client uploads to that URL, then calls
//     createChatMessage with the returned media_id.
//
// Returns: {
//   media_id, storage_path, mime_type,
//   upload_url, upload_token,
//   expires_at, max_bytes
// }

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";
import {
  ALLOWED_MIME,
  MAX_BYTES_BY_KIND,
  MAX_VIDEO_DURATION_SECONDS,
  MEDIA_BUCKET,
  ACTIVE_TTL_SECONDS,
  storagePathFor,
} from "../_shared/media.ts";

interface Body {
  room_id?: string;
  mime_type?: string;
  size_bytes?: number;
  duration_seconds?: number;
  // Tiny base64 JPEG (~1-2KB) used as a blurred-noise placeholder
  // shown to both participants before the receiver opens the media.
  // Optional — older clients won't include it.
  preview_data?: string;
}

// Hard cap so a malicious or buggy client can't store an oversized
// preview. 8KB base64 ≈ 6KB raw, plenty for a 24-32px JPEG.
const MAX_PREVIEW_BYTES = 8 * 1024;

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const body = await readJson<Body>(req);
  const roomId = body.room_id;
  const mime = (body.mime_type ?? "").trim();
  const size = Number(body.size_bytes ?? 0);
  const duration = body.duration_seconds ?? null;
  let previewData: string | null = body.preview_data?.trim() || null;
  if (previewData && previewData.length > MAX_PREVIEW_BYTES) {
    previewData = null;  // silently drop rather than fail the upload.
  }

  if (!roomId)              return fail("INVALID_INPUT", "room_id required.", 400);
  if (!mime)                return fail("INVALID_INPUT", "mime_type required.", 400);
  if (!Number.isFinite(size) || size <= 0)
                            return fail("INVALID_INPUT", "size_bytes required.", 400);

  const kind = ALLOWED_MIME[mime];
  if (!kind) return fail("MEDIA_TYPE_NOT_ALLOWED", "Unsupported media type.", 400);

  const max = MAX_BYTES_BY_KIND[kind];
  if (size > max) return fail("MEDIA_TOO_LARGE", "File exceeds the size limit.", 400);

  if (kind === "video") {
    if (duration == null || !Number.isFinite(duration) || duration <= 0) {
      return fail("INVALID_INPUT", "duration_seconds required for video.", 400);
    }
    if (duration > MAX_VIDEO_DURATION_SECONDS) {
      return fail("MEDIA_DURATION_TOO_LONG", "Video is too long.", 400);
    }
  }

  const sb = admin();

  // Room participant + active.
  const { data: room, error: rErr } = await sb
    .from("chat_rooms")
    .select("id, user_a, user_b, status")
    .eq("id", roomId)
    .maybeSingle();
  if (rErr)  return fail("INTERNAL_ERROR", rErr.message, 500);
  if (!room) return fail("ROOM_NOT_FOUND", "Chat room not found.", 404);
  if (room.user_a !== userId && room.user_b !== userId)
    return fail("NOT_ROOM_PARTICIPANT", "You are not a participant in this chat.", 403);
  if (room.status !== "active")
    return fail("ROOM_NOT_ACTIVE", "This chat is not active.", 409);

  // Sender not banned.
  const { data: me, error: mErr } = await sb
    .from("profiles")
    .select("is_banned, deleted_at")
    .eq("id", userId)
    .maybeSingle();
  if (mErr) return fail("INTERNAL_ERROR", mErr.message, 500);
  if (!me || me.is_banned || me.deleted_at !== null)
    return fail("USER_BANNED", "Your account is restricted.", 403);

  // Block check.
  const partnerId = room.user_a === userId ? room.user_b : room.user_a;
  const { data: blocks, error: bErr } = await sb
    .from("blocks")
    .select("blocker_id")
    .or(`and(blocker_id.eq.${userId},blocked_id.eq.${partnerId}),and(blocker_id.eq.${partnerId},blocked_id.eq.${userId})`)
    .limit(1);
  if (bErr) return fail("INTERNAL_ERROR", bErr.message, 500);
  if ((blocks ?? []).length > 0)
    return fail("BLOCKED_RELATIONSHIP", "You can't reach this person.", 403);

  // Create media row first (we know the id, then build storage_path).
  const expiresAt = new Date(Date.now() + ACTIVE_TTL_SECONDS * 1000).toISOString();

  // Reserve an id by inserting with a placeholder path, then update once
  // we know the id. Using returning id keeps this single round-trip.
  const placeholderPath = `rooms/${roomId}/__pending`;
  const { data: row, error: insErr } = await sb
    .from("media_assets")
    .insert({
      owner_id:        userId,
      room_id:         roomId,
      storage_path:    placeholderPath,
      mime_type:       mime,
      size_bytes:      size,
      duration_seconds: duration,
      view_once:       true,
      status:          "pending_upload",
      expires_at:      expiresAt,
      preview_data:    previewData,
    })
    .select("id")
    .single();
  if (insErr || !row) return fail("INTERNAL_ERROR", insErr?.message ?? "insert failed", 500);

  const path = storagePathFor(roomId, row.id, mime);
  const { error: updErr } = await sb
    .from("media_assets")
    .update({ storage_path: path })
    .eq("id", row.id);
  if (updErr) return fail("INTERNAL_ERROR", updErr.message, 500);

  // Mint a signed upload URL. supabase-js v2 provides createSignedUploadUrl.
  const { data: signed, error: sErr } = await sb
    .storage.from(MEDIA_BUCKET).createSignedUploadUrl(path);
  if (sErr || !signed) return fail("STORAGE_ERROR", sErr?.message ?? "signed URL failed", 500);

  return ok({
    media_id:     row.id,
    storage_path: path,
    mime_type:    mime,
    bucket:       MEDIA_BUCKET,
    upload_url:   signed.signedUrl,
    upload_token: signed.token,
    max_bytes:    max,
    expires_at:   expiresAt,
  });
});
