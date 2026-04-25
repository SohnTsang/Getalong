import Foundation

struct DiscoveryFilters: Equatable {
    var topicIds: [UUID] = []
    var city: String? = nil
    var languageCode: String? = nil
}

@MainActor
final class DiscoveryService {
    static let shared = DiscoveryService()
    private init() {}

    /// Calls the `getDiscoveryFeed` Edge Function.
    func fetchFeed(filters: DiscoveryFilters,
                   cursor: String? = nil,
                   limit: Int = 20) async throws -> [Post] {
        // TODO: invoke Edge Function and decode response.
        return []
    }

    func createPost(content: String,
                    topicIds: [UUID],
                    mood: String?) async throws -> Post {
        // Insertion via PostgREST with RLS (post.author_id = auth.uid()).
        // TODO
        throw NSError(domain: "DiscoveryService", code: -1)
    }
}
