import Foundation
import Supabase

enum ChatServiceError: LocalizedError, Equatable {
    case authRequired
    case roomNotFound
    case roomNotActive
    case notRoomParticipant
    case userBanned
    case blockedRelationship
    case emptyMessage
    case messageTooLong
    case insertFailed
    case loadFailed
    case other

    init(code: String?) {
        switch code {
        case "AUTH_REQUIRED":         self = .authRequired
        case "ROOM_NOT_FOUND":        self = .roomNotFound
        case "ROOM_NOT_ACTIVE":       self = .roomNotActive
        case "NOT_ROOM_PARTICIPANT":  self = .notRoomParticipant
        case "USER_BANNED":           self = .userBanned
        case "BLOCKED_RELATIONSHIP":  self = .blockedRelationship
        case "EMPTY_MESSAGE":         self = .emptyMessage
        case "MESSAGE_TOO_LONG":      self = .messageTooLong
        case "INSERT_FAILED":         self = .insertFailed
        default:                      self = .other
        }
    }

    var errorDescription: String? {
        switch self {
        case .roomNotFound, .roomNotActive, .notRoomParticipant,
             .userBanned, .blockedRelationship,
             .insertFailed, .other:
            return String(localized: "chat.error.sendFailed")
        case .emptyMessage:
            return String(localized: "chat.error.sendFailed")
        case .messageTooLong:
            return String(localized: "chat.error.sendFailed")
        case .loadFailed:
            return String(localized: "chat.error.loadFailed")
        case .authRequired:
            return String(localized: "error.notSignedIn")
        }
    }
}

@MainActor
final class ChatService {
    static let shared = ChatService()
    private init() {}

    // MARK: - Reads

    /// Fetch all chat rooms the current user is a participant in.
    /// RLS already restricts this to the user's own rooms.
    func fetchRooms() async throws -> [ChatRoom] {
        do {
            return try await Supa.client
                .from("chat_rooms")
                .select()
                .eq("status", value: "active")
                .order("last_message_at", ascending: false)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            GALog.chat.error("fetchRooms: \(error.localizedDescription)")
            throw ChatServiceError.loadFailed
        }
    }

    func fetchRoom(id: UUID) async throws -> ChatRoom? {
        let result: [ChatRoom] = try await Supa.client
            .from("chat_rooms")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        return result.first
    }

    /// Latest `limit` messages, returned ascending so the UI can append in order.
    func fetchMessages(roomId: UUID, limit: Int = 50) async throws -> [Message] {
        do {
            let descending: [Message] = try await Supa.client
                .from("messages")
                .select()
                .eq("room_id", value: roomId)
                .eq("is_deleted", value: false)
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return descending.reversed()
        } catch {
            GALog.chat.error("fetchMessages: \(error.localizedDescription)")
            throw ChatServiceError.loadFailed
        }
    }

    /// Lookup the partner profile for a room. Returns nil if absent.
    func fetchPartnerProfile(for room: ChatRoom, currentUserId: UUID) async throws -> Profile? {
        let partnerId = room.partnerId(currentUser: currentUserId)
        return try await ProfileService.shared.fetchProfile(id: partnerId)
    }

    // MARK: - Writes (Edge Function)

    private struct SendBody: Encodable { let room_id: UUID; let body: String }
    private struct SendMediaBody: Encodable {
        let room_id: UUID
        let media_id: UUID
        let body: String?
    }

    /// Sends a media message via createChatMessage Edge Function. The media
    /// must already exist in `media_assets` (status = pending_upload) and
    /// have its bytes uploaded to private storage.
    func sendMediaMessage(roomId: UUID, mediaId: UUID, caption: String?) async throws -> Message {
        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let captionToSend = (trimmedCaption?.isEmpty ?? true) ? nil : trimmedCaption
        return try await invokeCreate(body: SendMediaBody(
            room_id: roomId, media_id: mediaId, body: captionToSend
        ))
    }

    /// Sends a text message via createChatMessage Edge Function.
    func sendTextMessage(roomId: UUID, body: String) async throws -> Message {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatServiceError.emptyMessage }
        guard trimmed.count <= 1000 else { throw ChatServiceError.messageTooLong }

        return try await invokeCreate(body: SendBody(room_id: roomId, body: trimmed))
    }

    private func invokeCreate<B: Encodable>(body: B) async throws -> Message {
        do {
            let raw: Data = try await Supa.client.functions.invoke(
                "createChatMessage",
                options: .init(body: body)
            )
            if let envelope = try? JSONDecoder.gaChat.decode(EnvelopeOK.self, from: raw) {
                return envelope.data.message
            }
            if let err = try? JSONDecoder.gaChat.decode(EnvelopeErr.self, from: raw) {
                throw ChatServiceError(code: err.error_code)
            }
            throw ChatServiceError.other
        } catch let e as ChatServiceError {
            throw e
        } catch {
            if let data = Self.errorPayload(from: error),
               let err = try? JSONDecoder.gaChat.decode(EnvelopeErr.self, from: data) {
                throw ChatServiceError(code: err.error_code)
            }
            GALog.chat.error("createChatMessage: \(error.localizedDescription)")
            throw ChatServiceError.other
        }
    }

    // MARK: - Envelope helpers

    private struct EnvelopeOK: Decodable {
        struct DataPart: Decodable { let message: Message }
        let ok: Bool
        let data: DataPart
    }
    private struct EnvelopeErr: Decodable {
        let ok: Bool
        let error_code: String?
        let message: String?
    }

    private static func errorPayload(from error: Error) -> Data? {
        let mirror = Mirror(reflecting: error)
        for child in mirror.children {
            if let nested = Mirror(reflecting: child.value).children.first(where: { _ in true })?.value,
               let data = nested as? Data { return data }
            if let data = child.value as? Data { return data }
        }
        return nil
    }
}

private extension JSONDecoder {
    static let gaChat: JSONDecoder = {
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
