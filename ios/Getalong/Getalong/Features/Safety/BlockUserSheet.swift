import SwiftUI

/// Calm confirmation sheet shown before blocking a user. Submission is
/// idempotent server-side. After success the caller is responsible for
/// updating its local state (disabling the chat input, etc.).
struct BlockUserSheet: View {
    let userId: UUID
    let displayName: String?
    let onBlocked: () -> Void
    let onClose: () -> Void

    @State private var phase: Phase = .idle

    enum Phase: Equatable {
        case idle
        case submitting
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GASpacing.lg) {
            header
            subtitle
            if case .error(let m) = phase {
                GAErrorBanner(message: m, onDismiss: { phase = .idle })
            }
            Spacer(minLength: GASpacing.md)
            actions
        }
        .padding(GASpacing.lg)
        .background(GAColors.background.ignoresSafeArea())
        .presentationDetents([.fraction(0.4), .medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(phase == .submitting)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text("safety.block.title")
                .font(GATypography.title)
                .foregroundStyle(GAColors.textPrimary)
            if let name = displayName, !name.isEmpty {
                Text(name)
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textSecondary)
            }
        }
    }

    private var subtitle: some View {
        Text("safety.block.subtitle")
            .font(GATypography.body)
            .foregroundStyle(GAColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(spacing: GASpacing.sm) {
            GAButton(
                title: String(localized: "safety.block.confirm"),
                kind: .destructive,
                isLoading: phase == .submitting,
                isDisabled: phase == .submitting
            ) {
                Task { await submit() }
            }
            GAButton(title: String(localized: "common.cancel"),
                     kind: .ghost,
                     isDisabled: phase == .submitting,
                     action: onClose)
        }
    }

    private func submit() async {
        guard phase != .submitting else { return }
        phase = .submitting
        do {
            _ = try await ReportService.shared.blockUser(userId: userId)
            Haptics.success()
            onBlocked()
        } catch let e as SafetyServiceError {
            phase = .error(e.errorDescription ?? String(localized: "safety.block.error"))
            Haptics.error()
        } catch {
            phase = .error(String(localized: "safety.block.error"))
            Haptics.error()
        }
    }
}
