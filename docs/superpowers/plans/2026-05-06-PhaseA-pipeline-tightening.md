# Phase A — Pipeline Tightening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land Phase A from the design spec — cut Qwen3-4B timeout rate <2%, plug unified-log prompt leak, surface failures, bound context blocks.

**Spec:** `docs/superpowers/specs/2026-05-06-pipeline-tightening-design.md` (codex-approved GREEN). This plan does not restate the spec — read the spec for problem framing, success gates, rollback policy, and migration policy.

**Architecture:** Five tracks, each one commit on the same feature branch. Order T3 → T4 → T2 → T1 → T5. T1 and T5 are separate commits validated jointly. Cherry-pick hashes verified against `upstream/main` (codex pass 2). UserDefault kill-switches gate behavioral tracks (T1, T4, T5) for runtime rollback without code reverts.

**Tech Stack:** Swift / SwiftUI / SwiftData on macOS 13+. MLX-Swift for the Qwen3-4B-Instruct-2507-4bit-DWQ-2510 cleanup model. Foundation for UserDefaults. UserNotifications for the failure toast.

---

## Task 0: Branch + baseline capture

**Files:**
- None modified yet — environment prep.

- [ ] **Step 1: Confirm clean working tree**

```bash
git status --short
```

Expected: shows only untracked `W14*` planning markdown and the new `docs/superpowers/specs/*.md` and `docs/superpowers/plans/*.md`. No staged or unstaged changes to source files.

If anything else is modified, stop and resolve before continuing.

- [ ] **Step 2: Create feature branch**

```bash
git checkout -b phaseA-pipeline-tightening
```

Expected: branch created from current `main` HEAD (`b79ee67` "chore(build): land local builds in /Applications instead of ~/Downloads").

- [ ] **Step 3: Capture pre-Phase-A baseline**

```bash
git rev-parse HEAD > /tmp/phaseA_baseline_sha.txt
cp ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv /tmp/phaseA_baseline_timings.csv
wc -l /tmp/phaseA_baseline_timings.csv
```

Expected: SHA matches the `b79ee67` HEAD; CSV has at least the 30+ lines visible in earlier inspection. Keep these files — success gates compare against this snapshot.

- [ ] **Step 4: Confirm cherry-pick hashes resolve in upstream**

```bash
for h in 94be2ff cfc6a87 46c5ed7 34a7f5e 05cc14a 13240f3; do
  git log -1 --format="%h %s" "$h"
done
```

Expected: all six commits print one-line summaries matching what the spec describes. If any fails to resolve, stop — re-fetch upstream.

- [ ] **Step 5: No commit yet** — environment prep only.

---

## Task 1 (T3): Cherry-pick `94be2ff` — remove unified-log prompt broadcast

**STATUS: VERIFIED NO-OP (2026-05-06).** Pre-execution grep showed every line `94be2ff` deletes is already absent from our tree — the W11/W14 logging refactor already removed them. AIEnhancementService now uses `🦾 enhance: level=…` (count-only); OllamaService migrated to `LLMkit.OllamaClient` (debug prints absent). All remaining logger calls log only counts, never content. Skip the cherry-pick; record this no-op in the readout. Steps below preserved for audit but should not be re-executed.

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` (remove 4 lines of `logger.notice` broadcasts in `makeRequest`)
- Modify: `VoiceInk/Services/OllamaService.swift` (remove 6 lines)

- [x] **Step 1: Cherry-pick verbatim** ~~superseded by no-op finding~~

```bash
git cherry-pick 94be2ff
```

Expected outcomes:
- **Clean apply:** commit lands as-is. Skip to Step 3.
- **Context conflict only** (likely — our W11/W14 work added log lines near the deletion target): conflict markers appear in `AIEnhancementService.swift`. Resolve by accepting the upstream deletion (the four lines starting with `// Log the message being sent to AI enhancement` and the two `logger.notice(...)` lines that follow). Keep our surrounding W11/W14 logging.

- [ ] **Step 2: Resolve conflict if it appears**

If conflict markers appear:

```bash
# Inspect what's in conflict
git diff --check
# Open the file, delete:
#   - the comment line "// Log the message being sent to AI enhancement"
#   - the two logger.notice lines that broadcast systemMessage and formattedText
# Keep our 🦾 enhance breadcrumbs (level=…) intact.
git add VoiceInk/Services/AIEnhancement/AIEnhancementService.swift
# Repeat for OllamaService.swift if it also conflicts (less likely — we haven't modified it).
git cherry-pick --continue
```

- [ ] **Step 3: Verify the broadcasts are gone**

```bash
grep -n "AI Enhancement - System Message\|AI Enhancement - User Message" VoiceInk/Services/AIEnhancement/AIEnhancementService.swift VoiceInk/Services/OllamaService.swift
```

Expected: no matches. If matches remain, the cherry-pick didn't fully apply — investigate.

- [ ] **Step 4: Build clean**

```bash
xcodebuild -scheme VoiceInk -configuration Debug build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **` in the output. Any error means the cherry-pick removed something a later W11/W14 commit depended on — read the error, fix the call site (most likely just deleting the orphaned reference), do not stage and amend.

- [ ] **Step 5: Smoke-test**

Launch from `/Applications/VoiceInk.app`. Record one short ("hello world") and one long (>120c) phrase. Confirm both paste correctly to TextEdit.

- [ ] **Step 6: Verify the unified-log no longer carries prompts**

```bash
/usr/bin/log show --predicate 'subsystem == "com.prakashjoshipax.voiceink" AND eventMessage CONTAINS "AI Enhancement - System Message"' --info --last 5m
```

Expected: zero matches. If any appear, the cherry-pick or build is stale — re-launch the rebuilt app.

- [ ] **Step 7: No additional commit** — `git cherry-pick` already committed. Verify with `git log -1 --oneline`.

---

## Task 2 (T4a): Cherry-pick `cfc6a87` — failure notification + add kill-switch

**Files:**
- Modify (via cherry-pick): `VoiceInk/Whisper/TranscriptionPipeline.swift`
- Modify (kill-switch wrap): same file
- Modify: `VoiceInk/AppDefaults.swift` (register `EnableEnhancementFailureNotification` default `true`)

- [ ] **Step 1: Cherry-pick verbatim**

```bash
git cherry-pick cfc6a87
```

The upstream commit adds 6 lines to `TranscriptionPipeline.swift`. Note: upstream's path is `VoiceInk/Whisper/TranscriptionPipeline.swift`, but our repo has it at `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` (W11+ refactor). Cherry-pick will fail with "file not found" or "deleted by us".

- [ ] **Step 2: Resolve path renaming**

```bash
git status
# Expected: TranscriptionPipeline.swift listed under "deleted by us" or similar.
```

Get the upstream patch and apply it manually to our path:

```bash
git show cfc6a87 -- VoiceInk/Whisper/TranscriptionPipeline.swift
```

Read the diff. The upstream addition is a `NSUserNotification` call inside an enhancement-error catch block. Locate the equivalent catch block in `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` and add the same notification post.

```bash
# Abort the failed cherry-pick:
git cherry-pick --abort
```

- [ ] **Step 3: Locate the enhancement-error site in our pipeline**

```bash
grep -n "enhance\|EnhancementError" VoiceInk/Transcription/Engine/TranscriptionPipeline.swift | head -20
```

Read the catch block where enhancement failures are surfaced today (likely a `do { try await enhance… } catch { logger.error(…) }` pattern).

- [ ] **Step 4: Add the kill-switch + notification**

Edit `VoiceInk/AppDefaults.swift` to add the new default. Find the existing dictionary registration (around line 46 where `EnhancementTimeoutSeconds: 7` lives):

```swift
"EnableEnhancementFailureNotification": true,
```

Add it as a new key in the `register(defaults:)` dict.

In `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`, inside the enhancement catch block, add (adapt to the existing variable names — `enhancementError`, `error`, etc.):

```swift
if UserDefaults.standard.bool(forKey: "EnableEnhancementFailureNotification") {
    let center = UNUserNotificationCenter.current()
    let content = UNMutableNotificationContent()
    content.title = "Enhancement Failed"
    content.body = error.localizedDescription
    content.sound = .default
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
    center.add(request) { _ in }
}
```

Note: if upstream's commit uses the deprecated `NSUserNotification` API, prefer `UNUserNotificationCenter` (the supported API; `NSUserNotification` is deprecated since macOS 11). If our app already imports `UserNotifications` and posts elsewhere, mirror that pattern instead.

- [ ] **Step 5: Build clean**

```bash
xcodebuild -scheme VoiceInk -configuration Debug build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Trigger a failure to verify**

```bash
defaults write com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds 1
```

Launch the rebuilt app. Record a short phrase. Expected: enhancement times out fast (because budget=1s), notification appears.

```bash
defaults delete com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds
```

(deletes our test override so we go back to whatever the spec says is the new default once T1 lands — `15`).

- [ ] **Step 7: Verify kill-switch works**

```bash
defaults write com.prakashjoshipax.VoiceInk EnableEnhancementFailureNotification 0
defaults write com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds 1
```

Re-launch, force another timeout. Expected: NO notification.

```bash
defaults delete com.prakashjoshipax.VoiceInk EnableEnhancementFailureNotification
defaults delete com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds
```

- [ ] **Step 8: Commit**

```bash
git add VoiceInk/AppDefaults.swift VoiceInk/Transcription/Engine/TranscriptionPipeline.swift
git commit -m "$(cat <<'EOF'
phaseA(T4): surface enhancement failures via UNUserNotification

Cherry-pick of upstream cfc6a87 adapted to our W11+ TranscriptionPipeline path.
Gated by EnableEnhancementFailureNotification UserDefault, default true. Off
flips the toast off without a code revert (per Phase A rollback policy).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3 (T4b): Cherry-pick clipboard restore stack `46c5ed7`, `34a7f5e`, `05cc14a`

**Files (touched by all three cherry-picks):**
- `VoiceInk/CursorPaster.swift`
- `VoiceInk/Views/Settings/SettingsView.swift`

- [ ] **Step 1: Inspect the three commits as a chain**

```bash
git log --oneline 05cc14a^..46c5ed7 -- VoiceInk/CursorPaster.swift VoiceInk/Views/Settings/SettingsView.swift
```

Expected: three commits in chronological order: `05cc14a` (Jan 12) → `34a7f5e` (Feb 2) → `46c5ed7` (Feb 7). They build on each other; cherry-pick in chronological order.

- [ ] **Step 2: Cherry-pick the oldest first**

```bash
git cherry-pick 05cc14a
```

If conflicts: this commit "Enable clipboard restoration by default with 1 second delay" — accept upstream's defaults. Resolve any context conflicts in our favor only when our W11/W14 work changed nearby behavior; otherwise take upstream verbatim.

- [ ] **Step 3: Build + smoke**

```bash
xcodebuild -scheme VoiceInk -configuration Debug build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED. Smoke: copy something, dictate, confirm clipboard contents are restored after paste (within ~1s default delay).

- [ ] **Step 4: Cherry-pick `34a7f5e`**

```bash
git cherry-pick 34a7f5e
```

This is "Fix missing clipboard restore delay fallback guard" — small fix, should apply cleanly.

- [ ] **Step 5: Cherry-pick `46c5ed7`**

```bash
git cherry-pick 46c5ed7
```

This adds sub-second delay support. Apply, build, smoke.

- [ ] **Step 6: Verify the upstream toggle survives**

```bash
grep -n "isClipboardRestoreEnabled\|ClipboardRestoreEnabled\|clipboardRestoreEnabled" VoiceInk -r --include="*.swift"
```

Expected: at least one match — that's the upstream-provided UserDefault key. Note its exact name; the spec's rollback table assumes one exists. If the cherry-pick brought a UserDefault that toggles the entire clipboard-restore behavior, the spec's `EnableClipboardRestore` row points at it (no new wrapper needed). Document the exact key name in the next commit message.

- [ ] **Step 7: Verify default-on behavior**

```bash
defaults read com.prakashjoshipax.VoiceInk | grep -i clipboard
```

Expected: shows the upstream-introduced clipboard-related defaults.

- [ ] **Step 8: No additional commit beyond the three cherry-picks** — already committed.

---

## Task 4 (T4c): Cherry-pick `13240f3` — default new Power Mode to current transcription model

**Files:**
- Modify (via cherry-pick): `VoiceInk/PowerMode/PowerModeConfigView.swift`

- [ ] **Step 1: Cherry-pick**

```bash
git cherry-pick 13240f3
```

Three-line change. Upstream changes how new Power Mode entries are seeded — they now inherit the user's current global transcription model instead of being blank.

If conflict (our W14 Power Mode work may overlap): resolve by taking upstream's intent — newly created Power Mode configs read `UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")` for `selectedTranscriptionModelName`.

- [ ] **Step 2: Build**

```bash
xcodebuild -scheme VoiceInk -configuration Debug build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Smoke-test creation**

In the running app, create a new Power Mode config. Expected: `selectedTranscriptionModelName` is pre-filled with the current global transcription model (whichever Whisper variant is currently selected app-wide), not blank.

- [ ] **Step 4: No additional commit** — already committed.

---

## Task 5 (T2): Hide LFM2.5-1.2B from curated MLX lineup

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift` (line ~216 — the LFM2.5-1.2B-Instruct-4bit entry)

- [ ] **Step 1: Read the current registry to find the LFM2.5 entry**

```bash
grep -n -A 10 "LFM2.5-1.2B-Instruct-4bit" VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift
```

Expected: shows an entry around line 216 with `id: "mlx-community/LFM2.5-1.2B-Instruct-4bit"` and surrounding fields (likely `displayName`, `tier`, etc.).

- [ ] **Step 2: Determine the registry's separation between "user-visible curated" and "downloadable"**

Read the registry file in full to understand the data model:

Read `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift` from line 1 (the comment block at line 96 mentions the curated lineup philosophy).

Two possibilities the design must adapt to:

- **(a) Single list with a flag** (e.g., `isCurated: Bool` or similar) — flip LFM2.5's flag to `false`; keep the entry so it's still loadable via custom-model paths.
- **(b) Two arrays** (curated + extras) — move the LFM2.5 entry from the curated array to the extras array.
- **(c) Just one array, no separation** — add a new `isUserVisible: Bool` field (default `true`), set LFM2.5's to `false`. Filter the Settings UI by this field.

Pick the smallest patch matching the existing structure. Confirm with the surrounding code's data model.

- [ ] **Step 3: Apply the chosen change**

Whichever variant fits: the entry must remain loadable (T1 fallback uses it) but absent from the user-facing curated list shown in Settings → AI → Model picker.

- [ ] **Step 4: Verify a user with LFM2.5 selected is not auto-deselected**

Read whatever code resolves "user's selected MLX model" (likely in `MLXProvider.swift` or `AIService.swift`). Confirm it tolerates a selected model not in the curated list — already the case per spec migration policy #3 ("customMLXModels mechanics").

- [ ] **Step 5: Build**

```bash
xcodebuild -scheme VoiceInk -configuration Debug build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Smoke-test the Settings UI**

Launch the app, open Settings → wherever the curated MLX picker lives. Confirm LFM2.5-1.2B no longer appears in the curated picks. Confirm Qwen3-4B is still selectable. Confirm no crash.

- [ ] **Step 7: Verify LFM2.5 still loads programmatically**

In the running app, briefly switch to LFM2.5 via custom-model path or whatever mechanism Step 4 identified. Confirm it loads. Switch back to Qwen3-4B.

- [ ] **Step 8: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift
git commit -m "$(cat <<'EOF'
phaseA(T2): hide LFM2.5-1.2B from user-visible curated MLX lineup

Cleanup quality is poor on questiony / long dictations vs Qwen3-4B-Instruct-2507.
Entry remains loadable so T1's MLX timeout fallback chain can use it; just stops
being offered as a default-quality option to new users. Existing users who
selected LFM2.5 keep their selection per spec migration policy #3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6 (T1): Timeout bump 7→15s + MLX fallback chain

**Files:**
- Modify: `VoiceInk/AppDefaults.swift` (change `EnhancementTimeoutSeconds: 7` → `15`, add `EnableMLXFallback: true`)
- Modify: `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` (`@AppStorage` default `7` → `15`)
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` (`baseTimeout` fallback `? 7` → `? 15`)
- Modify: `VoiceInk/Services/AIEnhancement/MLXProvider.swift` (`storedTimeout > 0 ? … : 7` → `: 15`; surface fallback hook)
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` (`makeRequest` MLX branch — add fallback retry on timeout)

- [ ] **Step 1: Update the three default-7 sites**

```bash
grep -n "\\b7\\b" VoiceInk/AppDefaults.swift VoiceInk/Views/Components/EnhancementSettingsPanel.swift VoiceInk/Services/AIEnhancement/AIEnhancementService.swift VoiceInk/Services/AIEnhancement/MLXProvider.swift | grep -i timeout
```

Expected: shows the four sites currently using `7` as the default. Update each to `15`.

```swift
// VoiceInk/AppDefaults.swift line 46
"EnhancementTimeoutSeconds": 15,

// VoiceInk/Views/Components/EnhancementSettingsPanel.swift line 8
@AppStorage("EnhancementTimeoutSeconds") private var enhancementTimeoutSeconds = 15

// VoiceInk/Services/AIEnhancement/AIEnhancementService.swift baseTimeout
return stored > 0 ? TimeInterval(stored) : 15

// VoiceInk/Services/AIEnhancement/MLXProvider.swift line ~138
let effectiveTimeout = storedTimeout > 0 ? TimeInterval(storedTimeout) : 15
```

(adjust to actual surrounding code — the variable names and exact lines may differ slightly from the line numbers above).

- [ ] **Step 2: Register `EnableMLXFallback` default**

Add to `VoiceInk/AppDefaults.swift` register dict (next to `EnableEnhancementFailureNotification` from Task 2):

```swift
"EnableMLXFallback": true,
```

- [ ] **Step 3: Add the MLX fallback retry path**

In `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`, locate the MLX branch in `makeRequest(text:mode:)` (around line 294 per current state — the `if aiService.selectedProvider == .mlx { ... }` block, which catches `MLXProvider.ProviderError`).

Wrap the existing MLX call so that on timeout error specifically, we attempt one retry with the LFM2.5-1.2B model. Pseudocode:

```swift
// Inside the existing .mlx branch, in the catch that maps MLXProvider.ProviderError:
if case .timeout = providerError, UserDefaults.standard.bool(forKey: "EnableMLXFallback") {
    let fallbackModelId = "mlx-community/LFM2.5-1.2B-Instruct-4bit"
    if MLXProvider.isModelDownloaded(id: fallbackModelId) {  // implement or wire to existing equivalent
        logger.notice("🦾 mlx fallback: timeout on \(self.aiService.currentModel, privacy: .public), retrying with \(fallbackModelId, privacy: .public)")
        do {
            let fallbackResult = try await aiService.enhanceWithMLX(
                systemPrompt: mlxSystemMessage,
                userPrompt: mlxUserPrompt,
                promptMode: mlxPromptMode,
                modelOverride: fallbackModelId  // plumb this through MLXProvider if needed
            )
            return AIEnhancementOutputFilter.filter(stripPreamble(fallbackResult))
        } catch {
            // Fall through to original error surfacing.
        }
    }
}
throw EnhancementError.customError(providerError.errorDescription ?? "An unknown MLX error occurred.")
```

Three concrete pieces this requires:

1. A predicate `MLXProvider.isModelDownloaded(id:)` (or equivalent — find the existing local-model presence check; the registry has download-status tracking).
2. An optional `modelOverride: String?` parameter on `aiService.enhanceWithMLX(...)` that swaps the model for this single call without changing user state. If MLXProvider doesn't already support this, add it — should just route to a `loadModel(id:)` path that already exists for the prewarm flow.
3. Make the fallback **single-shot**: do NOT recurse, do NOT loop. If the fallback also fails, surface the *original* error, not the fallback's.

- [ ] **Step 4: Build**

```bash
xcodebuild -scheme VoiceInk -configuration Debug build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Smoke — happy path**

Launch the app. Record a normal phrase. Confirm Qwen3-4B handles it within new 15s budget, no fallback fires, paste works.

- [ ] **Step 6: Smoke — fallback path**

```bash
defaults write com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds 1
```

(force a sub-second budget to provoke timeout). Re-launch the app. Record a phrase. Expected:

- Qwen3-4B times out (visible in unified log: `🦾 enhance: timeout fired after 1.0s (EnhancementTimeoutSeconds)`).
- Fallback retry fires (visible: `🦾 mlx fallback: timeout on … retrying with mlx-community/LFM2.5-1.2B-Instruct-4bit`).
- LFM2.5 produces output, which pastes successfully.

```bash
defaults delete com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds
```

- [ ] **Step 7: Smoke — kill-switch**

```bash
defaults write com.prakashjoshipax.VoiceInk EnableMLXFallback 0
defaults write com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds 1
```

Re-launch, record. Expected: Qwen3-4B times out, NO fallback, failure notification (from Task 2) surfaces.

```bash
defaults delete com.prakashjoshipax.VoiceInk EnableMLXFallback
defaults delete com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds
```

- [ ] **Step 8: Smoke — fallback-failed path**

Temporarily move LFM2.5 out of the way (or pick a fallback-test approach that simulates "model not downloaded"). Force timeout. Expected: original timeout error surfaces, notification fires, no crash. Restore LFM2.5 after.

- [ ] **Step 9: Commit**

```bash
git add VoiceInk/AppDefaults.swift VoiceInk/Views/Components/EnhancementSettingsPanel.swift VoiceInk/Services/AIEnhancement/AIEnhancementService.swift VoiceInk/Services/AIEnhancement/MLXProvider.swift
git commit -m "$(cat <<'EOF'
phaseA(T1): bump enhance timeout 7→15s, add MLX fallback chain

Default budget 7s was producing 11% timeouts on Qwen3-4B-Instruct-2507 (W14F
lineup). Bump to 15s. On MLX-path timeout, retry once with LFM2.5-1.2B if
downloaded; otherwise surface the original error. Single-shot, MLX-only.

Gated by EnableMLXFallback UserDefault, default true. Spec rollback table makes
this the first-line knob: defaults write … EnableMLXFallback 0 restores
single-attempt flow without code revert.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7 (T5): Centralized context-budget + redaction helper

**Files:**
- Create: `VoiceInk/Services/AIEnhancement/ContextSanitizer.swift` (new file — keeps the helper out of the already-large `AIEnhancementService.swift`)
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` (call sites in `getSystemMessage`, `enhancePreview`, `commandModeRewrite`)
- Modify: `VoiceInk/AppDefaults.swift` (register `EnableContextSanitization: true`)

- [ ] **Step 1: Write the failing test**

(VoiceInk doesn't have a Swift Testing harness wired in CI; we run a manual repro script and grep instead. If `XCTest` already exists in the repo, prefer it — `find VoiceInk -name '*Tests*.swift'` will tell you. If no tests, do Step 1 as an inline `#if DEBUG` repro that runs once and prints to stderr, then delete it after Step 4 verifies.)

```bash
find . -name "*Tests*.swift" -not -path "./.git/*" | head -5
```

If no test target: skip the test-driven steps and rely on the manual repro in Step 5.

If a test target exists: write a unit test in `Tests/VoiceInkTests/ContextSanitizerTests.swift`:

```swift
import XCTest
@testable import VoiceInk

final class ContextSanitizerTests: XCTestCase {
    func test_redactsKeyShapeLines() {
        let input = """
        normal line
        password=hunter2
        api_key: foo123
        secretary planned the meeting
        """
        let out = ContextSanitizer.sanitize(input, maxBytes: 10_000)
        XCTAssertFalse(out.contains("hunter2"))
        XCTAssertFalse(out.contains("foo123"))
        XCTAssertTrue(out.contains("secretary planned"))  // word-boundary check
    }

    func test_redactsAuthHeaderShapes() {
        let input = """
        Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.foo.bar
        x-api-key: abc/+xyz=
        nothing here
        """
        let out = ContextSanitizer.sanitize(input, maxBytes: 10_000)
        XCTAssertFalse(out.contains("eyJhbGc"))
        XCTAssertFalse(out.contains("abc/+xyz"))
        XCTAssertTrue(out.contains("nothing here"))
    }

    func test_truncatesToTailWithMarker() {
        let head = String(repeating: "A", count: 1000)
        let tail = String(repeating: "B", count: 500)
        let input = head + "\n" + tail
        let out = ContextSanitizer.sanitize(input, maxBytes: 600)
        XCTAssertTrue(out.contains("…[truncated]…"))
        XCTAssertTrue(out.contains("BBB"))
        XCTAssertFalse(out.contains("AAA"))  // tail-prefer: head dropped
    }

    func test_idempotent() {
        let input = "password=foo\nhello\n" + String(repeating: "Z", count: 5000)
        let once = ContextSanitizer.sanitize(input, maxBytes: 1000)
        let twice = ContextSanitizer.sanitize(once, maxBytes: 1000)
        XCTAssertEqual(once, twice)
    }
}
```

- [ ] **Step 2: Run failing test**

```bash
xcodebuild test -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/ContextSanitizerTests 2>&1 | tail -15
```

Expected: FAIL — `ContextSanitizer` not defined. (If no test target, skip.)

- [ ] **Step 3: Implement `ContextSanitizer`**

Create `VoiceInk/Services/AIEnhancement/ContextSanitizer.swift`:

```swift
import Foundation

enum ContextSanitizer {
    /// Phase A T5 — bound a context block size + strip secret-shaped lines.
    /// Idempotent: sanitize(sanitize(x, n), n) == sanitize(x, n).
    /// Tail-prefer truncation: more recent content survives.
    static func sanitize(_ raw: String, maxBytes: Int) -> String {
        let redacted = redactSecretLines(in: raw)
        return truncateToTail(redacted, maxBytes: maxBytes)
    }

    private static let keyShapePattern = try! NSRegularExpression(
        pattern: #"\b(password|passwd|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|secret[_-]?key|client[_-]?secret|private[_-]?key|aws[_-]?secret|github[_-]?token)\b\s*[:=]\s*\S"#,
        options: [.caseInsensitive]
    )

    private static let authHeaderPattern = try! NSRegularExpression(
        pattern: #"\b(authorization|x-api-key)\s*:\s*\S+"#,
        options: [.caseInsensitive]
    )

    private static let bearerPattern = try! NSRegularExpression(
        pattern: #"\bbearer\s+[A-Za-z0-9._/+\-]+\b"#,
        options: [.caseInsensitive]
    )

    private static func redactSecretLines(in input: String) -> String {
        let lines = input.components(separatedBy: "\n")
        let kept = lines.filter { line in
            let range = NSRange(location: 0, length: (line as NSString).length)
            if keyShapePattern.firstMatch(in: line, range: range) != nil { return false }
            if authHeaderPattern.firstMatch(in: line, range: range) != nil { return false }
            if bearerPattern.firstMatch(in: line, range: range) != nil { return false }
            return true
        }
        return kept.joined(separator: "\n")
    }

    private static func truncateToTail(_ input: String, maxBytes: Int) -> String {
        let utf8Bytes = Array(input.utf8)
        guard utf8Bytes.count > maxBytes else { return input }

        // Find the last `maxBytes` bytes, then snap to the next line boundary forward
        // so we don't slice a UTF-8 codepoint and don't include a partial first line.
        let cutFrom = utf8Bytes.count - maxBytes
        // Walk forward to a newline so the truncated tail starts at a line boundary.
        var snap = cutFrom
        while snap < utf8Bytes.count, utf8Bytes[snap] != UInt8(ascii: "\n") { snap += 1 }
        if snap < utf8Bytes.count { snap += 1 }  // skip the newline itself

        let tailBytes = Array(utf8Bytes[snap..<utf8Bytes.count])
        guard let tail = String(bytes: tailBytes, encoding: .utf8) else {
            // If snapping produced invalid UTF-8 (shouldn't, since we land on \n),
            // bail to the un-truncated input — better correctness than secrets bleed.
            return input
        }
        return "…[truncated]…\n" + tail
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

```bash
xcodebuild test -scheme VoiceInk -destination 'platform=macOS' -only-testing:VoiceInkTests/ContextSanitizerTests 2>&1 | tail -15
```

Expected: PASS on all four cases. If `idempotent` fails, the truncation marker is bleeding through — fix the helper to recognize and not re-prepend.

(If no test target, run a quick repro in a temporary file and confirm the four assertions manually before proceeding.)

- [ ] **Step 5: Wire helper into the three call sites + kill-switch gate**

In `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`:

Add a private wrapper near the top of the class:

```swift
private func bound(_ raw: String, maxBytes: Int) -> String {
    UserDefaults.standard.bool(forKey: "EnableContextSanitization")
        ? ContextSanitizer.sanitize(raw, maxBytes: maxBytes)
        : raw
}
```

Then in `getSystemMessage` (around lines 182, 190, 173, 198 of the current file), replace each context-block construction:

```swift
// BEFORE:
"\n\n<CLIPBOARD_CONTEXT>\n\(clipboardText)\n</CLIPBOARD_CONTEXT>"
// AFTER:
"\n\n<CLIPBOARD_CONTEXT>\n\(bound(clipboardText, maxBytes: 2048))\n</CLIPBOARD_CONTEXT>"
```

Apply the same pattern at:
- `<CURRENT_WINDOW_CONTEXT>` site, `maxBytes: 2048`
- `<CURRENTLY_SELECTED_TEXT>` site, `maxBytes: 2048`
- `<CUSTOM_VOCABULARY>` interior, `maxBytes: 1024`

Then check `enhancePreview` (line 736) and `commandModeRewrite` (line 583) — these don't construct clipboard/screen blocks, but if they ever do (or if a future refactor moves construction up), they'll inherit the bound. No edits needed today; verify with the grep below.

- [ ] **Step 6: Register kill-switch default**

In `VoiceInk/AppDefaults.swift`, add to the register dict alongside `EnableMLXFallback`:

```swift
"EnableContextSanitization": true,
```

- [ ] **Step 7: Verify every context-block site is bounded**

```bash
grep -n -B1 -A2 'CLIPBOARD_CONTEXT\|CURRENT_WINDOW_CONTEXT\|CURRENTLY_SELECTED_TEXT\|CUSTOM_VOCABULARY' VoiceInk/Services/AIEnhancement/AIEnhancementService.swift
```

Expected: every match's value-interpolation (the `\(...)`) goes through `bound(...)`. If any raw `\(clipboardText)` or similar slips through, fix it.

- [ ] **Step 8: Build**

```bash
xcodebuild -scheme VoiceInk -configuration Debug build 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 9: Manual redaction smoke**

Set clipboard to:

```
normal line one
password=foo123
api_key: bar456
Authorization: Bearer eyJtest
normal line four
```

Dictate "this is a test". Inspect `lastUserMessageSent` via the debug pane (still present per the spec — T3 didn't remove it). Expected: clipboard block in the system prompt contains lines 1, 5, and any `<CLIPBOARD_CONTEXT>` framing — but NOT `foo123`, `bar456`, or `eyJtest`.

- [ ] **Step 10: Manual truncation smoke**

Copy a 5KB payload (e.g., a chunk of Lorem Ipsum) into clipboard. Dictate. Inspect the `<CLIPBOARD_CONTEXT>` block — should be ≤2KB plus the `…[truncated]…` marker, and should retain the *tail* of the original.

- [ ] **Step 11: Kill-switch verification**

```bash
defaults write com.prakashjoshipax.VoiceInk EnableContextSanitization 0
```

Re-launch. Repeat Step 9. Expected: redacted lines pass through unchanged (kill-switch off restores raw blocks).

```bash
defaults delete com.prakashjoshipax.VoiceInk EnableContextSanitization
```

- [ ] **Step 12: Commit**

```bash
git add VoiceInk/Services/AIEnhancement/ContextSanitizer.swift VoiceInk/Services/AIEnhancement/AIEnhancementService.swift VoiceInk/AppDefaults.swift
# If a test was added:
git add Tests/VoiceInkTests/ContextSanitizerTests.swift
git commit -m "$(cat <<'EOF'
phaseA(T5): bound context blocks + redact secret-shaped lines

ContextSanitizer.sanitize(_ raw:, maxBytes:) is idempotent and tail-prefer:
caps clipboard/screen-capture/selected-text at 2KB, custom vocabulary at 1KB,
and drops lines matching narrow key-shape and auth-header patterns
(word-boundary anchored to avoid 'secretary'-class false positives).

Wired into all three context-block construction sites in AIEnhancementService
(getSystemMessage; enhancePreview and commandModeRewrite verified clean).
Gated by EnableContextSanitization UserDefault, default true.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Joint T1+T5 validation

**Files:**
- None modified — measurement-only task.

This is the joint validation the spec promised. T1 raised the timeout floor; T5 reduced the input drive. Validate they hold the spec's success gates together.

- [ ] **Step 1: Build the latest HEAD**

```bash
xcodebuild -scheme VoiceInk -configuration Debug build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2: Sanity-record a smattering of dictations**

Launch the app. Record at minimum:
- 3 short dictations (≤120c — trips the W11.A2 fast-path).
- 3 medium dictations (200–500c).
- 3 long dictations (>500c — likely to push Qwen3-4B's tail).
- 1 dictation with a 5KB clipboard pre-loaded (validates T5 truncation pressure).
- 1 dictation with clipboard containing two `password=` lines (validates T5 redaction in flight).

- [ ] **Step 3: Inspect post-Phase-A timings vs baseline**

```bash
diff /tmp/phaseA_baseline_timings.csv ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv | head -50
tail -20 ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv
```

The new lines are the post-Phase-A run.

- [ ] **Step 4: Compute the gates**

For the post-Phase-A rows where `provider=mlx` and `model=mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510`:

```bash
awk -F',' '$2 == "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510" {print $9, $10}' ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv | tail -50
```

(adjust column indices to actual CSV schema). Compute:

- timeout rate: count of rows where last column = `timedOut` divided by total Qwen3-4B rows. **Gate: < 2%.**
- p95 of total-time column for `success` rows. **Gate: ≤ 8s.**

Per the spec, this gate is over a rolling 50 calls, so a 10-call check is informational only. The 50-call window is the production gate after ≥2 days of normal use.

- [ ] **Step 5: Document the readout**

Append a one-line note to the parking-lot doc or commit a small `docs/superpowers/plans/2026-05-06-PhaseA-readout.md` capturing the 10-call sample readings (informational; the 2-day rolling gate is the binding one).

- [ ] **Step 6: No new commit beyond the readout file** if you wrote one.

---

## Task 9: PR + handoff

**Files:**
- None modified directly — final wrap.

- [ ] **Step 1: Confirm the branch state**

```bash
git log --oneline main..HEAD
```

Expected: 6 commits in this order (oldest → newest):
1. cherry-pick 94be2ff (T3) — possibly with our resolved-conflict suffix.
2. phaseA(T4): surface enhancement failures … (Task 2).
3. cherry-picks 05cc14a, 34a7f5e, 46c5ed7 (Task 3 — three commits).
4. cherry-pick 13240f3 (Task 4).
5. phaseA(T2): hide LFM2.5-1.2B … (Task 5).
6. phaseA(T1): bump enhance timeout … (Task 6).
7. phaseA(T5): bound context blocks … (Task 7).

That's 7+ commits actually. Each track-mapped commit is recoverable via `git revert <hash>` per the rollback policy.

- [ ] **Step 2: Confirm uncommitted state is clean**

```bash
git status --short
```

Expected: empty (or only untracked planning markdown — those are intentional).

- [ ] **Step 3: Open PR (only if user asks)**

Per CLAUDE.md, do not push or create PRs without explicit user authorization. If the user asks: branch is `phaseA-pipeline-tightening`. PR title: `Phase A: pipeline tightening — timeout, fallback, redaction, failure visibility`. Use the spec link as the PR body anchor.

- [ ] **Step 4: Begin the 2-day measurement window**

The spec's success gates require ≥2 days of dogfood usage. Phase B (`<ACTIVE_APP>` tag + Power Mode presets) is blocked until the gates hold. Surface this to the user in the wrap-up message.

---

## Self-review checklist

(Run before declaring the plan complete.)

**1. Spec coverage:** Every Phase A track from the spec (T1, T2, T3, T4, T5) maps to one or more tasks above? T3=Task 1, T4=Tasks 2–4, T2=Task 5, T1=Task 6, T5=Task 7, joint validation=Task 8, wrap=Task 9. ✓

**2. Placeholder scan:** No "TBD", "implement later", or "similar to Task N" without code. The closest is Task 5 Step 2 ("Pick the smallest patch matching the existing structure") — that's a structural decision the implementer must make from the file's actual state, not a placeholder for code.

**3. Type consistency:** `bound(_:maxBytes:)` defined Task 7 Step 5, used same step. `ContextSanitizer.sanitize(_:maxBytes:)` defined Task 7 Step 3, used same step. `EnableMLXFallback`, `EnableContextSanitization`, `EnableEnhancementFailureNotification` defined and gated consistently. ✓

**4. Cherry-pick path drift:** Task 2 calls out `TranscriptionPipeline.swift` rename (W11+ moved it from `VoiceInk/Whisper/` to `VoiceInk/Transcription/Engine/`). Task 1 calls out that 94be2ff only removes log lines (NOT the @Published properties — spec was updated). ✓

**5. Build hygiene:** Each non-cherry-pick commit ends with explicit `git add <files>` + heredoc commit message. Cherry-pick commits use upstream's existing message. No `git add -A` or `git add .` per CLAUDE.md.
