import SwiftUI

struct ChatsView: View {
    var body: some View {
        NavigationStack {
            GAEmptyState(
                title: "No chats yet",
                message: "Accept a live invite or a missed invite to start a conversation.",
                systemImage: "ellipsis.message"
            )
            .background(GAColors.background.ignoresSafeArea())
            .navigationTitle("Chats")
        }
    }
}

#Preview {
    ChatsView()
}
