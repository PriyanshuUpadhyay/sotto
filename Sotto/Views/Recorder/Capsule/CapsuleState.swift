import SwiftUI

/// The 5 surface states the matte recorder capsule renders (council change #3:
/// 4 functional states + idle/ready; full 7-hue syntax palette deferred to P12).
///
/// This is the SINGLE source of truth shared by the a11y contract (`StateCue`),
/// the HUD capsule, the icon rail, and the inspector. The engine mapping
/// (`RecordingState` / `HaloPhase` → `CapsuleState`) and per-state color are
/// added by P2 as an extension — that packet owns the exact engine signals.
enum CapsuleState: Equatable, CaseIterable {
    /// Armed / listening — phosphor whisper, pre-record.
    case idleReady
    /// Capturing audio — SACRED red.
    case recording
    /// Transcribe + enhance collapsed into one working hue.
    case processing
    /// Pasted ✓ — terminal success.
    case commit
    /// Error — terminal failure with ⌘R retry.
    case fail
}

// MARK: - P2 · engine mapping + per-state color
//
// CapsuleState is the shared enum (declared above, P1a). P2 owns the engine
// signals that drive it: the per-state accent color and the mapping from the
// live engine lifecycle. The two TERMINAL states (`commit`/`fail`) are not in
// `RecordingState` — they are display states the HUD derives from the paste
// event (`lastPasteEvent` dwell → `.commit`) and the failure registry /
// `HaloPhase.failed` → `.fail`, matching how `ConstellationCluster` sourced
// them. `init(recordingState:phase:)` folds those terminal signals in.

extension CapsuleState {
    /// Map the engine's continuous lifecycle. `transcribing`+`enhancing` collapse
    /// into the single `processing` hue (council change #3, 4-state cut).
    /// `commit`/`fail` are NOT expressible here — see `init(recordingState:phase:)`.
    init(recordingState s: RecordingState) {
        switch s {
        case .idle, .starting, .busy:   self = .idleReady
        case .recording:                self = .recording
        case .transcribing, .enhancing: self = .processing
        }
    }

    /// Full mapping: the terminal `HaloPhase` display states (`.done`/`.failed`)
    /// win over the engine lifecycle, since the engine itself returns to `.idle`
    /// immediately on error and never carries a "pasted" state.
    init(recordingState s: RecordingState, phase: HaloPhase) {
        switch phase {
        case .done:   self = .commit
        case .failed: self = .fail
        default:      self = CapsuleState(recordingState: s)
        }
    }

    /// The accent color. Enters the matte capsule via the dot / border / glyph
    /// ONLY — never a full fill (spec §4: keeps the surface calm against matte).
    var color: Color {
        switch self {
        case .idleReady:  return Palette.phosphor
        case .recording:  return Palette.stateRecord
        case .processing: return Palette.stateProcessing
        case .commit:     return Palette.stateCommit
        case .fail:       return Palette.stateFail
        }
    }
}
