import Foundation

/// Whether acoustic vocabulary boosting (the CTC spotter-gated phonetic
/// corrector) is effectively on for a given transcription model.
///
/// The user flag (`IsAcousticBoostingEnabled`, set from ModelsTab) turns it on.
/// Keep this explicit: trace evidence from the realtime/Unified path showed the
/// post-hoc CTC spotter over-confirming the whole vocabulary, so it must not run
/// or download its model by default.
enum AcousticBoostingPolicy {
    static func isEnabled(forModelNamed _: String,
                          defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: "IsAcousticBoostingEnabled")
    }
}
