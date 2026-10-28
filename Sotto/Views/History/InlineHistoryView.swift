import SwiftUI
import SwiftData
import AppKit

/// History list on native controls: `List(selection:)` owns click, ⌘/⇧-click,
/// arrow keys and ⌘A; `DisclosureGroup` owns expand/collapse; the Edit menu
/// commands (Copy, Delete) and the context menu act on the selection.
struct InlineHistoryView: View {
    @Environment(\.modelContext) var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @State var searchText = ""
    /// Can hold rows past the loaded page after "Select All", so bulk actions
    /// fetch by id instead of reading `displayedTranscriptions`.
    @State var selection: Set<UUID> = []
    @State var expandedIds: Set<UUID> = []
    @State var showDeleteConfirmation = false
    /// A single-row delete waits out `undoWindowSeconds` before it touches the
    /// database or the audio file: the row hides immediately, an UNDO toast
    /// stands, and only then is the deletion committed. Bulk delete keeps its
    /// confirmation instead.
    @State var pendingDeletion: Transcription?
    @State var undoWindow: Task<Void, Never>?
    @State var inspectedId: UUID?
    @State var displayedTranscriptions: [Transcription] = []
    @State var isLoading = false
    @State var hasMoreContent = true
    @State var lastTimestamp: Date?
    @State private var isViewCurrentlyVisible = false
    /// Every row the current search matches, not just the loaded page — "Select
    /// All" selects all of them, so the control has to say so.
    @State var totalMatchingCount = 0
    @State private var searchDebounce: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private let exportService = SottoCSVExportService()
    let pageSize = 20
    static let undoWindowSeconds: TimeInterval = 5

    @Query(Self.createLatestTranscriptionIndicatorDescriptor()) private var latestTranscriptionIndicator: [Transcription]

    private static func createLatestTranscriptionIndicatorDescriptor() -> FetchDescriptor<Transcription> {
        var descriptor = FetchDescriptor<Transcription>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    func cursorQueryDescriptor(after timestamp: Date? = nil) -> FetchDescriptor<Transcription> {
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
    func matchingDescriptor() -> FetchDescriptor<Transcription> {
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

}
