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
    let mode: Mode
    let isBusy: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void
    let onReport: () -> Void
    /// Only fires for `.live` mode when the 15-second ring reaches 0.
    var onCountdownEnd: (() -> Void)? = nil

    var body: some View {
        Button(action: onAccept) {
            GACard(kind: .standard, padding: GASpacing.xl) {
                VStack(alignment: .leading, spacing: GASpacing.md) {
                    headlineRow
                    if !sender.tags.isEmpty {
                        tagsBlock
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.large,
                                 style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
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
            Image(systemName: "tray.full")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GAColors.textTertiary)
                .frame(width: 36, height: 36)
        }
    }

    private var tagsBlock: some View {
        FlowLayout(spacing: GASpacing.sm) {
            ForEach(sender.tags, id: \.self) { tag in
                GAChip(label: tag, kind: .neutral)
            }
        }
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

/// Small wrapper that drives `PulsingCountdownRing` from the absolute
/// `live_expires_at` timestamp on the invite, so independent cards
/// each tick down at their own rate based on when they were sent —
/// not when the view appeared.
private struct LiveInviteCountdownRing: View {
    let liveExpiresAt: Date
    let onComplete: () -> Void

    @State private var fired = false
    private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var now: Date = Date()

    private var remaining: Double {
        max(0, liveExpiresAt.timeIntervalSince(now))
    }
    private var seconds: Int { Int(ceil(remaining)) }
    private var progress: Double { min(1, max(0, remaining / 15)) }

    var body: some View {
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
        .onAppear { now = Date() }
        .onReceive(timer) { _ in
            now = Date()
            if remaining <= 0 && !fired {
                fired = true
                onComplete()
            }
        }
        .accessibilityHidden(true)
    }
}
