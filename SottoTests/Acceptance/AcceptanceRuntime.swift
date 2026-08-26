import Foundation
import XCTest

/// Runs one scenario's steps against the project step handlers.
///
/// Steps arrive fully substituted — the generator has already replaced each
/// `<placeholder>` with its example value — so the runtime's only job is to
/// match each step to a handler and stop at the first one that fails.
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
        steps: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let manifest: AcceptanceManifest
        do {
            manifest = try AcceptanceManifest.load()
        } catch {
            throw XCTSkip("\(error)")
        }

        let world = AcceptanceWorld(manifest: manifest)
        defer { world.tearDown() }

        for step in steps {
            do {
                try dispatch(step, world: world)
            } catch StepError.skipped(let why) {
                throw XCTSkip("\(feature) / \(scenario): \(step) — \(why)")
            } catch let error as StepError {
                XCTFail("\(feature) / \(scenario)\n  step: \(step)\n  \(error)", file: file, line: line)
                return
            }
        }
    }

    private static func dispatch(_ step: String, world: AcceptanceWorld) throws {
        let range = NSRange(step.startIndex..., in: step)
        for (regex, handler) in compiled {
            guard let match = regex.firstMatch(in: step, range: range) else { continue }
            let args = (1..<match.numberOfRanges).compactMap { index -> String? in
                guard let r = Range(match.range(at: index), in: step) else { return nil }
                return String(step[r])
            }
            try handler(args, world)
            return
        }
        throw StepError.undefined(step)
    }
}
