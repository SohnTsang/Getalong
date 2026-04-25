import SwiftUI

struct MissedInviteCard: View {
    let invite: Invite
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        GACard(kind: .standard, padding: GASpacing.lg) {
            VStack(alignment: .leading, spacing: GASpacing.md) {
                HStack(spacing: GASpacing.sm) {
                    GAStatusPill(label: "Missed",
                                 systemImage: "tray",
                                 tint: GAColors.inviteMissed)
                    Spacer()
                    if let exp = invite.missedExpiresAt {
                        Text("Expires \(exp, format: .relative(presentation: .named))")
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
                    Text("They wanted to chat.")
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textSecondary)
                }

                Text("You can still accept this.")
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textTertiary)

                HStack(spacing: GASpacing.md) {
                    GAButton(title: "Ignore", kind: .ghost, size: .compact) { onDecline() }
                    GAButton(title: "Accept", kind: .primary, size: .compact) { onAccept() }
                }
            }
        }
    }
}
