import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm = ProfileViewModel()
    @AppStorage("ga.appearance") private var appearanceRaw: String = GAAppearance.system.rawValue

    private var appearance: Binding<GAAppearance> {
        Binding(
            get: { GAAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    private var profile: Profile? {
        if case .authenticated(let p) = session.state { return p }
        return nil
    }

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                if let profile {
                    VStack(alignment: .leading, spacing: GASpacing.sectionGap) {
                        header(profile)
                        signalSection(profile)
                        topicsSection
                        preferencesSection(profile)
                        appearanceSection
                        signOutSection
                    }
                } else {
                    GAEmptyState(title: "No profile loaded",
                                 systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task { if let p = profile { await vm.loadTopics(for: p.id) } }
        }
    }

    // MARK: - Header

    private func header(_ p: Profile) -> some View {
        GACard(kind: .elevated, padding: GASpacing.xl) {
            VStack(alignment: .leading, spacing: GASpacing.lg) {
                HStack(alignment: .top, spacing: GASpacing.lg) {
                    avatar(p)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.displayName)
                            .font(GATypography.title)
                            .foregroundStyle(GAColors.textPrimary)
                        Text("@\(p.getalongId)")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textSecondary)
                    }
                    Spacer()
                }

                if let bio = p.bio, !bio.isEmpty {
                    Text(bio)
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textPrimary)
                        .lineLimit(3)
                }

                HStack(spacing: GASpacing.sm) {
                    GAStatusPill(label: p.plan.displayName,
                                 systemImage: planIcon(p.plan),
                                 tint: planTint(p.plan))
                    if p.trustScore > 0 {
                        GAStatusPill(label: "Trust \(p.trustScore)",
                                     systemImage: "checkmark.seal.fill",
                                     tint: GAColors.success)
                    }
                }
            }
        }
    }

    private func avatar(_ p: Profile) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [GAColors.accentSoft, GAColors.surfaceRaised],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials(for: p))
                .font(GATypography.title.weight(.bold))
                .foregroundStyle(GAColors.accent)
        }
        .frame(width: 64, height: 64)
        .overlay(Circle().strokeBorder(GAColors.border, lineWidth: 1))
    }

    private func initials(for p: Profile) -> String {
        let letters = p.displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let result = letters.joined().uppercased()
        if !result.isEmpty { return result }
        return p.getalongId.prefix(2).uppercased()
    }

    private func planIcon(_ plan: SubscriptionPlan) -> String {
        switch plan { case .gold: return "crown.fill"; case .silver: return "star.fill"; case .free: return "circle" }
    }
    private func planTint(_ plan: SubscriptionPlan) -> Color {
        switch plan {
        case .gold:   return GAColors.warning
        case .silver: return GAColors.secondary
        case .free:   return GAColors.textSecondary
        }
    }

    // MARK: - Sections

    private func signalSection(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: "Your signal",
                            subtitle: "The first thing people see.",
                            actionTitle: "Edit") { /* TODO */ }
            GACard {
                if let bio = p.bio, !bio.isEmpty {
                    Text(bio)
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textPrimary)
                } else {
                    placeholderRow(text: "Add a one-line intro so others know what you're about.",
                                   actionTitle: "Add intro") { /* TODO */ }
                }
            }
        }
    }

    private var topicsSection: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: "Topics",
                            subtitle: "Help people find you.",
                            actionTitle: "Manage") { /* TODO */ }
            GACard {
                if vm.isLoadingTopics {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, GASpacing.sm)
                } else if vm.topics.isEmpty {
                    placeholderRow(text: "Pick a few tags later — music, late-night, books, anything.",
                                   actionTitle: "Add tags") { /* TODO */ }
                } else {
                    FlowLayout(spacing: GASpacing.sm) {
                        ForEach(vm.topics) { GAChip(label: $0.nameEn) }
                    }
                }
            }
        }
    }

    private func preferencesSection(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: "Preferences",
                            actionTitle: "Edit") { /* TODO */ }
            GACard {
                VStack(spacing: 0) {
                    detailRow(label: "Region",
                              value: [p.city, p.country].compactMap { $0 }.joined(separator: ", "))
                    divider
                    detailRow(label: "Language",
                              value: p.languageCodes.first?.uppercased())
                    divider
                    detailRow(label: "I am", value: p.gender?.capitalized)
                    divider
                    detailRow(label: "Visible on profile",
                              value: p.gender == nil ? nil
                                    : (p.genderVisible ? "Yes" : "No"))
                    divider
                    detailRow(label: "I want to see",
                              value: p.interestedInGender?.capitalized)
                }
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: "Appearance")
            GACard {
                Picker("Appearance", selection: appearance) {
                    ForEach(GAAppearance.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var signOutSection: some View {
        VStack(spacing: GASpacing.md) {
            GAButton(title: "Sign out",
                     kind: .ghost) {
                Task { await session.signOut() }
            }
            Button { /* TODO: confirm + delete */ } label: {
                Text("Delete account")
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, GASpacing.sm)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func detailRow(label: String, value: String?) -> some View {
        let isEmpty = (value ?? "").isEmpty
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textSecondary)
            Spacer()
            Text(isEmpty ? "Not set" : value!)
                .font(GATypography.body)
                .foregroundStyle(isEmpty ? GAColors.textTertiary : GAColors.textPrimary)
        }
        .padding(.vertical, GASpacing.sm)
    }

    private var divider: some View {
        Rectangle()
            .fill(GAColors.border)
            .frame(height: 0.75)
    }

    private func placeholderRow(text: String,
                                actionTitle: String,
                                action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: GASpacing.md) {
            Text(text)
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
            Spacer(minLength: GASpacing.sm)
            Button(action: action) {
                Text(actionTitle)
                    .font(GATypography.footnote.weight(.semibold))
                    .foregroundStyle(GAColors.accent)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Simple flow layout (chips wrap)

private struct FlowLayout: Layout {
    var spacing: CGFloat = GASpacing.sm

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, totalH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth { x = 0; y += lineH + spacing; lineH = 0 }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            totalH = y + lineH
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : x, height: totalH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX {
                x = bounds.minX; y += lineH + spacing; lineH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                     proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(SessionManager())
}
