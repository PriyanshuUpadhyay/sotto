import SwiftUI
import SwiftData
import AppKit

/// History list on native controls: `List(selection:)` owns click, ⌘/⇧-click,
/// arrow keys and ⌘A; `DisclosureGroup` owns expand/collapse; the Edit menu
/// commands (Copy, Delete) and the context menu act on the selection.
struct InlineHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @State private var searchText = ""
    /// Can hold rows past the loaded page after "Select All", so bulk actions
    /// fetch by id instead of reading `displayedTranscriptions`.
    @State private var selection: Set<UUID> = []
    @State private var expandedIds: Set<UUID> = []
    @State private var showDeleteConfirmation = false
    /// A single-row delete waits out `undoWindowSeconds` before it touches the
    /// database or the audio file: the row hides immediately, an UNDO toast
    /// stands, and only then is the deletion committed. Bulk delete keeps its
    /// confirmation instead.
    @State private var pendingDeletion: Transcription?
    @State private var undoWindow: Task<Void, Never>?
    @State private var inspectedId: UUID?
    @State private var displayedTranscriptions: [Transcription] = []
    @State private var isLoading = false
    @State private var hasMoreContent = true
    @State private var lastTimestamp: Date?
    @State private var isViewCurrentlyVisible = false
    /// Every row the current search matches, not just the loaded page — "Select
    /// All" selects all of them, so the control has to say so.
    @State private var totalMatchingCount = 0
    @State private var searchDebounce: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

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

    /// Unpaginated twin of `cursorQueryDescriptor` — the scope "Select All"
    /// actually covers.
    private func matchingDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>()
        if !searchText.isEmpty {
            descriptor.predicate = #Predicate<Transcription> { transcription in
                transcription.text.localizedStandardContains(searchText) ||
                (transcription.enhancedText?.localizedStandardContains(searchText) ?? false)
            }
        }
        return descriptor
    }

    private var inspectedTranscription: Transcription? {
        guard let id = inspectedId else { return nil }
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
                listView
            }

            if selection.count > 1 {
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Animation.haloPhaseCrossfade, value: selection.count > 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .background {
            // ⌘F focuses search even when the list isn't the key view.
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .inspector(isPresented: Binding(
            get: { inspectedId != nil },
            set: { if !$0 { inspectedId = nil } }
        )) {
            inspectorContent
                .inspectorColumnWidth(min: 300, ideal: 380)
        }
        .alert("Delete Selected Items?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteSelectedTranscriptions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone. Are you sure you want to delete \(selection.count) item\(selection.count == 1 ? "" : "s")?")
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
            Text("\(selection.count) selected")
                .font(.system(size: 13, weight: .medium))
                .tabularNumbers()
                .foregroundColor(.secondary)

            Spacer()

            Button(action: { exportService.exportTranscriptionsToCSV(transcriptions: transcriptions(for: selection)) }) {
                Label("Export", systemImage: "square.and.arrow.up")
            }

            Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                Label("Delete", systemImage: "trash")
            }

            Divider()
                .frame(height: 16)

            if selection.count < totalMatchingCount {
                Button("Select All (\(totalMatchingCount))") { selectAllMatching() }
            } else {
                Button("Deselect All") { selection.removeAll() }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
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
                        .foregroundColor(Theme.inkSecondary)
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

    // MARK: - List

    /// Day sections over the WHOLE assembled list, so a day that continues past
    /// a "Load More" grows its section instead of repeating its label.
    private var daySections: [HistoryDayGrouping.Section<Transcription>] {
        HistoryDayGrouping.sections(displayedTranscriptions) { $0.timestamp }
    }

    private var listView: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(daySections, id: \.day) { section in
                    Section(HistoryDayGrouping.label(for: section.day)) {
                        ForEach(section.rows) { transcription in
                            HistoryRow(
                                transcription: transcription,
                                isExpanded: expansionBinding(for: transcription.id),
                                onShowInfo: { inspectedId = transcription.id }
                            )
                        }
                    }
                }

                if hasMoreContent {
                    Button(isLoading ? "Loading…" : "Load More") {
                        Task { await loadMoreContent() }
                    }
                    .disabled(isLoading)
                    .frame(maxWidth: .infinity)
                    .selectionDisabled()
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, 8, for: .scrollContent)
            .contentMargins(.vertical, 10, for: .scrollContent)
            // One panel in the stats cards' surface, inset from the window edges.
            .background(Theme.panel)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contextMenu(forSelectionType: UUID.self) { ids in
                rowMenu(for: ids)
            } primaryAction: { ids in
                // Double-click or Return on the selection.
                withAnimation(reduceMotion ? nil : .default) {
                    expandedIds.formSymmetricDifference(ids)
                }
            }
            .onCopyCommand {
                selection.isEmpty ? [] : [NSItemProvider(object: joinedText(for: selection) as NSString)]
            }
            .onDeleteCommand { requestDelete(selection) }
            .onExitCommand { handleEscape() }
            .onReceive(NotificationCenter.default.publisher(for: .focusTranscription)) { note in
                guard let id = note.userInfo?["id"] as? UUID else { return }
                selection = [id]
                // Defer so the list has the row laid out before we scroll.
                DispatchQueue.main.async {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func expansionBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { expandedIds.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedIds.insert(id) } else { expandedIds.remove(id) }
            }
        )
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<UUID>) -> some View {
        if !ids.isEmpty {
            Button("Copy") { setPasteboard(joinedText(for: ids)) }
            if ids.count == 1, let id = ids.first,
               let transcription = displayedTranscriptions.first(where: { $0.id == id }),
               transcription.enhancedText?.isEmpty == false {
                Button("Copy Original") { setPasteboard(transcription.text) }
            }
            Button("Export…") {
                exportService.exportTranscriptionsToCSV(transcriptions: transcriptions(for: ids))
            }
            if ids.count == 1, let id = ids.first {
                Button("Show Info") { inspectedId = id }
            }
            Divider()
            Button("Delete", role: .destructive) { requestDelete(ids) }
        }
    }

    private func handleEscape() {
        if inspectedId != nil {
            inspectedId = nil
        } else if !searchText.isEmpty {
            searchText = ""
        } else if !expandedIds.isEmpty {
            withAnimation(reduceMotion ? nil : .default) { expandedIds.removeAll() }
        } else {
            selection.removeAll()
        }
    }

    private func setPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    private func joinedText(for ids: Set<UUID>) -> String {
        transcriptions(for: ids)
            .map { $0.enhancedText ?? $0.text }
            .joined(separator: "\n\n")
    }

    // MARK: - Inspector

    private var inspectorContent: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Info")
                    .font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark") { inspectedId = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if let transcription = inspectedTranscription {
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
            totalMatchingCount = (try? modelContext.fetchCount(matchingDescriptor())) ?? items.count
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

    /// Newest first, including selected rows that are not on a loaded page.
    private func transcriptions(for ids: Set<UUID>) -> [Transcription] {
        let idList = Array(ids)
        let descriptor = FetchDescriptor<Transcription>(
            predicate: #Predicate { idList.contains($0.id) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func selectAllMatching() {
        var descriptor = matchingDescriptor()
        descriptor.propertiesToFetch = [\.id]
        do {
            selection = Set(try modelContext.fetch(descriptor).map(\.id))
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }

    /// One row goes through the undo window; several rows ask first.
    private func requestDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first,
           let transcription = displayedTranscriptions.first(where: { $0.id == id }) {
            deleteSingle(transcription)
        } else {
            selection = ids
            showDeleteConfirmation = true
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

        expandedIds.remove(transcription.id)
        if inspectedId == transcription.id {
            inspectedId = nil
        }

        selection.remove(transcription.id)
        modelContext.delete(transcription)
    }

    private func deleteSelectedTranscriptions() {
        for transcription in transcriptions(for: selection) {
            performDeletion(for: transcription)
        }
        selection.removeAll()

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

        expandedIds.remove(transcription.id)
        if inspectedId == transcription.id {
            inspectedId = nil
        }
        selection.remove(transcription.id)

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
}

// MARK: - History Row

private struct HistoryRow: View {
    let transcription: Transcription
    @Binding var isExpanded: Bool
    let onShowInfo: () -> Void

    @State private var selectedTab: TranscriptionTab = .original

    private var displayText: String {
        switch selectedTab {
        case .original:
            return transcription.text
        case .enhanced:
            return transcription.enhancedText ?? ""
        }
    }

    private var audioURL: URL? {
        guard let urlString = transcription.audioFileURL,
              let url = URL(string: urlString),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            details
        } label: {
            summary
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Time only — the day section header already names the day.
            Text(transcription.timestamp, format: .dateTime.hour().minute())
                .font(.mono(11))
                .tabularNumbers()
                .foregroundStyle(.secondary)

            if !isExpanded {
                Text(transcription.enhancedText ?? transcription.text)
                    .font(.transcript(15))
                    .lineSpacing(3)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 4)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if transcription.enhancedText != nil {
                    Picker("Version", selection: $selectedTab) {
                        ForEach(TranscriptionTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                Spacer()
                CopyIconButton(textToCopy: displayText)
            }

            Text(displayText)
                .font(.transcript(15))
                .lineSpacing(3)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let audioURL {
                AudioPlayerView(url: audioURL, transcription: transcription, onInfoTap: onShowInfo)
                    .padding(.vertical, 4)
            } else {
                HStack {
                    Spacer()
                    Button("View details", systemImage: "info.circle", action: onShowInfo)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("View details")
                }
            }
        }
        .padding(.vertical, 6)
    }
}
