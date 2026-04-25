import Foundation

enum SubscriptionPlan: String, Codable, CaseIterable {
    case free
    case silver
    case gold

    /// Concurrent outgoing live invite slots allowed by this plan.
    var concurrentLiveInviteSlots: Int {
        switch self {
        case .free, .silver: return 1
        case .gold:          return 2
        }
    }

    var displayName: String {
        switch self {
        case .free:   return "Free"
        case .silver: return "Silver"
        case .gold:   return "Gold"
        }
    }
}
