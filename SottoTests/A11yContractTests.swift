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

    // MARK: - Liquid Glass fallbacks
    //
    // The recorder family is made of the platform material now, so every
    // accessibility branch has to land somewhere opaque and legible.

    func testEveryGlassLevelKeepsItsOpaqueMatteFallback() {
        // Reduce Transparency / Increase Contrast collapse each level back onto
        // the matte ladder the capsule used before the glass — the code path
        // stays alive, it is not merely a lighter tint.
        let opaque = [Palette.mtRaise.resolvedNSColor(), Palette.mtRaise2.resolvedNSColor()]
        for level in [SottoGlassLevel.capsule, .panel, .chip, .scrim] {
            XCTAssertTrue(opaque.contains(level.opaqueFill.resolvedNSColor()),
                          "\(level) must fall back to an opaque matte surface")
        }
    }

    func testNothingIsLayeredGlassOnGlass() {
        // Apple's rule for elements sitting on Liquid Glass: use fills,
        // transparency and vibrancy so they read as a thin overlay that is part
        // of the material — never a second sheet of glass. Only the two surface
        // levels are the material; everything that rides on one is a fill.
        XCTAssertTrue(SottoGlassLevel.chip.isOverlay)
        XCTAssertTrue(SottoGlassLevel.scrim.isOverlay)
        XCTAssertFalse(SottoGlassLevel.capsule.isOverlay)
        XCTAssertFalse(SottoGlassLevel.panel.isOverlay)
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

    /// The audio player is the surface for reviewing a transcript against its
    /// audio, so its scrubber and transport must announce like every other
    /// reachable control.
    func testAudioPlayerControlsAnnounceDistinctNonEmptyLabels() {
        let labels = [WaveformView.scrubberAccessibilityLabel,
                      AudioPlayerView.playLabel,
                      AudioPlayerView.pauseLabel]
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty },
                      "each audio player control must announce a VoiceOver label")
        XCTAssertEqual(Set(labels).count, labels.count,
                       "the audio player controls must not announce the same label")
    }

    func testReviewTrayActionsAnnounceDistinctNonEmptyLabels() {
        let labels = [ReviewTray.undoButtonLabel, ReviewTray.copyButtonLabel]
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty },
                      "each review tray action must announce a VoiceOver label")
        XCTAssertEqual(Set(labels).count, labels.count,
                       "the review tray actions must not announce the same label")
    }
}
