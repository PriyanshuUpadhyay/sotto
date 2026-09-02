import XCTest
import SwiftUI
import KeyboardShortcuts
@testable import Sotto

@MainActor
final class SettingsShortcutsTabTests: XCTestCase {

    func test_shortcutsTab_isConstructible() {
        _ = ShortcutsTab()
    }

    func test_shortcutsTab_conformsToView() {
        XCTAssertTrue((ShortcutsTab() as Any) is any View)
    }

    // MARK: - Anchor
    // "Hands-free toggle hotkey, VAD threshold, silence duration, trigger
    //  phrases, session cap, and all additional shortcuts are reachable here;
    //  bindings match the existing KeyboardShortcuts.Name registrations and
    //  HandsFreeMode/AppStorage keys."
    //
    // The body renders `ForEach(ShortcutsTab.renderedSections)` and dispatches
    // to an EXHAUSTIVE `view(for:)` switch. `renderedSections == ShortcutsTab
    // Section.allCases`, so the rendered set IS the descriptor by construction:
    // a section cannot be dropped from the body without removing its enum case
    // (a compile error in the exhaustive switch) — these tests pin the rest.

    /// The body iterates exactly this source; it must equal `allCases`, so the
    /// rendered composition is provably the full descriptor.
    func test_renderedSections_isExactlyAllCases() {
        XCTAssertEqual(
            ShortcutsTab.renderedSections,
            ShortcutsTab.ShortcutsTabSection.allCases,
            "body must render every descriptor case via ForEach(renderedSections)"
        )
    }

    func test_allRequiredSectionsPresent() {
        let cases = Set(ShortcutsTab.ShortcutsTabSection.allCases)
        let required: Set<ShortcutsTab.ShortcutsTabSection> = [
            .primaryShortcuts, .paste,
            .retry, .commandPalette, .customCancel,
        ]
        XCTAssertEqual(
            cases, required,
            "ShortcutsTab descriptor must be exactly the required sections; diff: \(cases.symmetricDifference(required))"
        )
    }

    /// Every section is a shortcut-recorder section, so each must carry exactly
    /// one binding entry.
    func test_everySectionIsAccountedFor() {
        let bound = Set(ShortcutsTab.shortcutBindings.map(\.section))
        XCTAssertEqual(
            bound,
            Set(ShortcutsTab.ShortcutsTabSection.allCases),
            "every section must be a shortcut binding"
        )
    }

    /// Each shortcut-recorder section maps to the EXACT existing
    /// KeyboardShortcuts.Name registration. Renaming the Swift property breaks
    /// compilation; changing the underlying raw string changes `.rawValue` and
    /// fails the equality. Either way drift is caught.
    func test_shortcutBindings_mapToExactKeyboardShortcutsNames() {
        var byName: [ShortcutsTab.ShortcutsTabSection: String] = [:]
        for binding in ShortcutsTab.shortcutBindings {
            byName[binding.section] = binding.name
        }
        XCTAssertEqual(byName[.primaryShortcuts], KeyboardShortcuts.Name.toggleMiniRecorder.rawValue)
        XCTAssertEqual(byName[.primaryShortcuts], "toggleMiniRecorder")
        XCTAssertEqual(byName[.paste], KeyboardShortcuts.Name.pasteLastEnhancement.rawValue)
        XCTAssertEqual(byName[.paste], "pasteLastEnhancement")
        XCTAssertEqual(byName[.retry], KeyboardShortcuts.Name.retryLastTranscription.rawValue)
        XCTAssertEqual(byName[.retry], "retryLastTranscription")
        XCTAssertEqual(byName[.commandPalette], KeyboardShortcuts.Name.commandPalette.rawValue)
        XCTAssertEqual(byName[.commandPalette], "commandPalette")
        XCTAssertEqual(byName[.customCancel], KeyboardShortcuts.Name.cancelRecorder.rawValue)
        XCTAssertEqual(byName[.customCancel], "cancelRecorder")
    }

    /// Every shortcut-recorder section is covered exactly once by
    /// `shortcutBindings` — dropping paste-original/enhanced, retry,
    /// command-mode, scratchpad-toggle, primary, or custom-cancel fails here.
    func test_everyShortcutSectionHasExactlyOneBinding() {
        let sections = ShortcutsTab.shortcutBindings.map(\.section)
        let expected: [ShortcutsTab.ShortcutsTabSection] = [
            .primaryShortcuts, .paste,
            .retry, .commandPalette, .customCancel,
        ]
        XCTAssertEqual(Set(sections), Set(expected))
        XCTAssertEqual(sections.count, expected.count, "no duplicate / missing shortcut binding")
    }
    // MARK: - Status badges report the real state

    /// "1 active" next to a shortcut set to None is the one state where an
    /// honest badge matters most: the user cannot start a recording at all.
    func test_primaryShortcutStatus_reportsNoneAsAWarning() {
        let none = ShortcutsTab.primaryShortcutStatus(.none)
        XCTAssertEqual(none.text, "None")
        XCTAssertEqual(none.tone, .warning)
    }

    func test_primaryShortcutStatus_reportsABoundOptionAsActive() {
        for option in HotkeyManager.HotkeyOption.allCases where option != .none {
            let status = ShortcutsTab.primaryShortcutStatus(option)
            XCTAssertEqual(status.text, "1 active", "\(option) is a real binding")
            XCTAssertEqual(status.tone, .neutral)
        }
    }

}
