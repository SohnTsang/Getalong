import SwiftUI
import UIKit

/// Semantic color tokens for Getalong.
///
/// Never reference raw hex values in feature views. Always use these
/// tokens so light/dark mode and future re-skinning stay consistent.
enum GAColors {

    // MARK: Brand

    /// Warm coral accent — used for primary CTAs, send-invite, key actions.
    static let accent       = dynamic(light: 0xFF6B57, dark: 0xFF8775)
    static let accentSoft   = dynamic(light: 0xFFE7E1, dark: 0x3A1F1B)

    /// Calm secondary — invite countdown, secondary highlights.
    static let secondary    = dynamic(light: 0x6E7BFF, dark: 0x8C97FF)

    // MARK: Backgrounds

    /// Warm off-white in light mode, deep soft black in dark mode.
    static let background       = dynamic(light: 0xFAF7F2, dark: 0x0F1012)
    /// Card surface, slightly elevated from `background`.
    static let surface          = dynamic(light: 0xFFFFFF, dark: 0x16181C)
    /// Inset surface (e.g. inputs), one notch deeper than `surface`.
    static let surfaceMuted     = dynamic(light: 0xF1ECE5, dark: 0x1D2025)

    // MARK: Text

    static let textPrimary      = dynamic(light: 0x141518, dark: 0xF2F1EE)
    static let textSecondary    = dynamic(light: 0x595B62, dark: 0xA3A6AE)
    static let textTertiary     = dynamic(light: 0x8A8C93, dark: 0x70747C)
    static let textOnAccent     = dynamic(light: 0xFFFFFF, dark: 0x0F1012)

    // MARK: Borders & dividers

    static let border           = dynamic(light: 0xE5E0D8, dark: 0x2A2D33)
    static let divider          = dynamic(light: 0xEEEAE2, dark: 0x23262B)

    // MARK: Status

    static let success          = dynamic(light: 0x2EA66B, dark: 0x4DC78A)
    static let warning          = dynamic(light: 0xD9881E, dark: 0xF1A946)
    static let danger           = dynamic(light: 0xD8453B, dark: 0xF06B61)

    // MARK: Helpers

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
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
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}
