import XCTest
@testable import Sotto

/// Properties of the launch gate. The feature names two host versions; these
/// hold for every version triple.
final class PlatformSupportPropertyTests: XCTestCase {

    private static let versions = Gen<OperatingSystemVersion> { rng in
        OperatingSystemVersion(
            majorVersion: Gen<Int>.int(in: 10...30).generate(&rng),
            minorVersion: Gen<Int>.int(in: 0...9).generate(&rng),
            patchVersion: Gen<Int>.int(in: 0...9).generate(&rng)
        )
    }

    private static let versionPairs = Gen<(OperatingSystemVersion, OperatingSystemVersion)> { rng in
        (versions.generate(&rng), versions.generate(&rng))
    }

    private func parts(_ version: OperatingSystemVersion) -> (Int, Int, Int) {
        (version.majorVersion, version.minorVersion, version.patchVersion)
    }

    /// The gate IS the version comparison — no host is accepted or rejected for
    /// any other reason.
    func test_outcome_isExactlyTheVersionComparison() {
        forAll(Self.versions, "a host opens the menu bar item exactly when it meets the minimum") { host in
            let supported = PlatformSupport.launchOutcome(hostVersion: host) == .opensMenuBarItem
            return supported == (parts(host) >= parts(PlatformSupport.minimumMacOS))
        }
    }

    /// Monotone: upgrading macOS can never take support away.
    func test_support_isMonotoneInVersion() {
        forAll(Self.versionPairs, "a newer host is supported whenever an older one is") { pair in
            let (first, second) = pair
            let (older, newer) = parts(first) <= parts(second) ? (first, second) : (second, first)
            guard PlatformSupport.launchOutcome(hostVersion: older) == .opensMenuBarItem else { return true }
            return PlatformSupport.launchOutcome(hostVersion: newer) == .opensMenuBarItem
        }
    }

    func test_outcome_isAlwaysOneOfTheTwoDocumentedResults() {
        forAll(Self.versions, "every host gets a documented launch outcome") { host in
            let outcome = PlatformSupport.launchOutcome(hostVersion: host)
            return outcome == .opensMenuBarItem || outcome == .unsupportedMacOSVersion
        }
    }
}
