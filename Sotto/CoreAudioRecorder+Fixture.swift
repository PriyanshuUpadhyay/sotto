#if DEBUG
import AVFoundation
import Foundation

/// Test audio. With `SOTTO_AUDIO_FIXTURE=<audio file>` in the environment,
/// every recording plays that file in place of the microphone: it opens no
/// device and feeds the same meters, WAV file, and `onAudioChunk` stream as
/// live capture, in 10 ms chunks at real-time pace, from the file's start at
/// each recording, looping. Benchmarks and acceptance runs can then drive
/// capture -> streaming -> transcription -> paste without a person.
/// Debug builds only. Idea from Hex's `HEX_AUDIO_FIXTURE` (anomalyco/hex, MIT).
extension CoreAudioRecorder {
    static let audioFixtureEnvironmentKey = "SOTTO_AUDIO_FIXTURE"

    static var audioFixtureURL: URL? {
        guard let path = ProcessInfo.processInfo.environment[audioFixtureEnvironmentKey],
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Decodes an audio file to 16 kHz mono Float32, the rate Sotto records at.
    static func loadAudioFixture(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                         channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: file.processingFormat, to: target),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                           frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CoreAudioRecorderError.audioFixtureUnreadable(url.path)
        }
        try file.read(into: input)
        let capacity = AVAudioFrameCount(Double(input.frameLength) * 16000 / file.processingFormat.sampleRate) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw CoreAudioRecorderError.audioFixtureUnreadable(url.path)
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        guard status != .error, let channel = output.floatChannelData?[0], output.frameLength > 0 else {
            throw conversionError ?? CoreAudioRecorderError.audioFixtureUnreadable(url.path)
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    func startFixtureRecording(from fixture: URL, toOutputFile url: URL) throws {
        let samples = try Self.loadAudioFixture(fixture)
        logger.notice("🎙️ Playing audio fixture \(fixture.lastPathComponent, privacy: .public) in place of the microphone")

        deviceFormat = AudioStreamBasicDescription(
            mSampleRate: 16000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
        )
        outputFormat = Self.transcriptionOutputFormat
        let chunkFrames = 160
        conversionBuffer = UnsafeMutablePointer<Int16>.allocate(capacity: chunkFrames)
        conversionBufferSize = UInt32(chunkFrames)
        try createOutputFile(at: url)
        isRecording = true

        // Frames due are computed from elapsed time, so timer jitter never
        // changes the total amount of audio delivered.
        var chunk = [Float32](repeating: 0, count: chunkFrames)
        var position = 0
        var sent = 0
        let start = DispatchTime.now()
        let timer = DispatchSource.makeTimerSource(queue: fixtureQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
        timer.setEventHandler { [unowned self] in
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
            while sent + chunkFrames <= Int(elapsed * 16000) {
                for i in 0..<chunkFrames {
                    chunk[i] = samples[position]
                    position = (position + 1) % samples.count
                }
                chunk.withUnsafeMutableBufferPointer { buffer in
                    var list = AudioBufferList(
                        mNumberBuffers: 1,
                        mBuffers: AudioBuffer(mNumberChannels: 1,
                                              mDataByteSize: UInt32(chunkFrames * 4),
                                              mData: buffer.baseAddress)
                    )
                    calculateMeters(from: &list, frameCount: UInt32(chunkFrames))
                    convertAndWriteToFile(inputBuffer: &list, frameCount: UInt32(chunkFrames))
                }
                sent += chunkFrames
            }
        }
        fixtureTimer = timer
        timer.resume()
    }

    /// Returns only after any running chunk handler has finished, so teardown
    /// can free the buffers that the handler writes.
    func stopFixturePump() {
        guard let timer = fixtureTimer else { return }
        fixtureTimer = nil
        fixtureQueue.sync { timer.cancel() }
    }
}
#endif
