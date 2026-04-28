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
    private var realtimeToken: UUID?
    /// Belt-and-braces poll. The chat_rooms realtime channel is the
    /// primary refresh signal, but realtime can be hung mid-handshake
    /// (we've seen `subscribe` never complete without an error in the
    /// wild) and the user shouldn't have to leave the tab to see the
    /// latest message. 4s matches what we use inside ChatRoomView.
    private var fallbackPollTask: Task<Void, Never>?

    func attach(userId: UUID) async {
        guard currentUserId != userId else {
            await refresh()
            return
        }
        currentUserId = userId

        // Start the fallback poll *before* anything that can block.
        // The realtime addListener call below has been observed
        // hanging mid-subscribe on cold start; if we waited on it,
        // the poll never started and the Chats list would only
        // refresh on tab change. The poll is cheap and runs
        // independently — when realtime works it just races the poll.
        startFallbackPolling()
        await refresh()

        // Realtime registration runs unstructured so a hung
        // subscribe can't stall the rest of the app's startup.
        Task { [weak self, userId] in
            guard let self else { return }
            let token = await RealtimeChatRoomsManager.shared.addListener(
                userId: userId
            ) { [weak self] in
                Task { await self?.refresh() }
            }
            await MainActor.run { self.realtimeToken = token }
        }
    }

    private func startFallbackPolling() {
        fallbackPollTask?.cancel()
        fallbackPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    func detach() {
        fallbackPollTask?.cancel()
        fallbackPollTask = nil
        if let t = realtimeToken {
            RealtimeChatRoomsManager.shared.removeListener(t)
            realtimeToken = nil
        }
    }

    func refresh() async {
        guard let me = currentUserId else { return }
        if rows.isEmpty { isLoading = true }
        defer { isLoading = false }

        do {
            let raw = try await ChatService.shared.fetchRooms()
            // Defensive dedupe by partner: even though migration 0019
            // adds a unique index that prevents two active rooms with
            // the same partner, any pre-existing duplicates from
            // before the migration would still surface here. Keep the
            // most-recently-active row per partner.
            let rooms = Self.collapseByPartner(raw, currentUserId: me)
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

    /// Collapse multiple active rooms with the same partner down to one,
    /// keeping the most recently active row. Migration 0019 guarantees
    /// the database only allows one going forward; this is for any
    /// rooms created before the index existed.
    private static func collapseByPartner(_ rooms: [ChatRoom], currentUserId me: UUID) -> [ChatRoom] {
        var byPartner: [UUID: ChatRoom] = [:]
        for room in rooms {
            let partner = room.partnerId(currentUser: me)
            if let existing = byPartner[partner] {
                let existingTs = existing.lastMessageAt ?? existing.createdAt
                let candidateTs = room.lastMessageAt ?? room.createdAt
                if candidateTs > existingTs { byPartner[partner] = room }
            } else {
                byPartner[partner] = room
            }
        }
        // Stable order: most recent activity first.
        return byPartner.values.sorted {
            ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt)
        }
    }
}
