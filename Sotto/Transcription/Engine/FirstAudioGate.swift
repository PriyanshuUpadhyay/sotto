import Foundation
import Combine

// MARK: - FirstAudioGate
//
// Spec §4.2 / Appendix B.FirstAudio: gates the `.armed → .recording`
// transition. `observed` stays `false` while every captured frame is below
// the -50 dBFS silence threshold and latches `true` on the first frame at or
// above it. `RecorderUIManager` reads it via `SottoEngine.firstAudioObserved`.

@MainActor
final class FirstAudioGate: ObservableObject {
    static let silenceThreshold: Float = -50.0

    @Published private(set) var observed: Bool = false

    func start() {
        observed = false
    }

    func consume(rawDb: Float) {
        guard !observed else { return }
        if rawDb >= Self.silenceThreshold {
            observed = true
        }
    }

    func reset() {
        observed = false
    }
}
