import SwiftUI

struct DiscoveryView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm = DiscoveryViewModel()

    private var currentUserId: UUID? {
        if case .authenticated(let p) = session.state { return p.id }
        return nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                GAColors.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    GAAppTopBar(trailing: {
                        GATopBarRefreshButton(
                            isBusy: vm.isRefreshing,
                            cooldownRemaining: vm.cooldownRemaining,
                            onTap: { Task { await vm.tryManualRefresh(source: .manual) } }
                        )
                    })
                    GAScreen(maxWidth: 560) {
                        VStack(alignment: .leading, spacing: GASpacing.sectionGap) {
                            header
                            content
                        }
                    }
                    .refreshable { await vm.tryManualRefresh(source: .pull) }
                }

                // Global warning toast for soft validation errors that
                // do NOT belong inline under a card — currently just
                // "already has an active live invite". Shares the
                // GATopToast surface with the safety success toast.
                if let msg = vm.inviteToast {
                    GATopToast(kind: .warning,
                               message: msg) { vm.inviteToast = nil }
                        .padding(.horizontal, GASpacing.lg)
                        .padding(.top, GASpacing.md)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .animation(.easeOut(duration: 0.2), value: vm.inviteToast)
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.loadInitial() }
            .task(id: currentUserId) {
                if let uid = currentUserId {
                    // Detached so SwiftUI cancelling this .task
                    // doesn't propagate Task.cancel() into the
                    // realtime websocket subscribe.
                    Task { await vm.attach(userId: uid) }
                }
            }
            .onDisappear { vm.detach() }
            .sheet(item: $vm.pendingReport) { ctx in
                ReportSheet(
                    targetType: .profile,
                    targetId:   ctx.targetId,
                    onClose:    { vm.pendingReport = nil }
                )
            }
            .sheet(item: $vm.pendingBlock) { ctx in
                BlockUserSheet(
                    userId: ctx.userId,
                    line:   ctx.line,
                    handle: ctx.handle,
                    onBlocked: { Task { await vm.confirmBlocked(userId: ctx.userId) } },
                    onClose:   { vm.pendingBlock = nil }
                )
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text("discovery.title")
                .font(GATypography.screenTitle)
                .foregroundStyle(GAColors.textPrimary)
            Text("discovery.subtitle")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoadingInitial && vm.profiles.isEmpty {
            skeleton
        } else if vm.profiles.isEmpty {
            GACard {
                GAEmptyState(
                    title: String(localized: "discovery.empty.title"),
                    message: String(localized: "discovery.empty.subtitle"),
                    systemImage: "sparkles"
                )
            }
        } else {
            VStack(spacing: GASpacing.md) {
                ForEach(vm.profiles) { profile in
                    DiscoveryCard(
                        profile: profile,
                        sendState: vm.sendState(for: profile),
                        onSend:    { Task { await vm.sendSignal(to: profile) } },
                        onReport:  { vm.presentReport(profile) },
                        onBlock:   { vm.presentBlock(profile) },
                        onCountdownEnd: { vm.expireSentCard(profile) }
                    )
                }
            }
        }

        if let err = vm.loadError {
            GAErrorBanner(
                message: err,
                onRetry:   { Task { await vm.refresh() } },
                onDismiss: { vm.loadError = nil }
            )
        }
    }

    private var skeleton: some View {
        VStack(spacing: GASpacing.md) {
            ForEach(0..<3, id: \.self) { _ in
                GACard {
                    VStack(alignment: .leading, spacing: GASpacing.sm) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(GAColors.surfaceRaised)
                            .frame(height: 16)
                            .frame(maxWidth: 160)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(GAColors.surfaceRaised.opacity(0.6))
                            .frame(height: 12)
                            .frame(maxWidth: 220)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(GAColors.surfaceRaised.opacity(0.5))
                            .frame(height: 32)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .redacted(reason: .placeholder)
            }
        }
    }
}

// MARK: - Card

private struct DiscoveryCard: View {
    let profile: DiscoveryProfile
    let sendState: DiscoveryViewModel.CardSendState
    let onSend: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void
    /// Fires once when the live-invite countdown ring reaches zero. The
    /// VM uses this to drop the card from the local list — refresh may
    /// bring the same profile back later.
    let onCountdownEnd: () -> Void

    private var isInteractive: Bool {
        switch sendState {
        case .idle, .failed: return true
        case .sending, .sent: return false
        }
    }

    var body: some View {
        Button(action: { if isInteractive { onSend() } }) {
            GACard(kind: .standard, padding: GASpacing.xl) {
                VStack(alignment: .leading, spacing: GASpacing.md) {
                    signalRow
                    if hasFitChips {
                        fitChipsBlock
                    }
                    if !profile.tags.isEmpty {
                        tagsBlock
                    }
                    if !profile.sharedTags.isEmpty {
                        sharedRow
                    }
                    if case .failed(let message) = sendState {
                        failureRow(message)
                    }
                }
            }
            // Card never dims regardless of state — the countdown ring
            // in the corner is the only signal that an invite is live.
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.large,
                                 style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        // Block taps but DO NOT use .disabled — that dims the whole
        // card via opacity. We want the card to stay fully visible
        // even after the invite has been sent.
        .allowsHitTesting(isInteractive)
        .contextMenu {
            Button {
                onReport()
            } label: {
                Label(String(localized: "safety.menu.reportUser"),
                      systemImage: "flag")
            }
            Button(role: .destructive) {
                onBlock()
            } label: {
                Label(String(localized: "safety.menu.blockUser"),
                      systemImage: "hand.raised")
            }
        }
    }

    /// Border picks up the live countdown ring's accent colour the
    /// moment the invite goes out, so the whole card reads as "live".
    /// Idle / sending stay on the quiet gender hairline.
    private var borderColor: Color {
        switch sendState {
        case .sent:
            return GAColors.accent
        case .idle, .sending, .failed:
            guard let kind = GenderBadge.Kind.from(rawValue: profile.gender) else {
                return Color.clear
            }
            return kind.tint.opacity(0.30)
        }
    }

    private var borderWidth: CGFloat {
        switch sendState {
        case .sent: return 0.6
        default:    return 0.25
        }
    }

    // MARK: -

    /// Headline of the card: gender badge (if visible) + one-line signal.
    /// The trailing control flips with state — ellipsis menu when idle,
    /// a small spinner while sending, the live 15-second countdown ring
    /// once the invite has been sent.
    private var signalRow: some View {
        HStack(alignment: .top, spacing: GASpacing.sm) {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                if let kind = GenderBadge.Kind.from(rawValue: profile.gender) {
                    GenderBadge(kind: kind)
                }
                signalText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailingControl
                .padding(.top, -4)
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch sendState {
        case .sent:
            // One-shot countdown — ring runs from 15 to 0, then onCountdownEnd
            // drops the card from the Discover list.
            PulsingCountdownRing(total: 15, size: 36, lineWidth: 2.5,
                                 loops: false,
                                 onComplete: onCountdownEnd)
        case .sending:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        case .idle, .failed:
            menuButton
        }
    }

    @ViewBuilder
    private var signalText: some View {
        if let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bio.isEmpty {
            Text(bio)
                .font(GATypography.bodyEmphasized)
                .foregroundStyle(GAColors.textPrimary)
                .lineSpacing(2)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("discovery.card.noSignal")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textTertiary)
        }
    }

    private var menuButton: some View {
        Menu {
            Button {
                onReport()
            } label: {
                Label(String(localized: "safety.menu.reportUser"),
                      systemImage: "flag")
            }
            Button(role: .destructive) {
                onBlock()
            } label: {
                Label(String(localized: "safety.menu.blockUser"),
                      systemImage: "hand.raised")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GAColors.textTertiary)
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel(String(localized: "common.more"))
    }

    /// Taipei beta fit chips below the hero line. Soft visual weight —
    /// these are context, not filters. Distinct from `tagsBlock` (which
    /// is the user's own free-form profile tags). Renders short labels
    /// so the row stays one line on most devices.
    private var hasFitChips: Bool {
        profile.connectionIntentTyped != nil
            || profile.lifestyleRhythmTyped != nil
            || profile.conversationDomainTyped != nil
    }

    private var fitChipsBlock: some View {
        FlowLayout(spacing: GASpacing.sm) {
            if let intent = profile.connectionIntentTyped {
                fitChip(label: intent.localizedShort, kind: .intent)
            }
            if let rhythm = profile.lifestyleRhythmTyped {
                fitChip(label: rhythm.localizedShort, kind: .rhythm)
            }
            if let domain = profile.conversationDomainTyped {
                fitChip(label: domain.localizedShort, kind: .domain)
            }
        }
    }

    /// Each conversation-fit chip carries its own warm pastel palette
    /// (coral / green / wheat) so the three categories are
    /// distinguishable at a glance without needing labels. Colors are
    /// the designer-supplied fit-chip tokens on `GAColors`.
    private enum FitChipKind {
        case intent, rhythm, domain
        var textColor: Color {
            switch self {
            case .intent: return GAColors.fitIntentText
            case .rhythm: return GAColors.fitRhythmText
            case .domain: return GAColors.fitDomainText
            }
        }
        var backgroundColor: Color {
            switch self {
            case .intent: return GAColors.fitIntentBg
            case .rhythm: return GAColors.fitRhythmBg
            case .domain: return GAColors.fitDomainBg
            }
        }
    }

    private func fitChip(label: String, kind: FitChipKind) -> some View {
        Text(label)
            .font(GATypography.footnote.weight(.medium))
            .foregroundStyle(kind.textColor)
            .padding(.horizontal, GASpacing.sm)
            .padding(.vertical, 6)
            .background(kind.backgroundColor, in: Capsule())
    }

    /// Taipei beta: tags read as simple plain hashtags below the fit
    /// chips so the chips stay the only badge-style row on the card.
    /// One Text run wraps naturally; shared tags are subtly tinted with
    /// the accent so they still feel like a quiet "in common" signal
    /// without competing visually with the chips.
    private var tagsBlock: some View {
        Text(taggedHashtagAttributedString)
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var taggedHashtagAttributedString: AttributedString {
        var out = AttributedString()
        for (idx, tag) in profile.tags.enumerated() {
            var piece = AttributedString("#\(tag)")
            if profile.sharedTags.contains(tag) {
                piece.foregroundColor = GAColors.accent
            }
            if idx > 0 {
                out += AttributedString(" ")
            }
            out += piece
        }
        return out
    }

    private var sharedRow: some View {
        HStack(spacing: GASpacing.xs) {
            Image(systemName: "sparkles")
                .font(GATypography.caption)
                .foregroundStyle(GAColors.accent)
            Text(String(localized: "discovery.card.sameWavelength")
                 + ": " + profile.sharedTags.joined(separator: ", "))
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textSecondary)
                .lineLimit(2)
        }
    }

    /// Inline error row shown only on failed sends. Sending and sent
    /// states have no footer at all — the trailing control (spinner /
    /// countdown ring) is the only visual feedback.
    private func failureRow(_ message: String) -> some View {
        HStack(spacing: GASpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(GATypography.caption)
                .foregroundStyle(GAColors.danger)
            Text(message)
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.danger)
                .lineLimit(2)
            Spacer()
        }
    }
}

#Preview { DiscoveryView() }
