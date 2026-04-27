import SwiftUI

/// Shared top bar for the four main tabs.
///
///   ┌────────────────────────────────────────────┐
///   │ [leading]            ◉                [trailing] │
///   └────────────────────────────────────────────┘
///
/// The Getalong mark sits dead-centre; leading/trailing slots are for
/// per-tab actions (e.g. refresh on Discover, future: notifications).
struct GAAppTopBar<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading:  () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        @ViewBuilder leading:  @escaping () -> Leading  = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }
    ) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        // The bottom hairline is a real sibling rectangle (not an
        // overlay) so adjacent ScrollViews / GAScreen backgrounds in
        // the parent VStack can never paint over it. Otherwise the
        // border would render on Discovery but get clipped by the
        // GAScreen's `ignoresSafeArea()` background on the other tabs.
        VStack(spacing: 0) {
            ZStack {
                HStack {
                    leading()
                    Spacer()
                    trailing()
                }
                // Anchored to the centre regardless of leading/trailing
                // content widths.
                BrandMark()
            }
            .frame(height: 44)
            .padding(.horizontal, GASpacing.lg)

            Rectangle()
                .fill(GAColors.border)
                .frame(height: 1)
        }
        // Paint the top safe area with the page background so the bar
        // and the screen below it read as one continuous surface on
        // every tab.
        .background(GAColors.background.ignoresSafeArea(edges: .top))
    }
}

/// Compact Getalong brand mark — the same concentric-circle "signal
/// dot" used on the auth screen, scaled down for the top bar.
struct BrandMark: View {
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .stroke(GAColors.accent.opacity(0.18), lineWidth: 1)
                .frame(width: size, height: size)
            Circle()
                .stroke(GAColors.accent.opacity(0.32), lineWidth: 3)
                .frame(width: size * 0.65, height: size * 0.65)
            Circle()
                .fill(GAColors.accent)
                .frame(width: size * 0.30, height: size * 0.30)
        }
        .accessibilityLabel("Getalong")
    }
}

/// Convenience: a small refresh button intended for the trailing slot.
/// Disabled while `isBusy` is true OR while `cooldownRemaining` > 0.
struct GATopBarRefreshButton: View {
    var isBusy: Bool
    var cooldownRemaining: TimeInterval
    var onTap: () -> Void

    private var disabled: Bool { isBusy || cooldownRemaining > 0 }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(GAColors.textPrimary)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 32, height: 32)
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
        .accessibilityLabel(String(localized: "discovery.refresh"))
    }
}
