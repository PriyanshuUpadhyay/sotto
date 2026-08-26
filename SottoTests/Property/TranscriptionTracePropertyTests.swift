import XCTest
@testable import Sotto

/// Properties of the pipeline stage timings. The example tests pin one or two
/// stages; these hold for any sequence of stage recordings.
final class TranscriptionTracePropertyTests: XCTestCase {

    private struct Recording: CustomStringConvertible {
        let entries: [(stage: TranscriptionTrace.Stage, seconds: TimeInterval)]

        var description: String {
            entries.map { "\($0.stage.rawValue)=\($0.seconds)" }.joined(separator: " ")
        }

        func applied() -> TranscriptionTrace {
            var trace = TranscriptionTrace()
            for entry in entries { trace.record(entry.stage, seconds: entry.seconds) }
            return trace
        }

        func expectedTotal(for stage: TranscriptionTrace.Stage) -> TimeInterval? {
            let seconds = entries.filter { $0.stage == stage }.map(\.seconds)
            return seconds.isEmpty ? nil : seconds.reduce(0, +)
        }
    }

    private static let recordings = Gen<Recording> { rng in
        let stage = Gen<TranscriptionTrace.Stage>.element(of: TranscriptionTrace.Stage.allCases)
        let seconds = Gen<Int>.int(in: 0...5_000).map { TimeInterval($0) / 1_000 }
        let count = Gen<Int>.int(in: 0...12).generate(&rng)
        return Recording(entries: (0..<count).map { _ in
            (stage: stage.generate(&rng), seconds: seconds.generate(&rng))
        })
    }

    /// A stage that ran more than once reports the sum of its parts, and a
    /// stage that never ran reports nothing at all.
    func test_durations_sumPerStageAndStayAbsentWhenNeverRecorded() {
        forAll(Self.recordings, "each stage totals its recordings; unrecorded stages stay nil") { recording in
            let trace = recording.applied()
            return TranscriptionTrace.Stage.allCases.allSatisfy { stage in
                switch (trace.duration(for: stage), recording.expectedTotal(for: stage)) {
                case (nil, nil):
                    return true
                case let (actual?, expected?):
                    return abs(actual - expected) < 0.000_001
                default:
                    return false
                }
            }
        }
    }

    /// A zero-cost stage still reports zero — "did not run" and "ran instantly"
    /// stay distinguishable.
    func test_zeroDuration_isRecordedRatherThanTreatedAsAbsent() {
        forAll(Gen<TranscriptionTrace.Stage>.element(of: TranscriptionTrace.Stage.allCases),
               "recording zero seconds reports zero, not nil") { stage in
            var trace = TranscriptionTrace()
            trace.record(stage, seconds: 0)
            return trace.duration(for: stage) == 0
        }
    }

    /// The rendered timings follow the pipeline order, so the line reads as the
    /// order the stages actually ran in.
    func test_render_listsTimedStagesInPipelineOrder() {
        forAll(Self.recordings, "rendered timings follow Stage.allCases order") { recording in
            let rendered = recording.applied().render()
            guard let line = rendered.split(separator: "\n").first(where: { $0.hasPrefix("timings: ") }) else {
                return recording.entries.isEmpty
            }
            let listed = line.dropFirst("timings: ".count)
                .split(separator: " ")
                .compactMap { $0.split(separator: "=").first.map(String.init) }
            let expected = TranscriptionTrace.Stage.allCases
                .filter { recording.expectedTotal(for: $0) != nil }
                .map(\.rawValue)
            return listed == expected
        }
    }
}
