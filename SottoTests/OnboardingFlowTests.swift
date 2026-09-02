import XCTest
import SwiftUI
@testable import Sotto

@MainActor
final class OnboardingFlowTests: XCTestCase {

    // MARK: - Anchor 1 (positive)
    // "Step ordering is correct, the skip path reaches the essentials, and
    //  required-vs-optional gating is explicit."

    func test_stepOrdering_isExactlyWelcomeMicAccessibilityScreenRecShortcutModelTierDone() {
        XCTAssertEqual(
            OnboardingFlowStep.allCases,
            [.welcome, .microphone, .accessibility, .screenRecording, .shortcut, .modelTier, .done]
        )
    }

    func test_fullPath_isEveryStepInOrder() {
        XCTAssertEqual(OnboardingPath.full.steps, OnboardingFlowStep.allCases)
    }

    func test_fullPath_advancesSequentially() {
        XCTAssertEqual(OnboardingPath.full.step(after: .welcome), .microphone)
        XCTAssertEqual(OnboardingPath.full.step(after: .microphone), .accessibility)
        XCTAssertEqual(OnboardingPath.full.step(after: .accessibility), .screenRecording)
        XCTAssertEqual(OnboardingPath.full.step(after: .screenRecording), .shortcut)
        XCTAssertEqual(OnboardingPath.full.step(after: .shortcut), .modelTier)
        XCTAssertEqual(OnboardingPath.full.step(after: .modelTier), .done)
    }

    func test_advancingPastDone_clampsAtDone() {
        XCTAssertEqual(OnboardingPath.full.step(after: .done), .done)
        XCTAssertEqual(OnboardingPath.essentials.step(after: .done), .done)
    }

    func test_essentialsPath_yieldsEssentialsSubset() {
        XCTAssertEqual(
            OnboardingPath.essentials.steps,
            [.microphone, .shortcut, .modelTier, .done]
        )
    }

    func test_essentialsPath_isSubsetOfFull() {
        let full = Set(OnboardingPath.full.steps)
        XCTAssertTrue(Set(OnboardingPath.essentials.steps).isSubset(of: full))
    }

    func test_essentialsPath_skipsOptionalPermissionsAndIsReachable() {
        // Essentials reaches Shortcut directly after Microphone, skipping the
        // two optional permission steps (Accessibility, Screen Recording).
        XCTAssertEqual(OnboardingPath.essentials.step(after: .microphone), .shortcut)
        XCTAssertEqual(OnboardingPath.essentials.step(after: .shortcut), .modelTier)
        XCTAssertFalse(OnboardingPath.essentials.steps.contains(.accessibility))
        XCTAssertFalse(OnboardingPath.essentials.steps.contains(.screenRecording))
    }

    func test_skipToEssentialsAction_fromWelcome_reachesMicrophoneThenProgressesToDone() {
        let start = OnboardingPosition.start
        XCTAssertEqual(start.path, .full)
        XCTAssertEqual(start.step, .welcome)

        let skipped = start.skippingToEssentials()
        XCTAssertEqual(skipped.path, .essentials)
        XCTAssertEqual(skipped.step, .microphone)

        let afterMic = skipped.advanced()
        XCTAssertEqual(afterMic.step, .shortcut)

        let afterShortcut = afterMic.advanced()
        XCTAssertEqual(afterShortcut.step, .modelTier)

        let afterModelTier = afterShortcut.advanced()
        XCTAssertEqual(afterModelTier.step, .done)
        XCTAssertTrue(afterModelTier.isFinished)
    }

    // MARK: - Required vs optional gating (explicit)

    func test_microphoneIsRequired() {
        XCTAssertTrue(OnboardingFlowStep.microphone.isRequired)
        XCTAssertFalse(OnboardingFlowStep.microphone.isOptional)
    }

    func test_screenRecordingIsOptional() {
        XCTAssertTrue(OnboardingFlowStep.screenRecording.isOptional)
        XCTAssertFalse(OnboardingFlowStep.screenRecording.isRequired)
    }

    func test_accessibilityIsOptional() {
        XCTAssertTrue(OnboardingFlowStep.accessibility.isOptional)
        XCTAssertFalse(OnboardingFlowStep.accessibility.isRequired)
    }

    func test_nonPermissionStepsAreNeitherRequiredNorOptional() {
        for step: OnboardingFlowStep in [.welcome, .shortcut, .modelTier, .done] {
            XCTAssertFalse(step.isPermission, "\(step) must not be a permission step")
            XCTAssertFalse(step.isRequired)
            XCTAssertFalse(step.isOptional)
        }
    }

    func test_requiredStepGatesAdvanceUntilGranted() {
        XCTAssertFalse(OnboardingFlowStep.microphone.canAdvance(granted: false))
        XCTAssertTrue(OnboardingFlowStep.microphone.canAdvance(granted: true))
    }

    func test_optionalAndNonPermissionStepsAlwaysAdvance() {
        XCTAssertTrue(OnboardingFlowStep.accessibility.canAdvance(granted: false))
        XCTAssertTrue(OnboardingFlowStep.screenRecording.canAdvance(granted: false))
        XCTAssertTrue(OnboardingFlowStep.shortcut.canAdvance(granted: false))
        XCTAssertTrue(OnboardingFlowStep.modelTier.canAdvance(granted: false))
    }

    // MARK: - Anchor 2 (negative)
    // "No permission is requested at app launch; requests fire at the relevant
    //  onboarding step (point-of-use)."

    func test_noStepRequestsPermissionOnAppear() {
        for step in OnboardingFlowStep.allCases {
            XCTAssertFalse(
                step.requestsPermissionOnAppear,
                "\(step) must not request a permission as a side effect of presentation"
            )
        }
    }

    func test_permissionStepsMapToAStage_othersDoNot() {
        XCTAssertEqual(OnboardingFlowStep.microphone.permissionStage, .microphone)
        XCTAssertEqual(OnboardingFlowStep.accessibility.permissionStage, .accessibility)
        XCTAssertEqual(OnboardingFlowStep.screenRecording.permissionStage, .screenRecording)
        for step: OnboardingFlowStep in [.welcome, .shortcut, .modelTier, .done] {
            XCTAssertNil(step.permissionStage)
        }
    }

    /// Anchor 2 in the code, not just in the enum: the launch path must not
    /// re-open the Accessibility or Screen Recording dialogs, or "Skip for now"
    /// on their onboarding steps means nothing. Source-scanned because
    /// `applicationDidFinishLaunching` has no headless behaviour to assert.
    func test_appDelegate_doesNotPromptOptionalPermissionsAtLaunch() {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
        let src = (try? String(contentsOf: root.appendingPathComponent("Sotto/AppDelegate.swift"),
                               encoding: .utf8)) ?? ""
        XCTAssertFalse(src.isEmpty, "AppDelegate.swift not found")
        XCTAssertFalse(src.contains("AXIsProcessTrustedWithOptions"),
                       "launch must not prompt Accessibility")
        XCTAssertFalse(src.contains("CGRequestScreenCaptureAccess"),
                       "launch must not prompt Screen Recording")
    }

    func test_constructingFlow_requestsNoPermission() {
        let log = PermissionRequestLog()
        _ = OnboardingFlow(onFinish: {}, requestPermission: { log.record($0) })
        XCTAssertTrue(
            log.stages.isEmpty,
            "constructing OnboardingFlow must not request any OS permission"
        )
    }

    func test_flowIsConstructibleView() {
        XCTAssertTrue((OnboardingFlow(onFinish: {}) as Any) is any View)
    }
}

private final class PermissionRequestLog {
    private(set) var stages: [PermissionStage] = []
    func record(_ stage: PermissionStage) { stages.append(stage) }
}
