import SwiftUI

/// Incoming live invite — uses the shared `GALiveInviteCard` and ticks
/// a 100 ms timer anchored to backend `live_expires_at`.
struct IncomingLiveInviteView: View {
    let invite: Invite
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onExpired: () -> Void

    @State private var secondsLeft: Double = 0
    @State private var firedExpired: Bool = false
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GALiveInviteCard(
            role: .incoming,
            totalSeconds: 15,
            secondsLeft: secondsLeft,
            senderTitle: "Live invite",
            preview: invite.message,
            onAccept: onAccept,
            onDecline: onDecline
        )
        .onAppear { tick() }
        .onReceive(timer) { _ in tick() }
    }

    private func tick() {
        secondsLeft = invite.liveExpiresAt.timeIntervalSinceNow
        if secondsLeft <= 0 && !firedExpired {
            firedExpired = true
            onExpired()
        }
    }
}
