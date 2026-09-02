import SwiftUI
import SwiftData
import UniformTypeIdentifiers
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

enum SortColumn {
    case original
    case replacement
}

// MARK: - WordReplacementView (P3.D)
//
// Glass-card entries with hover-revealed edit/delete + drag-handle reorder.
// Inline edit replaces the previous sheet (`EditReplacementSheet` retired).
// Reorder persistence: `WordReplacement.sortOrder` (per-row int). Drag
// implicitly switches sortMode → .manual so the new order survives reopen.

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
    @State private var draggedID: UUID? = nil

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

    private func toggleSort(for column: SortColumn) {
        switch column {
        case .original:
            sortMode = (sortMode == .originalAsc) ? .originalDesc : .originalAsc
        case .replacement:
            sortMode = (sortMode == .replacementAsc) ? .replacementDesc : .replacementAsc
        }
        persistSortMode()
    }

    private func setManualSort() {
        // If switching INTO manual from an alpha mode, snapshot the current
        // displayed order into `sortOrder` so what the user sees is what
        // sticks. Without this rebase the indices reflect whatever was last
        // persisted (legacy 0s or stale manual order) and the visible order
        // shifts at the moment Custom is re-engaged.
        if sortMode != .manual {
            rebaseManualOrder(from: sortedReplacements)
        }
        sortMode = .manual
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
                sortHeader
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sortedReplacements) { replacement in
                            ReplacementGlassCard(
                                replacement: replacement,
                                isEditing: editingReplacementID == replacement.id,
                                isDragging: draggedID == replacement.id,
                                canDrag: sortMode == .manual,
                                onBeginEdit: { editingReplacementID = replacement.id },
                                onCancelEdit: { editingReplacementID = nil },
                                onSaveEdit: { newOriginal, newReplacement in
                                    saveEdit(replacement, newOriginal: newOriginal, newReplacement: newReplacement)
                                },
                                onDelete: { removeReplacement(replacement) }
                            )
                            .onDrag {
                                draggedID = replacement.id
                                if sortMode != .manual {
                                    // setManualSort rebases from current
                                    // displayed order before flipping mode,
                                    // so the drop persists in the order the
                                    // user was looking at.
                                    setManualSort()
                                }
                                return NSItemProvider(object: replacement.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: ReorderDropDelegate(
                                    target: replacement,
                                    items: sortedReplacements,
                                    draggedID: $draggedID,
                                    onReorder: applyReorder
                                )
                            )
                        }
                    }
                    .padding(.horizontal, 2)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 360)
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

    // MARK: - Sort header

    private var sortHeader: some View {
        HStack(spacing: 8) {
            Button(action: setManualSort) {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11, weight: .medium))
                    Text("Custom")
                        .font(.microlabel(11))
                        .tracking(1.2)
                        .textCase(.uppercase)
                }
                .foregroundStyle(sortMode == .manual ? Palette.phosphor : Palette.inkSecondary)
            }
            .buttonStyle(.plain)
            .help("Manual order — drag handle to reorder")

            Divider().frame(height: 12).overlay(Palette.mtLine)

            Button(action: { toggleSort(for: .original) }) {
                HStack(spacing: 4) {
                    Text("Original")
                        .font(.microlabel(11))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.inkSecondary)
                    if sortMode == .originalAsc || sortMode == .originalDesc {
                        Image(systemName: sortMode == .originalAsc ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.phosphor)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Sort by original")

            Image(systemName: "arrow.right")
                .foregroundStyle(Palette.inkSecondary)
                .font(.system(size: 10))
                .frame(width: 10)

            Button(action: { toggleSort(for: .replacement) }) {
                HStack(spacing: 4) {
                    Text("Replacement")
                        .font(.microlabel(11))
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(Palette.inkSecondary)
                    if sortMode == .replacementAsc || sortMode == .replacementDesc {
                        Image(systemName: sortMode == .replacementAsc ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.phosphor)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Sort by replacement")

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
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

    private func removeReplacement(_ replacement: WordReplacement) {
        modelContext.delete(replacement)
        do {
            try modelContext.save()
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

    /// Apply a reorder by moving `dragged` to the slot just before `target`.
    private func applyReorder(dragged: WordReplacement, target: WordReplacement) {
        guard dragged.id != target.id else { return }
        var items = sortedReplacements
        guard
            let from = items.firstIndex(where: { $0.id == dragged.id }),
            let to = items.firstIndex(where: { $0.id == target.id })
        else { return }
        let item = items.remove(at: from)
        items.insert(item, at: to)
        for (idx, entry) in items.enumerated() {
            entry.sortOrder = idx
        }
        do {
            try modelContext.save()
        } catch {
            log.error("Failed to persist reorder: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - ReplacementGlassCard

/// Glass-wrapped row. Hover reveals edit/delete (alpha 0 → 1). Inline edit
/// swaps content to two TextFields + Save / Cancel.
private struct ReplacementGlassCard: View {
    @ObservedObject private var motion = AccessibilityMotionMonitor.shared
    @Environment(\.colorSchemeContrast) private var contrast
    let replacement: WordReplacement
    let isEditing: Bool
    let isDragging: Bool
    let canDrag: Bool
    let onBeginEdit: () -> Void
    let onCancelEdit: () -> Void
    let onSaveEdit: (String, String) -> Void
    let onDelete: () -> Void

    @State private var hovering: Bool = false
    @State private var draftOriginal: String = ""
    @State private var draftReplacement: String = ""
    /// Which row action holds keyboard focus. Non-nil reveals the pair, so Edit
    /// and Delete are reachable without a pointer (hover alone hid them from the
    /// keyboard and from VoiceOver activation).
    @FocusState private var focusedAction: RowAction?

    private enum RowAction: Hashable { case edit, delete }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        HStack(alignment: .center, spacing: 10) {
            dragHandle
            if isEditing {
                editingContent
            } else {
                displayContent
            }
        }
        .padding(12)
        .background(shape.fill(Palette.mtRaise))
        .overlay(shape.strokeBorder(A11y.borderColor(increaseContrast: contrast == .increased), lineWidth: 1))
        .opacity(isDragging ? 0.45 : 1.0)
        .onHover { hover in
            // Reduce Motion → snap to revealed/hidden; otherwise smooth fade.
            if motion.reduceMotion {
                hovering = hover
            } else {
                withAnimation(Animation.haloPhaseCrossfade) {
                    hovering = hover
                }
            }
        }
        .onChange(of: isEditing) { _, nowEditing in
            if nowEditing {
                draftOriginal = replacement.originalText
                draftReplacement = replacement.replacementText
            }
        }
    }

    // MARK: Pieces

    private var dragHandle: some View {
        // Drag is allowed in any sort — non-manual mode auto-rebases the
        // current display order into `sortOrder` and switches sortMode to
        // `.manual` on drag start. Tooltip surfaces that side-effect so the
        // dim handle doesn't suggest the action is gated.
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(canDrag ? Palette.inkSecondary : Palette.inkTertiary)
            .frame(width: 18)
            .help(canDrag
                  ? "Drag to reorder"
                  : "Drag to reorder (switches to Custom sort)")
    }

    private var displayContent: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(replacement.originalText)
                .font(.mono(13))
                .foregroundStyle(Palette.inkPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(Palette.inkSecondary)
                .font(.system(size: 10))
                .frame(width: 10)

            Text(replacement.replacementText)
                .font(.mono(13))
                .foregroundStyle(Palette.inkPrimary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            actionButtons
                .opacity(hovering || focusedAction != nil ? 1 : 0)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 6) {
            Button(action: onBeginEdit) {
                Image(systemName: "pencil.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.phosphor)
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .focused($focusedAction, equals: .edit)
            .help("Edit replacement")
            .accessibilityLabel("Edit replacement")

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.inkSecondary)
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .focused($focusedAction, equals: .delete)
            .help("Remove replacement")
            .accessibilityLabel("Remove replacement")
        }
    }

    private var editingContent: some View {
        HStack(alignment: .center, spacing: 8) {
            matteDraftField("Original", text: $draftOriginal)

            Image(systemName: "arrow.right")
                .foregroundStyle(Palette.inkSecondary)
                .font(.system(size: 10))
                .frame(width: 10)

            matteDraftField("Replacement", text: $draftReplacement, onSubmit: { onSaveEdit(draftOriginal, draftReplacement) })

            Button(action: { onSaveEdit(draftOriginal, draftReplacement) }) {
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.phosphor)
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(draftOriginal.trimmingCharacters(in: .whitespaces).isEmpty
                      || draftReplacement.trimmingCharacters(in: .whitespaces).isEmpty)
            .help("Save")

            Button(action: onCancelEdit) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.inkSecondary)
                    .font(.system(size: 16, weight: .medium))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Cancel")
        }
    }

    private func matteDraftField(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void = {}) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.mono(13))
            .foregroundStyle(Palette.inkPrimary)
            .onSubmit(onSubmit)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
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

// MARK: - ReorderDropDelegate

/// Per-row drop delegate. Triggers reorder once when the dragged item enters
/// a new target row. Stable enough for VStack + small lists (dictionary
/// rarely exceeds tens of entries).
private struct ReorderDropDelegate: DropDelegate {
    let target: WordReplacement
    let items: [WordReplacement]
    @Binding var draggedID: UUID?
    let onReorder: (WordReplacement, WordReplacement) -> Void

    func dropEntered(info: DropInfo) {
        guard
            let draggedID,
            draggedID != target.id,
            let dragged = items.first(where: { $0.id == draggedID })
        else { return }
        onReorder(dragged, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
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
