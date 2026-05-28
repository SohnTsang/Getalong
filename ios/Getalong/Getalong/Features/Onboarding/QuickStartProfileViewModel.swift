import Foundation
import SwiftUI

@MainActor
final class QuickStartProfileViewModel: ObservableObject {

    let userId: UUID

    // MARK: - Existing required state (preserved)

    /// One honest line — the hero identity field. Required.
    @Published var oneLineIntro: String = ""
    /// Required: user must pick.
    @Published var gender: Gender? = nil
    /// Required: user must pick.
    @Published var interestedIn: InterestedInGender? = nil

    // MARK: - Taipei beta additions

    /// 18+ confirmation. Required to leave onboarding. The schema has no
    /// birth-date field — this is the only adult gate today, and the
    /// product decision is to keep it as a single explicit checkbox
    /// rather than a date picker (less friction, less PII).
    @Published var isAdultConfirmed: Bool = false

    /// Three "conversation fit" chips. Recommended but NOT required —
    /// the user can submit with any combination set to nil. They show
    /// up later in the profile editor either way.
    @Published var connectionIntent: ConnectionIntent? = nil
    @Published var lifestyleRhythm: LifestyleRhythm? = nil
    @Published var conversationDomain: ConversationDomain? = nil

    // MARK: - Bookkeeping

    @Published var isWorking: Bool = false
    @Published var errorMessage: String?

    static let signalMaxLength = ProfileLimits.signalMax

    init(userId: UUID) { self.userId = userId }

    var canSubmit: Bool {
        isAdultConfirmed
        && !trimmedSignal.isEmpty
        && trimmedSignal.count <= Self.signalMaxLength
        && gender != nil
        && interestedIn != nil
        && !isWorking
    }

    var trimmedSignal: String {
        oneLineIntro.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var signalHint: String? {
        if trimmedSignal.count > Self.signalMaxLength {
            return String(localized: "profile.validation.signalTooLong")
        }
        return nil
    }

    @discardableResult
    func submit(into session: SessionManager) async -> Bool {
        guard canSubmit else { return false }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        for _ in 0..<5 {
            let handle = Self.generateHandle()
            let payload = ProfileInsert(
                id: userId,
                getalongId: handle,
                displayName: handle,
                bio: trimmedSignal,
                birthYear: nil,
                city: nil,
                country: nil,
                languageCodes: Self.deviceLanguageCodes(),
                gender: gender?.rawValue,
                genderVisible: true,
                interestedInGender: interestedIn?.rawValue,
                connectionIntent: connectionIntent?.rawValue,
                lifestyleRhythm: lifestyleRhythm?.rawValue,
                conversationDomain: conversationDomain?.rawValue
            )
            do {
                let profile = try await ProfileService.shared.createProfile(payload)
                session.setAuthenticated(profile)
                return true
            } catch ProfileError.duplicateGetalongId {
                continue
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        errorMessage = String(localized: "error.generic")
        return false
    }

    private static func generateHandle() -> String {
        let chars = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let suffix = (0..<8).map { _ in chars.randomElement()! }
        return "u" + String(suffix)
    }

    private static func deviceLanguageCodes() -> [String] {
        if let code = Locale.preferredLanguages.first?
            .components(separatedBy: "-").first {
            return [code]
        }
        return []
    }
}
