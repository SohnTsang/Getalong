import SwiftUI

/// Lightweight tag editor. Presented as a sheet from ProfileView.
/// Adds/removes tags one at a time, persisting through ProfileTagService.
@MainActor
struct TagEditorSheet: View {
    let profileId: UUID
    let initialTags: [ProfileTag]
    var onChange: ([ProfileTag]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [ProfileTag]
    @State private var draft: String = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var suggestions: ProfileTagService.TagSuggestions =
        .init(featured: [], recent: [])
    @State private var isLoadingSuggestions = true
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
            GAScreen(maxWidth: 520) {
                VStack(alignment: .leading, spacing: GASpacing.sectionGap) {
                    header
                    inputCard
                    tagsCard
                    featuredCard
                    recentCard
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
                            helperText: countHelper)
                    .focused($draftFocused)

                GAButton(title: String(localized: "common.add"),
                         kind: .secondary,
                         size: .compact,
                         isLoading: isWorking,
                         isDisabled: !canAdd || isWorking,
                         fillsWidth: false) {
                    Task { await commitDraft() }
                }
            }
        }
    }

    private var tagsCard: some View {
        GACard {
            if tags.isEmpty {
                Text("profile.tags.empty")
                    .font(GATypography.body)
                    .foregroundStyle(GAColors.textSecondary)
            } else {
                FlowLayout(spacing: GASpacing.sm) {
                    ForEach(tags) { tag in
                        removableChip(tag)
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
        ProfileTag.normalize(draft) != nil &&
        tags.count < ProfileTagService.maxTagsPerProfile
    }

    private var countHelper: String {
        "\(tags.count) / \(ProfileTagService.maxTagsPerProfile)"
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

    // MARK: - Suggestion cards

    @ViewBuilder
    private var featuredCard: some View {
        if isLoadingSuggestions {
            GACard {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .padding(.vertical, GASpacing.sm)
            }
        } else if !suggestions.featured.isEmpty {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                GASectionHeader(
                    title: String(localized: "profile.tags.featured.title"),
                    subtitle: String(localized: "profile.tags.featured.subtitle")
                )
                GACard {
                    FlowLayout(spacing: GASpacing.sm) {
                        ForEach(suggestions.featured, id: \.tag) { s in
                            suggestionChip(label: s.tag,
                                           count: s.count) {
                                Task { await applySuggestion(s.tag) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var recentCard: some View {
        if !suggestions.recent.isEmpty {
            VStack(alignment: .leading, spacing: GASpacing.sm) {
                GASectionHeader(
                    title: String(localized: "profile.tags.recent.title"),
                    subtitle: String(localized: "profile.tags.recent.subtitle")
                )
                GACard {
                    FlowLayout(spacing: GASpacing.sm) {
                        ForEach(suggestions.recent, id: \.tag) { s in
                            suggestionChip(label: s.tag, count: nil) {
                                Task { await applySuggestion(s.tag) }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func suggestionChip(label: String,
                                count: Int?,
                                action: @escaping () -> Void) -> some View {
        let alreadyHas = tags.contains { $0.tag.lowercased() == label.lowercased() }
        Button(action: action) {
            HStack(spacing: GASpacing.xs) {
                Text(label)
                    .font(GATypography.caption)
                    .foregroundStyle(alreadyHas
                                     ? GAColors.textTertiary
                                     : GAColors.textPrimary)
                if let count, count > 0 {
                    Text("\(count)")
                        .font(GATypography.caption)
                        .foregroundStyle(GAColors.textTertiary)
                        .monospacedDigit()
                }
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
