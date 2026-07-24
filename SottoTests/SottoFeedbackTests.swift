import XCTest
import AppKit
@testable import Sotto

@MainActor
final class SottoFeedbackTests: XCTestCase {

    private var priorValue: Any?

    override func setUp() {
        super.setUp()
        priorValue = UserDefaults.standard.object(forKey: SottoFeedback.hapticsEnabledKey)
    }

    override func tearDown() {
        // Restore whatever the user/default had so tests don't mutate real prefs.
        if let priorValue {
            UserDefaults.standard.set(priorValue, forKey: SottoFeedback.hapticsEnabledKey)
        } else {
            UserDefaults.standard.removeObject(forKey: SottoFeedback.hapticsEnabledKey)
        }
        super.tearDown()
    }

    // MARK: - Event → pattern mapping

    func test_arm_isSingleAlignmentPulse() {
        XCTAssertEqual(SottoFeedback.pulses(for: .arm), [.alignment])
    }

    func test_commit_isSingleLevelChangePulse() {
        XCTAssertEqual(SottoFeedback.pulses(for: .commit), [.levelChange])
    }

    func test_fail_isDoubleGenericPulse() {
        // Failure is deliberately a DOUBLE tap so it reads distinct from the
        // single-pulse arm / commit confirmations.
        XCTAssertEqual(SottoFeedback.pulses(for: .fail), [.generic, .generic])
        XCTAssertEqual(SottoFeedback.pulses(for: .fail).count, 2)
    }

    func test_eachEventHasAtLeastOnePulse() {
        for event in [FeedbackEvent.arm, .commit, .fail] {
            XCTAssertFalse(SottoFeedback.pulses(for: event).isEmpty)
        }
    }

    // MARK: - Toggle gating

    func test_default_isEnabledWhenUnset() {
        UserDefaults.standard.removeObject(forKey: SottoFeedback.hapticsEnabledKey)
        XCTAssertTrue(SottoFeedback.isEnabled, "haptics default ON when key unset")
    }

    func test_resolvedPulses_nilWhenDisabled() {
        UserDefaults.standard.set(false, forKey: SottoFeedback.hapticsEnabledKey)
        XCTAssertFalse(SottoFeedback.isEnabled)
        for event in [FeedbackEvent.arm, .commit, .fail] {
            XCTAssertNil(SottoFeedback.resolvedPulses(for: event),
                         "disabled haptics must resolve to no pulses (play is a no-op)")
        }
    }

    func test_resolvedPulses_matchesPatternWhenEnabled() {
        UserDefaults.standard.set(true, forKey: SottoFeedback.hapticsEnabledKey)
        XCTAssertEqual(SottoFeedback.resolvedPulses(for: .arm), SottoFeedback.pulses(for: .arm))
        XCTAssertEqual(SottoFeedback.resolvedPulses(for: .fail), SottoFeedback.pulses(for: .fail))
    }

    // MARK: - Key contract

    func test_hapticsEnabledKey_isStableContract() {
        // GeneralTab binds @AppStorage to this exact literal; service reads it.
        XCTAssertEqual(SottoFeedback.hapticsEnabledKey, "feedbackHapticsEnabled")
    }
}
