import Foundation
import SwiftData
import os

/// The single write path for explicit post-paste edit signals. Pure and
/// injectable: no AX, no UI, no singleton. `TranscriptionPipeline` calls
/// `record(...)` from the compose-review (review-before-paste) editor's paste
/// callback — final text vs enhanced text at the user's ⌘↵; tests call it
/// against an in-memory `ModelContext`.
///
/// Replaces the retired AX-observer inference path — the signal here is
/// EXPLICIT (the user confirmed the text in the editor), so gating is minimal:
/// only drop an `.edit` that changed nothing, and coerce an empty `.edit` to a
/// thumbs-down.
struct EditSignalService {
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "EditSignal")
    private let maxRecords = 200
    private let maxAgeSeconds: TimeInterval = 90 * 24 * 3600

    func record(rawText: String,
                enhancedText: String,
                finalText: String,
                source: EditSignalSource,
                appBundleID: String?,
                transcriptionID: UUID,
                promptName: String?,
                in context: ModelContext) {
        let hash = EditTextNormalizer.hash(enhancedText)

        let record: EnhancementEditRecord
        switch source {
        case .revertRaw:
            record = EnhancementEditRecord(
                rawText: rawText, enhancedText: enhancedText, finalText: rawText,
                appBundleID: appBundleID, transcriptionID: transcriptionID,
                enhancedHash: hash, editKind: .style, signalSource: .revertRaw)
        case .thumbsDown:
            record = EnhancementEditRecord(
                rawText: rawText, enhancedText: enhancedText, finalText: enhancedText,
                appBundleID: appBundleID, transcriptionID: transcriptionID,
                enhancedHash: hash, editKind: .style, signalSource: .thumbsDown)
        case .acceptedUnchanged:
            // Internal outcome — normally produced by the `.edit` no-op path, not
            // passed in directly. Handled here for exhaustiveness.
            record = EnhancementEditRecord(
                rawText: rawText, enhancedText: enhancedText, finalText: enhancedText,
                appBundleID: appBundleID, transcriptionID: transcriptionID,
                enhancedHash: hash, editKind: .style, signalSource: .acceptedUnchanged)
        case .edit:
            let trimmed = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                record = EnhancementEditRecord(
                    rawText: rawText, enhancedText: enhancedText, finalText: enhancedText,
                    appBundleID: appBundleID, transcriptionID: transcriptionID,
                    enhancedHash: hash, editKind: .style, signalSource: .thumbsDown)
            } else if EditTextNormalizer.normalize(finalText) == EditTextNormalizer.normalize(enhancedText) {
                // Accepted unchanged: the user confirmed the enhancement as-is.
                // Recorded (not dropped) so the zero-edit rate is measurable.
                record = EnhancementEditRecord(
                    rawText: rawText, enhancedText: enhancedText, finalText: enhancedText,
                    appBundleID: appBundleID, transcriptionID: transcriptionID,
                    enhancedHash: hash, editKind: .style, signalSource: .acceptedUnchanged)
            } else {
                let kind = EditEligibility.classify(enhanced: enhancedText, final: finalText) ?? .style
                record = EnhancementEditRecord(
                    rawText: rawText, enhancedText: enhancedText, finalText: finalText,
                    appBundleID: appBundleID, transcriptionID: transcriptionID,
                    enhancedHash: hash, editKind: kind, signalSource: .edit)
            }
        }

        context.insert(record)
        do { try context.save() } catch {
            logger.error("edit-signal: save failed \(error.localizedDescription, privacy: .public)")
            return
        }
        prune(in: context)
        logger.notice("edit-signal: recorded \(record.signalSource.rawValue, privacy: .public)")
    }

    private func prune(in context: ModelContext) {
        let cutoff = Date().addingTimeInterval(-maxAgeSeconds)
        let descriptor = FetchDescriptor<EnhancementEditRecord>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        guard let all = try? context.fetch(descriptor) else { return }
        // Age cutoff, then strictly oldest-first eviction past the cap —
        // deliberately type-AGNOSTIC. The earlier policy evicted
        // `.acceptedUnchanged` before real edits, which class-biased the
        // retained sample under cap pressure: zero-edit signals vanished first,
        // dragging HistoryStats.zeroEditRate artificially low for high-volume
        // users. Oldest-first keeps the retained window an unbiased sample of
        // both classes; correction mining loses a few older `.edit` rows in
        // exchange, which its ≥3-dictation threshold tolerates.
        let fresh = all.filter { $0.timestamp >= cutoff }
        let toDelete = all.filter { $0.timestamp < cutoff } + fresh.dropFirst(maxRecords)
        guard !toDelete.isEmpty else { return }
        for record in toDelete { context.delete(record) }
        try? context.save()
    }
}
