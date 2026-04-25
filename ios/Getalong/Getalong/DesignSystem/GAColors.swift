import SwiftUI
import UIKit

/// Getalong "Quiet Signal" semantic colour tokens.
///
/// Light mode is a warm off-white with ink-coloured text.
/// Dark mode is a deep ink with a hint of warm umber, never pure black.
/// Never reference raw hex in feature code — always go through these tokens.
enum GAColors {

    // MARK: - Surfaces

    /// Page background. Warm off-white in light, deep ink in dark.
    static let background        = dyn(light: 0xF7F4EE, dark: 0x0E1014)
    /// Slightly lifted surface used for the section beneath cards
    /// (e.g. tab bar background, sheet header).
    static let backgroundElevated = dyn(light: 0xFBF8F2, dark: 0x141821)
    /// Standard card surface.
    static let surface           = dyn(light: 0xFFFFFF, dark: 0x1A1F2A)
    /// Card surface that sits ON another card / nested input fill.
    static let surfaceRaised     = dyn(light: 0xF1ECE3, dark: 0x232936)

    // MARK: - Text

    static let textPrimary       = dyn(light: 0x141518, dark: 0xF1EFEA)
    static let textSecondary     = dyn(light: 0x52555D, dark: 0xA7ABB5)
    static let textTertiary      = dyn(light: 0x8C909A, dark: 0x6C7280)
    static let textOnAccent      = dyn(light: 0xFFFFFF, dark: 0x0E1014)

    // MARK: - Lines

    static let border            = dyn(light: 0xE7E2D6, dark: 0x2A3140)
    static let borderStrong      = dyn(light: 0xCFC9BB, dark: 0x3A4258)

    // MARK: - Accent (warm coral — Getalong's voice)

    static let accent            = dyn(light: 0xE5573D, dark: 0xFF7B62)
    /// Pale wash of the accent for highlight backgrounds.
    static let accentSoft        = dyn(light: 0xFCE9E2, dark: 0x351913)
    /// Deeper accent for pressed state.
    static let accentPressed     = dyn(light: 0xC23F27, dark: 0xE6664E)
    /// Always pairs with `accent` background.
    static let accentText        = dyn(light: 0xFFFFFF, dark: 0x0E1014)

    /// Secondary accent — a calmer indigo used for outgoing-invite,
    /// progress, and "in flight" affordances. Coral is the verb; this
    /// indigo is the meanwhile.
    static let secondary         = dyn(light: 0x4F5BD5, dark: 0x8B95F2)
    static let secondarySoft     = dyn(light: 0xE6E8FA, dark: 0x1B1E33)

    // MARK: - Status

    static let success           = dyn(light: 0x2E8E66, dark: 0x4DC78A)
    static let warning           = dyn(light: 0xC0822B, dark: 0xE9B252)
    static let danger            = dyn(light: 0xC8453B, dark: 0xEC6F65)

    /// Live invite ring/glow tint.
    static let inviteLive        = dyn(light: 0xE5573D, dark: 0xFF7B62)
    /// Missed invite tone — softer, more amber.
    static let inviteMissed      = dyn(light: 0xC0822B, dark: 0xE9B252)

    /// Subtle shadow colour. Use as `Color.black.opacity` directly for
    /// shadows; this token is here for places where we need a tinted
    /// shadow to hint at warmth.
    static let shadow            = Color.black.opacity(0.05)

    // MARK: - Helpers

    private static func dyn(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(hex: dark)
                : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >>  8) & 0xFF) / 255
        let b = CGFloat( hex        & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
