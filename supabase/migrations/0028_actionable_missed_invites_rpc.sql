-- 0028_actionable_missed_invites_rpc.sql
--
-- Moves the "actionable missed invite" rule fully to the backend so
-- the client doesn't need to fetch all active chat rooms just to
-- decide what to show on the Missed tab. Previously iOS ran
-- `ChatService.fetchRooms()` in parallel with the invite query and
-- filtered client-side — one extra round trip per refresh per
-- subscriber. The badge query downloaded full invite rows just to
-- count distinct senders.
--
-- Two RPCs added:
--
--   * `get_actionable_missed_invites(p_limit, p_offset)`
--     returns the same shape `fetchMissedInvitesWithSender` used
--     (invite columns + sender JSON with bio / gender / gender_visible
--     / profile_tags), filtered so rows whose pair already has an
--     active chat are excluded server-side. Returns SETOF jsonb;
--     PostgREST surfaces the result as a plain JSON array of
--     invite-shaped objects.
--
--   * `get_actionable_missed_invite_count()`
--     returns the distinct-sender count using the same exclusion. The
--     UI dedupes missed cards by sender, so the badge must too — a
--     row-level count would over-report.
--
-- Both functions:
--   * are SECURITY DEFINER with `set search_path = public` so they
--     can't be hijacked by a caller-controlled schema path,
--   * filter on `i.receiver_id = auth.uid()` explicitly so a caller
--     can't read another user's missed invites,
--   * are granted to `authenticated` only (revoked from PUBLIC).
--
-- Indexes already cover the hot path:
--   * `invites_receiver_status_idx` (receiver_id, status, created_at desc)
--     — migration 0001 — drives the outer scan.
--   * `chat_rooms_user_a_idx` / `chat_rooms_user_b_idx` — migration
--     0001 — support the NOT EXISTS pair lookup. The partial
--     `chat_rooms_one_active_per_pair_idx` from migration 0019 covers
--     canonical-pair lookups but the NOT EXISTS uses raw `user_a/user_b`
--     filters, so the original two indexes are the operative ones.

-- =========================================================================
-- List RPC
-- =========================================================================

create or replace function public.get_actionable_missed_invites(
  p_limit  int default 200,
  p_offset int default 0
)
returns setof jsonb
language sql
security definer
stable
set search_path = public
as $$
  select to_jsonb(i.*)
       || jsonb_build_object(
            'sender',
            (
              select jsonb_build_object(
                'id',             p.id,
                'bio',            p.bio,
                'gender',         p.gender,
                'gender_visible', p.gender_visible,
                'profile_tags',   coalesce(
                  (
                    select jsonb_agg(
                             jsonb_build_object('tag', pt.tag)
                             order by pt.tag
                           )
                      from public.profile_tags pt
                     where pt.profile_id = p.id
                  ),
                  '[]'::jsonb
                )
              )
              from public.profiles p
              where p.id = i.sender_id
            )
          )
    from public.invites i
   where i.receiver_id = auth.uid()
     and i.status = 'missed'
     and not exists (
       select 1
         from public.chat_rooms r
        where r.status = 'active'
          and (
            (r.user_a = i.sender_id and r.user_b = auth.uid())
            or
            (r.user_a = auth.uid()  and r.user_b = i.sender_id)
          )
     )
   order by i.created_at desc
   limit  p_limit
   offset p_offset;
$$;

revoke all on function public.get_actionable_missed_invites(int, int) from public;
grant execute on function public.get_actionable_missed_invites(int, int) to authenticated;

-- =========================================================================
-- Count RPC (distinct senders, matches the UI's dedupe-by-sender rule)
-- =========================================================================

create or replace function public.get_actionable_missed_invite_count()
returns int
language sql
security definer
stable
set search_path = public
as $$
  select count(distinct i.sender_id)::int
    from public.invites i
   where i.receiver_id = auth.uid()
     and i.status = 'missed'
     and not exists (
       select 1
         from public.chat_rooms r
        where r.status = 'active'
          and (
            (r.user_a = i.sender_id and r.user_b = auth.uid())
            or
            (r.user_a = auth.uid()  and r.user_b = i.sender_id)
          )
     );
$$;

revoke all on function public.get_actionable_missed_invite_count() from public;
grant execute on function public.get_actionable_missed_invite_count() to authenticated;
