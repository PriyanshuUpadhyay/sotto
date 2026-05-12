import XCTest
import SwiftUI
@testable import VoiceInk

final class MenubarGlyphTests: XCTestCase {
    // MARK: - IconState ← HaloPhase (7-state HUD bridge)
    //
    // Spec §4.2: HaloPhase is the view-side state owned by HUD; menubar IconState
    // mirrors it so the bar reflects view-lifetime states (`.armed`, `.done`,
    // `.failed`) that engine RecordingState alone cannot express.

    func test_iconState_fromHaloPhase_hidden_isIdle() {
        XCTAssertEqual(MenuBarIconRenderer.IconState(haloPhase: .hidden), .idle)
    }

    func test_iconState_fromHaloPhase_armed_isArming() {
        XCTAssertEqual(MenuBarIconRenderer.IconState(haloPhase: .armed), .arming)
    }

    func test_iconState_fromHaloPhase_recording_isRecording() {
        XCTAssertEqual(MenuBarIconRenderer.IconState(haloPhase: .recording), .recording)
    }

    func test_iconState_fromHaloPhase_liveText_isRecording() {
        XCTAssertEqual(MenuBarIconRenderer.IconState(haloPhase: .liveText), .recording)
    }

    func test_iconState_fromHaloPhase_transcribing_isTranscribing() {
        XCTAssertEqual(MenuBarIconRenderer.IconState(haloPhase: .transcribing), .transcribing)
    }

    func test_iconState_fromHaloPhase_enhancing_isEnhancing() {
        XCTAssertEqual(MenuBarIconRenderer.IconState(haloPhase: .enhancing), .enhancing)
    }

    func test_iconState_fromHaloPhase_done_isCommitted() {
        XCTAssertEqual(MenuBarIconRenderer.IconState(haloPhase: .done), .committed)
    }

    func test_iconState_fromHaloPhase_failed_isFail() {
        XCTAssertEqual(MenuBarIconRenderer.IconState(haloPhase: .failed), .fail)
    }

    // MARK: - Combined init precedence (handsFree > halo view-state > engine state)

    func test_iconState_handsFreeBeatsHaloPhase() {
        let state = MenuBarIconRenderer.IconState(
            handsFree: .listening,
            recordingState: .idle,
            haloPhase: .recording
        )
        XCTAssertEqual(state, .handsFree)
    }

    func test_iconState_haloPhaseDone_beatsRecordingStateIdle() {
        // Engine returns to .idle on commit, but HaloPhase holds .done at view
        // layer for ~1.5s — menubar must reflect .committed during that hold.
        let state = MenuBarIconRenderer.IconState(
            handsFree: .inactive,
            recordingState: .idle,
            haloPhase: .done
        )
        XCTAssertEqual(state, .committed)
    }

    func test_iconState_haloPhaseHidden_fallsBackToRecordingState() {
        let state = MenuBarIconRenderer.IconState(
            handsFree: .inactive,
            recordingState: .recording,
            haloPhase: .hidden
        )
        XCTAssertEqual(state, .recording)
    }

    // MARK: - Accessibility label (exhaustive over IconState 8 cases)
    //
    // Pure-logic function so each label is testable without SwiftUI runtime.
    // MenuBarIcon composes this with the unresolved-failure suffix at view layer.

    func test_accessibilityLabel_idle() {
        XCTAssertEqual(MenubarGlyph.accessibilityLabel(for: .idle), "Sotto idle")
    }

    func test_accessibilityLabel_arming() {
        XCTAssertEqual(MenubarGlyph.accessibilityLabel(for: .arming), "Sotto listening")
    }

    func test_accessibilityLabel_recording() {
        XCTAssertEqual(MenubarGlyph.accessibilityLabel(for: .recording), "Sotto recording")
    }

    func test_accessibilityLabel_transcribing() {
        XCTAssertEqual(MenubarGlyph.accessibilityLabel(for: .transcribing), "Sotto transcribing")
    }

    func test_accessibilityLabel_enhancing() {
        XCTAssertEqual(MenubarGlyph.accessibilityLabel(for: .enhancing), "Sotto enhancing")
    }

    func test_accessibilityLabel_committed() {
        XCTAssertEqual(MenubarGlyph.accessibilityLabel(for: .committed), "Sotto committed")
    }

    func test_accessibilityLabel_fail() {
        XCTAssertEqual(MenubarGlyph.accessibilityLabel(for: .fail), "Sotto failed")
    }

    func test_accessibilityLabel_handsFree() {
        XCTAssertEqual(MenubarGlyph.accessibilityLabel(for: .handsFree), "Sotto hands-free")
    }
}
