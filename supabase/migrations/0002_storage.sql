-- Private Storage buckets for chat media.
-- One-time-view media must NEVER be publicly readable. All access is via
-- short-lived signed URLs issued by the openViewOnceMedia Edge Function.

insert into storage.buckets (id, name, public)
values ('chat-media', 'chat-media', false)
on conflict (id) do nothing;

-- No public select / insert / update / delete policies are added here.
-- Edge Functions use the service role key to upload and to mint signed URLs.
