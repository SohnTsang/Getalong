import SwiftUI

struct DiscoveryView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GASpacing.lg) {
                    Text("Today's voices")
                        .font(GATypography.display)
                        .foregroundStyle(GAColors.textPrimary)
                        .padding(.horizontal, GASpacing.lg)

                    HStack(spacing: GASpacing.sm) {
                        GAChip(label: "All", isSelected: true)
                        GAChip(label: "Music")
                        GAChip(label: "Travel")
                        GAChip(label: "Late night")
                    }
                    .padding(.horizontal, GASpacing.lg)

                    GAEmptyState(
                        title: "No posts yet",
                        message: "When people start sharing, you'll see their conversation starters here.",
                        systemImage: "bubble.left.and.bubble.right"
                    )
                    .gaCard()
                    .padding(.horizontal, GASpacing.lg)
                }
                .padding(.vertical, GASpacing.lg)
            }
            .background(GAColors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    DiscoveryView()
}
