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

    // MARK: - Liquid Glass frost
    //
    // The recorder family is made of the platform's Liquid Glass, so what sits
    // behind a surface is the user's desktop, not a token. Only the FROSTED
    // regions carry `Palette.ink*`: the band behind the word tape and the
    // transcript, and the chips. Those are the `mt*` ladder at
    // `Palette.glassFrostAlpha`, so their composite is computable — these tests
    // pin it against the two extremes a wallpaper can reach.

    /// Alpha-composite `base` over `backdrop`, both opaque sRGB hex.
    static func composite(_ base: UInt32, over backdrop: UInt32, alpha: Double) -> UInt32 {
        var out: UInt32 = 0
        for shift in [UInt32(16), 8, 0] {
            let f = Double((base >> shift) & 0xFF)
            let b = Double((backdrop >> shift) & 0xFF)
            let v = UInt32((f * alpha + b * (1 - alpha)).rounded())
            out |= min(255, v) << shift
        }
        return out
    }

    /// The extremes any wallpaper can push through the glass.
    private let backdrops: [UInt32] = [0xffffff, 0x000000]

    /// Dark appearance: `mtRaise` band, `mtRaise2` chip.
    private let frostBasesDark: [UInt32] = [0x16161a, 0x1b1b20]
    /// Light appearance: same two rungs.
    private let frostBasesLight: [UInt32] = [0xffffff, 0xe8e8ed]

    private func frostComposites(dark: Bool) -> [UInt32] {
        let bases = dark ? frostBasesDark : frostBasesLight
        return bases.flatMap { base in
            backdrops.map { Self.composite(base, over: $0, alpha: Palette.glassFrostAlpha) }
        }
    }

    /// The word tape, the review transcript and every chip label sit on a
    /// frosted region, never on bare glass — so body ink clears text AA no
    /// matter what the desktop puts behind the window.
    func testInkOverFrostClearsTextAAOverAnyBackdrop() {
        for bg in frostComposites(dark: true) {
            XCTAssertGreaterThanOrEqual(Self.contrastRatio(0xe7e7ea, bg), 4.5,
                "inkPrimary must clear text AA on the frost, backdrop-independent")
            XCTAssertGreaterThanOrEqual(Self.contrastRatio(0x9a9aa2, bg), 4.5,
                "inkSecondary (the tentative word) must clear text AA on the frost")
        }
        for bg in frostComposites(dark: false) {
            XCTAssertGreaterThanOrEqual(Self.contrastRatio(0x1d1d1f, bg), 4.5)
            XCTAssertGreaterThanOrEqual(Self.contrastRatio(0x515157, bg), 4.5)
        }
    }

    /// The accent and the state colors ride the chips (retry, settings, key
    /// hints), so they must clear AA graphical on the frost too.
    func testAccentsOverFrostClearGraphicalAAOverAnyBackdrop() {
        let dark: [UInt32] = [0xb9f27e /*phosphor*/, 0xff5a52, 0x7fb4ff, 0x8af06e, 0xffb86b]
        let light: [UInt32] = [0x3d6b00, 0xb42318, 0x005ea8, 0x2f6f1d, 0x8a4b00]
        for bg in frostComposites(dark: true) {
            for c in dark { XCTAssertGreaterThanOrEqual(Self.contrastRatio(c, bg), 3.0) }
        }
        for bg in frostComposites(dark: false) {
            for c in light { XCTAssertGreaterThanOrEqual(Self.contrastRatio(c, bg), 3.0) }
        }
    }

    /// The frost only holds the line above a floor. Pin the alpha so a later
    /// "make it more see-through" tweak has to face this test first.
    func testFrostAlphaStaysAboveTheLegibilityFloor() {
        XCTAssertGreaterThanOrEqual(Palette.glassFrostAlpha, 0.90,
            "below this the tentative word stops clearing 4.5:1 over a white wallpaper")
        XCTAssertLessThanOrEqual(Palette.glassFrostAlpha, 1.0)
    }
}
