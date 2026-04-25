import Foundation

@MainActor
final class MediaService {
    static let shared = MediaService()
    private init() {}

    /// Edge Function: `requestMediaUpload`.
    func requestUpload(roomId: UUID,
                       mimeType: String,
                       sizeBytes: Int64,
                       viewOnce: Bool) async throws -> (path: String, token: String?) {
        // TODO
        throw NSError(domain: "MediaService", code: -1)
    }

    /// Edge Function: `openViewOnceMedia`.
    /// Returns a short-lived signed URL after marking the media as viewed.
    func openViewOnce(mediaId: UUID, roomId: UUID) async throws -> URL {
        // TODO
        throw NSError(domain: "MediaService", code: -1)
    }
}
