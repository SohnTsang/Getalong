// finalizeViewOnceMedia — Getalong Edge Function.
//
// Body: { media_id: uuid }
//
// Called by the iOS viewer when the receiver closes a one-time-view media
// preview. Removes the storage object from chat-media-private and stamps
// storage_deleted_at on the row. Idempotent: repeated calls (after a
// network retry, after the object is already gone, etc.) succeed.
//
// Auth: only the user who already viewed this media (media.viewed_by) can
// finalize it — the owner cannot use this function to "unsend" before the
// receiver opens.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";
import { MEDIA_BUCKET } from "../_shared/media.ts";

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

  const { data: m, error: mErr } = await sb
    .from("media_assets")
    .select("id, owner_id, room_id, storage_path, view_once, status, viewed_by, viewed_at, storage_deleted_at")
    .eq("id", media_id)
    .maybeSingle();
  if (mErr) return fail("INTERNAL_ERROR", mErr.message, 500);
  if (!m)   return fail("MEDIA_NOT_FOUND", "Media not found.", 404);
  if (!m.view_once)
    return fail("MEDIA_NOT_VIEW_ONCE", "Media is not view-once.", 409);

  // Authorization: only the user who viewed it. The owner can't use this
  // path. If viewed_by is null (never opened), reject — only
  // openViewOnceMedia is allowed to flip it.
  if (m.viewed_by !== userId)
    return fail("MEDIA_NOT_OWNED", "You can't finalize this media.", 403);

  // Idempotent fast paths.
  if (m.storage_deleted_at) {
    return ok({ already_deleted: true });
  }

  // Remove the object. Treat "not found" as success (idempotent).
  const { error: rmErr } = await sb.storage
    .from(MEDIA_BUCKET).remove([m.storage_path]);
  if (rmErr) {
    // supabase-storage returns success even when paths don't exist, but
    // log + continue so we still stamp the row. The fallback cleanup will
    // re-attempt if the row stays unmarked.
    console.warn("finalizeViewOnceMedia: storage.remove warned:", rmErr.message);
  }

  const nowIso = new Date().toISOString();
  const { error: upErr } = await sb
    .from("media_assets")
    .update({ storage_deleted_at: nowIso })
    .eq("id", media_id)
    .is("storage_deleted_at", null);
  if (upErr) {
    return fail("INTERNAL_ERROR", upErr.message, 500);
  }

  return ok({
    storage_deleted_at: nowIso,
  });
});
