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

    // MARK: - Interrogation
    //
    // The scenarios ask whether the project still carries something. How each
    // fact answers that — exact name, case-insensitive name, or substring of a
    // mangled symbol — belongs with the probe that gathered it, not with the
    // step that reads it. A fact the probes could not gather answers nil, so
    // the step skips instead of passing on missing evidence.

    func declaresSwiftType(_ name: String) -> Bool {
        declaredSwiftTypes.contains(name)
    }

    /// Swift manglings embed the type name literally, so a substring search
    /// over the symbol table answers "does the binary still carry this type".
    func binaryExportsSymbol(for typeName: String) -> Bool? {
        binarySymbols?.contains { $0.contains(typeName) }
    }

    func bundleShipsResource(named name: String) -> Bool? {
        bundleResources?.contains(name)
    }

    /// `Package.resolved` records identities in the casing the package author
    /// chose, which need not match the casing the feature file uses.
    func buildResolvesPackage(named name: String) -> Bool? {
        resolvedPackages?.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
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
