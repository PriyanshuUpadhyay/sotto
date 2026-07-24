import Foundation

// MARK: - PasteEvent
//
// Spec §3.1 / plan §P1.G done-state — concrete signal for the orchestrator's
// `.done` derivation. `CursorPaster` builds one of these on every successful
// paste keystroke and posts `Notification.Name.sottoDidPaste`; the engine
// observes that notification and republishes via `lastPasteEvent`.
//
// `Equatable` so SwiftUI `.onChange(of:)` fires on each fresh paste even
// when the same `appName + preview` is pasted twice in a row — the
// `timestamp` field changes each time, breaking equality.

struct PasteEvent: Equatable {
    /// Frontmost app at the moment the paste fired (e.g. "Cursor", "Notes").
    /// Falls back to "clipboard" when no frontmost app is reported (rare).
    let appName: String
    /// 1-line preview of the pasted text — first line, trimmed, capped at
    /// `previewMaxLength` chars with an ellipsis. Used by the Constellation
    /// card's done-state subtitle.
    let preview: String
    /// Build instant — drives the `.done` 1s dwell window in the orchestrator
    /// AND breaks `Equatable` for back-to-back pastes of identical text.
    let timestamp: Date
    /// X1/F6: the dictation generation (`AIEnhancementService.dictationGeneration`)
    /// active when the TRANSCRIPTION PIPELINE issued this paste — `nil` for
    /// every other paste source ("Paste Last Transcription", the command
    /// palette, review-tray re-paste, …), which never supply one. Lets
    /// `SottoEngine.handleDidPaste` attribute the stop→paste acceptance-
    /// evidence span to the SPECIFIC dictation that caused it, rather than
    /// any paste that happens to arrive while a generation counter still
    /// matches.
    let dictationGeneration: Int?

    /// `Notification.userInfo` key carrying the `PasteEvent` value.
    static let userInfoKey = "sottoPasteEvent"

    /// Spec §3.1 done content shows a single italic line under "Pasted to <app>".
    /// 90 chars is generous for that single line at 13pt; the done-state chip
    /// in `ChipPanel` also `lineLimit(1)`s + `truncationMode(.tail)`s as a
    /// belt-suspenders.
    static let previewMaxLength = 90

    /// Build a 1-line preview from arbitrary pasted text.
    /// - Strips leading/trailing whitespace.
    /// - Keeps only the first non-empty line.
    /// - Truncates at `previewMaxLength` and appends `…`.
    static func preview(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let firstLine = trimmed
            .split(whereSeparator: { $0.isNewline })
            .first
            .map(String.init)
            ?? trimmed
        if firstLine.count <= previewMaxLength { return firstLine }
        let cutoff = firstLine.index(firstLine.startIndex, offsetBy: previewMaxLength)
        return String(firstLine[..<cutoff]) + "\u{2026}"
    }
}

// MARK: - RecorderStateProvider

// Protocol for objects that provide live recorder state to the UI.
@MainActor
protocol RecorderStateProvider: AnyObject {
    var recordingState: RecordingState { get }
    var partialTranscript: String { get }
    var enhancementService: AIEnhancementService? { get }

    /// True while transcription is running but the model is still cold-loading
    /// (first dictation after launch/wake). The HUD shows "warming up" instead
    /// of "transcribing" so the long load doesn't read as a freeze.
    var isWarmingUp: Bool { get }

    /// Latest paste event from `CursorPaster`. Source-of-truth lives here, NOT
    /// in `ConstellationContainer` — the orchestrator derives `.done` from
    /// the freshness of this value (plan §P1.G reviewer focus).
    var lastPasteEvent: PasteEvent? { get }

    /// Pretty label for the active transcription model (e.g.
    /// `"WHISPER · LARGE-V3"`). Surfaced in `ChipPanel` via
    /// `ClusterChips.transcribingChips` during the `.transcribing` phase.
    /// Nil → orchestrator falls back to a default chip label.
    var transcriptionModelLabel: String? { get }

    /// Spec §4.2: first-audio gate. View layer reads this to decide whether
    /// to render `.armed` or `.recording` during the early-`.recording`
    /// engine window before the first non-silent frame arrives.
    var firstAudioObserved: Bool { get }
}
