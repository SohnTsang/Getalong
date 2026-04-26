// deleteExpiredMedia — Getalong Edge Function (cleanup).
//
// Idempotent. Safe to call repeatedly. Recommended cadence: every 5–15 min
// via Supabase Scheduled Functions or pg_cron. If neither is configured,
// invoke manually with curl + service-role bearer:
//
//   curl -X POST <project>.supabase.co/functions/v1/deleteExpiredMedia \
//        -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
//
// Steps:
//   1. Mark active rows past expires_at as expired.
//   2. Mark pending_upload rows older than PENDING_TTL_SECONDS as expired.
//   3. Delete storage objects for viewed rows older than VIEWED_GRACE,
//      and for expired rows. Move rows to status=deleted.
//
// Auth: requires service-role bearer to avoid being callable by users.

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

  // 2. Pending → expired (older than 30 minutes, never uploaded/attached).
  const pendingCutoff = new Date(Date.now() - PENDING_TTL_SECONDS * 1000)
    .toISOString();
  const { data: expPending, error: e2 } = await sb
    .from("media_assets")
    .update({ status: "expired" })
    .eq("status", "pending_upload")
    .lt("created_at", pendingCutoff)
    .select("id");
  if (e2) console.warn("expirePending failed:", e2.message);

  // 3. Storage cleanup: delete files for viewed rows older than the grace
  //    window, and for expired rows. Then mark them deleted.
  const viewedCutoff = new Date(Date.now() - VIEWED_GRACE_SECONDS * 1000)
    .toISOString();

  const cleanup = async (statusList: string[], extraFilter?: (q: any) => any) => {
    let q = sb
      .from("media_assets")
      .select("id, storage_path")
      .in("status", statusList)
      .limit(BATCH_SIZE);
    if (extraFilter) q = extraFilter(q);
    const { data: rows, error } = await q;
    if (error) {
      console.warn("cleanup query failed:", error.message);
      return { deletedFiles: 0, deletedRows: 0 };
    }
    if (!rows || rows.length === 0) return { deletedFiles: 0, deletedRows: 0 };

    const paths = rows.map((r) => r.storage_path).filter(Boolean);
    let deletedFiles = 0;
    if (paths.length > 0) {
      const { error: rmErr } = await sb.storage
        .from(MEDIA_BUCKET).remove(paths);
      if (rmErr) {
        console.warn("storage remove failed:", rmErr.message);
        // Even if storage removal fails, do not flip the rows to deleted —
        // we'll retry on the next run.
        return { deletedFiles: 0, deletedRows: 0 };
      }
      deletedFiles = paths.length;
    }

    const ids = rows.map((r) => r.id);
    const { error: upErr } = await sb
      .from("media_assets")
      .update({ status: "deleted" })
      .in("id", ids);
    if (upErr) {
      console.warn("status flip to deleted failed:", upErr.message);
      return { deletedFiles, deletedRows: 0 };
    }
    return { deletedFiles, deletedRows: ids.length };
  };

  const viewedCleanup = await cleanup(["viewed"], (q) =>
    q.lt("viewed_at", viewedCutoff));
  const expiredCleanup = await cleanup(["expired"]);

  return ok({
    expired_active:  (expActive ?? []).length,
    expired_pending: (expPending ?? []).length,
    deleted_files:   viewedCleanup.deletedFiles + expiredCleanup.deletedFiles,
    deleted_rows:    viewedCleanup.deletedRows + expiredCleanup.deletedRows,
    ran_at:          nowIso,
  });
});
