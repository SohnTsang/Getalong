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

    /// Trigger threshold: start loading more when the card at
    /// `count - prefetchTrigger` (or later) appears.
    private let prefetchTrigger = 3

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
            loadError = e.errorDescription
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
            loadMoreError = e.errorDescription
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

    // MARK: - Report

    func presentReport(_ profile: DiscoveryProfile) {
        pendingReport = .init(targetId: profile.id)
    }
}
