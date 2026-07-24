import Testing
import Foundation
@testable import Sotto

/// The effective-enabled policy for acoustic vocabulary boosting. Trace evidence
/// showed the realtime/Unified spotter over-confirming the whole vocabulary, so
/// the feature is explicit opt-in for every tier.
@Suite struct AcousticBoostingPolicyTests {
    // A fresh, per-test suite — Swift Testing runs @Test methods in parallel, so
    // a shared suite name would race (one test's removePersistentDomain / set
    // clobbering another's flag). The name is unique per call site.
    private func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "AcousticBoostingPolicyTests.\(name)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    @Test("realtime/Unified model does not default boosting ON")
    func realtimeDefaultsOff() {
        let d = defaults()
        d.set(false, forKey: "IsAcousticBoostingEnabled")
        #expect(!AcousticBoostingPolicy.isEnabled(forModelNamed: "parakeet-unified-0.6b", defaults: d))
    }

    @Test("non-realtime model honors the flag (off when the flag is off)")
    func nonRealtimeHonorsFlagOff() {
        let d = defaults()
        d.set(false, forKey: "IsAcousticBoostingEnabled")
        #expect(!AcousticBoostingPolicy.isEnabled(forModelNamed: "parakeet-tdt-0.6b-v2", defaults: d))
    }

    @Test("flag ON enables boosting for any tier")
    func flagOnEnablesAny() {
        let d = defaults()
        d.set(true, forKey: "IsAcousticBoostingEnabled")
        #expect(AcousticBoostingPolicy.isEnabled(forModelNamed: "parakeet-tdt-0.6b-v2", defaults: d))
        #expect(AcousticBoostingPolicy.isEnabled(forModelNamed: "parakeet-unified-0.6b", defaults: d))
    }
}
