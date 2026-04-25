// expireMissedInvites — Getalong Edge Function (cron).

import { ok, fail, preflight } from "../_shared/response.ts";
import { admin, mapPgError } from "../_shared/auth.ts";

Deno.serve(async (req) => {
  const pre = preflight(req); if (pre) return pre;
  const { data, error } = await admin().rpc("expire_missed_invites");
  if (error) {
    const m = mapPgError(error);
    return fail(m.code, m.message, 500);
  }
  return ok({ expired_count: data ?? 0 });
});
