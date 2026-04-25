// expireMissedInvites — Getalong Edge Function (placeholder).
// See docs/EDGE_FUNCTIONS.md for the full contract.
//
// Sensitive logic (RLS bypass via service role) goes here.
// Replace this stub with the real implementation.

import { preflight, notImplemented } from "../_shared/response.ts";

Deno.serve((req) => {
  const pre = preflight(req);
  if (pre) return pre;
  return notImplemented("expireMissedInvites");
});
