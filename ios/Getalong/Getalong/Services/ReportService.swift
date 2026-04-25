import Foundation

enum ReportTargetType: String {
    case profile
    case post
    case message
    case media
}

@MainActor
final class ReportService {
    static let shared = ReportService()
    private init() {}

    /// Edge Function: `reportContent`.
    func report(targetType: ReportTargetType,
                targetId: UUID,
                reason: String,
                details: String? = nil) async throws {
        // TODO
    }

    /// Edge Function: `blockUser`.
    func blockUser(userId: UUID) async throws {
        // TODO
    }

    func unblockUser(userId: UUID) async throws {
        // Direct delete via RLS (auth.uid() = blocker_id).
        // TODO
    }
}
