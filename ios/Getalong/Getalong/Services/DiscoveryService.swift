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

enum DiscoveryServiceError: LocalizedError, Equatable {
    case authRequired
    /// The in-flight URLSession task was cancelled (typically because the
    /// SwiftUI view that owned the `Task` disappeared — tab switch, sheet
    /// covered it, a refresh started before the previous one finished).
    /// Callers should treat this as a no-op, not a user-facing failure.
    case cancelled
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
        case .cancelled:    return nil
        case .loadFailed,
             .other:        return String(localized: "discovery.error.loadFailed")
        }
    }

    /// True when the underlying NSError represents an in-flight
    /// URLSession cancellation — which Swift concurrency triggers
    /// whenever the surrounding `Task` is cancelled (e.g. SwiftUI
    /// `.task` tearing down on view disappear).
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorCancelled {
            return true
        }
        if let url = error as? URLError, url.code == .cancelled {
            return true
        }
        return false
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
        let exclude_ids: [String]?
    }

    private struct EnvelopeOK<T: Decodable>: Decodable { let ok: Bool; let data: T }
    private struct EnvelopeErr: Decodable {
        let ok: Bool; let error_code: String?; let message: String?
    }

    /// Fetch a single 10-card Discovery batch. `excludeIds` (typically the
    /// IDs the user is currently looking at) is forwarded so the backend
    /// can prefer fresh candidates on refresh; the server falls back to
    /// repeats if there aren't enough alternatives.
    func fetchFeed(limit: Int = 10,
                   tags: [String]? = nil,
                   excludeIds: [UUID] = []) async throws -> DiscoveryFeedResponse {
        let body = RequestBody(
            tags: tags,
            limit: limit,
            cursor: nil,
            exclude_ids: excludeIds.isEmpty
                ? nil
                : excludeIds.map { $0.uuidString }
        )
        let started = Date()
        let situation = excludeIds.isEmpty ? "fresh-batch" : "refresh-batch"
        GALog.discovery.info(
            "fetchFeed.start situation=\(situation, privacy: .public) limit=\(limit, privacy: .public) tags=\(tags?.count ?? 0, privacy: .public) exclude=\(excludeIds.count, privacy: .public)"
        )
        do {
            let raw = try await Supa.invokeRaw("getDiscoveryFeed", body: body)
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            if let env = try? JSONDecoder().decode(
                EnvelopeOK<DiscoveryFeedResponse>.self, from: raw) {
                if env.data.items.isEmpty {
                    // Expected state — surfaces as the empty card on screen,
                    // not an error. Logged at info so it's easy to spot.
                    GALog.discovery.info(
                        "fetchFeed.ok empty=true reason=no-candidates situation=\(situation, privacy: .public) hasMore=\(env.data.hasMore, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
                    )
                } else {
                    GALog.discovery.info(
                        "fetchFeed.ok items=\(env.data.items.count, privacy: .public) hasMore=\(env.data.hasMore, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
                    )
                }
                return env.data
            }
            if let err = try? JSONDecoder().decode(EnvelopeErr.self, from: raw) {
                GALog.discovery.error(
                    "fetchFeed.fail situation=\(situation, privacy: .public) reason=server-envelope code=\(err.error_code ?? "-", privacy: .public) message=\(err.message ?? "-", privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
                )
                throw DiscoveryServiceError(code: err.error_code)
            }
            let preview = String(data: raw, encoding: .utf8)?.prefix(400) ?? "-"
            GALog.discovery.error(
                "fetchFeed.fail situation=\(situation, privacy: .public) reason=undecodable-response body=\(String(preview), privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
            )
            throw DiscoveryServiceError.loadFailed
        } catch let e as DiscoveryServiceError {
            throw e
        } catch {
            let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
            // 1) URLSession cancelled — the surrounding Task was torn down
            //    (SwiftUI .task disappeared, refresh raced the initial load,
            //    user switched tabs). This is NOT a user-facing failure.
            if DiscoveryServiceError.isCancellation(error) {
                GALog.discovery.info(
                    "fetchFeed.cancelled situation=\(situation, privacy: .public) reason=task-cancelled hint=swiftui-task-disappeared-or-refresh-raced elapsedMs=\(elapsedMs, privacy: .public)"
                )
                throw DiscoveryServiceError.cancelled
            }
            // 2) Edge Function returned non-2xx with our envelope embedded.
            if let data = Supa.errorBody(from: error) {
                if let err = try? JSONDecoder().decode(EnvelopeErr.self, from: data) {
                    GALog.discovery.error(
                        "fetchFeed.fail situation=\(situation, privacy: .public) reason=http-envelope code=\(err.error_code ?? "-", privacy: .public) message=\(err.message ?? "-", privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
                    )
                    throw DiscoveryServiceError(code: err.error_code)
                }
                let preview = String(data: data, encoding: .utf8)?.prefix(400) ?? "-"
                GALog.discovery.error(
                    "fetchFeed.fail situation=\(situation, privacy: .public) reason=http-non-envelope body=\(String(preview), privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
                )
            }
            // 3) Plain transport (no connectivity, DNS, TLS, timeout, etc.)
            let ns = error as NSError
            GALog.discovery.error(
                "fetchFeed.fail situation=\(situation, privacy: .public) reason=transport domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) message=\(error.localizedDescription, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
            )
            throw DiscoveryServiceError.loadFailed
        }
    }
}
