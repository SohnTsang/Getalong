import SwiftUI

struct InvitesView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm = InvitesViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                GAColors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    GAAppTopBar()
                    GAScreen(maxWidth: 560) {
                        VStack(alignment: .leading, spacing: GASpacing.sectionGap) {
                            header
                            segment

                            switch vm.tab {
                            case .live:   liveTabBody
                            case .missed: missedTabBody
                            }

                            if let err = vm.errorMessage {
                                GAErrorBanner(message: err,
                                              onDismiss: { vm.errorMessage = nil })
                            }
                        }
                    }
                    .refreshable { await vm.refresh() }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
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

    /// Live tab: every incoming live-pending invite renders as its own
    /// 1-line user card with its own 15-second countdown. When a card
    /// hits 0 it drops from this list (the VM marks it missed; it'll
    /// reappear on the Missed tab).
    @ViewBuilder
    private var liveTabBody: some View {
        if vm.incomingLive.isEmpty {
            GACard(kind: .standard) {
                GAEmptyState(
                    title: String(localized: "signals.live.empty.title"),
                    message: String(localized: "signals.live.empty.subtitle"),
                    systemImage: "dot.radiowaves.left.and.right"
                )
            }
        } else {
            VStack(spacing: GASpacing.md) {
                ForEach(vm.incomingLive) { item in
                    InviteUserCard(
                        invite: item.invite,
                        sender: item.sender,
                        mode:   .live(liveExpiresAt: item.invite.liveExpiresAt),
                        isBusy: vm.processingInviteId == item.invite.id,
                        onAccept:  { Task { await vm.acceptLive(item.invite) } },
                        onDecline: { Task { await vm.declineLive(item.invite) } },
                        onReport:  { vm.presentReportInvite(item.invite) },
                        onCountdownEnd: {
                            Task { await vm.liveCountdownExpired(item) }
                        }
                    )
                }
            }
        }
    }

    /// Missed tab: invites the user didn't catch in 15s. Same card style,
    /// no timer; a single Accept button (server enforces the daily/plan
    /// missed-accept limit). Long-press for report or decline.
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
                ForEach(vm.missed) { item in
                    VStack(alignment: .leading, spacing: GASpacing.sm) {
                        InviteUserCard(
                            invite: item.invite,
                            sender: item.sender,
                            mode:   .missed,
                            isBusy: vm.processingInviteId == item.invite.id,
                            onAccept:  { Task { await vm.acceptMissed(item.invite) } },
                            onDecline: { Task { await vm.decline(item.invite) } },
                            onReport:  { vm.presentReportInvite(item.invite) }
                        )
                        HStack(spacing: GASpacing.sm) {
                            GAButton(title: String(localized: "signals.decline.notNow"),
                                     kind: .ghost, size: .compact,
                                     isDisabled: vm.processingInviteId == item.invite.id) {
                                Task { await vm.decline(item.invite) }
                            }
                            GAButton(title: String(localized: "signals.accept.start"),
                                     kind: .primary, size: .compact,
                                     isLoading: vm.processingInviteId == item.invite.id,
                                     isDisabled: vm.processingInviteId == item.invite.id) {
                                Task { await vm.acceptMissed(item.invite) }
                            }
                        }
                    }
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
