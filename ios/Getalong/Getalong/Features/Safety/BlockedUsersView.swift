import SwiftUI

@MainActor
final class BlockedUsersViewModel: ObservableObject {
    @Published var rows: [BlockedUser] = []
    @Published var isLoading: Bool = false
    @Published var loadError: String?
    @Published var rowError: String?
    @Published var rowSuccess: String?
    /// userId currently being unblocked. Drives per-row spinner + disable.
    @Published var processingId: UUID?
    /// Set when the user taps Unblock; the confirmation dialog reads this.
    @Published var pendingUnblock: BlockedUser?

    func reload() async {
        isLoading = rows.isEmpty
        defer { isLoading = false }
        do {
            rows = try await ReportService.shared.fetchBlockedUsers()
            loadError = nil
        } catch {
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
            rowSuccess = String(localized: "safety.blockedUsers.unblockSuccess")
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
                if let ok = vm.rowSuccess {
                    SuccessNote(text: ok, onDismiss: { vm.rowSuccess = nil })
                }
            }
        }
        .navigationTitle(String(localized: "safety.blockedUsers.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.reload() }
        .refreshable { await vm.reload() }
        .confirmationDialog(
            String(localized: "safety.blockedUsers.unblockConfirm.title"),
            isPresented: pendingBinding,
            titleVisibility: .visible,
            presenting: vm.pendingUnblock
        ) { target in
            Button(String(localized: "safety.blockedUsers.unblockConfirm.action"),
                   role: .destructive) {
                Task { await vm.confirmUnblock(target) }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: { _ in
            Text("safety.blockedUsers.unblockConfirm.message")
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
                    Text(user.displayName)
                        .font(GATypography.bodyEmphasized)
                        .foregroundStyle(GAColors.textPrimary)
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
        let words = user.displayName.split(separator: " ").prefix(2)
        let r = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return r.isEmpty ? "•" : r
    }
}

private struct SuccessNote: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: GASpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GAColors.success)
            Text(text)
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textPrimary)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GAColors.textTertiary)
            }
        }
        .padding(.horizontal, GASpacing.md)
        .padding(.vertical, GASpacing.sm)
        .background(GAColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                    style: .continuous))
    }
}
