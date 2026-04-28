import Foundation
import UniformTypeIdentifiers

/// A locally-prepared piece of media ready to upload.
struct MediaPreparedFile: Equatable {
    enum Kind: String { case image, gif, video }

    /// On-disk URL of the prepared bytes. Owned by the caller; cleaned up
    /// after upload completes.
    let localURL: URL
    let mimeType: String
    let kind: Kind
    let sizeBytes: Int64
    let durationSeconds: Int?
    let width: Int?
    let height: Int?
    /// Base64 of a ~24px JPEG of the same image. Sent up at request-
    /// upload time and stored on media_assets.preview_data so both
    /// participants can render a matching blurred-noise placeholder
    /// before the receiver opens the media.
    let previewBase64: String?

    var fileExtension: String {
        switch mimeType {
        case "image/jpeg":      return "jpg"
        case "image/png":       return "png"
        case "image/gif":       return "gif"
        case "video/mp4":       return "mp4"
        case "video/quicktime": return "mov"
        default:                return localURL.pathExtension
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: localURL)
    }
}

/// Server-aligned media policy (kept in sync with supabase/functions/_shared/media.ts).
enum MediaPolicy {
    static let imageMaxBytes: Int64 = 8  * 1024 * 1024
    static let gifMaxBytes:   Int64 = 10 * 1024 * 1024
    static let videoMaxBytes: Int64 = 30 * 1024 * 1024
    static let videoMaxDuration: TimeInterval = 15

    static func isAllowed(mime: String) -> Bool {
        switch mime {
        case "image/jpeg", "image/png", "image/gif",
             "video/mp4", "video/quicktime":
            return true
        default:
            return false
        }
    }

    static func maxBytes(for kind: MediaPreparedFile.Kind) -> Int64 {
        switch kind {
        case .image: return imageMaxBytes
        case .gif:   return gifMaxBytes
        case .video: return videoMaxBytes
        }
    }
}

enum MediaPreparationError: LocalizedError, Equatable {
    case unsupportedType
    case fileTooLarge
    case stillTooLargeAfterCompression
    case videoTooLong
    case compressionFailed
    case readFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return String(localized: "media.error.unsupportedType")
        case .fileTooLarge:
            return String(localized: "media.error.tooLarge")
        case .stillTooLargeAfterCompression:
            return String(localized: "media.error.fileTooLargeAfterCompression")
        case .videoTooLong:
            return String(localized: "media.error.videoTooLong")
        case .compressionFailed:
            return String(localized: "media.error.compressionFailed")
        case .readFailed:
            return String(localized: "media.error.compressionFailed")
        }
    }
}

/// Helper: temporary URL that won't collide with system files.
enum MediaTempFile {
    static func make(extension ext: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("getalong-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = UUID().uuidString + "." + ext
        return dir.appendingPathComponent(name)
    }
}
