import SwiftUI

struct ChatRoomView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm: ChatRoomViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var lastMessageId: UUID?

    init(roomId: UUID, partner: Profile?) {
        _vm = StateObject(wrappedValue: ChatRoomViewModel(roomId: roomId, partner: partner))
    }

    var body: some View {
        ZStack {
            GAColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(GAColors.border)

                messagesScroll

                if let err = vm.sendError {
                    GAErrorBanner(message: err,
                                  onDismiss: { vm.sendError = nil })
                        .padding(.horizontal, GASpacing.lg)
                        .padding(.top, GASpacing.sm)
                }

                if vm.hasBlockedPartner {
                    blockedCard
                } else {
                    ChatInputBar(text: $vm.draft,
                                 isSending: vm.isSending,
                                 canSend: vm.canSend,
                                 canAttachMedia: vm.canAttachMedia,
                                 onSend: { Task { await vm.send() } },
                                 onAttachPicked: { src in vm.startMediaPick(src) })
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let uid = currentUserId { await vm.attach(currentUserId: uid) }
        }
        .onDisappear { Task { await vm.detach() } }
        // Composer (selection → preview → upload → send).
        .sheet(isPresented: composerBinding) {
            if let controller = vm.mediaController {
                MediaComposerSheet(
                    controller: controller,
                    onConfirm: { vm.confirmMediaSend() },
                    onClose:   { vm.dismissMediaComposer() }
                )
            }
        }
        // Report sheet (profile / message / media).
        .sheet(item: $vm.pendingReport) { ctx in
            ReportSheet(
                targetType: ctx.targetType,
                targetId:   ctx.targetId,
                onClose:    { vm.pendingReport = nil }
            )
        }
        // Block confirmation.
        .sheet(isPresented: $vm.isBlockConfirmPresented) {
            if let p = vm.partner {
                BlockUserSheet(
                    userId: p.id,
                    displayName: p.displayName,
                    onBlocked: { Task { await vm.confirmedBlock() } },
                    onClose:   { vm.isBlockConfirmPresented = false }
                )
            }
        }
        // Viewer for receiver opening view-once media.
        .fullScreenCover(isPresented: viewerBinding) {
            if let mid = vm.openingMediaId, let mt = vm.openingMessageType {
                MediaViewerSheet(
                    mediaId: mid,
                    messageType: mt,
                    onViewed: { vm.markLocalAssetViewed(mid) },
                    onClose:  { vm.closeMediaViewer() }
                )
            }
        }
    }

    private var blockedCard: some View {
        VStack(spacing: GASpacing.xs) {
            Text("safety.block.blockedState")
                .font(GATypography.bodyEmphasized)
                .foregroundStyle(GAColors.textPrimary)
            Text("safety.block.inputDisabled")
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, GASpacing.lg)
        .padding(.vertical, GASpacing.lg)
        .background(GAColors.surfaceRaised)
        .overlay(
            Rectangle().fill(GAColors.border).frame(height: 0.5),
            alignment: .top
        )
    }

    private var composerBinding: Binding<Bool> {
        Binding(
            get: { vm.mediaController != nil },
            set: { newValue in
                if !newValue { vm.dismissMediaComposer() }
            }
        )
    }

    private var viewerBinding: Binding<Bool> {
        Binding(
            get: { vm.openingMediaId != nil },
            set: { newValue in
                if !newValue { vm.closeMediaViewer() }
            }
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: GASpacing.md) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(GAColors.textPrimary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "common.cancel"))

            avatar
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 0) {
                Text(vm.headerTitle)
                    .font(GATypography.bodyEmphasized)
                    .foregroundStyle(GAColors.textPrimary)
                if let sub = vm.headerSubtitle {
                    Text(sub)
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textTertiary)
                }
            }
            Spacer()
            safetyMenu
        }
        .padding(.horizontal, GASpacing.lg)
        .padding(.vertical, GASpacing.sm)
        .background(GAColors.background)
    }

    private var safetyMenu: some View {
        Menu {
            Button {
                vm.presentReportUser()
            } label: {
                Label(String(localized: "safety.menu.reportUser"),
                      systemImage: "flag")
            }
            if !vm.hasBlockedPartner {
                Button(role: .destructive) {
                    vm.presentBlockConfirm()
                } label: {
                    Label(String(localized: "safety.menu.blockUser"),
                          systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(GAColors.textPrimary)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(String(localized: "common.more"))
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [GAColors.accentSoft, GAColors.surfaceRaised],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials)
                .font(GATypography.caption.weight(.bold))
                .foregroundStyle(GAColors.accent)
        }
        .overlay(Circle().strokeBorder(GAColors.border, lineWidth: 0.75))
    }

    private var initials: String {
        guard let p = vm.partner else { return "?" }
        let words = p.displayName.split(separator: " ").prefix(2)
        let result = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return result.isEmpty ? p.getalongId.prefix(2).uppercased() : result
    }

    // MARK: - Messages

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if vm.isLoadingInitial {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .padding(.top, GASpacing.xxl)
                } else if vm.messages.isEmpty && vm.mediaController == nil {
                    emptyState
                        .padding(.top, GASpacing.xxl)
                } else {
                    LazyVStack(spacing: GASpacing.sm) {
                        ForEach(vm.messages) { message in
                            ChatMessageBubble(
                                message: message,
                                isMine: vm.isMine(message),
                                mediaAsset: vm.mediaAsset(for: message),
                                onTapMedia: vm.isMine(message) ? nil : { vm.openMedia(message) }
                            )
                            .id(message.id)
                            .contextMenu {
                                if !vm.isMine(message) {
                                    if message.messageType == .text {
                                        Button {
                                            vm.presentReportMessage(message)
                                        } label: {
                                            Label(
                                                String(localized: "safety.menu.reportMessage"),
                                                systemImage: "flag")
                                        }
                                    } else if let mid = message.mediaId {
                                        Button {
                                            vm.presentReportMedia(mediaId: mid)
                                        } label: {
                                            Label(
                                                String(localized: "safety.menu.reportMedia"),
                                                systemImage: "flag")
                                        }
                                    }
                                }
                            }
                        }

                        if let controller = vm.mediaController {
                            PendingMediaBubble(
                                controller: controller,
                                onRemove: { vm.dismissMediaComposer() }
                            )
                        }
                    }
                    .padding(.horizontal, GASpacing.lg)
                    .padding(.vertical, GASpacing.lg)
                }

                if let err = vm.loadError {
                    GAErrorBanner(message: err,
                                  onRetry: { Task { await vm.reload() } },
                                  onDismiss: { vm.loadError = nil })
                        .padding(.horizontal, GASpacing.lg)
                }
            }
            .onChange(of: vm.messages.last?.id) { newId in
                guard let id = newId, id != lastMessageId else { return }
                lastMessageId = id
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
            .onAppear {
                if let id = vm.messages.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        GACard {
            GAEmptyState(
                title: String(localized: "chat.empty.title"),
                message: String(localized: "chat.empty.subtitle"),
                systemImage: "bubble.left.and.bubble.right"
            )
        }
        .padding(.horizontal, GASpacing.lg)
    }

    private var currentUserId: UUID? {
        if case .authenticated(let p) = session.state { return p.id }
        return nil
    }
}
