import Foundation

@MainActor
final class ChatService {
    static let shared = ChatService()
    private init() {}

    func fetchRooms() async throws -> [ChatRoom] {
        // TODO
        return []
    }

    func fetchMessages(roomId: UUID,
                       before: Date? = nil,
                       limit: Int = 50) async throws -> [Message] {
        // TODO
        return []
    }

    /// Edge Function: `createChatMessage`.
    func sendText(roomId: UUID, body: String) async throws -> Message {
        // TODO
        throw NSError(domain: "ChatService", code: -1)
    }
}
