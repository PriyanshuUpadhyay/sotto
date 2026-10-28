import Foundation
import AVFoundation
import SwiftData
import os

extension TranscriptionPipeline {
    /// Returns true when the run was cancelled (cleanup already done); `run` then returns.
    func enhanceTranscript(
        text: String,
        transcription: Transcription,
        reviewEnabled: Bool,
        reviewCommitHandler: @escaping (String, String?, Bool) -> Void,
        onStateChange: (RecordingState) -> Void,
        onFailure: (String) -> Void,
        shouldCancel: () -> Bool,
        onCleanup: () async -> Void,
        onPreviewShown: () -> Void,
        finalPastedText: inout String?,
        didEnhance: inout Bool,
        didFireTranscribeCue: inout Bool,
        presentedComposeReview: inout Bool,
        reviewSession: inout Int?,
        trace: inout TranscriptionTrace
    ) async -> Bool {
        let isSkipShortEnhancementEnabled = UserDefaults.standard.bool(forKey: "SkipShortEnhancement")
        let savedThreshold = UserDefaults.standard.integer(forKey: "ShortEnhancementWordThreshold")
        let shortEnhancementWordThreshold = savedThreshold > 0 ? savedThreshold : 3
        let shouldSkipEnhancement = isSkipShortEnhancementEnabled && WordCounter.count(in: text) <= shortEnhancementWordThreshold

        if let enhancementService,
           enhancementService.isEnhancementEnabled,
           enhancementService.isConfigured,
           !shouldSkipEnhancement {
            if shouldCancel() { await onCleanup(); return true }

            let textForAI = text

            // Optionally skip the LLM when the raw transcript is already
            // clean (~66% of runs were no-ops costing ~1.7s median). Default
            // is now OFF — the stronger Light pass is meant to punctuate and
            // fix grammar on every dictation, not only messy ones; skipping
            // clean-looking Parakeet output muted it. Set the key true to
            // restore the latency-saving skip.
            let skipWhenClean = UserDefaults.standard.object(forKey: "SkipEnhancementWhenClean") as? Bool ?? false
            if !EnhancementSanityCheck.shouldCallModel(textForAI, skipWhenClean: skipWhenClean) {
                logger.notice("🦾 enhance: skipped (raw already clean)")
            } else {
                // P3.F: transcribe-complete cue fires "ASR finishes, before
                // enhance" per spec §3.10. The enhance step then runs (often
                // several seconds), and enhance-complete fires before paste.
                SoundManager.shared.playTranscribeComplete()
                didFireTranscribeCue = true

                onStateChange(.enhancing)

                // Never wait on the AI: the review editor appears NOW with
                // the raw transcript editable; ⌘↵ pastes the current text
                // immediately and the pending enhancement is dropped on
                // delivery.
                if reviewEnabled {
                    presentedComposeReview = true
                    reviewSession = ComposeReviewWindowManager.shared.present(
                        rawText: textForAI,
                        enhancedText: nil,
                        isEnhancing: true,
                        onCommit: reviewCommitHandler
                    )
                    onPreviewShown()
                }

                do {
                    let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
                    logger.notice("📝 AI enhancement: \(enhancedText, privacy: .public)")
                    transcription.enhancedText = enhancedText
                    transcription.aiEnhancementModelName = enhancementService.lastEnhancementModelUsed
                    transcription.promptName = promptName
                    transcription.enhancementDuration = enhancementDuration
                    trace.record(.enhancement, seconds: enhancementDuration)
                    transcription.aiRequestSystemMessage = enhancementService.lastSystemMessageSent
                    transcription.aiRequestUserMessage = enhancementService.lastUserMessageSent
                    finalPastedText = enhancedText
                    didEnhance = true
                    trace.afmModel = enhancementService.lastEnhancementModelUsed ?? ""
                    trace.afmEdits = WordDiffEngine.findSingleWordSubstitutions(original: textForAI, edited: enhancedText)
                        .map { TranscriptionTrace.WordEdit(from: $0.original, to: $0.replacement) }
                    trace.afterEnhance = enhancedText
                    if let reviewSession,
                       ComposeReviewWindowManager.shared.deliverEnhanced(enhancedText, session: reviewSession) {
                        // "Done" cue at the moment the enhanced text lands
                        // in the live panel (the pre-paste cue below never
                        // runs on the review path). Skipped when the user
                        // already committed/cancelled — the paste happened.
                        SoundManager.shared.playEnhanceComplete()
                    }
                } catch {
                    let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    let shortReason = String(errorDescription.prefix(80))
                    // Don't write the error into `transcription.enhancedText` —
                    // history views and the copy/paste path resolve text via
                    // `enhancedText ?? text`, so persisting a failure string
                    // there leaks "Enhancement failed: …" into the clipboard
                    // and the history list. Leaving it nil falls through to
                    // the raw transcript everywhere.
                    logger.error("AI enhancement failed: \(errorDescription, privacy: .public)")
                    // Clear the panel's ENHANCING state (raw stays editable).
                    // false = the panel was already committed/cancelled — the
                    // user pasted and moved on, so suppress the failure
                    // notification + visual along with the dropped delivery
                    // (the log line above still records it). No review
                    // session (review off) surfaces normally.
                    let surfaceFailure = reviewSession.map {
                        ComposeReviewWindowManager.shared.deliverEnhanced(nil, session: $0)
                    } ?? true
                    if surfaceFailure {
                        // A guardrail refusal is not a malfunction — the
                        // transcript still pastes, just un-enhanced. Say
                        // that plainly instead of "Enhancement failed:
                        // <raw provider string>", and say it regardless of
                        // the failure-notification pref: a silently
                        // declined dictation is exactly the case the user
                        // has no other signal for.
                        let isRefusal = (error as? EnhancementError).map {
                            if case .safetyRefusal = $0 { return true } else { return false }
                        } ?? false
                        if isRefusal {
                            // Fire-and-forget, NOT `await MainActor.run`:
                            // showNotification builds a hosting controller
                            // and an NSPanel synchronously, so awaiting it
                            // parks the raw transcript behind whatever else
                            // the main actor is doing. The toast is
                            // advisory; the paste is not.
                            Task { @MainActor in
                                NotificationManager.shared.showNotification(
                                    title: "Enhancement declined — pasted raw transcript",
                                    type: .warning,
                                    duration: 2.5
                                )
                            }
                        } else if UserDefaults.standard.bool(forKey: "EnableEnhancementFailureNotification") {
                            await MainActor.run {
                                NotificationManager.shared.showNotification(
                                    title: "Enhancement failed: \(shortReason)",
                                    type: .warning
                                )
                            }
                        }
                        // Surface to engine so the failure visual can render. Paste
                        // still proceeds with the un-enhanced transcript (silent fallback).
                        onFailure("Enhancement failed: \(shortReason)")
                    }
                    if shouldCancel() {
                        if presentedComposeReview { ComposeReviewWindowManager.shared.cancel() }
                        await onCleanup()
                        return true
                    }
                }
            }
        }

        return false
    }
}
