// Shared media policy for Getalong one-time-view chat media.

export const MEDIA_BUCKET = "chat-media-private";

/// Allowed MIME types for view-once media in MVP.
export const ALLOWED_MIME: Record<string, "image" | "gif" | "video"> = {
  "image/jpeg":      "image",
  "image/png":       "image",
  "image/gif":       "gif",
  "video/mp4":       "video",
  "video/quicktime": "video",
};

export const MAX_BYTES_BY_KIND = {
  image:  8  * 1024 * 1024,
  gif:    10 * 1024 * 1024,
  video:  30 * 1024 * 1024,
} as const;

export const MAX_VIDEO_DURATION_SECONDS = 15;

/// 7 days from creation.
export const PENDING_TTL_SECONDS    = 30 * 60;       // 30 min cleanup
export const ACTIVE_TTL_SECONDS     = 7 * 24 * 3600; // 7 days
export const VIEWED_GRACE_SECONDS   = 2 * 60;        // 2 min after viewed_at

export function kindFromMime(mime: string): "image" | "gif" | "video" | null {
  return ALLOWED_MIME[mime] ?? null;
}

export function messageTypeFromMime(mime: string): "image" | "gif" | "video" | null {
  return ALLOWED_MIME[mime] ?? null;
}

/// Picks a storage path that is unguessable. Format:
///   rooms/<room_id>/<media_id>.<ext>
export function storagePathFor(
  roomId: string,
  mediaId: string,
  mime: string,
): string {
  const ext = extFor(mime);
  return `rooms/${roomId}/${mediaId}.${ext}`;
}

function extFor(mime: string): string {
  switch (mime) {
    case "image/jpeg":      return "jpg";
    case "image/png":       return "png";
    case "image/gif":       return "gif";
    case "video/mp4":       return "mp4";
    case "video/quicktime": return "mov";
    default:                return "bin";
  }
}
