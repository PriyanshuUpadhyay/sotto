import Foundation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
    /// Transient failure dwell. Engine collapses back to `.idle` after
    /// `VoiceInkEngine.failedDwellSeconds`. Reason is the user-readable error.
    case failed(reason: String)
}
