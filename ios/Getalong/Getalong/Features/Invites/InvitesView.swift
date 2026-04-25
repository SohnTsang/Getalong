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
            .alert("Chat created", isPresented: chatCreatedBinding) {
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
            Text("Invites")
                .font(GATypography.screenTitle)
                .foregroundStyle(GAColors.textPrimary)
            Text("Live invites last 15 seconds. Missed ones wait for you.")
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
                    title: "No live invites",
                    message: "When someone sends a 15-second invite, it'll appear here.",
                    systemImage: "bolt.heart"
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
                    title: "No missed invites",
                    message: "Invites you didn't catch in time will land here.",
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
