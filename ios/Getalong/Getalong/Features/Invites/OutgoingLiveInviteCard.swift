import SwiftUI

struct OutgoingLiveInviteCard: View {
    let invite: Invite
    let onCancel: () -> Void

    @State private var secondsLeft: Double = 0
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GALiveInviteCard(
            role: .outgoing,
            totalSeconds: 15,
            secondsLeft: secondsLeft,
            senderTitle: "Signal sent",
            preview: invite.message,
            onCancel: onCancel
        )
        .onAppear { secondsLeft = invite.liveExpiresAt.timeIntervalSinceNow }
        .onReceive(timer) { _ in
            secondsLeft = invite.liveExpiresAt.timeIntervalSinceNow
        }
    }
}
