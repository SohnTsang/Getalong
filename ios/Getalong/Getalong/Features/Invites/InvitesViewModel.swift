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

    /// Active block context (drives the .sheet(item:) on InvitesView).
    @Published var pendingBlock: BlockContext?

    struct ReportContext: Identifiable, Equatable {
        let id = UUID()
        let targetType: ReportTargetType
        let targetId: UUID
    }

    struct BlockContext: Identifiable, Equatable {
        let id = UUID()
        let userId: UUID
        let displayName: String?
    }

    func presentReportInvite(_ invite: Invite) {
        pendingReport = .init(targetType: .invite, targetId: invite.id)
    }

    func presentBlockSender(_ item: InviteWithSender) {
        pendingBlock = .init(userId: item.invite.senderId, displayName: nil)
    }

    /// Called by BlockUserSheet's onBlocked closure after the server has
    /// recorded the block — drop any invites from that sender locally.
    func confirmBlocked(senderId: UUID) async {
        incomingLive.removeAll { $0.invite.senderId == senderId }
        missed.removeAll       { $0.invite.senderId == senderId }
        pendingBlock = nil
    }

    // Dev compose form (sender side, used from a small debug card).
    @Published var composeHandle: String = ""
    @Published var composeIsSending: Bool = false
    @Published var composeError: String?

    private(set) var currentUserId: UUID?
    private var realtimeToken: UUID?

    // MARK: - Lifecycle

    func attach(userId: UUID) async {
        currentUserId = userId
        await refresh()
        // Register on the shared multi-listener channel — the tracker
        // already keeps the socket alive at the tab-bar level, so this
        // call piggybacks on it instead of tearing down a sibling
        // subscription.
        let token = await RealtimeInviteManager.shared.addListener(userId: userId) {
            [weak self] in
            Task { await self?.refresh() }
        }
        realtimeToken = token
    }

    func detach() async {
        if let t = realtimeToken {
            RealtimeInviteManager.shared.removeListener(t)
            realtimeToken = nil
        }
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
            incomingLive = Self.dedupeBySender(i)
            missed       = Self.dedupeBySender(m)
            GALog.invite.info("invites.refresh ok live=\(self.incomingLive.count, privacy: .public) missed=\(self.missed.count, privacy: .public)")
        } catch {
            GALog.invite.error("invites.refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Collapses repeat invites from the same sender to one card —
    /// keeps the most recent (the list arrives `created_at desc`).
    /// Multiple invites from the same person turn into noise, not
    /// signal; we'd rather show "this person reached out" once.
    private static func dedupeBySender(_ items: [InviteWithSender]) -> [InviteWithSender] {
        var seen = Set<UUID>()
        var out: [InviteWithSender] = []
        out.reserveCapacity(items.count)
        for item in items where !seen.contains(item.invite.senderId) {
            seen.insert(item.invite.senderId)
            out.append(item)
        }
        return out
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
            // Drop every missed card from this sender, not just the one
            // tapped. The server-side RPC also resolves siblings (see
            // migration 0018) so a refresh can't bring them back; this
            // avoids the visual lag while the request is settling and
            // makes the tab badge tick down immediately.
            missed.removeAll { $0.invite.senderId == invite.senderId }
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
