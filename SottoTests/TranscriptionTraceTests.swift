import Testing
@testable import Sotto

@Suite struct TranscriptionTraceTests {

    @Test("empty trace omits every detail section")
    func emptyOmitsSections() {
        let out = TranscriptionTrace().render()
        #expect(!out.contains("phonetic"))
        #expect(!out.contains("acoustic"))
        #expect(!out.contains("AFM"))
        #expect(!out.contains("rejected"))
    }

    @Test("phonetic section rendered when populated")
    func rendersPhonetic() {
        var t = TranscriptionTrace()
        t.phonetic = [.init(token: "cmax", from: "cmax", to: "cmux", reason: "oov", distance: 1)]
        let out = t.render()
        #expect(out.contains("phonetic"))
        #expect(out.contains("cmux"))
        #expect(out.contains("oov"))
    }

    @Test("acoustic section shows a rejected (below-threshold) term")
    func rendersRejectedAcoustic() {
        var t = TranscriptionTrace()
        t.acoustic = [
            .init(term: "cmux", score: -2.0, kept: true),
            .init(term: "claude", score: -20.0, kept: false),
        ]
        let out = t.render()
        #expect(out.contains("acoustic"))
        #expect(out.contains("rejected"))
        #expect(out.contains("claude"))
    }

    @Test("AFM section rendered with word edits")
    func rendersAFM() {
        var t = TranscriptionTrace()
        t.afmModel = "afm-light"
        t.afmEdits = [.init(from: "teh", to: "the")]
        t.afterEnhance = "the cat"
        let out = t.render()
        #expect(out.contains("AFM"))
        #expect(out.contains("the"))
    }

    @Test("diagnostics section renders audio/session/fallback details")
    func rendersDiagnostics() {
        var t = TranscriptionTrace()
        t.audioDurationSeconds = 7.25
        t.audioSampleCount = 116_000
        t.sessionType = "batch"
        t.streamingFinalLength = 4
        t.fallbackReason = "streaming final 3 chars for 7.25s audio"
        let out = t.render()
        #expect(out.contains("diagnostics"))
        #expect(out.contains("duration=7.25s"))
        #expect(out.contains("samples=116000"))
        #expect(out.contains("streamingFinalLength=4"))
        #expect(out.contains("fallbackReason="))
    }

    @Test("streaming short-result heuristic catches empty and drastic partial-vs-final drops")
    func shortStreamingHeuristic() {
        #expect(StreamingTranscriptionSession.implausiblyShortFallbackReason(text: "", audioDurationSeconds: 1.0, maxObservedTranscriptLength: 0) != nil)
        #expect(StreamingTranscriptionSession.implausiblyShortFallbackReason(text: "Do a", audioDurationSeconds: 7.0, maxObservedTranscriptLength: 20) != nil)
        #expect(StreamingTranscriptionSession.implausiblyShortFallbackReason(text: "Yes", audioDurationSeconds: 1.5, maxObservedTranscriptLength: 3) == nil)
        #expect(StreamingTranscriptionSession.implausiblyShortFallbackReason(text: "Open settings now", audioDurationSeconds: 7.0, maxObservedTranscriptLength: 15) == nil)
    }

    @Test("streaming short-result heuristic uses max-observed-partial evidence, not a fixed floor or duration")
    func shortStreamingHeuristicUsesPartialEvidence() {
        // Same final text "Hi": legitimate when nothing longer was ever observed streaming.
        #expect(StreamingTranscriptionSession.implausiblyShortFallbackReason(text: "Hi", audioDurationSeconds: 60.0, maxObservedTranscriptLength: 2) == nil)
        // Same final text "Hi", but streaming had already shown much more — a dropped commit.
        #expect(StreamingTranscriptionSession.implausiblyShortFallbackReason(text: "Hi", audioDurationSeconds: 60.0, maxObservedTranscriptLength: 40) != nil)
        // Long dictation truncated to a much shorter final commit still falls back.
        #expect(StreamingTranscriptionSession.implausiblyShortFallbackReason(text: String(repeating: "a", count: 30), audioDurationSeconds: 90.0, maxObservedTranscriptLength: 300) != nil)
    }

    // MARK: - Boosting (M2 in-decoder vocabulary rescore)

    @Test("empty trace omits the boosting section")
    func emptyOmitsBoosting() {
        #expect(!TranscriptionTrace().render().contains("boosting"))
    }

    @Test("boosting engaged renders outcome + termCount + terms")
    func rendersBoostingEngaged() {
        var t = TranscriptionTrace()
        t.boosting = .init(outcome: .engaged, termCount: 2, terms: ["cmux", "foyer"])
        let out = t.render()
        #expect(out.contains("boosting"))
        #expect(out.contains("engaged"))
        #expect(out.contains("2 terms"))
        #expect(out.contains("cmux"))
        #expect(out.contains("foyer"))
    }

    @Test("boosting fallback renders the reason")
    func rendersBoostingFallback() {
        var t = TranscriptionTrace()
        t.boosting = .init(outcome: .fellBackToPlainDecode(reason: "empty context"),
                           termCount: 1, terms: ["cmux"])
        let out = t.render()
        #expect(out.contains("boosting"))
        #expect(out.contains("fell back to plain decode"))
        #expect(out.contains("empty context"))
    }

    @Test("boosting ctc-model-missing renders")
    func rendersBoostingCtcMissing() {
        var t = TranscriptionTrace()
        t.boosting = .init(outcome: .ctcModelMissing, termCount: 3, terms: ["a", "b", "c"])
        let out = t.render()
        #expect(out.contains("boosting"))
        #expect(out.contains("ctc model missing"))
    }

    @Test("boosting notAttempted renders and attempted flag derives from outcome")
    func rendersBoostingNotAttempted() {
        var t = TranscriptionTrace()
        t.boosting = .init(outcome: .notAttempted, termCount: 4, terms: [])
        #expect(t.boosting?.attempted == false)
        var engaged = TranscriptionTrace()
        engaged.boosting = .init(outcome: .engaged, termCount: 1, terms: ["x"])
        #expect(engaged.boosting?.attempted == true)
        let out = t.render()
        #expect(out.contains("boosting"))
        #expect(out.contains("not attempted"))
    }

    // MARK: - Pipeline Latency 01: every stage reports a duration

    @Test("the trace names exactly the seven pipeline stages")
    func stagesCoverThePipeline() {
        let names = TranscriptionTrace.Stage.allCases.map(\.rawValue)
        #expect(names == ["asr", "boosting", "filter", "wordReplacement",
                          "acoustic", "phonetic", "enhancement"])
    }

    @Test("a timed stage reports its duration; an untimed one reports none")
    func recordsStageDurations() {
        var t = TranscriptionTrace()
        #expect(t.duration(for: .asr) == nil)
        t.record(.asr, seconds: 0.25)
        #expect(t.duration(for: .asr) == 0.25)
        #expect(t.duration(for: .filter) == nil)
    }

    @Test("closing a stamp records the elapsed time")
    func recordsElapsedSinceStamp() {
        var t = TranscriptionTrace()
        let start = TranscriptionTrace.now()
        t.record(.filter, since: start)
        #expect((t.duration(for: .filter) ?? -1) >= 0)
    }

    @Test("re-timing a stage accumulates rather than overwriting")
    func repeatedStageAccumulates() {
        var t = TranscriptionTrace()
        t.record(.acoustic, seconds: 0.1)
        t.record(.acoustic, seconds: 0.2)
        #expect(abs((t.duration(for: .acoustic) ?? 0) - 0.3) < 0.0001)
    }

    @Test("render lists the timed stages and omits the untimed ones")
    func rendersTimings() {
        var t = TranscriptionTrace()
        t.record(.asr, seconds: 1.5)
        let out = t.render()
        #expect(out.contains("timings"))
        #expect(out.contains("asr=1.500s"))
        #expect(!out.contains("phonetic="))
    }
}
