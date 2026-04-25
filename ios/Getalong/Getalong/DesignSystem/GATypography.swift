import SwiftUI

/// Typography tokens for Getalong.
///
/// Sizes use Dynamic Type via `relativeTo:` so accessibility text sizing
/// works out of the box. Weight choices reflect the "calm, premium,
/// text-first" direction — avoid heavy display weights elsewhere.
enum GATypography {

    /// Big screen titles (Discover header, etc.).
    static let display      = Font.system(size: 30, weight: .semibold, design: .rounded)

    /// Section titles inside a screen.
    static let title        = Font.system(size: 22, weight: .semibold, design: .rounded)

    /// Subheaders, list-row primary text.
    static let headline     = Font.system(size: 17, weight: .semibold)

    /// Body text in cards, posts, chat bubbles.
    static let body         = Font.system(size: 16, weight: .regular)

    /// Smaller body, secondary metadata.
    static let callout      = Font.system(size: 15, weight: .regular)

    /// Footnotes, timestamps.
    static let footnote     = Font.system(size: 13, weight: .regular)

    /// Tiny labels (chip text, system messages).
    static let caption      = Font.system(size: 12, weight: .medium)

    /// Buttons (consistent across the app).
    static let button       = Font.system(size: 16, weight: .semibold, design: .rounded)
}
