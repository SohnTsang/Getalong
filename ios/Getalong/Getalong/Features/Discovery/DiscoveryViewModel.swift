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

    @Published var profiles: [DiscoveryProfile] = []
    @Published var isLoadingInitial: Bool = true
    @Published var isRefreshing: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var loadError: String?
    @Published var loadMoreError: String?
    @Published private(set) var hasMore: Bool = false

    /// Per-card send state keyed by profile id. Preserved across pagination
    /// so a "Signal sent" card stays sent after a new page lands. Cleared
    /// on pull-to-refresh by `refresh()`.
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

    /// Trigger threshold: start loading more when the card at
    /// `count - prefetchTrigger` (or later) appears.
    private let prefetchTrigger = 3

    /// Hard rate limit for the manual refresh button: at least this
    /// many seconds between successful refreshes. Prevents users from
    /// spamming the Edge Function.
    private let manualRefreshCooldown: TimeInterval = 6

    /// Last time refresh() completed successfully. Drives the
    /// cooldown countdown on the top bar refresh button.
    @Published private(set) var lastRefreshAt: Date?
    /// Wall-clock now, recomputed every second only while a cooldown
    /// is active, so `cooldownRemaining` actually changes.
    @Published private var clockTick: Date = Date()
    private var clockTimer: Timer?

    private var nextCursor: String?

    struct ReportContext: Identifiable, Equatable {
        let id = UUID()
        let targetId: UUID
    }

    // MARK: - Loads

    func loadInitial() async {
        guard isLoadingInitial || profiles.isEmpty else { return }
        await fetchFirstPage()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        sendStates = [:]
        loadMoreError = nil
        defer { isRefreshing = false }
        await fetchFirstPage()
        lastRefreshAt = Date()
        startCooldownTickIfNeeded()
    }

    /// Manual refresh from the top-bar button. No-ops if a refresh is
    /// already running or the cooldown window hasn't elapsed yet —
    /// callers don't have to guard themselves.
    func tryManualRefresh() async {
        guard cooldownRemaining <= 0, !isRefreshing else { return }
        await refresh()
    }

    /// Seconds remaining until the user may manually refresh again.
    /// Zero (or negative) means "go ahead".
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

    private func fetchFirstPage() async {
        nextCursor = nil
        hasMore = false
        if profiles.isEmpty { isLoadingInitial = true }
        do {
            let resp = try await DiscoveryService.shared.fetchFeed(cursor: nil)
            profiles = resp.items
            nextCursor = resp.nextCursor
            hasMore = resp.hasMore
            loadError = nil
        } catch let e as DiscoveryServiceError {
            // Cancellation = the SwiftUI Task was torn down or a newer
            // request superseded this one. Don't surface that to the
            // user, and don't blow away an already-good `profiles` list.
            if e == .cancelled {
                GALog.discovery.info("vm.firstPage cancelled — keeping current state")
            } else {
                loadError = e.errorDescription
            }
        } catch {
            loadError = String(localized: "discovery.error.loadFailed")
        }
        isLoadingInitial = false
    }

    /// Called by the view as cards appear. Triggers a load-more when the
    /// `currentItem` is within `prefetchTrigger` of the end and there's
    /// more to fetch. No-op when already loading or no cursor available.
    func loadMoreIfNeeded(currentItem profile: DiscoveryProfile) async {
        guard hasMore, !isLoadingMore, !isRefreshing, !isLoadingInitial else {
            return
        }
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            return
        }
        let triggerIndex = max(0, profiles.count - prefetchTrigger)
        guard index >= triggerIndex else { return }
        await loadMore()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, let cursor = nextCursor else { return }
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            let resp = try await DiscoveryService.shared.fetchFeed(cursor: cursor)
            let existing = Set(profiles.map(\.id))
            let unique = resp.items.filter { !existing.contains($0.id) }
            profiles.append(contentsOf: unique)
            nextCursor = resp.nextCursor
            hasMore = resp.hasMore
        } catch let e as DiscoveryServiceError {
            if e == .cancelled {
                GALog.discovery.info("vm.loadMore cancelled — keeping current state")
            } else {
                loadMoreError = e.errorDescription
            }
        } catch {
            loadMoreError = String(localized: "discovery.loadMoreError")
        }
    }

    // MARK: - Send Live Signal

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
    /// Discover list. A subsequent refresh may bring the same user back
    /// since the backend doesn't permanently filter them out.
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
