import SwiftUI

struct OutgoingLiveInviteCard: View {
    let invite: Invite
    let onCancel: () -> Void
    var isBusy: Bool = false

    @State private var secondsLeft: Double = 0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GALiveInviteCard(
            role: .outgoing,
            totalSeconds: 15,
            secondsLeft: secondsLeft,
            senderTitle: String(localized: "signals.outgoing.label"),
            preview: invite.message,
            onCancel: onCancel,
            isBusy: isBusy
        )
        .onAppear { secondsLeft = invite.liveExpiresAt.timeIntervalSinceNow }
        .onReceive(timer) { _ in
            secondsLeft = invite.liveExpiresAt.timeIntervalSinceNow
        }
    }
}
