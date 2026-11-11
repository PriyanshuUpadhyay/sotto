#if SOTTO_AUDIO_FIXTURE
import AVFoundation
import Foundation
import Testing
@testable import Sotto

/// `SOTTO_AUDIO_FIXTURE` replaces the microphone: a recording with no device
/// streams the file's audio and writes the same audio to the recording WAV.
struct AudioFixtureTests {
    /// A 16 kHz mono Int16 WAV whose sample n is (n % 200) * 100, so the
    /// expected stream values are known without decoding.
    private func writeRamp(to url: URL, frames: Int) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings,
                                   commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for n in 0..<frames { buffer.int16ChannelData![0][n] = Int16((n % 200) * 100) }
        try file.write(from: buffer)
    }

    @Test func aRecordingStreamsAndSavesTheFixtureInPlaceOfTheMicrophone() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sotto-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = dir.appendingPathComponent("ramp.wav")
        let recording = dir.appendingPathComponent("recording.wav")
        try writeRamp(to: fixture, frames: 16000)

        setenv(CoreAudioRecorder.audioFixtureEnvironmentKey, fixture.path, 1)
        defer { unsetenv(CoreAudioRecorder.audioFixtureEnvironmentKey) }

        let lock = NSLock()
        var streamed = [Int16]()
        let recorder = CoreAudioRecorder()
        recorder.onAudioChunk = { data in
            data.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                lock.lock(); streamed.append(contentsOf: samples); lock.unlock()
            }
        }
        try recorder.startRecording(toOutputFile: recording, deviceID: 0)
        Thread.sleep(forTimeInterval: 0.3)
        recorder.stopRecording()

        lock.lock(); let got = streamed; lock.unlock()
        #expect(got.count >= 1600)
        #expect(got.count % 160 == 0)
        for n in 0..<got.count {
            let expected = Int((n % 200) * 100)
            if abs(Int(got[n]) - expected) > 1 {
                Issue.record("sample \(n) is \(got[n]), expected \(expected)")
                break
            }
        }
        let saved = try AVAudioFile(forReading: recording)
        #expect(saved.length == AVAudioFramePosition(got.count))
    }
}
#endif
