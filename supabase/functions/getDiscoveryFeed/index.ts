// getDiscoveryFeed — Getalong Edge Function (placeholder).
// See docs/EDGE_FUNCTIONS.md for the full contract.
//
// Sensitive logic (RLS bypass via service role) goes here.
// Replace this stub with the real implementation.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { preflight, notImplemented } from "../_shared/response.ts";

serve((req) => {
  const pre = preflight(req);
  if (pre) return pre;
  return notImplemented("getDiscoveryFeed");
});
