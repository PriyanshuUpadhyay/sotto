import Foundation
import AVFoundation
import SwiftUI

/// User-overridable cue storage for the 5 spec cues (§3.10).
///
/// History (P3.G): originally supported `start` + `stop`. Spec § 3.10 expanded
/// to 5 cues — start / transcribeComplete / enhanceComplete / cancel / fail.
/// `stop` is migrated to `transcribeComplete` on first launch and dropped.
///
/// State is dictionary-keyed by `SoundType`, persisted as
/// `isUsingCustom<RawValue>Sound` + `custom<RawValue>SoundFilename` per cue
/// (preserving the existing key shape for `start`).
@MainActor
class CustomSoundManager: ObservableObject {
    static let shared = CustomSoundManager()

    /// Mirrors `CueSynthesizer.Cue`. Raw value is the persistent UserDefaults
    /// + filesystem identifier — DO NOT renumber existing cases.
    enum SoundType: String, CaseIterable, Identifiable {
        case start
        case transcribeComplete
        case enhanceComplete
        case cancel
        case fail

        var id: String { rawValue }

        /// Title shown on the settings card.
        var displayName: String {
            switch self {
            case .start:              return "Start"
            case .transcribeComplete: return "Transcribe complete"
            case .enhanceComplete:    return "Enhance complete"
            case .cancel:             return "Cancel"
            case .fail:               return "Fail"
            }
        }

        /// One-line description shown beneath the card title.
        var description: String {
            switch self {
            case .start:              return "Plays when recording starts."
            case .transcribeComplete: return "Plays after transcription, before enhancement."
            case .enhanceComplete:    return "Plays after enhancement, just before paste."
            case .cancel:             return "Plays when you cancel a recording."
            case .fail:               return "Plays when transcription or enhancement fails."
            }
        }

        /// Bridge to the synthesizer's cue identifier.
        var synthCue: CueSynthesizer.Cue {
            switch self {
            case .start:              return .start
            case .transcribeComplete: return .transcribeComplete
            case .enhanceComplete:    return .enhanceComplete
            case .cancel:             return .cancel
            case .fail:               return .fail
            }
        }

        var isUsingKey: String {
            "isUsingCustom\(rawValueCapitalized)Sound"
        }
        var filenameKey: String {
            "custom\(rawValueCapitalized)SoundFilename"
        }
        /// Filesystem-safe stem — also the prefix the file picker copies onto.
        var standardName: String {
            "Custom\(rawValueCapitalized)Sound"
        }

        private var rawValueCapitalized: String {
            // `start` -> `Start`, `transcribeComplete` -> `TranscribeComplete`.
            guard let first = rawValue.first else { return "" }
            return first.uppercased() + rawValue.dropFirst()
        }
    }

    // MARK: - Published state
    //
    // Single dictionary so SwiftUI re-renders when any cue's override flips.
    // Previous start/stop @Published bools are gone; the view binds via
    // `isUsingCustom(for:)`.

    @Published private(set) var overrideFlags: [SoundType: Bool] = [:]
    private var filenames: [SoundType: String] = [:]

    /// Per-cue waveform preview cache. First read triggers an off-main render
    /// via `prepareWaveformPreview`; subsequent reads are O(1). Cleared never —
    /// synthesized cues are deterministic so the cache is valid for app lifetime.
    private var waveformCache: [SoundType: [Float]] = [:]

    private let maxSoundDuration: TimeInterval = 3.0

    private init() {
        migrateLegacyStopKey()
        for type in SoundType.allCases {
            overrideFlags[type] = UserDefaults.standard.bool(forKey: type.isUsingKey)
            filenames[type] = UserDefaults.standard.string(forKey: type.filenameKey)
        }
        createCustomSoundsDirectoryIfNeeded()
        cleanupLegacyStopSound()
    }

    /// One-shot migration: pre-P3.G builds stored a generic "stop" cue.
    /// Spec §3.10 splits stop into transcribe/enhance complete. Reuse the user's
    /// existing custom file as `transcribeComplete` (closest semantic match —
    /// played at the same point in the pipeline today) and clear the legacy keys.
    private func migrateLegacyStopKey() {
        let legacyIsUsingKey = "isUsingCustomStopSound"
        let legacyFilenameKey = "customStopSoundFilename"
        let defaults = UserDefaults.standard
        let legacyIsUsing = defaults.bool(forKey: legacyIsUsingKey)
        let legacyFilename = defaults.string(forKey: legacyFilenameKey)
        guard legacyIsUsing || legacyFilename != nil else { return }

        let target = SoundType.transcribeComplete
        // Don't clobber if the user already set a transcribeComplete override.
        let alreadySet = defaults.bool(forKey: target.isUsingKey)
        if !alreadySet {
            defaults.set(legacyIsUsing, forKey: target.isUsingKey)
            if let legacyFilename {
                defaults.set(legacyFilename, forKey: target.filenameKey)
            }
        }

        defaults.removeObject(forKey: legacyIsUsingKey)
        defaults.removeObject(forKey: legacyFilenameKey)
    }

    /// Sweep + rename for the legacy `CustomStopSound.<ext>` file. Two cases:
    ///
    ///   1. `transcribeComplete`'s filename pointer still points at
    ///      `CustomStopSound.<ext>` (typical post-migration state). Rename
    ///      the file on disk to the new `CustomTranscribeCompleteSound.<ext>`
    ///      stem and update the in-memory + UserDefaults pointers. Without
    ///      this, the user's later override pick would copy a fresh file
    ///      under the new stem and orphan the legacy one.
    ///   2. Any leftover `CustomStopSound.*` files (e.g. user already had a
    ///      transcribeComplete override pre-migration so the legacy pointer
    ///      was dropped without touching the file) get deleted.
    ///
    /// Runs once per launch from `init`; cheap if nothing matches.
    private func cleanupLegacyStopSound() {
        guard let directory = customSoundsDirectory() else { return }
        let target = SoundType.transcribeComplete

        if let filename = filenames[target], filename.hasPrefix("CustomStopSound.") {
            let ext = (filename as NSString).pathExtension
            let newFilename = ext.isEmpty
                ? target.standardName
                : "\(target.standardName).\(ext)"
            let oldURL = directory.appendingPathComponent(filename)
            let newURL = directory.appendingPathComponent(newFilename)
            if FileManager.default.fileExists(atPath: oldURL.path) {
                if FileManager.default.fileExists(atPath: newURL.path) {
                    try? FileManager.default.removeItem(at: newURL)
                }
                if (try? FileManager.default.moveItem(at: oldURL, to: newURL)) != nil {
                    filenames[target] = newFilename
                    UserDefaults.standard.set(newFilename, forKey: target.filenameKey)
                }
            }
        }

        // Sweep any remaining orphans.
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: directory.path) {
            for entry in entries where entry.hasPrefix("CustomStopSound.") {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(entry))
            }
        }
    }

    private func customSoundsDirectory() -> URL? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return appSupport.appendingPathComponent("VoiceInk/CustomSounds")
    }

    private func createCustomSoundsDirectoryIfNeeded() {
        guard let directory = customSoundsDirectory() else { return }
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    // MARK: - Public override API

    /// True iff the user has supplied (and not since reset) an override file
    /// for this cue.
    func isUsingCustom(for type: SoundType) -> Bool {
        overrideFlags[type] ?? false
    }

    /// Resolved file URL for a cue's user override, or `nil` if none.
    func getCustomSoundURL(for type: SoundType) -> URL? {
        guard isUsingCustom(for: type),
              let filename = filenames[type],
              let directory = customSoundsDirectory() else {
            return nil
        }
        return directory.appendingPathComponent(filename)
    }

    func setCustomSound(url: URL, for type: SoundType) -> Result<Void, CustomSoundError> {
        switch validateAudioFile(url: url) {
        case .failure(let error):
            return .failure(error)
        case .success:
            switch copySoundFile(from: url, standardName: type.standardName) {
            case .failure(let error):
                return .failure(error)
            case .success(let filename):
                filenames[type] = filename
                UserDefaults.standard.set(filename, forKey: type.filenameKey)
                overrideFlags[type] = true
                UserDefaults.standard.set(true, forKey: type.isUsingKey)
                notifyCustomSoundsChanged()
                return .success(())
            }
        }
    }

    func resetSoundToDefault(for type: SoundType) {
        if let filename = filenames[type], let directory = customSoundsDirectory() {
            let fileURL = directory.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: fileURL)
        }
        filenames[type] = nil
        UserDefaults.standard.removeObject(forKey: type.filenameKey)
        overrideFlags[type] = false
        UserDefaults.standard.set(false, forKey: type.isUsingKey)
        notifyCustomSoundsChanged()
    }

    /// Filename stem shown next to the cue label. `nil` when using the
    /// synthesized default.
    func getSoundDisplayName(for type: SoundType) -> String? {
        return filenames[type]
    }

    // MARK: - Waveform preview cache

    /// Returns cached preview samples for the cue's synthesized waveform.
    /// `nil` until the first `prepareWaveformPreview(for:)` call resolves —
    /// callers should render an empty placeholder while pending.
    func cachedWaveformPreview(for type: SoundType) -> [Float]? {
        waveformCache[type]
    }

    /// Triggers an off-main render of the cue's waveform preview if not cached.
    /// Idempotent on the post-completion path: once the cache is populated,
    /// subsequent calls short-circuit at the top check. During the in-flight
    /// window the cache is still `nil`, so concurrent callers can each spawn
    /// a Task — the redundant work is harmless because the synthesizer is
    /// deterministic and the cache write produces identical samples either
    /// way.
    ///
    /// `bins` should match the bar count rendered by the view. Default 48 →
    /// roughly one bar per 5 ms of cue at 230 ms duration.
    func prepareWaveformPreview(for type: SoundType, bins: Int = 48) {
        if waveformCache[type] != nil { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            let samples = CueSynthesizer.waveformPreview(for: type.synthCue, bins: bins)
            await MainActor.run { [weak self] in
                // Convention: announce the change BEFORE mutating state so
                // observers see the new value on the next render pass rather
                // than missing the just-written value.
                self?.objectWillChange.send()
                self?.waveformCache[type] = samples
            }
        }
    }

    private func notifyCustomSoundsChanged() {
        NotificationCenter.default.post(name: NSNotification.Name("CustomSoundsChanged"), object: nil)
    }

    private func copySoundFile(from sourceURL: URL, standardName: String) -> Result<String, CustomSoundError> {
        guard let directory = customSoundsDirectory() else {
            return .failure(.directoryCreationFailed)
        }
        let fileExtension = sourceURL.pathExtension
        let newFilename = "\(standardName).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(newFilename)

        if sourceURL.resolvingSymlinksInPath() == destinationURL.resolvingSymlinksInPath() {
            return .success(newFilename)
        }
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            return .success(newFilename)
        } catch {
            return .failure(.fileCopyFailed)
        }
    }

    private func validateAudioFile(url: URL) -> Result<Void, CustomSoundError> {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .failure(.fileNotFound)
        }

        let asset = AVAsset(url: url)
        let duration = asset.duration.seconds
        guard duration.isFinite && duration > 0 else {
            return .failure(.invalidAudioFile)
        }
        if duration > maxSoundDuration {
            return .failure(.durationTooLong(duration: duration, maxDuration: maxSoundDuration))
        }
        do {
            _ = try AVAudioPlayer(contentsOf: url)
        } catch {
            return .failure(.invalidAudioFile)
        }
        return .success(())
    }
}

enum CustomSoundError: LocalizedError {
    case fileNotFound
    case invalidAudioFile
    case durationTooLong(duration: TimeInterval, maxDuration: TimeInterval)
    case directoryCreationFailed
    case fileCopyFailed

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file not found"
        case .invalidAudioFile:
            return "Invalid audio file format"
        case .durationTooLong(let duration, let maxDuration):
            return String(format: "Audio file is %.1f seconds long. Please use an audio file that is %.0f seconds or shorter.", duration, maxDuration)
        case .directoryCreationFailed:
            return "Failed to create custom sounds directory"
        case .fileCopyFailed:
            return "Failed to copy audio file"
        }
    }
}
