import Testing
import Foundation
@testable import Sotto

/// The structural + opt-in gate for file-based in-decoder vocabulary rescoring.
@Suite struct FluidAudioVocabularyBoostingTests {
    // Per-test UserDefaults suite (Swift Testing runs @Test methods in parallel).
    private func defaults(flag: Bool, _ name: String = #function) -> UserDefaults {
        let suite = "FluidAudioVocabularyBoostingTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        d.set(flag, forKey: "IsAcousticBoostingEnabled")
        return d
    }

    @Test("TDT (.fast) with vocab + boosting flag ON attempts boosting")
    func tdtFlagOnAttempts() {
        #expect(FluidAudioVocabularyBoosting.shouldAttempt(
            modelName: "parakeet-tdt-0.6b-v2", vocabulary: ["Sotto"], defaults: defaults(flag: true)))
    }

    // MUST-FIX 1: in-decoder rescore is opt-in for .fast — flag OFF, no boosting
    // (and therefore no CTC download).
    @Test("TDT (.fast) with vocab but boosting flag OFF does NOT attempt (opt-in)")
    func tdtFlagOffSkips() {
        #expect(!FluidAudioVocabularyBoosting.shouldAttempt(
            modelName: "parakeet-tdt-0.6b-v2", vocabulary: ["Sotto"], defaults: defaults(flag: false)))
    }

    @Test("Parakeet Unified is excluded even with the flag on (no CTC head)")
    func unifiedExcluded() {
        #expect(!FluidAudioVocabularyBoosting.shouldAttempt(
            modelName: "parakeet-unified-0.6b", vocabulary: ["Sotto"], defaults: defaults(flag: true)))
    }

    @Test("empty vocabulary skips boosting even with the flag on")
    func emptyVocabSkips() {
        #expect(!FluidAudioVocabularyBoosting.shouldAttempt(
            modelName: "parakeet-tdt-0.6b-v2", vocabulary: [], defaults: defaults(flag: true)))
    }
}
