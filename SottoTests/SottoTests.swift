import AppKit
import Testing
import SwiftUI
@testable import Sotto

struct PaletteTests {

    @Test func brandAcidTokenHasExpectedHex() async throws {
        // #D4FF3A == (0.831, 1.000, 0.227). Allow a tiny epsilon for floating-point
        // round-trip through SwiftUI Color components.
        let resolved = Palette.brandAcid.resolveComponents()
        #expect(abs(resolved.r - 0xD4/255.0) < 0.005, "brandAcid red component drifted: \(resolved.r)")
        #expect(abs(resolved.g - 0xFF/255.0) < 0.005, "brandAcid green component drifted: \(resolved.g)")
        #expect(abs(resolved.b - 0x3A/255.0) < 0.005, "brandAcid blue component drifted: \(resolved.b)")
    }

    @Test func successAndWarnAndNeutralTokensRetained() async throws {
        // Sanity: tokens we keep should still resolve to non-clear colors.
        #expect(Palette.success != Color.clear)
        #expect(Palette.warn != Color.clear)
        #expect(Palette.neutral != Color.clear)
    }
}

extension Color {
    func resolvedNSColor(in appearance: NSAppearance.Name = .darkAqua) -> NSColor {
        var resolved = NSColor.clear
        NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
            resolved = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        }
        return resolved
    }
}

private extension Color {
    func resolveComponents() -> (r: Double, g: Double, b: Double) {
        let resolved = resolvedNSColor()
        return (
            Double(resolved.redComponent),
            Double(resolved.greenComponent),
            Double(resolved.blueComponent)
        )
    }
}
