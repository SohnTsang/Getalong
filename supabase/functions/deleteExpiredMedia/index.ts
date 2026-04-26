// deleteExpiredMedia — Getalong fallback cleanup.
//
// Primary deletion path is finalizeViewOnceMedia, called by the iOS viewer
// when the receiver closes the preview. This function is the safety net
// that catches:
//
//   * viewed rows that never got a finalize call (app killed, network
//     failure, etc.) — after a 2-minute grace, delete the storage object
//     and stamp storage_deleted_at.
//   * pending_upload rows older than 30 minutes — never uploaded.
//   * active rows past expires_at — receiver never opened.
//   * expired rows with storage objects still around.
//
// Idempotent. Safe to call repeatedly. Service-role only.

import { ok, fail, preflight } from "../_shared/response.ts";
import { admin } from "../_shared/auth.ts";
import {
  MEDIA_BUCKET,
  PENDING_TTL_SECONDS,
  VIEWED_GRACE_SECONDS,
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

  // 1. Active → expired (past expires_at).
  const { data: expActive, error: e1 } = await sb
    .from("media_assets")
    .update({ status: "expired" })
    .eq("status", "active")
    .lt("expires_at", nowIso)
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
    .select("id");
  if (e2) console.warn("expirePending failed:", e2.message);

  // 3a. Viewed rows where the client never finalized (storage_deleted_at
  //     still null) and viewed_at is older than the grace window. Remove
  //     storage objects and stamp storage_deleted_at — keep status=viewed
  //     so the bubble keeps showing "Viewed" / "Opened".
  const viewedCutoff = new Date(Date.now() - VIEWED_GRACE_SECONDS * 1000)
    .toISOString();
  const finalizedFallback = await finalizeViewedFallback(sb, viewedCutoff);

  // 3b. Expired rows: remove storage objects and flip to deleted.
  const expiredCleanup = await cleanupExpired(sb);

  return ok({
    expired_active:           (expActive ?? []).length,
    expired_pending:          (expPending ?? []).length,
    viewed_finalized_fallback: finalizedFallback,
    deleted_expired:          expiredCleanup,
    ran_at:                   nowIso,
  });
});

async function finalizeViewedFallback(
  sb: ReturnType<typeof admin>,
  cutoffIso: string,
): Promise<{ rows: number; files: number }> {
  const { data: rows, error } = await sb
    .from("media_assets")
    .select("id, storage_path")
    .eq("status", "viewed")
    .is("storage_deleted_at", null)
    .lt("viewed_at", cutoffIso)
    .limit(BATCH_SIZE);
  if (error) {
    console.warn("viewed-fallback query failed:", error.message);
    return { rows: 0, files: 0 };
  }
  if (!rows || rows.length === 0) return { rows: 0, files: 0 };

  const paths = rows.map((r) => r.storage_path).filter(Boolean);
  if (paths.length > 0) {
    const { error: rmErr } = await sb.storage
      .from(MEDIA_BUCKET).remove(paths);
    if (rmErr) {
      console.warn("storage remove (viewed fallback) failed:", rmErr.message);
      return { rows: 0, files: 0 };
    }
  }
  const ids = rows.map((r) => r.id);
  const { error: upErr } = await sb
    .from("media_assets")
    .update({ storage_deleted_at: new Date().toISOString() })
    .in("id", ids);
  if (upErr) {
    console.warn("viewed-fallback stamp failed:", upErr.message);
    return { rows: 0, files: paths.length };
  }
  return { rows: ids.length, files: paths.length };
}

async function cleanupExpired(
  sb: ReturnType<typeof admin>,
): Promise<{ rows: number; files: number }> {
  const { data: rows, error } = await sb
    .from("media_assets")
    .select("id, storage_path, storage_deleted_at")
    .eq("status", "expired")
    .limit(BATCH_SIZE);
  if (error) {
    console.warn("expired query failed:", error.message);
    return { rows: 0, files: 0 };
  }
  if (!rows || rows.length === 0) return { rows: 0, files: 0 };

  const paths = rows
    .filter((r) => !r.storage_deleted_at)
    .map((r) => r.storage_path)
    .filter(Boolean);
  let files = 0;
  if (paths.length > 0) {
    const { error: rmErr } = await sb.storage
      .from(MEDIA_BUCKET).remove(paths);
    if (rmErr) {
      console.warn("storage remove (expired) failed:", rmErr.message);
      return { rows: 0, files: 0 };
    }
    files = paths.length;
  }
  const ids = rows.map((r) => r.id);
  const { error: upErr } = await sb
    .from("media_assets")
    .update({ status: "deleted", storage_deleted_at: new Date().toISOString() })
    .in("id", ids);
  if (upErr) {
    console.warn("expired status flip failed:", upErr.message);
    return { rows: 0, files };
  }
  return { rows: ids.length, files };
}
