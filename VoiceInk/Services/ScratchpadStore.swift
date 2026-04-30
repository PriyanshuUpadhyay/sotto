import Foundation
import SwiftData
import SwiftUI
import os

/// W12.E Scratchpad store. Owns SwiftData CRUD for `ScratchpadDocument` +
/// `ScratchpadVersion`, the 800ms autosave debounce, the 30s version-snapshot
/// cadence, the 50-version FIFO eviction, and the paste-fallback append path.
/// See plan `docs/superpowers/plans/W12E-scratchpad.md` §Task 3 +
/// §Migration policy #5/#6/#7/#11.
@MainActor
final class ScratchpadStore: ObservableObject {

    static let maxTabs = 10                  // §Migration policy #2
    static let maxVersionsPerDocument = 50   // §Migration policy #7
    private static let autosaveDebounceMs: UInt64 = 800_000_000
    private static let versionInterval: TimeInterval = 30  // seconds

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink",
                                 category: "ScratchpadStore")

    @Published private(set) var documents: [ScratchpadDocument] = []
    @Published var activeTabId: UUID?

    private var autosaveTasks: [UUID: Task<Void, Never>] = [:]
    private var lastVersionedAt: [UUID: Date] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadDocuments()
        if documents.isEmpty {
            _ = createTab(at: 0)
        }
        activeTabId = documents.first?.id
    }

    // MARK: - Load

    func loadDocuments() {
        let descriptor = FetchDescriptor<ScratchpadDocument>(
            sortBy: [SortDescriptor(\.tabIndex, order: .forward)]
        )
        documents = (try? modelContext.fetch(descriptor)) ?? []
        // Seed lastVersionedAt from the most recent version per document.
        for doc in documents {
            if let latest = doc.versions.max(by: { $0.capturedAt < $1.capturedAt }) {
                lastVersionedAt[doc.id] = latest.capturedAt
            }
        }
    }

    // MARK: - Tab CRUD

    /// Returns the new document, or nil if at the cap.
    @discardableResult
    func createTab(at index: Int? = nil) -> ScratchpadDocument? {
        guard documents.count < Self.maxTabs else {
            NotificationManager.shared.showNotification(
                title: "Tab limit reached (\(Self.maxTabs)). Close a tab to add a new one.",
                type: .info
            )
            return nil
        }
        let insertAt = index ?? documents.count
        let doc = ScratchpadDocument(tabIndex: insertAt)
        modelContext.insert(doc)
        // Reindex tabs at or after the insertion point.
        for existing in documents where existing.tabIndex >= insertAt {
            existing.tabIndex += 1
        }
        documents.insert(doc, at: insertAt)
        activeTabId = doc.id
        try? modelContext.save()
        return doc
    }

    func closeTab(_ document: ScratchpadDocument) {
        // Capture-then-evict so closing isn't a silent data loss.
        captureVersion(document, force: true)
        cancelAutosave(document.id)
        modelContext.delete(document)
        documents.removeAll { $0.id == document.id }
        // Reindex.
        for (idx, existing) in documents.enumerated() {
            existing.tabIndex = idx
        }
        // Activate the next available tab; create one if all are gone.
        if activeTabId == document.id {
            if let next = documents.first {
                activeTabId = next.id
            } else {
                _ = createTab()
            }
        }
        try? modelContext.save()
    }

    // MARK: - Content + autosave

    /// Called from the SwiftUI editor on every text change. Schedules a
    /// debounced 800ms write + checks the 30s version-snapshot cadence.
    func updateContent(_ document: ScratchpadDocument, content: String) {
        document.content = content
        document.title = derivedTitle(from: content)
        document.updatedAt = Date()

        // Cancel any pending autosave for this doc; reschedule.
        cancelAutosave(document.id)
        let docId = document.id
        autosaveTasks[docId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autosaveDebounceMs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                try? self.modelContext.save()
                self.maybeCaptureVersion(document)
                self.autosaveTasks[docId] = nil
            }
        }
    }

    private func maybeCaptureVersion(_ document: ScratchpadDocument) {
        let last = lastVersionedAt[document.id] ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.versionInterval {
            captureVersion(document, force: false)
        }
    }

    private func cancelAutosave(_ id: UUID) {
        autosaveTasks[id]?.cancel()
        autosaveTasks[id] = nil
    }

    // MARK: - Versions

    func captureVersion(_ document: ScratchpadDocument, force: Bool) {
        // Defensive: don't snapshot empty content unless the user explicitly
        // asked (force=true). Avoids a snapshot on every newly-opened tab.
        if !force && document.content.isEmpty { return }

        let version = ScratchpadVersion(content: document.content, document: document)
        modelContext.insert(version)
        lastVersionedAt[document.id] = Date()
        evictOldVersionsIfNeeded(document)
        try? modelContext.save()
        logger.notice("🦾 scratchpad: captured version for \(document.id, privacy: .public) — \(document.versions.count, privacy: .public) total")
    }

    private func evictOldVersionsIfNeeded(_ document: ScratchpadDocument) {
        guard document.versions.count > Self.maxVersionsPerDocument else { return }
        let sorted = document.versions.sorted { $0.capturedAt < $1.capturedAt }
        let evictionCount = document.versions.count - Self.maxVersionsPerDocument
        for victim in sorted.prefix(evictionCount) {
            modelContext.delete(victim)
        }
    }

    func restoreVersion(_ version: ScratchpadVersion, in document: ScratchpadDocument) {
        // Capture current state FIRST so restore is reversible.
        captureVersion(document, force: true)
        document.content = version.content
        document.updatedAt = Date()
        try? modelContext.save()
    }

    // MARK: - Paste-fallback

    /// Paste-fallback landing site. The text the user dictated couldn't be
    /// pasted into the foreground app (no focused text field, sandbox refusal,
    /// etc.) — `CursorPaster` calls this to rescue the dictation into a new
    /// Scratchpad tab. Bypasses the user-tab-cap (Migration policy #11).
    func appendFallbackTab(text: String) {
        let doc = ScratchpadDocument(
            content: text,
            tabIndex: documents.count
        )
        // Auto-derive title so the strip cell shows something meaningful even
        // before the user opens the tab.
        doc.title = derivedTitle(from: text)
        modelContext.insert(doc)
        documents.append(doc)
        try? modelContext.save()
        logger.notice("🦾 scratchpad: rescued paste into new tab — total \(self.documents.count, privacy: .public)")
        if documents.count > Self.maxTabs {
            NotificationManager.shared.showNotification(
                title: "Paste rescued to Scratchpad — \(self.documents.count) tabs (over \(Self.maxTabs)-cap)",
                type: .info
            )
        } else {
            NotificationManager.shared.showNotification(
                title: "Paste rescued to Scratchpad — open with ⌥+S",
                type: .info
            )
        }
    }

    // MARK: - Flush

    /// Awaits any pending autosave tasks. Called from the window controller's
    /// `windowWillClose` to ensure no in-flight 800ms debounce drops content.
    func flushAll() async {
        let tasks = Array(autosaveTasks.values)
        for task in tasks { _ = await task.value }
        try? modelContext.save()
    }

    // MARK: - Title derivation

    private func derivedTitle(from content: String) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if firstLine.isEmpty { return "Untitled" }
        return String(firstLine.prefix(30))
    }
}
