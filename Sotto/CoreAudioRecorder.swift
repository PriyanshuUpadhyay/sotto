import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import os

// MARK: - Core Audio Recorder (AUHAL-based, does not change system default device)
final class CoreAudioRecorder: @unchecked Sendable {

    // MARK: - Properties

    let logger = Logger(subsystem: OSLogSubsystems.app, category: "CoreAudioRecorder")

    var audioUnit: AudioUnit?
    var audioFile: ExtAudioFileRef?

    var isRecording = false
    private var currentDeviceID: AudioDeviceID = 0
    private var recordingURL: URL?

    // Device format (what the hardware provides)
    var deviceFormat = AudioStreamBasicDescription()
    // Output format (16kHz mono PCM Int16 for transcription)
    var outputFormat = AudioStreamBasicDescription()

    // Conversion buffer
    var conversionBuffer: UnsafeMutablePointer<Int16>?
    var conversionBufferSize: UInt32 = 0

    // Audio metering (thread-safe)
    let meterLock = NSLock()
    var _averagePower: Float = -160.0
    var _peakPower: Float = -160.0

    var averagePower: Float {
        meterLock.lock()
        defer { meterLock.unlock() }
        return _averagePower
    }

    var peakPower: Float {
        meterLock.lock()
        defer { meterLock.unlock() }
        return _peakPower
    }

    // Pre-allocated render buffer (to avoid malloc in real-time callback)
    var renderBuffer: UnsafeMutablePointer<Float32>?
    var renderBufferSize: UInt32 = 0

    /// Called on the audio thread with raw PCM data (16-bit, 16kHz, mono) for streaming.
    var onAudioChunk: ((_ data: Data) -> Void)?

    // MARK: - Initialization

    init() {}

    deinit {
        stopRecording()
    }

    // MARK: - Public Interface

    /// Starts recording from the specified device to the given URL (WAV format)
    func startRecording(toOutputFile url: URL, deviceID: AudioDeviceID) throws {
        // Stop any existing recording
        stopRecording()

        if deviceID == 0 {
            logger.error("Cannot start recording - no valid audio device (deviceID is 0)")
            throw CoreAudioRecorderError.failedToSetDevice(status: 0)
        }

        // Validate device still exists before proceeding with setup
        guard isDeviceAvailable(deviceID) else {
            logger.error("Cannot start recording - device \(deviceID, privacy: .public) is no longer available")
            throw CoreAudioRecorderError.deviceNotAvailable
        }

        currentDeviceID = deviceID
        recordingURL = url

        logger.notice("🎙️ Starting recording from device \(deviceID, privacy: .public)")
        logDeviceDetails(deviceID: deviceID)

        // Step 1: Create and configure the AudioUnit (AUHAL)
        try createAudioUnit()

        // Step 2: Set the input device (does NOT change system default)
        try setInputDevice(deviceID)

        // Step 3: Configure formats
        try configureFormats()

        // Step 4: Set up the input callback
        try setupInputCallback()

        // Step 5: Create the output file
        try createOutputFile(at: url)

        // Step 6: Initialize and start the AudioUnit
        try startAudioUnit()

        isRecording = true
    }

    /// Stops the current recording
    func stopRecording() {
        guard isRecording || audioUnit != nil else {
            logger.notice("stopRecording: skipped, not recording and no audio unit")
            return
        }
        logger.notice("stopRecording: stopping core audio recorder")

        // Stop and dispose AudioUnit
        if let unit = audioUnit {
            AudioOutputUnitStop(unit)
            AudioComponentInstanceDispose(unit)
            audioUnit = nil
        }

        // Close audio file
        if let file = audioFile {
            ExtAudioFileDispose(file)
            audioFile = nil
        }

        // Free conversion buffer
        if let buffer = conversionBuffer {
            buffer.deallocate()
            conversionBuffer = nil
            conversionBufferSize = 0
        }

        // Free render buffer
        if let buffer = renderBuffer {
            buffer.deallocate()
            renderBuffer = nil
            renderBufferSize = 0
        }

        isRecording = false
        currentDeviceID = 0
        recordingURL = nil

        // Reset meters
        meterLock.lock()
        _averagePower = -160.0
        _peakPower = -160.0
        meterLock.unlock()
    }

    var isCurrentlyRecording: Bool { isRecording }
    var currentRecordingURL: URL? { recordingURL }
    var currentDevice: AudioDeviceID { currentDeviceID }

    /// Switches to a new input device mid-recording without stopping the file write
    func switchDevice(to newDeviceID: AudioDeviceID) throws {
        guard isRecording, let unit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        // Don't switch if it's the same device
        guard newDeviceID != currentDeviceID else { return }

        let oldDeviceID = currentDeviceID
        logger.notice("🎙️ Switching recording device from \(oldDeviceID, privacy: .public) to \(newDeviceID, privacy: .public)")

        // Step 1: Stop the AudioUnit (but keep file open)
        var status = AudioOutputUnitStop(unit)
        if status != noErr {
            logger.warning("🎙️ Warning: AudioOutputUnitStop returned \(status, privacy: .public)")
        }

        // Step 2: Uninitialize to allow reconfiguration
        status = AudioUnitUninitialize(unit)
        if status != noErr {
            logger.warning("🎙️ Warning: AudioUnitUninitialize returned \(status, privacy: .public)")
        }

        // Step 3: Set the new device
        var device = newDeviceID
        status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            // Try to recover by restarting with old device
            logger.error("Failed to set new device: \(status, privacy: .public). Attempting recovery...")
            var recoveryDevice = oldDeviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &recoveryDevice, UInt32(MemoryLayout<AudioDeviceID>.size))
            AudioUnitInitialize(unit)
            AudioOutputUnitStart(unit)
            throw CoreAudioRecorderError.failedToSetDevice(status: status)
        }

        // Step 4: Get new device format
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var newDeviceFormat = AudioStreamBasicDescription()
        status = AudioUnitGetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &newDeviceFormat,
            &formatSize
        )

        if status != noErr {
            throw CoreAudioRecorderError.failedToGetDeviceFormat(status: status)
        }

        // Step 5: Configure callback format for new device
        var callbackFormat = AudioStreamBasicDescription(
            mSampleRate: newDeviceFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size) * newDeviceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size) * newDeviceFormat.mChannelsPerFrame,
            mChannelsPerFrame: newDeviceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            unit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &callbackFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        if status != noErr {
            throw CoreAudioRecorderError.failedToSetFormat(status: status)
        }

        // Step 6: Reallocate buffers if needed
        let maxFrames: UInt32 = 4096
        let bufferSamples = maxFrames * newDeviceFormat.mChannelsPerFrame
        if bufferSamples > renderBufferSize {
            renderBuffer?.deallocate()
            renderBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: Int(bufferSamples))
            renderBufferSize = bufferSamples
        }

        // Reallocate conversion buffer if new sample rate requires more space
        let maxOutputFrames = UInt32(Double(maxFrames) * (outputFormat.mSampleRate / newDeviceFormat.mSampleRate)) + 1
        if maxOutputFrames > conversionBufferSize {
            conversionBuffer?.deallocate()
            conversionBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(maxOutputFrames))
            conversionBufferSize = maxOutputFrames
        }

        // Update stored format
        deviceFormat = newDeviceFormat
        currentDeviceID = newDeviceID

        // Step 7: Reinitialize and restart
        status = AudioUnitInitialize(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToInitialize(status: status)
        }

        status = AudioOutputUnitStart(unit)
        if status != noErr {
            throw CoreAudioRecorderError.failedToStart(status: status)
        }

        logger.notice("🎙️ Successfully switched to device \(newDeviceID, privacy: .public)")
    }

    let inputCallback: AURenderCallback = { (
        inRefCon,
        ioActionFlags,
        inTimeStamp,
        inBusNumber,
        inNumberFrames,
        ioData
    ) -> OSStatus in

        let recorder = Unmanaged<CoreAudioRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
        return recorder.handleInputBuffer(
            ioActionFlags: ioActionFlags,
            inTimeStamp: inTimeStamp,
            inBusNumber: inBusNumber,
            inNumberFrames: inNumberFrames
        )
    }
}
