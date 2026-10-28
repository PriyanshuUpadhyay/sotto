import SwiftUI
import SwiftData
import AppKit

extension InlineHistoryView {
    // MARK: - Data Loading

    @MainActor
    func loadInitialContent() async {
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
    func loadMoreContent() async {
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
    func resetPagination() {
        displayedTranscriptions = []
        lastTimestamp = nil
        hasMoreContent = true
        isLoading = false
    }

    // MARK: - Selection & Deletion

    /// Newest first, including selected rows that are not on a loaded page.
    func transcriptions(for ids: Set<UUID>) -> [Transcription] {
        let idList = Array(ids)
        let descriptor = FetchDescriptor<Transcription>(
            predicate: #Predicate { idList.contains($0.id) },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func selectAllMatching() {
        var descriptor = matchingDescriptor()
        descriptor.propertiesToFetch = [\.id]
        do {
            selection = Set(try modelContext.fetch(descriptor).map(\.id))
        } catch {
            print("Error selecting all transcriptions: \(error)")
        }
    }

    /// One row goes through the undo window; several rows ask first.
    func requestDelete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        if ids.count == 1, let id = ids.first,
           let transcription = displayedTranscriptions.first(where: { $0.id == id }) {
            deleteSingle(transcription)
        } else {
            selection = ids
            showDeleteConfirmation = true
        }
    }

    func performDeletion(for transcription: Transcription) {
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

    func deleteSelectedTranscriptions() {
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
    func deleteSingle(_ transcription: Transcription) {
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
    func commitPendingDeletion() {
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
    func undoPendingDeletion() {
        undoWindow?.cancel()
        undoWindow = nil
        guard pendingDeletion != nil else { return }
        pendingDeletion = nil
        Task { await loadInitialContent() }
    }
}
