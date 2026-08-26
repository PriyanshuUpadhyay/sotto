import XCTest
@testable import Sotto

/// Covers the IR reading the acceptance runtime does. Placeholder substitution
/// and row lookup used to live in the Clojure generator; they moved here when
/// the generated tests became structure-bound, so they are covered here.
final class AcceptanceFeatureIRTests: XCTestCase {

    private func ir(_ json: String) throws -> AcceptanceFeatureIR {
        try JSONDecoder().decode(AcceptanceFeatureIR.self, from: Data(json.utf8))
    }

    // MARK: substitute

    func testReplacesAPlaceholderWithItsExampleValue() {
        XCTAssertEqual(
            AcceptanceFeatureIR.substitute("I open the <tab> settings tab",
                                           example: ["tab": .string("Vocabulary")]),
            "I open the Vocabulary settings tab"
        )
    }

    func testReplacesEveryOccurrenceOfTheSamePlaceholder() {
        XCTAssertEqual(
            AcceptanceFeatureIR.substitute("<w> then <w>", example: ["w": .string("um")]),
            "um then um"
        )
    }

    func testLeavesTextAloneWhenTheExampleIsEmpty() {
        XCTAssertEqual(
            AcceptanceFeatureIR.substitute("the app is running", example: [:]),
            "the app is running"
        )
    }

    func testRendersAWholeNumberWithoutADecimalPoint() {
        XCTAssertEqual(
            AcceptanceFeatureIR.substitute("under <budget> ms", example: ["budget": .number(1500)]),
            "under 1500 ms"
        )
    }

    func testLeavesAnUnmatchedPlaceholderInPlace() {
        XCTAssertEqual(
            AcceptanceFeatureIR.substitute("the <missing> value", example: ["other": .string("x")]),
            "the <missing> value"
        )
    }

    // MARK: steps

    private static let sample = """
    {"name":"F",
     "background":[{"text":"the app is running"}],
     "scenarios":[{"name":"S","steps":[{"text":"I open the <tab> tab"}],
                   "examples":[{"tab":"Vocabulary"},{"tab":"General"}]},
                  {"name":"NoExamples","steps":[{"text":"it holds"}]}]}
    """

    func testPrependsBackgroundStepsToEveryRow() throws {
        let steps = try ir(Self.sample).steps(scenarioIndex: 0, exampleIndex: 0)
        XCTAssertEqual(steps, ["the app is running", "I open the Vocabulary tab"])
    }

    func testUsesTheRowAtTheGivenIndex() throws {
        let steps = try ir(Self.sample).steps(scenarioIndex: 0, exampleIndex: 1)
        XCTAssertEqual(steps, ["the app is running", "I open the General tab"])
    }

    func testRunsAScenarioWithNoExamplesOnceWithNothingSubstituted() throws {
        let steps = try ir(Self.sample).steps(scenarioIndex: 1, exampleIndex: 0)
        XCTAssertEqual(steps, ["the app is running", "it holds"])
    }

    func testRejectsAScenarioIndexTheIRDoesNotHave() throws {
        XCTAssertThrowsError(try ir(Self.sample).steps(scenarioIndex: 9, exampleIndex: 0))
    }

    func testRejectsAnExampleIndexTheScenarioDoesNotHave() throws {
        XCTAssertThrowsError(try ir(Self.sample).steps(scenarioIndex: 0, exampleIndex: 9))
    }

    func testRejectsASecondRowOfAScenarioThatHasNoExamples() throws {
        XCTAssertThrowsError(try ir(Self.sample).steps(scenarioIndex: 1, exampleIndex: 1))
    }
}
