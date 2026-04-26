// openViewOnceMedia — Getalong Edge Function.
//
// Body: { media_id: uuid }
//
// Behaviour:
//   * Authenticated user must be a participant in the same room as the
//     media row, and must NOT be the media owner.
//   * Atomically transitions the row from active → viewed before issuing a
//     signed URL. The conditional update is the source of truth: a second
//     caller will not flip an already-flipped row, so they receive
//     MEDIA_ALREADY_VIEWED and never see a URL.
//   * Returns a short-lived signed URL (60 seconds).

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";
import { MEDIA_BUCKET } from "../_shared/media.ts";

const SIGNED_URL_TTL_SECONDS = 60;

interface Body { media_id?: string }

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const { media_id } = await readJson<Body>(req);
  if (!media_id) return fail("INVALID_INPUT", "media_id required.", 400);

  const sb = admin();

  // Load media + owning room.
  const { data: m, error: mErr } = await sb
    .from("media_assets")
    .select("id, owner_id, room_id, storage_path, mime_type, view_once, status, viewed_at, expires_at")
    .eq("id", media_id)
    .maybeSingle();
  if (mErr) return fail("INTERNAL_ERROR", mErr.message, 500);
  if (!m)   return fail("MEDIA_NOT_FOUND", "Media not found.", 404);
  if (!m.view_once)
    return fail("MEDIA_NOT_VIEW_ONCE", "Media is not view-once.", 409);
  if (m.owner_id === userId)
    return fail("MEDIA_NOT_OWNED", "You can't open your own one-time media.", 403);
  if (m.status === "viewed" || m.viewed_at !== null)
    return fail("MEDIA_ALREADY_VIEWED", "This media has already been viewed.", 410);
  if (m.status !== "active")
    return fail("MEDIA_NOT_ACTIVE", "Media is no longer available.", 410);
  if (m.expires_at && new Date(m.expires_at).getTime() < Date.now())
    return fail("MEDIA_EXPIRED", "Media has expired.", 410);

  // Participant check.
  const { data: room, error: rErr } = await sb
    .from("chat_rooms")
    .select("user_a, user_b")
    .eq("id", m.room_id)
    .maybeSingle();
  if (rErr) return fail("INTERNAL_ERROR", rErr.message, 500);
  if (!room) return fail("ROOM_NOT_FOUND", "Chat room not found.", 404);
  if (room.user_a !== userId && room.user_b !== userId)
    return fail("NOT_ROOM_PARTICIPANT", "You are not a participant in this chat.", 403);

  // Block check (either direction).
  const partnerId = m.owner_id;
  const { data: blocks, error: bErr } = await sb
    .from("blocks")
    .select("blocker_id")
    .or(`and(blocker_id.eq.${userId},blocked_id.eq.${partnerId}),and(blocker_id.eq.${partnerId},blocked_id.eq.${userId})`)
    .limit(1);
  if (bErr) return fail("INTERNAL_ERROR", bErr.message, 500);
  if ((blocks ?? []).length > 0)
    return fail("BLOCKED_RELATIONSHIP", "You can't view this media.", 403);

  // Atomic flip: only succeed if status=active and viewed_at is null.
  const nowIso = new Date().toISOString();
  const { data: flipped, error: fErr } = await sb
    .from("media_assets")
    .update({ status: "viewed", viewed_by: userId, viewed_at: nowIso })
    .eq("id", media_id)
    .eq("status", "active")
    .is("viewed_at", null)
    .select("id, storage_path, mime_type")
    .maybeSingle();
  if (fErr) return fail("INTERNAL_ERROR", fErr.message, 500);
  if (!flipped) {
    // Another open just won the race.
    return fail("MEDIA_ALREADY_VIEWED", "This media has already been viewed.", 410);
  }

  // Mint short-lived signed URL AFTER the flip; if this fails the row is
  // already viewed and the client surfaces a clear error.
  const { data: signed, error: sErr } = await sb
    .storage.from(MEDIA_BUCKET)
    .createSignedUrl(flipped.storage_path, SIGNED_URL_TTL_SECONDS);
  if (sErr || !signed) {
    console.warn("openViewOnceMedia: signed URL failed:", sErr?.message);
    return fail("STORAGE_ERROR", "Couldn't open this media.", 500);
  }

  return ok({
    signed_url:  signed.signedUrl,
    mime_type:   flipped.mime_type,
    expires_in:  SIGNED_URL_TTL_SECONDS,
    viewed_at:   nowIso,
  });
});
