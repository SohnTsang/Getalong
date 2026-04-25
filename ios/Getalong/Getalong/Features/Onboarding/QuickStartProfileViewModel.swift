import Foundation
import SwiftUI

@MainActor
final class QuickStartProfileViewModel: ObservableObject {

    let userId: UUID

    @Published var getalongId: String = ""
    @Published var displayName: String = ""
    @Published var oneLineIntro: String = ""
    @Published var is18Confirmed: Bool = false

    @Published var isWorking: Bool = false
    @Published var errorMessage: String?

    init(userId: UUID) { self.userId = userId }

    var canSubmit: Bool {
        !cleanedHandle.isEmpty
        && cleanedHandle.count >= 3
        && cleanedHandle.count <= 20
        && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && is18Confirmed
        && !isWorking
    }

    /// Lowercased, alphanumeric + `_` only. Mirrors what most apps allow.
    var cleanedHandle: String {
        getalongId
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    var handleHint: String? {
        let raw = getalongId.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return nil }
        if cleanedHandle.count < 3 { return "Handle must be at least 3 characters." }
        if cleanedHandle.count > 20 { return "Handle must be at most 20 characters." }
        if cleanedHandle != raw.lowercased() { return "Saved as @\(cleanedHandle)." }
        return nil
    }

    @discardableResult
    func submit(into session: SessionManager) async -> Bool {
        guard canSubmit else { return false }
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }

        let trimmedIntro = oneLineIntro.trimmingCharacters(in: .whitespacesAndNewlines)
        let payload = ProfileInsert(
            id: userId,
            getalongId: cleanedHandle,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            bio: trimmedIntro.isEmpty ? nil : trimmedIntro,
            birthYear: nil,
            city: nil,
            country: nil,
            languageCodes: Self.deviceLanguageCodes(),
            gender: nil,
            genderVisible: false
        )

        do {
            let profile = try await ProfileService.shared.createProfile(payload)
            session.setAuthenticated(profile)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private static func deviceLanguageCodes() -> [String] {
        if let code = Locale.preferredLanguages.first?
            .components(separatedBy: "-").first {
            return [code]
        }
        return []
    }
}
