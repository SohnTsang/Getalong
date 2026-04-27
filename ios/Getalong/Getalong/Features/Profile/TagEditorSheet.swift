import SwiftUI

/// Lightweight tag editor. Presented as a sheet from ProfileView.
/// Adds/removes tags one at a time, persisting through ProfileTagService.
@MainActor
struct TagEditorSheet: View {
    let profileId: UUID
    let initialTags: [ProfileTag]
    var onChange: ([ProfileTag]) -> Void

    enum SuggestionTab: Hashable, CaseIterable, Identifiable {
        case featured
        case history
        var id: Self { self }
        var localizedTitle: String {
            switch self {
            case .featured: return String(localized: "profile.tags.featured.title")
            case .history:  return String(localized: "profile.tags.recent.title")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [ProfileTag]
    @State private var draft: String = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var suggestions: ProfileTagService.TagSuggestions =
        .init(featured: [], recent: [])
    @State private var isLoadingSuggestions = true
    @State private var suggestionTab: SuggestionTab = .featured
    @FocusState private var draftFocused: Bool

    init(profileId: UUID,
         initialTags: [ProfileTag],
         onChange: @escaping ([ProfileTag]) -> Void) {
        self.profileId = profileId
        self.initialTags = initialTags
        self.onChange = onChange
        _tags = State(initialValue: initialTags)
    }

    var body: some View {
        NavigationStack {
            GAScreen(maxWidth: 520, topPadding: GASpacing.xxl) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {
                    header
                    inputCard
                    suggestionsSection
                    if let error {
                        GAErrorBanner(message: error,
                                      onDismiss: { self.error = nil })
                    }
                }
            }
            .navigationTitle("")
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.cancel")) { dismiss() }
                        .foregroundStyle(GAColors.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done")) {
                        onChange(tags)
                        dismiss()
                    }
                    .foregroundStyle(GAColors.accent)
                }
            }
            .task { await loadSuggestions() }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: GASpacing.xs) {
            Text("profile.tags")
                .font(GATypography.screenTitle)
                .foregroundStyle(GAColors.textPrimary)
            Text("profile.tags.subtitle")
                .font(GATypography.callout)
                .foregroundStyle(GAColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var inputCard: some View {
        GACard {
            VStack(alignment: .leading, spacing: GASpacing.md) {
                GATextField(title: String(localized: "profile.tags"),
                            text: $draft,
                            placeholder: String(localized: "profile.tags.placeholder"),
                            systemImage: "number",
                            autocapitalization: .never,
                            helperText: inputHelper,
                            errorMessage: inputError)
                    .focused($draftFocused)
                    .onChange(of: draft) { newValue in
                        // Hard-cap the input at the per-tag character limit
                        // so the user can't even type past it.
                        if newValue.count > ProfileTagService.maxTagLength {
                            draft = String(newValue.prefix(ProfileTagService.maxTagLength))
                        }
                    }

                GAButton(title: String(localized: "common.add"),
                         kind: .secondary,
                         size: .compact,
                         isLoading: isWorking,
                         isDisabled: !canAdd || isWorking,
                         fillsWidth: false) {
                    Task { await commitDraft() }
                }

                if !tags.isEmpty {
                    Rectangle()
                        .fill(GAColors.border)
                        .frame(height: 0.75)
                    FlowLayout(spacing: GASpacing.sm) {
                        ForEach(tags) { tag in
                            removableChip(tag)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func removableChip(_ tag: ProfileTag) -> some View {
        HStack(spacing: GASpacing.xs) {
            Text(tag.tag).font(GATypography.caption)
            Button {
                Task { await remove(tag) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GAColors.textSecondary)
            }
            .accessibilityLabel(String(localized: "profile.tags.remove"))
            .buttonStyle(.plain)
        }
        .padding(.leading, GASpacing.md)
        .padding(.trailing, GASpacing.sm)
        .padding(.vertical, 7)
        .background(GAColors.surfaceRaised)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(GAColors.border, lineWidth: 1))
    }

    // MARK: - Actions

    private var canAdd: Bool {
        guard let normalized = ProfileTag.normalize(draft) else { return false }
        return normalized.count <= ProfileTagService.maxTagLength
            && tags.count < ProfileTagService.maxTagsPerProfile
    }

    /// Helper text shows both the per-tag length and the per-profile cap,
    /// so the user can see at a glance how much room they have left in
    /// the current draft and how many tags they can still add.
    private var inputHelper: String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(trimmed.count)/\(ProfileTagService.maxTagLength) · \(tags.count)/\(ProfileTagService.maxTagsPerProfile)"
    }

    /// Inline error directly under the input — surfaces "too long",
    /// "duplicate", and the per-profile limit before the user submits.
    private var inputError: String? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count > ProfileTagService.maxTagLength {
            return String(localized: "profile.tags.tooLong")
        }
        if let normalized = ProfileTag.normalize(draft),
           tags.contains(where: { $0.normalizedTag == normalized }) {
            return String(localized: "profile.tags.duplicate")
        }
        if tags.count >= ProfileTagService.maxTagsPerProfile {
            return String(localized: "profile.tags.limitReached")
        }
        return nil
    }

    private func commitDraft() async {
        error = nil
        isWorking = true
        defer { isWorking = false }
        do {
            let inserted = try await ProfileTagService.shared.addTag(draft, existing: tags)
            tags.append(inserted)
            draft = ""
            draftFocused = true
            Haptics.success()
        } catch let e as ProfileTagError {
            error = e.errorDescription
            Haptics.warning()
        } catch {
            self.error = String(localized: "error.generic")
            Haptics.error()
        }
    }

    private func remove(_ tag: ProfileTag) async {
        do {
            try await ProfileTagService.shared.deleteTag(id: tag.id)
            tags.removeAll { $0.id == tag.id }
            Haptics.tap()
        } catch {
            self.error = String(localized: "error.generic")
        }
    }

    // MARK: - Suggestions (Featured / History tabs)

    @ViewBuilder
    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: GASpacing.sm) {
            Picker("", selection: $suggestionTab) {
                ForEach(SuggestionTab.allCases) { tab in
                    Text(tab.localizedTitle).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            tabSubtitle

            tabContent
        }
    }

    @ViewBuilder
    private var tabSubtitle: some View {
        let key: String = suggestionTab == .featured
            ? "profile.tags.featured.subtitle"
            : "profile.tags.recent.subtitle"
        Text(LocalizedStringKey(key))
            .font(GATypography.footnote)
            .foregroundStyle(GAColors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var tabContent: some View {
        if isLoadingSuggestions {
            GACard {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, GASpacing.sm)
            }
        } else {
            let items = currentSuggestions
            if items.isEmpty {
                GACard {
                    Text("profile.tags.suggestions.empty")
                        .font(GATypography.callout)
                        .foregroundStyle(GAColors.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, GASpacing.xs)
                }
            } else {
                GACard {
                    VStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.tag) { idx, s in
                            suggestionRow(
                                label: s.tag,
                                count: suggestionTab == .featured ? s.count : nil
                            ) {
                                Task { await applySuggestion(s.tag) }
                            }
                            if idx < items.count - 1 {
                                Rectangle()
                                    .fill(GAColors.border)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
        }
    }

    private var currentSuggestions: [ProfileTagService.TagSuggestion] {
        switch suggestionTab {
        case .featured: return suggestions.featured
        case .history:  return suggestions.recent
        }
    }

    /// One suggestion per row: tappable chip on the left, count (if any)
    /// pinned to the trailing edge so the numbers line up across rows.
    @ViewBuilder
    private func suggestionRow(label: String,
                               count: Int?,
                               action: @escaping () -> Void) -> some View {
        let alreadyHas = tags.contains { $0.tag.lowercased() == label.lowercased() }
        Button(action: action) {
            HStack(spacing: GASpacing.sm) {
                HStack(spacing: GASpacing.xs) {
                    Text(label)
                        .font(GATypography.caption)
                        .foregroundStyle(alreadyHas
                                         ? GAColors.textTertiary
                                         : GAColors.textPrimary)
                    if alreadyHas {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(GAColors.textTertiary)
                    }
                }
                .padding(.horizontal, GASpacing.md)
                .padding(.vertical, 7)
                .background(alreadyHas ? GAColors.surfaceRaised.opacity(0.5)
                                       : GAColors.surfaceRaised)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(GAColors.border, lineWidth: 1))

                Spacer(minLength: GASpacing.sm)

                if let count, count > 0 {
                    Text("\(count)")
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textTertiary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, GASpacing.xs)
        }
        .buttonStyle(.plain)
        .disabled(alreadyHas || tags.count >= ProfileTagService.maxTagsPerProfile)
    }

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        defer { isLoadingSuggestions = false }
        suggestions = await ProfileTagService.shared.fetchSuggestions()
    }

    private func applySuggestion(_ raw: String) async {
        guard !tags.contains(where: { $0.tag.lowercased() == raw.lowercased() })
        else { return }
        guard tags.count < ProfileTagService.maxTagsPerProfile else {
            error = String(localized: "profile.tags.limitReached")
            return
        }
        do {
            let inserted = try await ProfileTagService.shared.addTag(raw, existing: tags)
            tags.append(inserted)
            Haptics.success()
        } catch let e as ProfileTagError {
            error = e.errorDescription
            Haptics.warning()
        } catch {
            self.error = String(localized: "error.generic")
            Haptics.error()
        }
    }
}
