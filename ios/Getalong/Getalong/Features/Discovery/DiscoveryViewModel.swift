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
    @Published var loadError: String?
    /// Per-card send state keyed by profile id.
    @Published var sendStates: [UUID: CardSendState] = [:]
    /// Active report context for a profile card.
    @Published var pendingReport: ReportContext?

    private var nextCursor: String?
    private var hasMore: Bool = false

    struct ReportContext: Identifiable, Equatable {
        let id = UUID()
        let targetId: UUID
    }

    // MARK: - Loads

    func loadInitial() async {
        guard isLoadingInitial || profiles.isEmpty else { return }
        await fetch(reset: true)
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        await fetch(reset: true)
    }

    private func fetch(reset: Bool) async {
        if reset {
            nextCursor = nil
            hasMore = false
            if profiles.isEmpty { isLoadingInitial = true }
        }
        do {
            let resp = try await DiscoveryService.shared
                .fetchFeed(cursor: reset ? nil : nextCursor)
            if reset {
                profiles = resp.items
            } else {
                let existing = Set(profiles.map(\.id))
                profiles.append(contentsOf: resp.items.filter { !existing.contains($0.id) })
            }
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
