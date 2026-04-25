import SwiftUI

struct InvitesView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm = InvitesViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GASpacing.lg) {

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

                    Picker("", selection: $vm.tab) {
                        ForEach(InvitesViewModel.Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch vm.tab {
                    case .live:
                        liveTab
                    case .missed:
                        missedTab
                    }

                    if let err = vm.errorMessage {
                        GAErrorBanner(message: err,
                                      onDismiss: { vm.errorMessage = nil })
                    }

                    DevComposeInviteCard(vm: vm)
                        .padding(.top, GASpacing.lg)
                }
                .padding(.horizontal, GASpacing.lg)
                .padding(.vertical, GASpacing.lg)
            }
            .background(GAColors.background.ignoresSafeArea())
            .navigationTitle("Invites")
            .refreshable { await vm.refresh() }
            .task {
                if let uid = currentUserId {
                    await vm.attach(userId: uid)
                }
            }
            .onDisappear {
                Task { await vm.detach() }
            }
            .alert("Chat created", isPresented: chatCreatedBinding) {
                Button("OK", role: .cancel) { vm.clearLastChat() }
            } message: {
                if let id = vm.lastChatRoomId {
                    Text("Chat room \(id.uuidString.prefix(8))… is ready. Full chat UI is coming next.")
                }
            }
        }
    }

    // MARK: -

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

    @ViewBuilder
    private var liveTab: some View {
        if vm.incomingLive == nil && vm.outgoingLive == nil {
            GAEmptyState(
                title: "No active live invites",
                message: "Live invites last 15 seconds. When one comes in, you'll see it here.",
                systemImage: "bolt.heart"
            )
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var missedTab: some View {
        if vm.missed.isEmpty {
            GAEmptyState(
                title: "No missed invites",
                message: "Invites you didn't catch in time will land here.",
                systemImage: "tray"
            )
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
}

#Preview {
    InvitesView()
        .environmentObject(SessionManager())
}
