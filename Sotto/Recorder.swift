import Foundation
import AVFoundation
import CoreAudio
import os

@MainActor
class Recorder: NSObject, ObservableObject {
    private var recorder: CoreAudioRecorder?
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "Recorder")
    private let deviceManager = AudioDeviceManager.shared
    private var deviceSwitchObserver: NSObjectProtocol?
    private var isReconfiguring = false
    private let mediaController = MediaController.shared
    private let playbackController = PlaybackController.shared
    @Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)
    private var audioMeterUpdateTimer: DispatchSourceTimer?
    private let audioMeterQueue = DispatchQueue(label: "com.sotto.Sotto.audiometer", qos: .userInteractive)
    /// Dedicated serial queue for hardware setup.
    private let audioSetupQueue = DispatchQueue(label: "com.sotto.Sotto.audioSetup", qos: .userInitiated)
    private var audioRestorationTask: Task<Void, Never>?
    /// Non-nil while a hardware teardown is in progress. A concurrent
    /// `stopRecording()` call awaits this instead of returning immediately
    /// (which would race the pipeline reading a not-yet-disposed WAV).
    private var inFlightStopTask: Task<Void, Never>?
    /// Bumped by every start/stop request. A `startRecording()` call aborts
    /// if this no longer matches the value it captured before its await —
    /// a newer stop or start superseded it. Newest request always wins.
    private var opGeneration = 0
    private let smoothedValuesLock = NSLock()
    private var smoothedAverage: Float = 0
    private var smoothedPeak: Float = 0

    /// Audio chunk callback for streaming. Can be updated while recording;
    /// changes are forwarded to the live CoreAudioRecorder.
    var onAudioChunk: ((_ data: Data) -> Void)? {
        didSet { recorder?.onAudioChunk = onAudioChunk }
    }

    /// Raw average power (dBFS) forwarded on every audio-meter tick.
    /// `SottoEngine` sets this to feed `FirstAudioGate` (spec §4.2).
    var onRawAudioDb: ((Float) -> Void)?

    enum RecorderError: Error {
        case couldNotStartRecording
    }
    
    override init() {
        super.init()
        setupDeviceSwitchObserver()
    }

    private func setupDeviceSwitchObserver() {
        deviceSwitchObserver = NotificationCenter.default.addObserver(
            forName: .audioDeviceSwitchRequired,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task {
                await self?.handleDeviceSwitchRequired(notification)
            }
        }
    }

    private func handleDeviceSwitchRequired(_ notification: Notification) async {
        guard !isReconfiguring else { return }
        guard let recorder = recorder else { return }
        guard let userInfo = notification.userInfo,
              let newDeviceID = userInfo["newDeviceID"] as? AudioDeviceID else {
            logger.error("Device switch notification missing newDeviceID")
            return
        }

        // Prevent concurrent device switches and handleDeviceChange() interference
        isReconfiguring = true
        defer { isReconfiguring = false }

        logger.notice("🎙️ Device switch required: switching to device \(newDeviceID, privacy: .public)")

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                audioSetupQueue.async {
                    do {
                        try recorder.switchDevice(to: newDeviceID)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            // Notify user about the switch
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == newDeviceID })?.name {
                await MainActor.run {
                    NotificationManager.shared.showNotification(
                        title: "Switched to: \(deviceName)",
                        type: .info
                    )
                }
            }

            logger.notice("🎙️ Successfully switched recording to device \(newDeviceID, privacy: .public)")
        } catch {
            logger.error("❌ Failed to switch device: \(error.localizedDescription, privacy: .public)")

            // If switch fails, stop recording and notify user
            await handleRecordingError(error)
        }
    }

    func startRecording(toOutputFile url: URL, completion: @escaping (Result<Void, Error>) -> Void) async {
        opGeneration += 1
        let myGen = opGeneration

        // A prior stop's teardown+cleanup may still be finishing — await it
        // inline before installing a new recorder, so the install happens
        // inside the caller's own await (not a fire-and-forget retry the
        // caller can't observe or race a subsequent stop against).
        if let inFlightStopTask {
            await inFlightStopTask.value
        }

        logger.notice("startRecording called – deviceID=\(self.deviceManager.getCurrentDevice(), privacy: .public), file=\(url.lastPathComponent, privacy: .public)")

        let currentDeviceID = deviceManager.getCurrentDevice()
        let lastDeviceID = UserDefaults.standard.string(forKey: "lastUsedMicrophoneDeviceID")
        if String(currentDeviceID) != lastDeviceID {
            if let deviceName = deviceManager.availableDevices.first(where: { $0.id == currentDeviceID })?.name {
                NotificationManager.shared.showNotification(title: "Using: \(deviceName)", type: .info)
            }
        }
        UserDefaults.standard.set(String(currentDeviceID), forKey: "lastUsedMicrophoneDeviceID")

        let deviceID = currentDeviceID

        let coreAudioRecorder = CoreAudioRecorder()
        coreAudioRecorder.onAudioChunk = onAudioChunk

        // A stop (or a newer start) issued while we awaited above supersedes
        // this request — abort before installing, so a stale start can't
        // install a recorder a later stop has already moved past.
        guard opGeneration == myGen else {
            completion(.failure(RecorderError.couldNotStartRecording))
            return
        }

        deviceManager.isRecordingActive = true
        recorder = coreAudioRecorder

        audioRestorationTask?.cancel()
        audioRestorationTask = nil
        audioMeterUpdateTimer?.cancel()

        let capturedLogger = logger
        // Offload initialization to background thread to avoid hotkey lag.
        audioSetupQueue.async { [weak self] in
            do {
                try coreAudioRecorder.startRecording(toOutputFile: url, deviceID: deviceID)
                capturedLogger.notice("startRecording: CoreAudioRecorder started successfully")
                DispatchQueue.main.async { [weak self] in
                    self?.startAudioMeterTimer()
                }
                Task { [weak self] in
                    guard let self = self else { return }
                    await self.playbackController.pauseMedia()
                }
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                capturedLogger.error("Failed to start recording: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor [weak self] in
                    await self?.stopRecording()
                    self?.deviceManager.isRecordingActive = false
                    completion(.failure(error))
                }
            }
        }
    }

    func stopRecording() async {
        // Bumped first, unconditionally — this invalidates any start that
        // captured an earlier generation and is still awaiting a prior stop,
        // even if this call itself only coalesces onto that same stop below.
        opGeneration += 1

        // A stop is already tearing down + cleaning up — coalesce onto it
        // instead of reading `recorder` (already nil'd by the owner) and
        // returning early, which would let the caller proceed before dispose
        // (or `deviceManager.isRecordingActive` settling) completes.
        if let inFlightStopTask {
            await inFlightStopTask.value
            return
        }

        guard let currentRecorder = self.recorder else { return }

        // Clear the callback on the captured instance as the very first
        // mutation — the render thread can still invoke it until this runs,
        // so nothing (not even logging) may precede it.
        currentRecorder.onAudioChunk = nil

        logger.notice("stopRecording called")
        audioMeterUpdateTimer?.cancel()
        audioMeterUpdateTimer = nil
        recorder = nil
        onAudioChunk = nil

        // `inFlightStopTask` covers hardware teardown AND the cleanup below —
        // `startRecording()` awaits this same task before installing a new
        // recorder, so it must not observe a state where only teardown, but
        // not `isRecordingActive`/media restore, has settled.
        let op = Task {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                self.audioSetupQueue.async {
                    currentRecorder.stopRecording()
                    continuation.resume()
                }
            }

            self.smoothedValuesLock.lock()
            self.smoothedAverage = 0
            self.smoothedPeak = 0
            self.smoothedValuesLock.unlock()

            self.audioMeter = AudioMeter(averagePower: 0, peakPower: 0)

            self.audioRestorationTask = Task {
                await self.mediaController.unmuteSystemAudio()
                await self.playbackController.resumeMedia()
            }
            self.deviceManager.isRecordingActive = false
            self.inFlightStopTask = nil
        }
        inFlightStopTask = op
        await op.value
    }

    private func handleRecordingError(_ error: Error) async {
        logger.error("❌ Recording error occurred: \(error.localizedDescription, privacy: .public)")

        // Stop the recording
        await stopRecording()

        // Notify the user about the recording failure
        await MainActor.run {
            NotificationManager.shared.showNotification(
                title: "Recording Failed: \(error.localizedDescription)",
                type: .error
            )
        }
    }

    private func startAudioMeterTimer() {
        let timer = DispatchSource.makeTimerSource(queue: audioMeterQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(17)) 
        timer.setEventHandler { [weak self] in
            self?.updateAudioMeter()
        }
        timer.resume()
        audioMeterUpdateTimer = timer
    }

    private func updateAudioMeter() {
        guard let recorder = recorder else { return }

        // Sample audio levels (thread-safe read)
        let averagePower = recorder.averagePower
        let peakPower = recorder.peakPower

        onRawAudioDb?(averagePower)

        // Normalize values
        let minVisibleDb: Float = -60.0
        let maxVisibleDb: Float = 0.0

        let normalizedAverage: Float
        if averagePower < minVisibleDb {
            normalizedAverage = 0.0
        } else if averagePower >= maxVisibleDb {
            normalizedAverage = 1.0
        } else {
            normalizedAverage = (averagePower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }

        let normalizedPeak: Float
        if peakPower < minVisibleDb {
            normalizedPeak = 0.0
        } else if peakPower >= maxVisibleDb {
            normalizedPeak = 1.0
        } else {
            normalizedPeak = (peakPower - minVisibleDb) / (maxVisibleDb - minVisibleDb)
        }

        // Apply EMA smoothing with thread-safe access
        smoothedValuesLock.lock()
        smoothedAverage = smoothedAverage * 0.6 + normalizedAverage * 0.4
        smoothedPeak = smoothedPeak * 0.6 + normalizedPeak * 0.4
        let newAudioMeter = AudioMeter(averagePower: Double(smoothedAverage), peakPower: Double(smoothedPeak))
        smoothedValuesLock.unlock()

        // Dispatch to main queue for UI updates (more efficient than Task)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.audioMeter = newAudioMeter
        }
    }
    
    // MARK: - Cleanup

    deinit {
        audioMeterUpdateTimer?.cancel()
        audioRestorationTask?.cancel()
        if let observer = deviceSwitchObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

struct AudioMeter: Equatable {
    let averagePower: Double
    let peakPower: Double
}