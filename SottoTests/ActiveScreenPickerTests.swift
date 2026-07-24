import Testing
import CoreGraphics
@testable import Sotto

@Suite struct ActiveScreenPickerTests {
    // Two side-by-side displays: primary at origin, external to its right.
    private let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let external = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    @Test("mouse on the external display picks the external display")
    func mouseOnExternal() {
        let i = ActiveScreenPicker.pick(
            mouse: CGPoint(x: 2000, y: 500),
            frames: [primary, external],
            mainIndex: 0
        )
        #expect(i == 1)
    }

    @Test("mouse on the primary display picks the primary display")
    func mouseOnPrimary() {
        let i = ActiveScreenPicker.pick(
            mouse: CGPoint(x: 200, y: 200),
            frames: [primary, external],
            mainIndex: 0
        )
        #expect(i == 0)
    }

    @Test("mouse off every display falls back to NSScreen.main's index")
    func mouseOffscreenFallsBackToMain() {
        let i = ActiveScreenPicker.pick(
            mouse: CGPoint(x: -500, y: -500),
            frames: [primary, external],
            mainIndex: 1
        )
        #expect(i == 1)
    }

    @Test("out-of-range main index falls back to 0")
    func badMainIndex() {
        let i = ActiveScreenPicker.pick(
            mouse: CGPoint(x: -500, y: -500),
            frames: [primary, external],
            mainIndex: 9
        )
        #expect(i == 0)
    }

    @Test("no displays returns 0 (caller guards emptiness)")
    func empty() {
        let i = ActiveScreenPicker.pick(mouse: .zero, frames: [], mainIndex: 0)
        #expect(i == 0)
    }
}
