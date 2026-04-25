import SwiftUI

struct DiscoveryView: View {
    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {

                    VStack(alignment: .leading, spacing: GASpacing.xs) {
                        Text("discovery.title")
                            .font(GATypography.screenTitle)
                            .foregroundStyle(GAColors.textPrimary)
                        Text("discovery.subtitle")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textSecondary)
                    }

                    HStack(spacing: GASpacing.sm) {
                        GAChip(label: String(localized: "discovery.filter.all"), kind: .selected)
                    }

                    GACard {
                        GAEmptyState(
                            title: String(localized: "discovery.empty.title"),
                            message: String(localized: "discovery.empty.subtitle"),
                            systemImage: "bubble.left.and.bubble.right"
                        )
                    }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview { DiscoveryView() }
