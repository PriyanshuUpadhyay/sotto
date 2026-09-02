import XCTest
@testable import Sotto

/// Source-scan tests for the palette VIEW + CONTROLLER (Tasks 7–8). These are
/// runtime SwiftUI/AppKit surfaces with no headless behavior to assert, so we
/// scan the source for the onyx-token contract + controller invariants instead.
/// Self-contained: own private file-reading helper keyed off `#filePath`.
final class CommandPaletteViewTests: XCTestCase {

    /// Reads a source file under `Sotto/Views/CommandPalette/`. `#filePath`
    /// is `.../SottoTests/CommandPaletteViewTests.swift`; dropping two path
    /// components lands on the repo root.
    private func paletteSource(_ file: String) -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sotto/Views/CommandPalette/\(file)")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Task 7: view source-scan

    func test_paletteView_usesMatteTokens_notRawColors() {
        let src = paletteSource("CommandPalette.swift")
        XCTAssertFalse(src.isEmpty, "CommandPalette.swift not found")
        // Semantic tokens — surfaces, hairline and the phosphor signal all via
        // `Palette.*`, never raw literals. The card is Liquid Glass now, so its
        // surfaces are the glass tokens: the selected row is a lift on the
        // material and the footer a recess, in place of the matte slabs, and the
        // card's border is drawn by the material (and, in the opaque
        // accessibility branch, by `.sottoGlass`) rather than by this file.
        XCTAssertTrue(src.contains("sottoGlass(.panel"))
        XCTAssertTrue(src.contains("Palette.glassChipFill"))
        XCTAssertTrue(src.contains("Palette.glassScrim"))
        XCTAssertTrue(src.contains("Palette.mtLine"))
        XCTAssertTrue(src.contains("Palette.phosphor"))
        // No NavigationSplitView / .searchable (crash-guard rule for search surfaces).
        XCTAssertFalse(src.contains("NavigationSplitView"))
        XCTAssertFalse(src.contains(".searchable"))
    }

    // MARK: - Task 8: controller source-scan

    func test_controller_capturesFrontmostApp_and_singleton() {
        let src = paletteSource("CommandPaletteController.swift")
        XCTAssertFalse(src.isEmpty)
        XCTAssertTrue(src.contains("static let shared"))
        XCTAssertTrue(src.contains("frontmostApplication"))   // captures target before stealing focus
        XCTAssertTrue(src.contains("func toggle"))
        XCTAssertTrue(src.contains("requiresFocusRestore"))   // honors the restore flag
    }
}
