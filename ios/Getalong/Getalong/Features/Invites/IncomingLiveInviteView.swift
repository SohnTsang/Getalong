import SwiftUI

/// Incoming live invite — uses the shared `GALiveInviteCard` and ticks
/// a 100 ms timer anchored to backend `live_expires_at`.
struct IncomingLiveInviteView: View {
    let invite: Invite
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onExpired: () -> Void
    var isBusy: Bool = false
    var onReport: (() -> Void)? = nil

    @State private var secondsLeft: Double = 0
    @State private var firedExpired: Bool = false
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        GALiveInviteCard(
            role: .incoming,
            totalSeconds: 15,
            secondsLeft: secondsLeft,
            senderTitle: String(localized: "signals.live.label"),
            preview: invite.message,
            onAccept: onAccept,
            onDecline: onDecline,
            isBusy: isBusy
        )
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
