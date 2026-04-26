import SwiftUI

struct MissedInviteCard: View {
    let invite: Invite
    let onAccept: () -> Void
    let onDecline: () -> Void
    var isBusy: Bool = false
    var onReport: (() -> Void)? = nil

    var body: some View {
        GACard(kind: .standard, padding: GASpacing.lg) {
            VStack(alignment: .leading, spacing: GASpacing.md) {
                HStack(spacing: GASpacing.sm) {
                    GAStatusPill(label: String(localized: "signals.missed.label"),
                                 systemImage: "dot.radiowaves.left.and.right",
                                 tint: GAColors.inviteMissed)
                    Spacer()
                    if let exp = invite.missedExpiresAt {
                        Text(String(format: NSLocalizedString("signals.missed.expires %@", comment: ""),
                                    exp.formatted(.relative(presentation: .named))))
                            .font(GATypography.caption)
                            .foregroundStyle(GAColors.textTertiary)
                    }
                }

                if let m = invite.message, !m.isEmpty {
                    Text("\u{201C}\(m)\u{201D}")
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textPrimary)
                        .lineLimit(3)
                } else {
                    Text("signals.missed.fallback")
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textSecondary)
                }

                Text("signals.missed.support")
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textTertiary)

                HStack(spacing: GASpacing.md) {
                    GAButton(title: String(localized: "signals.decline.notNow"),
                             kind: .ghost, size: .compact,
                             isDisabled: isBusy) { onDecline() }
                    GAButton(title: String(localized: "signals.accept.start"),
                             kind: .primary, size: .compact,
                             isLoading: isBusy,
                             isDisabled: isBusy) { onAccept() }
                }
            }
        }
        .contextMenu {
            if let onReport {
                Button {
                    onReport()
                } label: {
                    Label(String(localized: "safety.menu.reportSignal"),
                          systemImage: "flag")
                }
            }
        }
    }
}
