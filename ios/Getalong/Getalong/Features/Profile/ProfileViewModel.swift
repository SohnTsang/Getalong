import Foundation
import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var topics: [Topic] = []
    @Published var isLoadingTopics = false

    func loadTopics(for profileId: UUID) async {
        isLoadingTopics = true
        defer { isLoadingTopics = false }
        do {
            topics = try await TopicService.shared.fetchTopicsForProfile(profileId)
        } catch {
            GALog.app.error("loadTopics: \(error.localizedDescription)")
        }
    }
}
