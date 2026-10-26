import AppKit
import Foundation

extension AIEnhancementService {
    /// Screen capture takes real wall-clock time (screenshot + OCR), during
    /// which a newer dictation can start — so unlike the synchronous clipboard
    /// capture, this must re-check `generation` AFTER the await, and discard
    /// (not just ignore) whatever `captureAndExtractText` just wrote into
    /// `screenCaptureService.lastCapturedText` if the check fails, since that
    /// call already committed the write as a side effect before returning.
    func captureScreenContext(generation: Int) async {
        guard generation == dictationGeneration else { return }
        guard CGPreflightScreenCaptureAccess() else {
            return
        }

        let captured = await screenCaptureService.captureAndExtractText()
        guard generation == dictationGeneration else {
            screenCaptureService.lastCapturedText = nil
            return
        }
        if captured != nil {
            objectWillChange.send()
        }
    }

    func captureClipboardContext(generation: Int) {
        guard generation == dictationGeneration else { return }
        lastCapturedClipboard = NSPasteboard.general.string(forType: .string)
    }

    /// Snapshots the frontmost-app category and custom vocabulary ONCE at
    /// record-start — both `warmAFMForNextEnhance` and the real
    /// `performEnhance` read this SAME snapshot (`currentDictationSnapshot`),
    /// so system instructions stay byte-stable within a dictation even if the
    /// user switches apps or edits their vocabulary list mid-recording (the
    /// warm-session key depends on it).
    func captureDictationSnapshot(generation: Int) {
        guard generation == dictationGeneration else { return }
        dictationSnapshot = DictationSnapshot(
            generation: generation,
            activeApp: activeAppForContext,
            customVocabulary: customVocabularyService.getCustomVocabulary(from: modelContext)
        )
    }

    /// Fire-and-forget enhancement warm-up. Errors swallowed.
    func warmAFMIfAvailable(source: String) async {
        if AIProvider.resolved() == .localGGUF {
            await aiService.warmGGUF(source: source)
            return
        }
        if #available(macOS 26.0, *) {
            guard AFMProvider.isAvailable else { return }
            await aiService.warmAFM(source: source)
        }
    }

    /// Warm enhancement for the NEXT enhance specifically.
    func warmAFMForNextEnhance(source: String, generation: Int) async {
        guard generation == dictationGeneration else { return }
        if AIProvider.resolved() == .localGGUF {
            await aiService.warmGGUF(source: source)
            return
        }
        if #available(macOS 26.0, *) {
            guard AFMProvider.isAvailable else { return }
            let instructions = await getSystemInstructions()
            guard generation == dictationGeneration else { return }
            await aiService.warmAFM(instructions: instructions, source: source, generation: generation)
        }
    }

    func clearCapturedContexts() {
        lastCapturedClipboard = nil
        screenCaptureService.lastCapturedText = nil
        selectedTextSlot = nil
        dictationSnapshot = nil
    }
}
