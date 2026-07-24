import XCTest
import AppKit
@testable import Sotto

final class MatteContrastTests: XCTestCase {
    /// WCAG 2.x relative-luminance contrast ratio between two sRGB hex colors.
    /// Returns a value in [1, 21].
    static func contrastRatio(_ aHex: UInt32, _ bHex: UInt32) -> Double {
        func lum(_ hex: UInt32) -> Double {
            func chan(_ c: Double) -> Double {
                let s = c / 255.0
                return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
            }
            let r = chan(Double((hex >> 16) & 0xFF))
            let g = chan(Double((hex >> 8) & 0xFF))
            let b = chan(Double(hex & 0xFF))
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }
        let la = lum(aHex) + 0.05, lb = lum(bHex) + 0.05
        return max(la, lb) / min(la, lb)
    }

    // Matte surface ladder (P1 will adopt these exact values).
    let mtCanvas: UInt32 = 0x0d0d0f
    let mtRaise:  UInt32 = 0x16161a
    let mtRaise2: UInt32 = 0x1b1b20

    func testPhosphorAccentClearsGraphicalAAOnAllSurfaces() {
        let phosphor: UInt32 = 0xb9f27e
        for bg in [mtCanvas, mtRaise, mtRaise2] {
            XCTAssertGreaterThanOrEqual(
                Self.contrastRatio(phosphor, bg), 3.0,
                "phosphor accent must clear AA graphical (3:1) on every matte surface")
        }
    }

    func testStateColorsClearGraphicalAA() {
        let states: [UInt32] = [0xff5a52 /*record*/, 0x7fb4ff /*processing*/,
                                0x8af06e /*commit*/, 0xffb86b /*fail*/]
        for c in states {
            for bg in [mtCanvas, mtRaise, mtRaise2] {
                XCTAssertGreaterThanOrEqual(Self.contrastRatio(c, bg), 3.0)
            }
        }
    }

    func testInkBodyTextClearsTextAA() {
        XCTAssertGreaterThanOrEqual(Self.contrastRatio(0xe7e7ea, mtRaise), 4.5) // primary
        XCTAssertGreaterThanOrEqual(Self.contrastRatio(0x9a9aa2, mtRaise), 4.5) // secondary
    }

    /// inkTertiary is a KNOWN large-text/graphical-only token: it clears 3:1
    /// but NOT 4.5:1. This test documents+enforces that boundary so no one
    /// uses it for body copy.
    func testInkTertiaryIsLargeTextOnly() {
        let r = Self.contrastRatio(0x6d6d78, mtRaise)
        XCTAssertGreaterThanOrEqual(r, 3.0)
        XCTAssertLessThan(r, 4.5)
    }
}
