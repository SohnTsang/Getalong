import Foundation
import SwiftUI
import UIKit

/// Lightweight observable that tracks the receiver-side missed count
/// and a "live invite is in flight" flag for the signed-in user.
///
/// Update sources, in priority order:
///   1. Supabase Realtime postgres-changes — primary signal. One
///      shared websocket per user, fanned out to listeners. Updates
///      land within ~1s of any invite row change.
///   2. App-foreground notification — catches anything missed while
///      the websocket was suspended in the background.
///   3. Slow safety-net poll — only runs while the realtime channel
///      is NOT confirmed connected, so we don't double up the
///      requests when realtime is healthy. Suspended in background.
///
/// Hot-path mutators (`setMissedCount`, `setHasActiveLiveInvite`) let
/// the Invite VM and the Discovery view push state directly without an
/// extra round trip — useful for the instant accent-border feedback
/// when the local user just sent an invite.
@MainActor
final class MissedInvitesTracker: ObservableObject {
    @Published private(set) var missedCount: Int = 0
    /// True only when the user is on the **receiving** side of a
    /// live_pending invite — i.e. someone else is inviting them and
    /// they have a 15-second window to act. Outgoing invites never
    /// flip this; the sender already sees their own countdown ring on
    /// the Discovery card and doesn't need a global navbar tint.
    @Published private(set) var hasActiveLiveInvite: Bool = false

    /// Slow safety-net poll. Only used while realtime hasn't confirmed
    /// it's healthy (initial connection, after a network blip, etc.).
    /// Once realtime is connected we cancel this timer entirely.
    private var pollTimer: Timer?

    /// Min seconds between refreshes. Realtime can fan a single user
    /// action into 2-3 row changes (insert, status flip, lock release);
    /// without coalescing each one becomes a SELECT round trip. 0.5s is
    /// short enough that the UI feels instant and long enough to fold a
    /// burst into one fetch.
    private let coalesceWindow: TimeInterval = 0.5
    private var pendingRefresh: Task<Void, Never>?
    private var refreshInFlight: Bool = false

    private var foregroundObserver: NSObjectProtocol?
    private var backgroundObserver: NSObjectProtocol?
    private var livePushObserver: NSObjectProtocol?
    private var realtimeListenerToken: UUID?
    private var realtimeHealthy: Bool = false
    private(set) var currentUserId: UUID?

    /// One-shot Task that re-runs runRefresh exactly when the earliest
    /// `live_expires_at` of the currently-pending incoming invites
    /// elapses. We can't trust realtime UPDATE events to flip the row
    /// to 'missed' — that's done by an `expireLiveInvites` cron, which
    /// runs on its own cadence — so we schedule the refresh locally.
    /// Without this, `hasActiveLiveInvite` stays true after the 15s
    /// window closes until a tab switch forces a manual refresh.
    private var liveExpiryTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func attach(userId: UUID) {
        guard currentUserId != userId else { return }
        currentUserId = userId
        scheduleRefresh()
        observeAppLifecycle()
        startRealtime(userId: userId)
        startPollingIfNeeded()
    }

    func detach() {
        currentUserId = nil
        missedCount = 0
        hasActiveLiveInvite = false
        realtimeHealthy = false
        pendingRefresh?.cancel(); pendingRefresh = nil
        liveExpiryTask?.cancel(); liveExpiryTask = nil
        pollTimer?.invalidate();  pollTimer = nil
        if let token = foregroundObserver {
            NotificationCenter.default.removeObserver(token)
            foregroundObserver = nil
        }
        if let token = backgroundObserver {
            NotificationCenter.default.removeObserver(token)
            backgroundObserver = nil
        }
        if let token = livePushObserver {
            NotificationCenter.default.removeObserver(token)
            livePushObserver = nil
        }
        if let token = realtimeListenerToken {
            RealtimeInviteManager.shared.removeListener(token)
            realtimeListenerToken = nil
        }
    }

    // MARK: - Hot-path mutators

    func setMissedCount(_ count: Int) {
        let clamped = max(0, count)
        if missedCount != clamped { missedCount = clamped }
    }

    func setHasActiveLiveInvite(_ value: Bool) {
        if hasActiveLiveInvite != value { hasActiveLiveInvite = value }
    }

    // MARK: - Refresh

    /// Coalesces bursts of triggers into a single network refresh. If a
    /// refresh is already running, marks the result stale; if one is
    /// queued within `coalesceWindow`, drops the duplicate.
    func scheduleRefresh() {
        if pendingRefresh != nil { return }
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(0.5 * 1_000_000_000))
            await self?.runRefresh()
            await MainActor.run { self?.pendingRefresh = nil }
        }
    }

    private func runRefresh() async {
        guard !refreshInFlight, let uid = currentUserId else { return }
        refreshInFlight = true
        defer { refreshInFlight = false }

        // Only fetch incoming — the navbar tint is a "someone is
        // inviting you right now" signal. Outgoing invites are
        // intentionally ignored here; the sender sees their own
        // countdown ring on the Discovery card.
        async let missedCall   = InviteService.shared.fetchMissedInvites(userId: uid)
        async let incomingCall = InviteService.shared.fetchIncomingLivePending(userId: uid)
        do {
            let (m, i) = try await (missedCall, incomingCall)
            // Match the InvitesView dedupe rule: one badge per distinct
            // sender. Multiple invites from the same person collapse to
            // one card on screen, so the badge has to as well —
            // otherwise the number won't agree with what the user sees.
            let distinctSenders = Set(m.map(\.senderId)).count
            setMissedCount(distinctSenders)
            setHasActiveLiveInvite(!i.isEmpty)
            scheduleLiveExpiryClear(for: i)
        } catch {
            GALog.invite.error("invite-tracker refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Schedules a local refresh at the earliest `live_expires_at` so
    /// the navbar accent clears the moment the 15s window closes,
    /// even if the server's expireLiveInvites cron hasn't yet flipped
    /// the row to 'missed'.
    private func scheduleLiveExpiryClear(for invites: [Invite]) {
        liveExpiryTask?.cancel()
        liveExpiryTask = nil
        guard let soonest = invites.map(\.liveExpiresAt).min() else { return }
        let delay = soonest.timeIntervalSinceNow + 1   // +1s safety margin
        guard delay > 0 else {
            scheduleRefresh()
            return
        }
        liveExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.scheduleRefresh() }
        }
    }

    /// Public alias preserved for callers that want an immediate
    /// non-coalesced refresh (e.g. when entering the Invite tab).
    func refresh() async { await runRefresh() }

    // MARK: - Realtime

    private func startRealtime(userId: UUID) {
        Task {
            let token = await RealtimeInviteManager.shared.addListener(userId: userId) {
                [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    self.realtimeHealthy = true
                    self.stopPolling()  // realtime took over; turn the timer off
                    self.scheduleRefresh()
                }
            }
            self.realtimeListenerToken = token
        }
    }

    // MARK: - Background-aware polling

    /// Slow safety-net poll for the case where realtime hasn't connected
    /// yet (cold start) or has been lost without us realising. We pick a
    /// long interval (90s) because the websocket is the primary signal.
    /// While the app is backgrounded the timer is suspended.
    private func startPollingIfNeeded() {
        guard pollTimer == nil, !realtimeHealthy else { return }
        // Timer's closure is @Sendable; hop to MainActor explicitly so
        // we can touch this @MainActor instance safely.
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: 90, repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.realtimeHealthy { self.stopPolling(); return }
                self.scheduleRefresh()
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - App lifecycle

    private func observeAppLifecycle() {
        if foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                // Background may have suspended the websocket; do one
                // catch-up refresh and resume the safety-net timer.
                Task { @MainActor in
                    self.scheduleRefresh()
                    self.startPollingIfNeeded()
                }
            }
        }
        if backgroundObserver == nil {
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    // No CPU/battery while the app isn't visible.
                    self.stopPolling()
                    self.realtimeHealthy = false  // re-verify on resume
                }
            }
        }
        // Foreground APNs push for a live invite — the realtime
        // websocket can fail to subscribe at sign-in (CancellationError)
        // and only recovers via its own retry path. Pushes always
        // arrive, so this gives the navbar tint a fast, reliable
        // signal independent of the socket.
        if livePushObserver == nil {
            livePushObserver = NotificationCenter.default.addObserver(
                forName: .gaLiveInvitePushReceived,
                object: nil, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.scheduleRefresh() }
            }
        }
    }
}
