import Foundation
import Supabase

enum MediaServiceError: LocalizedError, Equatable {
    case authRequired
    case roomNotFound
    case roomNotActive
    case notRoomParticipant
    case userBanned
    case blockedRelationship
    case typeNotAllowed
    case tooLarge
    case durationTooLong
    case mediaNotFound
    case mediaAlreadyViewed
    case mediaNotActive
    case mediaExpired
    case mediaNotUploaded
    case storageError
    case networkError
    case other

    init(code: String?) {
        switch code {
        case "AUTH_REQUIRED":              self = .authRequired
        case "ROOM_NOT_FOUND":             self = .roomNotFound
        case "ROOM_NOT_ACTIVE":            self = .roomNotActive
        case "NOT_ROOM_PARTICIPANT":       self = .notRoomParticipant
        case "USER_BANNED":                self = .userBanned
        case "BLOCKED_RELATIONSHIP":       self = .blockedRelationship
        case "MEDIA_TYPE_NOT_ALLOWED",
             "MEDIA_TYPE_MISMATCH":        self = .typeNotAllowed
        case "MEDIA_TOO_LARGE":            self = .tooLarge
        case "MEDIA_DURATION_TOO_LONG":    self = .durationTooLong
        case "MEDIA_NOT_FOUND":            self = .mediaNotFound
        case "MEDIA_ALREADY_VIEWED":       self = .mediaAlreadyViewed
        case "MEDIA_NOT_ACTIVE":           self = .mediaNotActive
        case "MEDIA_EXPIRED":              self = .mediaExpired
        case "MEDIA_NOT_UPLOADED":         self = .mediaNotUploaded
        case "STORAGE_ERROR":              self = .storageError
        default:                           self = .other
        }
    }

    var errorDescription: String? {
        switch self {
        case .authRequired:           return String(localized: "error.notSignedIn")
        case .tooLarge:               return String(localized: "media.error.tooLarge")
        case .durationTooLong:        return String(localized: "media.error.videoTooLong")
        case .mediaAlreadyViewed,
             .mediaNotActive,
             .mediaExpired,
             .mediaNotFound:          return String(localized: "media.unavailable")
        case .typeNotAllowed:         return String(localized: "media.error.unsupportedType")
        case .networkError:           return String(localized: "error.network")
        case .storageError,
             .mediaNotUploaded,
             .other,
             .roomNotFound,
             .roomNotActive,
             .notRoomParticipant,
             .userBanned,
             .blockedRelationship:    return String(localized: "media.error.uploadFailed")
        }
    }
}

@MainActor
final class MediaService {
    static let shared = MediaService()
    private init() {}

    // MARK: - Upload ticket

    struct UploadTicket: Decodable {
        let mediaId: UUID
        let storagePath: String
        let mimeType: String
        let bucket: String
        let uploadUrl: String
        let uploadToken: String
        let maxBytes: Int64
        let expiresAt: Date

        enum CodingKeys: String, CodingKey {
            case mediaId      = "media_id"
            case storagePath  = "storage_path"
            case mimeType     = "mime_type"
            case bucket
            case uploadUrl    = "upload_url"
            case uploadToken  = "upload_token"
            case maxBytes     = "max_bytes"
            case expiresAt    = "expires_at"
        }
    }

    private struct RequestBody: Encodable {
        let room_id: UUID
        let mime_type: String
        let size_bytes: Int64
        let duration_seconds: Int?
    }

    private struct EnvelopeOK<T: Decodable>: Decodable { let ok: Bool; let data: T }
    private struct EnvelopeErr: Decodable {
        let ok: Bool
        let error_code: String?
        let message: String?
    }

    func requestUpload(roomId: UUID, file: MediaPreparedFile) async throws -> UploadTicket {
        let body = RequestBody(
            room_id: roomId,
            mime_type: file.mimeType,
            size_bytes: file.sizeBytes,
            duration_seconds: file.durationSeconds
        )
        return try await invoke("requestMediaUpload", body: body)
    }

    // MARK: - Upload to storage

    /// Uploads `file` bytes to Supabase Storage using the signed URL from
    /// the ticket. Returns when the storage object exists. Cancels cleanly
    /// when the surrounding Task is cancelled.
    func upload(file: MediaPreparedFile, using ticket: UploadTicket) async throws {
        guard let url = URL(string: ticket.uploadUrl) else {
            throw MediaServiceError.storageError
        }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue(ticket.mimeType, forHTTPHeaderField: "Content-Type")
        req.setValue("3600", forHTTPHeaderField: "Cache-Control")
        req.setValue("true",  forHTTPHeaderField: "x-upsert")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared
                .upload(for: req, fromFile: file.localURL)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            GALog.media.error("upload network error: \(error.localizedDescription)")
            throw MediaServiceError.networkError
        }

        guard let http = response as? HTTPURLResponse else {
            throw MediaServiceError.storageError
        }
        if !(200..<300).contains(http.statusCode) {
            GALog.media.error(
                "upload failed: \(http.statusCode) \(String(data: data, encoding: .utf8) ?? "")"
            )
            throw MediaServiceError.storageError
        }
    }

    // MARK: - Open view-once

    struct OpenResponse: Decodable {
        let signedUrl: URL
        let mimeType: String
        let expiresIn: Int
        let viewedAt: Date

        enum CodingKeys: String, CodingKey {
            case signedUrl  = "signed_url"
            case mimeType   = "mime_type"
            case expiresIn  = "expires_in"
            case viewedAt   = "viewed_at"
        }
    }

    func openViewOnce(mediaId: UUID) async throws -> OpenResponse {
        struct Body: Encodable { let media_id: UUID }
        return try await invoke("openViewOnceMedia", body: Body(media_id: mediaId))
    }

    /// Best-effort: tells the backend the receiver has closed the viewer so
    /// the storage object can be removed immediately. Idempotent server-side.
    /// Failure is logged but never surfaced to the user; the fallback
    /// cleanup will catch unmarked rows after a 2-minute grace.
    func finalizeViewOnce(mediaId: UUID) async {
        struct Body: Encodable { let media_id: UUID }
        struct Resp: Decodable {
            let storageDeletedAt: Date?
            let alreadyDeleted: Bool?
            enum CodingKeys: String, CodingKey {
                case storageDeletedAt = "storage_deleted_at"
                case alreadyDeleted   = "already_deleted"
            }
        }
        do {
            let _: Resp = try await invoke("finalizeViewOnceMedia",
                                           body: Body(media_id: mediaId))
        } catch {
            GALog.media.error("finalizeViewOnce: \(error.localizedDescription)")
        }
    }

    // MARK: - Read media metadata (for messages)

    func fetchAsset(id: UUID) async throws -> MediaAsset? {
        let result: [MediaAsset] = try await Supa.client
            .from("media_assets")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return result.first
    }

    // MARK: - Invocation

    private func invoke<TBody: Encodable, TResp: Decodable>(
        _ name: String, body: TBody
    ) async throws -> TResp {
        do {
            let raw = try await Supa.invokeRaw(name, body: body)
            if let env = try? Self.decoder.decode(EnvelopeOK<TResp>.self, from: raw) {
                return env.data
            }
            if let err = try? Self.decoder.decode(EnvelopeErr.self, from: raw) {
                throw MediaServiceError(code: err.error_code)
            }
            throw MediaServiceError.other
        } catch let e as MediaServiceError {
            throw e
        } catch {
            if let data = Supa.errorBody(from: error) {
                if let err = try? Self.decoder.decode(EnvelopeErr.self, from: data) {
                    GALog.media.error("\(name) error code=\(err.error_code ?? "-") message=\(err.message ?? "-")")
                    throw MediaServiceError(code: err.error_code)
                }
                let preview = String(data: data, encoding: .utf8)?.prefix(400) ?? "-"
                GALog.media.error("\(name) body: \(preview)")
            }
            GALog.media.error("\(name) transport: \(error.localizedDescription)")
            throw MediaServiceError.networkError
        }
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = f.date(from: s) { return d }
            f.formatOptions = [.withInternetDateTime]
            if let d = f.date(from: s) { return d }
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid ISO-8601 date: \(s)"
            ))
        }
        return d
    }()

}

