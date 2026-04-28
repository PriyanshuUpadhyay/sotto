# RECON: VoiceInk AI Enhancement Architecture

**Date:** 2026-04-27
**VoiceInk pinned at:** v1.74 (commit `851b260e3f42fec4cc9d21ab9c5f67d2919e6e2e`)

---

## Summary of architectural divergence from plan

The plan assumed a `protocol AIProvider` with implementations like `OllamaProvider`, `OpenAIProvider`, etc. — that abstraction **does not exist**. Provider dispatch is hardcoded `if`/`switch` on a `String`-backed enum (`AIProvider`) at one call site (`AIEnhancementService.makeRequest`). Adding new providers means: (a) adding enum cases, (b) adding `if`/`switch` branches in `makeRequest`, and (c) optionally hosting an `actor`/`class` per provider that the dispatch branch awaits.

**Plan callout (Task 0.3 Step 8):** "If recon reveals a fundamentally different architecture (no protocol, hardcoded if/else, sync-only call site), STOP and surface" — this is exactly that case. **Surfaced in §7.** The fork can still proceed, but tasks referencing `<ProtocolName>` need adjustment (see §7).

---

## 1. Provider Abstraction

- **Protocol:** _none._ No protocol unifies providers.
- **Provider enum:** `AIProvider` defined in `VoiceInk/Services/AIEnhancement/AIService.swift:4-166`
  - String-backed (rawValue is user-visible name).
  - Cases: `cerebras`, `groq`, `gemini`, `anthropic`, `openAI`, `openRouter`, `mistral`, `elevenLabs`, `deepgram`, `soniox`, `speechmatics`, `ollama`, `localCLI`, `custom`.
  - Per-case computed properties: `baseURL`, `defaultModel`, `availableModels`, `requiresAPIKey`.
- **Factory:** _none._ Provider behaviour is dispatched inline in `AIEnhancementService.makeRequest(text:mode:)` at `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:204-287`.
  - Special-cased branches at lines 221 (`.ollama`), 234 (`.localCLI`).
  - Default branch (lines 247-278) routes API-based providers through `OpenAILLMClient.chatCompletion(...)` from the `LLMkit` SPM dep, with `.anthropic` switched to `AnthropicLLMClient.chatCompletion(...)`.
- **Method signature(s):** there is no protocol method. The de-facto contract per provider helper is:

  ```swift
  func enhance(text: String, withSystemPrompt: String) async throws -> String       // Ollama
  func enhance(systemPrompt: String, userPrompt: String) async throws -> String     // LocalCLI
  ```

  Returns the cleaned-up text (raw, before `AIEnhancementOutputFilter.filter`). The filter is applied at the dispatch site.

---

## 2. Existing Provider (reference impl)

- **Reference file (closest match to our embedded use case):** `VoiceInk/Services/AIEnhancement/LocalCLIService.swift`
- **Type:** `final class LocalCLIService` (not actor — but our actors fit the same shape).
- **Key responsibilities:**
  - `isConfigured: Bool` — provider availability gate (returns false → `AIService.isAPIKeyValid` becomes false → `AIEnhancementService.handleAPIKeyChange` disables enhancement).
  - `enhance(systemPrompt:userPrompt:) async throws -> String` — the actual call.
  - Per-provider error type `LocalCLIError: Error, LocalizedError`. Wrapped at the dispatch site as `EnhancementError.customError(localError.errorDescription ?? "...")`.
  - Settings stored in `UserDefaults` via `didSet` on instance properties.

This is the pattern we will mirror for `MLXProvider` (and minimally for `FoundationModelsProvider`).

---

## 3. Settings UI

- **Picker view:** `VoiceInk/Views/AI Models/APIKeyManagementView.swift:22-26`

  ```swift
  Picker("Provider", selection: $aiService.selectedProvider) {
      ForEach(AIProvider.allCases.filter { $0 != .elevenLabs && $0 != .deepgram && $0 != .soniox && $0 != .speechmatics }, id: \.self) { provider in
          Text(provider.rawValue).tag(provider)
      }
  }
  ```

- **Binding:** `$aiService.selectedProvider` (typed `AIProvider`, persisted via `didSet` in `AIService.swift:181-204`).
- **Per-provider config UI:** lives further down `APIKeyManagementView.swift` — model picker block at lines 71-119 (covers OpenRouter and the generic `availableModels` providers) + provider-conditional sections for Ollama and Local CLI farther down the file. New provider config UI (e.g. `MLXModelPickerView`) is added by appending a new conditional block:

  ```swift
  if aiService.selectedProvider == .mlx {
      MLXModelPickerView()
  }
  ```

- **Power Mode per-mode override:** `VoiceInk/PowerMode/PowerModeConfigView.swift:25-26, 76-94, 320-400` — per-mode `selectedAIProvider: String?` and `selectedAIModel: String?` (raw strings, not enum). New enum cases appear automatically if the picker iterates `AIProvider.allCases` (verified: line 320-ish region binds via `Binding<AIProvider>` + `selectedAIProvider = newValue.rawValue`). **No Power Mode code changes required for new enum cases**, except: filtering might need updating if MLX/FoundationModels should be excluded from certain Power Mode contexts (none apparent).
- **Top-level entry:** `VoiceInk/Views/EnhancementSettingsView.swift` hosts `APIKeyManagementView()` at line 74.

---

## 4. Persistence Keys

- **Provider selection (global):** `selectedAIProvider` (`UserDefaults`, value = `AIProvider.rawValue`). See `AIService.swift:183, 261-269`.
- **Per-provider model selection:** `"\(provider.rawValue)SelectedModel"` (e.g. `"OpenAISelectedModel"`). See `AIService.swift:287, 308`. Our MLX provider will use a custom key `mlx_selected_model_id` (matches plan).
- **Provider-specific keys observed:**
  - `ollamaBaseURL`, `ollamaSelectedModel`, `customProviderBaseURL`, `customProviderModel`
  - `localCLICommandTemplate`, `localCLISelectedTemplate`, `localCLITimeoutSeconds`
  - `isAIEnhancementEnabled`, `useClipboardContext`, `useScreenCaptureContext`, `selectedPromptId`, `customPrompts`
  - `EnhancementTimeoutSeconds`, `EnhancementRetryOnTimeout`, `SkipShortEnhancement`, `ShortEnhancementWordThreshold`
- **Per-Power-Mode persistence:** `selectedAIProvider: String?` and `selectedAIModel: String?` are fields on `PowerModeConfig` (Codable). See `VoiceInk/PowerMode/PowerModeConfig.swift:35-43, 51`.
- **API keys:** stored via `APIKeyManager.shared` (Keychain wrapper). Embedded providers don't need API keys, so `requiresAPIKey` returns `false` (matches `.ollama`, `.localCLI`).

---

## 5. Cancellation & Threading (codex-flagged)

### Provider call site

- **Top-level dispatch:** `AIEnhancementService.makeRequest(text:mode:)` at `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:204-287`.
- **Pipeline integration site:** `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift:111-142`:

  ```swift
  if let enhancementService, enhancementService.isEnhancementEnabled, ... {
      if shouldCancel() { await onCleanup(); return }
      onStateChange(.enhancing)
      let textForAI = promptDetectionResult?.processedText ?? text
      do {
          let (enhancedText, enhancementDuration, promptName) = try await enhancementService.enhance(textForAI)
          ...
          finalPastedText = enhancedText
      } catch {
          let errorDescription = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
          transcription.enhancedText = "Enhancement failed: \(errorDescription)"
          // NotificationManager.shared.showNotification(...) shown to user
          if shouldCancel() { await onCleanup(); return }
      }
  }
  ```

  Other call sites (audio file transcription, audio player view): `VoiceInk/Services/AudioFileTranscriptionService.swift:100`, `VoiceInk/Services/AudioFileTranscriptionManager.swift:182`, `VoiceInk/Views/AudioPlayerView.swift:541`.

### Cancellation: NO Swift `Task` cancellation infrastructure

- `shouldCancel` is a `() -> Bool` closure (`TranscriptionPipeline.swift:45`) that polls `engine.shouldCancelRecording: Bool` (`VoiceInkEngine.swift:11`).
- It is checked **before** and **after** `enhance(...)` (lines 115 and 140), but **not propagated as `Task.cancel()`** to the in-flight enhancement call.
- Consequence: if user cancels mid-enhancement, the call continues to completion server-side / on-device; result is then silently discarded post-hoc.
- **Implication for our providers:** we will still call `Task.checkCancellation()` defensively (per plan), but in practice the host will not cancel us. Plan's "cancellation smoke test" (Task 1.4 Step 4, Task 4.4 Step 7) is **skipped or marked N/A** with a documented gap to be closed in a follow-up. This matches plan's known-limitation #3 in §Self-Review.

### Threading

- `AIEnhancementService` is **`@MainActor`** (`AIEnhancementService.swift:12`). The whole class body runs on MainActor by default.
- `makeRequest(...)` is `async throws`. Inside, `await aiService.enhanceWith*(...)` calls jump off main when the underlying provider does I/O (URLSession, Process).
- **Implication for our providers:** our `actor`s are inherently off-main. When `await` ed from `@MainActor` code, the actor hop ensures generation runs on a cooperative thread, not main. **This is fine.** No host-side changes required.
- **One subtlety:** Inside `makeRequest`, MLX inference is heavy CPU/GPU work. While the actor isolates state, the actual generation runs as part of the actor's serial executor, which is a global cooperative thread pool. No main-thread blocking. Confirmed safe.

### Existing per-recording cancellation token? **No.** (Polled boolean only.)

---

## 6. Build Issues Encountered

### 6a. Personal team cannot sign upstream entitlements

- **Error:** "Cannot create a Mac App Development provisioning profile for `com.prakashjoshipax.VoiceInk`. Personal development teams do not support the Push Notifications and iCloud capabilities."
- **Cause:** `VoiceInk/VoiceInk.entitlements` declares `com.apple.developer.aps-environment`, `com.apple.developer.icloud-container-identifiers`, `com.apple.developer.icloud-services`, and a non-default `keychain-access-groups`. Personal Apple IDs cannot provision these.
- **Resolution path supported by upstream:** `make local`.
  - Defined in `Makefile:48-77` and documented in `BUILDING.md:57-77`.
  - Uses ad-hoc signing (`CODE_SIGN_IDENTITY=-`, `CODE_SIGNING_REQUIRED=NO`).
  - Switches entitlements to `VoiceInk/VoiceInk.local.entitlements` (no iCloud, no Push, no keychain-groups).
  - Sets `SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD` so Swift code falls back at compile time.
  - `LOCAL_BUILD`-gated sites: `VoiceInk/VoiceInk.swift:202`, `VoiceInk/Services/KeychainService.swift:14, 36, 68, 91, 112, 125`, `VoiceInk/Models/LicenseViewModel.swift:27`. Effects: keychain falls back to default keychain (no shared access group), Polar license check is bypassed, iCloud dictionary sync disabled.
  - Output: `~/Downloads/VoiceInk.app`.
- **Limitations of `make local` (per BUILDING.md and Makefile output):** no iCloud dictionary sync, no auto-updates. Acceptable for a personal fork.
- **First-time cost:** clones `whisper.cpp` to `~/VoiceInk-Dependencies/whisper.cpp` and builds the xcframework (~5-10 min). Subsequent builds reuse the cached framework.
- **Alternative considered (rejected):** edit `VoiceInk.xcodeproj` directly to point Debug/Release configurations at `VoiceInk.local.entitlements` + change bundle ID to `work.foyer.voiceink-fork`. Rejected because (a) `make local` is the upstream-supported escape hatch designed for exactly this, (b) editing the pbxproj would create a perpetual rebase conflict against upstream `v1.74` baseline.
- **Going forward:** all build verification in this fork uses `make local`. Phase 0 build is via `make local`. Phase 1+ Xcode work (`Cmd+B` / `Cmd+R` while in Xcode for code editing) will need either: (i) ad-hoc-signing scheme set up in Xcode, or (ii) continued use of CLI `make local` after edits. Decision deferred until Phase 1 — for now, code can be edited in Xcode without running there, then verified via `make local`.

---

## 7. Open Questions / Spec & Plan Conflicts

### 7a. No `protocol AIProvider` exists

- **Plan tasks affected:** 1.1 Step 1 (`<ProtocolName>`), 1.2 Step 3 (factory), 2.2 Step 1 (`<ProtocolName>`), 4.3 Step 1 (factory).
- **Reconciliation:**
  - **Drop the `: <ProtocolName>` conformance** from `actor FoundationModelsProvider` and `actor MLXProvider`. Each is a free-standing actor whose public surface is `enhance(systemPrompt:userPrompt:) async throws -> String` and `isConfigured: Bool`.
  - **Don't create a factory.** Add `case foundationModels` and `case mlx` to `AIProvider` enum. Add direct dispatch branches in `AIEnhancementService.makeRequest(...)` mirroring the existing Ollama/LocalCLI branches:

    ```swift
    if aiService.selectedProvider == .foundationModels {
        if #available(macOS 26.0, *) {
            do {
                let result = try await foundationModelsProvider.enhance(systemPrompt: systemMessage, userPrompt: formattedText)
                return AIEnhancementOutputFilter.filter(result)
            } catch {
                throw EnhancementError.customError(error.localizedDescription)
            }
        } else {
            throw EnhancementError.customError("Foundation Models requires macOS 26+")
        }
    }
    if aiService.selectedProvider == .mlx { ... }
    ```

  - **Where do the actors live?** Lazily instantiated as properties of `AIService` (mirrors `ollamaService`, `localCLIService`). Or as a private `lazy var` on `AIEnhancementService`. Decision: put them on `AIService` for consistency with existing pattern.

### 7b. `EnhancementError` already exists — extend, don't duplicate

- **Plan task affected:** 1.2 Step 1 (proposes new `EnhancementError` with cases `.providerUnavailable`, `.modelNotConfigured`, `.modelLoadFailed`, `.generationFailed`).
- **Reality:** `EnhancementError` defined in `AIEnhancementService.swift:454-486` already has `.notConfigured`, `.invalidResponse`, `.enhancementFailed`, `.networkError`, `.serverError`, `.rateLimitExceeded`, `.timeout`, `.customError(String)`.
- **Reconciliation:**
  - **Use `.customError(String)`** for our new failure modes. It already conforms to `LocalizedError` and is the existing pattern (see Ollama/LocalCLI dispatch — they wrap their per-provider errors via `.customError(localError.errorDescription ?? ...)`).
  - **Optional minor extension:** if we want `.providerUnavailable` to be matchable (e.g. for special UI handling), add ONE new case: `case providerUnavailable(String)`. Otherwise stick to `.customError`.
  - **Decision:** start with `.customError(...)` only. No new file. Extend the enum minimally only if a downstream task needs distinct matching.

### 7c. Passthrough fallback already implemented

- **Plan task affected:** 3.4 (proposes wrapping the call site in do/catch + setting `enhanced = raw`).
- **Reality:** `TranscriptionPipeline.swift:98, 111-142`. `finalPastedText` is initialised to the raw transcript (line 98). On enhancement failure (catch block at line 130), `finalPastedText` is **not touched** — the raw transcript is kept and pasted. A user-facing notification is shown via `NotificationManager.shared.showNotification(...)`. The failed-enhancement marker is stored on the transcription record (`transcription.enhancedText = "Enhancement failed: ..."`) for history/diagnostic visibility, **but does not affect what gets pasted**.
- **Reconciliation:**
  - **Task 3.4 is largely redundant.** The host already does passthrough.
  - Other call sites (audio file transcription manager/service/view) follow similar patterns — each must be reverified before declaring Task 3.4 complete, but no new code is expected.
  - **Decision for Task 3.4:** reduced to a verification-only step — confirm all four `enhance(...)` call sites preserve raw text on error, and add comments where the invariant isn't obvious. No new wrapping logic.

### 7d. macOS deployment target

- Need to verify (in Task 0.2) the current `MACOSX_DEPLOYMENT_TARGET` in `VoiceInk.xcodeproj`. If it is below 26.0, raise it to 26.0 — required by `FoundationModels.framework`. Alternative is `@available(macOS 26.0, *)` gating + a lower base target, but this drags `if #available` checks into many sites; cleaner to bump baseline since user is on macOS 26.

### 7e. `LLMkit` is the upstream LLM dispatch layer

- VoiceInk uses an SPM dep `LLMkit` (imports `import LLMkit` in `AIService.swift:2`, `AIEnhancementService.swift:5`, `APIKeyManagementView.swift:2`) which provides `OpenAILLMClient`, `AnthropicLLMClient`, etc. This is the host's existing LLM stack — our embedded providers bypass it entirely (we go straight to FoundationModels.framework / mlx-swift). Not a conflict, just context.

### 7f. Provider availability gating in `AIService.isAPIKeyValid`

- `AIService.selectedProvider.didSet` (lines 181-203) sets `isAPIKeyValid` based on `requiresAPIKey` and key presence. For `.localCLI`, it queries `localCLIService.isConfigured`. For `.ollama`, it sets `true` and triggers a connection check.
- Our providers should follow the same pattern:
  - `.foundationModels` → `requiresAPIKey = false`, `isAPIKeyValid = #available(macOS 26.0, *)` (or query the actor's availability check).
  - `.mlx` → `requiresAPIKey = false`, `isAPIKeyValid = MLXModelDownloader.status(forSelectedModel) == .downloaded` (so picker correctly gates "Enhancement enabled").
- **Plan addition:** these `isAPIKeyValid` rules need to be added to the `AIService.swift:181-203` `didSet` and to the `init` block (272-278).

---

## Adjusted file plan (deltas to original plan §File Structure)

**Modified in fork (specific to integration):**
- `VoiceInk/Services/AIEnhancement/AIService.swift`:
  - Add `.foundationModels` and `.mlx` cases to `AIProvider` enum (with `requiresAPIKey = false`).
  - Add `lazy var foundationModelsProvider: FoundationModelsProvider?` and `lazy var mlxProvider: MLXProvider?` (or instantiate inline at dispatch).
  - Update `isAPIKeyValid` logic in `didSet` and `init` for the two new cases.
  - Add `enhanceWithFoundationModels(...)` and `enhanceWithMLX(...)` helper functions mirroring `enhanceWithOllama` / `enhanceWithLocalCLI`.
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`:
  - Add two new dispatch branches (mirroring the `.ollama` and `.localCLI` blocks at lines 221-245) for `.foundationModels` and `.mlx`. Each wraps internal errors in `EnhancementError.customError(...)`.
- `VoiceInk/Views/AI Models/APIKeyManagementView.swift`:
  - The picker filter at line 23 already includes everything except ASR providers, so new enum cases auto-appear. Add a new conditional block after the existing per-provider sections:
    ```swift
    if aiService.selectedProvider == .mlx {
        MLXModelPickerView()
    }
    ```
  - For `.foundationModels`: no extra config UI needed (no model picker, no API key) — just availability message: `if aiService.selectedProvider == .foundationModels && !#available(macOS 26.0, *) { Text("Requires macOS 26+") }`.

**No changes needed (auto-propagated via enum):**
- `VoiceInk/PowerMode/PowerModeConfigView.swift` — picker iterates `AIProvider.allCases`.
- `VoiceInk/Views/MenuBarView.swift` — same.
- `VoiceInk/Services/SystemInfoService.swift` — diagnostic readout, harmless.

**Tasks superseded / reduced:**
- Task 1.2 Step 3 (factory): replaced by direct dispatch branches in `AIEnhancementService.makeRequest`.
- Task 3.4 (call-site fallback): reduced to verification — passthrough already exists.
- Task 4.3 Step 2 (factory): same as 1.2 Step 3.
