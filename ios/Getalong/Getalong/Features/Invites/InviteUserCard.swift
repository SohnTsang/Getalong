import SwiftUI

/// A single invite rendered in the Discovery 1-line user card style.
/// Used on the Invites tab for both Live (countdown ring + tap-to-accept)
/// and Missed (Accept button + decline). Tap on an idle Live card sends
/// the accept; the 3-dot menu offers report + decline.
struct InviteUserCard: View {
    enum Mode {
        /// Live, ticking down from 15s. The trailing slot is a one-shot
        /// PulsingCountdownRing that fires `onCountdownEnd` when it hits 0.
        case live(liveExpiresAt: Date)
        /// Missed — no timer; an Accept button replaces the ring.
        case missed
    }

    let invite: Invite
    let sender: InviteSenderSummary
    /// Normalized-tag set for the current user — passed down from
    /// InvitesViewModel so the card can accent the hashtags it shares
    /// with the sender (same shared-wavelength signal Discovery
    /// shows). Empty set is fine: just renders every tag in tertiary
    /// color.
    var myNormalizedTags: Set<String> = []
    let mode: Mode
    let isBusy: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onReport: () -> Void
    /// Optional block action — surfaced from the missed-card overflow
    /// menu. Live cards leave it nil and only show report + decline.
    var onBlock: (() -> Void)? = nil
    /// Only fires for `.live` mode when the 15-second ring reaches 0.
    var onCountdownEnd: (() -> Void)? = nil

    var body: some View {
        contentByMode
            .contextMenu {
                Button {
                    onReport()
                } label: {
                    Label(String(localized: "safety.menu.reportUser"),
                          systemImage: "flag")
                }
                Button(role: .destructive) {
                    onDecline()
                } label: {
                    Label(String(localized: "signals.decline.notNow"),
                          systemImage: "xmark.circle")
                }
            }
    }

    /// Live cards stay tap-to-accept; missed cards use an explicit Accept
    /// button + a 3-dot menu, so the whole card isn't a single accept
    /// hit-target.
    @ViewBuilder
    private var contentByMode: some View {
        switch mode {
        case .live:
            Button(action: onAccept) {
                cardBody
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
        case .missed:
            cardBody
        }
    }

    private var cardBody: some View {
        GACard(kind: .standard, padding: GASpacing.xl) {
            VStack(alignment: .leading, spacing: GASpacing.md) {
                headlineRow
                if hasFitChips {
                    fitChipsBlock
                }
                if !sender.tags.isEmpty {
                    tagsBlock
                }
                if case .missed = mode {
                    HStack(alignment: .center) {
                        receivedTimestamp
                        Spacer()
                        smallAcceptButton
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: GACornerRadius.large,
                             style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
    }

    // MARK: - Conversation-fit chips
    //
    // Mirrors `DiscoveryCard.fitChipsBlock` exactly: each of the three
    // categories carries its own warm pastel palette (coral / sage /
    // wheat) via the existing GAColors.fit* tokens, so the Invite tab
    // reads as the same product surface as Discovery. Soft visual
    // weight — context, not a filter — and any subset of the three may
    // be present.

    private var hasFitChips: Bool {
        sender.connectionIntentTyped != nil
            || sender.lifestyleRhythmTyped != nil
            || sender.conversationDomainTyped != nil
    }

    private var fitChipsBlock: some View {
        FlowLayout(spacing: GASpacing.sm) {
            if let intent = sender.connectionIntentTyped {
                fitChip(label: intent.localizedShort, kind: .intent)
            }
            if let rhythm = sender.lifestyleRhythmTyped {
                fitChip(label: rhythm.localizedShort, kind: .rhythm)
            }
            if let domain = sender.conversationDomainTyped {
                fitChip(label: domain.localizedShort, kind: .domain)
            }
        }
    }

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

    // MARK: -

    private var headlineRow: some View {
        HStack(alignment: .top, spacing: GASpacing.sm) {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                if let kind = GenderBadge.Kind.from(rawValue: sender.visibleGender) {
                    GenderBadge(kind: kind)
                }
                lineText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailingControl
                .padding(.top, -4)
        }
    }

    @ViewBuilder
    private var lineText: some View {
        if let bio = sender.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bio.isEmpty {
            Text(bio)
                .font(GATypography.bodyEmphasized)
                .foregroundStyle(GAColors.textPrimary)
                .lineSpacing(2)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
        } else if let m = invite.message?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !m.isEmpty {
            Text(m)
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

    @ViewBuilder
    private var trailingControl: some View {
        switch mode {
        case .live(let liveExpiresAt):
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 36, height: 36)
            } else {
                LiveInviteCountdownRing(
                    liveExpiresAt: liveExpiresAt,
                    onComplete: { onCountdownEnd?() }
                )
            }
        case .missed:
            missedMenuButton
        }
    }

    /// Bottom-left footer on missed cards: relative receive time. Uses
    /// `RelativeDateTimeFormatter` for fresh values ("1 sec ago",
    /// "5 min ago", "2 weeks ago") and falls back to an absolute date
    /// (e.g. "22/4/2026 14:30") once the row is older than 30 days,
    /// matching common chat-app conventions.
    private var receivedTimestamp: some View {
        Text(receivedRelative)
            .font(GATypography.caption)
            .foregroundStyle(GAColors.textTertiary)
            .monospacedDigit()
            .accessibilityLabel(Text(receivedRelative))
    }

    private var receivedRelative: String {
        let received = invite.createdAt
        let elapsed = -received.timeIntervalSinceNow
        // > 30 days: switch to absolute "d/M/yyyy HH:mm" so years stay
        // unambiguous when the missed list ages out.
        if elapsed > 60 * 60 * 24 * 30 {
            let f = DateFormatter()
            f.locale = Locale.current
            f.dateFormat = "d/M/yyyy HH:mm"
            return f.string(from: received)
        }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale.current
        f.unitsStyle = .short
        return f.localizedString(for: received, relativeTo: Date())
    }

    /// A pill-shaped Accept button sized smaller than GAButton.compact —
    /// missed cards already explain the context, so this only needs to
    /// look like a tappable affordance, not a primary CTA.
    private var smallAcceptButton: some View {
        Button(action: onAccept) {
            HStack(spacing: GASpacing.xs) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(GAColors.accentText)
                }
                Text("signals.accept")
                    .font(GATypography.caption.weight(.semibold))
                    .foregroundStyle(GAColors.accentText)
            }
            .padding(.horizontal, GASpacing.md)
            .padding(.vertical, 6)
            .background(GAColors.accent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(String(localized: "signals.accept"))
    }

    /// 3-dot overflow menu in the top-right of a missed card. Holds the
    /// safety actions and the destructive "Remove invite" (decline).
    private var missedMenuButton: some View {
        Menu {
            Button {
                onReport()
            } label: {
                Label(String(localized: "safety.menu.reportUser"),
                      systemImage: "flag")
            }
            if let onBlock {
                Button(role: .destructive) {
                    onBlock()
                } label: {
                    Label(String(localized: "safety.menu.blockUser"),
                          systemImage: "hand.raised")
                }
            }
            Button(role: .destructive) {
                onDecline()
            } label: {
                Label(String(localized: "signals.missed.remove"),
                      systemImage: "xmark.bin")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GAColors.textTertiary)
                .frame(width: 36, height: 36)
        }
        .accessibilityLabel(String(localized: "common.more"))
        .disabled(isBusy)
    }

    /// Plain `#tag #tag` text run in tertiary footnote — matches the
    /// Discovery card's hashtag treatment so the two cards share the
    /// same visual language. No capsule, no border, no "Tags" label;
    /// the tags wrap naturally as one Text view. Shared hashtags
    /// (those the current user also has, intersected via
    /// `myNormalizedTags`) pick up `GAColors.accent` on just that
    /// token — the same subtle "in common" signal Discovery shows.
    private var tagsBlock: some View {
        Text(senderHashtagAttributedString)
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var senderHashtagAttributedString: AttributedString {
        var out = AttributedString()
        for (idx, tag) in sender.tags.enumerated() {
            if idx > 0 { out += AttributedString(" ") }
            var piece = AttributedString("#\(tag)")
            // Use the same canonical normalize as ProfileTag (and the
            // backend trigger) so a sender's "Coffee" and the
            // caller's "coffee" still match. Falls through to no-
            // accent on any input the normalizer rejects (empty,
            // >30 chars) — those couldn't possibly be in the user's
            // own normalized tag set anyway.
            if let normalized = ProfileTag.normalize(tag),
               myNormalizedTags.contains(normalized) {
                piece.foregroundColor = GAColors.accent
            }
            out += piece
        }
        return out
    }

    // MARK: - Border

    private var borderColor: Color {
        switch mode {
        case .live:
            return GAColors.accent
        case .missed:
            guard let kind = GenderBadge.Kind.from(rawValue: sender.visibleGender) else {
                return Color.clear
            }
            return kind.tint.opacity(0.30)
        }
    }

    private var borderWidth: CGFloat {
        switch mode {
        case .live:   return 0.6
        case .missed: return 0.25
        }
    }
}

/// Drives a per-card 15-second ring from the invite's absolute
/// `live_expires_at`, so independent cards each tick down based on
/// when *their* invite was sent — not when the view appeared.
///
/// Reliability: `TimelineView(.periodic)` is the modern SwiftUI way
/// to schedule a recurring re-render, and a sibling sleep Task
/// guarantees `onComplete` fires exactly once at expiry even if the
/// timeline schedule misses (e.g. the view was off-screen, or the
/// app was suspended past `liveExpiresAt`).
private struct LiveInviteCountdownRing: View {
    let liveExpiresAt: Date
    let onComplete: () -> Void

    @State private var fired = false
    @State private var expiryTask: Task<Void, Never>?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { ctx in
            let remaining = max(0, liveExpiresAt.timeIntervalSince(ctx.date))
            let progress  = min(1, max(0, remaining / 15))
            let seconds   = Int(ceil(remaining))

            ZStack {
                Circle()
                    .stroke(GAColors.border, lineWidth: 2.5)
                    .frame(width: 36, height: 36)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(GAColors.accent,
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 36, height: 36)
                Text("\(seconds)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(GAColors.textPrimary)
            }
            // Belt-and-braces: fire from the timeline as well so a
            // visible card that hits 0 drops immediately.
            .onChange(of: remaining <= 0) { atZero in
                if atZero { fireOnce() }
            }
        }
        .frame(width: 36, height: 36)
        .onAppear {
            // If we appeared past expiry, fire right away.
            if liveExpiresAt.timeIntervalSinceNow <= 0 {
                fireOnce()
                return
            }
            // Schedule a one-shot sleep to expiry. This survives view
            // off-screen states (TimelineView pauses when not visible)
            // and guarantees `onComplete` runs at the correct moment.
            expiryTask?.cancel()
            let delay = liveExpiresAt.timeIntervalSinceNow
            expiryTask = Task { [delay] in
                try? await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
                if Task.isCancelled { return }
                await MainActor.run { fireOnce() }
            }
        }
        .onDisappear { expiryTask?.cancel(); expiryTask = nil }
        .accessibilityHidden(true)
    }

    @MainActor
    private func fireOnce() {
        guard !fired else { return }
        fired = true
        onComplete()
    }
}
