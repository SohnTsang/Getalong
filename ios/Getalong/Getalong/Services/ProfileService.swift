import Foundation

@MainActor
final class ProfileService {
    static let shared = ProfileService()
    private init() {}

    func fetchCurrentProfile() async throws -> Profile? {
        // TODO: select * from profiles where id = auth.uid()
        return nil
    }

    func upsertProfile(_ profile: Profile) async throws {
        // TODO
    }

    func setTopics(_ topicIds: [UUID]) async throws {
        // TODO: replace profile_topics rows for current user.
    }
}
