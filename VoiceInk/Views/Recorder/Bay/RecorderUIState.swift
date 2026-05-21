import SwiftUI
import Combine

// MARK: - RecorderUIState
//
// Single observable for the Bay HUD subtree. Bridges engine-side
// `RecordingState` + view-side `HaloPhase` lifetimes (sourced from
// `RecorderUIManager.phase`) + per-state payload (audio level, prompt name,
// error code, paste event). All three Bay subviews observe this object.
//
// Lives for the lifetime of the BayHUDView subtree — not the app. Unmounts
// when `phase == .hidden` and the SwiftUI tree returns `EmptyView`.

@MainActor
final class RecorderUIState: ObservableObject {
    @Published var phase: HaloPhase = .hidden
    @Published var audioLevel: Double = 0
    @Published var recordingStartedAt: Date?
    @Published var activePromptLabel: String?     // §2.3 — already-truncated 9-char uppercase, or nil
    @Published var errorCode: String?              // §4.2 fail — "ERR · NO_DEVICE" etc.
    @Published var lastPasteAppName: String?
}
