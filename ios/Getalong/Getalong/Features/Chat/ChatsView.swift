import SwiftUI

struct ChatsView: View {
    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 560) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {

                    VStack(alignment: .leading, spacing: GASpacing.xs) {
                        Text("Chats")
                            .font(GATypography.screenTitle)
                            .foregroundStyle(GAColors.textPrimary)
                        Text("Private one-to-one conversations.")
                            .font(GATypography.callout)
                            .foregroundStyle(GAColors.textSecondary)
                    }

                    GACard {
                        GAEmptyState(
                            title: "No chats yet",
                            message: "Accept a live or missed invite to start a conversation.",
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
