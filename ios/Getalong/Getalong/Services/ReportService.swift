import Foundation
import Supabase

enum ReportTargetType: String {
    case profile
    case message
    case media
    case chatRoom = "chat_room"
    case invite
}

/// Canonical report reasons. Keep in sync with REPORT_REASONS in
/// supabase/functions/reportContent/index.ts.
enum ReportReason: String, CaseIterable, Identifiable {
    case harassment
    case sexual
    case hate
    case scam
    case underage
    case selfHarm = "self_harm"
    case other

    var id: String { rawValue }

    var localizedLabel: String {
        switch self {
        case .harassment: return String(localized: "safety.report.reason.harassment")
        case .sexual:     return String(localized: "safety.report.reason.sexual")
        case .hate:       return String(localized: "safety.report.reason.hate")
        case .scam:       return String(localized: "safety.report.reason.scam")
        case .underage:   return String(localized: "safety.report.reason.underage")
        case .selfHarm:   return String(localized: "safety.report.reason.selfHarm")
        case .other:      return String(localized: "safety.report.reason.other")
        }
    }
}

enum SafetyServiceError: LocalizedError, Equatable {
    case authRequired
    case invalidInput
    case targetNotFound
    case notAllowed
    case alreadyReported
    case selfBlockNotAllowed
    case profileNotFound
    case network
    case other

    init(code: String?) {
        switch code {
        case "AUTH_REQUIRED":           self = .authRequired
        case "INVALID_INPUT":           self = .invalidInput
        case "TARGET_NOT_FOUND":        self = .targetNotFound
        case "NOT_ALLOWED":             self = .notAllowed
        case "ALREADY_REPORTED":        self = .alreadyReported
        case "PROFILE_NOT_FOUND":       self = .profileNotFound
        case "SELF_BLOCK_NOT_ALLOWED":  self = .selfBlockNotAllowed
        default:                        self = .other
        }
    }

    var errorDescription: String? {
        switch self {
        case .authRequired:        return String(localized: "error.notSignedIn")
        case .targetNotFound,
             .invalidInput,
             .profileNotFound,
             .notAllowed,
             .other:               return String(localized: "safety.report.error")
        case .alreadyReported:     return String(localized: "safety.report.alreadyReported")
        case .selfBlockNotAllowed: return String(localized: "safety.block.selfError")
        case .network:             return String(localized: "error.network")
        }
    }
}

@MainActor
final class ReportService {
    static let shared = ReportService()
    private init() {}

    // MARK: - Report

    private struct ReportBody: Encodable {
        let target_type: String
        let target_id: UUID
        let reason: String
        let details: String?
    }
    private struct ReportResp: Decodable {
        let id: UUID?
        let alreadyReported: Bool?
        enum CodingKeys: String, CodingKey {
            case id
            case alreadyReported = "already_reported"
        }
    }

    @discardableResult
    func report(targetType: ReportTargetType,
                targetId: UUID,
                reason: ReportReason,
                details: String?) async throws -> Bool {
        let resp: ReportResp = try await invoke(
            "reportContent",
            body: ReportBody(
                target_type: targetType.rawValue,
                target_id:   targetId,
                reason:      reason.rawValue,
                details:     details?.trimmingCharacters(in: .whitespacesAndNewlines)
                    .nilIfEmpty
            )
        )
        return resp.alreadyReported ?? false
    }

    // MARK: - Block

    private struct BlockBody: Encodable {
        let blocked_user_id: UUID
    }
    private struct BlockResp: Decodable {
        let blockedUserId: UUID
        let alreadyBlocked: Bool?
        enum CodingKeys: String, CodingKey {
            case blockedUserId  = "blocked_user_id"
            case alreadyBlocked = "already_blocked"
        }
    }

    @discardableResult
    func blockUser(userId: UUID) async throws -> Bool {
        let resp: BlockResp = try await invoke(
            "blockUser", body: BlockBody(blocked_user_id: userId)
        )
        return resp.alreadyBlocked ?? false
    }

    func unblockUser(userId: UUID) async throws {
        struct Resp: Decodable { let blockedUserId: UUID
            enum CodingKeys: String, CodingKey { case blockedUserId = "blocked_user_id" }
        }
        let _: Resp = try await invoke(
            "unblockUser", body: BlockBody(blocked_user_id: userId)
        )
    }

    // MARK: - Block state (local fetch)

    /// Returns true if the current user has blocked `userId`.
    func hasBlocked(userId: UUID, by: UUID) async -> Bool {
        do {
            let rows: [BlockRow] = try await Supa.client
                .from("blocks")
                .select("blocker_id, blocked_id")
                .eq("blocker_id", value: by)
                .eq("blocked_id", value: userId)
                .limit(1)
                .execute()
                .value
            return !rows.isEmpty
        } catch {
            GALog.app.error("hasBlocked failed: \(error.localizedDescription)")
            return false
        }
    }

    private struct BlockRow: Decodable {
        let blockerId: UUID
        let blockedId: UUID
        enum CodingKeys: String, CodingKey {
            case blockerId = "blocker_id"
            case blockedId = "blocked_id"
        }
    }

    /// Returns the list of profiles the current user has blocked, paired
    /// with the original block timestamp. RLS allows the user to read
    /// their own blocks rows; profile lookups happen via PostgREST.
    func fetchBlockedUsers() async throws -> [BlockedUser] {
        struct Row: Decodable {
            let blockedId: UUID
            let createdAt: Date
            enum CodingKeys: String, CodingKey {
                case blockedId = "blocked_id"
                case createdAt = "created_at"
            }
        }
        let rows: [Row] = try await Supa.client
            .from("blocks")
            .select("blocked_id, created_at")
            .order("created_at", ascending: false)
            .execute()
            .value
        if rows.isEmpty { return [] }

        // Fetch profiles in a single round-trip.
        let ids = rows.map { $0.blockedId }
        let profiles: [Profile] = try await Supa.client
            .from("profiles")
            .select()
            .in("id", values: ids)
            .execute()
            .value
        let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        return rows.map { row in
            BlockedUser(
                userId: row.blockedId,
                blockedAt: row.createdAt,
                profile: byId[row.blockedId]
            )
        }
    }

    // MARK: - Invocation

    private struct EnvelopeOK<T: Decodable>: Decodable { let ok: Bool; let data: T }
    private struct EnvelopeErr: Decodable {
        let ok: Bool
        let error_code: String?
        let message: String?
    }

    private func invoke<TBody: Encodable, TResp: Decodable>(
        _ name: String, body: TBody
    ) async throws -> TResp {
        do {
            let raw: Data = try await Supa.client.functions
                .invoke(name, options: .init(body: body))
            if let env = try? Self.decoder.decode(EnvelopeOK<TResp>.self, from: raw) {
                return env.data
            }
            if let err = try? Self.decoder.decode(EnvelopeErr.self, from: raw) {
                throw SafetyServiceError(code: err.error_code)
            }
            throw SafetyServiceError.other
        } catch let e as SafetyServiceError {
            throw e
        } catch {
            if let data = Self.errorPayload(from: error),
               let err  = try? Self.decoder.decode(EnvelopeErr.self, from: data) {
                throw SafetyServiceError(code: err.error_code)
            }
            GALog.app.error("safety \(name): \(error.localizedDescription)")
            throw SafetyServiceError.network
        }
    }

    private static let decoder = JSONDecoder()

    private static func errorPayload(from error: Error) -> Data? {
        let mirror = Mirror(reflecting: error)
        for child in mirror.children {
            if let nested = Mirror(reflecting: child.value).children
                .first(where: { _ in true })?.value,
               let data = nested as? Data { return data }
            if let data = child.value as? Data { return data }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

struct BlockedUser: Identifiable, Hashable {
    let userId: UUID
    let blockedAt: Date
    let profile: Profile?

    var id: UUID { userId }

    var displayName: String {
        if let name = profile?.displayName, !name.isEmpty { return name }
        if let h = profile?.getalongId, !h.isEmpty { return "@\(h)" }
        return String(localized: "chat.title.fallback")
    }

    var handle: String? {
        guard let h = profile?.getalongId, !h.isEmpty else { return nil }
        return "@\(h)"
    }
}
