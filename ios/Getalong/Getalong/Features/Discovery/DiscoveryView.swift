import SwiftUI

struct DiscoveryView: View {
    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {

                    VStack(alignment: .leading, spacing: GASpacing.xs) {
                        Text("Today's voices")
                            .font(GATypography.screenTitle)
                            .foregroundStyle(GAColors.textPrimary)
                        Text("Short notes from people open to a quick chat.")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textSecondary)
                    }

                    HStack(spacing: GASpacing.sm) {
                        GAChip(label: "All", kind: .selected)
                        GAChip(label: "Music")
                        GAChip(label: "Travel")
                        GAChip(label: "Late night")
                    }

                    GACard {
                        GAEmptyState(
                            title: "No posts yet",
                            message: "When people start sharing, you'll see their conversation starters here.",
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
