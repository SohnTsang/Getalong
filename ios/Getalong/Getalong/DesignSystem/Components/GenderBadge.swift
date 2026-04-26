import SwiftUI

/// Small, calm pill that surfaces a profile's gender above the one-line
/// signal. Uses two distinct token-based palettes so male/female are
/// instantly differentiable without resorting to clichéd pink/blue
/// stereotypes — male picks up the slate-blue secondary, female picks
/// up a muted rose that complements (but doesn't mirror) the brand red.
///
/// Visual rhythm matches `GAStatusPill`: small dot + uppercased caption,
/// 12pt height. Designed to be quiet on a surface card; never the
/// dominant element.
struct GenderBadge: View {
    enum Kind {
        case male
        case female

        /// Build a badge from the raw `profiles.gender` string. Returns
        /// nil for any value we don't render — including `null` (gender
        /// not set or not visible).
        static func from(rawValue: String?) -> Kind? {
            switch rawValue?.lowercased() {
            case "male":   return .male
            case "female": return .female
            default:       return nil
            }
        }

        /// Solid tint used for the badge's mark + label and for any
        /// surrounding card hairline that wants to echo the gender.
        var tint: Color {
            switch self {
            case .male:
                return GAColors.secondary
            case .female:
                return Color(.displayP3, red: 0.74, green: 0.36, blue: 0.45, opacity: 1)
            }
        }
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: 6) {
            mark
            Text(label)
                .font(GATypography.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(foreground)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(background)
        .clipShape(Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(stroke, lineWidth: 0.75)
        )
    }

    // MARK: - Glyph

    /// Different shape per kind so the badge is recognisable even at
    /// glance without the label: female reads as a small open ring,
    /// male reads as a solid bar — abstract, geometric, on-brand.
    @ViewBuilder
    private var mark: some View {
        switch kind {
        case .male:
            // Solid horizontal bar — a "transmitter" tick.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(foreground)
                .frame(width: 8, height: 3)
        case .female:
            // Thin open ring.
            Circle()
                .strokeBorder(foreground, lineWidth: 1.4)
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Palette

    private var label: String {
        switch kind {
        case .male:   return String(localized: "quickstart.gender.male")
        case .female: return String(localized: "quickstart.gender.female")
        }
    }

    private var foreground: Color { kind.tint }

    private var background: Color {
        switch kind {
        case .male:   return GAColors.secondarySoft
        case .female: return kind.tint.opacity(0.10)
        }
    }

    private var stroke: Color { kind.tint.opacity(0.25) }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        GenderBadge(kind: .male)
        GenderBadge(kind: .female)
    }
    .padding()
}
