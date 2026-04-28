import SwiftUI

struct ChatsView: View {
    @EnvironmentObject private var session: SessionManager
    /// Owned by MainTabView so realtime + initial fetch run from the
    /// moment the user signs in, not just when they open this tab.
    @EnvironmentObject private var vm: ChatsViewModel
    @State private var openedRoomId: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                GAColors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    GAAppTopBar()
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
                        atCapBanner
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
            .onAppear {
                Task { await vm.refresh() }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("chats.title")
                    .font(GATypography.screenTitle)
                    .foregroundStyle(GAColors.textPrimary)
                Spacer()
                chatLimitPill
            }
            Text("chats.subtitle")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
        }
    }

    /// "X / 5" pill in the header for Free users — small, calm, and
    /// in the user's peripheral vision so the limit never feels like a
    /// surprise. Gold users (unlimited) get nothing. Pill turns warning-
    /// coloured at the cap so the user knows they need to leave a chat
    /// before accepting another invite.
    @ViewBuilder
    private var chatLimitPill: some View {
        if let limit = chatLimit {
            let count = vm.rows.count
            let atCap = count >= limit
            HStack(spacing: 4) {
                Image(systemName: atCap
                      ? "exclamationmark.circle.fill"
                      : "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(count) / \(limit)")
                    .font(GATypography.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(atCap ? GAColors.danger : GAColors.textSecondary)
            .padding(.horizontal, GASpacing.sm)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(atCap
                          ? GAColors.danger.opacity(0.12)
                          : GAColors.surfaceRaised)
            )
            .overlay(
                Capsule().strokeBorder(
                    atCap ? GAColors.danger.opacity(0.35) : GAColors.border,
                    lineWidth: 0.75
                )
            )
            .accessibilityLabel(atCap
                ? Text("chats.limit.full \(count) \(limit)")
                : Text("chats.limit.usage \(count) \(limit)"))
        }
    }

    /// nil = unlimited (Gold / Silver placeholder). Otherwise = 5 (Free).
    /// Mirrors the server-side `_ga_active_chat_limit` rules in
    /// migration 0015 — keep these in sync.
    private var chatLimit: Int? {
        guard case .authenticated(let p) = session.state else { return nil }
        switch p.plan {
        case .gold, .silver: return nil
        case .free:          return 5
        }
    }

    /// Inline guidance shown only when a Free user is at their cap.
    /// Calm copy — points them at the action they can actually take
    /// (leave a chat) rather than nagging them to upgrade.
    @ViewBuilder
    private var atCapBanner: some View {
        if let limit = chatLimit, vm.rows.count >= limit {
            HStack(alignment: .top, spacing: GASpacing.sm) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(GAColors.danger)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("chats.limit.full.title")
                        .font(GATypography.footnote.weight(.semibold))
                        .foregroundStyle(GAColors.textPrimary)
                    Text("chats.limit.full.message")
                        .font(GATypography.footnote)
                        .foregroundStyle(GAColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(GASpacing.md)
            .background(
                RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                 style: .continuous)
                    .fill(GAColors.danger.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                 style: .continuous)
                    .strokeBorder(GAColors.danger.opacity(0.25), lineWidth: 0.75)
            )
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
            HStack(alignment: .top, spacing: GASpacing.md) {
                avatar

                VStack(alignment: .leading, spacing: GASpacing.xs) {
                    // Identity = the partner's line. No display name,
                    // no handle.
                    Text(partnerLine)
                        .font(GATypography.bodyEmphasized)
                        .foregroundStyle(GAColors.textPrimary)
                        .lineLimit(2)

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
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(lastActivityStamp)
                    .font(GATypography.caption)
                    .foregroundStyle(GAColors.textTertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    /// Circle avatar containing the first letter of the partner's line —
    /// no photos in Getalong, but a coloured monogram still gives the
    /// row a visual anchor.
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [GAColors.accentSoft, GAColors.surfaceRaised],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(avatarInitial)
                .font(GATypography.bodyEmphasized)
                .foregroundStyle(GAColors.accent)
        }
        .frame(width: 40, height: 40)
        .overlay(Circle().strokeBorder(GAColors.border, lineWidth: 0.75))
    }

    /// First character of the partner's line, uppercased. Falls through
    /// to the partner's getalong_id and finally "?" so we never render
    /// a blank avatar.
    private var avatarInitial: String {
        let line = partnerLine.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = line.first, first.isLetter || first.isNumber {
            return String(first).uppercased()
        }
        if let id = row.partner?.getalongId.first {
            return String(id).uppercased()
        }
        return "?"
    }

    /// Bio-only identity. Falls back to a quiet placeholder when the
    /// partner hasn't written one — same fallback the chat header uses.
    private var partnerLine: String {
        if let bio = row.partner?.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bio.isEmpty {
            return bio
        }
        return String(localized: "chat.title.fallback")
    }

    /// Top-right timestamp. Today → `HH:mm`, yesterday → "Yesterday",
    /// inside the past week → weekday name, older → `d/M/yyyy`.
    /// Always renders something — falls back to the room's createdAt
    /// for a brand-new chat that hasn't received its first message yet,
    /// so the row never has an empty trailing column.
    private var lastActivityStamp: String {
        let when = row.lastMessage?.createdAt
            ?? row.room.lastMessageAt
            ?? row.room.createdAt
        let cal = Calendar.current
        if cal.isDateInToday(when) {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "HH:mm"
            return f.string(from: when)
        }
        if cal.isDateInYesterday(when) {
            return String(localized: "chats.row.yesterday")
        }
        if let days = cal.dateComponents([.day],
                                         from: cal.startOfDay(for: when),
                                         to: cal.startOfDay(for: Date())).day,
           days < 7 {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "EEE"
            return f.string(from: when)
        }
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "d/M/yyyy"
        return f.string(from: when)
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

}

#Preview {
    ChatsView().environmentObject(SessionManager())
}
