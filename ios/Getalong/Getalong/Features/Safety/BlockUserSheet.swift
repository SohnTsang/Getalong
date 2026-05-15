import SwiftUI

/// Calm confirmation sheet shown before blocking a user. Submission is
/// idempotent server-side. After success the caller is responsible for
/// updating its local state (disabling the chat input, etc.).
///
/// Identity rule: the row's one-line profile (`bio`) is the primary
/// label; `@handle` is secondary. If the bio is empty we fall through
/// to a localized "No line yet" placeholder so the user never sees a
/// raw handle as the sole identity. Display name is intentionally not
/// shown — Getalong's chat identity is the line, not the name.
struct BlockUserSheet: View {
    let userId: UUID
    /// The user's one-line profile / bio. Primary identity in the sheet.
    let line: String?
    /// `@handle` without the leading `@`. Shown as secondary text.
    let handle: String?
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
        // Extra top padding: the title was sitting too tight against
        // the drag indicator. Use a shared safety-sheet constant so
        // BlockUserSheet and ReportSheet stay aligned.
        .padding(.top, GASafetySheet.topPadding)
        .padding(.horizontal, GASpacing.lg)
        .padding(.bottom, GASpacing.lg)
        .background(GAColors.background.ignoresSafeArea())
        .presentationDetents([.fraction(0.45), .medium])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(phase == .submitting)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text("safety.block.title")
                .font(GATypography.title)
                .foregroundStyle(GAColors.textPrimary)
            // Primary identity = the one-line profile.
            Text(primaryIdentity)
                .font(GATypography.bodyEmphasized)
                .foregroundStyle(GAColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            // Secondary = @handle if we have one.
            if let h = handle, !h.isEmpty {
                Text("@\(h)")
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textTertiary)
            }
        }
    }

    private var primaryIdentity: String {
        if let l = line?.trimmingCharacters(in: .whitespacesAndNewlines),
           !l.isEmpty {
            return l
        }
        return String(localized: "safety.identity.noLine")
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

/// Shared spacing constants for safety-flow sheets so BlockUserSheet
/// and ReportSheet stay aligned without one-off magic numbers.
enum GASafetySheet {
    /// Extra distance from the sheet's top edge (drag indicator) to
    /// the first content line. Larger than the default to give the
    /// title visible breathing room.
    static let topPadding: CGFloat = 32
}
