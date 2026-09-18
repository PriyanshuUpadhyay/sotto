import SwiftUI
import SwiftData
import os

private let log = Logger(subsystem: OSLogSubsystems.app, category: "Dictionary")

// MARK: - Sort modes

enum SortMode: String {
    case manual         = "manual"
    case originalAsc    = "originalAsc"
    case originalDesc   = "originalDesc"
    case replacementAsc = "replacementAsc"
    case replacementDesc = "replacementDesc"
}

// MARK: - WordReplacementView
//
// Native `List`: click / ⌘-click / ⇧-click selection, drag to reorder
// (`onMove`), double-click or Return to edit in place, Delete key or the
// context menu to remove. Reorder persistence: `WordReplacement.sortOrder`
// (per-row int). A drag switches sortMode → .manual so the new order survives
// reopen.

struct WordReplacementView: View {
    @Query private var wordReplacements: [WordReplacement]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var showAlert = false
    @State private var editingReplacementID: UUID? = nil
    @State private var alertMessage = ""
    @State private var sortMode: SortMode = .manual
    @State private var originalWord = ""
    @State private var replacementWord = ""
    @State private var showInfoPopover = false
    @State private var selection: Set<UUID> = []

    init() {
        if let savedSort = UserDefaults.standard.string(forKey: "wordReplacementSortMode"),
           let mode = SortMode(rawValue: savedSort) {
            _sortMode = State(initialValue: mode)
        }
    }

    private var sortedReplacements: [WordReplacement] {
        switch sortMode {
        case .manual:
            // Stable manual order: primary by sortOrder, fallback by dateAdded
            // for legacy rows where everyone has sortOrder == 0.
            return wordReplacements.sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.dateAdded < $1.dateAdded
            }
        case .originalAsc:
            return wordReplacements.sorted { $0.originalText.localizedCaseInsensitiveCompare($1.originalText) == .orderedAscending }
        case .originalDesc:
            return wordReplacements.sorted { $0.originalText.localizedCaseInsensitiveCompare($1.originalText) == .orderedDescending }
        case .replacementAsc:
            return wordReplacements.sorted { $0.replacementText.localizedCaseInsensitiveCompare($1.replacementText) == .orderedAscending }
        case .replacementDesc:
            return wordReplacements.sorted { $0.replacementText.localizedCaseInsensitiveCompare($1.replacementText) == .orderedDescending }
        }
    }

    private func setSortMode(_ mode: SortMode) {
        // Switching INTO manual from an alpha mode snapshots the displayed
        // order into `sortOrder`, so what the user sees is what sticks.
        if mode == .manual && sortMode != .manual {
            rebaseManualOrder(from: sortedReplacements)
        }
        sortMode = mode
        persistSortMode()
    }

    private func persistSortMode() {
        UserDefaults.standard.set(sortMode.rawValue, forKey: "wordReplacementSortMode")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: { showInfoPopover.toggle() }) {
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.phosphor)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showInfoPopover) {
                    WordReplacementInfoPopover()
                }
                Text("Define word replacements to automatically replace specific words or phrases")
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

            HStack(spacing: 8) {
                matteField("Original text (use commas for multiple)", text: $originalWord)

                Image(systemName: "arrow.right")
                    .foregroundStyle(Palette.inkSecondary)
                    .font(.system(size: 10))
                    .frame(width: 10)

                matteField("Replacement text", text: $replacementWord, onSubmit: addReplacement)

                // Present at all times: inserting the button on the first
                // keystroke resized the fields under the caret mid-typing.
                Button(action: addReplacement) {
                    Image(systemName: "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Palette.phosphor)
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .disabled(originalWord.isEmpty || replacementWord.isEmpty)
                .opacity(originalWord.isEmpty || replacementWord.isEmpty ? 0.35 : 1)
                .help("Add word replacement")
                .accessibilityLabel("Add word replacement")
            }

            if !wordReplacements.isEmpty {
                listHeader
                List(selection: $selection) {
                    ForEach(sortedReplacements) { replacement in
                        ReplacementRow(
                            replacement: replacement,
                            isEditing: editingReplacementID == replacement.id,
                            onCancelEdit: { editingReplacementID = nil },
                            onSaveEdit: { newOriginal, newReplacement in
                                saveEdit(replacement, newOriginal: newOriginal, newReplacement: newReplacement)
                            }
                        )
                    }
                    .onMove(perform: move)
                }
                .listStyle(.inset)
                // The page is one scroll view, so the list needs a set height.
                .frame(height: min(360, CGFloat(wordReplacements.count) * 28 + 16))
                .contextMenu(forSelectionType: UUID.self) { ids in
                    if ids.count == 1, let id = ids.first {
                        Button("Edit") { editingReplacementID = id }
                    }
                    Button("Delete", role: .destructive) { removeReplacements(ids) }
                } primaryAction: { ids in
                    // Double-click or Return edits in place.
                    if ids.count == 1 { editingReplacementID = ids.first }
                }
                .onDeleteCommand { removeReplacements(selection) }
            }
        }
        .padding()
        .alert("Word Replacement", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Matte field

    private func matteField(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.mono(13))
            .foregroundStyle(Palette.inkPrimary)
            .onSubmit(onSubmit)
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

    // MARK: - List header

    private var listHeader: some View {
        HStack(spacing: 8) {
            Picker("Sort", selection: Binding(get: { sortMode }, set: { setSortMode($0) })) {
                Text("Custom Order").tag(SortMode.manual)
                Divider()
                Text("Original A–Z").tag(SortMode.originalAsc)
                Text("Original Z–A").tag(SortMode.originalDesc)
                Text("Replacement A–Z").tag(SortMode.replacementAsc)
                Text("Replacement Z–A").tag(SortMode.replacementDesc)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .help("Drag rows to set a custom order")

            Spacer()

            Button("Remove", systemImage: "minus") { removeReplacements(selection) }
                .disabled(selection.isEmpty)
                .help("Remove the selected replacements")
        }
        .controlSize(.small)
    }

    // MARK: - Mutations

    private func addReplacement() {
        let original = originalWord.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacementWord.trimmingCharacters(in: .whitespacesAndNewlines)
        // Compute the next manual-order slot upfront, pass through the
        // service so the entry is constructed with the correct sortOrder
        // in a single save (avoids race-prone post-insert lookup that
        // would silently drop new rows to sortOrder 0 if the @Query
        // hadn't yet reflected the insert under CloudKit).
        let nextOrder = (wordReplacements.map(\.sortOrder).max() ?? 0) + 1
        if let error = DictionaryService.addWordReplacement(
            original: original,
            replacement: replacement,
            existing: Array(wordReplacements),
            context: modelContext,
            sortOrder: nextOrder
        ) {
            alertMessage = error
            showAlert = true
            return
        }
        originalWord = ""
        replacementWord = ""
    }

    private func removeReplacements(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for replacement in wordReplacements where ids.contains(replacement.id) {
            modelContext.delete(replacement)
        }
        do {
            try modelContext.save()
            selection.subtract(ids)
        } catch {
            modelContext.rollback()
            alertMessage = "Failed to remove replacement: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func saveEdit(_ replacement: WordReplacement, newOriginal: String, newReplacement: String) {
        let trimmedOriginal = newOriginal.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReplacement = newReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmedOriginal
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty, !trimmedReplacement.isEmpty else { return }

        // Duplicate guard — same logic as legacy sheet.
        let newTokensLower = tokens.map { $0.lowercased() }
        for existing in wordReplacements where existing.id != replacement.id {
            let existingTokens = existing.originalText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
            if let clash = newTokensLower.first(where: { existingTokens.contains($0) }) {
                alertMessage = "'\(clash)' already exists in word replacements"
                showAlert = true
                return
            }
        }

        replacement.originalText = trimmedOriginal
        replacement.replacementText = trimmedReplacement
        do {
            try modelContext.save()
            editingReplacementID = nil
        } catch {
            alertMessage = "Failed to save changes: \(error.localizedDescription)"
            showAlert = true
        }
    }

    // MARK: - Reorder helpers

    /// Snapshot the current displayed order into `sortOrder` so the manual
    /// baseline matches what the user sees before they drag.
    private func rebaseManualOrder(from items: [WordReplacement]) {
        for (idx, item) in items.enumerated() {
            item.sortOrder = idx
        }
        do {
            try modelContext.save()
        } catch {
            log.error("Failed to rebase manual order: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Native drag reorder. Works in any sort: the displayed order becomes the
    /// manual order, and the sort switches to Custom so it sticks.
    private func move(from source: IndexSet, to destination: Int) {
        var items = sortedReplacements
        items.move(fromOffsets: source, toOffset: destination)
        for (idx, entry) in items.enumerated() {
            entry.sortOrder = idx
        }
        sortMode = .manual
        persistSortMode()
        do {
            try modelContext.save()
        } catch {
            log.error("Failed to persist reorder: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - ReplacementRow

/// One `original → replacement` row. Editing swaps in two text fields;
/// Return saves, Escape cancels.
private struct ReplacementRow: View {
    let replacement: WordReplacement
    let isEditing: Bool
    let onCancelEdit: () -> Void
    let onSaveEdit: (String, String) -> Void

    @State private var draftOriginal: String = ""
    @State private var draftReplacement: String = ""

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isEditing {
                editingContent
            } else {
                displayContent
            }
        }
        .padding(.vertical, 2)
        .onChange(of: isEditing) { _, nowEditing in
            if nowEditing {
                draftOriginal = replacement.originalText
                draftReplacement = replacement.replacementText
            }
        }
    }

    private var displayContent: some View {
        Group {
            Text(replacement.originalText)
                .font(.mono(13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .font(.system(size: 10))

            Text(replacement.replacementText)
                .font(.mono(13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var editingContent: some View {
        Group {
            TextField("Original", text: $draftOriginal)
                .onSubmit { onSaveEdit(draftOriginal, draftReplacement) }

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
                .font(.system(size: 10))

            TextField("Replacement", text: $draftReplacement)
                .onSubmit { onSaveEdit(draftOriginal, draftReplacement) }

            Button("Save") { onSaveEdit(draftOriginal, draftReplacement) }
                .disabled(draftOriginal.trimmingCharacters(in: .whitespaces).isEmpty
                          || draftReplacement.trimmingCharacters(in: .whitespaces).isEmpty)

            Button("Cancel", action: onCancelEdit)
                .keyboardShortcut(.cancelAction)
        }
        .textFieldStyle(.roundedBorder)
        .font(.mono(13))
        .controlSize(.small)
    }
}

// MARK: - Info popover (unchanged)

struct WordReplacementInfoPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How to use Word Replacements")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.inkPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Separate multiple originals with commas:")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.inkSecondary)

                Text("Voicing, Voice ink, Voiceing")
                    .font(.mono(12))
                    .foregroundStyle(Palette.inkPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(codeChip)
            }

            Divider().overlay(Palette.mtLine)

            Text("Examples")
                .font(.system(size: 12))
                .foregroundStyle(Palette.inkSecondary)

            VStack(spacing: 12) {
                exampleRow(original: "my website link", replacement: "https://example.com")
                exampleRow(original: "Voicing, Voice ink", replacement: "Sotto")
            }
        }
        .padding()
        .frame(width: 380)
        .background(Palette.mtRaise)
    }

    private var codeChip: some View {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .fill(Palette.mtRaise2)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Palette.mtLine, lineWidth: 1)
            )
    }

    private func exampleRow(original: String, replacement: String) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Original:")
                    .font(.microlabel(9.5))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkSecondary)
                Text(original)
                    .font(.mono(12))
                    .foregroundStyle(Palette.inkPrimary)
            }

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Replacement:")
                    .font(.microlabel(9.5))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.inkSecondary)
                Text(replacement)
                    .font(.mono(12))
                    .foregroundStyle(Palette.inkPrimary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(codeChip)
    }
}
