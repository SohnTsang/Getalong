import Foundation
import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var tags: [ProfileTag] = []
    @Published var isLoadingTags = false

    func loadTags(for profileId: UUID) async {
        isLoadingTags = true
        defer { isLoadingTags = false }
        do {
            tags = try await ProfileTagService.shared.fetchTags(for: profileId)
        } catch {
            GALog.app.error("loadTags: \(error.localizedDescription)")
        }
    }
}
