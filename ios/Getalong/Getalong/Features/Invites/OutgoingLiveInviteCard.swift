import SwiftUI

/// Sender-side status card while a live invite is in flight.
struct OutgoingLiveInviteCard: View {
    let invite: Invite
    let onCancel: () -> Void

    @State private var secondsLeft: Double = 0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GACard {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                HStack {
                    Label("Live invite sent", systemImage: "paperplane.fill")
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.secondary)
                    Spacer()
                    Text("\(max(0, Int(ceil(secondsLeft))))s")
                        .font(GATypography.headline)
                        .monospacedDigit()
                        .foregroundStyle(GAColors.textPrimary)
                }
                ProgressView(value: max(0, min(1, secondsLeft / 15)))
                    .tint(GAColors.secondary)
                Text("Waiting for them to accept…")
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textSecondary)

                HStack {
                    Spacer()
                    GAButton(title: "Cancel", kind: .ghost, size: .compact) { onCancel() }
                }
                .padding(.top, GASpacing.xs)
            }
        }
        .onAppear { secondsLeft = invite.liveExpiresAt.timeIntervalSinceNow }
        .onReceive(timer) { _ in
            secondsLeft = invite.liveExpiresAt.timeIntervalSinceNow
        }
    }
}
