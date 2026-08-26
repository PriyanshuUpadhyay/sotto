import XCTest
@testable import Sotto

/// Properties of what the enhance step is handed: the output filter's whole
/// cleaning pass, and the gate that decides whether the model is called.
final class EnhancementInputPropertyTests: XCTestCase {

    /// Words, filler, bracketed engine noise, tag blocks, and ragged spacing —
    /// one token of every kind a rule in `cleaning` reacts to.
    private static let tokens = [
        "the", "timeout", "is", "sixty", "seconds.",
        "um", "uh", "hmm",
        "[noise]", "(inaudible)", "{music}", "]", "[",
        "<b>aside</b>", "<i>x", "</i>",
        " ", "  ", "\n"
    ]

    private static let transcripts = Gen<[String]>
        .array(of: .element(of: tokens), count: 0...14)
        .map { $0.joined(separator: " ") }

    private static let fillerLists = Gen<[String]>.subset(of: FillerWordManager.defaultFillerWords)

    private struct Case: CustomStringConvertible {
        let text: String
        let fillerWords: [String]

        var description: String { "text=\"\(text)\" fillers=\(fillerWords)" }
    }

    private static let cases = Gen<Case> { rng in
        Case(text: transcripts.generate(&rng), fillerWords: fillerLists.generate(&rng))
    }

    /// The bracket patterns use `.`, which does not cross a line break, while
    /// the whitespace tidy that runs after them collapses a run containing
    /// that break into one space. So a bracketed run split across lines
    /// survives one pass and is stripped by the next, and idempotence only
    /// holds within one line. `TranscriptionOutputFilterTests` pins that gap.
    private static let singleLineCases = Gen<Case> { rng in
        Case(text: transcripts.generate(&rng).replacingOccurrences(of: "\n", with: " "),
             fillerWords: fillerLists.generate(&rng))
    }

    // MARK: - cleaning

    func test_cleaning_isIdempotentWithinOneLine() {
        forAll(Self.singleLineCases, "cleaning an already cleaned single-line transcript changes nothing") { testCase in
            let once = TranscriptionOutputFilter.cleaning(
                testCase.text, removeFillerWords: true, fillerWords: testCase.fillerWords
            )
            let twice = TranscriptionOutputFilter.cleaning(
                once, removeFillerWords: true, fillerWords: testCase.fillerWords
            )
            return once == twice
        }
    }

    /// The postcondition every later stage relies on: no run of whitespace and
    /// no ragged ends.
    func test_cleaning_alwaysReturnsTidyText() {
        forAll(Self.cases, "the result has no double space and no ragged ends") { testCase in
            let cleaned = TranscriptionOutputFilter.cleaning(
                testCase.text, removeFillerWords: true, fillerWords: testCase.fillerWords
            )
            return cleaned == cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
                && cleaned.range(of: #"\s{2,}"#, options: .regularExpression) == nil
        }
    }

    /// With removal off, the word list must not matter at all.
    func test_cleaning_ignoresTheFillerListWhenRemovalIsOff() {
        forAll(Self.cases, "an off toggle makes the filler list irrelevant") { testCase in
            TranscriptionOutputFilter.cleaning(
                testCase.text, removeFillerWords: false, fillerWords: testCase.fillerWords
            ) == TranscriptionOutputFilter.cleaning(
                testCase.text, removeFillerWords: false, fillerWords: []
            )
        }
    }

    // MARK: - shouldCallModel

    /// The skip is opt-in. With the shipped default off, every transcript goes
    /// to the model however clean it looks — which is what Pipeline Latency 09
    /// asserts for both of its rows.
    func test_shouldCallModel_alwaysCallsWhenTheSkipIsOff() {
        forAll(Self.transcripts, "the model is called for every transcript when the skip is off") { text in
            EnhancementSanityCheck.shouldCallModel(text, skipWhenClean: false)
        }
    }

    /// With the skip on, the gate is exactly the cleanliness verdict.
    func test_shouldCallModel_withSkipOn_isTheCleanlinessVerdict() {
        forAll(Self.transcripts, "the skip fires exactly when the transcript looks clean") { text in
            EnhancementSanityCheck.shouldCallModel(text, skipWhenClean: true)
                == !EnhancementSanityCheck.isLikelyClean(text)
        }
    }
}
