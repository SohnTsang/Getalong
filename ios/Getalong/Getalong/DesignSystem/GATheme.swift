import SwiftUI

/// User-selectable appearance preference.
/// Persisted via `@AppStorage("ga.appearance")`.
enum GAAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

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

/// Elevation / shadow tokens.
enum GAElevation {
    /// Soft card shadow — kept subtle to feel premium, not floaty.
    static func cardShadow() -> some View {
        EmptyView()
    }
}

/// View modifier that applies the standard Getalong card chrome.
struct GACardStyle: ViewModifier {
    var padding: CGFloat = GASpacing.lg
    var radius: CGFloat = GACornerRadius.lg

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(GAColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(GAColors.border, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func gaCard(padding: CGFloat = GASpacing.lg,
                radius: CGFloat = GACornerRadius.lg) -> some View {
        modifier(GACardStyle(padding: padding, radius: radius))
    }
}
