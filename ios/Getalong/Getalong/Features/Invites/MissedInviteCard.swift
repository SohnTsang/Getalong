import SwiftUI

struct MissedInviteCard: View {
    let invite: Invite
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        GACard {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                HStack {
                    Label("Missed", systemImage: "tray")
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textSecondary)
                    Spacer()
                    if let exp = invite.missedExpiresAt {
                        Text("Expires \(exp, format: .relative(presentation: .named))")
                            .font(GATypography.caption)
                            .foregroundStyle(GAColors.textTertiary)
                    }
                }

                if let m = invite.message, !m.isEmpty {
                    Text(m)
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textPrimary)
                } else {
                    Text("They wanted to chat.")
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textSecondary)
                }

                HStack(spacing: GASpacing.md) {
                    GAButton(title: "Decline", kind: .ghost,    size: .compact) { onDecline() }
                    GAButton(title: "Accept",  kind: .primary,  size: .compact) { onAccept() }
                }
                .padding(.top, GASpacing.xs)
            }
        }
    }
}
