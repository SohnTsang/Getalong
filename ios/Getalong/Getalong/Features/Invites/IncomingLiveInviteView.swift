import SwiftUI

/// Live invite banner with backend-anchored countdown.
struct IncomingLiveInviteView: View {
    let invite: Invite
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onExpired: () -> Void

    @State private var secondsLeft: Double = 0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    private var totalSeconds: Double { 15 }
    private var progress: Double { max(0, min(1, secondsLeft / totalSeconds)) }
    private var displaySeconds: Int { max(0, Int(ceil(secondsLeft))) }

    var body: some View {
        GACard(padding: GASpacing.lg) {
            VStack(alignment: .leading, spacing: GASpacing.md) {
                HStack {
                    Label("Live invite", systemImage: "bolt.heart.fill")
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.accent)
                    Spacer()
                    Text("\(displaySeconds)s")
                        .font(GATypography.headline)
                        .monospacedDigit()
                        .foregroundStyle(GAColors.textPrimary)
                }

                ProgressView(value: progress)
                    .tint(GAColors.accent)

                if let m = invite.message, !m.isEmpty {
                    Text(m)
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textPrimary)
                        .padding(.vertical, GASpacing.xs)
                } else {
                    Text("Someone wants to start a conversation.")
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textSecondary)
                }

                HStack(spacing: GASpacing.md) {
                    GAButton(title: "Decline", kind: .ghost, size: .compact) { onDecline() }
                    GAButton(title: "Accept",  kind: .primary, size: .compact) { onAccept() }
                }
            }
        }
        .onAppear { tick() }
        .onReceive(timer) { _ in tick() }
    }

    private func tick() {
        secondsLeft = invite.liveExpiresAt.timeIntervalSinceNow
        if secondsLeft <= 0 {
            onExpired()
        }
    }
}
