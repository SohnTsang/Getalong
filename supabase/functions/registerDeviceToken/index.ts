// registerDeviceToken — Getalong Edge Function.
//
// Body: {
//   token: string,                       // APNs device token (hex)
//   platform?: "ios" | "android",        // default "ios"
//   environment?: "sandbox" | "production", // default "sandbox"
//   device_id?: string,
//   app_version?: string,
//   locale?: string,
//   timezone?: string
// }
//
// Behaviour:
//   * Requires auth.
//   * Upserts on (user_id, token) — marks active and bumps last_seen_at.
//   * Service role is used so the upsert side-effects (re-activating a
//     previously deactivated token, updating environment when a build
//     switches sandbox→production) are deterministic and don't depend on
//     RLS update predicates.

import { ok, fail, preflight } from "../_shared/response.ts";
import { requireUserId, admin, readJson } from "../_shared/auth.ts";

interface Body {
  token?: string;
  platform?: string;
  environment?: string;
  device_id?: string;
  app_version?: string;
  locale?: string;
  timezone?: string;
}

const HEX_RE = /^[0-9a-fA-F]{32,256}$/;

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  if (req.method !== "POST") return fail("INVALID_INPUT", "POST required.", 405);

  const userOrErr = await requireUserId(req);
  if (typeof userOrErr !== "string") return userOrErr;
  const userId = userOrErr;

  const body = await readJson<Body>(req);
  const token = (body.token ?? "").trim();
  if (!token || !HEX_RE.test(token)) {
    return fail("INVALID_INPUT", "token (hex) required.", 400);
  }

  const platform = body.platform === "android" ? "android" : "ios";
  const environment =
    body.environment === "production" ? "production" : "sandbox";

  const sb = admin();

  const { data, error } = await sb
    .from("device_tokens")
    .upsert(
      {
        user_id: userId,
        token,
        platform,
        environment,
        device_id: body.device_id ?? null,
        app_version: body.app_version ?? null,
        locale: body.locale ?? null,
        timezone: body.timezone ?? null,
        is_active: true,
        last_seen_at: new Date().toISOString(),
      },
      { onConflict: "user_id,token" },
    )
    .select("id, user_id, token, environment, is_active, last_seen_at")
    .single();

  if (error) return fail("INTERNAL_ERROR", error.message, 500);

  return ok({
    id: data.id,
    is_active: data.is_active,
    environment: data.environment,
    last_seen_at: data.last_seen_at,
  });
});
