import SwiftUI

@MainActor
final class BlockedUsersViewModel: ObservableObject {
    @Published var rows: [BlockedUser] = []
    @Published var isLoading: Bool = false
    @Published var loadError: String?
    @Published var rowError: String?
    /// Drives the top-of-screen success toast. Cleared automatically
    /// after the toast's own timeout, or on user tap.
    @Published var unblockedToast: String?
    /// userId currently being unblocked. Drives per-row spinner + disable.
    @Published var processingId: UUID?
    /// Set when the user taps Unblock; the .alert reads this and the
    /// confirm-action passes it through to `confirmUnblock`.
    @Published var pendingUnblock: BlockedUser?

    func reload() async {
        isLoading = rows.isEmpty
        defer { isLoading = false }
        do {
            rows = try await ReportService.shared.fetchBlockedUsers()
            loadError = nil
        } catch {
            // Pull-to-refresh / view-teardown cancellation is not a real
            // failure — keep current rows and the empty/normal state.
            if error.isCancellation { return }
            GALog.app.error("blocked users: \(error.localizedDescription)")
            loadError = String(localized: "safety.blockedUsers.loadError")
        }
    }

    func confirmUnblock(_ user: BlockedUser) async {
        guard processingId == nil else { return }
        processingId = user.userId
        defer { processingId = nil }
        rowError = nil
        do {
            try await ReportService.shared.unblockUser(userId: user.userId)
            rows.removeAll { $0.userId == user.userId }
            unblockedToast = String(localized: "safety.unblock.toast.success")
            Haptics.success()
        } catch {
            rowError = String(localized: "safety.blockedUsers.unblockError")
            Haptics.error()
        }
    }
}

struct BlockedUsersView: View {
    @StateObject private var vm = BlockedUsersViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.lg) {
                    if vm.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 100)
                    } else if vm.rows.isEmpty {
                        GACard {
                            GAEmptyState(
                                title: String(localized: "safety.blockedUsers.empty.title"),
                                message: String(localized: "safety.blockedUsers.empty.subtitle"),
                                systemImage: "hand.raised"
                            )
                        }
                    } else {
                        VStack(spacing: GASpacing.md) {
                            ForEach(vm.rows) { row in
                                BlockedUserRow(
                                    user: row,
                                    isBusy: vm.processingId == row.userId,
                                    onUnblock: { vm.pendingUnblock = row }
                                )
                            }
                        }
                    }

                    if let err = vm.loadError {
                        GAErrorBanner(message: err,
                                      onRetry: { Task { await vm.reload() } },
                                      onDismiss: { vm.loadError = nil })
                    }
                    if let err = vm.rowError {
                        GAErrorBanner(message: err,
                                      onDismiss: { vm.rowError = nil })
                    }
                }
            }

            // Top-of-screen success toast (shared GATopToast shell —
            // same auto-dismiss + drag-up pattern as the Discovery
            // warning toast). Placed in the same ZStack so it floats
            // above scroll content.
            if let ok = vm.unblockedToast {
                GATopToast(kind: .success,
                           message: ok) { vm.unblockedToast = nil }
                    .padding(.horizontal, GASpacing.lg)
                    .padding(.top, GASpacing.md)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.unblockedToast)
        .navigationTitle(String(localized: "safety.blockedUsers.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
        // Center alert instead of the previous bottom confirmationDialog.
        // System destructive-action affordance is what we want here.
        .alert(
            String(localized: "safety.unblock.alert.title"),
            isPresented: pendingBinding,
            presenting: vm.pendingUnblock
        ) { target in
            Button(String(localized: "safety.unblock.alert.action"),
                   role: .destructive) {
                Task { await vm.confirmUnblock(target) }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: { _ in
            Text("safety.unblock.alert.message")
        }
    }

    private var pendingBinding: Binding<Bool> {
        Binding(
            get: { vm.pendingUnblock != nil },
            set: { if !$0 { vm.pendingUnblock = nil } }
        )
    }
}

private struct BlockedUserRow: View {
    let user: BlockedUser
    let isBusy: Bool
    let onUnblock: () -> Void

    var body: some View {
        GACard(kind: .standard, padding: GASpacing.md) {
            HStack(spacing: GASpacing.md) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    // Primary identity: one-line profile / bio. Falls
                    // back to a localized "No line yet" placeholder so
                    // we never expose the raw handle as the only label.
                    Text(user.primaryLine)
                        .font(GATypography.bodyEmphasized)
                        .foregroundStyle(GAColors.textPrimary)
                        .lineLimit(2)
                    if let handle = user.handle {
                        Text(handle)
                            .font(GATypography.caption)
                            .foregroundStyle(GAColors.textTertiary)
                    }
                }
                Spacer()
                GAButton(
                    title: String(localized: "safety.blockedUsers.unblock"),
                    kind: .secondary,
                    size: .compact,
                    isLoading: isBusy,
                    isDisabled: isBusy,
                    fillsWidth: false,
                    action: onUnblock
                )
            }
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [GAColors.accentSoft, GAColors.surfaceRaised],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials)
                .font(GATypography.caption.weight(.bold))
                .foregroundStyle(GAColors.accent)
        }
        .frame(width: 36, height: 36)
        .overlay(Circle().strokeBorder(GAColors.border, lineWidth: 0.75))
    }

    private var initials: String {
        let source = user.primaryLine
        let r = source.unicodeScalars.first
            .map { String(Character($0)).uppercased() } ?? "•"
        return r.isEmpty ? "•" : r
    }
}

