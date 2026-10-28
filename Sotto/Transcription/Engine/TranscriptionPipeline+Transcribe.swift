import Foundation
import AVFoundation
import SwiftData
import os

extension TranscriptionPipeline {
    func transcribeAudio(
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        audioMetrics: (durationSeconds: Double?, sampleCount: Int?),
        trace: inout TranscriptionTrace
    ) async throws -> (text: String, transcriptionDuration: TimeInterval) {
        let transcriptionStart = Date()
        var text: String
        let asrStart = TranscriptionTrace.now()
        if let session {
            text = try await session.transcribe(audioURL: audioURL, audioDurationSeconds: audioMetrics.durationSeconds)
            trace.sessionType = session.diagnostics.sessionType
            trace.streamingFinalLength = session.diagnostics.streamingFinalLength
            trace.fallbackReason = session.diagnostics.fallbackReason ?? ""
            trace.wordConfidences = session.diagnostics.wordConfidences
                .map { (word: $0.text, confidence: $0.confidence) }
        } else {
            trace.sessionType = "batch"
            text = try await serviceRegistry.transcribe(audioURL: audioURL, model: model)
        }
        trace.record(.asr, since: asrStart)
        logger.notice("📝 Transcript: \(text, privacy: .public)")
        trace.asrText = text
        trace.asrModel = model.displayName
        // Agreement-based TDT streaming: one batch decode restores dropped
        // trailing words and carries the vocabulary rescore. EOU, Nemotron
        // and Unified have no AsrModelVersion, so they skip it.
        if trace.sessionType == "streaming", model.provider == .fluidAudio,
           FluidAudioModelManager.knownAsrVersion(for: model.name) != nil {
            let repairStart = TranscriptionTrace.now()
            let repaired = await serviceRegistry.fluidAudioTranscriptionService
                .repairStreamingTranscript(text, audioURL: audioURL, model: model)
            trace.record(.repair, since: repairStart)
            if repaired != text { trace.afterRepair = repaired }
            text = repaired
        }
        // The vocabulary rescore is FluidAudio-only and runs inside the
        // service actor (file decode or streaming repair); read its
        // per-utterance outcome here.
        if model.provider == .fluidAudio {
            let boostingStart = TranscriptionTrace.now()
            trace.boosting = await serviceRegistry.fluidAudioTranscriptionService.lastBoosting
            trace.record(.boosting, since: boostingStart)
        }
        let filterStart = TranscriptionTrace.now()
        text = TranscriptionOutputFilter.filter(text)
        trace.record(.filter, since: filterStart)
        logger.notice("📝 Output filter result: \(text, privacy: .public)")
        trace.afterFilter = text
        let transcriptionDuration = Date().timeIntervalSince(transcriptionStart)
        return (text, transcriptionDuration)
    }

    func cleanTranscript(
        _ input: String,
        audioURL: URL,
        model: any TranscriptionModel,
        trace: inout TranscriptionTrace
    ) async -> String {
        var text = input
        if UserDefaults.standard.bool(forKey: "IsTextFormattingEnabled") {
            text = WhisperTextFormatter.format(text)
            logger.notice("📝 Formatted transcript: \(text, privacy: .public)")
        }

        let wordReplaceStart = TranscriptionTrace.now()
        text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
        trace.record(.wordReplacement, since: wordReplaceStart)
        logger.notice("📝 WordReplacement: \(text, privacy: .public)")
        trace.afterWordReplace = text

        // Acoustic confirmation: CTC spotter reports which vocab terms it
        // thinks were spoken. Evidence from the realtime path showed it
        // over-confirming the entire vocabulary (21/21 kept on ordinary
        // utterances), which made the homophone unlock rewrite valid words
        // ("to"→"TUI", "then"→"Thine"). When explicitly enabled we still log
        // the spotter output for diagnostics, but we do not apply it below.
        // Re-enable by passing the confirmed set only after the spotter's
        // scores actually discriminate.
        var acousticallyConfirmed: Set<String>? = nil
        if AcousticBoostingPolicy.isEnabled(forModelNamed: model.name) {
            let terms = (try? modelContext.fetch(FetchDescriptor<VocabularyWord>()))?.map { $0.word } ?? []
            if !terms.isEmpty {
                let acousticStart = TranscriptionTrace.now()
                let details = await AcousticVocabularyService.shared.confirmedTermsDetailed(at: audioURL, terms: terms)
                trace.record(.acoustic, since: acousticStart)
                trace.acoustic = details
                acousticallyConfirmed = Set(details.filter { $0.kept }.map { $0.term })
                logger.notice("🎙️ AcousticConfirm: \(acousticallyConfirmed?.sorted().joined(separator: ",") ?? "-", privacy: .public)")
            }
        }

        // Evidence mode: do NOT apply the homophone-unlock (pass nil), but
        // keep the spotter's confirmations in trace.acoustic above.
        let phoneticStart = TranscriptionTrace.now()
        let phoneticResult = PhoneticCorrectionService.shared.correctDetailed(text, using: modelContext, acousticallyConfirmed: nil)
        trace.record(.phonetic, since: phoneticStart)
        text = phoneticResult.text
        trace.phonetic = phoneticResult.corrections
        trace.afterPhonetic = text
        logger.notice("📝 PhoneticCorrect: \(text, privacy: .public)")

        return text
    }
}
