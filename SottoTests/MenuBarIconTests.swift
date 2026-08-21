import XCTest
import SwiftUI
import AppKit
@testable import Sotto

final class MenuBarIconTests: XCTestCase {
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

    // MARK: - Combined init precedence (halo view-state > engine state)

    func test_iconState_haloPhaseDone_beatsRecordingStateIdle() {
        // Engine returns to .idle on commit, but HaloPhase holds .done at view
        // layer for ~1.5s — menubar must reflect .committed during that hold.
        let state = MenuBarIconRenderer.IconState(
            recordingState: .idle,
            haloPhase: .done
        )
        XCTAssertEqual(state, .committed)
    }

    func test_iconState_haloPhaseHidden_fallsBackToRecordingState() {
        let state = MenuBarIconRenderer.IconState(
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
        XCTAssertEqual(MenuBarIconRenderer.accessibilityLabel(for: .idle), "Sotto idle")
    }

    func test_accessibilityLabel_arming() {
        XCTAssertEqual(MenuBarIconRenderer.accessibilityLabel(for: .arming), "Sotto listening")
    }

    func test_accessibilityLabel_recording() {
        XCTAssertEqual(MenuBarIconRenderer.accessibilityLabel(for: .recording), "Sotto recording")
    }

    func test_accessibilityLabel_transcribing() {
        XCTAssertEqual(MenuBarIconRenderer.accessibilityLabel(for: .transcribing), "Sotto transcribing")
    }

    func test_accessibilityLabel_enhancing() {
        XCTAssertEqual(MenuBarIconRenderer.accessibilityLabel(for: .enhancing), "Sotto enhancing")
    }

    func test_accessibilityLabel_committed() {
        XCTAssertEqual(MenuBarIconRenderer.accessibilityLabel(for: .committed), "Sotto committed")
    }

    func test_accessibilityLabel_fail() {
        XCTAssertEqual(MenuBarIconRenderer.accessibilityLabel(for: .fail), "Sotto failed")
    }
}

// MARK: - Brand-glyph image contract

extension MenuBarIconTests {
    func test_image_isNonTemplate_andSized_forAllStates() {
        let states: [MenuBarIconRenderer.IconState] = [
            .idle, .arming, .recording, .transcribing,
            .enhancing, .committed, .fail,
        ]
        for state in states {
            let img = MenuBarIconRenderer.image(for: state, unresolvedFailures: 0)
            XCTAssertFalse(img.isTemplate, "\(state): brand glyph must be non-template")
            XCTAssertEqual(img.size, NSSize(width: 18, height: 18), "\(state): icon must be 18×18pt")
            XCTAssertNotNil(img.accessibilityDescription, "\(state): icon needs an a11y description")
        }
    }

    func test_image_withUnresolvedFailures_isNonTemplate_andSized() {
        let img = MenuBarIconRenderer.image(for: .idle, unresolvedFailures: 2)
        XCTAssertFalse(img.isTemplate)
        XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
    }

    func test_explicitMenuBarAppearanceControlsRenderedColors() {
        let aqua = MenuBarIconRenderer.image(
            for: .idle,
            unresolvedFailures: 0,
            appearance: NSAppearance(named: .aqua)
        )
        let darkAqua = MenuBarIconRenderer.image(
            for: .idle,
            unresolvedFailures: 0,
            appearance: NSAppearance(named: .darkAqua)
        )
        XCTAssertNotEqual(aqua.tiffRepresentation, darkAqua.tiffRepresentation)
    }
}

// MARK: - W14 · CapsuleState mapping (matte syntax-state restyle)
//
// The menu bar keys its accent off the shared `CapsuleState` so the bar and the
// recorder capsule render the same 5 functional states. `arming` reads as
// idle/ready; transcribing+enhancing collapse to processing.

extension MenuBarIconTests {
    func test_capsuleState_mapping_isExhaustiveAndCorrect() {
        XCTAssertEqual(MenuBarIconRenderer.IconState.idle.capsuleState, .idleReady)
        XCTAssertEqual(MenuBarIconRenderer.IconState.arming.capsuleState, .idleReady)
        XCTAssertEqual(MenuBarIconRenderer.IconState.recording.capsuleState, .recording)
        XCTAssertEqual(MenuBarIconRenderer.IconState.transcribing.capsuleState, .processing)
        XCTAssertEqual(MenuBarIconRenderer.IconState.enhancing.capsuleState, .processing)
        XCTAssertEqual(MenuBarIconRenderer.IconState.committed.capsuleState, .commit)
        XCTAssertEqual(MenuBarIconRenderer.IconState.fail.capsuleState, .fail)
    }

    func test_capsuleState_idle_usesPhosphorSignal() {
        // Idle/ready accent is phosphor (the brand "signal" at rest), per brief.
        let mappings: [(MenuBarIconRenderer.IconState, Color)] = [
            (.idle, Palette.phosphor),
            (.recording, Palette.stateRecord),
            (.transcribing, Palette.stateProcessing),
            (.committed, Palette.stateCommit),
            (.fail, Palette.stateFail),
        ]
        for (state, expected) in mappings {
            XCTAssertEqual(state.capsuleState.color.resolvedNSColor(), expected.resolvedNSColor())
        }
    }
}
