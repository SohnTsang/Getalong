import Foundation

/// Tiny shared state describing which chat room (if any) the user is
/// currently looking at. PushNotificationManager reads this in the
/// foreground-presentation hook to suppress banners for the open
/// conversation, matching the iMessage / WhatsApp behaviour.
@MainActor
final class ChatPresence {
    static let shared = ChatPresence()
    private init() {}

    private(set) var currentRoomId: UUID?

    func enter(_ roomId: UUID) { currentRoomId = roomId }
    func leave(_ roomId: UUID) {
        if currentRoomId == roomId { currentRoomId = nil }
    }
}
