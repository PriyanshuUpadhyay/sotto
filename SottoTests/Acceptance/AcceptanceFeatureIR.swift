import Foundation

/// The APS intermediate representation `gherkin-parser` writes for one feature.
///
/// The generated tests name the scenario and example row they run and read the
/// step text from here, so pointing the runtime at a mutated IR changes what the
/// same built test executes. That is what acceptance mutation needs.
struct AcceptanceFeatureIR: Decodable {
    let name: String
    let scenarios: [Scenario]
    let background: [Step]?

    struct Scenario: Decodable {
        let name: String
        let steps: [Step]
        let examples: [[String: Value]]?
    }

    struct Step: Decodable {
        let text: String
    }

    /// An example cell. The parser writes strings, but a mutation may put any
    /// JSON scalar in a cell, and a step reads whatever is there as text.
    enum Value: Decodable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null

        var text: String {
            switch self {
            case .string(let s): return s
            case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
            case .bool(let b):   return String(b)
            case .null:          return ""
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let s = try? container.decode(String.self) {
                self = .string(s)
            } else if let b = try? container.decode(Bool.self) {
                self = .bool(b)
            } else {
                self = .number(try container.decode(Double.self))
            }
        }
    }

    /// The steps of one example row, background first, with every `<placeholder>`
    /// replaced by the row's value.
    func steps(scenarioIndex: Int, exampleIndex: Int) throws -> [String] {
        guard scenarios.indices.contains(scenarioIndex) else {
            throw LoadError.noSuchScenario(feature: name, index: scenarioIndex)
        }
        let scenario = scenarios[scenarioIndex]
        let rows = scenario.examples ?? []
        let example: [String: Value]
        if rows.isEmpty {
            // A scenario with no Examples table runs once, with nothing to substitute.
            guard exampleIndex == 0 else {
                throw LoadError.noSuchExample(scenario: scenario.name, index: exampleIndex)
            }
            example = [:]
        } else {
            guard rows.indices.contains(exampleIndex) else {
                throw LoadError.noSuchExample(scenario: scenario.name, index: exampleIndex)
            }
            example = rows[exampleIndex]
        }
        return ((background ?? []) + scenario.steps)
            .map { AcceptanceFeatureIR.substitute($0.text, example: example) }
    }

    /// Replaces every `<key>` in `text` with that key's value from `example`.
    static func substitute(_ text: String, example: [String: Value]) -> String {
        example.reduce(text) { result, entry in
            result.replacingOccurrences(of: "<\(entry.key)>", with: entry.value.text)
        }
    }

    enum LoadError: Error, CustomStringConvertible {
        case missingPath
        case unreadable(String)
        case noSuchFeature(String)
        case noSuchScenario(feature: String, index: Int)
        case noSuchExample(scenario: String, index: Int)

        var description: String {
            switch self {
            case .missingPath:
                return "SOTTO_ACCEPTANCE_IR is not set — run the suite through bin/acceptance"
            case .unreadable(let path):
                return "acceptance IR not readable at \(path) — run bin/acceptance"
            case .noSuchFeature(let name):
                return "no feature named \"\(name)\" in the IR — regenerate with bin/acceptance"
            case .noSuchScenario(let feature, let index):
                return "feature \"\(feature)\" has no scenario at index \(index) — the generated tests are stale"
            case .noSuchExample(let scenario, let index):
                return "scenario \"\(scenario)\" has no example row at index \(index) — the generated tests are stale"
            }
        }
    }
}

/// Every feature IR the run was pointed at, indexed by feature name.
///
/// `SOTTO_ACCEPTANCE_IR` is a colon-separated list of JSON files and directories.
/// Earlier entries win, so a mutation run names its mutated file first and the
/// base IR directory second.
struct AcceptanceIRSet {
    private let byFeatureName: [String: AcceptanceFeatureIR]

    static func load() throws -> AcceptanceIRSet {
        guard let raw = ProcessInfo.processInfo.environment["SOTTO_ACCEPTANCE_IR"], !raw.isEmpty else {
            throw AcceptanceFeatureIR.LoadError.missingPath
        }
        var indexed: [String: AcceptanceFeatureIR] = [:]
        for entry in raw.split(separator: ":").map(String.init) {
            for file in try jsonFiles(at: entry) {
                guard let data = FileManager.default.contents(atPath: file) else {
                    throw AcceptanceFeatureIR.LoadError.unreadable(file)
                }
                let ir = try JSONDecoder().decode(AcceptanceFeatureIR.self, from: data)
                if indexed[ir.name] == nil { indexed[ir.name] = ir }
            }
        }
        return AcceptanceIRSet(byFeatureName: indexed)
    }

    private static func jsonFiles(at path: String) throws -> [String] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw AcceptanceFeatureIR.LoadError.unreadable(path)
        }
        guard isDirectory.boolValue else { return [path] }
        let names = try FileManager.default.contentsOfDirectory(atPath: path)
        return names.filter { $0.hasSuffix(".json") }.sorted().map { "\(path)/\($0)" }
    }

    func feature(named name: String) throws -> AcceptanceFeatureIR {
        guard let ir = byFeatureName[name] else {
            throw AcceptanceFeatureIR.LoadError.noSuchFeature(name)
        }
        return ir
    }
}
