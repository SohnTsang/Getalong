import Foundation
import SwiftUI

/// One row in the Chats list — a room joined with its partner profile
/// and an optional last-message preview.
struct ChatRow: Identifiable, Hashable {
    let id: UUID                 // room id
    let room: ChatRoom
    var partner: Profile?
    var lastMessage: Message?

    var partnerDisplayName: String? {
        partner?.displayName.isEmpty == false ? partner?.displayName : nil
    }
    var partnerHandle: String? {
        partner.map { "@\($0.getalongId)" }
    }
}

@MainActor
final class ChatsViewModel: ObservableObject {
    @Published var rows: [ChatRow] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private(set) var currentUserId: UUID?

    func attach(userId: UUID) async {
        currentUserId = userId
        await refresh()
    }

    func refresh() async {
        guard let me = currentUserId else { return }
        if rows.isEmpty { isLoading = true }
        defer { isLoading = false }

        do {
            let rooms = try await ChatService.shared.fetchRooms()
            // Build one ChatRow per room; fetch partner profile + last message in parallel.
            let built: [ChatRow] = await withTaskGroup(of: ChatRow.self) { group in
                for room in rooms {
                    group.addTask {
                        async let partner = (try? await ChatService.shared.fetchPartnerProfile(for: room, currentUserId: me))
                        async let last    = (try? await ChatService.shared.fetchMessages(roomId: room.id, limit: 1))
                        return ChatRow(
                            id: room.id,
                            room: room,
                            partner: await partner ?? nil,
                            lastMessage: (await last)?.last
                        )
                    }
                }
                var collected: [ChatRow] = []
                for await row in group { collected.append(row) }
                return collected
            }
            // Preserve room order.
            let order = Dictionary(uniqueKeysWithValues: rooms.enumerated().map { ($1.id, $0) })
            rows = built.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
        } catch {
            errorMessage = String(localized: "chat.error.loadFailed")
        }
    }
}
