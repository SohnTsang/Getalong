import SwiftUI

struct ChatRoomView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm: ChatRoomViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastMessageId: UUID?
    /// First scroll-to-bottom must happen *without* animation so the
    /// view appears already pinned at the latest message — no visible
    /// scroll-from-top animation when opening the room. Subsequent
    /// new-message scrolls keep the smooth ease-out.
    @State private var didInitialScroll: Bool = false

    private static let bottomAnchorId = "ga.chat.bottom-anchor"

    private func pinToBottom(proxy: ScrollViewProxy, animated: Bool? = nil) {
        let useAnimation = animated ?? didInitialScroll
        if useAnimation {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(Self.bottomAnchorId, anchor: .bottom)
        }
        didInitialScroll = true
    }

    init(roomId: UUID, partner: Profile?) {
        _vm = StateObject(wrappedValue: ChatRoomViewModel(roomId: roomId, partner: partner))
    }

    var body: some View {
        ZStack(alignment: .top) {
            GAColors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(GAColors.border)

                messagesScroll

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

            // Top-of-screen toast. Auto-dismisses after 3s; swipe up
            // to dismiss early. Sits in the ZStack overlay so it can
            // float above the header without pushing layout.
            if let err = vm.sendError {
                ChatErrorToast(message: err) { vm.sendError = nil }
                    .padding(.horizontal, GASpacing.lg)
                    .padding(.top, GASpacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.easeOut(duration: 0.22), value: vm.sendError)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let uid = currentUserId { await vm.attach(currentUserId: uid) }
        }
        .onChange(of: scenePhase) { newPhase in
            // When returning to the foreground, refresh block state in
            // case the partner blocked us while we were backgrounded.
            if newPhase == .active {
                Task { await vm.refreshBlockState() }
            }
        }
        .onDisappear { Task { await vm.detach() } }
        // Full-screen preview shown after the user picks media. They
        // see the image, the view-once badge, and a Send button in the
        // bottom-right; tapping Send fires upload + send.
        .sheet(isPresented: composerBinding) {
            if let controller = vm.mediaController {
                MediaPreviewSheet(
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
        // Leave-chat confirmation. Alert (center-aligned modal) rather
        // than a confirmationDialog — the latter slides up from the
        // bottom as an action sheet, which read like "more options"
        // rather than a yes/no decision.
        .alert(
            String(localized: "chat.delete.title"),
            isPresented: $vm.isDeleteConfirmPresented
        ) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "chat.delete.action"),
                   role: .destructive) {
                Task { await vm.confirmDeleteConversation() }
            }
        } message: {
            Text("chat.delete.message")
        }
        .onChange(of: vm.didDelete) { didDelete in
            if didDelete { dismiss() }
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
            get: { vm.isPreviewPresented },
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

            // Identity in chat is the partner's line — no avatar,
            // display name, or handle.
            Text(vm.headerLine)
                .font(GATypography.bodyEmphasized)
                .foregroundStyle(GAColors.textPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

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
            Button(role: .destructive) {
                vm.presentDeleteConfirm()
            } label: {
                Label(String(localized: "chat.delete.action"),
                      systemImage: "rectangle.portrait.and.arrow.right")
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
                } else if vm.messages.isEmpty && vm.pendingMedia.isEmpty {
                    emptyState
                        .padding(.top, GASpacing.xxl)
                } else {
                    LazyVStack(spacing: GASpacing.sm) {
                        ForEach(vm.messages) { message in
                            ChatMessageBubble(
                                message: message,
                                isMine: vm.isMine(message),
                                mediaAsset: vm.mediaAsset(for: message),
                                localThumbnail: vm.localThumbnail(for: message),
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

                        ForEach(vm.pendingMedia) { item in
                            PendingOutgoingMediaBubble(
                                item: item,
                                onRetry:  { vm.retryPendingMedia(item.id) },
                                onRemove: { vm.removePendingMedia(item.id) }
                            )
                            .id(item.id)
                        }

                        // Sentinel anchor at the very bottom of the
                        // scrollable content. Always scrollTo this id
                        // — guaranteed to exist (the last message id
                        // races with LazyVStack rendering), so the
                        // pin-to-bottom never silently no-ops.
                        Color.clear
                            .frame(height: 1)
                            .id(Self.bottomAnchorId)
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
            // Tap anywhere in the message list to dismiss the
            // keyboard. `simultaneousGesture` so taps on bubbles
            // (e.g. opening view-once media) still reach their
            // buttons. `.scrollDismissesKeyboard(.interactively)`
            // lets users drag the keyboard down by scrolling — what
            // every native chat app does.
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            )
            // Whenever the message count, the loading state, or a
            // pending optimistic bubble changes, pin to the sentinel
            // anchor. The first scroll runs without animation so the
            // room opens already at the bottom; subsequent ones use
            // the smooth ease-out.
            .onChange(of: vm.messages.count) { _ in
                pinToBottom(proxy: proxy)
            }
            .onChange(of: vm.isLoadingInitial) { loading in
                if !loading { pinToBottom(proxy: proxy) }
            }
            .onChange(of: vm.pendingMedia.count) { _ in
                pinToBottom(proxy: proxy)
            }
            .onAppear {
                pinToBottom(proxy: proxy, animated: false)
            }
            .task(id: vm.isLoadingInitial) {
                // After the initial fetch resolves, give LazyVStack a
                // tick to render the rows then pin. The first .onAppear
                // can fire before the message rows materialise; this
                // is the belt-and-braces path.
                if !vm.isLoadingInitial {
                    try? await Task.sleep(nanoseconds: 30_000_000)
                    pinToBottom(proxy: proxy, animated: false)
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

// MARK: - Toast

/// Top-of-screen error toast wrapping `GAErrorBanner` with two
/// behaviours we want for in-chat feedback (e.g. the per-room
/// pending-media cap):
///   * auto-dismiss after 3 seconds — long enough to read, short
///     enough to get out of the way,
///   * upward drag gesture to dismiss early.
private struct ChatErrorToast: View {
    let message: String
    let onDismiss: () -> Void

    @State private var dragY: CGFloat = 0

    var body: some View {
        GAErrorBanner(message: message, onDismiss: onDismiss)
            .offset(y: min(dragY, 0))
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        // Track upward translation only — downward
                        // drags shouldn't pull the toast off-screen.
                        dragY = min(v.translation.height, 0)
                    }
                    .onEnded { v in
                        if v.translation.height < -28 {
                            onDismiss()
                        } else {
                            withAnimation(.easeOut(duration: 0.18)) {
                                dragY = 0
                            }
                        }
                    }
            )
            // `.task(id: message)` restarts the timer if a new error
            // string replaces the current one without the view going
            // away — fresh 3 s for the fresh content.
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                onDismiss()
            }
    }
}
