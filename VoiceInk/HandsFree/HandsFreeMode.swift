import Foundation

/// W12.D hands-free configuration. Persisted via three separate UserDefaults
/// keys (registered in `AppDefaults`). Constructed on demand from the current
/// defaults; the canonical source is the per-key UserDefaults values.
struct HandsFreeMode: Equatable {
    /// dBFS gate for "voice present". Samples with average power < threshold
    /// count as silence. Default −40 dBFS. Stored as Double for parity with
    /// `@AppStorage(...): Double` in `HandsFreeSettingsView`.
    var vadThresholdDb: Double

    /// Continuous-silence duration before an utterance commits. Default 1.5s.
    var silenceDuration: TimeInterval

    /// Hard session cap. Master plan §3 W12.D: "20-min cap matches Wispr."
    /// Hard-coded in v1; lead Q6 = "20-min hardcoded; no Settings exposure v1".
    var sessionCap: TimeInterval { 20.0 * 60.0 }

    /// Trigger phrases that, when matched at the END of an utterance, strip
    /// themselves and fire AutoSend(.enter). Defaults from
    /// `AppDefaults.registerDefaults()`.
    var triggerPhrases: [String]

    /// Read the current state from UserDefaults.
    static func current() -> HandsFreeMode {
        let thresholdDb = UserDefaults.standard.double(forKey: "HandsFreeVADThresholdDb")
        let silenceMs = UserDefaults.standard.integer(forKey: "HandsFreeSilenceDurationMs")
        let phrasesJSON = UserDefaults.standard.string(forKey: "HandsFreeTriggerPhrasesJSON") ?? "[]"
        let phrases = (try? JSONDecoder().decode([String].self, from: Data(phrasesJSON.utf8))) ?? []
        return HandsFreeMode(
            vadThresholdDb: thresholdDb,
            silenceDuration: TimeInterval(silenceMs) / 1000.0,
            triggerPhrases: phrases
        )
    }

    /// Write the trigger phrase list back to UserDefaults as JSON.
    static func saveTriggerPhrases(_ phrases: [String]) {
        let json = (try? JSONEncoder().encode(phrases))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "[]"
        UserDefaults.standard.set(json, forKey: "HandsFreeTriggerPhrasesJSON")
    }
}
