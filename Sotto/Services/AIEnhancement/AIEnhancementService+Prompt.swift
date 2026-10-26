import Foundation

extension AIEnhancementService {
    func getSystemInstructions() async -> String {
        await getSystemInstructions(activeApp: resolvedActiveApp, customVocabulary: resolvedCustomVocabulary)
    }

    /// `activeApp`/`customVocabulary` are resolved by the CALLER — a pure
    /// function of its explicit inputs, deliberately not consulting
    /// `resolvedActiveApp`/`resolvedCustomVocabulary` (which read the shared,
    /// live `dictationGeneration`/`dictationSnapshot`) internally. That lets
    /// the record-start snapshot (recording path) and a live read (import
    /// path, `performEnhance(_:isImport:)`) share this one builder without
    /// either accidentally reading the other's state.
    ///
    /// Contains ONLY stable content: the canonical rules, the category
    /// register directive, and custom vocabulary. Deliberately excludes
    /// selected-text/clipboard/screen/active-app DATA — those are volatile
    /// per-moment context (`volatileContextSection`) that belongs in the user
    /// message instead, so this string is identical between the record-start
    /// AFM warm call and the real post-ASR enhance call within one dictation.
    /// AFM's warm-session reuse keys on exact instruction equality
    /// (`AFMProvider.warm(instructions:)`); embedding volatile data here would
    /// silently void the prewarm on any change (clipboard, screen, focus).
    func getSystemInstructions(activeApp: (name: String, bundleID: String)?, customVocabulary: String) async -> String {
        let customVocabularySection = if !customVocabulary.isEmpty {
            """


            The following are the user's vocabulary words, proper nouns, and technical terms. Spell them EXACTLY as shown. Speech recognition often replaces them with ordinary words that sound similar, so also restore a vocabulary term when the <TRANSCRIPT> wording sounds like it AND that term fits the sentence — e.g. a transcript reading 'red us' where the list has Redis. If the wording is not a close sound match, or the vocabulary term makes no sense there, leave the transcript wording untouched. Never force a vocabulary word in.
            <CUSTOM_VOCABULARY>
            \(bound(customVocabulary, maxBytes: 1024))
            </CUSTOM_VOCABULARY>
            """
        } else {
            ""
        }

        // The single fixed cleanup prompt: the canonical rules plus the register
        // directive for the active app's category, spliced INSIDE the
        // customPromptTemplate's <SYSTEM_INSTRUCTIONS> block (bounded by the
        // "transcription enhancer, do not respond" framing on both sides). The
        // category is derived in Swift from the bundle id — the only channel
        // allowed to steer tone.
        let category = AppCategory.from(bundleID: activeApp?.bundleID)
        let body = AIPrompts.cleanupRules + category.registerDirective
        let systemPrompt = String(format: AIPrompts.customPromptTemplate, body)

        return systemPrompt + customVocabularySection
    }

    func volatileContextSection() async -> String {
        await volatileContextSection(activeApp: activeAppForContext)
    }

    /// Selected-text/clipboard/screen/active-app DATA — everything that can
    /// change moment-to-moment within a dictation. Belongs in the USER
    /// message (see `makeRequest`), not system instructions — see
    /// `getSystemInstructions`'s doc comment for why.
    func volatileContextSection(activeApp: (name: String, bundleID: String)?) async -> String {
        let selectedText = await cachedSelectedText()
        let selectedTextContext = if let selectedText, !selectedText.isEmpty {
            "\n\n<CURRENTLY_SELECTED_TEXT>\n\(bound(selectedText, maxBytes: 2048))\n</CURRENTLY_SELECTED_TEXT>"
        } else {
            ""
        }

        let clipboardContext = if useClipboardContext,
                              let clipboardText = lastCapturedClipboard,
                              !clipboardText.isEmpty {
            "\n\n<CLIPBOARD_CONTEXT>\n\(bound(clipboardText, maxBytes: 2048))\n</CLIPBOARD_CONTEXT>"
        } else {
            ""
        }

        let screenCaptureContext = if useScreenCaptureContext,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
            "\n\n<CURRENT_WINDOW_CONTEXT>\n\(bound(capturedText, maxBytes: 2048))\n</CURRENT_WINDOW_CONTEXT>"
        } else {
            ""
        }

        let activeAppContext: String
        if let activeApp {
            let body = "name=\(activeApp.name)\nbundle=\(activeApp.bundleID)"
            activeAppContext = "\n\n<ACTIVE_APP>\n\(bound(body, maxBytes: 2048))\n</ACTIVE_APP>"
        } else {
            activeAppContext = ""
        }

        return selectedTextContext + clipboardContext + screenCaptureContext + activeAppContext
    }

    /// Kicks off a detached fetch for the frontmost selection — call at
    /// record-start (`SottoEngine`) so it runs concurrently with ASR
    /// instead of paying the AX/menu-Copy cost (100s of ms) live on the
    /// post-ASR path, and only once per dictation rather than once per
    /// prewarm-and-real-enhance pair. Never awaited by the caller — recording
    /// start is never gated on this.
    ///
    /// `generation` must be the value `beginNewDictation()` returned for THIS
    /// dictation. Guarded at entry so a call from an older, superseded
    /// dictation's still-running record-start work never installs a new slot
    /// over a newer dictation's — and since each valid call creates a FRESH
    /// `SelectedTextSlot` (replacing, never mutating, `selectedTextSlot`), a
    /// slow fetch that loses this entry race writes into an orphaned slot
    /// object nothing reads anymore.
    func captureSelectedTextContext(generation: Int) {
        guard generation == dictationGeneration else { return }
        let provider = selectedTextProvider
        let slot = SelectedTextSlot()
        selectedTextSlot = slot
        Task.detached {
            let result = await provider()
            await slot.write(result)
        }
    }

    /// Awaits the record-start capture with a short grace period so a slow
    /// fetch doesn't stall enhancement indefinitely — past the grace, proceeds
    /// without selected-text context, same as AX being unavailable. The slow
    /// fetch itself is left running in the background (see `SelectedTextSlot`).
    private func cachedSelectedText(graceSeconds: TimeInterval = 0.3) async -> String? {
        guard let slot = selectedTextSlot else { return nil }
        return await slot.read(timeoutSeconds: graceSeconds, sleep: selectedTextGraceSleep)
    }

    /// T5 — gate ContextSanitizer behind a kill-switch. Default true.
    private func bound(_ raw: String, maxBytes: Int) -> String {
        UserDefaults.standard.bool(forKey: "EnableContextSanitization")
            ? ContextSanitizer.sanitize(raw, maxBytes: maxBytes)
            : raw
    }
}
