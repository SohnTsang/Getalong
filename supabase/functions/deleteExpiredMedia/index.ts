// deleteExpiredMedia — Getalong fallback cleanup.
//
// Now the *primary* deletion path for view-once media. finalizeViewOnceMedia
// no longer deletes storage on close — it only stamps view_finalized_at.
// This function (and the pg_cron equivalent in cleanup_expired_media)
// removes storage objects according to:
//
//   * pending_upload rows older than 30 minutes — never finished uploading.
//   * active rows past their 7-day expires_at — receiver never opened.
//   * any row past retention_until (created_at + 24h for view-once)
//     where storage_deleted_at is null.
//
// Moderation-held rows (moderation_hold_at IS NOT NULL) are skipped
// indefinitely — they live until the manual review path stamps
// moderation_reviewed_at (and a future tool decides what to do with the
// bytes).
//
// Idempotent. Safe to call repeatedly. Service-role only.
//
// pg_cron runs `public.cleanup_expired_media()` every 2 minutes. This
// HTTP endpoint exists for ad-hoc invocation (CI tests, manual
// remediation, "I want it gone now"). The two share semantics — if you
// change one, change the other.

import { ok, fail, preflight } from "../_shared/response.ts";
import { admin } from "../_shared/auth.ts";
import {
  MEDIA_BUCKET,
  PENDING_TTL_SECONDS,
} from "../_shared/media.ts";

function authorize(req: Request): boolean {
  const auth = (req.headers.get("Authorization") ?? "").trim();
  if (!auth.toLowerCase().startsWith("bearer ")) return false;
  const token = auth.slice(7).trim();
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  return serviceKey.length > 0 && token === serviceKey;
}

const BATCH_SIZE = 200;

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST" && req.method !== "GET")
    return fail("INVALID_INPUT", "POST or GET required.", 405);
  if (!authorize(req))
    return fail("AUTH_REQUIRED", "Service role required.", 401);

  const sb = admin();
  const nowIso = new Date().toISOString();

  // 1. Active → expired (past expires_at). Skip held rows; we still want
  //    them on hold even if the active TTL has elapsed.
  const { data: expActive, error: e1 } = await sb
    .from("media_assets")
    .update({ status: "expired" })
    .eq("status", "active")
    .lt("expires_at", nowIso)
    .is("moderation_hold_at", null)
    .select("id");
  if (e1) console.warn("expireActive failed:", e1.message);

  // 2. Pending → expired (older than 30 minutes, never uploaded).
  const pendingCutoff = new Date(Date.now() - PENDING_TTL_SECONDS * 1000)
    .toISOString();
  const { data: expPending, error: e2 } = await sb
    .from("media_assets")
    .update({ status: "expired" })
    .eq("status", "pending_upload")
    .lt("created_at", pendingCutoff)
    .is("moderation_hold_at", null)
    .select("id");
  if (e2) console.warn("expirePending failed:", e2.message);

  // 3. Storage cleanup — anything past retention_until that still has
  //    bytes and isn't on hold.
  const retentionResult = await sweepRetentionElapsed(sb);

  return ok({
    expired_active:    (expActive ?? []).length,
    expired_pending:   (expPending ?? []).length,
    storage_swept:     retentionResult,
    ran_at:            nowIso,
  });
});

async function sweepRetentionElapsed(
  sb: ReturnType<typeof admin>,
): Promise<{ rows: number; files: number; failed: number }> {
  const nowIso = new Date().toISOString();
  // Indexed predicate: media_assets_retention_cleanup_idx covers
  // (retention_until) WHERE storage_deleted_at IS NULL AND
  // moderation_hold_at IS NULL. The .lte/.is filters here line up.
  const { data: rows, error } = await sb
    .from("media_assets")
    .select("id, storage_path")
    .lte("retention_until", nowIso)
    .is("storage_deleted_at", null)
    .is("moderation_hold_at", null)
    .limit(BATCH_SIZE);
  if (error) {
    console.warn("retention sweep query failed:", error.message);
    return { rows: 0, files: 0, failed: 0 };
  }
  if (!rows || rows.length === 0) return { rows: 0, files: 0, failed: 0 };

  const paths = rows.map((r) => r.storage_path).filter(Boolean) as string[];
  let filesRemoved = 0;
  let filesFailed = 0;
  if (paths.length > 0) {
    const { error: rmErr } = await sb.storage
      .from(MEDIA_BUCKET).remove(paths);
    if (rmErr) {
      // supabase-js .remove() returns success (no error) for missing
      // keys, so a real error here means the bucket actually rejected
      // the delete. Don't stamp storage_deleted_at — the next cron
      // pass will retry.
      console.warn("storage remove (retention) failed:", rmErr.message);
      return { rows: 0, files: 0, failed: paths.length };
    }
    filesRemoved = paths.length;
  }

  const ids = rows.map((r) => r.id);
  const { error: upErr } = await sb
    .from("media_assets")
    .update({ storage_deleted_at: new Date().toISOString() })
    .in("id", ids)
    .is("storage_deleted_at", null);
  if (upErr) {
    console.warn("retention sweep stamp failed:", upErr.message);
    filesFailed += ids.length;
    return { rows: 0, files: filesRemoved, failed: filesFailed };
  }
  return { rows: ids.length, files: filesRemoved, failed: filesFailed };
}
