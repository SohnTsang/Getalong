import SwiftUI

enum GAChipKind {
    case neutral
    case selected
    case accent
    case warning
    case success
}

/// Pill-shaped chip used for topics, filters, status labels.
struct GAChip: View {
    let label: String
    var systemImage: String? = nil
    var kind: GAChipKind = .neutral
    var action: (() -> Void)? = nil

    var body: some View {
        let chipContent = HStack(spacing: GASpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(label).font(GATypography.caption)
        }
        .padding(.horizontal, GASpacing.md)
        .padding(.vertical, 7)
        .background(fill)
        .foregroundStyle(foreground)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))

        if let action {
            Button(action: action) { chipContent }
                .buttonStyle(.plain)
        } else {
            chipContent
        }
    }

    private var fill: Color {
        switch kind {
        case .neutral:  return GAColors.surfaceRaised
        case .selected: return GAColors.accentSoft
        case .accent:   return GAColors.accent
        case .warning:  return GAColors.warning.opacity(0.15)
        case .success:  return GAColors.success.opacity(0.15)
        }
    }
    private var foreground: Color {
        switch kind {
        case .neutral:  return GAColors.textPrimary
        case .selected: return GAColors.accent
        case .accent:   return GAColors.accentText
        case .warning:  return GAColors.warning
        case .success:  return GAColors.success
        }
    }
    private var stroke: Color {
        switch kind {
        case .neutral:  return GAColors.border
        case .selected: return GAColors.accent.opacity(0.45)
        case .accent:   return Color.clear
        case .warning:  return GAColors.warning.opacity(0.35)
        case .success:  return GAColors.success.opacity(0.35)
        }
    }
}

/// Solid status pill — used for plan badges (Free/Silver/Gold) and
/// invite states (Live/Missed). Tighter than `GAChip`.
struct GAStatusPill: View {
    let label: String
    var systemImage: String? = nil
    var tint: Color = GAColors.accent

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(label.uppercased()).font(GATypography.micro).tracking(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(tint)
        .background(tint.opacity(0.14))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.75))
    }
}
