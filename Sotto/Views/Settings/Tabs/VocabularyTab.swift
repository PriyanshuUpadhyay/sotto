import SwiftUI

@MainActor
struct VocabularyTab: View {
    @StateObject private var whisperPrompt = WhisperPrompt()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var highlightedSection: VocabularyTabSection?

    // MARK: - Introspectable composition descriptor
    //
    // The three former destinations — Dictionary words, Word replacements, and
    // Snippets — are merged into this one tab. Each section is enumerated here
    // and rendered through the EXHAUSTIVE `view(for:)` switch over
    // `ForEach(renderedSections)`, where `renderedSections == allCases`. So the
    // rendered composition IS this descriptor by construction: a section cannot
    // be dropped from the body without removing its enum case (a compile error
    // in the exhaustive switch), and each section's factory returns the EXISTING
    // editor view — over the SAME SwiftData model — so dropping an editor is a
    // compile error caught by `SettingsVocabularyTabTests`.

    enum VocabularyTabSection: CaseIterable, Hashable {
        case dictionary
        case wordReplacements
    }

    /// The exact, ordered list the body's `ForEach` renders from. It IS
    /// `allCases`, so the rendered set equals the full descriptor by
    /// construction; `SettingsVocabularyTabTests` asserts this equality.
    static var renderedSections: [VocabularyTabSection] { VocabularyTabSection.allCases }

    /// Factory for the dictionary section so its reuse of the existing
    /// `VocabularyView` (over the `VocabularyWord` SwiftData model) is
    /// introspectable. Dropping the dictionary editor changes this return type.
    static func dictionaryView(whisperPrompt: WhisperPrompt) -> VocabularyView {
        VocabularyView(whisperPrompt: whisperPrompt)
    }

    /// Factory for the word-replacements section, reusing the existing
    /// `WordReplacementView` (over the `WordReplacement` SwiftData model).
    static func wordReplacementsView() -> WordReplacementView {
        WordReplacementView()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(Self.renderedSections, id: \.self) { section in
                        view(for: section)
                            .id(section)
                            .settingsSectionHighlight(active: highlightedSection == section, reduceMotion: reduceMotion)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .tint(Brand.tint)
            .onReceive(NotificationCenter.default.publisher(for: .selectSettingsSection)) { note in
                handleSettingsSectionJump(note, thisTab: .vocabulary, sections: Self.renderedSections, label: { $0.searchLabel }, proxy: proxy, reduceMotion: reduceMotion, highlight: $highlightedSection)
            }
        }
    }

    // MARK: - Descriptor-driven rendering
    //
    // Exhaustive over VocabularyTabSection: removing an enum case fails to
    // compile, so the descriptor cannot drift from what the body renders. Each
    // case reuses the EXISTING editor view over its original SwiftData model.

    @ViewBuilder
    private func view(for section: VocabularyTabSection) -> some View {
        switch section {
        case .dictionary:
            SettingsCard(
                iconSystemName: "character.book.closed.fill",
                iconTint: Brand.tint,
                title: "Dictionary",
                subtitle: "Words to help Sotto recognize your vocabulary."
            ) {
                Self.dictionaryView(whisperPrompt: whisperPrompt)
            }

        case .wordReplacements:
            SettingsCard(
                iconSystemName: "arrow.2.squarepath",
                iconTint: Brand.tint,
                title: "Word Replacements",
                subtitle: "Automatically replace words or phrases."
            ) {
                Self.wordReplacementsView()
            }
        }
    }
}
