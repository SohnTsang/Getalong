import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var session: SessionManager
    @StateObject private var vm = ProfileViewModel()
    @State private var isTagEditorPresented: Bool = false
    @State private var isBasicsPresented: Bool = false
    @State private var isRegionPresented: Bool = false
    @State private var isPreferencesPresented: Bool = false
    @State private var saveSuccessNote: String?
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
            VStack(spacing: 0) {
                GAAppTopBar()
                GAScreen(maxWidth: 560) {
                if let profile {
                    VStack(alignment: .leading, spacing: GASpacing.sectionGap) {
                        if let note = saveSuccessNote {
                            successNote(note)
                        }
                        signalSection(profile)
                        tagsSection
                        regionSection(profile)
                        preferencesSection(profile)
                        appearanceSection
                        safetySection
                        legalSection
                        signOutSection
                    }
                } else {
                    GAEmptyState(title: String(localized: "profile.empty.title"),
                                 systemImage: "person.crop.circle.badge.questionmark")
                }
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
            .sheet(isPresented: $isBasicsPresented) {
                if let p = profile {
                    EditProfileBasicsSheet(
                        initial: p,
                        onSaved: { updated in
                            session.setAuthenticated(updated)
                            isBasicsPresented = false
                            flashSuccess()
                        },
                        onClose: { isBasicsPresented = false }
                    )
                }
            }
            .sheet(isPresented: $isRegionPresented) {
                if let p = profile {
                    EditRegionSheet(
                        initial: p,
                        onSaved: { updated in
                            session.setAuthenticated(updated)
                            isRegionPresented = false
                            flashSuccess()
                        },
                        onClose: { isRegionPresented = false }
                    )
                }
            }
            .sheet(isPresented: $isPreferencesPresented) {
                if let p = profile {
                    EditPreferencesSheet(
                        initial: p,
                        onSaved: { updated in
                            session.setAuthenticated(updated)
                            isPreferencesPresented = false
                            flashSuccess()
                        },
                        onClose: { isPreferencesPresented = false }
                    )
                }
            }
        }
    }

    // MARK: - Success note

    private func successNote(_ text: String) -> some View {
        HStack(spacing: GASpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GAColors.success)
            Text(text)
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textPrimary)
            Spacer()
            Button { saveSuccessNote = nil } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(GAColors.textTertiary)
            }
        }
        .padding(.horizontal, GASpacing.md)
        .padding(.vertical, GASpacing.sm)
        .background(GAColors.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: GACornerRadius.medium,
                                    style: .continuous))
    }

    private func flashSuccess() {
        saveSuccessNote = String(localized: "profile.edit.success")
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run { saveSuccessNote = nil }
        }
    }

    // MARK: - Sections (tap-the-card opens the editor)

    private func signalSection(_ p: Profile) -> some View {
        Button {
            isBasicsPresented = true
        } label: {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                GASectionHeader(title: String(localized: "profile.yourSignal"),
                                subtitle: String(localized: "profile.yourSignal.subtitle"))
                GACard {
                    if let bio = p.bio, !bio.isEmpty {
                        Text(bio)
                            .font(GATypography.body)
                            .foregroundStyle(GAColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, GASpacing.xs)
                    } else {
                        Text("profile.yourSignal.placeholder")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, GASpacing.xs)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var tagsSection: some View {
        Button {
            isTagEditorPresented = true
        } label: {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                GASectionHeader(title: String(localized: "profile.tags"),
                                subtitle: String(localized: "profile.tags.subtitle"))
                GACard {
                    if vm.isLoadingTags {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .padding(.vertical, GASpacing.sm)
                    } else if vm.tags.isEmpty {
                        Text("profile.tags.empty")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, GASpacing.xs)
                    } else {
                        FlowLayout(spacing: GASpacing.sm) {
                            ForEach(vm.tags) { GAChip(label: $0.tag) }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Region card opens the GPS sheet. We never let the user type a
    /// city/country by hand — region is GPS-derived or empty.
    private func regionSection(_ p: Profile) -> some View {
        Button {
            isRegionPresented = true
        } label: {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                GASectionHeader(title: String(localized: "profile.region.title"))
                GACard {
                    detailRow(label: String(localized: "profile.region.title"),
                              value: regionText(p))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func regionText(_ p: Profile) -> String? {
        let parts = [p.city, p.country].compactMap { value -> String? in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// Single Preferences card grouping gender / visibility / want-to-see.
    /// Tap opens the unified EditPreferencesSheet which keeps each as a
    /// separately spaced sub-card.
    private func preferencesSection(_ p: Profile) -> some View {
        Button {
            isPreferencesPresented = true
        } label: {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                GASectionHeader(title: String(localized: "profile.preferences.title"))
                GACard {
                    VStack(spacing: 0) {
                        detailRow(label: String(localized: "profile.gender.iAm"),
                                  value: p.gender.flatMap { Gender(rawValue: $0)?.localizedLabel })
                        divider
                        detailRow(
                            label: String(localized: "profile.gender.visibleOnDiscover"),
                            value: p.gender == nil ? nil
                                : String(localized: p.genderVisible
                                         ? "profile.gender.yes"
                                         : "profile.gender.no")
                        )
                        divider
                        detailRow(label: String(localized: "profile.gender.wantToSee"),
                                  value: p.interestedInGender.flatMap { InterestedInGender(rawValue: $0)?.localizedLabel })
                    }
                }
            }
        }
        .buttonStyle(.plain)
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

    private var safetySection: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            GASectionHeader(title: String(localized: "profile.safety.title"))
            GACard {
                NavigationLink {
                    BlockedUsersView()
                } label: {
                    HStack {
                        Text("profile.safety.blockedUsers")
                            .font(GATypography.body)
                            .foregroundStyle(GAColors.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(GATypography.caption)
                            .foregroundStyle(GAColors.textTertiary)
                    }
                    .padding(.vertical, GASpacing.sm)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
            .padding(.vertical, GASpacing.md)
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
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, GASpacing.md)
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
