import SwiftUI

struct InvitesView: View {
    @State private var tab: Tab = .live

    enum Tab: String, CaseIterable, Identifiable {
        case live = "Live"
        case missed = "Missed"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: GASpacing.lg) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { t in Text(t.rawValue).tag(t) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, GASpacing.lg)
                .padding(.top, GASpacing.lg)

                switch tab {
                case .live:
                    GAEmptyState(
                        title: "No active live invites",
                        message: "When someone sends you a 15-second invite, it'll appear here.",
                        systemImage: "bolt.heart"
                    )
                case .missed:
                    GAEmptyState(
                        title: "No missed invites",
                        message: "Invites you didn't catch in time will land here.",
                        systemImage: "tray"
                    )
                }
                Spacer(minLength: 0)
            }
            .background(GAColors.background.ignoresSafeArea())
            .navigationTitle("Invites")
        }
    }
}

#Preview {
    InvitesView()
}
