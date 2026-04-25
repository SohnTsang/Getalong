import Foundation
import SwiftUI

@MainActor
final class InvitesViewModel: ObservableObject {

    enum Tab: String, CaseIterable, Identifiable {
        case live = "Live"
        case missed = "Missed"
        var id: String { rawValue }
    }

    // Inbound
    @Published var incomingLive: Invite?
    @Published var missed: [Invite] = []

    // Outbound
    @Published var outgoingLive: Invite?

    // UI
    @Published var tab: Tab = .live
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastChatRoomId: UUID?
    @Published var lastChatPartner: String?

    // Dev compose form (handle only — invites are a single tap)
    @Published var composeHandle: String = ""
    @Published var composeIsSending: Bool = false
    @Published var composeError: String?

    private(set) var currentUserId: UUID?

    // MARK: - Lifecycle

    func attach(userId: UUID) async {
        currentUserId = userId
        await refresh()
        await RealtimeInviteManager.shared.start(userId: userId) { [weak self] in
            Task { await self?.refresh() }
        }
    }

    func detach() async {
        await RealtimeInviteManager.shared.stop()
    }

    // MARK: - Reads

    func refresh() async {
        guard let uid = currentUserId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let inbox      = InviteService.shared.fetchIncomingLivePending(userId: uid)
            async let missedList = InviteService.shared.fetchMissedInvites(userId: uid)
            async let outbox     = InviteService.shared.fetchOutgoingLivePending(userId: uid)
            let (i, m, o) = try await (inbox, missedList, outbox)
            // The most recent live_pending receiver-side wins. The UI only
            // shows one banner at a time.
            incomingLive = i.first
            missed       = m
            outgoingLive = o.first
        } catch {
            GALog.invite.error("refresh: \(error.localizedDescription)")
        }
    }

    // MARK: - Receiver actions

    func acceptLive(_ invite: Invite) async {
        errorMessage = nil
        do {
            let resp = try await InviteService.shared.acceptLiveInvite(inviteId: invite.id)
            lastChatRoomId  = resp.chatRoomId
            lastChatPartner = "@…"  // partner handle could be loaded separately
            incomingLive = nil
            await refresh()
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    func declineLive(_ invite: Invite) async {
        await decline(invite)
    }

    func decline(_ invite: Invite) async {
        do {
            try await InviteService.shared.declineInvite(inviteId: invite.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptMissed(_ invite: Invite) async {
        errorMessage = nil
        do {
            let resp = try await InviteService.shared.acceptMissedInvite(inviteId: invite.id)
            lastChatRoomId  = resp.chatRoomId
            lastChatPartner = "@…"
            await refresh()
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    /// Fired by the receiver UI when its countdown reaches zero.
    func liveCountdownExpired(_ invite: Invite) async {
        do {
            try await InviteService.shared.markLiveInviteMissed(inviteId: invite.id)
        } catch {
            GALog.invite.error("markLiveInviteMissed: \(error.localizedDescription)")
        }
        await refresh()
    }

    // MARK: - Sender actions

    func cancelOutgoing(_ invite: Invite) async {
        do {
            try await InviteService.shared.cancelLiveInvite(inviteId: invite.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendDevCompose() async {
        composeError = nil
        let handle = composeHandle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard handle.count >= 3 else {
            composeError = "Enter a handle to invite."
            return
        }
        composeIsSending = true
        defer { composeIsSending = false }
        do {
            _ = try await InviteService.shared.sendLiveInvite(receiverHandle: handle)
            composeHandle = ""
            await refresh()
            Haptics.success()
        } catch {
            composeError = error.localizedDescription
            Haptics.error()
        }
    }

    // MARK: - Helpers

    func clearLastChat() {
        lastChatRoomId = nil
        lastChatPartner = nil
    }
}
