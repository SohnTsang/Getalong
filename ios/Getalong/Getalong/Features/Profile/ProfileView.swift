import SwiftUI

struct ProfileView: View {
    @AppStorage("ga.appearance") private var appearanceRaw: String = GAAppearance.system.rawValue

    private var appearance: Binding<GAAppearance> {
        Binding(
            get: { GAAppearance(rawValue: appearanceRaw) ?? .system },
            set: { appearanceRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GASpacing.lg) {

                    GACard {
                        VStack(alignment: .leading, spacing: GASpacing.sm) {
                            Text("Your profile")
                                .font(GATypography.headline)
                                .foregroundStyle(GAColors.textPrimary)
                            Text("Sign in to set up your profile, topics, and preferences.")
                                .font(GATypography.callout)
                                .foregroundStyle(GAColors.textSecondary)
                            GAButton(title: "Sign in", size: .compact) { }
                                .padding(.top, GASpacing.sm)
                        }
                    }

                    GACard {
                        VStack(alignment: .leading, spacing: GASpacing.md) {
                            Text("Appearance")
                                .font(GATypography.headline)
                                .foregroundStyle(GAColors.textPrimary)

                            Picker("Appearance", selection: appearance) {
                                ForEach(GAAppearance.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    GACard {
                        VStack(alignment: .leading, spacing: GASpacing.md) {
                            Text("Safety")
                                .font(GATypography.headline)
                            row("Blocked users", systemImage: "hand.raised")
                            row("Reports", systemImage: "flag")
                            row("Delete account", systemImage: "trash", danger: true)
                        }
                    }
                }
                .padding(GASpacing.lg)
            }
            .background(GAColors.background.ignoresSafeArea())
            .navigationTitle("Profile")
        }
    }

    @ViewBuilder
    private func row(_ title: String, systemImage: String, danger: Bool = false) -> some View {
        HStack(spacing: GASpacing.md) {
            Image(systemName: systemImage)
                .foregroundStyle(danger ? GAColors.danger : GAColors.textSecondary)
            Text(title)
                .font(GATypography.body)
                .foregroundStyle(danger ? GAColors.danger : GAColors.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(GAColors.textTertiary)
        }
        .padding(.vertical, GASpacing.xs)
    }
}

#Preview {
    ProfileView()
}
