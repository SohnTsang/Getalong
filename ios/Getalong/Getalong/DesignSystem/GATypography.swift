import SwiftUI

/// Getalong typography scale — full hierarchy. Every size is a token.
/// Do not write `Font.system(size:)` inside feature views.
///
/// Choices:
/// * `largeTitle` / `screenTitle` use rounded design — adds the calm,
///   slightly humanist character we want without going decorative.
/// * Body and below stay default-design for readability.
/// * All sizes scale with Dynamic Type via `.relativeTo:`.
enum GATypography {

    /// Editorial hero — auth / first run / brand moments only.
    /// Tighter line height, serif design for character.
    static let editorial = Font.system(size: 44, weight: .regular, design: .serif)

    /// Mid-size serif used for in-card quoted messages (the live-invite
    /// teaser on the auth landing).
    static let editorialQuote = Font.system(size: 22, weight: .regular, design: .serif)

    /// Hero text on standard top-of-screen layouts.
    static let largeTitle = Font.system(size: 32, weight: .semibold, design: .rounded)

    /// Top-of-screen title (e.g. nav title replacement).
    static let screenTitle = Font.system(size: 26, weight: .semibold, design: .rounded)

    /// Strong card title.
    static let title = Font.system(size: 22, weight: .semibold, design: .rounded)

    /// Card section header / list group label.
    static let sectionTitle = Font.system(size: 13, weight: .semibold)
        .smallCaps()

    /// Standard reading text.
    static let body = Font.system(size: 16, weight: .regular)

    /// Same body, but bold/semibold to mark a key sentence.
    static let bodyEmphasized = Font.system(size: 16, weight: .semibold)

    /// Slightly smaller body for secondary copy.
    static let callout = Font.system(size: 15, weight: .regular)

    /// Footnotes, helper text, error text.
    static let footnote = Font.system(size: 13, weight: .regular)

    /// Captions on chips/pills/timestamps.
    static let caption = Font.system(size: 12, weight: .medium)

    /// Tiny micro-label (kbd, count badges).
    static let micro = Font.system(size: 11, weight: .semibold)

    /// All buttons share this. Consistent weight/letter form across the app.
    static let button = Font.system(size: 16, weight: .semibold, design: .rounded)

    /// Big, monospaced countdown number (Live invite).
    static let countdown = Font.system(size: 44, weight: .semibold, design: .rounded)
        .monospacedDigit()
}
