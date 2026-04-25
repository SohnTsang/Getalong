import Foundation

/// User's own gender. Persisted as the lowercase raw value in `profiles.gender`.
/// Optional in the schema — `nil` means "not stated".
enum Gender: String, CaseIterable, Identifiable {
    case male
    case female

    var id: String { rawValue }
    var label: String {
        switch self {
        case .male:   return "Male"
        case .female: return "Female"
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
}
