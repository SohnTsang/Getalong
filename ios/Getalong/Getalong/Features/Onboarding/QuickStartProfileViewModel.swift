import Foundation
import SwiftUI

@MainActor
final class QuickStartProfileViewModel: ObservableObject {

    let userId: UUID

    /// The only field the user actually fills in. Required.
    @Published var oneLineIntro: String = ""
    /// Required: user must pick.
    @Published var gender: Gender? = nil
    /// Required: user must pick.
    @Published var interestedIn: InterestedInGender? = nil

    @Published var isWorking: Bool = false
    @Published var errorMessage: String?

    static let signalMaxLength = 160

    init(userId: UUID) { self.userId = userId }

    var canSubmit: Bool {
        !trimmedSignal.isEmpty
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

        // Try a few generated handles to absorb the rare duplicate.
        for _ in 0..<5 {
            let handle = Self.generateHandle()
            let payload = ProfileInsert(
                id: userId,
                getalongId: handle,
                // display_name is required by the schema. We seed it from
                // the handle; the user can change it later from Profile.
                displayName: handle,
                bio: trimmedSignal,
                birthYear: nil,
                city: nil,
                country: nil,
                languageCodes: Self.deviceLanguageCodes(),
                gender: gender?.rawValue,
                genderVisible: true,
                interestedInGender: interestedIn?.rawValue
            )
            do {
                let profile = try await ProfileService.shared.createProfile(payload)
                session.setAuthenticated(profile)
                return true
            } catch ProfileError.duplicateGetalongId {
                continue   // try a different random handle
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        errorMessage = String(localized: "error.generic")
        return false
    }

    /// Stable internal handle: 8 random base-36 chars prefixed with "u".
    /// Hidden from onboarding UI; users only ever see this as their @handle
    /// after creation, and can edit display_name freely.
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
