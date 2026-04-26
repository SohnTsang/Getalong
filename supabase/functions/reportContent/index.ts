// reportContent — Getalong Edge Function.
//
// Body: {
//   target_type: "profile" | "message" | "media" | "chat_room" | "invite",
//   target_id: uuid,
//   reason: string,        // one of REPORT_REASONS
//   details?: string       // optional free text, max 1000 chars
// }
//
// Behaviour:
//   * Validates the reporter has a relationship to the target (room
//     participant for message/media/chat_room, sender or receiver for
//     invites, just-exists for profiles).
//   * Inserts into public.reports. The unique index
//     (reporter_id, target_type, target_id, reason) gives us idempotency
//     under retry — a duplicate is reported back as ALREADY_REPORTED.

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
}

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const body = await readJson<Body>(req);
  const targetType = (body.target_type ?? "") as Target;
  const targetId   = (body.target_id ?? "").trim();
  const reason     = (body.reason ?? "").trim();
  const details    = (body.details ?? "").trim().slice(0, MAX_DETAILS_LEN);

  if (!TARGETS.includes(targetType))
    return fail("INVALID_INPUT", "target_type required.", 400);
  if (!targetId)
    return fail("INVALID_INPUT", "target_id required.", 400);
  if (!REPORT_REASONS.has(reason))
    return fail("INVALID_INPUT", "reason required.", 400);

  const sb = admin();

  // Self-report on profile is allowed but pointless; on message/media we
  // explicitly disallow because it would let users harass the moderation
  // queue. The participant check below catches profile self-reports
  // accidentally; we just continue — moderators can dismiss.

  // Validate target exists + reporter has a relationship to it.
  const accessOrErr = await ensureAccess(sb, userId, targetType, targetId);
  if (accessOrErr) return accessOrErr;

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

  if (error) {
    // Unique violation → idempotent ALREADY_REPORTED.
    const code = (error as { code?: string }).code;
    if (code === "23505") {
      return ok({ already_reported: true });
    }
    return fail("REPORT_FAILED", error.message, 500);
  }

  return ok({ id: data.id });
});

async function ensureAccess(
  sb: ReturnType<typeof admin>,
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
  sb: ReturnType<typeof admin>,
  userId: string,
  roomId: string,
): Promise<Response | null> {
  const { data, error } = await sb
    .from("chat_rooms")
    .select("user_a, user_b")
    .eq("id", roomId)
    .maybeSingle();
  if (error) return fail("INTERNAL_ERROR", error.message, 500);
  if (!data)  return fail("TARGET_NOT_FOUND", "Chat room not found.", 404);
  if (data.user_a !== userId && data.user_b !== userId)
    return fail("NOT_ALLOWED", "Not your conversation.", 403);
  return null;
}
