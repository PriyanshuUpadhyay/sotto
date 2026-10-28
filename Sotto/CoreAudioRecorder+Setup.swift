import Foundation
import CoreAudio
import AudioToolbox
import AVFoundation
import os

extension CoreAudioRecorder {
    // MARK: - AudioUnit Setup

    func createAudioUnit() throws {
        var desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        guard let component = AudioComponentFindNext(nil, &desc) else {
            logger.error("AudioUnit not found - HAL Output component unavailable")
            throw CoreAudioRecorderError.audioUnitNotFound
        }

        var unit: AudioUnit?
        var status = AudioComponentInstanceNew(component, &unit)
        guard status == noErr, let audioUnit = unit else {
            logger.error("Failed to create AudioUnit instance: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToCreateAudioUnit(status: status)
        }

        self.audioUnit = audioUnit

        // Enable input on element 1 (input scope)
        var enableInput: UInt32 = 1
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Input,
            1, // Element 1 = input
            &enableInput,
            UInt32(MemoryLayout<UInt32>.size)
        )

        if status != noErr {
            logger.error("Failed to enable audio input: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToEnableInput(status: status)
        }

        // Disable output on element 0 (output scope)
        var disableOutput: UInt32 = 0
        status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            kAudioUnitScope_Output,
            0, // Element 0 = output
            &disableOutput,
            UInt32(MemoryLayout<UInt32>.size)
        )

        if status != noErr {
            logger.error("Failed to disable audio output: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToDisableOutput(status: status)
        }
    }

    func setInputDevice(_ deviceID: AudioDeviceID) throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        var device = deviceID
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &device,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        if status != noErr {
            logger.error("Failed to set input device \(deviceID, privacy: .public): \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetDevice(status: status)
        }
    }

    func configureFormats() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        // Get the device's native format (input scope, element 1)
        var formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var status = AudioUnitGetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Input,
            1,
            &deviceFormat,
            &formatSize
        )

        if status != noErr {
            logger.error("Failed to get device format: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToGetDeviceFormat(status: status)
        }

        // Configure output format: 16kHz, mono, PCM Int16
        outputFormat = AudioStreamBasicDescription(
            mSampleRate: 16000.0,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )

        // Set callback format (Float32 for processing, then convert to Int16 for file)
        var callbackFormat = AudioStreamBasicDescription(
            mSampleRate: deviceFormat.mSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float32>.size) * deviceFormat.mChannelsPerFrame,
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float32>.size) * deviceFormat.mChannelsPerFrame,
            mChannelsPerFrame: deviceFormat.mChannelsPerFrame,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            audioUnit,
            kAudioUnitProperty_StreamFormat,
            kAudioUnitScope_Output,
            1,
            &callbackFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        )

        if status != noErr {
            logger.error("Failed to set audio format: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetFormat(status: status)
        }

        // Log format details
        let devSampleRate = deviceFormat.mSampleRate
        let devChannels = deviceFormat.mChannelsPerFrame
        let devBits = deviceFormat.mBitsPerChannel
        let outSampleRate = outputFormat.mSampleRate
        let outChannels = outputFormat.mChannelsPerFrame
        let outBits = outputFormat.mBitsPerChannel
        logger.notice("🎙️ Device format: sampleRate=\(devSampleRate, privacy: .public), channels=\(devChannels, privacy: .public), bitsPerChannel=\(devBits, privacy: .public)")
        logger.notice("🎙️ Output format: sampleRate=\(outSampleRate, privacy: .public), channels=\(outChannels, privacy: .public), bitsPerChannel=\(outBits, privacy: .public)")
        if devSampleRate != outSampleRate {
            logger.notice("🎙️ Converting: \(Int(devSampleRate), privacy: .public)Hz → \(Int(outSampleRate), privacy: .public)Hz")
        }

        // Pre-allocate buffers for real-time callback (avoid malloc in callback)
        let maxFrames: UInt32 = 4096
        let bufferSamples = maxFrames * deviceFormat.mChannelsPerFrame
        renderBuffer = UnsafeMutablePointer<Float32>.allocate(capacity: Int(bufferSamples))
        renderBufferSize = bufferSamples

        // Pre-allocate conversion buffer (output is always smaller due to downsampling)
        let maxOutputFrames = UInt32(Double(maxFrames) * (outputFormat.mSampleRate / deviceFormat.mSampleRate)) + 1
        conversionBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: Int(maxOutputFrames))
        conversionBufferSize = maxOutputFrames
    }

    func setupInputCallback() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        var callbackStruct = AURenderCallbackStruct(
            inputProc: inputCallback,
            inputProcRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_SetInputCallback,
            kAudioUnitScope_Global,
            0,
            &callbackStruct,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size)
        )

        if status != noErr {
            logger.error("Failed to set input callback: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetCallback(status: status)
        }
    }

    func createOutputFile(at url: URL) throws {
        // Remove existing file if any
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        // Create ExtAudioFile for writing
        var fileRef: ExtAudioFileRef?
        var status = ExtAudioFileCreateWithURL(
            url as CFURL,
            kAudioFileWAVEType,
            &outputFormat,
            nil,
            AudioFileFlags.eraseFile.rawValue,
            &fileRef
        )

        if status != noErr {
            logger.error("Failed to create audio file at \(url.path, privacy: .public): \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToCreateFile(status: status)
        }

        audioFile = fileRef

        // Set client format (what we'll write)
        status = ExtAudioFileSetProperty(
            fileRef!,
            kExtAudioFileProperty_ClientDataFormat,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
            &outputFormat
        )

        if status != noErr {
            logger.error("Failed to set file format: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToSetFileFormat(status: status)
        }
    }

    func startAudioUnit() throws {
        guard let audioUnit = audioUnit else {
            throw CoreAudioRecorderError.audioUnitNotInitialized
        }

        var status = AudioUnitInitialize(audioUnit)
        if status != noErr {
            logger.error("Failed to initialize AudioUnit: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToInitialize(status: status)
        }

        status = AudioOutputUnitStart(audioUnit)
        if status != noErr {
            logger.error("Failed to start AudioUnit: \(status, privacy: .public)")
            throw CoreAudioRecorderError.failedToStart(status: status)
        }
    }
}
