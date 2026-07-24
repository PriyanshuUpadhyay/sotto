import Foundation

/// Whether the FILE-BASED FluidAudio path should attempt in-decoder vocabulary
/// rescoring (FluidAudio's `VocabularyRescorer.ctcTokenRescore`, driven through
/// `SlidingWindowAsrManager.configureVocabularyBoosting`).
///
/// Gates, in order: (1) non-empty custom vocabulary; (2) the Parakeet Unified
/// model is excluded — it runs through `UnifiedAsrManager` (not the TDT
/// `AsrModels` that rescoring needs) and has no CTC head, so in-decoder rescore
/// is impossible there, the same structural limit as the live stream; (3) the
/// acoustic-boosting policy is enabled for the model. For `.fast` that policy is
/// the user's "Acoustic vocabulary boosting" flag, so file-based rescore — and
/// its CTC model download — is OPT-IN, matching how M1 gates the live path.
/// The runtime additionally requires the CTC model on disk and falls back to the
/// plain decode otherwise.
///
/// A deliberate decision point, not an inline-able forwarder: this name stands in
/// for a non-obvious rule — Parakeet Unified is excluded because
/// `UnifiedAsrManager` has no CTC head (so rescore is structurally impossible,
/// not merely unwired), combined with the opt-in policy gate. That is exactly
/// doctrine #3's "name replaces a non-obvious block" exception to inlining a
/// single-call-site helper; keeping it named also makes the gate unit-testable
/// without ASR models (`defaults`-injectable).
enum FluidAudioVocabularyBoosting {
    static func shouldAttempt(modelName: String, vocabulary: [String],
                              defaults: UserDefaults = .standard) -> Bool {
        guard !vocabulary.isEmpty else { return false }
        guard !FluidAudioModelManager.isParakeetUnifiedModel(named: modelName) else { return false }
        return AcousticBoostingPolicy.isEnabled(forModelNamed: modelName, defaults: defaults)
    }
}
