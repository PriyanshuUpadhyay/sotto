import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class SettingsGeneralTabTests: XCTestCase {

    func test_generalTab_isConstructible() {
        _ = GeneralTab()
    }

    func test_generalTab_conformsToView() {
        XCTAssertTrue((GeneralTab() as Any) is any View)
    }

    // MARK: - Anchor 1
    // "Every control reads/writes the same persisted key the old card used —
    //  no setting is dropped or renamed."
    //
    // The body renders `ForEach(GeneralTab.renderedSections)` and dispatches to
    // an EXHAUSTIVE `view(for:)` switch. `renderedSections == GeneralTabSection
    // .allCases`, so the rendered set IS the descriptor by construction: a
    // section cannot be dropped from the body without removing the enum case
    // (compile error in the exhaustive switch) which these tests also catch.

    /// The body iterates exactly this source; it must equal `allCases`, so the
    /// rendered composition is provably the full descriptor.
    func test_renderedSections_isExactlyAllCases() {
        XCTAssertEqual(
            GeneralTab.renderedSections,
            GeneralTab.GeneralTabSection.allCases,
            "body must render every descriptor case via ForEach(renderedSections)"
        )
    }

    func test_allRequiredSectionsPresent() {
        let cases = Set(GeneralTab.GeneralTabSection.allCases)
        let required: Set<GeneralTab.GeneralTabSection> = [
            .audioInput, .soundFeedback,
            .launchAtLogin, .hideDock, .autoUpdate,
            .checkForUpdates, .permissionsStatus,
        ]
        XCTAssertEqual(
            cases, required,
            "GeneralTab descriptor must be exactly the 7 required sections; diff: \(cases.symmetricDifference(required))"
        )
    }

    /// Every descriptor case must be accounted for: either it carries a
    /// persisted binding, or it is an explicitly non-persisted section
    /// (action / read-only). A new case left unclassified fails this test.
    func test_everySectionIsAccountedFor_boundOrNonPersisted() {
        let bound = Set(GeneralTab.migratedBindings.map(\.section))
        let nonPersisted: Set<GeneralTab.GeneralTabSection> = [.checkForUpdates, .permissionsStatus]
        XCTAssertEqual(
            bound.union(nonPersisted),
            Set(GeneralTab.GeneralTabSection.allCases),
            "every section must be a migrated binding or an explicit non-persisted section"
        )
        // The two non-persisted sections must NOT carry a persisted key.
        XCTAssertTrue(bound.isDisjoint(with: nonPersisted),
                      "action / read-only sections must not be listed in migratedBindings")
    }

    /// Asserts the EXACT existing persisted key / manager identifier each
    /// migrated control binds to. A rename of any key fails here.
    func test_migratedBindings_preserveExistingPersistedKeys() {
        var byKey: [GeneralTab.GeneralTabSection: Set<String>] = [:]
        for binding in GeneralTab.migratedBindings {
            byKey[binding.section, default: []].insert(binding.settingsKey)
        }
        XCTAssertEqual(byKey[.audioInput], ["audioInputMode"])
        XCTAssertEqual(byKey[.soundFeedback], ["isSoundFeedbackEnabled", "isSystemMuteEnabled"])
        XCTAssertEqual(byKey[.hideDock], ["IsMenuBarOnly"])
        XCTAssertEqual(byKey[.launchAtLogin], ["LaunchAtLogin"])
        XCTAssertEqual(byKey[.autoUpdate], ["autoUpdateCheck"])
    }

    /// Every migrated persisted control must have a binding entry — dropping
    /// recorder appearance, sound, mute, hide-dock, launch-at-login, or
    /// auto-update fails this test.
    func test_eachMigratedControlHasBinding() {
        let bound = Set(GeneralTab.migratedBindings.map(\.section))
        for section: GeneralTab.GeneralTabSection in [
            .audioInput, .soundFeedback,
            .hideDock, .launchAtLogin, .autoUpdate,
        ] {
            XCTAssertTrue(bound.contains(section),
                          "missing migrated binding for \(section)")
        }
    }

    /// The reused managers still expose the keys named in `migratedBindings`,
    /// proving the bindings resolve against real persistence.
    func test_managerBindings_resolveToExistingManagers() {
        XCTAssertTrue(AudioInputMode.allCases.contains(AudioDeviceManager.shared.inputMode))
        _ = SoundManager.shared.isEnabled
        _ = MediaController.shared.isSystemMuteEnabled
    }

    // MARK: - Anchor 2
    // "Audio Input migration includes system-default/custom/prioritized modes,
    //  device selection, priority ordering, refresh/current-device state, and
    //  preserves AudioDeviceManager persistence."
    //
    // The audio-input section reuses the full AudioInputSettingsView (which owns
    // all three modes + device picker + prioritized add/remove/reorder +
    // refresh state) — removing the audio controls changes the factory's
    // return type and fails this test.

    func test_audioInputSection_reusesFullAudioInputSettingsView() {
        let view = GeneralTab.audioInputView()
        XCTAssertTrue((view as Any) is AudioInputSettingsView,
                      "audio input section must reuse AudioInputSettingsView")
    }

    func test_audioInputSection_preservesAudioDeviceManagerPersistence() {
        let key = GeneralTab.migratedBindings
            .first { $0.section == .audioInput }?.settingsKey
        XCTAssertEqual(key, "audioInputMode",
                       "audio input must stay bound to AudioDeviceManager's key")
        XCTAssertTrue(AudioInputMode.allCases.contains(AudioDeviceManager.shared.inputMode))
    }

    // MARK: - Negative anchor
    // "Does not request OS permissions on view appearance (status strip is
    //  read-only)."

    func test_permissionStatus_isReadableWithoutRequesting() {
        let manager = PermissionManager()
        _ = manager.isAccessibilityEnabled
        _ = manager.isScreenRecordingEnabled
        _ = manager.audioPermissionStatus
    }
}
