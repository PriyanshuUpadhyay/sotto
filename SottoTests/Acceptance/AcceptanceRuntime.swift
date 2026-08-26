import Foundation
import XCTest

/// Runs one scenario example row against the project step handlers.
///
/// The generated test names the scenario and row; the step text, the background
/// steps, and the row's values all come from the IR this run was pointed at. So
/// the same built test bundle runs any mutated IR, which is what lets acceptance
/// mutation reuse one build instead of regenerating per mutation.
@MainActor
enum AcceptanceRuntime {

    private static let compiled: [(regex: NSRegularExpression, handler: AcceptanceSteps.Handler)] = {
        AcceptanceSteps.registry.map { entry in
            // A malformed step pattern is a defect in this file, not test data.
            (try! NSRegularExpression(pattern: entry.pattern), entry.handler)
        }
    }()

    static func run(
        feature: String,
        scenario: String,
        scenarioIndex: Int,
        exampleIndex: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let manifest: AcceptanceManifest
        let steps: [String]
        do {
            manifest = try AcceptanceManifest.load()
            steps = try AcceptanceIRSet.load()
                .feature(named: feature)
                .steps(scenarioIndex: scenarioIndex, exampleIndex: exampleIndex)
        } catch {
            throw XCTSkip("\(error)")
        }

        let world = AcceptanceWorld(manifest: manifest)
        defer { world.tearDown() }

        for step in steps {
            do {
                try await dispatch(step, world: world)
            } catch StepError.skipped(let why) {
                throw XCTSkip("\(feature) / \(scenario): \(step) — \(why)")
            } catch let error as StepError {
                XCTFail("\(feature) / \(scenario)\n  step: \(step)\n  \(error)", file: file, line: line)
                return
            }
        }
    }

    private static func dispatch(_ step: String, world: AcceptanceWorld) async throws {
        let range = NSRange(step.startIndex..., in: step)
        for (regex, handler) in compiled {
            guard let match = regex.firstMatch(in: step, range: range) else { continue }
            let args = (1..<match.numberOfRanges).compactMap { index -> String? in
                guard let r = Range(match.range(at: index), in: step) else { return nil }
                return String(step[r])
            }
            try await handler(args, world)
            return
        }
        throw StepError.undefined(step)
    }
}
