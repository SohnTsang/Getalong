-- 0016_chat_room_soft_delete.sql
--
-- Adds a soft-delete state to chat_rooms so a participant can remove a
-- conversation from their list and free a slot under the active-chat
-- limit. We never hard-delete rows here — moderation/reporting and
-- view-once media cleanup all rely on row history persisting.
--
-- Status flows:
--   'active'  → ('archived' | 'blocked' | 'deleted')
--   'deleted' is a terminal state for the conversation (no resurrection).
--
-- Both participants share the same row, so deletion is room-level: when
-- one user deletes, the conversation disappears for both. This is the
-- simpler MVP model and matches how the active-chat limit is computed.

alter table public.chat_rooms
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid references public.profiles(id) on delete set null;

-- Replace the status check constraint to accept 'deleted'.
alter table public.chat_rooms
  drop constraint if exists chat_rooms_status_check;

alter table public.chat_rooms
  add constraint chat_rooms_status_check
  check (status in ('active', 'archived', 'blocked', 'deleted'));

create index if not exists chat_rooms_status_idx
  on public.chat_rooms (status);

-- _ga_count_active_chats already filters status='active' so deleted rooms
-- automatically stop counting. No change needed there. This migration is
-- additive only.
