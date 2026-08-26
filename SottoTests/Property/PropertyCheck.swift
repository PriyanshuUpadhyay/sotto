import Foundation
import XCTest

/// A very small property-testing harness.
///
/// The project has no property-testing dependency and the acceptance suite
/// asserts on the exact set of resolved packages, so adding one would change
/// what ships. This covers what the properties here need: seeded generation so
/// a failure reproduces, and a report that names the seed and the input.
///
/// Property tests live under `SottoTests/Property` and are skipped by
/// `make test`; run them with `make property`.

/// SplitMix64 — same input seed, same sequence, on every machine and run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Builds one random value from a seeded source.
struct Gen<Value> {
    let generate: (inout SeededGenerator) -> Value

    func map<Mapped>(_ transform: @escaping (Value) -> Mapped) -> Gen<Mapped> {
        Gen<Mapped> { rng in transform(generate(&rng)) }
    }
}

extension Gen {
    static func always(_ value: Value) -> Gen<Value> {
        Gen { _ in value }
    }

    static func int(in range: ClosedRange<Int>) -> Gen<Int> {
        Gen<Int> { rng in Int.random(in: range, using: &rng) }
    }

    static func element<Element>(of choices: [Element]) -> Gen<Element> {
        Gen<Element> { rng in choices[Int.random(in: 0..<choices.count, using: &rng)] }
    }

    static func array<Element>(of element: Gen<Element>, count: ClosedRange<Int>) -> Gen<[Element]> {
        Gen<[Element]> { rng in
            (0..<Int.random(in: count, using: &rng)).map { _ in element.generate(&rng) }
        }
    }

    /// A subset of `choices`, in the original order, possibly empty or whole.
    static func subset<Element>(of choices: [Element]) -> Gen<[Element]> {
        Gen<[Element]> { rng in choices.filter { _ in Bool.random(using: &rng) } }
    }
}

extension XCTestCase {

    /// The seed every property run starts from. Fixed, so a red run stays red
    /// until the defect is fixed rather than disappearing on a rerun.
    static let propertySeed: UInt64 = 0x5010_7A11_5EED

    /// Checks that `property` holds for every generated value, and reports the
    /// trial, the seed, and the input when it does not.
    func forAll<Value>(
        _ generator: Gen<Value>,
        trials: Int = 200,
        seed: UInt64 = XCTestCase.propertySeed,
        _ what: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ property: (Value) throws -> Bool
    ) rethrows {
        var rng = SeededGenerator(seed: seed)
        for trial in 1...trials {
            let value = generator.generate(&rng)
            guard try property(value) else {
                XCTFail(
                    """
                    property does not hold: \(what)
                      trial: \(trial) of \(trials)
                      seed:  \(seed)
                      input: \(value)
                    """,
                    file: file,
                    line: line
                )
                return
            }
        }
    }
}
