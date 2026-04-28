import Foundation
import AVFoundation
import SwiftUI

private final class AudioPlayerCompletionDelegate: NSObject, AVAudioPlayerDelegate {
    private let onFinished: () -> Void
    init(_ onFinished: @escaping () -> Void) { self.onFinished = onFinished }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { self.onFinished() }
    }
}

/// Front-door for app cue playback. Per spec §3.10 / plan P3.F + P3.G, all
/// default cues are synthesized at runtime via `CueSynthesizer` — no bundled
/// audio assets. Each of the 5 cues (start / transcribeComplete /
/// enhanceComplete / cancel / fail) accepts a user-supplied override file
/// loaded from app support via `CustomSoundManager`. Overrides take precedence
/// when present; otherwise the synthesized cue plays.
@MainActor
class SoundManager: ObservableObject {
    static let shared = SoundManager()

    private let synth = CueSynthesizer.shared

    /// Per-cue custom override players. Loaded lazily on first
    /// `CustomSoundsChanged` notification + at app launch.
    private var customPlayers: [CustomSoundManager.SoundType: AVAudioPlayer] = [:]

    /// Retain delegate for the start cue's `onFinished` callback (chain target
    /// for `RecorderUIManager` mute deferral).
    private var startSoundDelegate: AudioPlayerCompletionDelegate?

    @AppStorage("isSoundFeedbackEnabled") private var isSoundFeedbackEnabled = true

    private init() {
        Task(priority: .background) {
            await reloadCustomSoundsAsync()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reloadCustomSounds),
            name: NSNotification.Name("CustomSoundsChanged"),
            object: nil
        )
    }

    /// Warms up the cue synthesizer's `AVAudioEngine`. Call once at app launch
    /// so the first user cue plays without ~50–100ms graph startup latency.
    func warmUp() {
        synth.warmUp()
    }

    @objc private func reloadCustomSounds() {
        Task {
            await reloadCustomSoundsAsync()
        }
    }

    private func loadAndPreparePlayer(from url: URL?) -> AVAudioPlayer? {
        guard let url = url else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.4
        player?.prepareToPlay()
        return player
    }

    private func reloadCustomSoundsAsync() async {
        for (_, player) in customPlayers where player.isPlaying {
            player.stop()
        }
        customPlayers.removeAll(keepingCapacity: true)

        for type in CustomSoundManager.SoundType.allCases {
            if let player = loadAndPreparePlayer(from: CustomSoundManager.shared.getCustomSoundURL(for: type)) {
                customPlayers[type] = player
            }
        }
    }

    // MARK: - Public cue API

    /// Recording-start cue. Plays the user's custom start sound if set, else
    /// the synthesized 880Hz pluck. `onFinished` fires after the cue's duration
    /// — used by `RecorderUIManager` to defer system-audio mute until after the
    /// cue plays clean (avoids the cue itself getting muted).
    func playStartSound(onFinished: (() -> Void)? = nil) {
        guard isSoundFeedbackEnabled else {
            onFinished?()
            return
        }
        if let player = customPlayers[.start] {
            player.volume = 0.4
            if let onFinished {
                let delegate = AudioPlayerCompletionDelegate(onFinished)
                startSoundDelegate = delegate
                player.delegate = delegate
            } else {
                startSoundDelegate = nil
                player.delegate = nil
            }
            player.play()
            return
        }

        synth.play(.start)
        if let onFinished {
            // Synthesized cue is fire-and-forget; deliver the completion after
            // the known cue duration so callers (mute-system-audio) can chain.
            let nanos: UInt64 = UInt64(CueSynthesizer.duration(of: .start) * 1_000_000_000)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: nanos)
                onFinished()
            }
        }
    }

    /// Generic "transcription complete / pre-paste" cue (back-compat alias).
    /// Pipeline call sites prefer the explicit `playTranscribeComplete` /
    /// `playEnhanceComplete` cues; this remains for any caller still wired to
    /// the legacy stop-sound semantics and maps to transcribe complete.
    func playStopSound() {
        playTranscribeComplete()
    }

    /// Cancel cue. Descending two-note A4 → E4 (or user override).
    func playEscSound() {
        playCue(.cancel)
    }

    /// Transcription-complete cue (post-ASR, pre-enhance OR pre-paste-without-
    /// enhance). C–E–G–B major-7 arpeggio (or user override).
    func playTranscribeComplete() {
        playCue(.transcribeComplete)
    }

    /// Enhancement-complete cue (post-enhance, pre-paste). Stacked arpeggio
    /// (or user override).
    func playEnhanceComplete() {
        playCue(.enhanceComplete)
    }

    /// Failure cue. Descending minor F4 → Db4 (or user override).
    func playFail() {
        playCue(.fail)
    }

    /// Plays the cue corresponding to a `CustomSoundManager.SoundType`. Used by
    /// the Custom Sounds settings view's ▶ Play button so the preview matches
    /// runtime playback (custom override if present, else synthesized).
    func playPreview(_ type: CustomSoundManager.SoundType) {
        guard isSoundFeedbackEnabled else { return }
        playCue(type)
    }

    private func playCue(_ type: CustomSoundManager.SoundType) {
        guard isSoundFeedbackEnabled else { return }
        if let player = customPlayers[type] {
            // Restart override from start so rapid back-to-back plays don't
            // collide mid-buffer.
            player.currentTime = 0
            player.play()
            return
        }
        synth.play(type.synthCue)
    }

    var isEnabled: Bool {
        get { isSoundFeedbackEnabled }
        set {
            objectWillChange.send()
            isSoundFeedbackEnabled = newValue
        }
    }
}
