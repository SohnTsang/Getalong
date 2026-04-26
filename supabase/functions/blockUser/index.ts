// blockUser — Getalong Edge Function.
//
// Body: { blocked_user_id?: uuid, blocked_handle?: string }
//
// Behaviour:
//   * Inserts a row into public.blocks. Idempotent — a repeated block on
//     the same user returns ok with already_blocked = true.
//   * Cancels any active live_pending invites between the two users in
//     either direction so a stale 15-second timer can't surface after the
//     block is in place.
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

  // Idempotent insert. Existing row → already_blocked.
  const { error: insErr } = await sb
    .from("blocks")
    .insert({ blocker_id: blockerId, blocked_id: blockedId });
  let alreadyBlocked = false;
  if (insErr) {
    const code = (insErr as { code?: string }).code;
    if (code === "23505") {
      alreadyBlocked = true;
    } else {
      return fail("BLOCK_FAILED", insErr.message, 500);
    }
  }

  // Tear down active live_pending invites between the two users so the
  // receiver doesn't see a stale countdown after the block lands.
  const { error: cancelErr } = await sb
    .from("invites")
    .update({ status: "cancelled" })
    .eq("status", "live_pending")
    .or(
      `and(sender_id.eq.${blockerId},receiver_id.eq.${blockedId}),` +
      `and(sender_id.eq.${blockedId},receiver_id.eq.${blockerId})`
    );
  if (cancelErr) console.warn("blockUser: cancel invites failed:", cancelErr.message);

  return ok({
    blocked_user_id: blockedId,
    already_blocked: alreadyBlocked,
  });
});
