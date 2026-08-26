import XCTest
import SwiftUI
@testable import Sotto

final class A11yContractTests: XCTestCase {
    func testEveryStateHasDistinctNonColorGlyph() {
        let states: [CapsuleState] = [.idleReady, .recording, .processing, .commit, .fail]
        let glyphs = states.map { StateCue.glyph(for: $0) }
        XCTAssertEqual(Set(glyphs).count, glyphs.count,
                       "each state must have a UNIQUE SF Symbol (non-color cue)")
        XCTAssertFalse(glyphs.contains(""), "no empty glyph")
    }

    func testVoiceOverLabelsAreDistinctAndSpoken() {
        let states: [CapsuleState] = [.idleReady, .recording, .processing, .commit, .fail]
        let labels = states.map { StateCue.voiceOverLabel(for: $0) }
        XCTAssertEqual(Set(labels).count, labels.count)
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })
    }

    func testHairlineStrengthensUnderIncreaseContrast() {
        // Under Increase Contrast, hairlines must step to the stronger token so
        // edges stay visible.
        XCTAssertEqual(A11y.borderColor(increaseContrast: false), Palette.mtLine)
        XCTAssertEqual(A11y.borderColor(increaseContrast: true),  Palette.mtLine2)
    }

    func testAllInkOnAllSurfacesClearsTextAA() {
        // Reuse the P0 oracle: primary+secondary clear 4.5 on every matte surface.
        let bgs: [UInt32] = [0x0d0d0f, 0x16161a, 0x1b1b20]
        for bg in bgs {
            XCTAssertGreaterThanOrEqual(MatteContrastTests.contrastRatio(0xe7e7ea, bg), 4.5)
            XCTAssertGreaterThanOrEqual(MatteContrastTests.contrastRatio(0x9a9aa2, bg), 4.5)
        }
    }

    func testMotionTokensCollapseUnderReduceMotion() {
        // Every animated state + the breathing whisper route through Motion.*,
        // which returns nil under Reduce Motion → an instant state cut.
        XCTAssertNotNil(Motion.breathe(reduceMotion: false))
        XCTAssertNil(Motion.breathe(reduceMotion: true))
        XCTAssertNotNil(Motion.pulse(Motion.recordPulse, reduceMotion: false))
        XCTAssertNil(Motion.pulse(Motion.recordPulse, reduceMotion: true))
    }

    // MARK: - Mac Platform Conformance 03
    //
    // Every reachable control the feature names must announce a non-empty
    // VoiceOver label.

    func testMenuBarItemAnnouncesNonEmptyLabelInEveryState() {
        for state in MenuBarIconRenderer.IconState.allCases {
            let label = MenuBarIconRenderer.accessibilityLabel(for: state)
            XCTAssertFalse(label.isEmpty, "menu bar item must announce a label in \(state)")
        }
    }

    func testDictionaryAddButtonAnnouncesNonEmptyLabel() {
        XCTAssertFalse(VocabularyView.addButtonLabel.isEmpty,
                       "dictionary add button must announce a VoiceOver label")
    }

    func testReviewTrayActionsAnnounceDistinctNonEmptyLabels() {
        let labels = [ReviewTray.undoButtonLabel, ReviewTray.copyButtonLabel]
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty },
                      "each review tray action must announce a VoiceOver label")
        XCTAssertEqual(Set(labels).count, labels.count,
                       "the review tray actions must not announce the same label")
    }
}
