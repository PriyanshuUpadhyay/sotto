import Foundation

/// W12.D session lifecycle. Owned by `HandsFreeSessionService`; published to
/// SwiftUI and the menubar observer.
enum HandsFreeSessionState: Equatable {
    /// Default. Recorder behaves exactly as pre-W12.D.
    case inactive

    /// Recorder is running, listening for voice. Transitions to `.committing`
    /// when `SilenceDetector` reports an utterance boundary.
    case listening

    /// An utterance just ended. `VoiceInkEngine.commitUtterance()` is running
    /// (stop → pipeline → restart). Transitions back to `.listening` when
    /// the new recorder is started, or to `.inactive` on session end.
    case committing

    /// Graceful drain in progress (user toggle, session cap, or pipeline
    /// failure). Transitions to `.inactive` when cleanup is done.
    case endingSession

    var displayName: String {
        switch self {
        case .inactive:      return "Inactive"
        case .listening:     return "Listening"
        case .committing:    return "Committing"
        case .endingSession: return "Ending"
        }
    }
}
