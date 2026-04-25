import Foundation

/// Coordinates client-side media compression and private uploads.
///
/// Real flow:
///   1. Client calls `requestMediaUpload` Edge Function.
///   2. Edge Function returns a private storage path.
///   3. Client uploads bytes via Supabase Storage SDK to that path.
///   4. Client calls `createChatMessage` to attach the media to a message.
///
/// View-once enforcement (open + auto-delete) lives in
/// `openViewOnceMedia` / `deleteExpiredMedia` Edge Functions.
final class MediaUploadManager {
    static let shared = MediaUploadManager()
    private init() {}

    func upload(localURL: URL,
                roomId: UUID,
                viewOnce: Bool) async throws -> MediaAsset {
        // TODO: implement.
        throw NSError(domain: "MediaUploadManager", code: -1)
    }
}
