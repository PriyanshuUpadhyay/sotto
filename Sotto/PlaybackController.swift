import AppKit
import Combine
import Foundation
import SwiftUI
import MediaRemoteAdapter
class PlaybackController: ObservableObject {
    static let shared = PlaybackController()
    private var mediaController: MediaRemoteAdapter.MediaController

    /// Last state pushed by the listener. Only a hint: the adapter recycles its
    /// helper process every 100 events, and several apps emit nothing when they
    /// are paused, so every decision re-reads the live state and falls back to
    /// this.
    @MainActor private var lastKnownTrackInfo: TrackInfo?

    /// Bundle id of the app this controller paused, i.e. the one it owes a
    /// resume to.
    @MainActor private var pausedBundleId: String?
    @MainActor private var pauseTask: Task<Void, Never>?
    @MainActor private var resumeTask: Task<Void, Never>?
    @MainActor private var isRestartingListener = false

    /// Opened synchronously on the recorder's setup queue when a recording
    /// starts, closed when it stops. `performPause()` re-checks it after its
    /// state probe, so a stop that overtakes a slow pause cannot leave the
    /// media paused for good.
    private let pauseWindowLock = NSLock()
    private var isPauseWindowOpen = false

    private static let probeTimeout: TimeInterval = 0.4
    private static let resumeVerifyDelay: UInt64 = 500_000_000
    private static let listenerRestartDelay: UInt64 = 500_000_000

    @Published var isPauseMediaEnabled: Bool = UserDefaults.standard.bool(forKey: "isPauseMediaEnabled") {
        didSet {
            UserDefaults.standard.set(isPauseMediaEnabled, forKey: "isPauseMediaEnabled")

            if isPauseMediaEnabled {
                startMediaTracking()
            } else {
                stopMediaTracking()
            }
        }
    }

    private init() {
        mediaController = MediaRemoteAdapter.MediaController()

        setupMediaControllerCallbacks()

        if isPauseMediaEnabled {
            startMediaTracking()
        }
    }

    private func setupMediaControllerCallbacks() {
        // The adapter delivers both callbacks on the main queue.
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            MainActor.assumeIsolated { self?.lastKnownTrackInfo = trackInfo }
        }

        mediaController.onListenerTerminated = { [weak self] in
            MainActor.assumeIsolated { self?.restartListener() }
        }
    }

    private func startMediaTracking() {
        mediaController.startListening()
    }

    private func stopMediaTracking() {
        mediaController.stopListening()
        endPauseWindow()
        Task { @MainActor [weak self] in
            self?.lastKnownTrackInfo = nil
            self?.pausedBundleId = nil
        }
    }

    /// The listener is a helper process. If it dies unnoticed the cached state
    /// freezes and media is never paused again.
    @MainActor
    private func restartListener() {
        guard isPauseMediaEnabled, !isRestartingListener else { return }
        isRestartingListener = true

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.listenerRestartDelay)
            guard let self = self else { return }
            self.isRestartingListener = false
            guard self.isPauseMediaEnabled else { return }
            self.mediaController.startListening()
        }
    }

    func beginPauseWindow() {
        pauseWindowLock.lock()
        isPauseWindowOpen = true
        pauseWindowLock.unlock()
    }

    private func endPauseWindow() {
        pauseWindowLock.lock()
        isPauseWindowOpen = false
        pauseWindowLock.unlock()
    }

    private var isPauseWindowStillOpen: Bool {
        pauseWindowLock.lock()
        defer { pauseWindowLock.unlock() }
        return isPauseWindowOpen
    }

    @MainActor
    func pauseMedia() async {
        resumeTask?.cancel()
        resumeTask = nil
        pausedBundleId = nil

        guard isPauseMediaEnabled else { return }

        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.performPause()
        }
        pauseTask = task
        await task.value
    }

    @MainActor
    private func performPause() async {
        // A stale cache that wrongly claims playback would create a resume
        // obligation and start media the user had stopped, so pausing needs a
        // positive live read and never falls back to the cache.
        guard let info = await liveTrackInfo(),
              info.payload.isPlaying == true,
              let bundleId = info.payload.bundleIdentifier,
              isPauseWindowStillOpen else {
            return
        }

        pausedBundleId = bundleId
        mediaController.pause()
    }

    @MainActor
    func resumeMedia() async {
        endPauseWindow()

        // A very short recording can stop before its own pause has decided
        // anything; without this wait the resume sees no obligation and the
        // pause lands afterwards, leaving the media paused for good.
        if let pauseTask {
            await pauseTask.value
        }
        pauseTask = nil

        guard isPauseMediaEnabled, let bundleId = pausedBundleId else { return }
        pausedBundleId = nil

        let delay = MediaController.shared.audioResumptionDelay
        let task = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.performResume(bundleId: bundleId, delay: delay)
        }
        resumeTask = task
        await task.value
    }

    @MainActor
    private func performResume(bundleId: String, delay: Double) async {
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
        }

        guard isAppStillRunning(bundleId: bundleId) else { return }

        if let before = (await liveTrackInfo()) ?? lastKnownTrackInfo,
           let currentBundleId = before.payload.bundleIdentifier {
            // Another app took over the now-playing slot, or the user already
            // resumed by hand.
            guard currentBundleId == bundleId, before.payload.isPlaying != true else { return }
        }

        mediaController.play()

        // Some apps (e.g. Plexamp) ignore the MediaRemote `play` command but
        // respond to the hardware media key. That key is a toggle, so send it
        // only after a read confirms the app is still paused — sending it blind
        // pauses media that has already resumed.
        try? await Task.sleep(nanoseconds: Self.resumeVerifyDelay)
        guard !Task.isCancelled else { return }

        guard let after = await liveTrackInfo(),
              after.payload.bundleIdentifier == bundleId,
              after.payload.isPlaying == false else {
            return
        }

        Self.sendMediaPlayPauseKey()
    }

    /// One-shot read of the live now-playing state. Returns nil when nothing
    /// plays, or when the helper process does not answer in time.
    @MainActor
    private func liveTrackInfo() async -> TrackInfo? {
        await withCheckedContinuation { (continuation: CheckedContinuation<TrackInfo?, Never>) in
            var settled = false
            let settle: (TrackInfo?) -> Void = { info in
                guard !settled else { return }
                settled = true
                continuation.resume(returning: info)
            }

            mediaController.getTrackInfo { settle($0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.probeTimeout) { settle(nil) }
        }
    }

    /// Simulate the hardware media Play/Pause key (NX_KEYTYPE_PLAY = 16).
    private static func sendMediaPlayPauseKey() {
        func post(down: Bool) {
            let flags: UInt = down ? 0xa00 : 0xb00
            let data1 = Int((16 << 16) | ((down ? 0xa : 0xb) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: flags),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            )
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
        post(down: true)
        post(down: false)
    }

    private func isAppStillRunning(bundleId: String) -> Bool {
        let runningApps = NSWorkspace.shared.runningApplications
        return runningApps.contains { $0.bundleIdentifier == bundleId }
    }
}
