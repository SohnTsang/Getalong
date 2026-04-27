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
    case deleteFailed
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
        case "DELETE_FAILED":         self = .deleteFailed
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
        case .deleteFailed:
            return String(localized: "chat.delete.error")
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
            let raw = try await Supa.invokeRaw("createChatMessage", body: body)
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
            if let data = Supa.errorBody(from: error) {
                if let err = try? JSONDecoder.gaChat.decode(EnvelopeErr.self, from: data) {
                    GALog.chat.error("createChatMessage error code=\(err.error_code ?? "-") message=\(err.message ?? "-")")
                    throw ChatServiceError(code: err.error_code)
                }
                let preview = String(data: data, encoding: .utf8)?.prefix(400) ?? "-"
                GALog.chat.error("createChatMessage body: \(preview)")
            }
            GALog.chat.error("createChatMessage transport: \(error.localizedDescription)")
            throw ChatServiceError.other
        }
    }

    // MARK: - Delete conversation

    /// Soft-deletes the chat room for both participants. The row stays in
    /// the database (so messages, media, and reports remain auditable),
    /// but its status flips to 'deleted' which removes it from
    /// `fetchRooms()` and from the active-chat-limit count.
    /// Idempotent — calling twice returns success the second time.
    @discardableResult
    func deleteConversation(roomId: UUID) async throws -> UUID {
        struct Body: Encodable { let room_id: UUID }
        struct DeleteEnvelope: Decodable {
            struct DataPart: Decodable { let room_id: UUID }
            let ok: Bool; let data: DataPart
        }
        GALog.chat.info("deleteConversation start id=\(roomId.uuidString, privacy: .public)")
        do {
            let raw = try await Supa.invokeRaw(
                "deleteConversation", body: Body(room_id: roomId)
            )
            if let env = try? JSONDecoder().decode(DeleteEnvelope.self, from: raw) {
                GALog.chat.info("deleteConversation ok id=\(roomId.uuidString, privacy: .public)")
                return env.data.room_id
            }
            if let err = try? JSONDecoder().decode(EnvelopeErr.self, from: raw) {
                GALog.chat.error("deleteConversation server code=\(err.error_code ?? "-", privacy: .public)")
                throw ChatServiceError(code: err.error_code)
            }
            throw ChatServiceError.deleteFailed
        } catch let e as ChatServiceError {
            throw e
        } catch {
            if let data = Supa.errorBody(from: error),
               let err = try? JSONDecoder().decode(EnvelopeErr.self, from: data) {
                GALog.chat.error("deleteConversation http code=\(err.error_code ?? "-", privacy: .public)")
                throw ChatServiceError(code: err.error_code)
            }
            GALog.chat.error("deleteConversation transport: \(error.localizedDescription, privacy: .public)")
            throw ChatServiceError.deleteFailed
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
