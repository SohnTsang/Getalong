import Foundation
import SwiftUI

@MainActor
final class ChatRoomViewModel: ObservableObject {

    let roomId: UUID
    private(set) var partner: Profile?
    private(set) var currentUserId: UUID?

    @Published var messages: [Message] = []
    @Published var isLoadingInitial: Bool = true
    @Published var loadError: String?
    @Published var sendError: String?
    @Published var isSending: Bool = false
    @Published var draft: String = ""

    init(roomId: UUID, partner: Profile?) {
        self.roomId = roomId
        self.partner = partner
    }

    func attach(currentUserId: UUID) async {
        self.currentUserId = currentUserId

        // Hydrate partner if we don't have one yet.
        if partner == nil {
            if let room = try? await ChatService.shared.fetchRoom(id: roomId) {
                partner = try? await ChatService.shared.fetchPartnerProfile(
                    for: room, currentUserId: currentUserId)
            }
        }

        await reload()

        await RealtimeChatManager.shared.start(roomId: roomId) { [weak self] in
            Task { await self?.reloadOnRealtimeInsert() }
        }
    }

    func detach() async {
        await RealtimeChatManager.shared.stop()
    }

    // MARK: - Loads

    func reload() async {
        do {
            messages = try await ChatService.shared.fetchMessages(roomId: roomId, limit: 50)
            loadError = nil
        } catch {
            loadError = String(localized: "chat.error.loadFailed")
        }
        isLoadingInitial = false
    }

    /// Realtime hint: a new message landed. Refetch the latest 50 — cheap
    /// for MVP, deduplicates implicitly because we replace the array.
    private func reloadOnRealtimeInsert() async {
        do {
            let latest = try await ChatService.shared.fetchMessages(roomId: roomId, limit: 50)
            messages = latest
        } catch {
            GALog.chat.error("realtime reload: \(error.localizedDescription)")
        }
    }

    // MARK: - Send

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isSending else { return }
        sendError = nil
        isSending = true
        defer { isSending = false }

        do {
            let inserted = try await ChatService.shared.sendTextMessage(roomId: roomId, body: text)
            // Optimistic-style: append directly so we don't wait for realtime.
            if !messages.contains(where: { $0.id == inserted.id }) {
                messages.append(inserted)
            }
            draft = ""
            Haptics.tap()
        } catch let e as ChatServiceError {
            sendError = e.errorDescription
            Haptics.error()
        } catch {
            sendError = String(localized: "chat.error.sendFailed")
            Haptics.error()
        }
    }

    // MARK: - Display helpers

    func isMine(_ message: Message) -> Bool {
        message.senderId == currentUserId
    }

    var headerTitle: String {
        partner?.displayName.isEmpty == false
            ? partner!.displayName
            : String(localized: "chat.title.fallback")
    }

    var headerSubtitle: String? {
        partner.map { "@\($0.getalongId)" }
    }
}
