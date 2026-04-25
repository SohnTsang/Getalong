import Foundation

/// User's own gender. Persisted as the lowercase raw value in `profiles.gender`.
/// Optional in the schema — `nil` means "not stated".
enum Gender: String, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }
    /// Raw English label kept for any non-localized callers.
    var label: String {
        switch self {
        case .male:   return "Male"
        case .female: return "Female"
        }
    }
    /// Localized label for UI.
    var localizedLabel: String {
        switch self {
        case .male:   return String(localized: "quickstart.gender.male")
        case .female: return String(localized: "quickstart.gender.female")
        }
    }
}

/// Who the user wants to see in discovery. Persisted in
/// `profiles.interested_in_gender`. Optional — `nil` means "no preference".
enum InterestedInGender: String, CaseIterable, Identifiable {
    case male
    case female
    case everyone

    var id: String { rawValue }
    var label: String {
        switch self {
        case .male:     return "Male"
        case .female:   return "Female"
        case .everyone: return "Everyone"
        }
    }
    var localizedLabel: String {
        switch self {
        case .male:     return String(localized: "quickstart.gender.male")
        case .female:   return String(localized: "quickstart.gender.female")
        case .everyone: return String(localized: "quickstart.gender.everyone")
        }
    }
}
