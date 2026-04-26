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
                            onExpired: { Task { await vm.liveCountdownExpired(invite) } },
                            isBusy: vm.processingInviteId == invite.id,
                            onReport: { vm.presentReportInvite(invite) }
                        )
                    }

                    if let outgoing = vm.outgoingLive {
                        OutgoingLiveInviteCard(
                            invite: outgoing,
                            onCancel: { Task { await vm.cancelOutgoing(outgoing) } },
                            isBusy: vm.processingInviteId == outgoing.id
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
            .sheet(isPresented: chatCreatedBinding) {
                if let id = vm.lastChatRoomId {
                    ConversationStartedSheet(roomId: id) {
                        vm.clearLastChat()
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                }
            }
            .sheet(item: $vm.pendingReport) { ctx in
                ReportSheet(
                    targetType: ctx.targetType,
                    targetId:   ctx.targetId,
                    onClose:    { vm.pendingReport = nil }
                )
            }
        }
    }

    // MARK: -

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text("signals.title")
                .font(GATypography.screenTitle)
                .foregroundStyle(GAColors.textPrimary)
            Text("signals.subtitle")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var segment: some View {
        Picker("", selection: $vm.tab) {
            ForEach(InvitesViewModel.Tab.allCases) { tab in
                Text(tab.localizedTitle).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var liveTabBody: some View {
        if vm.incomingLive == nil && vm.outgoingLive == nil {
            GACard(kind: .standard) {
                GAEmptyState(
                    title: String(localized: "signals.live.empty.title"),
                    message: String(localized: "signals.live.empty.subtitle"),
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
                    title: String(localized: "signals.missed.empty.title"),
                    message: String(localized: "signals.missed.empty.subtitle"),
                    systemImage: "tray"
                )
            }
        } else {
            VStack(spacing: GASpacing.md) {
                ForEach(vm.missed) { invite in
                    MissedInviteCard(
                        invite: invite,
                        onAccept:  { Task { await vm.acceptMissed(invite) } },
                        onDecline: { Task { await vm.decline(invite) } },
                        isBusy: vm.processingInviteId == invite.id,
                        onReport: { vm.presentReportInvite(invite) }
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
