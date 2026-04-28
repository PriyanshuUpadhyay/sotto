import Foundation
import AVFoundation
import os

/// Runtime audio cue synthesizer (P3.F / spec §3.10, §6.3).
///
/// 5 parametric cues — start / transcribe-complete / enhance-complete / cancel /
/// fail — generated on the fly from sine notes + per-note attack/decay envelopes.
/// No bundled audio assets. All cues clamp under 300ms.
///
/// Engine lifecycle:
/// - `AVAudioEngine` + a single `AVAudioPlayerNode` are created at init and never
///   torn down. `warmUp()` starts the engine + schedules a silent pre-roll once,
///   masking the ~50–100ms first-cue startup latency (see plan P3.F risk note).
/// - Subsequent cue calls just synthesize a fresh `AVAudioPCMBuffer` and call
///   `scheduleBuffer` — no per-cue start/stop.
///
/// Loudness normalization: every note's per-cue amplitude is shaped by the same
/// envelope helper, then the entire summed buffer is scaled by `masterGain` so
/// all 5 cues sit at consistent peak loudness regardless of voice count.
@MainActor
final class CueSynthesizer {
    static let shared = CueSynthesizer()

    // MARK: - Engine

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let sampleRate: Double = 44_100
    private let format: AVAudioFormat
    private var didWarmUp = false
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "CueSynthesizer")

    /// Master gain applied to every generated buffer. Tuned so the loudest cue
    /// (start pluck — single voice peaking near 1.0) sits comfortably below
    /// clipping while quieter cues remain audible. Re-tuned per spec §5 row W7
    /// to match the lighter aesthetic — ~30% perceived drop relative to the
    /// pre-W7 0.45 default.
    nonisolated static let masterGain: Float = 0.32

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Starts the engine, fires `player.play()`, and schedules a silent pre-roll
    /// to flush the audio graph. Idempotent — call from app launch
    /// (`VoiceInkApp.init` after manager construction).
    func warmUp() {
        guard !didWarmUp else { return }
        didWarmUp = true
        do {
            engine.prepare()
            try engine.start()
            player.play()
            // Silent zero-amplitude buffer (~80ms) to hide first-cue startup
            // latency. The audio graph processes this while the user is reading
            // UI; subsequent cues fire instantly.
            if let silent = makeBuffer(totalDuration: 0.080, notes: []) {
                player.scheduleBuffer(silent, completionHandler: nil)
            }
        } catch {
            logger.error("warmUp failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Restarts the engine if it was stopped (system audio device change,
    /// route reconfiguration, etc). Lazy — first cue after a stop pays the
    /// restart cost; subsequent cues stay hot.
    private func ensureRunning() {
        if !didWarmUp { warmUp(); return }
        if !engine.isRunning {
            do {
                try engine.start()
                if !player.isPlaying { player.play() }
            } catch {
                logger.error("ensureRunning restart failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Cues

    /// Five named cues per spec §3.10. The raw value mirrors `CustomSoundManager.SoundType`
    /// so user-override storage and UI bindings can use the same key.
    enum Cue: String, CaseIterable, Identifiable, Sendable {
        case start
        case transcribeComplete
        case enhanceComplete
        case cancel
        case fail

        var id: String { rawValue }
    }

    /// Plays a cue. Defaults to the synthesized buffer; SoundManager layers the
    /// custom-override fallback on top.
    func play(_ cue: Cue) {
        let (notes, total) = Self.parameters(for: cue)
        schedule(notes: notes, totalDuration: total)
    }

    /// Recording start: 880 Hz sine pluck + major-6th overtone (5/3 ratio).
    func playStart() { play(.start) }

    /// Transcribe complete: C–E–G–B (C major maj7) arpeggio.
    func playTranscribeComplete() { play(.transcribeComplete) }

    /// Enhance complete: stacked maj7 + fourth-up arpeggio.
    func playEnhanceComplete() { play(.enhanceComplete) }

    /// Cancel: descending two-note A4 → E4.
    func playCancel() { play(.cancel) }

    /// Failure: descending minor F4 → Db4.
    func playFail() { play(.fail) }

    // MARK: - Cue parameter table

    /// Cue duration in seconds — used by SoundManager to schedule fire-and-forget
    /// completion callbacks for synthesized cues without an explicit completion
    /// hook on `scheduleBuffer`.
    static func duration(of cue: Cue) -> Double {
        parameters(for: cue).totalDuration
    }

    /// Single source of truth for each cue's note table + total duration.
    /// Pulled out as `static` so it can be reused by the nonisolated waveform
    /// renderer without main-actor hops.
    nonisolated static func parameters(for cue: Cue) -> (notes: [CueNote], totalDuration: Double) {
        switch cue {
        case .start:
            let total = 0.230
            let attack = 0.090
            let amp = 0.85
            return (
                [
                    CueNote(frequency: 880,               startTime: 0, duration: total, attack: attack, amplitude: amp),
                    // Major 6th overtone — adds warmth without clouding the fundamental.
                    CueNote(frequency: 880 * (5.0 / 3.0), startTime: 0, duration: total, attack: attack, amplitude: amp * 0.35),
                ],
                total
            )

        case .transcribeComplete:
            return (Self.arpeggio(frequencies: [261.63, 329.63, 392.00, 493.88], baseAmp: 0.65), 0.220)

        case .enhanceComplete:
            var notes = Self.arpeggio(frequencies: [261.63, 329.63, 392.00, 493.88], baseAmp: 0.50)
            notes.append(contentsOf: Self.arpeggio(frequencies: [349.23, 440.00, 523.25, 659.25], baseAmp: 0.50 * 0.70))
            return (notes, 0.220)

        case .cancel:
            let attack = 0.025
            let noteDur = 0.120
            let amp = 0.60
            return (
                [
                    CueNote(frequency: 440.00, startTime: 0.000, duration: noteDur, attack: attack, amplitude: amp),
                    CueNote(frequency: 329.63, startTime: 0.060, duration: noteDur, attack: attack, amplitude: amp),
                ],
                0.180
            )

        case .fail:
            let attack = 0.030
            let noteDur = 0.160
            let amp = 0.65
            return (
                [
                    CueNote(frequency: 349.23, startTime: 0.000, duration: noteDur, attack: attack, amplitude: amp),
                    CueNote(frequency: 277.18, startTime: 0.070, duration: noteDur, attack: attack, amplitude: amp),
                ],
                0.220
            )
        }
    }

    // MARK: - Helpers

    /// Builds an arpeggio: each frequency offset by 50 ms, 30 ms attack, 180 ms
    /// total per-note duration. Returns notes ready for `schedule(...)`.
    nonisolated private static func arpeggio(frequencies: [Double], baseAmp: Double) -> [CueNote] {
        let stagger: Double = 0.050
        let attack: Double = 0.030
        let noteDur: Double = 0.180
        return frequencies.enumerated().map { idx, freq in
            CueNote(
                frequency: freq,
                startTime: Double(idx) * stagger,
                duration: noteDur,
                attack: attack,
                amplitude: baseAmp
            )
        }
    }

    // MARK: - Waveform sampling (off-main)

    /// Synthesizes a downsampled peak-amplitude envelope of the cue, normalized
    /// to 0…1 with a small floor so silent regions stay visible. Pure value
    /// computation — safe to call from any actor; `CustomSoundManager` caches
    /// the result so each cue is sampled at most once.
    ///
    /// `bins` controls the bar count of the lollipop preview. Synthesis cost is
    /// O(notes × cueFrames); for a 230 ms cue at 44.1 kHz that's ~10k iterations
    /// per voice — fast, but we still cache to avoid re-doing it on every
    /// SwiftUI body recompute.
    nonisolated static func waveformPreview(for cue: Cue, bins: Int) -> [Float] {
        guard bins > 0 else { return [] }
        let (notes, totalDuration) = parameters(for: cue)
        let sampleRate: Double = 44_100
        let totalFrames = Int(totalDuration * sampleRate)
        guard totalFrames > 0 else { return [] }

        var raw = [Float](repeating: 0, count: totalFrames)
        let twoPi = 2.0 * Double.pi
        for note in notes {
            let startFrame = Int(note.startTime * sampleRate)
            let noteFrames = Int(note.duration * sampleRate)
            let attackFrames = max(1, Int(note.attack * sampleRate))
            let decayFrames = max(1, noteFrames - attackFrames)
            let decayConst = log(1000.0) / Double(decayFrames)
            let phaseInc = twoPi * note.frequency / sampleRate
            var phase = 0.0
            for f in 0..<noteFrames {
                let dst = startFrame + f
                if dst < 0 || dst >= totalFrames { continue }
                let envelope: Double
                if f < attackFrames {
                    envelope = Double(f) / Double(attackFrames)
                } else {
                    envelope = exp(-decayConst * Double(f - attackFrames))
                }
                raw[dst] += Float(sin(phase) * envelope * note.amplitude)
                phase += phaseInc
                if phase > twoPi { phase -= twoPi }
            }
        }

        // Apply master gain so the envelope matches what the user actually hears.
        for i in 0..<totalFrames { raw[i] *= masterGain }

        // Downsample to `bins` peak windows.
        var out = [Float](repeating: 0, count: bins)
        for i in 0..<bins {
            let s = (i * totalFrames) / bins
            let e = max(s + 1, ((i + 1) * totalFrames) / bins)
            var peak: Float = 0
            for j in s..<min(e, totalFrames) {
                let a = abs(raw[j])
                if a > peak { peak = a }
            }
            out[i] = peak
        }

        // Normalize so the loudest bin reads 1.0; floor at 0.04 so silent tails
        // still show a hairline lollipop instead of disappearing.
        if let maxPeak = out.max(), maxPeak > 0 {
            for i in 0..<bins {
                out[i] = max(0.04, out[i] / maxPeak)
            }
        }
        return out
    }

    /// Generates a buffer for the given notes and schedules it on the player.
    /// Engine + player are guaranteed running.
    private func schedule(notes: [CueNote], totalDuration: Double) {
        ensureRunning()
        guard let buffer = makeBuffer(totalDuration: totalDuration, notes: notes) else { return }
        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    /// Synthesizes a mono PCM buffer summing all notes with each note's own
    /// linear-attack / exponential-decay envelope. Adds a 4 ms trailing fade-out
    /// across the whole buffer to suppress click artifacts at cue end.
    /// Master gain applied last to normalize loudness across cues.
    private func makeBuffer(totalDuration: Double, notes: [CueNote]) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(totalDuration * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        guard let channel = buffer.floatChannelData?[0] else { return nil }

        // Zero out
        let totalFrames = Int(frameCount)
        for i in 0..<totalFrames { channel[i] = 0 }

        let twoPi = 2.0 * Double.pi
        for note in notes {
            let startFrame = Int(note.startTime * sampleRate)
            let noteFrames = Int(note.duration * sampleRate)
            let attackFrames = max(1, Int(note.attack * sampleRate))
            let decayFrames = max(1, noteFrames - attackFrames)
            // Exponential decay: ~60 dB drop across decayFrames.
            let decayConst = log(1000.0) / Double(decayFrames)
            let phaseInc = twoPi * note.frequency / sampleRate
            var phase = 0.0

            for f in 0..<noteFrames {
                let dst = startFrame + f
                if dst < 0 || dst >= totalFrames { continue }
                let envelope: Double
                if f < attackFrames {
                    // Linear attack — tiny ramp-in suppresses click at note start.
                    envelope = Double(f) / Double(attackFrames)
                } else {
                    // Exponential decay — natural, plucky tail.
                    let t = Double(f - attackFrames)
                    envelope = exp(-decayConst * t)
                }
                channel[dst] += Float(sin(phase) * envelope * note.amplitude)
                phase += phaseInc
                if phase > twoPi { phase -= twoPi }
            }
        }

        // Trailing 4 ms linear fade-out across the whole buffer's tail. Belt-
        // and-braces against any residual amplitude at buffer end (the
        // exponential decay never quite hits zero).
        let fadeFrames = min(Int(0.004 * sampleRate), totalFrames)
        if fadeFrames > 1 {
            let start = totalFrames - fadeFrames
            for f in 0..<fadeFrames {
                let g = Float(1.0 - Double(f) / Double(fadeFrames - 1))
                channel[start + f] *= g
            }
        }

        // Master gain — normalizes peak loudness across cues regardless of
        // voice count (single-pluck vs. 8-voice stacked arpeggio).
        for i in 0..<totalFrames { channel[i] *= CueSynthesizer.masterGain }

        return buffer
    }
}

/// One sine voice in a cue. `attack` is linear ramp-in, the rest of `duration`
/// is exponential decay.
struct CueNote: Sendable {
    let frequency: Double   // Hz
    let startTime: Double   // seconds, relative to cue start
    let duration: Double    // seconds, total envelope length (attack + decay)
    let attack: Double      // seconds, linear ramp-in
    let amplitude: Double   // peak amplitude (0…1, pre-master-gain)
}
