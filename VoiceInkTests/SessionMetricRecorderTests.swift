import Testing
import Foundation
import SwiftData
@testable import VoiceInk

@Suite(.serialized)
struct SessionMetricRecorderTests {

    private func makeContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Transcription.self, SessionMetric.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeCompletedTranscription(
        text: String = "hello world from voice ink",
        enhancedText: String? = nil,
        duration: TimeInterval = 10.0,
        transcriptionDuration: TimeInterval? = 2.0,
        enhancementDuration: TimeInterval? = nil,
        transcriptionModelName: String? = "whisper-large-v3",
        aiEnhancementModelName: String? = nil,
        powerModeName: String? = nil
    ) -> Transcription {
        let t = Transcription(
            text: text,
            duration: duration,
            enhancedText: enhancedText,
            transcriptionModelName: transcriptionModelName,
            aiEnhancementModelName: aiEnhancementModelName,
            transcriptionDuration: transcriptionDuration,
            enhancementDuration: enhancementDuration,
            powerModeName: powerModeName,
            transcriptionStatus: .completed
        )
        return t
    }

    @Test func testRecordsCompletedTranscription() throws {
        let ctx = try makeContext()
        let t = makeCompletedTranscription(
            text: "one two three four five",
            duration: 10,
            transcriptionDuration: 2,
            transcriptionModelName: "whisper-large-v3",
            powerModeName: "default"
        )
        ctx.insert(t)

        let inserted = try SessionMetricRecorder.recordRecorderSession(
            transcription: t,
            model: nil,
            in: ctx
        )
        #expect(inserted == true)

        let metrics = try ctx.fetch(FetchDescriptor<SessionMetric>())
        #expect(metrics.count == 1)
        let m = metrics[0]
        #expect(m.transcriptionId == t.id)
        #expect(m.wordCount == 5)
        #expect(m.audioDuration == 10)
        #expect(m.transcriptionDuration == 2)
        #expect(m.speedFactor == 5.0)
        #expect(m.transcriptionModelName == "whisper-large-v3")
        #expect(m.powerModeName == "default")
        #expect(m.source == "recorder")
    }

    @Test func testIdempotency() throws {
        let ctx = try makeContext()
        let t = makeCompletedTranscription()
        ctx.insert(t)

        let first = try SessionMetricRecorder.recordRecorderSession(
            transcription: t,
            model: nil,
            in: ctx
        )
        let second = try SessionMetricRecorder.recordRecorderSession(
            transcription: t,
            model: nil,
            in: ctx
        )
        #expect(first == true)
        #expect(second == false)

        let metrics = try ctx.fetch(FetchDescriptor<SessionMetric>())
        #expect(metrics.count == 1)
    }

    @Test func testSkipsNonCompletedTranscription() throws {
        let ctx = try makeContext()
        let t = Transcription(
            text: "incomplete",
            duration: 5,
            transcriptionDuration: 1,
            transcriptionStatus: .failed
        )
        ctx.insert(t)

        let inserted = try SessionMetricRecorder.recordRecorderSession(
            transcription: t,
            model: nil,
            in: ctx
        )
        #expect(inserted == false)

        let metrics = try ctx.fetch(FetchDescriptor<SessionMetric>())
        #expect(metrics.count == 0)
    }

    @Test func testWordCountUsesEnhancedText() throws {
        let ctx = try makeContext()
        let t = makeCompletedTranscription(
            text: "raw two three",                  // 3 words
            enhancedText: "enhanced output has six tokens here",  // 6 words
            enhancementDuration: 1.5
        )
        ctx.insert(t)

        _ = try SessionMetricRecorder.recordRecorderSession(
            transcription: t,
            model: nil,
            in: ctx
        )

        let metrics = try ctx.fetch(FetchDescriptor<SessionMetric>())
        #expect(metrics.count == 1)
        #expect(metrics[0].wordCount == 6)
        #expect(metrics[0].enhancementDuration == 1.5)
    }

    @Test func testWordCountFallsBackToRawWhenEnhancementMissing() throws {
        let ctx = try makeContext()
        let t = makeCompletedTranscription(
            text: "raw two three four",            // 4 words
            enhancedText: nil,
            enhancementDuration: nil
        )
        ctx.insert(t)

        _ = try SessionMetricRecorder.recordRecorderSession(
            transcription: t,
            model: nil,
            in: ctx
        )

        let metrics = try ctx.fetch(FetchDescriptor<SessionMetric>())
        #expect(metrics.count == 1)
        #expect(metrics[0].wordCount == 4)
        #expect(metrics[0].enhancementDuration == nil)
    }

    @Test func testSpeedFactorComputation() throws {
        let ctx = try makeContext()
        let t = makeCompletedTranscription(
            duration: 10,
            transcriptionDuration: 2
        )
        ctx.insert(t)

        _ = try SessionMetricRecorder.recordRecorderSession(
            transcription: t,
            model: nil,
            in: ctx
        )

        let metrics = try ctx.fetch(FetchDescriptor<SessionMetric>())
        #expect(metrics.count == 1)
        #expect(metrics[0].speedFactor == 5.0)
    }
}
