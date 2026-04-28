import Foundation
import Combine

/// Per-room "last seen" timestamp for the signed-in user. Drives the
/// red unread-dot in the Chats list — no DB schema change required.
///
/// Persisted via UserDefaults so unread state survives app launches.
/// Stored as `[roomId.uuidString : ISO-8601 date string]`.
@MainActor
final class ChatReadState: ObservableObject {
    static let shared = ChatReadState()

    /// Bumping this @Published lets observers (ChatsView rows)
    /// recompute hasUnread without reading every room key.
    @Published private(set) var revision: Int = 0

    private static let storageKey = "ga.chat.lastReadAt.v1"
    private var lastReadAt: [UUID: Date] = [:]
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() { load() }

    func lastRead(for roomId: UUID) -> Date? { lastReadAt[roomId] }

    /// Mark the room read up to `at` (default = now).
    func markRead(_ roomId: UUID, at: Date = Date()) {
        // Keep the latest stamp — never go backwards.
        if let existing = lastReadAt[roomId], existing >= at { return }
        lastReadAt[roomId] = at
        save()
        revision &+= 1
    }

    /// hasUnread = there's a most-recent message from the partner that
    /// arrived after the user last entered the room. Sender's own
    /// messages don't count.
    func hasUnread(_ row: ChatRow, currentUserId: UUID?) -> Bool {
        guard let last = row.lastMessage,
              let me = currentUserId,
              last.senderId != me
        else { return false }
        let seen = lastReadAt[row.id] ?? .distantPast
        return last.createdAt > seen
    }

    // MARK: - Persistence

    private func load() {
        guard let dict = UserDefaults.standard.dictionary(
            forKey: Self.storageKey
        ) as? [String: String] else { return }
        var out: [UUID: Date] = [:]
        for (k, v) in dict {
            if let id = UUID(uuidString: k),
               let date = Self.isoFormatter.date(from: v) {
                out[id] = date
            }
        }
        lastReadAt = out
    }

    private func save() {
        var encoded: [String: String] = [:]
        for (id, date) in lastReadAt {
            encoded[id.uuidString] = Self.isoFormatter.string(from: date)
        }
        UserDefaults.standard.set(encoded, forKey: Self.storageKey)
    }
}
