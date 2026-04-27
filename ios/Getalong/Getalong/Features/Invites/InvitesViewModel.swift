import Foundation
import SwiftUI

@MainActor
final class InvitesViewModel: ObservableObject {

    enum Tab: CaseIterable, Identifiable, Hashable {
        case live, missed
        var id: Self { self }

        var localizedTitle: String {
            switch self {
            case .live:   return String(localized: "signals.tab.live")
            case .missed: return String(localized: "signals.tab.missed")
            }
        }
    }

    // Live invites coming in (multiple cards stack on the Live tab).
    @Published var incomingLive: [InviteWithSender] = []
    // Missed invites the user can still act on.
    @Published var missed: [InviteWithSender] = []

    // UI
    @Published var tab: Tab = .live
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastChatRoomId: UUID?
    /// Invite id for which a network action (accept/decline) is currently
    /// in flight. Cards observe this to disable themselves and show a
    /// spinner.
    @Published var processingInviteId: UUID?

    /// Active report context (drives the .sheet(item:) on InvitesView).
    @Published var pendingReport: ReportContext?

    struct ReportContext: Identifiable, Equatable {
        let id = UUID()
        let targetType: ReportTargetType
        let targetId: UUID
    }

    func presentReportInvite(_ invite: Invite) {
        pendingReport = .init(targetType: .invite, targetId: invite.id)
    }

    // Dev compose form (sender side, used from a small debug card).
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
            async let inboxList  = InviteService.shared.fetchIncomingLivePendingWithSender(userId: uid)
            async let missedList = InviteService.shared.fetchMissedInvitesWithSender(userId: uid)
            let (i, m) = try await (inboxList, missedList)
            incomingLive = i
            missed       = m
            GALog.invite.info("invites.refresh ok live=\(i.count, privacy: .public) missed=\(m.count, privacy: .public)")
        } catch {
            GALog.invite.error("invites.refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Receiver actions

    func acceptLive(_ invite: Invite) async {
        guard processingInviteId == nil else { return }
        processingInviteId = invite.id
        defer { processingInviteId = nil }
        errorMessage = nil
        do {
            let resp = try await InviteService.shared.acceptLiveInvite(inviteId: invite.id)
            lastChatRoomId  = resp.chatRoomId
            incomingLive.removeAll { $0.id == invite.id }
            await refresh()
            Haptics.success()
        } catch let e as InviteServiceError {
            errorMessage = e.errorDescription
            Haptics.error()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    func declineLive(_ invite: Invite) async {
        await decline(invite)
    }

    func decline(_ invite: Invite) async {
        guard processingInviteId == nil else { return }
        processingInviteId = invite.id
        defer { processingInviteId = nil }
        do {
            try await InviteService.shared.declineInvite(inviteId: invite.id)
            incomingLive.removeAll { $0.id == invite.id }
            missed.removeAll       { $0.id == invite.id }
            await refresh()
        } catch let e as InviteServiceError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func acceptMissed(_ invite: Invite) async {
        guard processingInviteId == nil else { return }
        processingInviteId = invite.id
        defer { processingInviteId = nil }
        errorMessage = nil
        do {
            let resp = try await InviteService.shared.acceptMissedInvite(inviteId: invite.id)
            lastChatRoomId = resp.chatRoomId
            missed.removeAll { $0.id == invite.id }
            await refresh()
            Haptics.success()
        } catch let e as InviteServiceError {
            // Server is the source of truth for the daily / plan-based
            // missed-accept limit; surface its message.
            errorMessage = e.errorDescription
            Haptics.error()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
    }

    /// Fired by the live card when its 15-second countdown reaches zero.
    /// We mark the invite missed server-side (idempotent — the backend
    /// also expires it) and drop it from the local Live list immediately
    /// so the UI doesn't sit on a 0s card.
    func liveCountdownExpired(_ inviteWithSender: InviteWithSender) async {
        let id = inviteWithSender.invite.id
        incomingLive.removeAll { $0.id == id }
        do {
            try await InviteService.shared.markLiveInviteMissed(inviteId: id)
        } catch {
            GALog.invite.error("markLiveInviteMissed: \(error.localizedDescription, privacy: .public)")
        }
        await refresh()
    }

    // MARK: - Dev compose

    func sendDevCompose() async {
        composeError = nil
        let handle = composeHandle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
        guard handle.count >= 3 else {
            composeError = String(localized: "signals.dev.recipient.error")
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
    }
}
