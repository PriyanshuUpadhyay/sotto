import XCTest
@testable import Sotto

@MainActor
final class OnboardingStateTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "OnboardingStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_freshInstall_isNotCompleted() {
        let state = OnboardingState(defaults: defaults)
        XCTAssertFalse(state.completed)
        XCTAssertFalse(state.skipped)
        XCTAssertFalse(state.hotkeyReminderShown)
        XCTAssertFalse(state.firstInvocationDidFire)
    }

    func test_markCompleted_setsSentinel_andPersistsAcrossInstances() {
        let state = OnboardingState(defaults: defaults)
        state.markCompleted()
        XCTAssertTrue(state.completed)
        XCTAssertFalse(state.skipped)
        XCTAssertTrue(OnboardingState(defaults: defaults).completed,
                      "Sentinel must persist across instances on the same suite")
    }

    func test_markSkipped_setsBothCompletedAndSkipped() {
        let state = OnboardingState(defaults: defaults)
        state.markSkipped()
        XCTAssertTrue(state.completed)
        XCTAssertTrue(state.skipped)
        XCTAssertTrue(OnboardingState(defaults: defaults).skipped,
                      "Skipped sentinel must persist across instances")
    }

    func test_markSkippedPermissions_persists() {
        let state = OnboardingState(defaults: defaults)
        state.markSkippedPermissions()
        XCTAssertTrue(OnboardingState(defaults: defaults).skippedPermissions)
    }

    func test_markHotkeyReminderShown_persists() {
        let state = OnboardingState(defaults: defaults)
        XCTAssertFalse(state.hotkeyReminderShown)
        state.markHotkeyReminderShown()
        XCTAssertTrue(state.hotkeyReminderShown)
        XCTAssertTrue(OnboardingState(defaults: defaults).hotkeyReminderShown)
    }

    func test_markFirstInvocation_isIdempotent() {
        let state = OnboardingState(defaults: defaults)
        XCTAssertFalse(state.firstInvocationDidFire)
        state.markFirstInvocation()
        state.markFirstInvocation()
        XCTAssertTrue(state.firstInvocationDidFire)
        XCTAssertTrue(OnboardingState(defaults: defaults).firstInvocationDidFire)
    }

    func test_suiteIsolation_noGlobalPollution() {
        let stateA = OnboardingState(defaults: defaults)
        stateA.markCompleted()

        let otherSuite = "OnboardingStateTests-\(UUID().uuidString)"
        let otherDefaults = UserDefaults(suiteName: otherSuite)!
        otherDefaults.removePersistentDomain(forName: otherSuite)
        let stateB = OnboardingState(defaults: otherDefaults)
        XCTAssertFalse(stateB.completed,
                       "A separate suite must not observe another suite's sentinel")
        otherDefaults.removePersistentDomain(forName: otherSuite)
    }

    // MARK: - OnboardingStep flow logic

    func test_onboardingStep_nextAdvancesAndClampsAtDone() {
        XCTAssertEqual(OnboardingStep.welcome.next(), .permissions)
        XCTAssertEqual(OnboardingStep.permissions.next(), .hotkey)
        XCTAssertEqual(OnboardingStep.hotkey.next(), .done)
        XCTAssertEqual(OnboardingStep.done.next(), .done)
    }

    func test_onboardingStep_previousRewindsAndClampsAtWelcome() {
        XCTAssertEqual(OnboardingStep.done.previous(), .hotkey)
        XCTAssertEqual(OnboardingStep.permissions.previous(), .welcome)
        XCTAssertEqual(OnboardingStep.welcome.previous(), .welcome)
    }

    func test_onboardingStep_hasFourCases() {
        XCTAssertEqual(OnboardingStep.allCases.count, 4)
    }

    // MARK: - PermissionStage wizard logic (D3 one-screen-per-permission)

    func test_permissionStage_hasThreeScreens() {
        XCTAssertEqual(PermissionStage.allCases, [.microphone, .accessibility, .screenRecording])
    }

    func test_permissionStage_nextWalksScreensThenEnds() {
        XCTAssertEqual(PermissionStage.microphone.next(), .accessibility)
        XCTAssertEqual(PermissionStage.accessibility.next(), .screenRecording)
        XCTAssertNil(PermissionStage.screenRecording.next())
    }

    func test_permissionStage_onlyMicrophoneIsRequired() {
        XCTAssertTrue(PermissionStage.microphone.isRequired)
        XCTAssertFalse(PermissionStage.accessibility.isRequired)
        XCTAssertFalse(PermissionStage.screenRecording.isRequired)
    }

    func test_permissionStage_micGatesAdvanceUntilGranted() {
        XCTAssertFalse(PermissionStage.microphone.canAdvance(granted: false))
        XCTAssertTrue(PermissionStage.microphone.canAdvance(granted: true))
    }

    func test_permissionStage_recommendedStagesAlwaysAdvance() {
        XCTAssertTrue(PermissionStage.accessibility.canAdvance(granted: false))
        XCTAssertTrue(PermissionStage.screenRecording.canAdvance(granted: false))
    }

    // MARK: - Hotkey reminder trigger condition (D7 one-shot, D10 first-invocation)

    func test_shouldPresentHotkeyReminder_trueOnFreshInstall() {
        let state = OnboardingState(defaults: defaults)
        XCTAssertTrue(state.shouldPresentHotkeyReminder)
    }

    func test_shouldPresentHotkeyReminder_falseWhenSkipped() {
        let state = OnboardingState(defaults: defaults)
        state.markSkipped()
        XCTAssertFalse(state.shouldPresentHotkeyReminder)
    }

    func test_shouldPresentHotkeyReminder_falseAfterShown() {
        let state = OnboardingState(defaults: defaults)
        state.markHotkeyReminderShown()
        XCTAssertFalse(state.shouldPresentHotkeyReminder)
    }

    func test_shouldPresentHotkeyReminder_falseAfterFirstInvocation() {
        let state = OnboardingState(defaults: defaults)
        state.markFirstInvocation()
        XCTAssertFalse(state.shouldPresentHotkeyReminder)
    }

    func test_shouldPresentHotkeyReminder_trueWhenOnlyCompleted() {
        let state = OnboardingState(defaults: defaults)
        state.markCompleted()
        XCTAssertTrue(state.shouldPresentHotkeyReminder)
    }
}
