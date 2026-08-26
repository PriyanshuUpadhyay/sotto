import Foundation

/// Project facts gathered by `acceptance/manifest.clj` before the generated
/// tests run. A fact that could not be gathered is nil, which makes the step
/// that needs it skip with a reason rather than pass on missing evidence.
struct AcceptanceManifest: Decodable {
    let repoRoot: String
    let deploymentTarget: String?
    let documentedMinimumMacOS: [String]
    let declaredSwiftTypes: [String]
    let resolvedPackages: [String]?
    let appBundlePath: String?
    let bundleResources: [String]?
    let binarySymbols: [String]?
    let appBundleSizeMB: Int?

    enum LoadError: Error, CustomStringConvertible {
        case missingPath
        case unreadable(String)

        var description: String {
            switch self {
            case .missingPath:
                return "SOTTO_ACCEPTANCE_MANIFEST is not set — run the suite through bin/acceptance"
            case .unreadable(let path):
                return "acceptance manifest not readable at \(path) — run bin/acceptance"
            }
        }
    }

    static func load() throws -> AcceptanceManifest {
        guard let path = ProcessInfo.processInfo.environment["SOTTO_ACCEPTANCE_MANIFEST"] else {
            throw LoadError.missingPath
        }
        guard let data = FileManager.default.contents(atPath: path) else {
            throw LoadError.unreadable(path)
        }
        return try JSONDecoder().decode(AcceptanceManifest.self, from: data)
    }
}
