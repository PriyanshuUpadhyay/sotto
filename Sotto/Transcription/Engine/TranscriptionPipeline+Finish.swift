import Foundation
import AVFoundation
import SwiftData
import os

extension TranscriptionPipeline {
    func makeReviewCommitHandler(
        transcription: Transcription,
        dictationGeneration: Int
    ) -> (String, String?, Bool) -> Void {
        // Shared ⌘↵ handler for both present sites. `enhancedRef` is whatever
        // enhanced text the panel had actually received by commit time — nil
        // when the user pasted ahead of a pending (or absent) enhancement, in
        // which case there is no exact edit signal to record.
        return { [weak self] finalText, enhancedRef, fromRawLineage in
            guard let self else { return }
            self.performPaste(pasteText: finalText, dictationGeneration: dictationGeneration)
            // Auto-vocab AX monitoring starts only after the paste lands in
            // the real target field.
            AutoLearnVocabularyService.shared.beginMonitoring()
            // Exact edit signal: final vs enhanced. EditSignalService
            // self-handles a no-op (final == enhanced). Read the target app
            // AFTER performPaste so lastPasteContext is the real field.
            // `transcription.promptName` is read here (not captured at present
            // time) — on the early-present path it is only set once
            // enhancement succeeds, which is also what makes enhancedRef non-nil.
            if let enhancedRef {
                // CorrectionMiner mines `.edit` as enhanced→final. When the
                // committed text descends from the RAW face (raw toggle, or
                // edits made before the enhancement landed), enhanced was
                // never the base: verbatim raw → `.revertRaw`; edited raw →
                // record NOTHING (there is no valid enhanced→final pair, and
                // a wrong triplet is worse than a missing one).
                let source: EditSignalSource? = fromRawLineage
                    ? (finalText == transcription.text ? .revertRaw : nil)
                    : .edit
                if let source {
                    let bundleID = CursorPaster.lastPasteContext?.targetApp?.bundleIdentifier
                    EditSignalService().record(
                        rawText: transcription.text,
                        enhancedText: enhancedRef,
                        finalText: finalText,
                        source: source,
                        appBundleID: bundleID,
                        transcriptionID: transcription.id,
                        promptName: transcription.promptName,
                        in: self.modelContext
                    )
                }
            }
        }
    }

    func recordSessionMetric(
        transcription: Transcription,
        model: any TranscriptionModel,
        didInsertSessionMetric: inout Bool
    ) {
        // SessionMetric lives in the separate stats.store container, not the
        // transcript context — write it through a fresh stats context and
        // save THAT (the transcript save below persists the Transcription).
        if let statsContainer = StatsModelContainerProvider.shared.modelContainer {
            do {
                let statsContext = ModelContext(statsContainer)
                didInsertSessionMetric = try SessionMetricRecorder.recordRecorderSession(
                    transcription: transcription,
                    model: model,
                    in: statsContext
                )
                if didInsertSessionMetric {
                    try statsContext.save()
                }
            } catch {
                logger.error("Failed to record session metric: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func presentOrPasteTranscript(
        finalPastedText: String?,
        transcription: Transcription,
        presentedComposeReview: inout Bool,
        reviewEnabled: Bool,
        didEnhance: Bool,
        didFireTranscribeCue: Bool,
        dictationGeneration: Int,
        reviewCommitHandler: @escaping (String, String?, Bool) -> Void,
        onPreviewShown: () -> Void
    ) {
        if let textToPaste = finalPastedText,
           transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue,
           !presentedComposeReview {

            let pasteText = textToPaste

            if reviewEnabled {
                // Enhancement never ran (disabled / skipped / short) — present
                // the editor now with the single available text. When it DID
                // run, the panel went up at enhance-start above and this tail
                // is skipped.
                presentedComposeReview = true

                // "Done" cue now — processing is complete and the editor appears
                // (mirrors the pre-paste cue on the auto-paste path below).
                if didEnhance {
                    SoundManager.shared.playEnhanceComplete()
                } else if !didFireTranscribeCue {
                    SoundManager.shared.playTranscribeComplete()
                }

                ComposeReviewWindowManager.shared.present(
                    rawText: transcription.text,
                    enhancedText: didEnhance ? pasteText : nil,
                    isEnhancing: false,
                    onCommit: reviewCommitHandler
                )
                onPreviewShown()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) { [weak self] in
                    guard let self else { return }
                    // P3.F: pre-paste cue. enhance-complete if enhancement
                    // actually ran (slightly softer stacked arpeggio), else
                    // transcribe-complete (the fundamental "done" cue) — but only
                    // if the pre-enhance transcribe cue didn't already fire
                    // (enhance-failure path) so we don't stack three cues.
                    if didEnhance {
                        SoundManager.shared.playEnhanceComplete()
                    } else if !didFireTranscribeCue {
                        SoundManager.shared.playTranscribeComplete()
                    }
                    self.performPaste(pasteText: pasteText, dictationGeneration: dictationGeneration)
                }
            }
        }
    }
}
