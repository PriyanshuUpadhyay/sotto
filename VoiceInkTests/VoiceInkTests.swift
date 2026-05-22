import Testing
import SwiftUI
@testable import Sotto

struct PaletteTests {

    @Test func accentTokenHasExpectedHex() async throws {
        // #FF5B3A == (1.000, 0.357, 0.227). Allow a tiny epsilon for floating-point
        // round-trip through SwiftUI Color components.
        let resolved = Palette.accent.resolveComponents()
        #expect(abs(resolved.r - 1.000) < 0.005, "accent red component drifted: \(resolved.r)")
        #expect(abs(resolved.g - 0.357) < 0.005, "accent green component drifted: \(resolved.g)")
        #expect(abs(resolved.b - 0.227) < 0.005, "accent blue component drifted: \(resolved.b)")
    }

    @Test func successAndWarnAndNeutralTokensRetained() async throws {
        // Sanity: tokens we keep should still resolve to non-clear colors.
        #expect(Palette.success != Color.clear)
        #expect(Palette.warn != Color.clear)
        #expect(Palette.neutral != Color.clear)
    }
}

private extension Color {
    /// Pull the SRGB components out of a SwiftUI Color via NSColor on macOS.
    /// Approximate; epsilon of 0.005 in tests is well above NSColor round-trip noise.
    func resolveComponents() -> (r: Double, g: Double, b: Double) {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
        #else
        return (0, 0, 0)
        #endif
    }
}
