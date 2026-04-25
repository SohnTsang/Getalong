import SwiftUI

/// User-selectable appearance preference.
enum GAAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Card chrome

enum GACardKind {
    /// Default surface, subtle border, very light shadow.
    case standard
    /// Slightly raised surface with a stronger shadow.
    case elevated
    /// Card that responds to a tap (slight press dim).
    case interactive
    /// Card highlighted by the accent (used for the live invite hero).
    case highlight
}

struct GACardStyle: ViewModifier {
    var kind: GACardKind = .standard
    var padding: CGFloat = GASpacing.cardPadding
    var radius:  CGFloat = GACornerRadius.large

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: strokeWidth)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
    }

    private var fill: Color {
        switch kind {
        case .standard, .interactive: return GAColors.surface
        case .elevated:               return GAColors.surface
        case .highlight:              return GAColors.accentSoft
        }
    }
    private var stroke: Color {
        switch kind {
        case .highlight: return GAColors.accent.opacity(0.35)
        default:         return GAColors.border
        }
    }
    private var strokeWidth: CGFloat {
        kind == .highlight ? 1 : 0.75
    }
    private var shadowColor: Color {
        switch kind {
        case .elevated, .highlight: return Color.black.opacity(0.08)
        default:                    return Color.black.opacity(0.04)
        }
    }
    private var shadowRadius: CGFloat {
        switch kind {
        case .elevated, .highlight: return 18
        default:                    return 10
        }
    }
    private var shadowY: CGFloat {
        switch kind {
        case .elevated, .highlight: return 6
        default:                    return 3
        }
    }
}

extension View {
    /// Apply Getalong card chrome.
    func gaCard(_ kind: GACardKind = .standard,
                padding: CGFloat = GASpacing.cardPadding,
                radius:  CGFloat = GACornerRadius.large) -> some View {
        modifier(GACardStyle(kind: kind, padding: padding, radius: radius))
    }
}
