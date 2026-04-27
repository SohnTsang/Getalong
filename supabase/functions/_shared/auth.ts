// Shared auth + admin client helpers for Getalong Edge Functions.

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.44.4";
import { fail, GAErrorCode } from "./response.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY     = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

/// Verifies the Authorization: Bearer JWT and returns the user id.
export async function requireUserId(req: Request): Promise<string | Response> {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return fail("AUTH_REQUIRED", "Missing Authorization header.", 401);
  }
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data?.user) {
    return fail("AUTH_REQUIRED", "Invalid or expired session.", 401);
  }
  return data.user.id;
}

/// Service-role client. Bypasses RLS — only call from Edge Functions.
export function admin(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/// Maps a Postgres error from a P0001 raise to the JSON error contract.
/// Recognised codes are passed through; everything else is INTERNAL_ERROR.
export function mapPgError(err: unknown): { code: GAErrorCode; message: string } {
  // supabase-js surfaces { message, code, details, hint } for postgrest errors.
  const e = err as { message?: string; code?: string; details?: string };
  const text = (e?.message ?? "").trim();
  const known: GAErrorCode[] = [
    "AUTH_REQUIRED",
    "PROFILE_NOT_FOUND",
    "USER_BANNED",
    "RECEIVER_BANNED",
    "SELF_INVITE_NOT_ALLOWED",
    "BLOCKED_RELATIONSHIP",
    "LIVE_INVITE_SLOT_FULL",
    "DUPLICATE_LIVE_INVITE",
    "INVITE_NOT_FOUND",
    "INVITE_NOT_ACTIONABLE",
    "LIVE_INVITE_EXPIRED",
    "MISSED_INVITE_EXPIRED",
    "MISSED_ACCEPT_LIMIT_REACHED",
    "ACTIVE_CHAT_LIMIT_REACHED",
    "PRIORITY_INVITE_LIMIT_REACHED",
    "CHAT_ALREADY_EXISTS",
  ];
  for (const code of known) {
    if (text === code || text.endsWith(code)) {
      return { code, message: code };
    }
  }
  return { code: "INTERNAL_ERROR", message: text || "Unknown error" };
}

export async function readJson<T = Record<string, unknown>>(req: Request): Promise<T> {
  try { return await req.json() as T; } catch { return {} as T; }
}
