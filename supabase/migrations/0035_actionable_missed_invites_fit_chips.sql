-- 0035_actionable_missed_invites_fit_chips.sql
--
-- Surfaces the three Taipei-beta "conversation fit" columns on the
-- missed-invite sender JSON so the Invite-tab user card can render
-- the same coral/sage/wheat chips Discovery shows. The matching
-- columns already exist on `public.profiles` (migration 0034); this
-- migration only adds three keys to the embedded jsonb_build_object
-- inside `get_actionable_missed_invites`. No schema change, no
-- filter/order change, no permission change — strictly an additive
-- payload extension.
--
-- The live-invite path (PostgREST embedding inside
-- `InviteService.fetchIncomingLivePendingWithSender`) gets the same
-- three columns by extending its `select(...)` embed string on the
-- iOS side; no separate migration needed for that path.

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
                'id',                  p.id,
                'bio',                 p.bio,
                'gender',              p.gender,
                'gender_visible',      p.gender_visible,
                -- Taipei beta conversation-fit columns. All nullable
                -- so legacy profiles continue to decode safely; the
                -- client treats NULL as "chip not set" and just hides
                -- that chip.
                'connection_intent',   p.connection_intent,
                'lifestyle_rhythm',    p.lifestyle_rhythm,
                'conversation_domain', p.conversation_domain,
                'profile_tags',        coalesce(
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

-- Grants unchanged from migration 0028; re-issued here for safety
-- in case a future redeploy ever drops them.
revoke all on function public.get_actionable_missed_invites(int, int) from public;
grant execute on function public.get_actionable_missed_invites(int, int) to authenticated;

-- `get_actionable_missed_invite_count()` is intentionally not
-- modified — it returns only a distinct-sender count and never reads
-- the fit columns.
