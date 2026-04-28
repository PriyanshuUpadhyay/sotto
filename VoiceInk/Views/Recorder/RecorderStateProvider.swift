import Foundation

// MARK: - PasteEvent
//
// Spec §3.1 / plan §P1.G done-state — concrete signal for the orchestrator's
// `.done` derivation. `CursorPaster` builds one of these on every successful
// paste keystroke and posts `Notification.Name.voiceInkDidPaste`; the engine
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

    /// `Notification.userInfo` key carrying the `PasteEvent` value.
    static let userInfoKey = "voiceInkPasteEvent"

    /// Spec §3.1 done content shows a single italic line under "Pasted to <app>".
    /// 90 chars is generous for that single line at 13pt; ConstellationCard
    /// also `lineLimit(1)`s + `truncationMode(.tail)`s as a belt-suspenders.
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

    /// Latest paste event from `CursorPaster`. Source-of-truth lives here, NOT
    /// in `ConstellationContainer` — the orchestrator derives `.done` from
    /// the freshness of this value (plan §P1.G reviewer focus).
    var lastPasteEvent: PasteEvent? { get }

    /// Pretty label for the active transcription model (e.g.
    /// `"WHISPER · LARGE-V3"`). Surfaced in ConstellationCard's
    /// `.transcribing` content row. Nil → orchestrator falls back to the
    /// card's default placeholder.
    var transcriptionModelLabel: String? { get }
}
