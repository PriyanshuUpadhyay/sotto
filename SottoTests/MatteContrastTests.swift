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

    // MARK: - Liquid Glass
    //
    // The recorder family is made of the platform's Liquid Glass, so what sits
    // behind a surface is the user's desktop, not a token — no test can assert a
    // contrast ratio against it. What CAN be pinned is the contract that keeps
    // the material responsible for legibility:
    //   • `Glass.regular` (the variant Apple specifies for components carrying
    //     text) is the only material used, and it is untinted except where
    //     colour is a status signal;
    //   • text on it is `Palette.ink*` plus `glassInkShadow()`, never a lower
    //     rung of the ink ladder;
    //   • the scrim behind the review transcript stays a scrim — a soft recess —
    //     rather than growing back into an opaque slab;
    //   • and every text-carrying surface still falls back to the opaque matte
    //     ladder under Reduce Transparency / Increase Contrast, where the ratios
    //     above apply again (`A11yContractTests`).

    /// The scrim is a recess, not a frost. Above this it stops reading as glass
    /// and the review panel goes back to being an opaque dark slab — which is
    /// exactly what the material change was meant to end.
    func testTranscriptScrimStaysASoftRecess() {
        XCTAssertGreaterThan(Palette.glassScrimAlpha, 0,
            "a zero scrim leaves the transcript with no recess at all")
        XCTAssertLessThanOrEqual(Palette.glassScrimAlpha, 0.25,
            "the glass owns legibility; above 0.25 the scrim reads as a slab")
    }

    /// Colour on glass is reserved for status and must stay faint enough that
    /// the material still reads as glass rather than as a coloured fill.
    func testStateTintOnGlassStaysFaint() {
        XCTAssertLessThanOrEqual(Palette.glassStateTintAlpha, 0.2)
    }

    /// A chip on glass is a thin overlay that belongs to the material (Apple's
    /// rule for elements sitting on Liquid Glass), so its own alpha stays low —
    /// it lifts the surface, it does not replace it.
    func testChipOnGlassIsAThinOverlay() {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let fill = Palette.glassChipFill.resolvedNSColor(in: appearance)
            XCTAssertGreaterThan(fill.alphaComponent, 0,
                                 "the chip must still be visible on the glass")
            XCTAssertLessThanOrEqual(fill.alphaComponent, 0.2,
                                     "a chip is an overlay on the material, not a second surface")
        }
    }

    /// The pill's lens is the platform material plus a LIFT, not a fill. Untinted
    /// regular glass read as a black pill over a dark desktop, so the capsule
    /// carries a faint stain of the opposite polarity in each appearance — faint
    /// enough that the desktop still comes through it, and present in both.
    func testCapsuleLiftIsAFaintStainInBothAppearances() {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            var lift = NSColor.clear
            NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                lift = Palette.glassCapsuleLift.usingColorSpace(.sRGB) ?? .clear
            }
            XCTAssertGreaterThan(lift.alphaComponent, 0,
                                 "without a lift the pill measured as its own backdrop")
            XCTAssertLessThanOrEqual(lift.alphaComponent, 0.25,
                                     "above this the lens stops lensing and reads as a fill")
        }
        // The lift opposes the appearance: a highlight in Dark, a shade in Light.
        var dark = NSColor.clear, light = NSColor.clear
        NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
            dark = Palette.glassCapsuleLift.usingColorSpace(.sRGB) ?? .clear
        }
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            light = Palette.glassCapsuleLift.usingColorSpace(.sRGB) ?? .clear
        }
        XCTAssertGreaterThan(dark.brightnessComponent, light.brightnessComponent)
    }

    /// The rim is a top-lit gradient, so the top stop has to outrun the bottom
    /// one — a rim with equal ends is the flat stroke the material must not get.
    func testRimGlossIsTopLitAndOpposesTheAppearance() {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let top = Palette.glassRimTop.resolvedNSColor(in: appearance)
            let bottom = Palette.glassRimBottom.resolvedNSColor(in: appearance)
            XCTAssertGreaterThan(top.alphaComponent, bottom.alphaComponent,
                                 "the specular edge belongs on top")
            XCTAssertGreaterThan(bottom.alphaComponent, 0,
                                 "the bottom return is softer, not absent")
            XCTAssertLessThanOrEqual(top.alphaComponent, 0.5,
                                     "past this the hairline reads as a drawn border")
        }
        let darkTop = Palette.glassRimTop.resolvedNSColor(in: .darkAqua)
        let lightTop = Palette.glassRimTop.resolvedNSColor(in: .aqua)
        XCTAssertGreaterThan(darkTop.brightnessComponent, lightTop.brightnessComponent)
    }

    /// The ink that rides the glass is body ink with the separation shadow —
    /// never `inkTertiary`, whose ratio is only large-text/graphical even on the
    /// opaque fallback surface.
    func testInkOnGlassIsBodyInkNotTertiary() {
        let onGlass = [Palette.inkPrimary, Palette.inkSecondary]
        XCTAssertFalse(onGlass.contains { $0.resolvedNSColor() == Palette.inkTertiary.resolvedNSColor() })
        // The shadow that separates it from the desktop actually paints.
        XCTAssertGreaterThan(Palette.glassInkShadow.resolvedNSColor().alphaComponent, 0)
    }
}
