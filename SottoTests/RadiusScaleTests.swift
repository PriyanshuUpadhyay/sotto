import XCTest
@testable import Sotto

final class RadiusScaleTests: XCTestCase {
    func testScaleHasFourSteps() {
        XCTAssertEqual(Radius.control, 6)
        XCTAssertEqual(Radius.card, 10)
        XCTAssertEqual(Radius.panel, 16)
        XCTAssertEqual(Radius.hud, 22)
    }

    func testCapsuleRadius() {
        XCTAssertEqual(Radius.capsule, 19)
    }

    // Concentric nesting: an inner surface inset by `padding` from an outer
    // surface should have radius = outer - padding (clamped at 0).
    func testConcentricInner() {
        XCTAssertEqual(Radius.inner(of: Radius.panel, inset: 6), 10)
        XCTAssertEqual(Radius.inner(of: Radius.control, inset: 10), 0) // clamps
    }
}
