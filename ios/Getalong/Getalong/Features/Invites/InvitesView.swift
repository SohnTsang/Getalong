import SwiftUI

struct InvitesView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm = InvitesViewModel()

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {

                    header

                    if let invite = vm.incomingLive {
                        IncomingLiveInviteView(
                            invite: invite,
                            onAccept:  { Task { await vm.acceptLive(invite) } },
                            onDecline: { Task { await vm.declineLive(invite) } },
                            onExpired: { Task { await vm.liveCountdownExpired(invite) } }
                        )
                    }

                    if let outgoing = vm.outgoingLive {
                        OutgoingLiveInviteCard(
                            invite: outgoing,
                            onCancel: { Task { await vm.cancelOutgoing(outgoing) } }
                        )
                    }

                    segment

                    switch vm.tab {
                    case .live:   liveTabBody
                    case .missed: missedTabBody
                    }

                    if let err = vm.errorMessage {
                        GAErrorBanner(message: err,
                                      onDismiss: { vm.errorMessage = nil })
                    }

                    DevComposeInviteCard(vm: vm)
                        .padding(.top, GASpacing.lg)
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.refresh() }
            .task {
                if let uid = currentUserId { await vm.attach(userId: uid) }
            }
            .onDisappear { Task { await vm.detach() } }
            .alert("Chat started", isPresented: chatCreatedBinding) {
                Button("OK", role: .cancel) { vm.clearLastChat() }
            } message: {
                if let id = vm.lastChatRoomId {
                    Text("Room \(id.uuidString.prefix(8))… is ready. Full chat is coming next.")
                }
            }
        }
    }

    // MARK: -

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text("Signals")
                .font(GATypography.screenTitle)
                .foregroundStyle(GAColors.textPrimary)
            Text("Live signals are quick, mutual moments. No pressure if it isn't yours.")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
        }
    }

    private var segment: some View {
        Picker("", selection: $vm.tab) {
            ForEach(InvitesViewModel.Tab.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var liveTabBody: some View {
        if vm.incomingLive == nil && vm.outgoingLive == nil {
            GACard(kind: .standard) {
                GAEmptyState(
                    title: "No live signals",
                    message: "When someone clicks with what you said, you'll feel it here.",
                    systemImage: "dot.radiowaves.left.and.right"
                )
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var missedTabBody: some View {
        if vm.missed.isEmpty {
            GACard(kind: .standard) {
                GAEmptyState(
                    title: "No missed signals",
                    message: "If you miss a live signal, it lands here so you can still respond.",
                    systemImage: "tray"
                )
            }
        } else {
            VStack(spacing: GASpacing.md) {
                ForEach(vm.missed) { invite in
                    MissedInviteCard(
                        invite: invite,
                        onAccept:  { Task { await vm.acceptMissed(invite) } },
                        onDecline: { Task { await vm.decline(invite) } }
                    )
                }
            }
        }
    }

    private var currentUserId: UUID? {
        if case .authenticated(let p) = session.state { return p.id }
        return nil
    }

    private var chatCreatedBinding: Binding<Bool> {
        Binding(
            get: { vm.lastChatRoomId != nil },
            set: { if !$0 { vm.clearLastChat() } }
        )
    }
}

#Preview {
    InvitesView().environmentObject(SessionManager())
}
