import SwiftUI

/// Premium live-invite card. Used both for an incoming invite (with
/// Accept/Decline) and an outgoing invite-in-flight (countdown only).
///
/// The card avoids casino/game cues — no gradients, no flashing — and
/// leans on a single calm progress ring around the seconds-left counter.
struct GALiveInviteCard: View {
    enum Role { case incoming, outgoing }

    let role: Role
    let totalSeconds: Double
    let secondsLeft: Double
    let senderTitle: String   // e.g. "@alice" or "Live invite sent"
    let preview: String?      // optional message preview
    var onAccept:  (() -> Void)? = nil
    var onDecline: (() -> Void)? = nil
    var onCancel:  (() -> Void)? = nil

    private var progress: Double { max(0, min(1, secondsLeft / totalSeconds)) }
    private var displaySeconds: Int { max(0, Int(ceil(secondsLeft))) }

    var body: some View {
        VStack(alignment: .leading, spacing: GASpacing.lg) {
            header

            HStack(alignment: .top, spacing: GASpacing.lg) {
                countdownRing
                VStack(alignment: .leading, spacing: GASpacing.xs) {
                    Text(senderTitle)
                        .font(GATypography.bodyEmphasized)
                        .foregroundStyle(GAColors.textPrimary)
                    if let preview, !preview.isEmpty {
                        Text("\u{201C}\(preview)\u{201D}")
                            .font(GATypography.body)
                            .foregroundStyle(GAColors.textSecondary)
                            .lineLimit(3)
                    } else {
                        Text(role == .incoming
                             ? "Sent you a signal."
                             : "Waiting for a response\u{2026}")
                            .font(GATypography.body)
                            .foregroundStyle(GAColors.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }

            actions
        }
        .gaCard(.elevated, padding: GASpacing.xl, radius: GACornerRadius.xlarge)
    }

    // MARK: -

    private var header: some View {
        HStack {
            GAStatusPill(label: role == .incoming ? "Live signal" : "Signal sent",
                         systemImage: "dot.radiowaves.left.and.right",
                         tint: GAColors.inviteLive)
            Spacer()
            Text("\(displaySeconds)s left")
                .font(GATypography.caption)
                .foregroundStyle(GAColors.textSecondary)
        }
    }

    private var countdownRing: some View {
        ZStack {
            Circle()
                .stroke(GAColors.accent.opacity(0.15), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(GAColors.accent,
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
            Text("\(displaySeconds)")
                .font(GATypography.countdown)
                .foregroundStyle(GAColors.textPrimary)
        }
        .frame(width: 84, height: 84)
    }

    @ViewBuilder
    private var actions: some View {
        switch role {
        case .incoming:
            HStack(spacing: GASpacing.md) {
                GAButton(title: "Decline",
                         kind: .ghost,
                         size: .compact) { onDecline?() }
                GAButton(title: "Accept",
                         kind: .primary,
                         size: .compact) { onAccept?() }
            }
        case .outgoing:
            HStack {
                Spacer()
                GAButton(title: "Cancel",
                         kind: .ghost,
                         size: .compact,
                         fillsWidth: false) { onCancel?() }
            }
        }
    }
}
