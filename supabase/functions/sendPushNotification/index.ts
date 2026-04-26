// sendPushNotification — Getalong Edge Function.
//
// Two roles:
//   1. Manual invocation for testing — supply { user_id, kind } or
//      { user_id, alerts } and the function delivers via APNs.
//   2. Internal callable used by other Edge Functions (sendLiveInvite,
//      acceptLiveInvite, acceptMissedInvite, createChatMessage). They
//      authenticate with the service-role key.
//
// Body:
//   {
//     user_id: uuid,                                     // required
//     kind?: "live_signal_received" | "conversation_started" | "new_message",
//     alerts?: { en: {title,body}, ja?: {...}, "zh-Hant"?: {...} },
//     data?: Record<string, unknown>,                    // optional custom payload
//     collapse_id?: string,
//     thread_id?: string
//   }
//
// Auth: requires either a valid Bearer JWT (any signed-in user — used in dev
// to test from the CLI) or a service-role bearer token (matches
// SUPABASE_SERVICE_ROLE_KEY in env). The latter is how internal callers
// invoke this function.

import { ok, fail, preflight } from "../_shared/response.ts";
import { readJson } from "../_shared/auth.ts";
import {
  pushToUser,
  PUSH_LIVE_SIGNAL_RECEIVED,
  PUSH_CONVERSATION_STARTED,
  PUSH_NEW_MESSAGE,
  PushPerLocaleAlert,
} from "../_shared/apns.ts";

interface Body {
  user_id?: string;
  kind?: string;
  alerts?: PushPerLocaleAlert;
  data?: Record<string, unknown>;
  collapse_id?: string;
  thread_id?: string;
}

const KIND_PRESETS: Record<string, PushPerLocaleAlert> = {
  live_signal_received:  PUSH_LIVE_SIGNAL_RECEIVED,
  conversation_started:  PUSH_CONVERSATION_STARTED,
  new_message:           PUSH_NEW_MESSAGE,
};

function authorize(req: Request): boolean {
  const auth = (req.headers.get("Authorization") ?? "").trim();
  if (!auth.toLowerCase().startsWith("bearer ")) return false;
  const token = auth.slice(7).trim();
  // Accept the service-role key for internal callers.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (serviceKey && token === serviceKey) return true;
  // Otherwise we trust any non-empty bearer (anon/user JWTs). Supabase's
  // function gateway already verified it is a valid project JWT before we
  // saw the request.
  return token.length > 0;
}

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);
  if (!authorize(req))       return fail("AUTH_REQUIRED", "Auth required.", 401);

  const body = await readJson<Body>(req);
  if (!body.user_id) return fail("INVALID_INPUT", "user_id required.", 400);

  let alerts: PushPerLocaleAlert | undefined = body.alerts;
  if (!alerts && body.kind && KIND_PRESETS[body.kind]) {
    alerts = KIND_PRESETS[body.kind];
  }
  if (!alerts) {
    return fail("INVALID_INPUT", "kind or alerts required.", 400);
  }

  const result = await pushToUser(body.user_id, alerts, {
    data:       body.data,
    collapseId: body.collapse_id,
    threadId:   body.thread_id,
  });

  return ok(result);
});
