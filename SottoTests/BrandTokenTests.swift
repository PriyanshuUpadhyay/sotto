import XCTest
import SwiftUI
import AppKit
@testable import Sotto

final class BrandTokenTests: XCTestCase {
    // The window surface must be a *dynamic* (appearance-adaptive) color,
    // NOT a fixed onyx hex. We assert it resolves differently in light vs dark.
    // AppKit has no UIKit-style `resolvedColor(with:)`; instead we resolve the
    // dynamic color's components inside each appearance's drawing context.
    func testWindowSurfaceIsAppearanceAdaptive() {
        let base = NSColor(Theme.windowBackground)
        func brightness(_ name: NSAppearance.Name) -> CGFloat {
            var value: CGFloat = -1
            NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
                value = (base.usingColorSpace(.sRGB) ?? base).brightnessComponent
            }
            return value
        }
        XCTAssertNotEqual(brightness(.aqua), brightness(.darkAqua),
                          "windowBackground must adapt to system appearance")
    }
}

extension BrandTokenTests {
    /// Pins the default accent hue. Brand.tint follows the user's stored accent
    /// now, so the assertion explicitly runs on .phosphor and restores both the
    /// live choice and the persisted key (removed again if it was absent) — a
    /// persisted non-default accent must not fail this, and the test must not
    /// leave a key behind.
    @MainActor
    func testBrandIsPhosphor() {
        let key = "SottoAccentChoice"
        let priorChoice = AccentStore.shared.choice
        let priorRaw = UserDefaults.standard.string(forKey: key)
        defer {
            AccentStore.shared.choice = priorChoice
            if priorRaw == nil { UserDefaults.standard.removeObject(forKey: key) }
        }
        AccentStore.shared.choice = .phosphor

        let c = Brand.tint.resolvedNSColor()
        XCTAssertEqual(c.redComponent,   0xB9/255.0, accuracy: 0.01)
        XCTAssertEqual(c.greenComponent, 0xF2/255.0, accuracy: 0.01)
        XCTAssertEqual(c.blueComponent,  0x7E/255.0, accuracy: 0.01)
    }

    /// AccentStore persistence round-trip: a choice write lands in UserDefaults
    /// under the stored key, maps back through AccentChoice(rawValue:), and
    /// re-points Brand.tint / Palette.phosphor. Restores the prior state so the
    /// default-accent assertions above stay valid regardless of test order.
    @MainActor
    func testAccentStore_persistsChoice_andRebindsBrandTint() {
        let key = "SottoAccentChoice"
        let priorChoice = AccentStore.shared.choice
        let priorRaw = UserDefaults.standard.string(forKey: key)
        defer {
            AccentStore.shared.choice = priorChoice
            if priorRaw == nil { UserDefaults.standard.removeObject(forKey: key) }
        }

        AccentStore.shared.choice = .ice

        let stored = UserDefaults.standard.string(forKey: key)
        XCTAssertEqual(stored, "ice", "choice must persist to UserDefaults on set")
        XCTAssertEqual(stored.flatMap(AccentChoice.init(rawValue:)), .ice,
                       "the stored raw value must round-trip back to the same AccentChoice")

        let tint = Brand.tint.resolvedNSColor()
        XCTAssertEqual(tint.redComponent,   0x8A/255.0, accuracy: 0.01)
        XCTAssertEqual(tint.greenComponent, 0xD8/255.0, accuracy: 0.01)
        XCTAssertEqual(tint.blueComponent,  0xFF/255.0, accuracy: 0.01)
    }

    func testAccentChoice_unknownRawValue_fallsBackViaFailableInit() {
        XCTAssertNil(AccentChoice(rawValue: "not-a-color"),
                     "unknown stored values must fail the init so AccentStore falls back to .phosphor")
    }

    /// The store itself falls back: a garbage (or missing) stored value must
    /// initialize to .phosphor, not crash or land on an arbitrary case.
    func testAccentStore_garbageStoredValue_initializesToPhosphor() {
        let suiteName = "AccentStoreFallbackTests"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        suite.set("chartreuse", forKey: "SottoAccentChoice")
        XCTAssertEqual(AccentStore(defaults: suite).choice, .phosphor,
                       "garbage stored value must fall back to the default accent")

        suite.removeObject(forKey: "SottoAccentChoice")
        XCTAssertEqual(AccentStore(defaults: suite).choice, .phosphor,
                       "missing stored value must fall back to the default accent")
    }
}
