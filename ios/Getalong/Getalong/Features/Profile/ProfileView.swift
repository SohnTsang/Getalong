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
            ScrollView {
                VStack(alignment: .leading, spacing: GASpacing.lg) {
                    if let profile {
                        identityCard(profile)
                        introCard(profile)
                        tagsCard
                        regionCard(profile)
                        genderCard(profile)
                        appearanceCard
                        signOutCard
                    } else {
                        GAEmptyState(title: "No profile loaded",
                                     systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
                .padding(GASpacing.lg)
            }
            .background(GAColors.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .task { if let p = profile { await vm.loadTopics(for: p.id) } }
        }
    }

    // MARK: - Cards

    private func identityCard(_ profile: Profile) -> some View {
        GACard {
            VStack(alignment: .leading, spacing: GASpacing.xs) {
                Text(profile.displayName)
                    .font(GATypography.title)
                    .foregroundStyle(GAColors.textPrimary)
                Text("@\(profile.getalongId)")
                    .font(GATypography.callout)
                    .foregroundStyle(GAColors.textSecondary)
                HStack(spacing: GASpacing.sm) {
                    GAChip(label: profile.plan.displayName.uppercased())
                    if profile.trustScore > 0 {
                        GAChip(label: "Trust \(profile.trustScore)")
                    }
                }
                .padding(.top, GASpacing.sm)
            }
        }
    }

    private func introCard(_ profile: Profile) -> some View {
        GACard {
            sectionHeader(title: "One-line intro", actionTitle: "Edit") { }
            if let bio = profile.bio, !bio.isEmpty {
                Text(bio)
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textPrimary)
                    .padding(.top, GASpacing.xs)
            } else {
                placeholderRow("Add a one-line intro so others know what you're about.")
            }
        }
    }

    private var tagsCard: some View {
        GACard {
            sectionHeader(title: "Tags", actionTitle: "Add tags") { /* TODO */ }
            if vm.isLoadingTopics {
                ProgressView().padding(.vertical, GASpacing.sm)
            } else if vm.topics.isEmpty {
                placeholderRow("Pick a few tags later to help people find you.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: GASpacing.sm)],
                          alignment: .leading,
                          spacing: GASpacing.sm) {
                    ForEach(vm.topics) { GAChip(label: $0.nameEn) }
                }
                .padding(.top, GASpacing.sm)
            }
        }
    }

    private func regionCard(_ profile: Profile) -> some View {
        GACard {
            sectionHeader(title: "Region", actionTitle: "Edit") { /* TODO */ }
            VStack(alignment: .leading, spacing: GASpacing.xs) {
                row("City",     value: profile.city)
                row("Country",  value: profile.country)
                row("Language", value: profile.languageCodes.first?.uppercased())
            }
            .padding(.top, GASpacing.xs)
        }
    }

    private func genderCard(_ profile: Profile) -> some View {
        GACard {
            sectionHeader(title: "Gender", actionTitle: "Edit") { /* TODO */ }
            VStack(alignment: .leading, spacing: GASpacing.xs) {
                row("Gender", value: profile.gender)
                row("Visible on profile",
                    value: profile.gender == nil ? nil
                                                 : (profile.genderVisible ? "Yes" : "No"))
            }
            .padding(.top, GASpacing.xs)
        }
    }

    private var appearanceCard: some View {
        GACard {
            sectionHeader(title: "Appearance", actionTitle: nil) { }
            Picker("Appearance", selection: appearance) {
                ForEach(GAAppearance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.top, GASpacing.sm)
        }
    }

    private var signOutCard: some View {
        GAButton(title: "Sign out", kind: .ghost) {
            Task { await session.signOut() }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func sectionHeader(title: String,
                               actionTitle: String?,
                               action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(GATypography.headline)
                .foregroundStyle(GAColors.textPrimary)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(GATypography.footnote)
                    .foregroundStyle(GAColors.accent)
            }
        }
    }

    private func placeholderRow(_ text: String) -> some View {
        Text(text)
            .font(GATypography.callout)
            .foregroundStyle(GAColors.textSecondary)
            .padding(.top, GASpacing.xs)
    }

    @ViewBuilder
    private func row(_ label: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(GATypography.footnote)
                .foregroundStyle(GAColors.textSecondary)
            Spacer()
            Text(value?.isEmpty == false ? value! : "Not set")
                .font(GATypography.body)
                .foregroundStyle(value?.isEmpty == false ? GAColors.textPrimary : GAColors.textTertiary)
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(SessionManager())
}
