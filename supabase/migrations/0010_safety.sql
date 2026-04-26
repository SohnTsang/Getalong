-- Getalong: safety hardening for reports + blocks.
--
-- Extends reports.target_type to include 'chat_room' and 'invite' so a
-- single sheet covers everything users can flag in chat/signals. Adds a
-- partial unique index so the same reporter cannot file the exact same
-- (target_type, target_id, reason) twice — the function returns
-- ALREADY_REPORTED instead.

alter table public.reports
  drop constraint if exists reports_target_type_check;

alter table public.reports
  add constraint reports_target_type_check
  check (target_type in (
    'profile',
    'post',
    'message',
    'media',
    'chat_room',
    'invite'
  ));

-- Dedup: one open/active report per (reporter, target_type, target_id,
-- reason). Uses a unique index so we can detect collisions in the function
-- and return ALREADY_REPORTED. Reason is included so a user can re-flag
-- the same thing under a different category.
create unique index if not exists reports_reporter_target_reason_idx
  on public.reports (reporter_id, target_type, target_id, reason);

-- Helpful read indexes for future moderation tools.
create index if not exists reports_reporter_idx
  on public.reports (reporter_id, created_at desc);
