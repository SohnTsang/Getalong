// reportContent — Getalong Edge Function.
//
// Body: {
//   target_type: "profile" | "message" | "media" | "chat_room" | "invite",
//   target_id: uuid,
//   reason: string,        // one of REPORT_REASONS
//   details?: string,      // optional free text, max 1000 chars
//   context_room_id?: uuid // ONLY used for target_type='profile' to
//                          // scope evidence preservation to the chat
//                          // the report was filed from. Ignored for
//                          // other target types (which already carry
//                          // their own room scope).
// }
//
// Behaviour:
//   * Validates the reporter has a relationship to the target (room
//     participant for message/media/chat_room, sender or receiver for
//     invites, just-exists for profiles).
//   * Inserts into public.reports. The unique index
//     (reporter_id, target_type, target_id, reason) gives us idempotency
//     under retry — a duplicate is reported back as ALREADY_REPORTED.
//   * Preserves relevant view-once media bytes by setting
//     moderation_hold_at on the media row(s) so cleanup_expired_media
//     skips them. Scope follows the target:
//       - media        → that one media asset
//       - message      → that message's media (if any)
//       - chat_room    → all media still in that room (one UPDATE)
//       - profile      → only when context_room_id is supplied AND the
//                        reporter is a participant; scoped to that
//                        room's media. Never room-less.
//       - invite       → no media preservation.
//   * Already-deleted media (storage_deleted_at IS NOT NULL) is left
//     alone — bytes are gone, there is nothing to preserve, and the
//     report still succeeds.
//   * Duplicate reports still re-apply the moderation hold so a re-tap
//     after a network drop can't leave evidence unprotected.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";

type Target = "profile" | "message" | "media" | "chat_room" | "invite";

const TARGETS: Target[] = ["profile", "message", "media", "chat_room", "invite"];

const REPORT_REASONS = new Set([
  "harassment",
  "sexual",
  "hate",
  "scam",
  "underage",
  "self_harm",
  "other",
]);

const MAX_DETAILS_LEN = 1000;

interface Body {
  target_type?: string;
  target_id?: string;
  reason?: string;
  details?: string;
  context_room_id?: string;
}

type SbAdmin = ReturnType<typeof admin>;

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const body = await readJson<Body>(req);
  const targetType    = (body.target_type ?? "") as Target;
  const targetId      = (body.target_id ?? "").trim();
  const reason        = (body.reason ?? "").trim();
  const details       = (body.details ?? "").trim().slice(0, MAX_DETAILS_LEN);
  const contextRoomId = (body.context_room_id ?? "").trim();

  if (!TARGETS.includes(targetType))
    return fail("INVALID_INPUT", "target_type required.", 400);
  if (!targetId)
    return fail("INVALID_INPUT", "target_id required.", 400);
  if (!REPORT_REASONS.has(reason))
    return fail("INVALID_INPUT", "reason required.", 400);

  const sb = admin();

  // Validate target exists + reporter has a relationship to it.
  const accessOrErr = await ensureAccess(sb, userId, targetType, targetId);
  if (accessOrErr) return accessOrErr;

  // For target_type='profile', validate the optional context_room_id
  // *before* writing the report. We don't reject the report when the
  // context check fails — we just drop the context. A reporter who
  // names a room they aren't in shouldn't be able to put that room's
  // media on hold.
  let scopedRoomForProfile: string | null = null;
  if (targetType === "profile" && contextRoomId.length > 0) {
    const room = await loadRoom(sb, contextRoomId);
    if (room && (room.user_a === userId || room.user_b === userId)) {
      scopedRoomForProfile = contextRoomId;
    }
  }

  // Insert the report row first, so we have an id to stamp on the
  // moderation hold. A duplicate reporter+target+reason returns the
  // existing row's id.
  const { reportId, alreadyReported, insertError } =
    await insertOrFetchReport(sb, userId, targetType, targetId, reason, details);
  if (insertError) return insertError;

  // Apply moderation holds. Failures here are logged but never break
  // the report — the user-facing flow is "we got it" regardless.
  const holdReason = `report:${reason}`;
  try {
    switch (targetType) {
      case "media":
        await holdMediaById(sb, targetId, holdReason, reportId);
        break;
      case "message":
        await holdMediaForMessage(sb, targetId, holdReason, reportId);
        break;
      case "chat_room":
        await holdRoom(sb, targetId, holdReason, reportId);
        break;
      case "profile":
        if (scopedRoomForProfile) {
          await holdRoom(sb, scopedRoomForProfile, holdReason, reportId);
        }
        break;
      case "invite":
        // No media preservation for invite reports.
        break;
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.warn("reportContent: moderation hold failed:", msg);
  }

  if (alreadyReported) return ok({ already_reported: true });
  return ok({ id: reportId });
});

// ---------------------------------------------------------------------------

async function insertOrFetchReport(
  sb: SbAdmin,
  userId: string,
  targetType: Target,
  targetId: string,
  reason: string,
  details: string,
): Promise<{ reportId: string | null; alreadyReported: boolean; insertError: Response | null }> {
  const { data, error } = await sb
    .from("reports")
    .insert({
      reporter_id: userId,
      target_type: targetType,
      target_id:   targetId,
      reason,
      details:     details.length > 0 ? details : null,
    })
    .select("id")
    .single();

  if (!error && data) {
    return { reportId: data.id as string, alreadyReported: false, insertError: null };
  }

  // Unique violation → look up the existing report's id so the hold
  // logic can still attach itself to a real report row.
  const code = (error as { code?: string } | null)?.code;
  if (code === "23505") {
    const { data: existing, error: lookupErr } = await sb
      .from("reports")
      .select("id")
      .eq("reporter_id", userId)
      .eq("target_type", targetType)
      .eq("target_id",   targetId)
      .eq("reason",      reason)
      .maybeSingle();
    if (lookupErr) {
      return { reportId: null, alreadyReported: true,
               insertError: fail("REPORT_FAILED", lookupErr.message, 500) };
    }
    return {
      reportId:        existing?.id as string ?? null,
      alreadyReported: true,
      insertError:     null,
    };
  }

  return {
    reportId: null,
    alreadyReported: false,
    insertError: fail("REPORT_FAILED", error?.message ?? "report failed", 500),
  };
}

async function ensureAccess(
  sb: SbAdmin,
  userId: string,
  targetType: Target,
  targetId: string,
): Promise<Response | null> {
  switch (targetType) {
    case "profile": {
      const { data, error } = await sb
        .from("profiles").select("id").eq("id", targetId).maybeSingle();
      if (error) return fail("INTERNAL_ERROR", error.message, 500);
      if (!data)  return fail("TARGET_NOT_FOUND", "Profile not found.", 404);
      return null;
    }
    case "message": {
      const { data, error } = await sb
        .from("messages")
        .select("id, room_id")
        .eq("id", targetId)
        .maybeSingle();
      if (error) return fail("INTERNAL_ERROR", error.message, 500);
      if (!data)  return fail("TARGET_NOT_FOUND", "Message not found.", 404);
      return await assertRoomParticipant(sb, userId, data.room_id);
    }
    case "media": {
      const { data, error } = await sb
        .from("media_assets")
        .select("id, room_id")
        .eq("id", targetId)
        .maybeSingle();
      if (error) return fail("INTERNAL_ERROR", error.message, 500);
      if (!data)  return fail("TARGET_NOT_FOUND", "Media not found.", 404);
      return await assertRoomParticipant(sb, userId, data.room_id);
    }
    case "chat_room": {
      return await assertRoomParticipant(sb, userId, targetId);
    }
    case "invite": {
      const { data, error } = await sb
        .from("invites")
        .select("id, sender_id, receiver_id")
        .eq("id", targetId)
        .maybeSingle();
      if (error) return fail("INTERNAL_ERROR", error.message, 500);
      if (!data)  return fail("TARGET_NOT_FOUND", "Invite not found.", 404);
      if (data.sender_id !== userId && data.receiver_id !== userId)
        return fail("NOT_ALLOWED", "Not your invite.", 403);
      return null;
    }
  }
}

async function assertRoomParticipant(
  sb: SbAdmin,
  userId: string,
  roomId: string,
): Promise<Response | null> {
  const room = await loadRoom(sb, roomId);
  if (!room)  return fail("TARGET_NOT_FOUND", "Chat room not found.", 404);
  if (room.user_a !== userId && room.user_b !== userId)
    return fail("NOT_ALLOWED", "Not your conversation.", 403);
  return null;
}

async function loadRoom(
  sb: SbAdmin,
  roomId: string,
): Promise<{ id: string; user_a: string; user_b: string } | null> {
  const { data, error } = await sb
    .from("chat_rooms")
    .select("id, user_a, user_b")
    .eq("id", roomId)
    .maybeSingle();
  if (error || !data) return null;
  return data as { id: string; user_a: string; user_b: string };
}

// ---------------------------------------------------------------------------
// Moderation hold helpers. All of these are best-effort: they no-op on
// already-deleted bytes, on missing rows, and on duplicate report id
// stamps (the hold may already be set from an earlier report — we only
// overwrite when the column is null).

async function holdMediaById(
  sb: SbAdmin,
  mediaId: string,
  reasonText: string,
  reportId: string | null,
): Promise<void> {
  // Only stamp moderation_hold_at if storage still exists. We don't
  // clobber an existing hold (preserve the original report id /
  // reason) unless this row had no hold yet.
  await sb
    .from("media_assets")
    .update({
      moderation_hold_at:        new Date().toISOString(),
      moderation_hold_reason:    reasonText,
      moderation_hold_report_id: reportId,
    })
    .eq("id", mediaId)
    .is("storage_deleted_at", null)
    .is("moderation_hold_at", null);
}

async function holdMediaForMessage(
  sb: SbAdmin,
  messageId: string,
  reasonText: string,
  reportId: string | null,
): Promise<void> {
  const { data, error } = await sb
    .from("messages")
    .select("id, media_id")
    .eq("id", messageId)
    .maybeSingle();
  if (error || !data || !data.media_id) return;
  await holdMediaById(sb, data.media_id as string, reasonText, reportId);
}

async function holdRoom(
  sb: SbAdmin,
  roomId: string,
  reasonText: string,
  reportId: string | null,
): Promise<void> {
  // Stamp the room itself so the hold survives even if every row in
  // media_assets has already been cleaned up.
  await sb
    .from("chat_rooms")
    .update({
      moderation_hold_at:        new Date().toISOString(),
      moderation_hold_reason:    reasonText,
      moderation_hold_report_id: reportId,
    })
    .eq("id", roomId)
    .is("moderation_hold_at", null);

  // Single UPDATE for every still-existing media row in the room.
  // Scoped to room_id and storage_deleted_at IS NULL so we don't
  // resurrect bytes that are already gone.
  await sb
    .from("media_assets")
    .update({
      moderation_hold_at:        new Date().toISOString(),
      moderation_hold_reason:    reasonText,
      moderation_hold_report_id: reportId,
    })
    .eq("room_id", roomId)
    .is("storage_deleted_at", null)
    .is("moderation_hold_at", null);
}
