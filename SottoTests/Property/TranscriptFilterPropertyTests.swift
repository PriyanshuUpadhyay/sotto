import XCTest
@testable import Sotto

/// Properties of `TranscriptionOutputFilter.removingFillerWords` — the pure
/// core of filler word removal, so the invariants hold for every transcript,
/// not just the three the feature spells out.
final class TranscriptFilterPropertyTests: XCTestCase {

    private static let vocabulary = ["so", "um", "uh", "this", "basically", "like", "plan", "the"]

    private struct Case: CustomStringConvertible {
        let spokenWords: [String]
        let fillerWords: [String]

        var transcript: String { spokenWords.joined(separator: " ") }

        var description: String {
            "transcript=\"\(transcript)\" fillers=\(fillerWords)"
        }
    }

    private static let cases = Gen<Case> { rng in
        let words = Gen<[String]>.array(of: .element(of: vocabulary), count: 0...12).generate(&rng)
        let fillers = Gen<[String]>.subset(of: vocabulary).generate(&rng)
        return Case(spokenWords: words, fillerWords: fillers)
    }

    private func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    // MARK: - Identity

    func test_disabled_leavesEveryTranscriptUntouched() {
        forAll(Self.cases, "removal off is the identity") { testCase in
            TranscriptionOutputFilter.removingFillerWords(
                testCase.transcript, enabled: false, fillerWords: testCase.fillerWords
            ) == testCase.transcript
        }
    }

    func test_emptyList_leavesEveryTranscriptUntouched() {
        forAll(Self.cases, "an empty filler list is the identity") { testCase in
            TranscriptionOutputFilter.removingFillerWords(
                testCase.transcript, enabled: true, fillerWords: []
            ) == testCase.transcript
        }
    }

    // MARK: - Idempotence

    func test_removal_isIdempotent() {
        forAll(Self.cases, "removing twice is the same as removing once") { testCase in
            let once = TranscriptionOutputFilter.removingFillerWords(
                testCase.transcript, enabled: true, fillerWords: testCase.fillerWords
            )
            let twice = TranscriptionOutputFilter.removingFillerWords(
                once, enabled: true, fillerWords: testCase.fillerWords
            )
            return once == twice
        }
    }

    // MARK: - Conservation and ordering

    func test_removal_keepsEveryNonFillerWordInOrder() {
        forAll(Self.cases, "the surviving words are exactly the non-filler words, in order") { testCase in
            let delivered = TranscriptionOutputFilter.removingFillerWords(
                testCase.transcript, enabled: true, fillerWords: testCase.fillerWords
            )
            let expected = testCase.spokenWords.filter { !testCase.fillerWords.contains($0) }
            return words(in: delivered) == expected
        }
    }

    // MARK: - Case insensitivity

    func test_removal_ignoresCase() {
        forAll(Self.cases, "an upper-cased transcript loses the same words") { testCase in
            let delivered = TranscriptionOutputFilter.removingFillerWords(
                testCase.transcript.uppercased(), enabled: true, fillerWords: testCase.fillerWords
            )
            let expected = testCase.spokenWords
                .filter { !testCase.fillerWords.contains($0) }
                .map { $0.uppercased() }
            return words(in: delivered) == expected
        }
    }
}
