import Foundation

@MainActor
final class SubscriptionService {
    static let shared = SubscriptionService()
    private init() {}

    func currentPlan() async throws -> SubscriptionPlan {
        // TODO: read from `subscriptions` (RLS: own row).
        return .free
    }

    /// Edge Function: `syncSubscriptionStatus`.
    /// Called after a StoreKit purchase or RevenueCat customer update.
    func syncWithBackend(receiptOrAppUserID: String) async throws {
        // TODO
    }
}
