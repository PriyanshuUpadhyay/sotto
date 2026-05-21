import XCTest
@testable import VoiceInk

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
}
