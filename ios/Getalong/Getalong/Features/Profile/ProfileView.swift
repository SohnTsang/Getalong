import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm = ProfileViewModel()
    @State private var isTagEditorPresented: Bool = false
    @State private var isDeleteConfirmPresented: Bool = false
    @State private var isDeleting: Bool = false
    @State private var deleteError: String?
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
                        tagsSection
                        preferencesSection(profile)
                        appearanceSection
                        legalSection
                        signOutSection
                    }
                } else {
                    GAEmptyState(title: String(localized: "profile.empty.title"),
                                 systemImage: "person.crop.circle.badge.questionmark")
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .task { if let p = profile { await vm.loadTags(for: p.id) } }
            .sheet(isPresented: $isTagEditorPresented) {
                if let p = profile {
                    TagEditorSheet(profileId: p.id,
                                   initialTags: vm.tags) { updated in
                        vm.tags = updated
                    }
                }
            }
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
                        GAStatusPill(label: String(format: NSLocalizedString("profile.trust %lld", comment: ""), p.trustScore),
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
            GASectionHeader(title: String(localized: "profile.yourSignal"),
                            subtitle: String(localized: "profile.yourSignal.subtitle"),
                            actionTitle: String(localized: "common.edit")) { /* TODO */ }
            GACard {
                if let bio = p.bio, !bio.isEmpty {
                    Text(bio)
                        .font(GATypography.body)
                        .foregroundStyle(GAColors.textPrimary)
                } else {
                    placeholderRow(text: String(localized: "profile.yourSignal.placeholder"),
                                   actionTitle: String(localized: "profile.yourSignal.add")) { /* TODO */ }
                }
            }
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: String(localized: "profile.tags"),
                            subtitle: String(localized: "profile.tags.subtitle"),
                            actionTitle: String(localized: vm.tags.isEmpty
                                                 ? "profile.tags.add"
                                                 : "profile.tags.edit")) {
                isTagEditorPresented = true
            }
            GACard {
                if vm.isLoadingTags {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .padding(.vertical, GASpacing.sm)
                } else if vm.tags.isEmpty {
                    placeholderRow(text: String(localized: "profile.tags.empty"),
                                   actionTitle: String(localized: "profile.tags.add")) {
                        isTagEditorPresented = true
                    }
                } else {
                    FlowLayout(spacing: GASpacing.sm) {
                        ForEach(vm.tags) { GAChip(label: $0.tag) }
                    }
                }
            }
        }
    }

    private func preferencesSection(_ p: Profile) -> some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: String(localized: "profile.preferences"),
                            actionTitle: String(localized: "common.edit")) { /* TODO */ }
            GACard {
                VStack(spacing: 0) {
                    detailRow(label: String(localized: "profile.region"),
                              value: [p.city, p.country].compactMap { $0 }.joined(separator: ", "))
                    divider
                    detailRow(label: String(localized: "profile.language"),
                              value: p.languageCodes.first?.uppercased())
                    divider
                    detailRow(label: String(localized: "profile.gender.iAm"),
                              value: p.gender.flatMap { Gender(rawValue: $0)?.localizedLabel })
                    divider
                    detailRow(label: String(localized: "profile.gender.visible"),
                              value: p.gender == nil ? nil
                                    : String(localized: p.genderVisible ? "profile.gender.yes" : "profile.gender.no"))
                    divider
                    detailRow(label: String(localized: "profile.gender.wantToSee"),
                              value: p.interestedInGender.flatMap { InterestedInGender(rawValue: $0)?.localizedLabel })
                }
            }
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: String(localized: "profile.appearance"))
            GACard {
                Picker("profile.appearance", selection: appearance) {
                    ForEach(GAAppearance.allCases) { mode in
                        Text(mode.localizedLabel).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var legalSection: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: String(localized: "profile.legal"))
            GACard {
                VStack(spacing: 0) {
                    legalRow(label: String(localized: "profile.legal.privacy"),
                             url: LegalLinks.privacy)
                    divider
                    legalRow(label: String(localized: "profile.legal.terms"),
                             url: LegalLinks.terms)
                    divider
                    legalRow(label: String(localized: "profile.legal.support"),
                             url: LegalLinks.support)
                }
            }
        }
    }

    private func legalRow(label: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(label)
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(GATypography.caption)
                    .foregroundStyle(GAColors.textTertiary)
            }
            .padding(.vertical, GASpacing.sm)
        }
        .buttonStyle(.plain)
    }

    private var signOutSection: some View {
        VStack(spacing: GASpacing.md) {
            if let err = deleteError {
                GAErrorBanner(message: err, onDismiss: { deleteError = nil })
            }
            GAButton(title: String(localized: "profile.signOut"),
                     kind: .ghost,
                     isDisabled: isDeleting) {
                Task { await session.signOut() }
            }
            Button { isDeleteConfirmPresented = true } label: {
                Text("profile.deleteAccount")
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.textTertiary)
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .padding(.top, GASpacing.sm)
        .confirmationDialog(
            String(localized: "profile.deleteAccount.confirm.title"),
            isPresented: $isDeleteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button(String(localized: "profile.deleteAccount.confirm.action"),
                   role: .destructive) {
                Task { await performDelete() }
            }
            Button(String(localized: "common.cancel"), role: .cancel) {}
        } message: {
            Text("profile.deleteAccount.confirm.message")
        }
    }

    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await AuthService.shared.deleteAccount()
        } catch {
            deleteError = String(localized: "profile.deleteAccount.error")
            Haptics.error()
        }
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
            Text(isEmpty ? String(localized: "profile.gender.notSet") : value!)
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

struct FlowLayout: Layout {
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
