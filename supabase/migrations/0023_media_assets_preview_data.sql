-- 0023_media_assets_preview_data.sql
--
-- Adds a tiny base64-encoded JPEG preview to media_assets so both
-- sender and receiver can render the same blurred-noise placeholder
-- for view-once media — same image content on both sides, neither
-- side gets the original bytes pre-tap.
--
-- The client computes a 24×24-ish low-quality JPEG from the prepared
-- image (~1-2KB) before requesting upload, and passes it through
-- requestMediaUpload. Both sides decode it, draw it heavily blurred
-- with our existing dot-grain overlay. The original full-resolution
-- image still only leaves storage when the receiver taps to open
-- (view-once enforcement is unchanged).

alter table public.media_assets
  add column if not exists preview_data text;

comment on column public.media_assets.preview_data is
  'Base64-encoded tiny JPEG (~24px long edge) used as a blurred '
  'placeholder on both sides of the chat. Visible to room participants '
  'via existing media_assets RLS — no extra policy needed.';
