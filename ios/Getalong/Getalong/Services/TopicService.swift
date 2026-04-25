import Foundation
import Supabase

@MainActor
final class TopicService {
    static let shared = TopicService()
    private init() {}

    func fetchAll() async throws -> [Topic] {
        try await Supa.client
            .from("topics")
            .select()
            .order("name_en", ascending: true)
            .execute()
            .value
    }

    func fetchTopicsForProfile(_ profileId: UUID) async throws -> [Topic] {
        struct Row: Decodable { let topics: Topic }
        let rows: [Row] = try await Supa.client
            .from("profile_topics")
            .select("topics(*)")
            .eq("profile_id", value: profileId)
            .execute()
            .value
        return rows.map(\.topics)
    }
}
