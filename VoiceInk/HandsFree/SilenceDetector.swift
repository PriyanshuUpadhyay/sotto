import Foundation

/// W12.D silence-detection helper. Pure state machine; no Combine, no
/// concurrency primitives. Owned by `HandsFreeSessionService`; called from the
/// main actor exclusively. See plan
/// `docs/superpowers/plans/W12D-hands-free-vad.md` §Migration policy #6.
final class SilenceDetector {
    enum SilenceEvent: Equatable {
        case silenceDetected
    }

    private var thresholdDb: Double = -40.0
    private var silenceDuration: TimeInterval = 1.5

    private var lastVoiceTimestamp: Date?
    private var hasSpokenInUtterance: Bool = false
    private var didEmitSilence: Bool = false

    func configure(thresholdDb: Double, silenceDuration: TimeInterval) {
        self.thresholdDb = thresholdDb
        self.silenceDuration = silenceDuration
    }

    func reset() {
        lastVoiceTimestamp = nil
        hasSpokenInUtterance = false
        didEmitSilence = false
    }

    /// Called once per audio meter sample (~17ms cadence from `Recorder`).
    /// Returns `.silenceDetected` exactly once per utterance boundary; returns
    /// `nil` for all subsequent samples until `reset()` is called.
    ///
    /// `Recorder.audioMeter.averagePower` is the EMA-smoothed normalized
    /// `[0, 1]` value computed in `Recorder.updateAudioMeter` from the AUHAL
    /// dBFS reading using `(power - minVisibleDb) / (maxVisibleDb -
    /// minVisibleDb)` with `minVisibleDb = -60` and `maxVisibleDb = 0`. We
    /// invert that mapping back to dBFS before threshold comparison. If
    /// `Recorder`'s normalization formula changes, this detector breaks
    /// silently — Risk #8 in the plan.
    func update(meter: AudioMeter, now: Date) -> SilenceEvent? {
        guard !didEmitSilence else { return nil }

        let avgNormalized = meter.averagePower // normalized [0, 1] Double
        let dB: Double = avgNormalized > 0
            ? -60.0 + (avgNormalized * 60.0)
            : -160.0

        if dB >= thresholdDb {
            // Voice present.
            lastVoiceTimestamp = now
            hasSpokenInUtterance = true
            return nil
        }

        // Silence sample — only meaningful if we've heard voice already.
        guard hasSpokenInUtterance, let last = lastVoiceTimestamp else { return nil }
        let silenceElapsed = now.timeIntervalSince(last)
        if silenceElapsed >= silenceDuration {
            didEmitSilence = true
            return .silenceDetected
        }
        return nil
    }
}
