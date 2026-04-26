import SwiftUI

struct ChatsView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm = ChatsViewModel()
    @State private var openedRoomId: UUID?

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {

                    header

                    if vm.isLoading && vm.rows.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 80)
                    } else if vm.rows.isEmpty {
                        GACard {
                            GAEmptyState(
                                title: String(localized: "chats.empty.title"),
                                message: String(localized: "chats.empty.subtitle"),
                                systemImage: "ellipsis.message"
                            )
                        }
                    } else {
                        VStack(spacing: GASpacing.md) {
                            ForEach(vm.rows) { row in
                                NavigationLink {
                                    ChatRoomView(roomId: row.id,
                                                 partner: row.partner)
                                } label: {
                                    ChatRowView(row: row, currentUserId: currentUserId)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let err = vm.errorMessage {
                        GAErrorBanner(message: err,
                                      onDismiss: { vm.errorMessage = nil })
                    }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.refresh() }
            .task {
                if let uid = currentUserId { await vm.attach(userId: uid) }
            }
            .onAppear {
                Task { await vm.refresh() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text("chats.title")
                .font(GATypography.screenTitle)
                .foregroundStyle(GAColors.textPrimary)
            Text("chats.subtitle")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
        }
    }

    private var currentUserId: UUID? {
        if case .authenticated(let p) = session.state { return p.id }
        return nil
    }
}

// MARK: - Row

private struct ChatRowView: View {
    let row: ChatRow
    let currentUserId: UUID?

    var body: some View {
        GACard(kind: .interactive, padding: GASpacing.lg) {
            HStack(alignment: .center, spacing: GASpacing.md) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.partnerDisplayName ?? String(localized: "chat.title.fallback"))
                            .font(GATypography.bodyEmphasized)
                            .foregroundStyle(GAColors.textPrimary)
                        if let handle = row.partnerHandle {
                            Text(handle)
                                .font(GATypography.caption)
                                .foregroundStyle(GAColors.textTertiary)
                        }
                        Spacer()
                        if let when = row.lastMessage?.createdAt ?? row.room.lastMessageAt {
                            Text(when.formatted(.relative(presentation: .numeric)))
                                .font(GATypography.caption)
                                .foregroundStyle(GAColors.textTertiary)
                        }
                    }
                    if let preview = lastMessagePreview {
                        Text(preview.text)
                            .font(GATypography.callout)
                            .foregroundStyle(preview.isPlaceholder
                                ? GAColors.textTertiary
                                : GAColors.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("chats.row.noMessage")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textTertiary)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(GAColors.textTertiary)
            }
        }
    }

    /// Builds a one-line preview for the chat list row. Media messages
    /// never include a thumbnail or media bytes — only a localized label.
    private var lastMessagePreview: (text: String, isPlaceholder: Bool)? {
        guard let m = row.lastMessage else { return nil }
        switch m.messageType {
        case .text, .system:
            if let body = m.body, !body.isEmpty {
                return (body, false)
            }
            return nil
        case .image:
            return (String(localized: "chats.row.media.photo"), true)
        case .gif:
            return (String(localized: "chats.row.media.gif"),   true)
        case .video:
            return (String(localized: "chats.row.media.video"), true)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [GAColors.accentSoft, GAColors.surfaceRaised],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials)
                .font(GATypography.bodyEmphasized)
                .foregroundStyle(GAColors.accent)
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(GAColors.border, lineWidth: 0.75))
    }

    private var initials: String {
        guard let p = row.partner else { return "?" }
        let words = p.displayName.split(separator: " ").prefix(2)
        let result = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        if !result.isEmpty { return result }
        return p.getalongId.prefix(2).uppercased()
    }
}

#Preview {
    ChatsView().environmentObject(SessionManager())
}
