-- discovery_missing_partner.sql
--
-- Diagnose why target user B never appears in user A's Discovery feed.
-- Run in the Supabase SQL editor. Replace the two UUIDs below.
--
-- This proves WHICH layer drops B:
--   * a hard exclusion (active room / blocked room / block row / live_pending), or
--   * B simply isn't status='deleted' (so no penalty path runs), or
--   * B is eligible and should be appearing (bug is elsewhere — capture
--     the Edge Function debug logs instead; see index.ts DISCOVERY_DEBUG_*).
--
-- Nothing here mutates data.

\set A '00000000-0000-0000-0000-000000000000'   -- current user (caller)
\set B '11111111-1111-1111-1111-111111111111'   -- the partner who won't appear

-- 1. Profile B eligibility (must be: exists, not banned, not deleted).
select 'profile_B' as check,
       id, getalong_id, is_banned, deleted_at,
       (id is not null and is_banned = false and deleted_at is null) as eligible
  from public.profiles
 where id = :'B';

-- 2. Block hard-exclusion (either direction). Any row here = B is hard-excluded.
select 'blocks' as check, blocker_id, blocked_id, created_at
  from public.blocks
 where (blocker_id = :'A' and blocked_id = :'B')
    or (blocker_id = :'B' and blocked_id = :'A');

-- 3. ALL chat_rooms between A and B, newest first. This is the decisive check.
--    * any status='active' row  -> B is HARD-EXCLUDED (correct behaviour;
--      a newer active room exists, e.g. B re-invited A after the delete).
--    * status='blocked'/'archived' -> NOT excluded by the active query, NOT
--      penalised by the deleted query -> B is simply absent from any penalty.
--    * status='deleted' with deleted_at set -> the intended soft-penalty path.
select 'chat_rooms' as check,
       id, status, deleted_at, deleted_by, created_at,
       case
         when status = 'active'  then 'HARD-EXCLUDED (active room exists)'
         when status = 'deleted' and deleted_at is not null then
           case
             when deleted_at >= now() - interval '7 days'  then 'penalty 20 (strong, <=7d)'
             when deleted_at >= now() - interval '30 days' then 'penalty 8 (weak, <=30d)'
             else 'penalty 0 (older than 30d) — ranks like a fresh stranger'
           end
         when status in ('blocked','archived') then
           'NOT excluded, NOT penalised — falls through with band 0 (should appear!)'
         else 'unexpected status'
       end as discovery_effect
  from public.chat_rooms
 where (user_a = :'A' and user_b = :'B')
    or (user_a = :'B' and user_b = :'A')
 order by created_at desc;

-- 4. live_pending invite hard-exclusion (either direction, still ticking).
select 'live_pending_invites' as check,
       id, sender_id, receiver_id, status, live_expires_at,
       (live_expires_at > now()) as still_live
  from public.invites
 where status = 'live_pending'
   and live_expires_at > now()
   and ((sender_id = :'A' and receiver_id = :'B')
     or (sender_id = :'B' and receiver_id = :'A'));

-- 5. Candidate-window sanity: how many profiles are eligible AND newer than B?
--    If this count is >= 200, B falls outside the range(0,199) fetch window
--    (the latent Task-2 bug). In a beta pool this should be far below 200.
select 'window_pressure' as check,
       count(*) filter (where p.is_banned = false and p.deleted_at is null) as total_eligible,
       count(*) filter (
         where p.is_banned = false and p.deleted_at is null
           and p.created_at > (select created_at from public.profiles where id = :'B')
       ) as eligible_newer_than_B,
       200 as fetch_window
  from public.profiles p;
