// finalizeViewOnceMedia — Getalong Edge Function.
//
// Body: { media_id: uuid }
//
// Called by the iOS viewer when the receiver closes a one-time-view media
// preview. The user-facing flow is unchanged — closing the viewer makes
// the media unavailable, the bubble flips to "Opened" / "No longer
// available", and a second open is blocked.
//
// What this function does NOT do anymore: delete the storage object on
// close. View-once media is now retained privately for up to 24 hours
// (see migration 0026) so that reports filed shortly after viewing can
// still preserve evidence. The cleanup cron deletes the bytes once
// retention_until has elapsed and no moderation hold exists.
//
// Behaviour:
//   * Authenticated user must be the viewer of this media (viewed_by).
//   * Stamps view_finalized_at = now() if not already set.
//   * Ensures retention_until is set (created_at + 24h fallback for
//     legacy rows).
//   * Idempotent: returns ok for already-finalized, already-deleted,
//     and moderation-held rows.
//   * No storage IO. Cleanup is the cron's job.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";
import { VIEW_ONCE_RETENTION_SECONDS } from "../_shared/media.ts";

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
    .select(`
      id,
      owner_id,
      room_id,
      view_once,
      status,
      viewed_by,
      viewed_at,
      view_finalized_at,
      retention_until,
      moderation_hold_at,
      storage_deleted_at,
      created_at
    `)
    .eq("id", media_id)
    .maybeSingle();
  if (mErr) return fail("INTERNAL_ERROR", mErr.message, 500);
  if (!m)   return fail("MEDIA_NOT_FOUND", "Media not found.", 404);
  if (!m.view_once)
    return fail("MEDIA_NOT_VIEW_ONCE", "Media is not view-once.", 409);

  // Authorization: only the user who already opened it. The owner
  // cannot use this path. If viewed_by is null the receiver never
  // hit openViewOnceMedia, so there is nothing to finalize.
  if (m.viewed_by !== userId)
    return fail("MEDIA_NOT_OWNED", "You can't finalize this media.", 403);
  if (!m.viewed_at)
    return fail("MEDIA_NOT_OWNED", "Media has not been opened.", 409);

  // Idempotent fast paths. We deliberately return ok=true on all of
  // them so the iOS client never surfaces a finalize failure to the
  // user — the user-facing "view-once is over" state is driven by
  // viewed_at, which is already set.
  if (m.storage_deleted_at) {
    return ok({ already_deleted: true });
  }
  if (m.moderation_hold_at) {
    // Held for review. Stamp view_finalized_at if missing so the
    // record reflects that the user actually closed the viewer, but
    // do not touch retention or storage.
    if (!m.view_finalized_at) {
      const { error: upErr } = await sb
        .from("media_assets")
        .update({ view_finalized_at: new Date().toISOString() })
        .eq("id", media_id)
        .is("view_finalized_at", null);
      if (upErr) {
        console.error("finalize: held-row stamp failed:", upErr.message);
      }
    }
    return ok({ moderation_hold: true });
  }

  // Normal close: stamp view_finalized_at and ensure retention_until is
  // set. Both updates are guarded by .is(..., null) so concurrent
  // finalize calls don't fight each other.
  const nowIso = new Date().toISOString();

  if (!m.view_finalized_at) {
    const { error: upErr } = await sb
      .from("media_assets")
      .update({ view_finalized_at: nowIso })
      .eq("id", media_id)
      .is("view_finalized_at", null);
    if (upErr) {
      console.error("finalize: view_finalized_at stamp failed:", upErr.message);
      // Non-fatal — the row may have been finalized concurrently.
    }
  }

  if (!m.retention_until) {
    const fallbackUntil = new Date(
      new Date(m.created_at).getTime() + VIEW_ONCE_RETENTION_SECONDS * 1000,
    ).toISOString();
    const { error: rErr } = await sb
      .from("media_assets")
      .update({ retention_until: fallbackUntil })
      .eq("id", media_id)
      .is("retention_until", null);
    if (rErr) {
      console.error("finalize: retention_until backfill failed:", rErr.message);
    }
  }

  return ok({
    view_finalized_at: m.view_finalized_at ?? nowIso,
  });
});
