import Foundation
import Supabase

/// One profile card returned by `getDiscoveryFeed`. Only fields that are
/// safe to display in the Discover tab are surfaced here. The Edge
/// Function is responsible for never returning email or auth metadata.
struct DiscoveryProfile: Identifiable, Hashable, Decodable {
    let id: UUID
    let getalongId: String
    let displayName: String
    let bio: String?
    let city: String?
    let country: String?
    let gender: String?
    let plan: String
    let tags: [String]
    let sharedTags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case getalongId  = "getalong_id"
        case displayName = "display_name"
        case bio
        case city
        case country
        case gender
        case plan
        case tags
        case sharedTags  = "shared_tags"
    }

    var location: String? {
        let parts = [city, country].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct DiscoveryFeedResponse: Decodable {
    let items: [DiscoveryProfile]
    let nextCursor: String?
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
        case hasMore    = "has_more"
    }
}

enum DiscoveryServiceError: LocalizedError {
    case authRequired
    case loadFailed
    case other

    init(code: String?) {
        switch code {
        case "AUTH_REQUIRED": self = .authRequired
        default:              self = .other
        }
    }

    var errorDescription: String? {
        switch self {
        case .authRequired: return String(localized: "error.notSignedIn")
        case .loadFailed,
             .other:        return String(localized: "discovery.error.loadFailed")
        }
    }
}

@MainActor
final class DiscoveryService {
    static let shared = DiscoveryService()
    private init() {}

    private struct RequestBody: Encodable {
        let tags: [String]?
        let limit: Int
        let cursor: String?
    }

    private struct EnvelopeOK<T: Decodable>: Decodable { let ok: Bool; let data: T }
    private struct EnvelopeErr: Decodable {
        let ok: Bool; let error_code: String?; let message: String?
    }

    /// Fetch a page of Discovery profiles. `cursor` is the opaque value
    /// returned by a previous call.
    func fetchFeed(cursor: String? = nil,
                   limit: Int = 20,
                   tags: [String]? = nil) async throws -> DiscoveryFeedResponse {
        let body = RequestBody(tags: tags, limit: limit, cursor: cursor)
        GALog.discovery.info("fetchFeed cursor=\(cursor ?? "-") limit=\(limit)")
        do {
            let raw = try await Supa.invokeRaw("getDiscoveryFeed", body: body)
            if let env = try? JSONDecoder().decode(
                EnvelopeOK<DiscoveryFeedResponse>.self, from: raw) {
                GALog.discovery.info("fetchFeed ok items=\(env.data.items.count) hasMore=\(env.data.hasMore)")
                return env.data
            }
            if let err = try? JSONDecoder().decode(EnvelopeErr.self, from: raw) {
                GALog.discovery.error("server error code=\(err.error_code ?? "-") message=\(err.message ?? "-")")
                throw DiscoveryServiceError(code: err.error_code)
            }
            GALog.discovery.error("undecodable response: \(String(data: raw, encoding: .utf8) ?? "-")")
            throw DiscoveryServiceError.loadFailed
        } catch let e as DiscoveryServiceError {
            throw e
        } catch {
            if let data = Supa.errorBody(from: error) {
                if let err = try? JSONDecoder().decode(EnvelopeErr.self, from: data) {
                    GALog.discovery.error("http error code=\(err.error_code ?? "-") message=\(err.message ?? "-")")
                    throw DiscoveryServiceError(code: err.error_code)
                }
                let preview = String(data: data, encoding: .utf8)?.prefix(400) ?? "-"
                GALog.discovery.error("http error body: \(preview)")
            }
            GALog.discovery.error("transport: \(error.localizedDescription) [\((error as NSError).domain) #\((error as NSError).code)]")
            throw DiscoveryServiceError.loadFailed
        }
    }
}
