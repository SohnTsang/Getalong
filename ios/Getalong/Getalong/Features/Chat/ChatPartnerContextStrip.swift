import SwiftUI

/// Compact, read-only context bar shown at the top of a ChatRoom (under
/// the header divider, above the message list). Helps the user remember
/// who they're talking to using ONLY lightweight public context — the
/// same fields Discovery and the Invite cards surface:
///   1. up to three conversation-fit chips (intent / rhythm / domain)
///   2. plain `#tag #tag` hashtags
///
/// Deliberately does NOT show the one-line bio (kept out so the chat
/// stays focused on the conversation, not the profile), nor any avatar,
/// handle, display name, gender badge, title, or action. Any missing
/// piece is hidden; if both chips and tags are absent the parent doesn't
/// render the strip at all (see `ChatRoomViewModel.hasPartnerContext`).
/// Chip palette + hashtag style mirror `DiscoveryCard` / `InviteUserCard`
/// so the surfaces read alike.
struct ChatPartnerContextStrip: View {
    let intent: ConnectionIntent?
    let rhythm: LifestyleRhythm?
    let domain: ConversationDomain?
    let tags: [String]

    private var hasFitChips: Bool {
        intent != nil || rhythm != nil || domain != nil
    }

    private var isEmpty: Bool {
        !hasFitChips && tags.isEmpty
    }

    var body: some View {
        if isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                if hasFitChips {
                    fitChipsBlock
                }
                if !tags.isEmpty {
                    hashtagsBlock
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GASpacing.md)
            .padding(.vertical, GASpacing.md)
            .background(
                RoundedRectangle(cornerRadius: GACornerRadius.large, style: .continuous)
                    .fill(GAColors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: GACornerRadius.large, style: .continuous)
                            .strokeBorder(GAColors.border.opacity(0.6), lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, GASpacing.lg)
            .padding(.top, GASpacing.md)
            .padding(.bottom, GASpacing.sm)
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
        Text(tags.map { "#\($0)" }.joined(separator: "  "))
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textSecondary)
            .lineSpacing(3)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
