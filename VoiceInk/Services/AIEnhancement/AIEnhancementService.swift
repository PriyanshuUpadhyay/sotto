import Foundation
import SwiftData
import AppKit
import os
import LLMkit

enum EnhancementPrompt {
    case transcriptionEnhancement
    case aiAssistant
}

@MainActor
class AIEnhancementService: ObservableObject {
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AIEnhancementService")

    /// W12.A canonical state. Source of truth for enhance on/off + intensity.
    @Published var enhanceLevel: EnhanceLevel {
        didSet {
            UserDefaults.standard.set(enhanceLevel.rawValue, forKey: "enhanceLevel")
            // Forward-compat: keep the legacy bool key in sync so a downgrade
            // doesn't drop the user's on/off state. Drop in a follow-up packet
            // ≥3 months post-W12.A merge.
            UserDefaults.standard.set(enhanceLevel != .none, forKey: "isAIEnhancementEnabled")
            if enhanceLevel != .none && selectedPromptId == nil {
                selectedPromptId = customPrompts.first?.id
            }
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
        }
    }

    /// Derived view for back-compat (Migration policy #2). DO NOT add new readers.
    /// Reads return `enhanceLevel != .none`; writes map `true → .medium`,
    /// `false → .none`. Observers see the same change because `enhanceLevel`
    /// is `@Published` and fires `objectWillChange`.
    var isEnhancementEnabled: Bool {
        get { enhanceLevel != .none }
        set { enhanceLevel = newValue ? .medium : .none }
    }

    @Published var useClipboardContext: Bool {
        didSet {
            UserDefaults.standard.set(useClipboardContext, forKey: "useClipboardContext")
        }
    }

    @Published var useScreenCaptureContext: Bool {
        didSet {
            UserDefaults.standard.set(useScreenCaptureContext, forKey: "useScreenCaptureContext")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        }
    }

    @Published var customPrompts: [CustomPrompt] {
        didSet {
            if let encoded = try? JSONEncoder().encode(customPrompts) {
                UserDefaults.standard.set(encoded, forKey: "customPrompts")
            }
        }
    }

    @Published var selectedPromptId: UUID? {
        didSet {
            UserDefaults.standard.set(selectedPromptId?.uuidString, forKey: "selectedPromptId")
            NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
            NotificationCenter.default.post(name: .promptSelectionChanged, object: nil)
        }
    }

    @Published var lastSystemMessageSent: String?
    @Published var lastUserMessageSent: String?

    var activePrompt: CustomPrompt? {
        allPrompts.first { $0.id == selectedPromptId }
    }

    var allPrompts: [CustomPrompt] {
        return customPrompts
    }

    /// Module-internal so live-preview surfaces (P3.E Prompts editor) can
    /// observe provider/model swaps for reactive UI updates without going
    /// through the optional `getAIService()` accessor.
    let aiService: AIService
    private let screenCaptureService: ScreenCaptureService
    private let customVocabularyService: CustomVocabularyService
    private var baseTimeout: TimeInterval {
        let stored = UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
        return stored > 0 ? TimeInterval(stored) : 7
    }
    private let rateLimitInterval: TimeInterval = 1.0
    private var lastRequestTime: Date?
    private let modelContext: ModelContext
    
    @Published var lastCapturedClipboard: String?

    init(aiService: AIService = AIService(), modelContext: ModelContext) {
        self.aiService = aiService
        self.modelContext = modelContext
        self.screenCaptureService = ScreenCaptureService()
        self.customVocabularyService = CustomVocabularyService.shared

        // W12.A: prefer canonical enhanceLevel key; fall back to legacy bool key.
        if let raw = UserDefaults.standard.string(forKey: "enhanceLevel"),
           let level = EnhanceLevel(rawValue: raw) {
            self.enhanceLevel = level
        } else if UserDefaults.standard.object(forKey: "isAIEnhancementEnabled") != nil {
            self.enhanceLevel = .from(legacyBool: UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled"))
        } else {
            self.enhanceLevel = .default
        }
        self.useClipboardContext = UserDefaults.standard.bool(forKey: "useClipboardContext")
        self.useScreenCaptureContext = UserDefaults.standard.bool(forKey: "useScreenCaptureContext")
        if let savedPromptsData = UserDefaults.standard.data(forKey: "customPrompts"),
           let decodedPrompts = try? JSONDecoder().decode([CustomPrompt].self, from: savedPromptsData) {
            self.customPrompts = decodedPrompts
        } else {
            self.customPrompts = []
        }

        if let savedPromptId = UserDefaults.standard.string(forKey: "selectedPromptId") {
            self.selectedPromptId = UUID(uuidString: savedPromptId)
        }

        if isEnhancementEnabled && (selectedPromptId == nil || !allPrompts.contains(where: { $0.id == selectedPromptId })) {
            self.selectedPromptId = allPrompts.first?.id
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAPIKeyChange),
            name: .aiProviderKeyChanged,
            object: nil
        )

        initializePredefinedPrompts()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAPIKeyChange() {
        DispatchQueue.main.async {
            self.objectWillChange.send()
            if !self.aiService.isAPIKeyValid {
                self.isEnhancementEnabled = false
            }
        }
    }

    func getAIService() -> AIService? {
        return aiService
    }

    var isConfigured: Bool {
        aiService.isAPIKeyValid
    }

    private func waitForRateLimit() async throws {
        if let lastRequest = lastRequestTime {
            let timeSinceLastRequest = Date().timeIntervalSince(lastRequest)
            if timeSinceLastRequest < rateLimitInterval {
                try await Task.sleep(nanoseconds: UInt64((rateLimitInterval - timeSinceLastRequest) * 1_000_000_000))
            }
        }
        lastRequestTime = Date()
    }

    private func getSystemMessage(for mode: EnhancementPrompt) async -> String {
        let selectedTextContext: String
        if AXIsProcessTrusted() {
            if let selectedText = await SelectedTextService.fetchSelectedText(), !selectedText.isEmpty {
                selectedTextContext = "\n\n<CURRENTLY_SELECTED_TEXT>\n\(selectedText)\n</CURRENTLY_SELECTED_TEXT>"
            } else {
                selectedTextContext = ""
            }
        } else {
            selectedTextContext = ""
        }

        let clipboardContext = if useClipboardContext,
                              let clipboardText = lastCapturedClipboard,
                              !clipboardText.isEmpty {
            "\n\n<CLIPBOARD_CONTEXT>\n\(clipboardText)\n</CLIPBOARD_CONTEXT>"
        } else {
            ""
        }

        let screenCaptureContext = if useScreenCaptureContext,
                                   let capturedText = screenCaptureService.lastCapturedText,
                                   !capturedText.isEmpty {
            "\n\n<CURRENT_WINDOW_CONTEXT>\n\(capturedText)\n</CURRENT_WINDOW_CONTEXT>"
        } else {
            ""
        }

        let customVocabulary = customVocabularyService.getCustomVocabulary(from: modelContext)

        let allContextSections = selectedTextContext + clipboardContext + screenCaptureContext

        let customVocabularySection = if !customVocabulary.isEmpty {
            """


            The following are important vocabulary words, proper nouns, and technical terms. When these words or similar-sounding words appear in the <TRANSCRIPT>, ensure they are spelled EXACTLY as shown below:
            <CUSTOM_VOCABULARY>
            \(customVocabulary)
            </CUSTOM_VOCABULARY>
            """
        } else {
            ""
        }

        let finalContextSection = allContextSections + customVocabularySection

        // W12.A bug-fix (2026-04-30): the level directive must be SPLICED
        // INSIDE the customPromptTemplate's <SYSTEM_INSTRUCTIONS> block, not
        // prepended OUTSIDE it. Prepending fragmented the prompt — Qwen3-Instruct
        // saw a bare `<CLEANUP_LEVEL>` content tag + a standalone "Apply X
        // cleanup" directive at the top, then the strong "TRANSCRIPTION
        // ENHANCER, DO NOT RESPOND" framing arrived later. On question-like
        // dictations the model regressed to chat-instruct mode and answered
        // the question instead of cleaning the transcript. Splicing inside
        // keeps the directive bounded by the framing on both sides.
        //
        // Assistant mode is intentionally exempt — the user wants a response,
        // not a cleanup, so the cleanup directive must NOT reframe it.
        let levelDirective = AIPrompts.cleanupDirective(for: enhanceLevel)
        let systemPrompt: String

        if let activePrompt = activePrompt {
            if activePrompt.id == PredefinedPrompts.assistantPromptId {
                systemPrompt = activePrompt.promptText
            } else if activePrompt.useSystemInstructions {
                let combinedBody = levelDirective + activePrompt.promptText
                systemPrompt = String(format: AIPrompts.customPromptTemplate, combinedBody)
            } else {
                systemPrompt = levelDirective + activePrompt.promptText
            }
        } else {
            let defaultPrompt = allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId }) ?? allPrompts.first!
            let combinedBody = levelDirective + defaultPrompt.promptText
            systemPrompt = String(format: AIPrompts.customPromptTemplate, combinedBody)
        }

        return systemPrompt + finalContextSection
    }

    private func makeRequest(text: String, mode: EnhancementPrompt) async throws -> String {
        guard isConfigured else {
            throw EnhancementError.notConfigured
        }

        guard !text.isEmpty else {
            return ""
        }

        let formattedText = "\n<TRANSCRIPT>\n\(text)\n</TRANSCRIPT>"
        let systemMessage = await getSystemMessage(for: mode)
        logger.notice("🦾 enhance: level=\(self.enhanceLevel.rawValue, privacy: .public)")

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = formattedText
        }

        if aiService.selectedProvider == .ollama {
            do {
                let result = try await aiService.enhanceWithOllama(text: formattedText, systemPrompt: systemMessage)
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalAIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if aiService.selectedProvider == .localCLI {
            do {
                let result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: formattedText)
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                if let localError = error as? LocalCLIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if aiService.selectedProvider == .mlx {
            // W11.B — AFM-first routing. When Apple Foundation Models is
            // available (macOS 26+ with Apple Intelligence enabled), prefer
            // AFM and use MLX as fallback. On AFM safety-filter refusal we
            // transparently retry with MLX. Other AFM errors propagate as
            // EnhancementError so the user sees them. AFM-unavailable users
            // get the unchanged MLX path.
            //
            // W14.A — `ForceMLXOverAFM` UserDefault opts out of AFM-first
            // routing, sending the request directly to MLX. Default off.
            let forceMLX = UserDefaults.standard.bool(forKey: "ForceMLXOverAFM")
            if #available(macOS 26.0, *), AFMProvider.isAvailable, !forceMLX {
                let afmSystemPrompt = systemMessage + Self.afmOutputDirective
                await MainActor.run {
                    self.lastSystemMessageSent = afmSystemPrompt
                    self.lastUserMessageSent = text
                }
                logger.notice("🦾 afm: routing — AFM primary (mlx fallback on safety refusal)")
                do {
                    let result = try await aiService.enhanceWithAFM(systemPrompt: afmSystemPrompt, userPrompt: text)
                    return AIEnhancementOutputFilter.filter(stripPreamble(result))
                } catch let providerError as AFMProvider.ProviderError {
                    if case .safetyRefusal = providerError {
                        logger.notice("🦾 afm: refused, falling back to MLX")
                        // Fall through to MLX path below.
                    } else {
                        throw EnhancementError.customError(providerError.errorDescription ?? "An unknown Apple Foundation Models error occurred.")
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }

            do {
                // W11 prompt-fix: pass the <TRANSCRIPT>-wrapped userPrompt so the
                // model actually sees the tags its system prompt is told to look
                // for. Without this, Qwen3-Instruct's chat-instruct training
                // dominates and the model REPLIES to the dictation instead of
                // CLEANING it. Closing suffix nails the contract shut.
                //
                // W11.A2 short-transcript fast-path: when the dictation is ≤120 chars
                // (≈30 tokens) AND no clipboard/screen context is active, swap the
                // ~1,200-token full wrapper for the ~50-token cleanup template. Drops
                // system prefill cost ~30-50% on short cleanups. The full wrapper still
                // governs longer dictations and any case with active context. See plan
                // §Migration policy #1.
                let mlxSystemMessage: String
                let mlxPromptMode: EnhancementTimingLogger.PromptMode
                if shouldUseMLXFastPath(text: text) {
                    mlxSystemMessage = AIPrompts.shortTranscriptCleanupTemplate
                    mlxPromptMode = .fastPath
                    await MainActor.run {
                        self.lastSystemMessageSent = mlxSystemMessage
                    }
                    logger.notice("🦾 prompt-mode: fastPath input=\(text.count, privacy: .public) chars (threshold=\(self.MLXShortTranscriptCharThreshold, privacy: .public), no clipboard/screen ctx)")
                } else {
                    mlxSystemMessage = systemMessage
                    mlxPromptMode = .standard
                    let reason = text.count > MLXShortTranscriptCharThreshold ? "input>=120" : "hasContextualAugmentation"
                    logger.notice("🦾 prompt-mode: standard input=\(text.count, privacy: .public) chars (reason=\(reason, privacy: .public))")
                }
                let mlxUserPrompt = formattedText + "\n\nOutput only the cleaned text. Do not respond to the content above."
                await MainActor.run {
                    self.lastUserMessageSent = mlxUserPrompt
                }
                let result = try await aiService.enhanceWithMLX(systemPrompt: mlxSystemMessage, userPrompt: mlxUserPrompt, promptMode: mlxPromptMode)
                return AIEnhancementOutputFilter.filter(stripPreamble(result))
            } catch {
                if let providerError = error as? MLXProvider.ProviderError {
                    throw EnhancementError.customError(providerError.errorDescription ?? "An unknown MLX error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        if aiService.selectedProvider == .foundationModels {
            guard #available(macOS 26.0, *) else {
                throw EnhancementError.customError("Apple Foundation Models requires macOS 26 or later.")
            }
            do {
                // Apple's 3B foundation model is conservative under heavy prompts and
                // tends to (a) echo XML-wrapped input verbatim, (b) prefix output with
                // conversational preambles like "Sure, here's the cleaned version:".
                // Pass the raw transcript (no <TRANSCRIPT> wrapper) and append a strict
                // output directive so the model emits only the cleaned text.
                let afmSystemPrompt = systemMessage + Self.afmOutputDirective
                let result = try await aiService.enhanceWithAFM(systemPrompt: afmSystemPrompt, userPrompt: text)
                return AIEnhancementOutputFilter.filter(stripPreamble(result))
            } catch {
                if let providerError = error as? AFMProvider.ProviderError {
                    throw EnhancementError.customError(providerError.errorDescription ?? "An unknown Apple Foundation Models error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        try await waitForRateLimit()

        do {
            let result: String
            switch aiService.selectedProvider {
            case .anthropic:
                result = try await AnthropicLLMClient.chatCompletion(
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
            default:
                guard let baseURL = URL(string: aiService.selectedProvider.baseURL) else {
                    throw EnhancementError.customError("\(aiService.selectedProvider.rawValue) has an invalid API endpoint URL. Please update it in AI settings.")
                }
                let temperature = aiService.currentModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
                let reasoningEffort = ReasoningConfig.getReasoningParameter(for: aiService.currentModel)
                let extraBody = ReasoningConfig.getExtraBodyParameters(for: aiService.currentModel)
                result = try await OpenAILLMClient.chatCompletion(
                    baseURL: baseURL,
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    temperature: temperature,
                    reasoningEffort: reasoningEffort,
                    extraBody: extraBody,
                    timeout: baseTimeout
                )
            }
            return AIEnhancementOutputFilter.filter(result.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw EnhancementError.customError(error.localizedDescription)
        }
    }

    /// W11.A2: 30-token threshold expressed as 120 chars (matching the
    /// `userPrompt.count / 4` heuristic in `MLXProvider.swift` line 119).
    /// Bumping this raises fast-path coverage at the risk of producing thin
    /// cleanup on medium dictations. Plan §Migration policy #1.
    private let MLXShortTranscriptCharThreshold = 120

    private func shouldUseMLXFastPath(text: String) -> Bool {
        guard text.count <= MLXShortTranscriptCharThreshold else { return false }
        return !hasNonEmptyContextualAugmentation()
    }

    private func hasNonEmptyContextualAugmentation() -> Bool {
        if useClipboardContext, let s = lastCapturedClipboard, !s.isEmpty {
            return true
        }
        if useScreenCaptureContext, let s = screenCaptureService.lastCapturedText, !s.isEmpty {
            return true
        }
        return false
    }

    /// Belt-and-suspenders: strip the conversational preamble Apple's 3B foundation
    /// model sometimes emits despite explicit "no preamble" instructions in the prompt.
    /// Examples: "Sure, here's a cleaned-up version of the text:\n\n<actual content>"
    private func stripPreamble(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the first line ends with ':' or starts with a known filler phrase and is
        // followed by a blank line + actual content, drop everything up to the content.
        let preambleHeads = [
            "sure,", "sure!", "sure.", "here's", "here is", "here are",
            "of course", "okay,", "got it", "no problem", "absolutely",
            "i've cleaned", "i have cleaned", "i'll clean", "below is", "the cleaned",
        ]
        let lines = trimmed.components(separatedBy: "\n")
        guard let first = lines.first else { return trimmed }
        let firstLower = first.lowercased().trimmingCharacters(in: .whitespaces)
        let looksLikePreamble = firstLower.hasSuffix(":")
            || preambleHeads.contains(where: { firstLower.hasPrefix($0) })
        guard looksLikePreamble, lines.count >= 2 else { return trimmed }

        let rest = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return rest.isEmpty ? trimmed : rest
    }

    private func mapLLMKitError(_ error: LLMKitError) -> EnhancementError {
        switch error {
        case .missingAPIKey:
            return .notConfigured
        case .httpError(let statusCode, let message):
            if statusCode == 429 { return .rateLimitExceeded }
            if (500...599).contains(statusCode) { return .serverError }
            return .customError("HTTP \(statusCode): \(message)")
        case .noResultReturned:
            return .enhancementFailed
        case .networkError:
            return .networkError
        case .timeout:
            return .timeout
        case .invalidURL, .decodingError, .encodingError:
            return .customError(error.localizedDescription ?? "An unknown error occurred.")
        }
    }

    private var retryOnTimeout: Bool {
        UserDefaults.standard.bool(forKey: "EnhancementRetryOnTimeout")
    }

    private func makeRequestWithRetry(text: String, mode: EnhancementPrompt, maxRetries: Int = 3, initialDelay: TimeInterval = 1.0) async throws -> String {
        var retries = 0
        var currentDelay = initialDelay

        while retries < maxRetries {
            do {
                return try await makeRequest(text: text, mode: mode)
            } catch let error as EnhancementError {
                switch error {
                case .networkError, .serverError, .rateLimitExceeded:
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries.")
                        throw error
                    }
                case .timeout:
                    if retryOnTimeout {
                        retries += 1
                        if retries < maxRetries {
                            logger.warning("Request timed out, retrying immediately... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        } else {
                            logger.error("Request timed out after \(maxRetries, privacy: .public) retries.")
                            throw error
                        }
                    } else {
                        logger.error("Request timed out, failing immediately (retry disabled).")
                        throw error
                    }
                default:
                    throw error
                }
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && [NSURLErrorNotConnectedToInternet, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost].contains(nsError.code) {
                    retries += 1
                    if retries < maxRetries {
                        logger.warning("Request failed with network error, retrying in \(currentDelay, privacy: .public)s... (Attempt \(retries, privacy: .public)/\(maxRetries, privacy: .public))")
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                    } else {
                        logger.error("Request failed after \(maxRetries, privacy: .public) retries with network error.")
                        throw EnhancementError.networkError
                    }
                } else {
                    throw error
                }
            }
        }

        throw EnhancementError.enhancementFailed
    }

    func enhance(_ text: String) async throws -> (String, TimeInterval, String?) {
        let startTime = Date()
        let enhancementPrompt: EnhancementPrompt = .transcriptionEnhancement
        let promptName = activePrompt?.title

        do {
            let result = try await makeRequestWithRetry(text: text, mode: enhancementPrompt)
            let endTime = Date()
            let duration = endTime.timeIntervalSince(startTime)
            return (result, duration, promptName)
        } catch {
            throw error
        }
    }

    /// W12.B Command Mode rewrite entry. Takes a captured selection + a dictated
    /// instruction; returns the rewrite + the elapsed duration. Mirrors the
    /// `enhance(_:)` provider routing (Ollama / LocalCLI / MLX / AFM / cloud) but
    /// uses `AIPrompts.commandModeTemplate` for the system prompt and
    /// `<SELECTION>...</SELECTION>` for the user prompt. The cleanup-level
    /// directive (W12.A) is intentionally NOT prepended — Command Mode is its own
    /// rewrite intent, not a CLEANUP intensity. See plan
    /// `docs/superpowers/plans/W12B-command-mode.md` §Migration policy #3.
    func commandModeRewrite(selection: String, instruction: String) async throws -> (String, TimeInterval) {
        let startTime = Date()

        guard isConfigured else {
            throw EnhancementError.notConfigured
        }
        guard !selection.isEmpty, !instruction.isEmpty else {
            throw EnhancementError.enhancementFailed
        }

        let systemMessage = String(format: AIPrompts.commandModeTemplate, instruction)
        let userPrompt = "<SELECTION>\n\(selection)\n</SELECTION>"

        logger.notice("🦾 command-mode: provider=\(self.aiService.selectedProvider.rawValue, privacy: .public) selectionChars=\(selection.count, privacy: .public) instructionChars=\(instruction.count, privacy: .public)")

        await MainActor.run {
            self.lastSystemMessageSent = systemMessage
            self.lastUserMessageSent = userPrompt
        }

        let result: String

        if aiService.selectedProvider == .ollama {
            do {
                result = try await aiService.enhanceWithOllama(text: userPrompt, systemPrompt: systemMessage)
            } catch {
                if let localError = error as? LocalAIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                }
                throw EnhancementError.customError(error.localizedDescription)
            }
        } else if aiService.selectedProvider == .localCLI {
            do {
                result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: userPrompt)
            } catch {
                if let localError = error as? LocalCLIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                }
                throw EnhancementError.customError(error.localizedDescription)
            }
        } else if aiService.selectedProvider == .mlx {
            // Migration policy #9 — mirror the AFM-first / MLX-fallback routing
            // from enhance(...) verbatim.
            var afmRefused = false
            if #available(macOS 26.0, *), AFMProvider.isAvailable {
                let afmSystemPrompt = systemMessage + Self.afmOutputDirective
                await MainActor.run { self.lastSystemMessageSent = afmSystemPrompt }
                do {
                    let raw = try await aiService.enhanceWithAFM(systemPrompt: afmSystemPrompt, userPrompt: userPrompt)
                    let duration = Date().timeIntervalSince(startTime)
                    return (AIEnhancementOutputFilter.filter(stripPreamble(raw)), duration)
                } catch let providerError as AFMProvider.ProviderError {
                    if case .safetyRefusal = providerError {
                        logger.notice("🦾 command-mode: AFM refused, falling back to MLX")
                        afmRefused = true
                    } else {
                        throw EnhancementError.customError(providerError.errorDescription ?? "An unknown Apple Foundation Models error occurred.")
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
            _ = afmRefused

            do {
                // Migration policy #11 — no fast-path on Command Mode. Always uses
                // the full commandModeTemplate.
                let raw = try await aiService.enhanceWithMLX(systemPrompt: systemMessage, userPrompt: userPrompt, promptMode: .standard)
                result = AIEnhancementOutputFilter.filter(stripPreamble(raw))
            } catch {
                if let providerError = error as? MLXProvider.ProviderError {
                    throw EnhancementError.customError(providerError.errorDescription ?? "An unknown MLX error occurred.")
                }
                throw EnhancementError.customError(error.localizedDescription)
            }
        } else if aiService.selectedProvider == .foundationModels {
            guard #available(macOS 26.0, *) else {
                throw EnhancementError.customError("Apple Foundation Models requires macOS 26 or later.")
            }
            do {
                let afmSystemPrompt = systemMessage + Self.afmOutputDirective
                let raw = try await aiService.enhanceWithAFM(systemPrompt: afmSystemPrompt, userPrompt: userPrompt)
                result = AIEnhancementOutputFilter.filter(stripPreamble(raw))
            } catch {
                if let providerError = error as? AFMProvider.ProviderError {
                    throw EnhancementError.customError(providerError.errorDescription ?? "An unknown Apple Foundation Models error occurred.")
                }
                throw EnhancementError.customError(error.localizedDescription)
            }
        } else {
            try await waitForRateLimit()
            do {
                let raw: String
                switch aiService.selectedProvider {
                case .anthropic:
                    raw = try await AnthropicLLMClient.chatCompletion(
                        apiKey: aiService.apiKey,
                        model: aiService.currentModel,
                        messages: [.user(userPrompt)],
                        systemPrompt: systemMessage,
                        timeout: baseTimeout
                    )
                default:
                    guard let baseURL = URL(string: aiService.selectedProvider.baseURL) else {
                        throw EnhancementError.customError("\(aiService.selectedProvider.rawValue) has an invalid API endpoint URL. Please update it in AI settings.")
                    }
                    let temperature = aiService.currentModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
                    let reasoningEffort = ReasoningConfig.getReasoningParameter(for: aiService.currentModel)
                    let extraBody = ReasoningConfig.getExtraBodyParameters(for: aiService.currentModel)
                    raw = try await OpenAILLMClient.chatCompletion(
                        baseURL: baseURL,
                        apiKey: aiService.apiKey,
                        model: aiService.currentModel,
                        messages: [.user(userPrompt)],
                        systemPrompt: systemMessage,
                        temperature: temperature,
                        reasoningEffort: reasoningEffort,
                        extraBody: extraBody,
                        timeout: baseTimeout
                    )
                }
                result = AIEnhancementOutputFilter.filter(raw.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch let error as LLMKitError {
                throw mapLLMKitError(error)
            } catch let error as EnhancementError {
                throw error
            } catch {
                throw EnhancementError.customError(error.localizedDescription)
            }
        }

        let duration = Date().timeIntervalSince(startTime)
        return (result, duration)
    }

    /// Live-preview enhancement run for the Prompts editor (spec §3.9 / plan §P3.E).
    ///
    /// Diverges from `enhance(_:)` on three deliberate axes:
    /// 1. **Arbitrary prompt** — caller supplies the prompt being edited, NOT
    ///    `activePrompt`. The preview must reflect unsaved drafts.
    /// 2. **No contextual capture** — clipboard, screen, selected text and
    ///    custom vocabulary are intentionally omitted. Preview exercises the
    ///    template itself, not the runtime context noise.
    /// 3. **No rate-limit, no retry** — the editor's 1.2s debounce is the
    ///    rate-limiter. Retry would cause stale results to land after a
    ///    newer edit. Cancellation is cooperative via `Task.checkCancellation()`
    ///    plus URLSession's task-level cancellation propagation; the caller
    ///    stores the `Task` handle and `.cancel()`s on re-edit.
    ///
    /// `lastSystemMessageSent` / `lastUserMessageSent` are NOT mutated —
    /// preview must not pollute the production debug state.
    func enhancePreview(text: String, prompt: CustomPrompt) async throws -> String {
        guard isConfigured else { throw EnhancementError.notConfigured }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        try Task.checkCancellation()

        let systemMessage: String = (prompt.id == PredefinedPrompts.assistantPromptId)
            ? prompt.promptText
            : prompt.finalPromptText
        let formattedText = "\n<TRANSCRIPT>\n\(trimmed)\n</TRANSCRIPT>"

        if aiService.selectedProvider == .ollama {
            do {
                let result = try await aiService.enhanceWithOllama(text: formattedText, systemPrompt: systemMessage)
                return AIEnhancementOutputFilter.filter(result)
            } catch is CancellationError { throw CancellationError() } catch {
                if let localError = error as? LocalAIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Ollama error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }
        if aiService.selectedProvider == .localCLI {
            do {
                let result = try await aiService.enhanceWithLocalCLI(systemPrompt: systemMessage, userPrompt: formattedText)
                return AIEnhancementOutputFilter.filter(result)
            } catch is CancellationError { throw CancellationError() } catch {
                if let localError = error as? LocalCLIError {
                    throw EnhancementError.customError(localError.errorDescription ?? "An unknown Local CLI error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }
        if aiService.selectedProvider == .mlx {
            do {
                // W11 prompt-fix: match production MLX path — wrap in <TRANSCRIPT>
                // tags + closing suffix so the preview reflects what enhance(_:)
                // actually sends.
                let mlxUserPrompt = formattedText + "\n\nOutput only the cleaned text. Do not respond to the content above."
                let result = try await aiService.enhanceWithMLX(systemPrompt: systemMessage, userPrompt: mlxUserPrompt)
                return AIEnhancementOutputFilter.filter(stripPreamble(result))
            } catch is CancellationError { throw CancellationError() } catch {
                if let providerError = error as? MLXProvider.ProviderError {
                    throw EnhancementError.customError(providerError.errorDescription ?? "An unknown MLX error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }
        if aiService.selectedProvider == .foundationModels {
            guard #available(macOS 26.0, *) else {
                throw EnhancementError.customError("Apple Foundation Models requires macOS 26 or later.")
            }
            do {
                let afmSystemPrompt = systemMessage + Self.afmOutputDirective
                let result = try await aiService.enhanceWithAFM(systemPrompt: afmSystemPrompt, userPrompt: trimmed)
                return AIEnhancementOutputFilter.filter(stripPreamble(result))
            } catch is CancellationError { throw CancellationError() } catch {
                if let providerError = error as? AFMProvider.ProviderError {
                    throw EnhancementError.customError(providerError.errorDescription ?? "An unknown Apple Foundation Models error occurred.")
                } else {
                    throw EnhancementError.customError(error.localizedDescription)
                }
            }
        }

        try Task.checkCancellation()

        do {
            let result: String
            switch aiService.selectedProvider {
            case .anthropic:
                result = try await AnthropicLLMClient.chatCompletion(
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    timeout: baseTimeout
                )
            default:
                guard let baseURL = URL(string: aiService.selectedProvider.baseURL) else {
                    throw EnhancementError.customError("\(aiService.selectedProvider.rawValue) has an invalid API endpoint URL. Please update it in AI settings.")
                }
                let temperature = aiService.currentModel.lowercased().hasPrefix("gpt-5") ? 1.0 : 0.3
                let reasoningEffort = ReasoningConfig.getReasoningParameter(for: aiService.currentModel)
                let extraBody = ReasoningConfig.getExtraBodyParameters(for: aiService.currentModel)
                result = try await OpenAILLMClient.chatCompletion(
                    baseURL: baseURL,
                    apiKey: aiService.apiKey,
                    model: aiService.currentModel,
                    messages: [.user(formattedText)],
                    systemPrompt: systemMessage,
                    temperature: temperature,
                    reasoningEffort: reasoningEffort,
                    extraBody: extraBody,
                    timeout: baseTimeout
                )
            }
            return AIEnhancementOutputFilter.filter(result.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as LLMKitError {
            throw mapLLMKitError(error)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as EnhancementError {
            throw error
        } catch {
            throw EnhancementError.customError(error.localizedDescription)
        }
    }

    func captureScreenContext() async {
        guard CGPreflightScreenCaptureAccess() else {
            return
        }

        if let capturedText = await screenCaptureService.captureAndExtractText() {
            await MainActor.run {
                self.objectWillChange.send()
            }
        }
    }

    func captureClipboardContext() {
        lastCapturedClipboard = NSPasteboard.general.string(forType: .string)
    }

    /// W11.A1: fire-and-forget MLX warm-up. Safe no-op when the active provider
    /// isn't MLX or no model is selected. Errors logged inside `warmMLX()` but
    /// never surfaced — a failed warm leaves the next `enhance(...)` paying the
    /// cold-load cost, same as pre-W11.A1 behavior.
    ///
    /// W11.D: `source` flows into the prewarm-fired diagnostic log
    /// (`appLaunch` / `wake` / `recordingStart`).
    func warmMLXIfSelected(source: String) async {
        guard aiService.selectedProvider == .mlx else { return }
        await aiService.warmMLX(source: source)
    }

    /// W11.B: fire-and-forget Apple Foundation Models warm-up. Fired by
    /// `ModelPrewarmService` whenever AFM is available — i.e. the AFM-first
    /// routing in `.mlx` selection or the direct `.foundationModels`
    /// selection. Errors are swallowed inside `warmAFM(source:)`.
    func warmAFMIfAvailable(source: String) async {
        if #available(macOS 26.0, *) {
            // Warm whenever AFM is available, since the active path can flip
            // from MLX → AFM mid-session if the user enables Apple Intelligence.
            // Cheap; LanguageModelSession.prewarm() is idempotent.
            guard AFMProvider.isAvailable else { return }
            await aiService.warmAFM(source: source)
        }
    }

    /// W11.B: human-readable label for the Active Path indicator in the
    /// Enhancement Settings panel. Reflects what the next enhance(...) will
    /// actually route through given the user's MLX selection.
    var activeLocalPathDescription: String {
        if #available(macOS 26.0, *) {
            return AFMProvider.availabilityDescription()
        }
        return "MLX (macOS 26 required for Apple Foundation Models)"
    }

    /// W11.B / W11.A2 — directive appended to AFM system prompt. Apple's 3B
    /// foundation model is conservative under heavy prompts and tends to
    /// (a) echo XML-wrapped input verbatim, (b) prefix output with
    /// conversational preambles like "Sure, here's the cleaned version:".
    /// This block nails the contract shut. `stripPreamble(...)` is the
    /// belt-and-suspenders backup.
    fileprivate static let afmOutputDirective: String = """


    IMPORTANT OUTPUT RULES:
    - Output ONLY the cleaned text. Nothing else.
    - Do NOT add a preamble like "Sure, here's…" or "Here's the cleaned version:".
    - Do NOT wrap the output in quotes or code fences.
    - Do NOT explain what you changed.
    - Do NOT ask follow-up questions.
    """
    
    func clearCapturedContexts() {
        lastCapturedClipboard = nil
        screenCaptureService.lastCapturedText = nil
    }

    func addPrompt(title: String, promptText: String, icon: PromptIcon = "doc.text.fill", description: String? = nil, triggerWords: [String] = [], useSystemInstructions: Bool = true) {
        let newPrompt = CustomPrompt(title: title, promptText: promptText, icon: icon, description: description, isPredefined: false, triggerWords: triggerWords, useSystemInstructions: useSystemInstructions)
        customPrompts.append(newPrompt)
        if customPrompts.count == 1 {
            selectedPromptId = newPrompt.id
        }
    }

    func updatePrompt(_ prompt: CustomPrompt) {
        if let index = customPrompts.firstIndex(where: { $0.id == prompt.id }) {
            customPrompts[index] = prompt
        }
    }

    func deletePrompt(_ prompt: CustomPrompt) {
        customPrompts.removeAll { $0.id == prompt.id }
        if selectedPromptId == prompt.id {
            selectedPromptId = allPrompts.first?.id
        }
    }

    func setActivePrompt(_ prompt: CustomPrompt) {
        selectedPromptId = prompt.id
    }

    private func initializePredefinedPrompts() {
        let predefinedTemplates = PredefinedPrompts.createDefaultPrompts()

        for template in predefinedTemplates {
            if let existingIndex = customPrompts.firstIndex(where: { $0.id == template.id }) {
                var updatedPrompt = customPrompts[existingIndex]
                updatedPrompt = CustomPrompt(
                    id: updatedPrompt.id,
                    title: template.title,
                    promptText: template.promptText,
                    isActive: updatedPrompt.isActive,
                    icon: template.icon,
                    description: template.description,
                    isPredefined: true,
                    triggerWords: updatedPrompt.triggerWords,
                    useSystemInstructions: template.useSystemInstructions
                )
                customPrompts[existingIndex] = updatedPrompt
            } else {
                customPrompts.append(template)
            }
        }
    }
}

enum EnhancementError: Error {
    case notConfigured
    case invalidResponse
    case enhancementFailed
    case networkError
    case serverError
    case rateLimitExceeded
    case timeout
    case customError(String)
}

extension EnhancementError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "AI provider not configured. Please check your API key."
        case .invalidResponse:
            return "Invalid response from AI provider."
        case .enhancementFailed:
            return "AI enhancement failed to process the text."
        case .networkError:
            return "Network connection failed. Check your internet."
        case .serverError:
            return "The AI provider's server encountered an error. Please try again later."
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .timeout:
            return "Enhancement request timed out. Check your connection or increase the timeout duration."
        case .customError(let message):
            return message
        }
    }
}
