import XCTest
@testable import Sotto

/// Recorder placement geometry + single-state-source guard. The cluster-side
/// `ClusterPhase` state machine these tests once pinned was retired with the
/// Constellation HUD (P2 → matte capsule); its phase/chip coverage now lives in
/// the CapsuleState suite. What survives here is provider-agnostic:
///   • `ConstellationLayout` resolves a finite floating anchor
///   • the removed Bay-specific `RecorderUIState` has not reappeared
final class RecorderStateMachineTests: XCTestCase {

    // MARK: - Floating placement geometry

    /// The floating recorder resolves a finite, on-screen anchor.
    func test_constellation_floatingPlacementResolvesFiniteAnchor() {
        let floating = ConstellationLayout.resolve(mode: .floating, screenWidth: 1440)
        XCTAssertTrue(floating.anchorX.isFinite && floating.anchorX > 0)
        XCTAssertTrue(floating.anchorY.isFinite && floating.anchorY > 0)
    }

    // MARK: - Single state source guard

    /// The Bay-specific `RecorderUIState` representation was removed in m04/f02.
    /// Scan the production tree to assert it has not reappeared as a competing
    /// recorder-state declaration.
    func test_recorderUIState_representationDoesNotExist() {
        let sottoDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SottoTests/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sotto", isDirectory: true)

        guard let walker = FileManager.default.enumerator(
            at: sottoDir, includingPropertiesForKeys: nil
        ) else {
            return XCTFail("could not enumerate \(sottoDir.path)")
        }

        var offenders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
            if source.contains("enum RecorderUIState") || source.contains("struct RecorderUIState") {
                offenders.append(url.lastPathComponent)
            }
        }
        XCTAssertTrue(offenders.isEmpty, "RecorderUIState must not be redeclared: \(offenders)")
    }
}
