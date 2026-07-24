import XCTest
@testable import Sotto

/// Source-scan tests for the palette INVOCATION wiring (Tasks 9–10): the global
/// `KeyboardShortcuts.Name.commandPalette` + its handler, the absence of any
/// in-app ⌘K (removed — global hotkey only), and the bindable recorder in
/// Settings → Shortcuts. These are App/AppKit wiring surfaces with no headless
/// behavior to assert, so we scan the source instead. Self-contained: own
/// `#filePath`-relative helper.
final class CommandPaletteWiringTests: XCTestCase {

    /// Reads a source file relative to the repo root. `#filePath` is
    /// `.../SottoTests/CommandPaletteWiringTests.swift`; dropping two path
    /// components lands on the repo root.
    private func source(_ relativePath: String) -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(relativePath)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Task 9: invocation wiring

    func test_hotkeyManager_registersCommandPalette_unboundByDefault() {
        let src = source("Sotto/HotkeyManager.swift")
        XCTAssertFalse(src.isEmpty, "HotkeyManager.swift not found")
        // Declared with no `default:` argument → unbound until the user binds it.
        XCTAssertTrue(src.contains("static let commandPalette = Self(\"commandPalette\")"))
        XCTAssertTrue(src.contains("for: .commandPalette"))
        XCTAssertTrue(src.contains("CommandPaletteController.shared.toggle"))
    }

    /// The in-app ⌘K was removed — the palette is driven ONLY by the global,
    /// user-bindable `KeyboardShortcuts.Name.commandPalette` hotkey. Sotto.swift
    /// no longer mounts a hidden ⌘K button.
    func test_contentView_hasNoInApp_cmdK() {
        let src = source("Sotto/Sotto.swift")
        XCTAssertFalse(src.isEmpty, "Sotto.swift not found")
        XCTAssertFalse(src.contains(".keyboardShortcut(\"k\""))
        XCTAssertFalse(src.contains("CommandPaletteController.shared.toggle"))
    }

    // MARK: - Task 10: settings recorder

    func test_shortcutsTab_exposesCommandPaletteRecorder() {
        let src = source("Sotto/Views/Settings/Tabs/ShortcutsTab.swift")
        XCTAssertFalse(src.isEmpty, "ShortcutsTab.swift not found")
        // ShortcutsTab is descriptor-driven: a binding entry + a `recorderCard`
        // switch arm, both keyed off the `.commandPalette` section (the recorder
        // itself lives inside the `recorderCard` helper as `Recorder(for: name)`).
        XCTAssertTrue(src.contains("section: .commandPalette"))
        XCTAssertTrue(src.contains("name: .commandPalette"))
    }
}
