import XCTest
import SwiftUI
import AppKit
@testable import Sotto

final class MatteTokenTests: XCTestCase {
    private func rgb(
        _ color: Color,
        appearance: NSAppearance.Name = .darkAqua
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
        let resolved = color.resolvedNSColor(in: appearance)
        return (resolved.redComponent, resolved.greenComponent, resolved.blueComponent)
    }

    func testMatteLadderHexValues() {
        let canvas = rgb(Palette.mtCanvas)
        XCTAssertEqual(canvas.r, 0x0d/255.0, accuracy: 0.01)
        XCTAssertEqual(canvas.g, 0x0d/255.0, accuracy: 0.01)
        XCTAssertEqual(canvas.b, 0x0f/255.0, accuracy: 0.01)

        let raise2 = rgb(Palette.mtRaise2)
        XCTAssertEqual(raise2.r, 0x1b/255.0, accuracy: 0.01)
    }

    func testSurfaceLadderIsMonotonicallyLighter() {
        func lightness(_ color: Color) -> CGFloat {
            let components = rgb(color)
            return max(components.r, components.g, components.b)
        }
        XCTAssertLessThan(lightness(Palette.mtCanvas), lightness(Palette.mtRaise))
        XCTAssertLessThan(lightness(Palette.mtRaise), lightness(Palette.mtRaise2))
        XCTAssertLessThan(lightness(Palette.mtRaise2), lightness(Palette.mtLine))
    }

    func testPhosphorAccentValue() {
        let p = rgb(AccentChoice.phosphor.color)
        XCTAssertEqual(p.r, 0xb9/255.0, accuracy: 0.01)
        XCTAssertEqual(p.g, 0xf2/255.0, accuracy: 0.01)
        XCTAssertEqual(p.b, 0x7e/255.0, accuracy: 0.01)
    }

    func testStateColorsExist() {
        // record stays sacred red; the 4-state subset is wired now.
        XCTAssertEqual(rgb(Palette.stateRecord).r, 0xff/255.0, accuracy: 0.01)
        XCTAssertEqual(rgb(Palette.stateCommit).g, 0xf0/255.0, accuracy: 0.01)
        _ = Palette.stateProcessing
        _ = Palette.stateFail
    }

    func testMonoDataFontExists() {
        // Compile-time existence: these are the data/microlabel helpers the
        // matte surfaces consume. A passing build is the assertion.
        _ = Font.mono(13)
        _ = Font.microlabel(11)
    }

    func testMotionReduceMotionBypass() {
        // Normal motion returns the animation; reduceMotion returns nil so
        // .animation(_, value:) becomes an instant cut.
        XCTAssertNotNil(Motion.breathe(reduceMotion: false))
        XCTAssertNil(Motion.breathe(reduceMotion: true))
        XCTAssertEqual(Motion.breatheDuration, 3.0, accuracy: 0.001)
    }

    func testThemeMatteAliasesResolveToLadder() {
        XCTAssertEqual(NSColor(Theme.canvas), NSColor(Palette.mtCanvas))
        XCTAssertEqual(NSColor(Theme.panel), NSColor(Palette.mtRaise))
        XCTAssertEqual(NSColor(Theme.selectedRow), NSColor(Palette.mtRaise2))
    }
}
