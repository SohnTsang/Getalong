import Foundation

/// Single source of truth for the legal/support URLs we link from the app.
/// The custom domain is the canonical surface; the GitHub Pages mirror is
/// kept here only as a fallback during migration.
enum LegalLinks {
    static let privacy = URL(string: "https://getalong.app/privacy/")!
    static let terms   = URL(string: "https://getalong.app/terms/")!
    static let support = URL(string: "https://getalong.app/support/")!
}
