import Foundation
import SwiftUI
import UIKit

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
    private var foregroundObserver: NSObjectProtocol?

    func attach(userId: UUID) async {
        guard currentUserId != userId else {
            await refresh()
            return
        }
        currentUserId = userId

        await refresh()
        observeAppLifecycle()

        // Realtime registration runs unstructured so a hung
        // subscribe can't stall the rest of the app's startup.
        // RealtimeChatRoomsManager retries failed subscribes with
        // backoff, so a launch-time CancellationError no longer
        // leaves the socket dead.
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

    private func observeAppLifecycle() {
        guard foregroundObserver == nil else { return }
        // Catch up the moment the app returns from background — the
        // websocket may have been suspended and a message could have
        // landed while we weren't listening.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func detach() {
        if let token = foregroundObserver {
            NotificationCenter.default.removeObserver(token)
            foregroundObserver = nil
        }
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
            let next = built.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
            // Avoid republishing identical content. Same-shape refreshes
            // (e.g. the user comes back to the tab and nothing changed)
            // would otherwise trigger a SwiftUI re-render of every row
            // for no reason.
            if next != rows { rows = next }
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
