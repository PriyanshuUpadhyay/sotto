import Foundation

// MARK: - RecordingState
//
// Engine-side recording lifecycle. Failures are surfaced as one-shot
// `FailureEvent`s via `SottoEngine.failurePublisher` and remembered by
// `FailureRegistry`; the engine returns to `.idle` immediately on error so
// the view layer's failure lifetime is owned outside the engine.

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
}
