import SwiftUI
import SwiftData
import KeyboardShortcuts
import AppKit

struct InlineHistoryView: View {
    /// The transcript the triptych shell currently has selected (drives the row
    /// highlight). `nil` when the view is used standalone (no inspector).
    var selectedID: UUID? = nil
    /// Emitted when a row is chosen, so the triptych inspector can inspect it.
    var onSelect: ((Transcription) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @State private var searchText = ""
    @State private var expandedId: UUID?
    @State private var selectedTranscriptions: Set<Transcription> = []
    @State private var showDeleteConfirmation = false
    /// A single-row delete waits out `undoWindowSeconds` before it touches the
    /// database or the audio file: the row hides immediately, an UNDO toast
    /// stands, and only then is the deletion committed. Bulk delete keeps its
    /// confirmation instead.
    @State private var pendingDeletion: Transcription?
    @State private var undoWindow: Task<Void, Never>?
    @State private var isPanelPresented = false
    @State private var panelTranscriptionId: UUID?
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?
    @State private var isViewCurrentlyVisible = false

    // Keyboard-first navigation cursor (distinct from checkbox selection + expansion).
    @State private var focusedId: UUID?
    @State private var searchDebounce: Task<Void, Never>?
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool

    private let exportService = SottoCSVExportService()
    private let pageSize = 20
    private static let undoWindowSeconds: TimeInterval = 5

    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]

    private static func createLatestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\Transcription.timestamp, order: .reverse)]
        )

        if let timestamp = timestamp {
            if !searchText.isEmpty {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    (transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)) &&
                    transcription.timestamp < timestamp
                }
            } else {
                descriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.timestamp < timestamp
                }
            }
        } else if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }

        descriptor.fetchLimit = pageSize
        return descriptor
    }

    private var allSelected: Bool {
        !displayedTranscriptions.isEmpty && displayedTranscriptions.allSatisfy { selectedTranscriptions.contains($0) }
    }

    private var panelTranscription: Transcription? {
        guard let id = panelTranscriptionId else { return nil }
        return displayedTranscriptions.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            HistoryTopBar(
                searchText: $searchText,
                searchFocused: $searchFocused
            )

            if displayedTranscriptions.isEmpty && !isLoading {
                emptyStateView
            } else {
                cardListView
            }

            if !selectedTranscriptions.isEmpty {
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Animation.haloPhaseCrossfade, value: selectedTranscriptions.isEmpty)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .background {
            // Global ⌘F focuses search even when the list isn't the key view.
            // Scoped to ⌘F only — ⌘C/⌘⌫ stay on the focused list (onKeyPress)
            // so they don't shadow text-field copy / expanded-text selection.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .overlay {
            Color.black.opacity(isPanelPresented ? 0.1 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(isPanelPresented)
                .onTapGesture {
                    withAnimation(Animation.haloExpand) {
                        isPanelPresented = false
                    }
                }
                .animation(Animation.haloExpand, value: isPanelPresented)
        }
        .overlay(alignment: .trailing) {
            if isPanelPresented {
                panelContent
                    .frame(width: 400)
                    .frame(maxHeight: .infinity)
                    .background(Theme.Material.panel)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.separator)
                            .frame(width: 1)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 8, x: -2, y: 0)
                    .ignoresSafeArea()
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(Animation.haloExpand, value: isPanelPresented)
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete \(selectedTranscriptions.count) item\(selectedTranscriptions.count == 1 ? "" : "s")?")
        }
        .onAppear {
            isViewCurrentlyVisible = true
            Task { await loadInitialContent() }
        }
        .onDisappear {
            isViewCurrentlyVisible = false
            // Leaving the surface ends the undo window — the delete stands.
            commitPendingDeletion()
        }
        .onChange(of: searchText) { _, _ in
            // Debounce the SwiftData fetch ~250ms so we don't refetch per keystroke.
            searchDebounce?.cancel()
            searchDebounce = Task {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await resetPagination()
                await loadInitialContent()
            }
        }
        .onChange(of: latestTranscriptionIndicator.first?.id) { oldId, newId in
            guard isViewCurrentlyVisible else { return }
            if newId != oldId {
                Task {
                    await resetPagination()
                    await loadInitialContent()
                }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 16) {
            Text("\(selectedTranscriptions.count) selected")
                .font(.system(size: 13, weight: .medium))
                .tabularNumbers()
                .foregroundColor(.secondary)

            Spacer()

            Button(action: {
                exportService.exportTranscriptionsToCSV(transcriptions: Array(selectedTranscriptions))
            }) {
                Label("Export", systemImage: "square.and.arrow.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button(action: { showDeleteConfirmation = true }) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(Palette.recRed.opacity(0.8))

            Divider()
                .frame(height: 16)

            if allSelected {
                Button("Deselect All") {
                    selectedTranscriptions.removeAll()
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Button("Select All") {
                    Task { await selectAllTranscriptions() }
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Theme.Material.chrome)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.separator)
                .frame(height: 1)
        }
        .shadow(color: Color.black.opacity(0.1), radius: 3, y: -2)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        if searchText.isEmpty {
            coachingEmptyState
        } else {
            searchEmptyState
        }
    }

    /// Failed-search variant — distinct from first-run coaching: no hotkey
    /// teaching, just a "narrow your query" nudge on semantic ink tokens.
    private var searchEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(Theme.inkTertiary)
            Text("No results found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
            Text("Try a different search term")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Genuinely-empty history → first-run activation surface. Teaches the core
    /// press·speak·release gesture against the user's *actual* bound dictation
    /// hotkey (rendered as KeyCaps). If no hotkey is bound, swaps the lesson for
    /// an Acid-Lime CTA that deep-links to Shortcuts settings.
    private var coachingEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "waveform")
                .font(.system(size: 38, weight: .light))
                .foregroundColor(Theme.inkTertiary)

            VStack(spacing: 6) {
                Text("Start dictating")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                Text("Your transcriptions will appear here.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            if dictationGlyphs.isEmpty {
                Button {
                    openShortcutsSettings()
                } label: {
                    Text("Set a dictation shortcut")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                }
                .buttonStyle(LimeFillButtonStyle())
                .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Text("Hold")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        KeyCombo(keys: dictationGlyphs)
                        Text("to dictate")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Text("press · speak · release")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.inkTertiary)
                }
                .padding(.top, 4)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Unicode key-cap glyphs for the *primary* dictation hotkey
    /// (`selectedHotkey1`). Empty ⇒ no hotkey bound. Shared with the onboarding
    /// shortcut step and the first-run reminder toast.
    private var dictationGlyphs: [String] {
        HotkeyManager.dictationGlyphs(for: hotkeyManager.selectedHotkey1)
    }

    private func openShortcutsSettings() {
        // Staged via the coordinator — a bare notification is lossy when
        // SettingsContentView isn't mounted yet.
        SottoWindowCoordinator.shared.open(settingsTab: .shortcuts)
    }

    // MARK: - Card List

    private var cardListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(displayedTranscriptions) { transcription in
                        HistoryCardRow(
                            transcription: transcription,
                            isExpanded: expandedId == transcription.id,
                            isChecked: selectedTranscriptions.contains(transcription),
                            isFocused: focusedId == transcription.id,
                            isSelected: selectedID == transcription.id,
                            onToggleExpand: {
                                onSelect?(transcription)
                                withAnimation(Animation.haloPhaseCrossfade) {
                                    expandedId = expandedId == transcription.id ? nil : transcription.id
                                }
                            },
                            onToggleCheck: { toggleSelection(transcription) },
                            onShowInfo: {
                                panelTranscriptionId = transcription.id
                                withAnimation(Animation.haloExpand) {
                                    isPanelPresented = true
                                }
                            },
                            onExportAudio: {
                                exportService.exportTranscriptionsToCSV(transcriptions: [transcription])
                            },
                            onDelete: { deleteSingle(transcription) }
                        )
                        .cardSurface(isSelected: selectedID == transcription.id)
                        // Brand focus ring — matches the card radius, distinct
                        // from hover (fill lift) and checkbox-checked (circular toggle).
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                .strokeBorder(Brand.tint, lineWidth: 2)
                                .opacity(focusedId == transcription.id ? 1 : 0)
                        }
                        .id(transcription.id)
                    }

                    if hasMoreContent {
                        Button(action: {
                            Task { await loadMoreContent() }
                        }) {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView().controlSize(.small)
                                }
                                Text(isLoading ? "Loading..." : "Load More")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)
                        .cardSurface()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .focusable(true)
            .focused($listFocused)
            .onKeyPress { keyPress in
                handleKeyPress(keyPress, proxy: proxy)
            }
            .onReceive(NotificationCenter.default.publisher(for: .focusTranscription)) { note in
                guard let id = note.userInfo?["id"] as? UUID else { return }
                focusedId = id
                // Defer so the list has the row laid out before we scroll.
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Keyboard Navigation

    private func moveFocus(by delta: Int, proxy: ScrollViewProxy) {
        guard !displayedTranscriptions.isEmpty else { return }
        let ids = displayedTranscriptions.map { $0.id }
        let newIndex: Int
        if let current = focusedId, let ci = ids.firstIndex(of: current) {
            newIndex = max(0, min(ids.count - 1, ci + delta))
        } else {
            newIndex = delta > 0 ? 0 : ids.count - 1
        }
        focusedId = ids[newIndex]
        // Keep the triptych inspector in lock-step with the keyboard cursor: an
        // arrow move selects the focused transcript so the inspector (⌘I pane)
        // re-targets it, mirroring a click. No-op when used standalone (onSelect nil).
        onSelect?(displayedTranscriptions[newIndex])
        if reduceMotion {
            proxy.scrollTo(ids[newIndex], anchor: .center)
        } else {
            withAnimation(Animation.haloPhaseCrossfade) {
                proxy.scrollTo(ids[newIndex], anchor: .center)
            }
        }
    }

    private func handleKeyPress(_ keyPress: KeyPress, proxy: ScrollViewProxy) -> KeyPress.Result {
        let cmd = keyPress.modifiers.contains(.command)

        switch keyPress.key {
        case .downArrow:
            moveFocus(by: 1, proxy: proxy)
            return .handled
        case .upArrow:
            moveFocus(by: -1, proxy: proxy)
            return .handled
        case .return:
            guard let id = focusedId else { return .ignored }
            withAnimation(Animation.haloPhaseCrossfade) {
                expandedId = expandedId == id ? nil : id
            }
            return .handled
        case .escape:
            return handleEscape()
        case .delete:
            guard cmd else { return .ignored }
            handleDeleteKey()
            return .handled
        default:
            break
        }

        guard cmd else { return .ignored }
        let chars = keyPress.characters.isEmpty ? String(keyPress.key.character) : keyPress.characters
        switch chars.lowercased() {
        case "c":
            copyForKeyboard()
            return .handled
        case "a":
            Task { await selectAllTranscriptions() }
            return .handled
        case "f":
            searchFocused = true
            return .handled
        default:
            return .ignored
        }
    }

    private func handleEscape() -> KeyPress.Result {
        if !searchText.isEmpty {
            searchText = ""
            return .handled
        }
        if isPanelPresented {
            withAnimation(Animation.haloExpand) {
                isPanelPresented = false
            }
            return .handled
        }
        if expandedId != nil {
            withAnimation(Animation.haloPhaseCrossfade) { expandedId = nil }
            return .handled
        }
        if !selectedTranscriptions.isEmpty || focusedId != nil {
            selectedTranscriptions.removeAll()
            focusedId = nil
            return .handled
        }
        return .ignored
    }

    private func copyForKeyboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if !selectedTranscriptions.isEmpty {
            let joined = selectedTranscriptions
                .sorted { $0.timestamp > $1.timestamp }
                .map { $0.enhancedText ?? $0.text }
                .joined(separator: "\n\n")
            pasteboard.setString(joined, forType: .string)
        } else if let id = focusedId,
                  let transcription = displayedTranscriptions.first(where: { $0.id == id }) {
            pasteboard.setString(transcription.enhancedText ?? transcription.text, forType: .string)
        }
    }

    private func handleDeleteKey() {
        if !selectedTranscriptions.isEmpty {
            showDeleteConfirmation = true
            return
        }
        guard let id = focusedId,
              let transcription = displayedTranscriptions.first(where: { $0.id == id }) else { return }
        // Pick the next cursor target BEFORE the delete reloads the list.
        let ids = displayedTranscriptions.map { $0.id }
        if let idx = ids.firstIndex(of: id) {
            if idx < ids.count - 1 {
                focusedId = ids[idx + 1]
            } else if idx > 0 {
                focusedId = ids[idx - 1]
            } else {
                focusedId = nil
            }
        }
        deleteSingle(transcription)
    }

    // MARK: - Sliding Panel

    private var panelContent: some View {
        infoPanelContent
    }

    private var infoPanelContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Info")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Button(action: {
                    withAnimation(Animation.haloExpand) {
                        isPanelPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(Divider().opacity(0.5), alignment: .bottom)
            .zIndex(1)

            if let transcription = panelTranscription {
                TranscriptionInfoPanel(transcription: transcription)
                    .id(transcription.id)
            } else {
                Spacer()
            }
        }
    }

    // MARK: - Data Loading

    @MainActor
    private func loadInitialContent() async {
        isLoading = true
        defer { isLoading = false }

        do {
            lastTimestamp = nil
            let items = try modelContext.fetch(cursorQueryDescriptor())
            displayedTranscriptions = items.filter { $0.id != pendingDeletion?.id }
            lastTimestamp = items.last?.timestamp
            hasMoreContent = items.count == pageSize
        } catch {
            print("Error loading transcriptions: \(error)")
        }
    }

    @MainActor
    private func loadMoreContent() async {
        guard !isLoading, hasMoreContent, let lastTimestamp = lastTimestamp else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let newItems = try modelContext.fetch(cursorQueryDescriptor(after: lastTimestamp))
            displayedTranscriptions.append(contentsOf: newItems.filter { $0.id != pendingDeletion?.id })
            self.lastTimestamp = newItems.last?.timestamp
            hasMoreContent = newItems.count == pageSize
        } catch {
            print("Error loading more transcriptions: \(error)")
        }
    }

    @MainActor
    private func resetPagination() {
        displayedTranscriptions = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    // MARK: - Selection & Deletion

    private func toggleSelection(_ transcription: Transcription) {
        if selectedTranscriptions.contains(transcription) {
            selectedTranscriptions.remove(transcription)
        } else {
            selectedTranscriptions.insert(transcription)
        }
    }

    private func performDeletion(for transcription: Transcription) {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                print("Error deleting audio file: \(error.localizedDescription)")
            }
        }

        if expandedId == transcription.id {
            expandedId = nil
        }
        if panelTranscriptionId == transcription.id {
            panelTranscriptionId = nil
            isPanelPresented = false
        }

        selectedTranscriptions.remove(transcription)
        modelContext.delete(transcription)
    }

    private func deleteSelectedTranscriptions() {
        for transcription in selectedTranscriptions {
            performDeletion(for: transcription)
        }
        selectedTranscriptions.removeAll()

        Task {
            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
                await loadInitialContent()
            } catch {
                print("Error saving deletion: \(error.localizedDescription)")
                await loadInitialContent()
            }
        }
    }

    /// One row, one keypress: no modal. The row leaves the list at once and an
    /// UNDO toast stands for `undoWindowSeconds`; the transcript and its audio
    /// file survive until that window closes.
    private func deleteSingle(_ transcription: Transcription) {
        // At most one undo window is open — an earlier pending delete stands.
        commitPendingDeletion()

        if expandedId == transcription.id { expandedId = nil }
        if panelTranscriptionId == transcription.id {
            panelTranscriptionId = nil
            isPanelPresented = false
        }
        selectedTranscriptions.remove(transcription)

        pendingDeletion = transcription
        displayedTranscriptions.removeAll { $0.id == transcription.id }

        undoWindow = Task {
            try? await Task.sleep(for: .seconds(Self.undoWindowSeconds))
            guard !Task.isCancelled else { return }
            commitPendingDeletion()
        }

        NotificationManager.shared.showNotification(
            title: "Deleted 1 transcription",
            type: .info,
            duration: Self.undoWindowSeconds,
            actionButton: (label: "UNDO", action: { undoPendingDeletion() })
        )
    }

    /// Ends the undo window and performs the deferred deletion for real.
    @MainActor
    private func commitPendingDeletion() {
        undoWindow?.cancel()
        undoWindow = nil
        guard let transcription = pendingDeletion else { return }
        pendingDeletion = nil

        performDeletion(for: transcription)
        Task {
            do {
                try modelContext.save()
                NotificationCenter.default.post(name: .transcriptionDeleted, object: nil)
            } catch {
                print("Error saving deletion: \(error.localizedDescription)")
            }
            await loadInitialContent()
        }
    }

    /// Cancels the pending deletion — nothing was removed yet, so the row simply
    /// comes back on the next load.
    @MainActor
    private func undoPendingDeletion() {
        undoWindow?.cancel()
        undoWindow = nil
        guard pendingDeletion != nil else { return }
        pendingDeletion = nil
        Task { await loadInitialContent() }
    }

    private func selectAllTranscriptions() async {
        do {
            var allDescriptor = FetchDescriptor<Transcription>()

            if !searchText.isEmpty {
                allDescriptor.predicate = #Predicate<Transcription> { transcription in
                    transcription.text.localizedStandardContains(searchText) ||
                    (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
                }
            }

            allDescriptor.propertiesToFetch = [\.id]
            let allTranscriptions = try modelContext.fetch(allDescriptor)
            let visibleIds = Set(displayedTranscriptions.map { $0.id })

            await MainActor.run {
                selectedTranscriptions = Set(displayedTranscriptions)

                for transcription in allTranscriptions {
                    if !visibleIds.contains(transcription.id) {
                        selectedTranscriptions.insert(transcription)
                    }
                }
            }
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }
}

// MARK: - History Card Row

private struct HistoryCardRow: View {
    let transcription: Transcription
    let isExpanded: Bool
    let isChecked: Bool
    let isFocused: Bool
    var isSelected: Bool = false
    let onToggleExpand: () -> Void
    let onToggleCheck: () -> Void
    let onShowInfo: () -> Void
    let onExportAudio: () -> Void
    let onDelete: () -> Void

    @State private var selectedTab: TranscriptionTab = .original

    private var displayText: String {
        switch selectedTab {
        case .original:
            return transcription.text
        case .enhanced:
            return transcription.enhancedText ?? ""
        }
    }

    private var hasAudioFile: Bool {
        if let urlString = transcription.audioFileURL,
           let url = URL(string: urlString),
           FileManager.default.fileExists(atPath: url.path) {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { isChecked },
                    set: { _ in onToggleCheck() }
                ))
                .toggleStyle(CircularCheckboxStyle())
                .labelsHidden()

                // The expand area excludes the checkbox so clicking the checkbox
                // toggles selection only. The parent ScrollView is `.focusable`
                // for keyboard nav, which swallows a plain `.onTapGesture` here
                // (clicks only ever focused the list) — `.simultaneousGesture`
                // co-recognizes with that focus grab, so a single click both
                // expands the row AND focuses the list for subsequent keys.
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.mono(11))
                            .tabularNumbers()
                            .foregroundStyle(Palette.inkSecondary)

                        if !isExpanded {
                            Text(transcription.enhancedText ?? transcription.text)
                                .font(.system(size: 13))
                                .lineLimit(2)
                                .foregroundStyle(Palette.inkPrimary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(Theme.inkTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(Animation.haloPhaseCrossfade, value: isExpanded)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { onToggleExpand() })
            }
            .contextMenu {
                Button("Copy Original") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(transcription.text, forType: .string)
                }
                if let enhanced = transcription.enhancedText, !enhanced.isEmpty {
                    Button("Copy Enhanced") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(enhanced, forType: .string)
                    }
                }
                if hasAudioFile {
                    Button("Export Audio") { onExportAudio() }
                }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }

            if isExpanded {
                expandedContent
                    .padding(.top, 10)
            }
        }
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tabs
            if transcription.enhancedText != nil {
                HStack(spacing: 4) {
                    ForEach(TranscriptionTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(Animation.haloPhaseCrossfade) {
                                selectedTab = tab
                            }
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Theme.groupedBackground : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }

            ScrollView {
                Text(displayText)
                    .font(.body)
                    .foregroundColor(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 350)
            .overlay(alignment: .bottomTrailing) {
                CopyIconButton(textToCopy: displayText)
                    .padding(8)
            }

            if hasAudioFile, let urlString = transcription.audioFileURL,
               let url = URL(string: urlString) {
                Divider()
                AudioPlayerView(url: url, transcription: transcription, onInfoTap: onShowInfo)
                .padding(.vertical, 4)
            } else {
                HStack {
                    Spacer()
                    Button(action: onShowInfo) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("View details")
                }
            }
        }
    }

}

// MARK: - Card Surface

/// Native, appearance-adaptive card treatment for History rows: a `panel`
/// material fill, `Theme.separator` edge, `Radius.card` continuous corners.
/// Hover lifts the fill with a subtle ink overlay so rows read as interactive.
private struct CardSurfaceBackground: ViewModifier {
    var cornerRadius: CGFloat = Radius.card
    var padding: CGFloat = 14
    var isSelected: Bool = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .padding(padding)
            .background(shape.fill(isSelected ? Theme.selectedRow : Theme.panel))
            .overlay(shape.fill(Theme.inkPrimary.opacity(hovering && !isSelected ? 0.04 : 0)))
            .overlay(shape.strokeBorder(isSelected ? Theme.hairlineStrong : Theme.hairline, lineWidth: 1))
            .onHover { hovering = $0 }
    }
}

private extension View {
    func cardSurface(cornerRadius: CGFloat = Radius.card, isSelected: Bool = false) -> some View {
        modifier(CardSurfaceBackground(cornerRadius: cornerRadius, isSelected: isSelected))
    }
}

