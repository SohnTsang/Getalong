import SwiftUI

/// Compact, read-only context strip shown at the top of a ChatRoom
/// (under the header, above the message list). Helps the user remember
/// who they're talking to using ONLY public profile context — the same
/// fields Discovery and the Invite cards surface:
///   1. one honest line (bio), max 2 lines
///   2. up to three conversation-fit chips (intent / rhythm / domain)
///   3. plain `#tag #tag` hashtags
///
/// It is purely informational: no avatar, no handle, no display name, no
/// buttons, no actions. Any missing piece is hidden; if everything is
/// empty the parent doesn't render the strip at all (see
/// `ChatRoomViewModel.hasPartnerContext`). Chip palette + hashtag style
/// mirror `DiscoveryCard` / `InviteUserCard` so the surfaces read alike.
struct ChatPartnerContextStrip: View {
    let line: String?
    let intent: ConnectionIntent?
    let rhythm: LifestyleRhythm?
    let domain: ConversationDomain?
    let tags: [String]

    private var trimmedLine: String? {
        guard let t = line?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        return t
    }

    private var hasFitChips: Bool {
        intent != nil || rhythm != nil || domain != nil
    }

    private var isEmpty: Bool {
        trimmedLine == nil && !hasFitChips && tags.isEmpty
    }

    var body: some View {
        if isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                if let line = trimmedLine {
                    Text(line)
                        .font(GATypography.footnote.weight(.medium))
                        .foregroundStyle(GAColors.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if hasFitChips {
                    fitChipsBlock
                }
                if !tags.isEmpty {
                    hashtagsBlock
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GASpacing.md)
            .padding(.vertical, GASpacing.sm)
            .background(
                RoundedRectangle(cornerRadius: GACornerRadius.medium, style: .continuous)
                    .fill(GAColors.surfaceRaised)
            )
            .padding(.horizontal, GASpacing.lg)
            .padding(.top, GASpacing.sm)
            .padding(.bottom, GASpacing.xs)
        }
    }

    // MARK: - Fit chips (mirrors DiscoveryCard / InviteUserCard)

    private var fitChipsBlock: some View {
        FlowLayout(spacing: GASpacing.sm) {
            if let intent { fitChip(label: intent.localizedShort, kind: .intent) }
            if let rhythm { fitChip(label: rhythm.localizedShort, kind: .rhythm) }
            if let domain { fitChip(label: domain.localizedShort, kind: .domain) }
        }
    }

    private enum FitChipKind {
        case intent, rhythm, domain
        var textColor: Color {
            switch self {
            case .intent: return GAColors.fitIntentText
            case .rhythm: return GAColors.fitRhythmText
            case .domain: return GAColors.fitDomainText
            }
        }
        var backgroundColor: Color {
            switch self {
            case .intent: return GAColors.fitIntentBg
            case .rhythm: return GAColors.fitRhythmBg
            case .domain: return GAColors.fitDomainBg
            }
        }
    }

    private func fitChip(label: String, kind: FitChipKind) -> some View {
        Text(label)
            .font(GATypography.footnote.weight(.medium))
            .foregroundStyle(kind.textColor)
            .padding(.horizontal, GASpacing.sm)
            .padding(.vertical, 6)
            .background(kind.backgroundColor, in: Capsule())
    }

    // MARK: - Hashtags (plain text, same treatment as Discovery/Invite)

    private var hashtagsBlock: some View {
        Text(tags.map { "#\($0)" }.joined(separator: " "))
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textTertiary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
