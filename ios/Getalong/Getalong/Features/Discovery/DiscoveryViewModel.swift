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

    /// Global warning toast triggered by soft validation errors that do
    /// NOT belong inline under a Discovery card. The "already has an
    /// active live invite" rejection lives here so the card layout
    /// stays stable (no height jump, no per-card error chip).
    @Published var inviteToast: String?

    /// Per-card send state keyed by profile id. Cleared on every
    /// successful refresh so a stale "sent" never carries over.
    @Published var sendStates: [UUID: CardSendState] = [:]

    /// Outgoing invite ids per profile id, set after a successful
    /// `sendLiveInvite`. Used by the realtime reconciliation pass to
    /// drop a sent-state card the moment its underlying invite leaves
    /// `live_pending` — accepted, declined, expired, missed.
    private var sentInviteIds: [UUID: UUID] = [:]
    private var realtimeListenerToken: UUID?
    private var currentUserId: UUID?

    /// Active report context for a profile card.
    @Published var pendingReport: ReportContext?

    /// Active block confirmation context for a profile card.
    @Published var pendingBlock: BlockContext?

    struct BlockContext: Identifiable, Equatable {
        let id = UUID()
        let userId: UUID
        /// The blocked user's one-line profile (bio). Primary identity
        /// in BlockUserSheet; falls back to a localized "No line yet"
        /// if empty so the sheet never shows the raw handle as primary.
        let line: String?
        /// `@handle` without the leading `@`. Shown as secondary text
        /// in the sheet.
        let handle: String?
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

    // MARK: - Lifecycle

    func attach(userId: UUID) async {
        guard currentUserId != userId else { return }
        // User switched on a reused view model (AppRouter can transition
        // .authenticated(A) -> .authenticated(B) without rebuilding the
        // tab tree). Invalidate the previous user's in-flight refresh so
        // its result can't land in the new user's feed; the session-token
        // guard in fetchBatch is the final backstop.
        refreshTask?.cancel()
        refreshTask = nil
        currentUserId = userId
        // Watch the user's own invite mutations so a sent-state card
        // drops the moment the receiver accepts (or it expires) —
        // without waiting for the 15-second ring to finish.
        let token = await RealtimeInviteManager.shared.addListener(userId: userId) {
            [weak self] in
            Task { await self?.reconcileOutgoingInvites() }
        }
        realtimeListenerToken = token
    }

    func detach() {
        // Cancel any in-flight refresh so a fetch can't complete and
        // mutate published state after the view has gone away (tab
        // switch / sign-out). onDisappear — not gesture release — is the
        // only thing that calls detach(), so this does NOT reintroduce
        // the refreshable-cancellation bug we fixed.
        refreshTask?.cancel()
        refreshTask = nil
        if let t = realtimeListenerToken {
            RealtimeInviteManager.shared.removeListener(t)
            realtimeListenerToken = nil
        }
    }

    // MARK: - Loads

    enum RefreshSource: String { case pull, manual }

    /// The in-flight refresh, owned by the view model rather than the
    /// SwiftUI `.refreshable` / button closure. Decoupling matters: a
    /// `.refreshable` task gets cancelled the instant the gesture is
    /// released or the view subtree rebuilds (we saw refreshes cancelled
    /// at ~16 ms), which previously aborted the network call. As an
    /// unstructured `Task` this fetch is NOT a child of the view's task
    /// tree, so it runs to completion regardless; the closure just awaits
    /// its result to keep the pull spinner up.
    private var refreshTask: Task<Bool, Never>?

    func loadInitial() async {
        guard isLoadingInitial || profiles.isEmpty else { return }
        _ = await fetchBatch(excludeCurrent: false)
    }

    func refresh(source: RefreshSource = .manual) async {
        // Serialize: if a refresh is already running, await it instead of
        // launching a duplicate fetch (covers pull + top-bar button both
        // firing, or a refresh racing the previous one).
        if let existing = refreshTask {
            _ = await existing.value
            return
        }
        guard !isRefreshing else { return }

        isRefreshing = true
        GALog.discovery.info("refresh.start source=\(source.rawValue, privacy: .public)")

        // Refresh-diversity: send the IDs we're currently showing as a
        // SESSION HINT only — the server `discovery_exposures` history is
        // the authoritative seen-memory. Run the fetch in a VM-owned
        // unstructured Task so SwiftUI cancelling the `.refreshable`
        // closure (gesture release, view rebuild, tab switch) cannot
        // cancel the actual network request.
        let task = Task { [weak self] () -> Bool in
            guard let self else { return false }
            return await self.fetchBatch(excludeCurrent: true)
        }
        refreshTask = task
        let succeeded = await task.value
        refreshTask = nil
        isRefreshing = false

        // Cooldown starts ONLY on a real success. A cancelled or failed
        // refresh must not arm the cooldown (it would block the next
        // genuine refresh for no reason).
        guard succeeded else { return }
        lastRefreshAt = Date()
        startCooldownTickIfNeeded()
        GALog.discovery.info("cooldown.started")
    }

    /// Manual refresh from the top-bar button / pull-to-refresh. No-ops if
    /// a refresh is already running or the cooldown window hasn't elapsed.
    func tryManualRefresh(source: RefreshSource = .manual) async {
        guard cooldownRemaining <= 0, !isRefreshing else {
            let reason = cooldownRemaining > 0 ? "cooldown" : "already-refreshing"
            GALog.discovery.info("refresh.skip reason=\(reason, privacy: .public)")
            return
        }
        await refresh(source: source)
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

    /// Returns true ONLY when `profiles` was successfully replaced.
    /// Returns false on cancellation (no-op, state preserved) and on
    /// error. Callers use this to decide whether to arm the cooldown.
    @discardableResult
    private func fetchBatch(excludeCurrent: Bool) async -> Bool {
        // Snapshot the session this fetch belongs to. AppRouter can move
        // .authenticated(A) -> .authenticated(B) without tearing the tab
        // tree down, so this view model can outlive a user switch. If the
        // signed-in user changes while the request is in flight, we must
        // NOT let A's results overwrite B's feed.
        let requestUserId = currentUserId
        if profiles.isEmpty { isLoadingInitial = true }
        // Session hint only — the currently-visible IDs. Server exposure
        // history is the production seen-memory; this just covers the
        // on-screen cards until the next server exposure read catches up.
        let excluded = excludeCurrent ? profiles.map(\.id) : []
        do {
            let resp = try await DiscoveryService.shared.fetchFeed(
                limit: Self.pageSize,
                excludeIds: excluded
            )
            // Stale-session backstop: discard if the user changed while we
            // were awaiting. (requestUserId == nil means the very first
            // load fired before attach() set the id — that result is for
            // the only/current session, so it's safe to keep.)
            if let req = requestUserId, req != currentUserId {
                GALog.discovery.info("refresh.discarded reason=user-changed")
                return false
            }
            // Replace the entire list — no append, no merge. This is the
            // whole point of the 10-card batch model: refresh = a new
            // small set, not a longer feed.
            profiles = resp.items
            sendStates = [:]
            sentInviteIds = [:]
            loadError = nil
            isLoadingInitial = false
            GALog.discovery.info("refresh.success items=\(resp.items.count, privacy: .public)")
            return true
        } catch let e as DiscoveryServiceError {
            isLoadingInitial = false
            // Cancellation = the SwiftUI Task was torn down or a newer
            // request superseded this one. Don't surface that to the
            // user, don't blow away an already-good `profiles` list, and
            // don't arm the cooldown.
            if e == .cancelled {
                GALog.discovery.info("refresh.cancelled no-cooldown")
                return false
            }
            loadError = e.errorDescription
            GALog.discovery.info("refresh.failed no-cooldown")
            return false
        } catch {
            isLoadingInitial = false
            loadError = String(localized: "discovery.error.loadFailed")
            GALog.discovery.info("refresh.failed no-cooldown")
            return false
        }
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
            let resp = try await InviteService.shared.sendLiveInvite(receiverId: profile.id)
            sendStates[profile.id] = .sent
            sentInviteIds[profile.id] = resp.inviteId
            Haptics.success()
        } catch let e as InviteServiceError {
            // If a block was hidden behind a stale row, drop the card.
            if e == .blockedRelationship || e == .receiverBanned {
                profiles.removeAll { $0.id == profile.id }
                sendStates.removeValue(forKey: profile.id)
                return
            }
            // "Already have an active live invite" is a global, not a
            // per-card failure — surface it as a top toast so the card
            // layout doesn't jump under the user's tap. Reset the
            // tapped card back to idle so they can retry once the
            // existing invite settles.
            //
            // Anti-spam: only set the toast (and fire the haptic) if
            // one isn't already on screen. Rapid taps while the toast
            // is visible bounce off cheaply — the toast itself runs a
            // single 3.2-s auto-dismiss timer keyed on the message
            // string, so an identical re-set wouldn't restart it
            // anyway, but skipping the haptic + state churn keeps the
            // experience clean.
            if e == .liveInviteSlotFull {
                sendStates.removeValue(forKey: profile.id)
                if inviteToast == nil {
                    inviteToast = e.errorDescription
                        ?? String(localized: "error.liveSignalSlotFull")
                    Haptics.warning()
                }
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

    /// Triggered on every realtime invite event for the current user.
    /// Cross-references our locally-tracked sent invite ids against the
    /// server's outgoing live_pending list — any tracked id missing
    /// from the server side has left live_pending (accepted, declined,
    /// expired, missed) and the matching card should drop immediately.
    private func reconcileOutgoingInvites() async {
        guard let uid = currentUserId, !sentInviteIds.isEmpty else { return }
        let pending = (try? await InviteService.shared.fetchOutgoingLivePending(userId: uid)) ?? []
        let stillPending = Set(pending.map(\.id))
        for (profileId, inviteId) in sentInviteIds where !stillPending.contains(inviteId) {
            GALog.discovery.info(
                "vm.reconcile drop card profile=\(profileId.uuidString, privacy: .public) invite=\(inviteId.uuidString, privacy: .public) reason=outgoing-no-longer-pending"
            )
            profiles.removeAll { $0.id == profileId }
            sendStates.removeValue(forKey: profileId)
            sentInviteIds.removeValue(forKey: profileId)
        }
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
        pendingBlock = .init(
            userId: profile.id,
            line:   profile.bio,
            handle: profile.getalongId
        )
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
