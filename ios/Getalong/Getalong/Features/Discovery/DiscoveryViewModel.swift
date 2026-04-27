import Foundation
import SwiftUI

@MainActor
final class DiscoveryViewModel: ObservableObject {

    enum CardSendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    /// Discovery shows a single batch of up to 10 cards. Refresh replaces
    /// the whole list. There is no infinite scroll, no load-more, and no
    /// next-page paging on iOS.
    static let pageSize: Int = 10

    @Published var profiles: [DiscoveryProfile] = []
    @Published var isLoadingInitial: Bool = true
    @Published var isRefreshing: Bool = false
    @Published var loadError: String?

    /// Per-card send state keyed by profile id. Cleared on every
    /// successful refresh so a stale "sent" never carries over.
    @Published var sendStates: [UUID: CardSendState] = [:]

    /// Active report context for a profile card.
    @Published var pendingReport: ReportContext?

    /// Active block confirmation context for a profile card.
    @Published var pendingBlock: BlockContext?

    struct BlockContext: Identifiable, Equatable {
        let id = UUID()
        let userId: UUID
        let displayName: String?
    }

    /// Hard rate limit for the manual refresh button: at least this many
    /// seconds between successful refreshes. Prevents users from spamming
    /// the Edge Function.
    private let manualRefreshCooldown: TimeInterval = 6

    /// Last time refresh() completed successfully. Drives the cooldown
    /// countdown on the top-bar refresh button.
    @Published private(set) var lastRefreshAt: Date?
    /// Wall-clock now, recomputed every second only while a cooldown
    /// is active, so `cooldownRemaining` actually changes.
    @Published private var clockTick: Date = Date()
    private var clockTimer: Timer?

    struct ReportContext: Identifiable, Equatable {
        let id = UUID()
        let targetId: UUID
    }

    // MARK: - Loads

    func loadInitial() async {
        guard isLoadingInitial || profiles.isEmpty else { return }
        await fetchBatch(excludeCurrent: false)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // Refresh-diversity: ask the backend to skip the IDs we're
        // currently showing. The server falls back to repeats if there
        // aren't enough fresh candidates.
        await fetchBatch(excludeCurrent: true)
        lastRefreshAt = Date()
        startCooldownTickIfNeeded()
    }

    /// Manual refresh from the top-bar button. No-ops if a refresh is
    /// already running or the cooldown window hasn't elapsed yet.
    func tryManualRefresh() async {
        guard cooldownRemaining <= 0, !isRefreshing else { return }
        await refresh()
    }

    /// Seconds remaining until the user may manually refresh again.
    var cooldownRemaining: TimeInterval {
        guard let last = lastRefreshAt else { return 0 }
        let elapsed = clockTick.timeIntervalSince(last)
        return max(0, manualRefreshCooldown - elapsed)
    }

    private func startCooldownTickIfNeeded() {
        clockTimer?.invalidate()
        clockTick = Date()
        guard cooldownRemaining > 0 else { return }
        clockTimer = Timer.scheduledTimer(
            withTimeInterval: 1, repeats: true
        ) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                self.clockTick = Date()
                if self.cooldownRemaining <= 0 {
                    timer.invalidate()
                }
            }
        }
    }

    private func fetchBatch(excludeCurrent: Bool) async {
        if profiles.isEmpty { isLoadingInitial = true }
        let excluded = excludeCurrent ? profiles.map(\.id) : []
        do {
            let resp = try await DiscoveryService.shared.fetchFeed(
                limit: Self.pageSize,
                excludeIds: excluded
            )
            // Replace the entire list — no append, no merge. This is the
            // whole point of the 10-card batch model: refresh = a new
            // small set, not a longer feed.
            profiles = resp.items
            sendStates = [:]
            loadError = nil
        } catch let e as DiscoveryServiceError {
            // Cancellation = the SwiftUI Task was torn down or a newer
            // request superseded this one. Don't surface that to the
            // user, and don't blow away an already-good `profiles` list.
            if e == .cancelled {
                GALog.discovery.info("vm.fetchBatch cancelled — keeping current state")
            } else {
                loadError = e.errorDescription
            }
        } catch {
            loadError = String(localized: "discovery.error.loadFailed")
        }
        isLoadingInitial = false
    }

    // MARK: - Send Live Invite

    func sendSignal(to profile: DiscoveryProfile) async {
        let current = sendStates[profile.id] ?? .idle
        switch current {
        case .sending, .sent: return
        default: break
        }
        sendStates[profile.id] = .sending
        do {
            _ = try await InviteService.shared.sendLiveInvite(receiverId: profile.id)
            sendStates[profile.id] = .sent
            Haptics.success()
        } catch let e as InviteServiceError {
            // If a block was hidden behind a stale row, drop the card.
            if e == .blockedRelationship || e == .receiverBanned {
                profiles.removeAll { $0.id == profile.id }
                sendStates.removeValue(forKey: profile.id)
                return
            }
            sendStates[profile.id] = .failed(
                e.errorDescription ?? String(localized: "error.generic"))
            Haptics.error()
        } catch {
            sendStates[profile.id] = .failed(String(localized: "error.generic"))
            Haptics.error()
        }
    }

    func sendState(for profile: DiscoveryProfile) -> CardSendState {
        sendStates[profile.id] ?? .idle
    }

    /// Called by the card when its 15-second countdown ring reaches zero.
    /// At that point the live invite has either been accepted (a chat room
    /// will open via the realtime listener) or has lapsed into a missed
    /// invite — either way we no longer want this card sitting in the
    /// Discover list.
    func expireSentCard(_ profile: DiscoveryProfile) {
        guard sendStates[profile.id] == .sent else { return }
        GALog.discovery.info("vm.expireSentCard id=\(profile.id.uuidString, privacy: .public)")
        profiles.removeAll { $0.id == profile.id }
        sendStates.removeValue(forKey: profile.id)
    }

    // MARK: - Report

    func presentReport(_ profile: DiscoveryProfile) {
        pendingReport = .init(targetId: profile.id)
    }

    func presentBlock(_ profile: DiscoveryProfile) {
        pendingBlock = .init(userId: profile.id, displayName: profile.displayName)
    }

    /// Called by BlockUserSheet's onBlocked closure after the server has
    /// successfully recorded the block. Drop the row from the feed and
    /// dismiss the sheet.
    func confirmBlocked(userId: UUID) async {
        profiles.removeAll { $0.id == userId }
        sendStates.removeValue(forKey: userId)
        pendingBlock = nil
    }
}
