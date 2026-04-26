import SwiftUI

struct DiscoveryView: View {
    @StateObject private var vm = DiscoveryViewModel()

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {
                    header
                    content
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.refresh() }
            .task { await vm.loadInitial() }
            .sheet(item: $vm.pendingReport) { ctx in
                ReportSheet(
                    targetType: .profile,
                    targetId:   ctx.targetId,
                    onClose:    { vm.pendingReport = nil }
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
                        onReport:  { vm.presentReport(profile) }
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

    var body: some View {
        GACard(kind: .standard, padding: GASpacing.lg) {
            VStack(alignment: .leading, spacing: GASpacing.md) {
                identityRow
                bioRow
                if !profile.tags.isEmpty {
                    tagsBlock
                }
                if !profile.sharedTags.isEmpty {
                    sharedRow
                }
                if let location = profile.location {
                    locationRow(location)
                }
                actionRow
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onReport()
            } label: {
                Label(String(localized: "safety.menu.reportUser"),
                      systemImage: "flag")
            }
        }
    }

    // MARK: -

    private var identityRow: some View {
        HStack(alignment: .top, spacing: GASpacing.md) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(GATypography.title)
                    .foregroundStyle(GAColors.textPrimary)
                    .lineLimit(2)
                Text("@\(profile.getalongId)")
                    .font(GATypography.caption)
                    .foregroundStyle(GAColors.textTertiary)
            }
            Spacer(minLength: 0)
            menuButton
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
        let words = profile.displayName.split(separator: " ").prefix(2)
        let r = words.compactMap { $0.first.map(String.init) }.joined().uppercased()
        if !r.isEmpty { return r }
        return profile.getalongId.prefix(2).uppercased()
    }

    private var menuButton: some View {
        Menu {
            Button(role: .destructive) {
                onReport()
            } label: {
                Label(String(localized: "safety.menu.reportUser"),
                      systemImage: "flag")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(GAColors.textTertiary)
                .frame(width: 28, height: 28)
        }
        .accessibilityLabel(String(localized: "common.more"))
    }

    @ViewBuilder
    private var bioRow: some View {
        if let bio = profile.bio?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bio.isEmpty {
            Text(bio)
                .font(GATypography.body)
                .foregroundStyle(GAColors.textPrimary)
                .lineSpacing(2)
                .lineLimit(4)
        } else {
            Text("discovery.card.noSignal")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textTertiary)
        }
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

    private func locationRow(_ location: String) -> some View {
        HStack(spacing: GASpacing.xs) {
            Image(systemName: "mappin.and.ellipse")
                .font(GATypography.caption)
                .foregroundStyle(GAColors.textTertiary)
            Text(location)
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textTertiary)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch sendState {
        case .idle:
            GAButton(title: String(localized: "discovery.action.sendSignal"),
                     systemImage: "dot.radiowaves.left.and.right",
                     kind: .primary,
                     size: .compact,
                     action: onSend)
        case .sending:
            GAButton(title: String(localized: "discovery.action.sending"),
                     kind: .primary,
                     size: .compact,
                     isLoading: true,
                     isDisabled: true,
                     action: {})
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
            .padding(.vertical, GASpacing.xs)
        case .failed(let message):
            VStack(alignment: .leading, spacing: GASpacing.xs) {
                Text(message)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.danger)
                    .lineLimit(2)
                GAButton(title: String(localized: "discovery.action.sendSignal"),
                         systemImage: "dot.radiowaves.left.and.right",
                         kind: .primary,
                         size: .compact,
                         action: onSend)
            }
        }
    }
}

#Preview { DiscoveryView() }
