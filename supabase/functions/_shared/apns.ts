// Shared APNs HTTP/2 sender for Getalong.
//
// Uses APNs token-based auth (ES256 JWT) and the HTTP/2 APIs of api.push.apple.com
// / api.sandbox.push.apple.com. Deno's fetch automatically negotiates HTTP/2.
//
// Environment variables read from Supabase secrets:
//   APNS_AUTH_KEY_P8   – PKCS#8 PEM body of the .p8 key
//   APNS_KEY_ID        – 10-char Apple key id
//   APNS_TEAM_ID       – 10-char Apple team id
//   APNS_BUNDLE_ID     – iOS bundle id (apns-topic)
//   APNS_USE_SANDBOX   – "true" to force sandbox endpoint (default true while in dev)
//
// Per-call:
//   environment field on each device_tokens row picks sandbox vs production
//   when APNS_USE_SANDBOX is unset. When APNS_USE_SANDBOX is "true" everything
//   goes to sandbox; "false" forces production.

import { admin } from "./auth.ts";

export interface PushAlert {
  title: string;
  body: string;
}

export interface PushExtras {
  /// e.g. { type: "live_invite", invite_id: "..." }
  data?: Record<string, unknown>;
  /// "alert" | "background"
  pushType?: "alert" | "background";
  badge?: number;
  sound?: string;
  category?: string;
  threadId?: string;
  collapseId?: string;
  expiresAtUnix?: number;
}

export type LocaleCode = "en" | "ja" | "zh-Hant";

const LOCALE_FALLBACK: LocaleCode = "en";

/// Pick the best matching server-side locale from a free-form locale string
/// such as "en-US", "ja_JP", "zh-Hant-TW". Defaults to English.
export function normalizeLocale(raw: string | null | undefined): LocaleCode {
  if (!raw) return LOCALE_FALLBACK;
  const lower = raw.toLowerCase().replace(/_/g, "-");
  if (lower.startsWith("ja")) return "ja";
  if (
    lower.startsWith("zh-hant") ||
    lower.startsWith("zh-tw") ||
    lower.startsWith("zh-hk") ||
    lower.startsWith("zh-mo")
  ) return "zh-Hant";
  if (lower.startsWith("zh")) return "zh-Hant";
  return "en";
}

// =========================================================================
// APNs JWT (ES256)
// =========================================================================

interface CachedJWT { token: string; iat: number }
let cachedJWT: CachedJWT | null = null;

/// APNs requires the JWT be reused for at least 20 minutes and refreshed
/// within 60 minutes. Refresh every 45 minutes to be safe.
const JWT_LIFETIME_SECONDS = 45 * 60;

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const cleaned = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(cleaned);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

function b64url(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function b64urlString(s: string): string {
  return b64url(new TextEncoder().encode(s));
}

async function importApnsKey(pem: string): Promise<CryptoKey> {
  // Support both raw base64 and full PEM. Normalise to PEM-stripped bytes.
  const buf = pemToArrayBuffer(pem);
  return await crypto.subtle.importKey(
    "pkcs8",
    buf,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function mintJWT(): Promise<string> {
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const keyId  = Deno.env.get("APNS_KEY_ID");
  const pem    = Deno.env.get("APNS_AUTH_KEY_P8");
  if (!teamId || !keyId || !pem) {
    throw new Error("APNs env not configured (APNS_TEAM_ID/APNS_KEY_ID/APNS_AUTH_KEY_P8).");
  }

  const iat = Math.floor(Date.now() / 1000);
  const header = b64urlString(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const payload = b64urlString(JSON.stringify({ iss: teamId, iat }));
  const signingInput = `${header}.${payload}`;

  const key = await importApnsKey(pem);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${b64url(new Uint8Array(sig))}`;
}

async function getJWT(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.iat < JWT_LIFETIME_SECONDS) {
    return cachedJWT.token;
  }
  const token = await mintJWT();
  cachedJWT = { token, iat: now };
  return token;
}

// =========================================================================
// Send
// =========================================================================

interface DeviceTokenRow {
  id: string;
  token: string;
  environment: "sandbox" | "production";
  locale: string | null;
}

export interface PushPerLocaleAlert {
  en: PushAlert;
  ja?: PushAlert;
  "zh-Hant"?: PushAlert;
}

export interface SendPushResult {
  attempted: number;
  sent: number;
  failed: number;
  deactivated: number;
  errors: Array<{ token_id: string; status: number; reason: string }>;
}

function endpointFor(env: "sandbox" | "production"): string {
  const force = (Deno.env.get("APNS_USE_SANDBOX") ?? "").toLowerCase();
  if (force === "true")  return "https://api.sandbox.push.apple.com";
  if (force === "false") return "https://api.push.apple.com";
  return env === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com";
}

function pickAlert(alerts: PushPerLocaleAlert, locale: LocaleCode): PushAlert {
  if (locale === "ja"      && alerts.ja)      return alerts.ja;
  if (locale === "zh-Hant" && alerts["zh-Hant"]) return alerts["zh-Hant"]!;
  return alerts.en;
}

/// Sends a push notification to every active device token for `userId`.
/// Best-effort: failures are logged and reported in the result, but the
/// caller should never let a push failure surface to the user.
export async function pushToUser(
  userId: string,
  alerts: PushPerLocaleAlert,
  extras: PushExtras = {},
): Promise<SendPushResult> {
  const sb = admin();
  const { data: rows, error } = await sb
    .from("device_tokens")
    .select("id, token, environment, locale")
    .eq("user_id", userId)
    .eq("is_active", true);

  const result: SendPushResult = {
    attempted: 0, sent: 0, failed: 0, deactivated: 0, errors: [],
  };

  if (error) {
    console.warn("pushToUser: failed to load device tokens", error.message);
    return result;
  }
  const tokens = (rows ?? []) as DeviceTokenRow[];
  if (tokens.length === 0) return result;

  const bundleId = Deno.env.get("APNS_BUNDLE_ID");
  if (!bundleId) {
    console.warn("pushToUser: APNS_BUNDLE_ID not configured");
    return result;
  }

  let jwt: string;
  try { jwt = await getJWT(); }
  catch (e) {
    console.warn("pushToUser: failed to mint JWT:", (e as Error).message);
    return result;
  }

  const pushType = extras.pushType ?? "alert";

  await Promise.all(tokens.map(async (row) => {
    result.attempted++;
    const url = `${endpointFor(row.environment)}/3/device/${row.token}`;
    const alert = pickAlert(alerts, normalizeLocale(row.locale));

    const aps: Record<string, unknown> = { alert };
    if (extras.sound !== undefined)    aps.sound    = extras.sound;
    else                               aps.sound    = "default";
    if (extras.badge !== undefined)    aps.badge    = extras.badge;
    if (extras.category)               aps.category = extras.category;
    if (extras.threadId)               aps["thread-id"] = extras.threadId;

    const payload = { aps, ...(extras.data ?? {}) };
    const headers: Record<string, string> = {
      authorization: `bearer ${jwt}`,
      "apns-topic": bundleId,
      "apns-push-type": pushType,
      "content-type": "application/json",
    };
    if (extras.collapseId)    headers["apns-collapse-id"] = extras.collapseId;
    if (extras.expiresAtUnix) headers["apns-expiration"]  = String(extras.expiresAtUnix);

    try {
      const res = await fetch(url, {
        method: "POST",
        headers,
        body: JSON.stringify(payload),
      });
      if (res.status === 200) {
        result.sent++;
        return;
      }

      // Read APNs reason if any.
      let reason = "";
      try {
        const text = await res.text();
        if (text) {
          try { reason = JSON.parse(text)?.reason ?? text; }
          catch { reason = text; }
        }
      } catch { /* swallow */ }

      result.failed++;
      result.errors.push({ token_id: row.id, status: res.status, reason });

      // Deactivate on permanent failures.
      if (res.status === 410 || reason === "Unregistered" ||
          reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic") {
        const { error: dErr } = await sb
          .from("device_tokens")
          .update({ is_active: false })
          .eq("id", row.id);
        if (!dErr) result.deactivated++;
      }
    } catch (e) {
      result.failed++;
      result.errors.push({
        token_id: row.id, status: 0,
        reason: (e as Error).message ?? "fetch failed",
      });
    }
  }));

  return result;
}

// =========================================================================
// Canonical Getalong notifications
// =========================================================================

export const PUSH_LIVE_SIGNAL_RECEIVED: PushPerLocaleAlert = {
  en: {
    title: "New Live Signal",
    body:  "Someone sent you a signal. Respond before it fades.",
  },
  ja: {
    title: "ライブのきっかけが届きました",
    body:  "きっかけが届いています。今なら会話につながるかもしれません。",
  },
  "zh-Hant": {
    title: "收到即時訊號",
    body:  "有人向你送出訊號。趁現在回應，可能就能開始對話。",
  },
};

export const PUSH_CONVERSATION_STARTED: PushPerLocaleAlert = {
  en: {
    title: "Conversation started",
    body:  "Your signal clicked. Start talking when you're ready.",
  },
  ja: {
    title: "会話がはじまりました",
    body:  "きっかけがつながりました。準備ができたら話してみましょう。",
  },
  "zh-Hant": {
    title: "對話已開始",
    body:  "你的訊號有了回應。準備好時，就開始聊聊吧。",
  },
};

export const PUSH_NEW_MESSAGE: PushPerLocaleAlert = {
  en: {
    title: "New message",
    body:  "You have a new message on Getalong.",
  },
  ja: {
    title: "新しいメッセージ",
    body:  "Getalongに新しいメッセージが届いています。",
  },
  "zh-Hant": {
    title: "新訊息",
    body:  "你在 Getalong 收到一則新訊息。",
  },
};
