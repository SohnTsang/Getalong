// blockUser — Getalong Edge Function.
//
// Body: { blocked_user_id?: uuid, blocked_handle?: string }
//
// Behaviour:
//   * Inserts a row into public.blocks. Idempotent — a repeated block on
//     the same user returns ok with already_blocked = true.
//   * Soft-deletes the active chat room between the pair (if any), in
//     a single transaction, so the conversation disappears from BOTH
//     users' Chats lists and neither side can keep sending messages
//     / media in that room. Existing message/media history rows are
//     preserved.
//   * Cancels any active live_pending invites between the two users in
//     either direction so a stale 15-second timer can't surface after
//     the block is in place.
//
// Atomicity: all four side effects (block row, room close, invite
// cancel, media-cleanup mark) run inside one SQL function
// `_ga_block_user_and_close_rooms` (migration 0032). A failure in any
// step rolls the whole thing back — there's no half-blocked state.
//
// Errors: AUTH_REQUIRED, INVALID_INPUT, PROFILE_NOT_FOUND,
//         SELF_BLOCK_NOT_ALLOWED, BLOCK_FAILED.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";

interface Body {
  blocked_user_id?: string;
  blocked_handle?: string;
}

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const blockerId = userOrErr;

  const body = await readJson<Body>(req);
  const sb = admin();

  let blockedId = (body.blocked_user_id ?? "").trim();
  if (!blockedId && body.blocked_handle) {
    const handle = body.blocked_handle.trim().toLowerCase();
    const { data, error } = await sb
      .from("profiles").select("id")
      .eq("getalong_id", handle).maybeSingle();
    if (error) return fail("INTERNAL_ERROR", error.message, 500);
    if (!data)  return fail("PROFILE_NOT_FOUND", `No user @${handle}.`, 404);
    blockedId = data.id;
  }
  if (!blockedId) {
    return fail("INVALID_INPUT", "blocked_user_id or blocked_handle required.", 400);
  }
  if (blockedId === blockerId) {
    return fail("SELF_BLOCK_NOT_ALLOWED", "You can't block yourself.", 400);
  }

  // Verify the target profile actually exists (and isn't deleted).
  const { data: target, error: tErr } = await sb
    .from("profiles").select("id, deleted_at")
    .eq("id", blockedId).maybeSingle();
  if (tErr) return fail("INTERNAL_ERROR", tErr.message, 500);
  if (!target || target.deleted_at !== null)
    return fail("PROFILE_NOT_FOUND", "User not found.", 404);

  // Single transactional RPC. Inserts the block row, soft-deletes
  // every active chat room between the pair (with deleted_at/by
  // stamps), cancels pending live invites, and marks the closed
  // rooms' media for retention cleanup — all-or-nothing.
  const { data: rpcData, error: rpcErr } = await sb
    .rpc("_ga_block_user_and_close_rooms", {
      p_blocker: blockerId,
      p_blocked: blockedId,
    });
  if (rpcErr) {
    const e = rpcErr as { code?: string; message?: string; details?: string; hint?: string };
    console.error(
      `blockUser RPC failed code=${e.code ?? "-"} message=${e.message ?? "-"} ` +
      `details=${e.details ?? "-"} hint=${e.hint ?? "-"}`,
    );
    return fail("BLOCK_FAILED", rpcErr.message ?? "Block failed.", 500);
  }
  const row = Array.isArray(rpcData) ? rpcData[0] : rpcData;
  const alreadyBlocked = Boolean(row?.already_blocked);
  const roomsClosed = Number(row?.rooms_closed ?? 0);

  return ok({
    blocked_user_id: blockedId,
    already_blocked: alreadyBlocked,
    rooms_closed:    roomsClosed,
  });
});
