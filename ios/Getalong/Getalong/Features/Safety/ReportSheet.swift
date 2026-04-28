import SwiftUI

/// Sheet for reporting a profile, message, or media. The caller decides
/// the target by passing `targetType` + `targetId`. Submission is
/// idempotent server-side, so a re-tap (network drop, etc.) is safe.
struct ReportSheet: View {
    let targetType: ReportTargetType
    let targetId: UUID
    /// Optional. When the report is filed from inside a chat (reporting
    /// the partner's profile, a media bubble, or a message), pass the
    /// room id so the backend can scope evidence preservation to that
    /// conversation. Ignored server-side for invite/profile-without-room
    /// reports.
    var contextRoomId: UUID? = nil
    let onClose: () -> Void

    @State private var selectedReason: ReportReason?
    @State private var details: String = ""
    @State private var phase: Phase = .editing

    enum Phase: Equatable {
        case editing
        case submitting
        case success
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GASpacing.lg) {
            header
            if case .success = phase {
                successView
            } else {
                content
            }
        }
        .padding(GASpacing.lg)
        .background(GAColors.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(phase == .submitting)
    }

    // MARK: -

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("safety.report.title")
                    .font(GATypography.title)
                    .foregroundStyle(GAColors.textPrimary)
                Text("safety.report.subtitle")
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GAColors.textSecondary)
                    .frame(width: 32, height: 32)
                    .background(GAColors.surfaceRaised, in: Circle())
            }
            .accessibilityLabel(String(localized: "common.cancel"))
            .disabled(phase == .submitting)
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GASpacing.lg) {
                reasonList
                detailsField
                if case .error(let m) = phase {
                    GAErrorBanner(message: m, onDismiss: { phase = .editing })
                }
                submitButton
            }
        }
    }

    private var reasonList: some View {
        VStack(spacing: 0) {
            ForEach(ReportReason.allCases) { reason in
                reasonRow(reason)
                if reason != ReportReason.allCases.last {
                    Rectangle().fill(GAColors.border).frame(height: 0.5)
                }
            }
        }
        .background(GAColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                    style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.large,
                             style: .continuous)
                .strokeBorder(GAColors.border, lineWidth: 0.75)
        )
    }

    private func reasonRow(_ reason: ReportReason) -> some View {
        Button {
            selectedReason = reason
        } label: {
            HStack {
                Text(reason.localizedLabel)
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textPrimary)
                Spacer()
                Image(systemName: selectedReason == reason
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedReason == reason
                                     ? GAColors.accent : GAColors.textTertiary)
            }
            .padding(.horizontal, GASpacing.md)
            .padding(.vertical, GASpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detailsField: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            ZStack(alignment: .topLeading) {
                if details.isEmpty {
                    Text("safety.report.details.placeholder")
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $details)
                    .font(GATypography.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(minHeight: 96)
            }
            .background(GAColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.large,
                                        style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.large,
                                 style: .continuous)
                    .strokeBorder(GAColors.border, lineWidth: 0.75)
            )
        }
    }

    private var submitButton: some View {
        GAButton(
            title: String(localized: "safety.report.submit"),
            kind: .primary,
            isLoading: phase == .submitting,
            isDisabled: selectedReason == nil || phase == .submitting
        ) {
            Task { await submit() }
        }
    }

    private var successView: some View {
        VStack(alignment: .leading, spacing: GASpacing.md) {
            HStack(spacing: GASpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(GAColors.success)
                    .font(.system(size: 22, weight: .regular))
                Text("safety.report.success")
                    .font(GATypography.bodyEmphasized)
                    .foregroundStyle(GAColors.textPrimary)
            }
            GAButton(title: String(localized: "common.close"),
                     kind: .ghost, action: onClose)
        }
    }

    // MARK: -

    private func submit() async {
        guard let reason = selectedReason, phase != .submitting else { return }
        phase = .submitting
        do {
            _ = try await ReportService.shared.report(
                targetType:    targetType,
                targetId:      targetId,
                reason:        reason,
                details:       details,
                contextRoomId: contextRoomId
            )
            Haptics.success()
            phase = .success
        } catch let e as SafetyServiceError {
            phase = .error(e.errorDescription ?? String(localized: "safety.report.error"))
            Haptics.error()
        } catch {
            phase = .error(String(localized: "safety.report.error"))
            Haptics.error()
        }
    }
}
