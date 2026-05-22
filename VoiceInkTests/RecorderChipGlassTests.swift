import XCTest
@testable import Sotto

final class RecorderChipGlassTests: XCTestCase {
    // ClusterPhase → HaloPhase mapping (drives recorderChip glass + halo color).

    func test_haloPhase_idle_isHidden() {
        XCTAssertEqual(HaloPhase(clusterPhase: .idle), .hidden)
    }

    func test_haloPhase_recording() {
        XCTAssertEqual(HaloPhase(clusterPhase: .recording), .recording)
    }

    func test_haloPhase_transcribing() {
        XCTAssertEqual(HaloPhase(clusterPhase: .transcribing), .transcribing)
    }

    func test_haloPhase_enhancing() {
        XCTAssertEqual(HaloPhase(clusterPhase: .enhancing), .enhancing)
    }

    func test_haloPhase_done_ignoresPayload() {
        XCTAssertEqual(HaloPhase(clusterPhase: .done(appName: "Notes", preview: "hi")), .done)
    }

    func test_haloPhase_failed_ignoresReason() {
        XCTAssertEqual(HaloPhase(clusterPhase: .failed(reason: "No speech detected")), .failed)
    }
}
