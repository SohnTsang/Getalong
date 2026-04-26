// Shared response helpers for Getalong Edge Functions.
// Stable JSON contract: { ok: true, data } | { ok: false, error_code, message }.

export type GAErrorCode =
  | "AUTH_REQUIRED"
  | "PROFILE_NOT_FOUND"
  | "USER_BANNED"
  | "RECEIVER_BANNED"
  | "SELF_INVITE_NOT_ALLOWED"
  | "BLOCKED_RELATIONSHIP"
  | "LIVE_INVITE_SLOT_FULL"
  | "DUPLICATE_LIVE_INVITE"
  | "INVITE_NOT_FOUND"
  | "INVITE_NOT_ACTIONABLE"
  | "LIVE_INVITE_EXPIRED"
  | "MISSED_INVITE_EXPIRED"
  | "MISSED_ACCEPT_LIMIT_REACHED"
  | "ACTIVE_CHAT_LIMIT_REACHED"
  | "CHAT_ALREADY_EXISTS"
  | "INVALID_INPUT"
  | "NOT_IMPLEMENTED"
  | "INTERNAL_ERROR"
  | "RECEIVER_NOT_FOUND"
  | "ROOM_NOT_FOUND"
  | "ROOM_NOT_ACTIVE"
  | "NOT_ROOM_PARTICIPANT"
  | "EMPTY_MESSAGE"
  | "MESSAGE_TOO_LONG"
  | "INSERT_FAILED";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
};

export function ok<T>(data: T, status = 200): Response {
  return new Response(JSON.stringify({ ok: true, data }), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

export function fail(
  errorCode: GAErrorCode,
  message: string,
  status = 400,
): Response {
  return new Response(
    JSON.stringify({ ok: false, error_code: errorCode, message }),
    {
      status,
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    },
  );
}

export function preflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  return null;
}

export function notImplemented(name: string): Response {
  return fail(
    "NOT_IMPLEMENTED",
    `Edge Function "${name}" is a placeholder; implementation pending.`,
    501,
  );
}
