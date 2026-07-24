import SwiftUI
import SwiftData

enum VocabularySortMode: String {
    case wordAsc = "wordAsc"
    case wordDesc = "wordDesc"
}

struct VocabularyView: View {
    @Query private var vocabularyWords: [VocabularyWord]
    @Query private var editRecords: [EnhancementEditRecord]
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorSchemeContrast) private var contrast
    @ObservedObject var whisperPrompt: WhisperPrompt
    @State private var newWord = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var sortMode: VocabularySortMode = .wordAsc
    @State private var dismissedKeys: Set<String> = CorrectionSuggestionDismissals.dismissed()

    init(whisperPrompt: WhisperPrompt) {
        self.whisperPrompt = whisperPrompt

        if let savedSort = UserDefaults.standard.string(forKey: "vocabularySortMode"),
           let mode = VocabularySortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedItems: [VocabularyWord] {
        switch sortMode {
        case .wordAsc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending }
        case .wordDesc:
            return vocabularyWords.sorted { $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedDescending }
        }
    }

    private func toggleSort() {
        sortMode = (sortMode == .wordAsc) ? .wordDesc : .wordAsc
        UserDefaults.standard.set(sortMode.rawValue, forKey: "vocabularySortMode")
    }

    private var shouldShowAddButton: Bool {
        !newWord.isEmpty
    }

    /// Up to 3 highest-confidence correction suggestions mined from repeated
    /// post-paste edits. Recomputed from the live queries + dismissals.
    private var suggestions: [CorrectionSuggestion] {
        Array(CorrectionMiner.mine(
            records: editRecords,
            existingVocabulary: Set(vocabularyWords.map { $0.word.lowercased() }),
            existingReplacements: Set(wordReplacements.flatMap {
                CorrectionMiner.replacementPairKeys(original: $0.originalText, replacement: $0.replacementText)
            }),
            dismissed: dismissedKeys
        ).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            matteInfoCard("Add words to help Sotto recognize them properly. (Requires AI enhancement)")

            if !suggestions.isEmpty {
                suggestionsSection
            }

            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.inkSecondary)
                    TextField("Add word to vocabulary", text: $newWord)
                        .textFieldStyle(.plain)
                        .font(.mono(13))
                        .foregroundStyle(Palette.inkPrimary)
                        .onSubmit { addWords() }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(matteFieldBackground)

                if shouldShowAddButton {
                    Button(action: addWords) {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Palette.phosphor)
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .disabled(newWord.isEmpty)
                    .help("Add word")
                }
            }
            .animation(Animation.haloPhaseCrossfade, value: shouldShowAddButton)

            if !vocabularyWords.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: toggleSort) {
                        HStack(spacing: 4) {
                            Text("Vocabulary Words (\(vocabularyWords.count))")
                                .font(.microlabel(11))
                                .tracking(1.2)
                                .textCase(.uppercase)
                                .foregroundStyle(Palette.inkSecondary)

                            Image(systemName: sortMode == .wordAsc ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Palette.phosphor)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Sort alphabetically")

                    ScrollView {
                        FlowLayout(spacing: 8) {
                            ForEach(sortedItems) { item in
                                VocabularyWordView(item: item) {
                                    removeWord(item)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 200)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .alert("Vocabulary", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Correction suggestions

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggested from your edits")
                .font(.microlabel(11))
                .tracking(1.2)
                .textCase(.uppercase)
                .foregroundStyle(Palette.inkSecondary)

            ForEach(suggestions) { suggestion in
                CorrectionSuggestionRow(
                    suggestion: suggestion,
                    onAdd: { addSuggestion(suggestion) },
                    onDismiss: { dismissSuggestion(suggestion) }
                )
            }
        }
        .animation(Animation.haloPhaseCrossfade, value: suggestions)
    }

    private func addSuggestion(_ suggestion: CorrectionSuggestion) {
        // Adding the word grows `vocabularyWords`, which drops the suggestion
        // from `suggestions` on the next recompute.
        if let error = DictionaryService.addVocabularyWords(
            suggestion.replacement, existing: Array(vocabularyWords), context: modelContext) {
            alertMessage = error
            showAlert = true
        }
    }

    private func dismissSuggestion(_ suggestion: CorrectionSuggestion) {
        dismissedKeys.insert(suggestion.id)
        CorrectionSuggestionDismissals.dismiss(suggestion.id)
    }

    // MARK: - Matte chrome

    private func matteInfoCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(Palette.phosphor)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Palette.mtRaise)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(A11y.borderColor(increaseContrast: contrast == .increased), lineWidth: 1)
                )
        )
    }

    private var matteFieldBackground: some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Palette.mtRaise2)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Palette.mtLine, lineWidth: 1)
            )
    }

    private func addWords() {
        let input = newWord.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        if let error = DictionaryService.addVocabularyWords(input, existing: Array(vocabularyWords), context: modelContext) {
            alertMessage = error
            showAlert = true
            return
        }
        newWord = ""
    }

    private func removeWord(_ word: VocabularyWord) {
        modelContext.delete(word)

        do {
            try modelContext.save()
        } catch {
            // Rollback the delete to restore UI consistency
            modelContext.rollback()
            alertMessage = "Failed to remove word: \(error.localizedDescription)"
            showAlert = true
        }
    }
}

struct VocabularyWordView: View {
    let item: VocabularyWord
    let onDelete: () -> Void
    @State private var isDeleteHovered = false

    var body: some View {
        HStack(spacing: 6) {
            Text(item.word)
                .font(.mono(13))
                .lineLimit(1)
                .foregroundStyle(Palette.inkPrimary)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isDeleteHovered ? Palette.stateFail : Palette.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Remove word")
            .onHover { hover in
                withAnimation(Animation.haloPhaseCrossfade) {
                    isDeleteHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.mtRaise2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .strokeBorder(Palette.mtLine, lineWidth: 1)
        }
    }
}

/// A single mined-correction suggestion: shows the `original → replacement`
/// pair the user has repeatedly corrected, with Add-to-vocabulary and Dismiss.
struct CorrectionSuggestionRow: View {
    let suggestion: CorrectionSuggestion
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(suggestion.original)
                    .font(.mono(13))
                    .foregroundStyle(Palette.inkSecondary)
                    .strikethrough()
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.inkTertiary)
                Text(suggestion.replacement)
                    .font(.mono(13))
                    .foregroundStyle(Palette.inkPrimary)
                Text("· seen \(suggestion.count)×")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.inkTertiary)
            }
            .lineLimit(1)

            Spacer(minLength: 8)

            Button(action: onAdd) {
                Image(systemName: "plus.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.phosphor)
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Add “\(suggestion.replacement)” to vocabulary")

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.inkSecondary)
                    .font(.system(size: 16, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Dismiss suggestion")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Palette.mtRaise2)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Palette.mtLine, lineWidth: 1)
                )
        )
    }
}
