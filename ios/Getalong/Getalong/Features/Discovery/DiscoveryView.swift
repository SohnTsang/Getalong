import SwiftUI

struct DiscoveryView: View {
    @StateObject private var vm = DiscoveryViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GAAppTopBar(trailing: {
                    GATopBarRefreshButton(
                        isBusy: vm.isRefreshing,
                        cooldownRemaining: vm.cooldownRemaining,
                        onTap: { Task { await vm.tryManualRefresh() } }
                    )
                })
                GAScreen(maxWidth: 560) {
                    VStack(alignment: .leading, spacing: GASpacing.sectionGap) {
                        header
                        content
                    }
                }
                .refreshable { await vm.tryManualRefresh() }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task { await vm.loadInitial() }
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
                    displayName: ctx.displayName,
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
                        onBlock:   { vm.presentBlock(profile) }
                    )
                    .onAppear {
                        Task { await vm.loadMoreIfNeeded(currentItem: profile) }
                    }
                }
                loadMoreFooter
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

    @ViewBuilder
    private var loadMoreFooter: some View {
        if let err = vm.loadMoreError {
            HStack(spacing: GASpacing.sm) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(GAColors.danger)
                Text(err)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textSecondary)
                    .lineLimit(2)
                Spacer()
                Button {
                    Task { await vm.loadMore() }
                } label: {
                    Text("discovery.loadMoreRetry")
                        .font(GATypography.footnote.weight(.semibold))
                        .foregroundStyle(GAColors.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(GASpacing.md)
            .background(GAColors.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                        style: .continuous))
        } else if vm.isLoadingMore {
            HStack(spacing: GASpacing.sm) {
                ProgressView().controlSize(.small)
                Text("discovery.loadingMore")
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, GASpacing.md)
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
                    if !profile.tags.isEmpty {
                        tagsBlock
                    }
                    if !profile.sharedTags.isEmpty {
                        sharedRow
                    }
                    stateFooter
                }
            }
            // When the card represents a gendered identity, echo the
            // gender colour as a thin hairline around the card so the
            // badge and the card frame read as a single visual idea.
            .overlay(
                RoundedRectangle(cornerRadius: GACornerRadius.large,
                                 style: .continuous)
                    .strokeBorder(genderTintBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
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

    private var genderTintBorder: Color {
        guard let kind = GenderBadge.Kind.from(rawValue: profile.gender) else {
            return Color.clear
        }
        return kind.tint.opacity(0.30)
    }

    // MARK: -

    /// Headline of the card: gender badge (if visible) + one-line signal.
    /// No avatar, no display name, no @handle, no region — by product
    /// direction. Small ellipsis on the trailing side opens the report
    /// menu.
    private var signalRow: some View {
        HStack(alignment: .top, spacing: GASpacing.sm) {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                if let kind = GenderBadge.Kind.from(rawValue: profile.gender) {
                    GenderBadge(kind: kind)
                }
                signalText
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            menuButton
                .padding(.top, -4)
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

    private var tagsBlock: some View {
        FlowLayout(spacing: GASpacing.sm) {
            ForEach(profile.tags, id: \.self) { tag in
                GAChip(label: tag,
                       kind: profile.sharedTags.contains(tag) ? .selected : .neutral)
            }
        }
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

    /// Quiet footer that telegraphs the per-card invite state.
    /// Idle = nothing rendered (the whole card is the tap target).
    /// Other states show feedback only.
    @ViewBuilder
    private var stateFooter: some View {
        switch sendState {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: GASpacing.sm) {
                ProgressView().controlSize(.small)
                Text("discovery.action.sending")
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textSecondary)
                Spacer()
            }
        case .sent:
            HStack(spacing: GASpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(GAColors.success)
                VStack(alignment: .leading, spacing: 2) {
                    Text("discovery.action.sent")
                        .font(GATypography.bodyEmphasized)
                        .foregroundStyle(GAColors.textPrimary)
                    Text("discovery.signal.liveFor")
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textTertiary)
                }
                Spacer()
            }
        case .failed(let message):
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
}

#Preview { DiscoveryView() }
