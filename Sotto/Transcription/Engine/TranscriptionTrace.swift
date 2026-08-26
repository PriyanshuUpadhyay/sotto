import Foundation

/// Per-utterance observability record: each pipeline stage's text plus the
/// structured detail for the three blind spots — phonetic correction, CTC
/// acoustic confirmation (incl. rejected terms), and AFM word edits. Assembled
/// in `TranscriptionPipeline.run` and emitted once at the end behind the
/// `PipelineTraceLoggingEnabled` debug flag. A plain value type — no manager.
struct TranscriptionTrace {
    struct PhoneticCorrection { let token, from, to, reason: String; let distance: Int }  // reason: "oov" | "homophone-unlock"
    struct AcousticDetection { let term: String; let score: Float; let kept: Bool }
    struct WordEdit { let from, to: String }

    /// M2 in-decoder custom-vocabulary rescore (FluidAudio file-based path).
    /// Non-nil only when the FluidAudio file decode actually ran for the
    /// utterance, so the realtime/streaming (M1) path leaves it nil and renders
    /// no boosting line. `attempted` is derived from `outcome` so the
    /// attempted/outcome pair can't disagree.
    struct BoostingTrace {
        enum Outcome: Equatable {
            case engaged
            case fellBackToPlainDecode(reason: String)
            case ctcModelMissing
            case notAttempted
        }
        let outcome: Outcome
        let termCount: Int
        let terms: [String]
        var attempted: Bool { if case .notAttempted = outcome { return false }; return true }
    }

    /// The pipeline stages `TranscriptionPipeline.run` walks, in order.
    enum Stage: String, CaseIterable {
        case asr, boosting, filter, wordReplacement, acoustic, phonetic, enhancement
    }

    /// Wall-clock cost per stage. A stage that did not run has no entry, so a
    /// missing duration and a zero duration stay distinguishable.
    private(set) var stageDurations: [Stage: TimeInterval] = [:]

    var audioDurationSeconds: Double? = nil
    var audioSampleCount: Int? = nil
    var sessionType = ""
    var streamingFinalLength: Int? = nil
    var fallbackReason = ""
    var asrText = "";  var asrModel = ""
    var boosting: BoostingTrace? = nil
    var afterFilter = "";  var afterWordReplace = ""
    var acoustic: [AcousticDetection] = []
    var phonetic: [PhoneticCorrection] = [];  var afterPhonetic = ""
    var afmModel = "";  var afmEdits: [WordEdit] = [];  var afterEnhance = ""

    func duration(for stage: Stage) -> TimeInterval? { stageDurations[stage] }

    /// Adds to the stage's running total. A stage that runs more than once per
    /// utterance reports the sum of its parts, not just the last one.
    mutating func record(_ stage: Stage, seconds: TimeInterval) {
        stageDurations[stage, default: 0] += seconds
    }

    /// Monotonic stamp taken before a stage starts; close it with
    /// `record(_:since:)`. A stamp rather than a closure because most stages
    /// also write to the trace, and a closure capturing it would overlap
    /// exclusive access.
    static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }

    mutating func record(_ stage: Stage, since start: UInt64) {
        record(stage, seconds: Double(Self.now() &- start) / 1_000_000_000)
    }

    /// Pure, multi-line readable render. Sections appear only when non-empty.
    func render() -> String {
        var lines: [String] = []
        if audioDurationSeconds != nil || audioSampleCount != nil || !sessionType.isEmpty || streamingFinalLength != nil || !fallbackReason.isEmpty {
            var parts: [String] = []
            if !sessionType.isEmpty { parts.append("session=\(sessionType)") }
            if let audioDurationSeconds {
                parts.append("duration=\(String(format: "%.2fs", audioDurationSeconds))")
            }
            if let audioSampleCount { parts.append("samples=\(audioSampleCount)") }
            if let streamingFinalLength { parts.append("streamingFinalLength=\(streamingFinalLength)") }
            if !fallbackReason.isEmpty { parts.append("fallbackReason=\(fallbackReason)") }
            lines.append("diagnostics: \(parts.joined(separator: " "))")
        }
        if !asrText.isEmpty {
            let m = asrModel.isEmpty ? "" : " [\(asrModel)]"
            lines.append("ASR\(m): \(asrText)")
        }
        if let b = boosting {
            let label: String
            switch b.outcome {
            case .engaged: label = "engaged"
            case .fellBackToPlainDecode(let reason): label = "fell back to plain decode: \(reason)"
            case .ctcModelMissing: label = "ctc model missing"
            case .notAttempted: label = "not attempted"
            }
            let shown = b.terms.prefix(20).joined(separator: ", ")
            let more = b.terms.count > 20 ? " +\(b.terms.count - 20) more" : ""
            let termsStr = b.terms.isEmpty ? "" : " (\(shown)\(more))"
            lines.append("boosting [\(label)]: \(b.termCount) terms\(termsStr)")
        }
        if !afterFilter.isEmpty { lines.append("filter: \(afterFilter)") }
        if !afterWordReplace.isEmpty { lines.append("wordReplace: \(afterWordReplace)") }
        if !acoustic.isEmpty {
            lines.append("acoustic:")
            for d in acoustic {
                let mark = d.kept ? "✓" : "✗"
                let rej = d.kept ? "" : " (rejected)"
                lines.append("  \(mark) \(d.term)  score=\(String(format: "%.2f", d.score))\(rej)")
            }
        }
        if !phonetic.isEmpty {
            lines.append("phonetic:")
            for c in phonetic {
                lines.append("  \(c.token): \(c.from) → \(c.to)  (\(c.reason), dist=\(c.distance))")
            }
        }
        if !afterPhonetic.isEmpty { lines.append("afterPhonetic: \(afterPhonetic)") }
        if !afmEdits.isEmpty || !afterEnhance.isEmpty {
            let m = afmModel.isEmpty ? "" : " [\(afmModel)]"
            lines.append("AFM\(m):")
            for e in afmEdits { lines.append("  \(e.from) → \(e.to)") }
            if !afterEnhance.isEmpty { lines.append("  after: \(afterEnhance)") }
        }
        let timed = Stage.allCases.compactMap { stage -> String? in
            guard let seconds = stageDurations[stage] else { return nil }
            return "\(stage.rawValue)=\(String(format: "%.3fs", seconds))"
        }
        if !timed.isEmpty { lines.append("timings: " + timed.joined(separator: " ")) }
        return lines.joined(separator: "\n")
    }
}
