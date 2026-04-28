# VoiceInk Fork: Embedded LLM Providers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two new AI Enhancement providers to a private fork of VoiceInk: Apple's Foundation Models (built-in, macOS 26+) and on-device LLMs via mlx-swift. Both are in-process — no daemon — and selectable per Power Mode alongside existing OpenAI/Ollama/OpenRouter providers.

**Architecture:** Fork VoiceInk v1.74 → keep all existing functionality untouched → add three new Swift `actor` types (`FoundationModelsProvider`, `MLXProvider`, plus `MLXModelRegistry` enum) under `Services/Enhancement/` → register them in whatever provider abstraction VoiceInk uses → extend the AI Enhancement settings UI to expose them and (for MLX) a curated model picker with download flow. All inference is actor-isolated, off main thread, cancellable via `Task` cancellation. Failures fall back to passthrough (raw transcript inserted) so dictation never silently breaks.

**Tech Stack:** Swift / SwiftUI, macOS 26 (Tahoe), Apple `FoundationModels` framework, `mlx-swift` + `mlx-swift-examples` (`MLXLLM`, `MLXLMCommon`) + `swift-transformers` (`Hub`) Swift Package Manager dependencies pinned to **exact commits** (not version ranges). Xcode 16+. No new test frameworks — manual smoke checklist covers regression for this personal-fork scope.

**Spec:** [`docs/superpowers/specs/2026-04-27-voiceink-fork-embedded-llm-design.md`](../specs/2026-04-27-voiceink-fork-embedded-llm-design.md)

**Codex critique applied:** Pre-approval critique flagged `fatalError` crash path, missing actor isolation, missing cancellation contract, fragile SPM pinning, missing disk-space / OOM handling, scope creep on custom-repo UI + idle-evict stepper. All addressed below or explicitly deferred with reasoning.

---

## File Structure

**Created in fork:**
- `VoiceInk/Services/Enhancement/FoundationModelsProvider.swift` — `actor` wrapping `LanguageModelSession`. ~80 LOC.
- `VoiceInk/Services/Enhancement/MLXProvider.swift` — `actor` loading MLX-quantized HF models, running inference, idle-evicting. ~220 LOC.
- `VoiceInk/Services/Enhancement/MLXModelRegistry.swift` — curated list of 4 MLX model entries, status enum, `MLXModelDownloader` helper that pins HF cache root to Application Support and pre-checks disk space. ~140 LOC.
- `VoiceInk/Views/Settings/MLXModelPickerView.swift` — SwiftUI view: 4 curated models with download/delete/select. **No custom HF repo field in v1** (deferred per scope cut). ~130 LOC.
- `FORK.md` — fork management notes.
- `docs/RECON.md` — Phase 0 recon notes; informs all later integration tasks.

**Modified in fork (exact lines determined in Phase 0):**
- VoiceInk's existing AI Enhancement provider enum/registry.
- VoiceInk's AI Enhancement settings view.
- VoiceInk's settings persistence (UserDefaults keys).
- Xcode project file — add 3 SPM dependencies pinned to exact commit SHAs.

**Why this structure:** New providers are self-contained Swift actors conforming to VoiceInk's existing provider protocol. Touch points in upstream code are minimized to: (a) registration of new provider variants and (b) settings UI entries. Recon (Phase 0) is required to know exact files/lines.

---

## Testing Posture

**No automated tests added.** VoiceInk has a thin test surface; this fork stays consistent. For a personal-use fork, the value of new unit tests is low. **Manual smoke tests** are listed at the end of each phase and at the end of the plan; each must pass before the corresponding commit.

If a regression is found later, write a regression test at that time.

---

## Cross-cutting requirements (apply to every relevant task)

These are folded into specific tasks below; they are listed here once for clarity:

- **Actor isolation:** `FoundationModelsProvider` and `MLXProvider` are `actor` types. All mutable state (`session`, `modelContainer`, `lastUsedAt`, `evictTask`) is actor-isolated. No `static var`, no shared mutable globals.
- **Off-main-thread:** all `enhance(...)` calls are `async` and execute inside the actor. Caller (VoiceInk) must `await` from a non-main context. Verified in Phase 0 RECON §7.
- **Cancellation:** generation respects `Task.checkCancellation()`. When VoiceInk cancels the in-flight Task (e.g. user starts a new dictation), the provider returns `CancellationError`.
- **Failure fallback:** if model load or generate throws (OOM, missing file, network), the provider re-throws. The integration site (Phase 4.3) catches and **inserts the raw transcript as fallback** so dictation never silently fails.
- **No `fatalError`** in availability gates. Throw recoverable errors; UI hides the unavailable option.
- **Storage:** all MLX model files live under `Application Support/<bundle-id>/MLXModels/` — explicitly set, not Hub default cache (which can be in `Caches/` and purged by macOS).

---

## Phase 0 — Recon & Workspace Setup

### Task 0.1: Create private fork and clone

**Files:** Create `~/Code/voiceink-fork/` working tree (path adjustable).

- [ ] **Step 1: Choose Option A (private GitHub) or Option B (local-only)**

Option A — Private GitHub fork:

```bash
# In browser: github.com/Beingpax/VoiceInk → Fork → Private
cd ~/Code
gh repo clone <your-username>/VoiceInk voiceink-fork
cd voiceink-fork
git remote add upstream https://github.com/Beingpax/VoiceInk.git
git fetch upstream
```

Option B — Local-only:

```bash
cd ~/Code
git clone https://github.com/Beingpax/VoiceInk.git voiceink-fork
cd voiceink-fork
git remote rename origin upstream
```

- [ ] **Step 2: Pin to v1.74 tag and create work branch**

```bash
git fetch upstream --tags
git checkout -b priyanshu/embedded-llm v1.74
git log -1 --pretty='%h %s'
```

Expected: a commit referencing the v1.74 release.

- [ ] **Step 3: Verify clean state**

```bash
git status
```

Expected: clean working tree on `priyanshu/embedded-llm`.

---

### Task 0.2: Build from source, verify it runs

- [ ] **Step 1: Open in Xcode**

```bash
open VoiceInk.xcodeproj
```

- [ ] **Step 2: Set personal Apple ID signing**

In Xcode → project root → Signing & Capabilities → Team: personal Apple ID. Enable "Automatically manage signing".

- [ ] **Step 3: Build & run**

`Cmd+R`. Expected: app launches; dictate one sentence into TextEdit as sanity check.

- [ ] **Step 4: If build fails, document and stop**

Record build errors verbatim in `docs/RECON.md` (created next task) under §1 "Build Issues". Common gotchas: missing FluidAudio SPM resolution, code signing, provisioning profile.

Do **not** proceed until build is green.

---

### Task 0.3: Recon AI Enhancement architecture

**Files:** Create `docs/RECON.md` in fork repo.

- [ ] **Step 1: Find provider abstraction**

```bash
rg -n "openai|ollama|openrouter|anthropic" VoiceInk/Services/ --type swift -l
```

Identify the file(s) hosting provider type/enum + per-provider implementations. Note paths.

- [ ] **Step 2: Identify protocol or shared base**

Open files from step 1. Find: `protocol` definition (e.g. `AIProvider`), provider `enum`, factory function. Record exact names.

- [ ] **Step 3: Find settings UI for provider selection**

```bash
rg -n "AIProvider|EnhancementProvider|providerType|selectedProvider" VoiceInk/Views/ --type swift
```

Identify SwiftUI view(s), picker control type, binding source-of-truth (`@AppStorage` / view model).

- [ ] **Step 4: Find settings persistence keys**

```bash
rg -n "@AppStorage|UserDefaults" VoiceInk/ --type swift | rg -i "provider|enhanc"
```

Record exact keys for provider selection and per-provider config.

- [ ] **Step 5: Find cancellation / lifecycle hooks**

This is the cancellation-contract piece codex flagged. Search for how VoiceInk currently invokes a provider's `enhance(...)` and whether/how it cancels in-flight calls when the user starts a new dictation.

```bash
rg -n "enhance|Task.detached|Task {" VoiceInk/ --type swift | rg -v "test"
```

Look for the call site. Note:
- Is it called from a `Task` that gets cancelled on new dictation?
- Or fired-and-forgotten?
- Is there a per-recording cancellation token?

If there's no cancellation, that's a finding to document — our providers will still respect `Task.checkCancellation()` so a future cancellation hookup is straightforward.

- [ ] **Step 6: Find threading context of provider calls**

In the same call site, note whether it's invoked from `MainActor` or a background Task. Our actors are inherently background; the host needs to be ready for `async` calls.

- [ ] **Step 7: Write `docs/RECON.md`**

Use this exact template:

```markdown
# RECON: VoiceInk AI Enhancement Architecture

**Date:** <YYYY-MM-DD>
**VoiceInk pinned at:** v1.74 (commit <hash>)

## 1. Provider Abstraction
- Protocol: `<exact name>` defined in `<exact path>:<line range>`
- Provider enum: `<exact name>` defined in `<exact path>:<line range>`
- Factory: `<exact function>` in `<exact path>:<line range>`
- Method signature(s) every provider implements:
  ```swift
  <exact protocol body>
  ```

## 2. Existing Provider (reference impl)
- Reference file: `<filename>` (e.g. `OllamaProvider.swift`)
- Key responsibilities: <list>

## 3. Settings UI
- Picker view: `<exact path>:<line range>`
- Binding: `<exact @AppStorage key or @State var>`
- Site for adding a new provider entry:
  ```swift
  <exact code site>
  ```

## 4. Persistence Keys
- Provider selection: `<exact key>`
- Per-provider config (e.g. model name): `<exact key pattern>`

## 5. Cancellation & Threading (codex-flagged)
- Provider call site: `<exact path>:<line range>`
- Wrapped in `Task` that's cancellable? `<yes / no / how>`
- Threading context: `<MainActor / background / unspecified>`
- Existing per-recording cancellation token? `<yes / no>`

## 6. Build Issues Encountered
<empty if none>

## 7. Open Questions / Spec Conflicts
<list anything that contradicts the design spec>
```

- [ ] **Step 8: Commit**

```bash
git add docs/RECON.md
git commit -m "docs: recon notes on AI Enhancement architecture"
```

If recon reveals a fundamentally different architecture (no protocol, hardcoded if/else, sync-only call site), STOP and surface in §7 before proceeding.

---

## Phase 1 — Foundation Models Provider

### Task 1.1: Create `FoundationModelsProvider.swift`

**Files:** Create `VoiceInk/Services/Enhancement/FoundationModelsProvider.swift`.

- [ ] **Step 1: Write the actor**

Replace `<ProtocolName>` and the protocol body with the exact name/signature from RECON.md §1.

```swift
import Foundation
import FoundationModels

/// On-device LLM provider using Apple's Foundation Models framework.
/// Available on macOS 26+ only. Pre-26 hosts must not call this — UI hides
/// the option (Task 1.3) and the factory throws (Task 1.2). No fatalError.
@available(macOS 26.0, *)
actor FoundationModelsProvider: <ProtocolName> {

    private var session: LanguageModelSession

    init() {
        self.session = LanguageModelSession()
    }

    /// Match the exact signature from RECON.md §1.
    /// Example below assumes `enhance(systemPrompt:userPrompt:) async throws -> String`.
    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        try Task.checkCancellation()

        let combined = """
        \(systemPrompt)

        \(userPrompt)
        """

        let response = try await session.respond(to: Prompt { combined })

        try Task.checkCancellation()
        return response.content
    }

    /// Reset the session if it accumulates state across long sessions.
    func resetSession() {
        self.session = LanguageModelSession()
    }
}
```

- [ ] **Step 2: Add to Xcode project**

Drag into `Services/Enhancement/` group → confirm target membership = VoiceInk app.

- [ ] **Step 3: Build (Cmd+B)**

Expected: success. If `FoundationModels` import fails, raise the macOS deployment target to 26.0 (Build Settings → Deployment → macOS Deployment Target → 26.0). Document the bump in `FORK.md` (Task 5.1).

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Services/Enhancement/FoundationModelsProvider.swift VoiceInk.xcodeproj
git commit -m "feat(enhancement): add Foundation Models actor provider"
```

---

### Task 1.2: Register Foundation Models in provider enum/factory

**Files:** Modify the provider enum file + factory function from RECON.md §1.

- [ ] **Step 1: Define a recoverable error type (shared)**

If RECON.md §1 doesn't already show an error type used by the protocol, create one in a new file `VoiceInk/Services/Enhancement/EnhancementError.swift`:

```swift
import Foundation

enum EnhancementError: LocalizedError {
    case providerUnavailable(String)
    case modelNotConfigured(String)
    case modelLoadFailed(String)
    case generationFailed(String)

    var errorDescription: String? {
        switch self {
        case .providerUnavailable(let why): return "Provider unavailable: \(why)"
        case .modelNotConfigured(let why): return "Model not configured: \(why)"
        case .modelLoadFailed(let why): return "Model load failed: \(why)"
        case .generationFailed(let why): return "Generation failed: \(why)"
        }
    }
}
```

If the existing protocol uses a different error mechanism (recorded in RECON.md §1), match that instead — don't add a parallel error type.

- [ ] **Step 2: Add enum case**

In the provider enum file, add:

```swift
case foundationModels
```

Add corresponding `displayName` / `id` / icon entries matching the enum's existing per-case properties.

- [ ] **Step 3: Wire factory (no fatalError)**

Replace the Phase-1 sketch's `fatalError` with a thrown error:

```swift
case .foundationModels:
    if #available(macOS 26.0, *) {
        return FoundationModelsProvider()
    } else {
        throw EnhancementError.providerUnavailable("Foundation Models requires macOS 26+")
    }
```

If the factory's signature doesn't currently `throws` (recorded in RECON.md), this is a small refactor: change the factory and its call sites to `throws`. The cost is bounded — VoiceInk's existing providers presumably have constructors that can fail in similar ways (e.g. missing API key) and the codebase will already have plumbed `throws` through. Verify in RECON.md §1 method signatures.

- [ ] **Step 4: Build**

Expected: clean. If `switch` exhaustiveness errors fire elsewhere, add `.foundationModels` cases (typically just a UI label/icon mapping).

- [ ] **Step 5: Commit**

```bash
git add <files modified>
git commit -m "feat(enhancement): register Foundation Models, no fatalError"
```

---

### Task 1.3: Expose Foundation Models in settings UI

**Files:** Modify the picker view from RECON.md §3.

- [ ] **Step 1: Add picker entry, gated on macOS 26**

```swift
if #available(macOS 26.0, *) {
    Text("Apple Foundation Models").tag(AIProvider.foundationModels)
}
```

(Substitute the enum type name from RECON.md.)

- [ ] **Step 2: Build & run**

`Cmd+R`. Settings → AI Enhancement → confirm "Apple Foundation Models" appears.

- [ ] **Step 3: Commit**

```bash
git add <files modified>
git commit -m "feat(ui): expose Foundation Models in AI Enhancement picker"
```

---

### Task 1.4: Manual smoke test

- [ ] **Step 1: Configure**

In running app: Settings → AI Enhancement → select "Apple Foundation Models".

- [ ] **Step 2: Dictate**

In TextEdit, trigger dictation hotkey, say:

> "hey um can you remind me to like buy milk tomorrow"

- [ ] **Step 3: Verify**

Expected: cleaned-up text inserted. Filler words removed, capitalisation, punctuation present.

- [ ] **Step 4: Verify cancellation (if RECON.md §5 confirmed wrappable Task)**

Trigger dictation, then immediately trigger again before first finishes. Expected: first call cancels (no insertion), second proceeds. If §5 said no cancellation infrastructure exists, skip — gracefulness will be added when host catches up.

- [ ] **Step 5: Verify per-Power-Mode selection**

Set a different Power Mode to a different provider (e.g. Ollama). Switch modes, dictate, confirm provider switches.

- [ ] **Step 6: If smoke fails, fix before proceeding**

Common: `LanguageModelSession` API mismatch — refer to Apple's `FoundationModels` framework docs and adjust call site. Empty response — check session state. Crash on pre-26 — tighten `#available` gating.

- [ ] **Step 7: Commit any fixes**

```bash
git add <files>
git commit -m "fix(foundation-models): <specific issue>"
```

---

## Phase 2 — MLX Dependencies & Skeleton

### Task 2.1: Add SPM packages, pinned to exact commits

**Files:** Modify Xcode project (SPM dependency list).

- [ ] **Step 1: Identify exact commit SHAs to pin**

Open these repos in browser, find the latest stable release tag, copy the commit SHA underneath the tag. Record SHAs in this task before adding to Xcode.

- `mlx-swift` → `https://github.com/ml-explore/mlx-swift/releases` → latest release commit SHA: `<RECORD_HERE>`
- `mlx-swift-examples` → `https://github.com/ml-explore/mlx-swift-examples/releases` (or latest tag) → `<RECORD_HERE>`
- `swift-transformers` → `https://github.com/huggingface/swift-transformers/releases` → `<RECORD_HERE>`

- [ ] **Step 2: Add `mlx-swift`**

Xcode → File → Add Package Dependencies →
- URL: `https://github.com/ml-explore/mlx-swift`
- Dependency Rule: **Exact Version** → use the tagged version, OR **Commit** → paste the SHA from Step 1.
- Targets: VoiceInk app target.
- Products: `MLX`, `MLXNN`, `MLXOptimizers`, `MLXRandom`.

- [ ] **Step 3: Add `mlx-swift-examples`**

Same flow:
- URL: `https://github.com/ml-explore/mlx-swift-examples`
- Pinning: **Exact** or **Commit**.
- Products: `MLXLLM`, `MLXLMCommon`.

- [ ] **Step 4: Add `swift-transformers` for `Hub`**

Same flow:
- URL: `https://github.com/huggingface/swift-transformers`
- Pinning: **Exact** or **Commit**.
- Products: `Hub`.

If `mlx-swift-examples` already vendors `Hub`, you may skip this step — confirm by checking Cmd-click resolution after building.

- [ ] **Step 5: Build (Cmd+B)**

First build is slow (compiles MLX kernels). Allow 5-10 min on M-series.

- [ ] **Step 6: Verify pins**

Open `Package.resolved` (in `<project>.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/`) and confirm all three dependencies are pinned to the exact SHAs from Step 1.

- [ ] **Step 7: Commit**

```bash
git add VoiceInk.xcodeproj '*Package.resolved'
git commit -m "build: add mlx-swift / examples / Hub pinned to exact commits"
```

---

### Task 2.2: Create `MLXProvider.swift` actor skeleton

**Files:** Create `VoiceInk/Services/Enhancement/MLXProvider.swift`.

- [ ] **Step 1: Write the skeleton**

```swift
import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Hub

/// On-device LLM provider using mlx-swift. Loads MLX-quantized HuggingFace
/// models lazily. Idle-evicts after `idleEvictSeconds` to release ~2-4 GB RAM.
/// All state is actor-isolated.
actor MLXProvider: <ProtocolName> {

    private let modelId: String
    private let idleEvictSeconds: TimeInterval

    private var modelContainer: ModelContainer?
    private var lastUsedAt: Date?
    private var evictTask: Task<Void, Never>?

    init(modelId: String, idleEvictSeconds: TimeInterval = 600) {
        self.modelId = modelId
        self.idleEvictSeconds = idleEvictSeconds
    }

    deinit {
        evictTask?.cancel()
    }

    func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
        // Implemented in Task 3.1 (load) + 3.2 (generate) + 3.4 (error fallback).
        throw EnhancementError.generationFailed("Not implemented yet")
    }

    func reset() {
        // Implemented in Task 3.3.
    }
}
```

- [ ] **Step 2: Add to Xcode, build**

Expected: clean (`throw` only hits at runtime).

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Services/Enhancement/MLXProvider.swift VoiceInk.xcodeproj
git commit -m "feat(enhancement): add MLX actor provider skeleton"
```

---

## Phase 3 — MLX Provider Implementation

### Task 3.1: Implement model loading (actor-isolated)

**Files:** Modify `VoiceInk/Services/Enhancement/MLXProvider.swift`.

- [ ] **Step 1: Add `loadModel()` private method**

Inside `MLXProvider`:

```swift
private func loadModel() async throws -> ModelContainer {
    if let existing = modelContainer {
        return existing
    }

    try Task.checkCancellation()

    // Pin Hub cache root to Application Support so macOS won't purge it.
    // Hub respects HF_HOME env var; setting once is enough.
    Self.ensureApplicationSupportCacheRoot()

    let configuration = ModelConfiguration(id: modelId)

    do {
        let loaded = try await LLMModelFactory.shared.loadContainer(
            configuration: configuration
        ) { progress in
            #if DEBUG
            print("[MLX] load \(self.modelId): \(Int(progress.fractionCompleted * 100))%")
            #endif
        }
        try Task.checkCancellation()
        self.modelContainer = loaded
        return loaded
    } catch is CancellationError {
        throw CancellationError()
    } catch {
        throw EnhancementError.modelLoadFailed("\(modelId): \(error.localizedDescription)")
    }
}

/// Set HF_HOME to Application Support so Hub places weights in a non-purgeable
/// location. Idempotent; first call wins.
nonisolated static func ensureApplicationSupportCacheRoot() {
    let env = ProcessInfo.processInfo.environment
    if env["HF_HOME"] != nil { return }

    let appSupport = try? FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask, appropriateFor: nil, create: true
    )
    guard let root = appSupport else { return }
    let bundle = Bundle.main.bundleIdentifier ?? "com.voiceink.fork"
    let target = root
        .appendingPathComponent(bundle, isDirectory: true)
        .appendingPathComponent("MLXModels", isDirectory: true)
    try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    setenv("HF_HOME", target.path, 1)
}
```

> **Note:** `LLMModelFactory.loadContainer` signature varies across `mlx-swift-examples` releases. If build fails, Cmd-click `LLMModelFactory` in Xcode and adjust closure shape. The pin in Task 2.1 should keep this stable, but check on first encounter.

- [ ] **Step 2: Build**

Expected: clean.

- [ ] **Step 3: No commit yet** — Task 3.2 lands the call site, commit together.

---

### Task 3.2: Implement generation with cancellation

**Files:** Modify `VoiceInk/Services/Enhancement/MLXProvider.swift`.

- [ ] **Step 1: Replace `enhance(...)`**

```swift
func enhance(systemPrompt: String, userPrompt: String) async throws -> String {
    guard !modelId.isEmpty else {
        throw EnhancementError.modelNotConfigured(
            "No MLX model selected. Configure in Settings → AI Enhancement → MLX."
        )
    }

    try Task.checkCancellation()
    let container = try await loadModel()
    self.lastUsedAt = Date()
    self.scheduleEvictionCheck()

    do {
        let result = try await container.perform { context in
            try Task.checkCancellation()

            let chat: [Chat.Message] = [
                .system(systemPrompt),
                .user(userPrompt),
            ]
            let input = try await context.processor.prepare(input: .init(messages: chat))

            var output = ""
            _ = try MLXLMCommon.generate(
                input: input,
                parameters: .init(temperature: 0.1, topP: 0.9, maxTokens: 1024),
                context: context
            ) { tokens in
                if Task.isCancelled { return .stop }
                output = context.tokenizer.decode(tokens: tokens)
                return .more
            }
            try Task.checkCancellation()
            return output
        }
        return result
    } catch is CancellationError {
        throw CancellationError()
    } catch {
        throw EnhancementError.generationFailed("\(modelId): \(error.localizedDescription)")
    }
}
```

> **Note:** `Chat.Message` and the generate signature may differ in your installed `MLXLMCommon` version. Cmd-click to verify and adjust to the equivalent shape.

- [ ] **Step 2: Build**

Expected: clean.

- [ ] **Step 3: Commit (Tasks 3.1 + 3.2 together)**

```bash
git add VoiceInk/Services/Enhancement/MLXProvider.swift
git commit -m "feat(enhancement): MLX model load + cancellable generation"
```

---

### Task 3.3: Implement idle eviction (actor-safe)

**Files:** Modify `VoiceInk/Services/Enhancement/MLXProvider.swift`.

- [ ] **Step 1: Add `scheduleEvictionCheck()` and `reset()`**

Inside `MLXProvider`:

```swift
private func scheduleEvictionCheck() {
    evictTask?.cancel()
    let timeout = self.idleEvictSeconds
    evictTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        if Task.isCancelled { return }
        guard let self else { return }
        await self.evictIfIdle()
    }
}

private func evictIfIdle() {
    guard let last = lastUsedAt,
          Date().timeIntervalSince(last) >= idleEvictSeconds else { return }
    modelContainer = nil
    #if DEBUG
    print("[MLX] evicted \(modelId) after idle")
    #endif
}

func reset() {
    evictTask?.cancel()
    evictTask = nil
    modelContainer = nil
    lastUsedAt = nil
}
```

The `await self.evictIfIdle()` inside the eviction `Task` re-enters the actor, so the eviction itself is serialised against any concurrent `enhance(...)` — no race on `modelContainer`.

- [ ] **Step 2: Build**

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Services/Enhancement/MLXProvider.swift
git commit -m "feat(enhancement): MLX idle eviction + reset"
```

---

### Task 3.4: Integration-site error fallback

**Files:** Modify the call site identified in RECON.md §5 (where VoiceInk invokes the selected provider's `enhance(...)`).

- [ ] **Step 1: Wrap the existing `enhance(...)` call in do/catch**

Sketch — adapt to actual call site:

```swift
let enhanced: String
do {
    enhanced = try await provider.enhance(systemPrompt: sys, userPrompt: raw)
} catch is CancellationError {
    return  // user started a new dictation; abandon this output
} catch let EnhancementError.modelNotConfigured(msg) {
    showToast("⚠️ \(msg)")
    enhanced = raw  // passthrough
} catch {
    logger.error("Enhancement failed: \(error.localizedDescription)")
    enhanced = raw  // passthrough
}
insertText(enhanced)
```

If RECON.md §5 showed an existing fallback pattern (e.g. some other provider already passes through on failure), match it. The principle is: **dictation never silently drops text**.

- [ ] **Step 2: Build**

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add <call site file>
git commit -m "feat(enhancement): passthrough fallback on provider failure"
```

---

## Phase 4 — Model Registry & Picker UI

### Task 4.1: Create `MLXModelRegistry.swift`

**Files:** Create `VoiceInk/Services/Enhancement/MLXModelRegistry.swift`.

- [ ] **Step 1: Write the file**

```swift
import Foundation
import Hub

struct MLXModelEntry: Identifiable, Hashable {
    let id: String              // HF repo, e.g. "mlx-community/Qwen2.5-3B-Instruct-4bit"
    let displayName: String
    let approximateSizeGB: Double
    let notes: String
}

enum MLXModelRegistry {
    static let curated: [MLXModelEntry] = [
        .init(
            id: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            displayName: "Qwen 2.5 3B Instruct (4-bit)",
            approximateSizeGB: 2.0,
            notes: "Fast. Good baseline for cleanup tasks."
        ),
        .init(
            id: "mlx-community/Qwen2.5-7B-Instruct-4bit",
            displayName: "Qwen 2.5 7B Instruct (4-bit)",
            approximateSizeGB: 4.5,
            notes: "Better quality. Recommended on 16 GB+ Macs."
        ),
        .init(
            id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            displayName: "Llama 3.2 3B Instruct (4-bit)",
            approximateSizeGB: 2.0,
            notes: "Alt to Qwen 3B."
        ),
        .init(
            id: "mlx-community/Mistral-7B-Instruct-v0.3-4bit",
            displayName: "Mistral 7B Instruct v0.3 (4-bit)",
            approximateSizeGB: 4.2,
            notes: "Alt to Qwen 7B."
        ),
    ]
}

enum MLXModelStatus: Equatable {
    case notDownloaded
    case downloading(fraction: Double)
    case downloaded
    case failed(String)
}

enum MLXModelDownloader {
    /// Pinned root: Application Support, not Caches. Set up by
    /// MLXProvider.ensureApplicationSupportCacheRoot() at first call.
    private static func cacheRoot() -> URL {
        MLXProvider.ensureApplicationSupportCacheRoot()
        let env = ProcessInfo.processInfo.environment["HF_HOME"]
        return URL(fileURLWithPath: env ?? NSHomeDirectory())
    }

    static func status(for repoId: String) -> MLXModelStatus {
        let dir = repoDir(for: repoId)
        let weights = dir.appendingPathComponent("model.safetensors")
        return FileManager.default.fileExists(atPath: weights.path)
            ? .downloaded
            : .notDownloaded
    }

    static func download(
        _ repoId: String,
        approximateSizeGB: Double,
        progress: @escaping (Double) -> Void
    ) async throws {
        try preflightDiskSpace(needGB: approximateSizeGB + 1.0)

        let repo = Hub.Repo(id: repoId, type: .model)
        let hub = HubApi()
        _ = try await hub.snapshot(from: repo) { info in
            progress(info.fractionCompleted)
        }
    }

    static func delete(_ repoId: String) throws {
        let dir = repoDir(for: repoId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    /// Throws if free space < required.
    private static func preflightDiskSpace(needGB: Double) throws {
        let url = cacheRoot()
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = Double(values?.volumeAvailableCapacityForImportantUsage ?? 0) / 1_073_741_824.0  // GB
        guard free >= needGB else {
            throw EnhancementError.modelLoadFailed(
                "Need ~\(String(format: "%.1f", needGB)) GB free; \(String(format: "%.1f", free)) GB available."
            )
        }
    }

    private static func repoDir(for repoId: String) -> URL {
        // HF cache layout: <cacheRoot>/models/<org>/<name>/
        // The exact layout depends on Hub version; Cmd-click HubApi to verify.
        let parts = repoId.split(separator: "/")
        return cacheRoot()
            .appendingPathComponent("models")
            .appendingPathComponent(parts.dropLast().joined(separator: "/"))
            .appendingPathComponent(String(parts.last ?? ""))
    }
}
```

> **Note:** `Hub.Repo` and `HubApi.snapshot` API names vary between `swift-transformers` releases. The exact pin from Task 2.1 keeps this stable. If signature drift appears, Cmd-click and adapt.

- [ ] **Step 2: Add to Xcode, build**

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Services/Enhancement/MLXModelRegistry.swift VoiceInk.xcodeproj
git commit -m "feat(enhancement): MLX registry + downloader with disk pre-flight"
```

---

### Task 4.2: Create `MLXModelPickerView.swift`

**Files:** Create `VoiceInk/Views/Settings/MLXModelPickerView.swift`.

- [ ] **Step 1: Write the view**

```swift
import SwiftUI

struct MLXModelPickerView: View {
    @AppStorage("mlx_selected_model_id") private var selectedModelId: String = ""

    @State private var statuses: [String: MLXModelStatus] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MLX Model").font(.headline)

            ForEach(MLXModelRegistry.curated) { model in
                modelRow(model)
            }
        }
        .task { refreshAllStatuses() }
    }

    @ViewBuilder
    private func modelRow(_ model: MLXModelEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName).font(.body)
                Text("\(String(format: "%.1f", model.approximateSizeGB)) GB · \(model.notes)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            statusControl(for: model)
            Toggle("", isOn: Binding(
                get: { selectedModelId == model.id },
                set: { if $0 { selectedModelId = model.id } }
            ))
            .toggleStyle(.checkbox)
            .disabled(statuses[model.id] != .downloaded)
        }
    }

    @ViewBuilder
    private func statusControl(for model: MLXModelEntry) -> some View {
        switch statuses[model.id] ?? .notDownloaded {
        case .notDownloaded:
            Button("Download") { Task { await download(model) } }
        case .downloading(let f):
            ProgressView(value: f).frame(width: 80)
        case .downloaded:
            Button("Delete") { delete(model) }
                .buttonStyle(.borderless)
        case .failed(let msg):
            Text("Failed: \(msg)").foregroundStyle(.red).font(.caption)
        }
    }

    private func refreshAllStatuses() {
        for model in MLXModelRegistry.curated {
            statuses[model.id] = MLXModelDownloader.status(for: model.id)
        }
    }

    private func download(_ model: MLXModelEntry) async {
        statuses[model.id] = .downloading(fraction: 0)
        do {
            try await MLXModelDownloader.download(
                model.id,
                approximateSizeGB: model.approximateSizeGB
            ) { fraction in
                Task { @MainActor in
                    statuses[model.id] = .downloading(fraction: fraction)
                }
            }
            statuses[model.id] = .downloaded
        } catch {
            statuses[model.id] = .failed(error.localizedDescription)
        }
    }

    private func delete(_ model: MLXModelEntry) {
        do {
            try MLXModelDownloader.delete(model.id)
            statuses[model.id] = .notDownloaded
            if selectedModelId == model.id { selectedModelId = "" }
        } catch {
            statuses[model.id] = .failed(error.localizedDescription)
        }
    }
}
```

- [ ] **Step 2: Add to Xcode, build**

Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Views/Settings/MLXModelPickerView.swift VoiceInk.xcodeproj
git commit -m "feat(ui): MLX model picker with download/delete"
```

---

### Task 4.3: Wire MLXProvider into factory

**Files:** Modify provider factory (RECON.md §1).

- [ ] **Step 1: Add `.mlx` enum case**

In the provider enum: `case mlx` + corresponding displayName (`"MLX (local, on-device)"`) + id (`"mlx"`). Update non-exhaustive switches.

- [ ] **Step 2: Wire factory**

Hardcoded 10-min idle eviction (UI knob deferred per scope cut):

```swift
case .mlx:
    let modelId = UserDefaults.standard.string(forKey: "mlx_selected_model_id") ?? ""
    return MLXProvider(modelId: modelId, idleEvictSeconds: 600)
```

The empty-`modelId` case is handled inside `MLXProvider.enhance(...)` (Task 3.2 throws `.modelNotConfigured`).

- [ ] **Step 3: Build**

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add <files>
git commit -m "feat(enhancement): wire MLX provider via UserDefaults model id"
```

---

### Task 4.4: Hook `MLXModelPickerView` into Settings UI

**Files:** Modify AI Enhancement settings view (RECON.md §3).

- [ ] **Step 1: Add picker option + conditional sub-view**

```swift
Text("MLX (local, on-device)").tag(AIProvider.mlx)
```

Wherever existing per-provider config UI lives (e.g. OpenAI API-key field shown only when OpenAI is selected):

```swift
if selectedProvider == .mlx {
    MLXModelPickerView()
}
```

- [ ] **Step 2: Build & run**

`Cmd+R`. Settings → AI Enhancement → select "MLX". Confirm picker appears with all 4 curated models in `.notDownloaded`.

- [ ] **Step 3: Manual download test**

Download Qwen 2.5 3B Instruct. Confirm progress UI, final `.downloaded`. Tick the checkbox.

- [ ] **Step 4: Manual disk-space pre-flight test**

Synthetic test: temporarily set the model's `approximateSizeGB` in `MLXModelRegistry.curated` to an absurd value (e.g. 9999.0), trigger download. Expected: immediate `.failed` with disk-space message. Revert the change before commit.

- [ ] **Step 5: End-to-end smoke**

Dictate a sentence. Confirm:
- First request: ~5-30s (model load).
- Subsequent: ~1-2s.
- Output sensibly cleaned.
- If download not done, `.failed` toast / passthrough — original transcript inserted (not silently dropped).

- [ ] **Step 6: Idle-evict smoke**

Wait 11 minutes idle (or temporarily set `idleEvictSeconds: 30` in factory for the test, then revert). Dictate again. Expected: model reloads (~5-15s), output produced.

- [ ] **Step 7: Cancellation smoke (if RECON §5 supports it)**

Dictate, immediately re-trigger. Expected: first generation cancelled, no insertion of stale output; second proceeds.

- [ ] **Step 8: Commit**

```bash
git add <files>
git commit -m "feat(ui): MLX picker integrated into AI Enhancement settings"
```

---

## Phase 5 — Documentation

### Task 5.1: Write `FORK.md`

**Files:** Create `FORK.md` at fork repo root.

- [ ] **Step 1: Write the file**

```markdown
# Fork Notes

## Base
- Upstream: https://github.com/Beingpax/VoiceInk
- Pinned to tag: **v1.74** (April 22, 2026)
- Work branch: `priyanshu/embedded-llm`

## What this fork adds
- `FoundationModelsProvider` (actor) — Apple Foundation Models, macOS 26+
- `MLXProvider` (actor) — on-device LLM via mlx-swift, curated 4-model picker
- Disk-space pre-flight, Application Support model storage, idle eviction (10 min hardcoded)
- Persistence keys: `mlx_selected_model_id`
- macOS deployment target raised to 26.0 (required by FoundationModels)

## What this fork does NOT add
- Real-time meeting transcription (deferred — see spec)
- Custom HF repo input field (deferred; edit `MLXModelRegistry.curated` to add models)
- Idle-evict timeout UI (hardcoded 10 min; change `idleEvictSeconds:` in factory if needed)
- Public distribution

## Pinned dependencies (exact commits)
- `mlx-swift`: <SHA>
- `mlx-swift-examples`: <SHA>
- `swift-transformers`: <SHA>

Check `Package.resolved` for the source of truth.

## Build
- Xcode 16+
- macOS 26 deployment target
- Personal Apple ID signing
- `Cmd+R` in Xcode

## Pulling upstream changes
```bash
git fetch upstream
git log v1.74..upstream/main -- <path>
git cherry-pick <commit-sha>     # preferred
# OR
git rebase upstream/main          # riskier
```

Document each pull below.

### Upstream pulls
_(none yet)_

## License
- VoiceInk upstream is GPL-3. This fork inherits GPL-3.
- **Do not distribute** (private-use only). Distribution triggers GPL-3 source-availability obligation — separate decision.
```

- [ ] **Step 2: Commit**

```bash
git add FORK.md
git commit -m "docs: fork management notes"
```

---

### Task 5.2: Final smoke checklist

Run every item. Each must pass before declaring done.

- [ ] Foundation Models provider visible in settings (only on macOS 26).
- [ ] Foundation Models dictation produces cleaned-up text.
- [ ] MLX provider visible in settings.
- [ ] MLX model picker shows 4 curated models with sizes.
- [ ] Disk-space pre-flight rejects oversized download attempts.
- [ ] Download fetches a curated model; progress UI updates; final `.downloaded`.
- [ ] Selected MLX model is used for dictation; first-call ~5-30s, then ~1-2s.
- [ ] Generation passthrough on provider failure: dictation never silently drops.
- [ ] Cancellation: starting a new dictation cancels the in-flight one (if RECON §5 supports it; otherwise documented gap).
- [ ] Idle eviction: after 10 min, model is unloaded; next call reloads.
- [ ] Switching MLX → Foundation Models → OpenRouter works without restart.
- [ ] Per-Power-Mode provider selection still works (regression check).
- [ ] App quit + relaunch: provider selection and downloaded models persist.

- [ ] **Final commit (if any fixes during smoke):**

```bash
git add <files>
git commit -m "fix: <issue from smoke checklist>"
```

---

## Self-Review

**Spec coverage:**

| Spec section | Plan task(s) |
|---|---|
| Decision: fork VoiceInk + 2 providers | Phases 0-4 |
| Foundation Models provider | Tasks 1.1, 1.2, 1.3, 1.4 |
| mlx-swift provider | Tasks 2.1, 2.2, 3.1, 3.2, 3.3 |
| Curated model registry (Qwen 3B/7B, Llama 3.2 3B, Mistral 7B) | Task 4.1 |
| Custom HF repo field | **Cut from v1** (codex scope-creep concession) |
| First-time UX: no auto-download | Task 4.2 (Toggle disabled until `.downloaded`) + Task 3.2 guard |
| Settings UI: per-Power-Mode toggle | Task 4.4 (matches existing VoiceInk picker pattern) |
| macOS 26 gate (Foundation Models) | Task 1.1 (`@available`) + Task 1.2 (factory throws, no fatalError) + Task 1.3 (`#available` UI) |
| Idle eviction default 10 min | Task 3.3 + Task 4.3 (hardcoded; UI knob cut) |
| Storage in Application Support | Task 3.1 (`ensureApplicationSupportCacheRoot`) + Task 4.1 (downloader uses same root) |
| Pin to v1.74 | Task 0.1 |
| Private fork | Task 0.1 (Option B / private remote) |
| FORK.md with rebase procedure | Task 5.1 |
| Manual smoke testing | Tasks 1.4, 4.4, 5.2 |
| **Codex: actor isolation** | Tasks 1.1, 2.2, 3.x — both providers are actors |
| **Codex: cancellation contract** | Task 0.3 §5 RECON, Task 3.2 (`Task.checkCancellation` + cancel-aware generate callback), Task 3.4 (call-site catch) |
| **Codex: no fatalError** | Task 1.2 (`EnhancementError.providerUnavailable`) |
| **Codex: passthrough fallback** | Task 3.4 |
| **Codex: pinned SPM deps** | Task 2.1 (exact-version / commit pinning) |
| **Codex: disk-space pre-flight** | Task 4.1 (`preflightDiskSpace`) |
| **Codex: explicit storage path** | Task 3.1 (`HF_HOME` → Application Support) |

**Placeholder scan:** No `TBD`/`TODO`/"implement later" markers. Recon-driven specifics (exact protocol/enum names, file paths, picker code site) are gated behind Task 0.3 producing `RECON.md`, which all later tasks reference. SPM commit SHAs are explicit `<RECORD_HERE>` placeholders that the engineer fills in Task 2.1 Step 1 — that's a deliberate live data capture, not a plan placeholder.

**Type consistency:** `FoundationModelsProvider`, `MLXProvider`, `MLXModelEntry`, `MLXModelRegistry`, `MLXModelStatus`, `MLXModelDownloader`, `MLXModelPickerView`, `EnhancementError` used consistently. UserDefaults key `mlx_selected_model_id` referenced consistently. `idleEvictSeconds` constant of 600 used in both factory wiring and skeleton default.

**Known plan limitations (acceptable):**
1. Exact code for the small "register provider in enum / wire factory / wire UI picker" edits is descriptive rather than prescriptive, because the integration site lives in upstream code that hasn't been read yet. Phase 0 produces RECON.md which fills this in. Prescribing exact line numbers for unread code would be a fabricated placeholder.
2. mlx-swift / Hub API usage may need minor tweaks against the actual installed package version; pinned SHAs in Task 2.1 minimise drift, and code-site notes flag the likely tweak points.
3. If RECON.md §5 reveals VoiceInk has no per-call cancellation infrastructure, Task 3.4's cancellation contract is honoured by the providers but not exercised by the host. That's documented as a known gap to be closed by upstream or a follow-up commit, not a blocker for v1.

---

**Plan complete and saved to `docs/superpowers/plans/2026-04-27-voiceink-fork-embedded-llm.md`.**

**Two execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch with checkpoints.

**Which approach?**
