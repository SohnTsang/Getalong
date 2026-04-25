import SwiftUI

struct ChatsView: View {
    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {

                    VStack(alignment: .leading, spacing: GASpacing.xs) {
                        Text("chats.title")
                            .font(GATypography.screenTitle)
                            .foregroundStyle(GAColors.textPrimary)
                        Text("chats.subtitle")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textSecondary)
                    }

                    GACard {
                        GAEmptyState(
                            title: String(localized: "chats.empty.title"),
                            message: String(localized: "chats.empty.subtitle"),
                            systemImage: "ellipsis.message"
                        )
                    }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview { ChatsView() }
