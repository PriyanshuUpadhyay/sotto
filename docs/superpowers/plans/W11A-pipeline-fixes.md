# W11.A — Enhance Pipeline Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.
>
> **CRITICAL pre-merge constraint:** before any code from this packet lands on `main`, the user must capture **5 baseline `🦾 enhance: total=…s` log lines** on the current build (pre-W11.A) and save them to `docs/superpowers/research/2026-04-29-baseline-enhance-timings.md`. This is the regression baseline the post-W11.A perf wins are measured against. The capture protocol is below in §Pre-merge ground-truth gate.

**Date:** 2026-04-29
**Scope:** Phase 1 of W11 — pipeline-side perf fixes for the enhance call path. Five P0 fixes from R2 §1 + two secondaries (idle-evict slider + max-tokens heuristic tightening). No new dependencies, no model swaps, no new SPM packages, no deployment-target bump.
**Sources of truth:**
- R2 audit (the WHY): `docs/superpowers/research/2026-04-29-enhance-pipeline-perf-audit.md`
- Master plan §2: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`
- W10 lineup (the WHAT this runs against): `docs/superpowers/plans/W10-mlx-registry-swap.md`

**Goal:** make first-enhance-after-idle and steady-state warm enhance both feel materially faster on the user's M-base 32 GB without changing the model lineup, the chat-template path, or any quality-affecting behavior outside the documented fast-path branch.

---

## Prelude — packet shape + commit etiquette

W11.A is **one logical packet** (per master plan §2) but its diff straddles two code areas + the plan doc itself. CLAUDE.md plan-files-committed-alongside-impl directs this split:

- `docs(plans): W11A — pipeline fixes plan` — this file (`W11A-pipeline-fixes.md`). Lands first, before any code.
- `feat(mlx): W11A — pipeline fixes (prewarm + fast-path + KV reuse + greedy + timeout + idle-evict + max-tokens)` — the code edits across A1...A7. **Single squashed commit** at merge time per `feedback_skip_per_packet_builds.md`. (See §Rollback plan for why squashed-not-split here, contrary to W10's three-commit boundary.)

Coder leaves edits uncommitted; lead handles both commits. No per-fix build is run during the packet; the integration `make local` runs once at the end (Task 9).

---

## Pre-merge ground-truth gate (USER-SIDE)

Before the coder touches a single source file, the user runs the protocol in R2 §6 against the **current build (HEAD before W11.A code lands)** to lock the regression baseline.

**Why this is non-negotiable:** the repo currently has zero captured `🦾 enhance: total=…s` numbers (R2 §B5). Without a baseline, "the perf fixes worked" is unfalsifiable. Every subsequent W11 packet (B = AFM, C = spec-decode) also leans on this baseline.

### How to capture (Console.app path)

1. Open `Console.app`.
2. Filter: paste `🦾 enhance:` into the search field. (Or, more precisely, set Subsystem filter to `com.prakashjoshipax.voiceink` and Category filter to `MLXProvider`.)
3. Make sure VoiceInk is on the current `main` build with MLX selected as the AI Enhancement provider, default prompt active, clipboard context **enabled** (typical user state per R2 §6).
4. Pick the model: `Qwen3-4B-Instruct-2507-4bit-DWQ-2510` (the W10 default mid). Confirm it is downloaded.

### How to capture (CLI alternative)

If the user prefers terminal over Console.app, the equivalent stream:

```bash
log stream --predicate 'subsystem == "com.prakashjoshipax.voiceink" AND category == "MLXProvider"' \
  --style compact \
  | grep --line-buffered '🦾 enhance:'
```

Run this in a terminal pane while dictating; redirect to a file with `tee baseline-enhance.log` if the user wants a transcript.

### What to capture

Run the 5-dictation sequence from R2 §6 verbatim:

| # | Scenario | Dictation phrase | When |
|---|---|---|---|
| 1 | Cold first | "Hey Alex, can you send me the slides from yesterday's meeting?" | Right after launching the app (or after waiting ≥10 min since last enhance) |
| 2 | Warm short | "Yeah totally, thanks." | Within 30 seconds of #1 |
| 3 | Warm medium | "I think the issue is that we're not handling the empty case in the parser. Can you take a look at the file we discussed?" | Within 30 seconds of #2 |
| 4 | Warm long | A 30-second monologue describing what you did today (~150-300 words) | Within 30 seconds of #3 |
| 5 | Cold-after-idle | "Quick reminder for tomorrow morning standup." | Wait 11+ minutes after #4 (forces the existing 600s idle eviction), then dictate |

For each dictation, copy the **full block of `🦾 enhance: …` log lines** (typically 4 lines per cycle: `model-load` if cold, `prep`, `gen`, `total`; plus the `WARN` line if total > 10s). Paste into:

`docs/superpowers/research/2026-04-29-baseline-enhance-timings.md`

(Coder does NOT create that file — the user does, with their captured numbers. The plan tracks it as a write-blocker dependency.)

### What "good baseline" means

Per R2 §3, on M-base 32 GB with Qwen3-4B-Instruct-2507:
- #1 cold expected total = 5-11s
- #2 warm short expected total = 2.5-4.5s
- #5 cold-after-idle expected total ≈ #1

If the user's numbers cluster at the **high end**, R2 §6 says H6 (system prompt bloat) and H1 (cold load) are confirmed dominant — A1 + A2 + A3 should yield the biggest measured gains. If at the **low end**, the H6 contribution is smaller and A2 + A3 will look proportionally less dramatic — flag in the post-merge follow-up.

### Gate condition

The W11.A code packet does NOT merge until:
- [x] `2026-04-29-baseline-enhance-timings.md` exists with at least the 5 dictation captures.
- [x] No catastrophic surprises (e.g. consistent `WARN total > 30s` would mean something else is broken; reconcile before W11.A lands).

---

## Architecture (W11.A fix list — A1 through A7)

```
Fix    Where                                                        Yield (R2 estimate)         Risk
─────  ─────────────────────────────────────────────────────────    ──────────────────────────  ─────
A1     MLX prewarm registered + triggered on launch / wake / rec    -1.5 to -4s cold spike       LOW
       ModelPrewarmService.swift:107-115 + VoiceInkEngine.swift     on first-enhance-after-idle
       :206-229 + AIService warm-shim + MLXProvider.warm()

A2     Short-transcript fast-path system prompt                     -30-50% prefill on short     LOW
       AIEnhancementService.swift:148-205 (getSystemMessage)        dictations (≤30 tokens user
       + MLX branch :250-263                                         input AND no clipboard/
                                                                     screen context)

A3     KV-cache reuse for system prefill                            -150-400ms ttft on warm      MED
       MLXProvider.swift:106-109 (TokenIterator construction)       2nd-onward enhance (skips
       + actor-state cache: [KVCache]? keyed on systemPrompt        system prefill entirely)
       hash; invalidate on prompt switch / model swap

A4     Greedy decode (temperature=0.0, drop topP)                   -5-15ms / 100-token          LOW
       MLXProvider.swift:94-98 (GenerateParameters)                  generation (compounds)

A5     Wall-clock generation timeout                                Caps 16-64s rambling cases    LOW
       MLXProvider.swift:106-124 + EnhancementTimeoutSeconds         at user's existing setting
       AppStorage (currently remote-API-only)                        (default 7s)

A6     idleEvictSeconds configurable @AppStorage                    Reduces frequency of cold     LOW
       AIService.swift:282 + new MLX-section settings UI             surprise from 10min → 30min
       (slider 60s ... 3600s ... never)                              default

A7     max_tokens heuristic tightening                              Faster early-stop on very     LOW
       MLXProvider.swift:79-80 (floor 192→96, ceiling 768→512)       short inputs; still ample
                                                                     headroom for typical
```

**Combined target:** total enhance wall-clock improves by 30-60% on warm calls, 40-70% on cold calls (R2 §3 table). Real numbers come from the post-merge re-capture (Task 9.3).

---

## Tech Stack

Swift 5.x, SwiftUI, mlx-swift-lm 3.31.3, swift-huggingface 0.9.0. **No SPM additions.** A3 leans on mlx-swift-lm 3.31.3 prompt-cache support (PR #155 — "Fix prompt-cache round-trip support for ArraysCache, MambaCache, and CacheList") which is already in the bundled framework.

Build via `make local` (~3 min cold). One integration build at Task 9, per CLAUDE.md cadence.

---

## Spec refs

- Research: `docs/superpowers/research/2026-04-29-enhance-pipeline-perf-audit.md` (the WHY for each A-fix; line-cited evidence; severity rankings)
- Master plan: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` §0 Q2 (idleEvictSeconds default 1800s) + §0 Q10 (test-infra deferred — build-only validation) + §2 W11.A scope table
- W6 plan precedent: `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` (the `🦾 enhance:` log instrumentation we depend on for both pre- and post-merge captures)
- W10 plan precedent: `docs/superpowers/plans/W10-mlx-registry-swap.md` (current model lineup; W11.A runs against this lineup unchanged)

---

## CLAUDE.md cadence rules respected

- **Single integration build at merge time.** No `make local` per A-task; one full build at Task 9. Per `feedback_skip_per_packet_builds.md`.
- **One squashed commit at merge time** for the code edits (vs. W10's three-commit boundary). See §Rollback plan for why this packet differs.
- **No `xcodebuild` per file.** SourceKit handles per-file syntax during edits.
- **No commits during execution.** Coder leaves edits staged-but-uncommitted; lead handles the doc commit + the code commit.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** The pre-existing `🦾` log markers in `MLXProvider.swift` are W6 instrumentation and stay (W6 documented exception).
- **Pre-existing spec-ref comments preserved.** `MLXProvider.swift` doc-comments at lines 13-16, 75-78, 148-149, 191-194, 196-200, 220-221 stay; new comments added only where the WHY is non-obvious.
- **No new test files.** Per Q10=defer, validation is build-only.

---

## File structure

### New files

None. W11.A is entirely an in-place edit packet across the existing enhance call path. No new types, no new views, no new services. (One settings UI row is added inside the existing `EnhancementSettingsPanel.swift` Section list — no new view file.)

### Modified files

- `VoiceInk/Services/AIEnhancement/MLXProvider.swift` — A3 (KV-cache reuse: new `private var prefillCache: [KVCache]?` + new `private var prefillCacheKey: String?` actor-state; capture-and-reuse logic in `enhance(...)`; invalidation in `reset()` + on systemPrompt-hash mismatch). A4 (`GenerateParameters` → `temperature: 0.0`, drop `topP`). A5 (wrap `for await item in stream` in `withTimeout` honoring `EnhancementTimeoutSeconds`). A6 (`init` accepts `idleEvictSeconds` as already; no struct change but the call site in `AIService` reads from new AppStorage). A7 (max_tokens heuristic update at line 79-80). New: `func warm() async throws` exposing `loadModel()` without enhancing, for the prewarm path. ~+90 LOC, -15 LOC.
- `VoiceInk/Services/AIEnhancement/AIService.swift` — A1 (route a public `warmMLX()` method that calls `mlxProvider(for:).warm()` if MLX is selected; safe no-op otherwise). A6 (read `MLXIdleEvictSeconds` from `@AppStorage` defaulting to 1800; pass to `MLXProvider(modelId:idleEvictSeconds:)` at the existing line 282 call site). ~+25 LOC, -2 LOC.
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` — A2 (the MLX provider branch at line 250-263: detect short-transcript fast-path conditions and substitute the minimal cleanup-only system prompt; new private constant `MLXShortTranscriptTokenThreshold` for tunability). New: A1 hook `warmMLXIfSelected()` exposed for `VoiceInkEngine`'s recording-start `Task.detached`. ~+45 LOC, -2 LOC.
- `VoiceInk/Services/ModelPrewarmService.swift` — A1 (extend `shouldPrewarm()` switch at lines 108-114 to include `.mlx`; extend `performPrewarm()` to dispatch to the right manager when the active provider is MLX — calling `aiService.warmMLX()` instead of `serviceRegistry.transcribe(...)`). The MLX path does NOT need an audio sample; it just loads weights into memory. ~+25 LOC, -3 LOC.
- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` — A1 (add `await self.enhancementService?.warmMLXIfSelected()` inside the existing `Task.detached` at lines 206-229, alongside the clipboard/screen capture calls). ~+3 LOC.
- `VoiceInk/Resources/AIPrompts.swift` — A2 (new `static let shortTranscriptCleanupTemplate: String` — the ~50-token minimal cleanup prompt the fast-path branches to). The existing `customPromptTemplate` and `assistantMode` UNCHANGED. ~+15 LOC.
- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` — A6 (new `Section` for "MLX (on-device) — Idle Eviction" with the `MLXIdleEvictSeconds` slider + reset-to-default; only visible when the active provider is MLX, gated via `EnvironmentObject` access to `aiService.selectedProvider`). ~+30 LOC.
- `VoiceInk/AppDefaults.swift` — A6 (register `MLXIdleEvictSeconds: 1800` default in the `register(defaults:)` dictionary at line ~45). ~+1 LOC.

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift` — W10's lineup. UNTOUCHED. W11.A runs against the registry unchanged; no entry edits, no new entries, no `expectedLatencySeconds` refinement (that's a W10 follow-up if needed).
- `VoiceInk/Services/AIEnhancement/MLXModelDownloader` — UNTOUCHED. The prewarm path leans on the model already being downloaded; if it isn't, A1's `warm()` shim resolves to a no-op (MLXProvider.loadModel returns the standard `.modelLoadFailed` we silently swallow in the warm hook — see Migration policy #5).
- `VoiceInk/Services/AIEnhancement/MLXProvider.swift` `applicationSupportModelsRoot()` (lines 196-211) — W6 legacy migration helper. UNTOUCHED.
- `VoiceInk/Services/AIEnhancement/MLXProvider.swift` `purgeLegacyApplicationSupportModelsIfPresent()` reachable from `MLXModelRegistry` — UNTOUCHED.
- `VoiceInk/Services/AIEnhancement/MLXProvider.swift` `🦾` log instrumentation lines 69, 99, 128, 132, 134, 167, 176, 181, 186, 238 — UNTOUCHED. These are the diagnostic surface both pre- and post-merge captures rely on.
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` non-MLX provider branches — `.ollama` (lines 224-235), `.localCLI` (lines 237-248), `.foundationModels` (lines 265-294), all remote-API providers (lines 296-336) — UNTOUCHED. A2 fast-path applies to MLX only. A5 wall-clock timeout applies to MLX only (remote APIs already honor `EnhancementTimeoutSeconds` per `AIEnhancementService.swift:73-76, :307, :325`).
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` `getSystemMessage(for:)` non-MLX-fast-path code path — UNTOUCHED. The fast-path is a content-aware branch INSIDE the MLX call site (`makeRequest`), not a rewrite of `getSystemMessage`. The full system prompt assembly (lines 148-205) stays identical for non-MLX providers and for MLX when fast-path conditions don't fire.
- `VoiceInk/Models/AIPrompts.swift` `customPromptTemplate` (lines 2-40) and `assistantMode` (lines 42-64) — UNTOUCHED. A2 adds a NEW constant; it does not modify the existing two.
- `VoiceInk/Models/PromptTemplates.swift` — UNTOUCHED. The "System Default" body content stays the same; A2 swaps the entire prompt scaffolding (wrapper + body) in fast-path branches, not the body content.
- `VoiceInk/Models/CustomPrompt.swift` `finalPromptText` (lines 128-134) — UNTOUCHED. A2 doesn't modify how the wrapper applies; it bypasses the wrapper for fast-path branches by replacing the systemMessage entirely before it reaches MLXProvider.
- `VoiceInk/Services/ModelPrewarmService.swift` `prewarmEnabledKey` (line 18) — UNTOUCHED. The existing `PrewarmModelOnWake` AppStorage gates ALL prewarming; A1 adds MLX to the same guarded path. **Migration consequence:** users with `PrewarmModelOnWake = false` get no MLX prewarm. Acceptable per Migration policy #2 (one switch governs the whole prewarm system).
- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` outside the recording-start `Task.detached` (lines 206-229) — UNTOUCHED. A1 adds one line inside the existing detached scope; recorder state machine is unaffected.
- `VoiceInk/Transcription/Pipeline/TranscriptionPipeline.swift` — UNTOUCHED. The pipeline raw-transcript fallback path (`docs/superpowers/research/2026-04-29-enhance-pipeline-perf-audit.md` cites lines 149-167) is what catches A5 timeout failures; we surface A5 as a normal `MLXProvider.ProviderError.generationFailed("Timed out")` so the existing fallback flow handles it.
- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` — UNTOUCHED. The picker rendering doesn't touch idle-evict; the slider lives in `EnhancementSettingsPanel`, which is the existing settings home for MLX-related toggles (the `Skip short transcriptions` and `Timeout duration` settings already live there).
- `VoiceInk/Services/AIEnhancement/Foundation*Provider.swift` (if exists) — UNTOUCHED. AFM is W11.B's territory; W11.A is MLX-only.
- All test files (`VoiceInkTests/*.swift`) — W11.A ships no new tests. Per Q10 in master plan §0, validation is build-only.

---

## Migration policy (resolves ambiguity for each design point)

The lead pinned the following architecture decisions for this packet. Restated as the authoritative ruleset for the coder.

1. **Fast-path is content-aware, not user-toggleable.** A2 applies a 50-token cleanup-only system prompt automatically when ALL of (a) `userPrompt` is ≤ `MLXShortTranscriptTokenThreshold` (default 30 tokens, computed via `userPrompt.count / 4` matching the heuristic in `MLXProvider.swift:79`), (b) `useClipboardContext` is false OR `lastCapturedClipboard` is empty/nil, (c) `useScreenCaptureContext` is false OR `screenCaptureService.lastCapturedText` is empty/nil. There is no user-facing "Use fast-path" toggle in v1 — the heuristic is intentionally invisible. If a user reports the fast-path producing visibly worse cleanup vs the full prompt, we either (i) raise the threshold, (ii) tighten the conditions (e.g. require the active prompt to be the System Default), or (iii) add a hidden `MLXFastPathDisabled` AppStorage as an escape hatch. v1 ships none of these — punt to a follow-up if needed. Matches R2 §H6 "Fix sketch" — content-aware short-transcript fast path.

2. **A1 obeys the existing `PrewarmModelOnWake` master switch.** R2 §H1 fix sketch wanted MLX added to `shouldPrewarm()` unconditionally; the current `ModelPrewarmService` gates ALL prewarm on `UserDefaults.standard.bool(forKey: "PrewarmModelOnWake")` (line 97-101). W11.A respects that — MLX prewarm fires ONLY when the user has opted into prewarm at all. Users who disabled prewarm (probably for battery reasons) keep that behavior. **No new master switch.** Yes this means a user with `PrewarmModelOnWake = false` who switches to MLX still pays the cold-load on first enhance. That's their preference — they explicitly turned prewarm off. Out-of-scope alternative: add a separate `PrewarmMLXOnWake` switch — punted to W11.A.follow-up if user reports it.

3. **A1 recording-start prewarm is fire-and-forget.** The hook in `VoiceInkEngine.swift:206-229` is already a `Task.detached` that captures clipboard + screen context concurrently with audio capture. We add `enhancementService?.warmMLXIfSelected()` to that same scope so MLX warm-up runs in PARALLEL with audio capture, not blocking it. Errors swallowed (logged as `notice`, not `error`) — a failed warm doesn't fail the recording. The user STILL pays cold-load latency on the actual `enhance()` call, but only if warm-up didn't finish in time (typically ≥3s of audio capture overlap is enough on M-base). **Acceptable degradation profile.**

4. **A3 KV-cache reuse — invalidation policy.** The cache is keyed on `SHA256(systemPrompt)` (truncated to first 16 hex chars for log readability — collision risk negligible at ~50-100 distinct keys/user-month). Cache is invalidated when:
   - The hash changes (different prompt template selected, clipboard/screen context content changes, custom vocabulary edited).
   - `reset()` is called (model swap; idle eviction; provider switch away from MLX).
   - Generation throws (defensive; a stale cache after a partial-prefill error is unsafe to reuse).
   - Process restart (cache is actor-instance state, not persisted).
   - **NOT** on warm short-path A2 fast-path — the fast-path uses a different (smaller) systemPrompt hash key, so it gets its own cache slot. **Two slots maximum** at any time: full-prompt slot and fast-path slot. Memory cost: ~94 MB (full) + ~10 MB (fast-path) per R2 §B1, well under the 32 GB budget.
   - **NOT** on `userPrompt` changes — only the system-prefill is cached; user-prompt prefill recomputes every call. This is exactly the win — system-prefill is the dominant cost per R2 §3 table.

5. **A3 KV-cache implementation — wrap `TokenIterator` directly, not `container.generate(...)`.** mlx-swift-lm `ModelContainer.generate(input:parameters:)` builds a fresh cache internally and discards it after the stream completes (Evaluate.swift:1184-1208 per R2 §B1). To reuse cache, the coder constructs `TokenIterator(input:model:cache:parameters:)` (Evaluate.swift:585-604) directly inside an `await container.perform { context in … }` closure, drives the iterator manually, and stashes the cache in actor state on success. **Reference implementation pattern**: see mlx-swift-lm `Examples/LLMEval/LLMEval.swift` for a TokenIterator-driven enhance loop. **Risk:** this is the highest-complexity edit in the packet. If the reviewer flags it as opaque or risk-laden, A3 is the **first fix to defer** — see Migration policy #11 (defer order) and Risks #1.

6. **A4 sampler swap — no other GenerateParameters changes.** R2 §H4 already validated: drop `topP: 0.9`, set `temperature: 0.0`. No other knobs touched. We do NOT add `repetitionPenalty: 1.05` (R2 §H4 mentions it as optional; current behavior shows no repetition pathology so we skip). We do NOT add `kvBits` quantization (R2 §"What's NOT worth fixing" — net loss for short-context cleanup).

7. **A5 timeout — honor existing `EnhancementTimeoutSeconds` AppStorage (default 7s).** The key already exists at `AppDefaults.swift:45` registering `7`, surfaced in `EnhancementSettingsPanel.swift:7` as the user-visible "Timeout duration" picker. R2 §H2 notes it currently only applies to remote-API providers. A5 makes it apply to MLX too. **No new AppStorage key.** **No separate MLX-specific timeout knob.** When the existing setting expires, MLX throws `MLXProvider.ProviderError.generationFailed("Timed out after \(timeout)s")` — the existing `AIEnhancementService.swift:257-261` `catch` block handles it; the existing `TranscriptionPipeline` fallback to raw transcript handles the user-visible recovery (per R2 §P0-4 fix sketch). The existing `EnhancementRetryOnTimeout` AppStorage (line 8) is honored by the remote-API code path; for MLX, we treat it as advisory — A5's first cut does NOT retry on timeout (a retried MLX call inherits the same unrecoverable cold-cache state as the first attempt; one retry would only double the wall-clock cost). **Punt MLX-retry to a follow-up.**

8. **A5 implementation — `Task.withTimeout` helper or inline `Task.sleep` race.** Swift's standard library has no `Task.timeout`. Two options:
   - **(picked) Wrap the AsyncStream consumption in a parent `Task` and race it against a sleep `Task` via `withTaskGroup` or `Task.detached(priority: .high)` / `Task { try await Task.sleep(...); throw … }` cancellation.** Implementation idiom: `try await withThrowingTaskGroup { group in group.addTask { /* generation */ }; group.addTask { try await Task.sleep(...); throw TimeoutError() }; try await group.next() }`. On timeout the generation task is cancelled (mlx-swift-lm honors `Task.isCancelled` in the iterator per R2 §B2). On success the timeout task is cancelled.
   - **(rejected) Add `mlx-swift-lm`-internal token-cap-by-time.** Out of scope; would require upstream patch.
   - The wall-clock budget is read from `EnhancementTimeoutSeconds` at the start of `enhance(...)` and applies to the **whole enhance call** (load + prep + gen + total). Not just generation. A user setting "7s" and getting a 9s cold-load + 4s gen pre-A1 would hit timeout at 7s — A1 fixes that by avoiding cold-load. Post-A1, a typical warm 7s ceiling is plenty.

9. **A6 idle-evict slider — value range and granularity.** Per master plan §0 Q2=a: configurable, default 1800s. Slider range: 60s minimum (lower than 1 min spam-thrashes load/evict cycles), 3600s max + a "Never" sentinel value (`.greatestFiniteMagnitude` mapped from a UI checkbox or "∞" tick). Tick stops: 60, 300, 600, 1200, 1800 (default), 2700, 3600, ∞. **No "auto on free RAM" mode** — R2 §H1 fix sketch suggested it; would require introspecting `mach_task_basic_info` and is overkill for the v1 win. The user picks; defaults are sensible.

10. **A7 max_tokens — boundary derivation.** R2 §H2 fix sketch: floor 192→96 for transcripts under ~30 chars; ceiling 768→512. The current line 79-80 is:
    ```swift
    let approxInputTokens = userPrompt.count / 4
    let dynamicMaxTokens = max(192, min(768, approxInputTokens * 3))
    ```
    The W11.A change:
    ```swift
    let approxInputTokens = userPrompt.count / 4
    let floor = userPrompt.count < 30 ? 96 : 192
    let dynamicMaxTokens = max(floor, min(512, approxInputTokens * 3))
    ```
    (Implementation note: the 30-char sub-floor is a hard branch on character count, not token count, to avoid the divide-by-4 round-down hitting at 28 chars / 7 tokens × 3 = 21 tokens needing a 96 floor.) The 512 ceiling is the new universal cap; 768 was conservative. Real cleanup output is ~80-200 tokens; 512 is still 2.5× expected.

11. **Defer order if reviewer flags any A-fix as risky.** If pre-merge review surfaces concerns, defer in this order (least-yield-loss first):
    1. **A6** (idle-evict slider) — pure UX; cuts only the cold-after-idle frequency, not the per-call cost. Easiest to ship in a v1.1.
    2. **A7** (max_tokens tightening) — micro-optimization on bounded edge cases.
    3. **A4** (greedy sampler) — small per-token win; quality-neutral but reviewer might want a side-by-side diff before signing off.
    4. **A5** (wall-clock timeout) — concurrency-correctness sensitive; if reviewer flags the `withTaskGroup` pattern, defer to a focused follow-up.
    5. **A3** (KV-cache reuse) — highest complexity, highest potential for subtle bugs. **First to defer if anything looks shaky.**
    6. **A2** (short-transcript fast-path) — would lose the biggest content-aware win but keeps the rest of the packet shippable.
    7. **A1** (prewarm) — last to defer; lowest risk, biggest cold-load win.
    Coder leaves a flag in the report ("A3 deferred — reviewer asked for side-by-side") so the lead can split the commit accordingly.

12. **No spec-ref `/* … */` paragraphs in code.** Per CLAUDE.md preference for sentence fragments. New comments in the modified files use one- or two-line `///` doc-comments above declarations, citing this plan path (`docs/superpowers/plans/W11A-pipeline-fixes.md`) only where the WHY is non-obvious (the fast-path branch condition, the KV-cache invalidation policy, the timeout-via-TaskGroup idiom). The 4 existing `🦾` log lines stay verbatim.

13. **No emoji in new code.** Existing `🦾` markers in `MLXProvider.swift` are W6 instrumentation and stay. No new emoji.

---

## Tasks

### Task 0: Audit + read references

**Files:** none (read-only).

- [ ] **Step 0.1: Confirm baseline timings doc exists**

```bash
ls -la docs/superpowers/research/2026-04-29-baseline-enhance-timings.md
```

Expected: file exists, ≥5 captured `🦾 enhance: total=…s` log blocks. If the file is absent or empty, **stop** and request the user run the Pre-merge ground-truth gate protocol above. Do NOT proceed with code edits without baseline data.

- [ ] **Step 0.2: Confirm the touched lines in `MLXProvider.swift` match the plan's citations**

```bash
grep -n "GenerateParameters\|dynamicMaxTokens\|for await item in stream\|idleEvictSeconds\|loadModel" VoiceInk/Services/AIEnhancement/MLXProvider.swift
```

Expected matches at approximately:
- Line 50: `init(modelId: String, idleEvictSeconds: TimeInterval = 600)` — A6 will change call-site default, not this signature
- Line 79-80: `let approxInputTokens = userPrompt.count / 4` + `let dynamicMaxTokens = max(192, min(768, approxInputTokens * 3))` — A7 target
- Line 94-98: `let parameters = GenerateParameters(maxTokens: dynamicMaxTokens, temperature: 0.1, topP: 0.9)` — A4 target
- Line 106-110: `let stream = try await container.generate(input: input, parameters: parameters)` — A3 + A5 target
- Line 162-189: `private func loadModel()` — A1 target (called by new `warm()` method)

If any match is off by more than 5 lines from the plan, reconcile with the lead — the line numbers in this plan are committed to the W10 post-merge state.

- [ ] **Step 0.3: Confirm `EnhancementTimeoutSeconds` is wired the way the plan assumes**

```bash
grep -rn "EnhancementTimeoutSeconds" VoiceInk --include="*.swift"
```

Expected matches: `AppDefaults.swift:45` (registers 7), `EnhancementSettingsPanel.swift:7` (UI binding), `AIEnhancementService.swift:74` (`baseTimeout` getter). The latter is currently used only by remote-API providers (lines 307, 325 of the same file). A5 will read the same key inside `MLXProvider.enhance(...)`.

- [ ] **Step 0.4: Confirm the recording-start `Task.detached` boundary**

```bash
grep -n "Task.detached\|captureClipboardContext\|captureScreenContext" VoiceInk/Transcription/Engine/VoiceInkEngine.swift
```

Expected: a `Task.detached` block around line 206 with calls to `enhancementService.captureClipboardContext()` (line 225) and `await enhancementService.captureScreenContext()` (line 227). A1 inserts `await enhancementService?.warmMLXIfSelected()` adjacent to those calls — same scope, same priority.

---

### Task 1: A1 — MLX prewarm

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXProvider.swift`
- Modify: `VoiceInk/Services/AIEnhancement/AIService.swift`
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`
- Modify: `VoiceInk/Services/ModelPrewarmService.swift`
- Modify: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`

- [ ] **Step 1.1: Expose `warm()` on `MLXProvider`**

Add a public method on the actor that calls `loadModel()` without enhancing. Diff shape:

```swift
/// Load weights into memory without running enhance. Idempotent — a second
/// call when warm is a cheap actor-state check.
func warm() async throws {
    _ = try await loadModel()
    self.lastUsedAt = Date()
    self.scheduleEvictionCheck()
}
```

- [ ] **Step 1.2: Add `AIService.warmMLX()` shim**

In `AIService.swift`, mirror the pattern of `enhanceWithMLX` (line 553):

```swift
func warmMLX() async {
    let modelId = UserDefaults.standard.string(forKey: "mlx_selected_model_id") ?? ""
    guard !modelId.isEmpty else { return }
    guard MLXModelDownloader.status(for: modelId) == .downloaded else { return }
    let provider = mlxProvider(for: modelId)
    do {
        try await provider.warm()
    } catch {
        // Warm failures are non-fatal — the user still pays cold-load on the
        // actual enhance call, but no UX degradation beyond that.
        Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AIService")
            .notice("🦾 warmMLX failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

- [ ] **Step 1.3: Add `AIEnhancementService.warmMLXIfSelected()` hook**

In `AIEnhancementService.swift`, an entry point that the prewarm service AND the recording-start hook can both call:

```swift
/// Fire-and-forget MLX warm-up. Safe no-op if the active provider isn't MLX
/// or no MLX model is selected. Errors logged but not surfaced.
func warmMLXIfSelected() async {
    guard aiService.selectedProvider == .mlx else { return }
    await aiService.warmMLX()
}
```

- [ ] **Step 1.4: Extend `ModelPrewarmService.shouldPrewarm()` switch**

In `ModelPrewarmService.swift:108-114`, current code:

```swift
switch model.provider {
case .whisper, .fluidAudio:
    return true
default:
    logger.notice("Skipping prewarm - cloud models don't need it")
    return false
}
```

becomes — note that `model.provider` here is the **transcription** provider (whisper/fluidAudio), NOT the AI Enhancement provider. The plan's A1 needs a SEPARATE check for the MLX-as-enhance-provider case. Diff shape:

```swift
// Transcription model prewarm (existing).
switch model.provider {
case .whisper, .fluidAudio:
    return true
default:
    break
}

// AI Enhancement MLX prewarm (W11.A1) — orthogonal to transcription model.
// Returns true if MLX is the selected enhance provider with a downloaded
// model; the actual MLX warm dispatch is in performPrewarm().
if isMLXEnhanceProviderReady() {
    return true
}

logger.notice("Skipping prewarm - no warmable provider")
return false
```

The new helper:

```swift
private func isMLXEnhanceProviderReady() -> Bool {
    let modelId = UserDefaults.standard.string(forKey: "mlx_selected_model_id") ?? ""
    guard !modelId.isEmpty else { return false }
    return MLXModelDownloader.status(for: modelId) == .downloaded
}
```

- [ ] **Step 1.5: Extend `performPrewarm()` to dispatch MLX warm**

The transcription prewarm path (lines 66-91) calls `serviceRegistry.transcribe(...)` with a sample audio file. The MLX path doesn't need audio — just calls `aiService.warmMLX()` (or surfaces it via the `AIEnhancementService` it doesn't directly hold). Two options:

- **(picked) Inject a dependency on `AIEnhancementService` (or its `AIService`) into `ModelPrewarmService`.** Constructor parameter; pass-through from the caller (likely the app-level service container). The prewarm service then calls `await enhancementService.warmMLXIfSelected()`.
- **(rejected) Post a `NotificationCenter` notification and let `AIEnhancementService` self-handle.** Tighter coupling than necessary; observer registration leak risk.

Diff shape inside `performPrewarm()`:

```swift
// Existing transcription prewarm path runs first (if shouldPrewarm path was
// for whisper/fluidAudio).
if let currentModel = transcriptionModelManager.currentTranscriptionModel,
   currentModel.provider == .whisper || currentModel.provider == .fluidAudio {
    // … existing serviceRegistry.transcribe(audioURL:model:) block …
}

// MLX enhance prewarm (additive; runs alongside transcription prewarm).
if isMLXEnhanceProviderReady() {
    let warmStart = Date()
    await enhancementService?.warmMLXIfSelected()
    let warmDuration = Date().timeIntervalSince(warmStart)
    logger.notice("MLX warm completed in \(String(format: "%.2f", warmDuration), privacy: .public)s")
}
```

The constructor adds `enhancementService: AIEnhancementService?` (optional — at app-launch time the service might not be wired yet; the dependency is injected post-init via the existing observable wiring). Minor refactor at the call site (the app-level service container that wires `ModelPrewarmService` today).

- [ ] **Step 1.6: Add recording-start hook in `VoiceInkEngine.swift:206-229`**

Inside the existing `Task.detached`:

```swift
Task.detached { [weak self] in
    guard let self else { return }

    // … existing whisper/fluidAudio model preload …

    if let enhancementService = await self.enhancementService {
        await MainActor.run {
            enhancementService.captureClipboardContext()
        }
        await enhancementService.captureScreenContext()
        // W11.A1: warm MLX in parallel with audio capture so first-enhance
        // after this recording skips cold-load. Fire-and-forget; errors
        // swallowed inside warmMLXIfSelected.
        await enhancementService.warmMLXIfSelected()
    }
}
```

- [ ] **Step 1.7: Verify no orphan references**

```bash
grep -rn "warmMLX\|warmMLXIfSelected" VoiceInk --include="*.swift"
```

Expected: matches in `AIService.swift` (definition + body), `AIEnhancementService.swift` (definition + body), `ModelPrewarmService.swift` (call site), `VoiceInkEngine.swift` (call site). No matches elsewhere.

**Risk:** LOW — additive paths; no existing behavior modified beyond the prewarm switch widening. Per R2 §H1: -1.5 to -4s on cold-after-idle first-enhance.

**Verification:** type-check passes (SourceKit live during edits). No new tests. Deferred validation: integration build (Task 9) + post-merge re-capture (Task 9.3) — the user repeats the 5-dictation protocol and expects #1 cold load to drop materially.

---

### Task 2: A2 — short-transcript fast-path system prompt

**Files:**
- Modify: `VoiceInk/Resources/AIPrompts.swift` (NOTE: actual path is `VoiceInk/Models/AIPrompts.swift`)
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

- [ ] **Step 2.1: Add `shortTranscriptCleanupTemplate` to `AIPrompts`**

In `VoiceInk/Models/AIPrompts.swift` (alongside `customPromptTemplate` and `assistantMode`):

```swift
/// Minimal cleanup-only system prompt for the W11.A2 short-transcript
/// fast-path. ~50 tokens vs the ~675-token customPromptTemplate wrapper +
/// ~600-token System Default body. Used only when userPrompt is ≤30 chars
/// AND no clipboard/screen context is active. See plan
/// docs/superpowers/plans/W11A-pipeline-fixes.md §Migration policy #1.
static let shortTranscriptCleanupTemplate = """
You are a text-cleanup engine. Output ONLY the cleaned dictation:
- Fix obvious grammar, remove fillers, keep names and numbers.
- Apply standard punctuation (periods, commas, question marks).
- No preamble, no commentary, no tags, no quotes.
- If the dictation is empty, output an empty string.
"""
```

- [ ] **Step 2.2: Add the fast-path branch in the MLX call site**

In `AIEnhancementService.swift`, inside `makeRequest(text:mode:)` at the existing `if aiService.selectedProvider == .mlx` block (line 250-263), branch BEFORE the existing `getSystemMessage(for:)` call:

```swift
if aiService.selectedProvider == .mlx {
    do {
        // W11.A2 short-transcript fast-path: when transcript is ≤30 chars
        // AND no contextual augmentation is active, swap the giant wrapper
        // for the minimal cleanup template. Drops system prefill from
        // ~1,275 → ~50 tokens. See plan §A2 + Migration policy #1.
        let useFastPath = text.count <= MLXShortTranscriptCharThreshold
            && !hasNonEmptyContextualAugmentation()
        let systemMessageForMLX: String
        if useFastPath {
            systemMessageForMLX = AIPrompts.shortTranscriptCleanupTemplate
            logger.notice("🦾 enhance: fast-path system-prompt (text=\(text.count)c)")
        } else {
            systemMessageForMLX = await getSystemMessage(for: mode)
        }
        await MainActor.run {
            self.lastSystemMessageSent = systemMessageForMLX
            self.lastUserMessageSent = text
        }
        let result = try await aiService.enhanceWithMLX(systemPrompt: systemMessageForMLX, userPrompt: text)
        return AIEnhancementOutputFilter.filter(stripPreamble(result))
    } catch {
        // … existing error mapping unchanged …
    }
}
```

The new constant + helper at file scope:

```swift
private let MLXShortTranscriptCharThreshold = 120  // ~30 tokens at chars/4 heuristic

private func hasNonEmptyContextualAugmentation() -> Bool {
    if useClipboardContext, let s = lastCapturedClipboard, !s.isEmpty { return true }
    if useScreenCaptureContext, let s = screenCaptureService.lastCapturedText, !s.isEmpty { return true }
    return false
}
```

(Note: `30 tokens × 4 chars/token = 120 chars`. The plan uses `120` not `30` to match `userPrompt.count` which is bytes, consistent with `MLXProvider.swift:79`'s `userPrompt.count / 4` heuristic.)

- [ ] **Step 2.3: Confirm `getSystemMessage(for:)` is bypassed cleanly when fast-path fires**

The existing line 217 `let systemMessage = await getSystemMessage(for: mode)` runs unconditionally before the MLX branch. The fast-path version moves it INSIDE the branch (gated). This means non-MLX providers still call `getSystemMessage` exactly once at the top of `makeRequest`. The MLX fast-path skips it entirely (saving the screen-OCR / clipboard read latency that ALSO contributes to `prep`). **Side benefit:** the existing `lastSystemMessageSent` debug surface in `EnhancementSettingsPanel.swift` shows the fast-path system message correctly, so the user can verify which path fired by opening the "Last Sent System Prompt" disclosure.

Verify no regression by manually re-reading `makeRequest` post-edit — the non-MLX paths must still call `getSystemMessage(for: mode)` at the top.

- [ ] **Step 2.4: Verify no orphan references**

```bash
grep -rn "shortTranscriptCleanupTemplate\|MLXShortTranscriptCharThreshold\|hasNonEmptyContextualAugmentation" VoiceInk --include="*.swift"
```

Expected: matches in `AIPrompts.swift` (definition), `AIEnhancementService.swift` (constant + helper + call site).

**Risk:** LOW — content-aware branch; only activates on short inputs without context. The full prompt path is preserved for all other cases. Per R2 §H6: -30-50% prefill cost on short dictations.

**Verification:** type-check passes. Manual UI check: open "Last Sent System Prompt" disclosure after a short dictation and confirm the short template appears; after a longer dictation or with clipboard ON, the full wrapper appears.

---

### Task 3: A3 — KV-cache reuse for system prefill

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXProvider.swift`

- [ ] **Step 3.1: Add cache state to the actor**

New private fields adjacent to existing actor state (around line 47-48):

```swift
#if canImport(MLXLLM)
/// W11.A3: persistent KV-cache for the system-prompt prefill. Keyed on
/// SHA-256(systemPrompt) so a prompt-template / context change invalidates.
/// Two slots maximum (full-prompt + fast-path-prompt); ARC frees both on
/// `reset()`. See plan §Migration policy #4.
private var prefillCache: [KVCache]?
private var prefillCacheKey: String?
#endif
```

- [ ] **Step 3.2: Compute key + branch on cache hit/miss inside `enhance(...)`**

Inside `enhance(systemPrompt:userPrompt:)` after the chat-template `prepare(input:)` call (around line 91), before the existing `container.generate(...)` call (line 106):

```swift
// W11.A3: SHA-256 of systemPrompt, truncated to 16 hex chars for log
// readability. Collision risk negligible at typical 50-100 distinct keys
// per user-month.
let cacheKey = systemPrompt.sha256Prefix16()  // helper below
let cacheReusable = (prefillCacheKey == cacheKey) && (prefillCache != nil)
```

Then drive a `TokenIterator` directly (see Migration policy #5) instead of `container.generate(...)`:

```swift
let stream = AsyncThrowingStream<Generation, Error> { continuation in
    let task = Task {
        do {
            try await container.perform { context in
                let cache: [KVCache]
                if cacheReusable, let existing = self.prefillCache {
                    cache = existing
                } else {
                    cache = context.model.newCache(parameters: parameters)
                }
                let iterator = try TokenIterator(
                    input: input,
                    model: context.model,
                    cache: cache,
                    parameters: parameters
                )
                for await item in MLXLMCommon.generate(iterator: iterator, /* … */) {
                    continuation.yield(item)
                    if Task.isCancelled { break }
                }
                // On clean completion, stash the cache for next call.
                await self.cachePrefill(cache, forKey: cacheKey)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
    continuation.onTermination = { _ in task.cancel() }
}
```

**Coder discretion on the iterator-driver shape:** the example above is illustrative. Match the actual mlx-swift-lm 3.31.3 API (the coder should consult `.local-build/SourcePackages/checkouts/mlx-swift-lm/Libraries/MLXLMCommon/Evaluate.swift:1184-1208` to confirm the `TokenIterator(input:model:cache:parameters:)` signature and any newer convenience overloads). If the manual driver looks like it's reimplementing too much of `container.generate(...)`, the coder may instead **fork** mlx-swift-lm's `runSynchronousGenerationLoop` into a private file scope helper, passing the cache through.

The new helper methods on the actor:

```swift
private func cachePrefill(_ cache: [KVCache], forKey key: String) {
    self.prefillCache = cache
    self.prefillCacheKey = key
}

private func invalidatePrefillCache() {
    self.prefillCache = nil
    self.prefillCacheKey = nil
}
```

- [ ] **Step 3.3: Invalidate on `reset()` and on generation error**

Update `reset()` (line 150-157):

```swift
func reset() {
    evictTask?.cancel()
    evictTask = nil
    #if canImport(MLXLLM)
    modelContainer = nil
    invalidatePrefillCache()  // W11.A3: cache lifetime bound to model
    #endif
    lastUsedAt = nil
}
```

In the `catch` block of `enhance(...)` (lines 137-142), add `invalidatePrefillCache()` before re-throwing — a partial prefill on error leaves the cache in an unknown state.

- [ ] **Step 3.4: Add the SHA-256 helper**

A file-scope String extension (or, if the coder prefers, a private static helper on `MLXProvider`):

```swift
private extension String {
    /// SHA-256 prefix for cache-keying. CryptoKit available since macOS 10.15.
    func sha256Prefix16() -> String {
        let data = Data(self.utf8)
        let digest = SHA256.hash(data: data)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
```

(Adds `import CryptoKit` at the top of `MLXProvider.swift` if not already imported.)

- [ ] **Step 3.5: Log cache hit/miss for observability**

Add a `notice` log line so the post-merge capture can verify cache hits are happening on warm calls:

```swift
if cacheReusable {
    Self.logger.notice("🦾 enhance: KV-cache HIT key=\(cacheKey, privacy: .public)")
} else {
    Self.logger.notice("🦾 enhance: KV-cache MISS key=\(cacheKey, privacy: .public)")
}
```

The post-merge capture's #2 warm-short dictation should show `KV-cache HIT` and have `ttft` drop materially vs #1 cold.

**Risk:** MED — highest complexity in the packet. Three failure modes to watch for:
- **(a)** Stale cache after a partial-prefill error (mitigated by Step 3.3 invalidation in `catch`).
- **(b)** Cache shape mismatch on prompt-length change (mitigated by hash-keyed slot — different prompt → different key → fresh cache).
- **(c)** Memory creep — two slots × ~100 MB ≈ 200 MB, freed on `reset()` only. If a user toggles between prompts repeatedly, a third slot would replace the older one (use LRU or just keep last-2). v1 keeps "last 1 slot" — overwrites on miss. Multiple-prompt-toggle users pay miss cost on each switch; acceptable.

Per R2 §B1: -150-400ms `ttft` on warm 2nd-onward enhance.

**Verification:** type-check passes. Post-merge capture #2 vs #1 — the `KV-cache HIT` log line must appear on #2; `ttft` on #2 should be a fraction of #1 minus the cold-load delta.

---

### Task 4: A4 — greedy sampler

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXProvider.swift`

- [ ] **Step 4.1: Update `GenerateParameters`**

In `MLXProvider.swift:94-98`, current:

```swift
let parameters = GenerateParameters(
    maxTokens: dynamicMaxTokens,
    temperature: 0.1,
    topP: 0.9
)
```

becomes:

```swift
// W11.A4: temperature=0.0 routes to ArgMaxSampler in mlx-swift-lm
// (Evaluate.swift:141-153). topP omitted — ignored at temp=0 anyway.
// Quality impact zero on cleanup task per R2 §H4.
let parameters = GenerateParameters(
    maxTokens: dynamicMaxTokens,
    temperature: 0.0
)
```

**Risk:** LOW — quality-neutral swap per R2 §H4. The 5-15ms saving compounds over 50-200 tokens. Coder verifies via dictation that output isn't worse — fast-path through the picker still produces clean output.

**Verification:** type-check passes. Post-merge capture: tok/s should be marginally higher; output content should look identical to pre-A4 cleanup runs on the same input.

---

### Task 5: A5 — wall-clock generation timeout

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXProvider.swift`

- [ ] **Step 5.1: Read timeout from AppStorage at top of `enhance(...)`**

Around line 64 of `MLXProvider.swift` (after `let totalStart = Date()`):

```swift
// W11.A5: honor user-set EnhancementTimeoutSeconds (default 7s) for the
// whole enhance call. Caps worst-case rambling MLX outputs the same way
// remote-API providers are already capped.
let timeoutSeconds = TimeInterval(
    UserDefaults.standard.integer(forKey: "EnhancementTimeoutSeconds")
)
let effectiveTimeout = timeoutSeconds > 0 ? timeoutSeconds : 7.0
```

Note: `MLXProvider` is an actor — reading `UserDefaults.standard` inside an actor is safe (UserDefaults is thread-safe). No need to MainActor-hop.

- [ ] **Step 5.2: Wrap the whole enhance body in a TaskGroup with a timeout sibling**

Restructure `enhance(...)` body around line 64-142:

```swift
return try await withThrowingTaskGroup(of: String.self) { group in
    group.addTask { [self] in
        // … existing enhance body returning the output string …
        return output
    }
    group.addTask {
        try await Task.sleep(nanoseconds: UInt64(effectiveTimeout * 1_000_000_000))
        Self.logger.warning("🦾 enhance: TIMEOUT after \(effectiveTimeout, format: .fixed(precision: 1), privacy: .public)s — cancelling generation")
        throw ProviderError.generationFailed("Timed out after \(Int(effectiveTimeout))s")
    }
    let result = try await group.next()!
    group.cancelAll()
    return result
}
```

Coder discretion on whether to extract the enhance body into a helper to keep the `withThrowingTaskGroup` block readable — likely yes given it's ~80 lines.

- [ ] **Step 5.3: Confirm cancellation propagates**

mlx-swift-lm's `TokenIterator` honors `Task.isCancelled` per R2 §B2. The existing `if Task.isCancelled { break }` at line 111 inside the stream loop catches it. So when the timeout-task throws, the group cancels the generation-task; the iterator sees `isCancelled` and breaks; control returns to the catch which throws our `ProviderError.generationFailed("Timed out...")`.

- [ ] **Step 5.4: Confirm A3 cache state on timeout**

A timeout that fires mid-prefill leaves the cache in an unknown state — invalidate. Already covered by §Step 3.3's `catch` block invalidation, but call out explicitly: the `catch is CancellationError` arm at line 137 should ALSO call `invalidatePrefillCache()` since A5 cancels via cancellation propagation.

**Risk:** LOW — concurrency idiom is standard `withThrowingTaskGroup`. The R2 §P0-4 fix sketch describes exactly this shape. Reviewer's main concern would be: does cancelling the prefill leave any GPU state half-allocated? Per mlx-swift-lm's `MLX.GPU.flush(...)` semantics, no — autoreleased weights free at the next allocation cycle.

Per R2 §H2: caps 16-64s rambling cases at the user's existing 7s setting (or whichever value they've picked).

**Verification:** type-check passes. Manual: in dev, set `EnhancementTimeoutSeconds = 1` via the picker, dictate something → expect the WARN line + raw-transcript fallback in the UI. Reset to 7 after.

---

### Task 6: A6 — `idleEvictSeconds` configurable

**Files:**
- Modify: `VoiceInk/AppDefaults.swift`
- Modify: `VoiceInk/Services/AIEnhancement/AIService.swift`
- Modify: `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`

- [ ] **Step 6.1: Register the default**

In `AppDefaults.swift` around line 45 (alongside `"EnhancementTimeoutSeconds": 7`):

```swift
"MLXIdleEvictSeconds": 1800,  // W11.A6: 30 min — was hardcoded 600s in MLXProvider init
```

- [ ] **Step 6.2: Read from AppStorage at the `MLXProvider` call site**

In `AIService.swift:282`, current:

```swift
let provider = MLXProvider(modelId: modelId, idleEvictSeconds: 600)
```

becomes:

```swift
let evictSeconds = TimeInterval(
    UserDefaults.standard.integer(forKey: "MLXIdleEvictSeconds")
)
let resolvedEvict = evictSeconds > 0 ? evictSeconds : 1800
let provider = MLXProvider(modelId: modelId, idleEvictSeconds: resolvedEvict)
```

- [ ] **Step 6.3: Add the slider to `EnhancementSettingsPanel`**

Append a new Section inside the existing `Form` (after the `"Last Sent System Prompt"` section at line 161-168, or wherever the layout flow makes most sense):

```swift
Section {
    HStack {
        Text("Idle eviction")
        Spacer()
        Picker("", selection: $mlxIdleEvictSeconds) {
            Text("60 seconds").tag(60)
            Text("5 minutes").tag(300)
            Text("10 minutes").tag(600)
            Text("20 minutes").tag(1200)
            Text("30 minutes").tag(1800)
            Text("45 minutes").tag(2700)
            Text("1 hour").tag(3600)
            Text("Never").tag(Int.max)
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
} header: {
    HStack(spacing: 4) {
        Text("MLX (on-device)")
        InfoTip("How long the on-device model stays in memory after the last enhancement. Higher values trade memory for fewer cold-load spikes; lower values free memory faster.")
    }
}
```

The new `@AppStorage`:

```swift
@AppStorage("MLXIdleEvictSeconds") private var mlxIdleEvictSeconds = 1800
```

Coder discretion on whether to gate this Section behind `aiService.selectedProvider == .mlx` — recommended yes (Section disappears for non-MLX users; reduces UI clutter).

**Risk:** LOW — pure UI + AppStorage round-trip. The `Int.max` "Never" sentinel maps to a 68-year sleep before eviction inside `scheduleEvictionCheck()` at `MLXProvider.swift:226-227`. Effectively "never" for any real user session. (If we wanted true never-evict, the cleaner change is to skip scheduling the eviction task entirely when `idleEvictSeconds == Int.max` — coder may add that conditional inside `scheduleEvictionCheck()` for tidiness.)

**Verification:** type-check passes. Manual: open Enhancement Settings panel, see the new MLX section with the picker. Change value; confirm the next `MLXProvider` instance instantiated uses the new value (read it from a debug log or by waiting out the old vs new threshold).

---

### Task 7: A7 — `max_tokens` heuristic

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXProvider.swift`

- [ ] **Step 7.1: Update the heuristic at lines 79-80**

Current:

```swift
let approxInputTokens = userPrompt.count / 4
let dynamicMaxTokens = max(192, min(768, approxInputTokens * 3))
```

becomes:

```swift
// W11.A7: floor 192→96 for very-short transcripts (<30 chars); ceiling
// 768→512 universally. Real cleanup output is 80-200 tokens; 512 is still
// 2.5× expected. See plan §Migration policy #10 + R2 §H2.
let approxInputTokens = userPrompt.count / 4
let floor = userPrompt.count < 30 ? 96 : 192
let dynamicMaxTokens = max(floor, min(512, approxInputTokens * 3))
```

**Risk:** LOW — bounded heuristic change. Worst case: a 30-token-output cleanup of a 5-char input is now capped at 96 tokens (was 192) — still 3× the realistic output. The 512 ceiling drops the worst-case generation budget by ~33%, helping the WARN-line frequency (matters even more after A5 caps wall-clock).

**Verification:** type-check passes. Post-merge capture: `maxTokens=N` value in the `prep` log line should show 96/192/512 boundaries instead of 192/768.

---

### Task 8: Static checks (coder-runnable, no dictation)

**Files:** none (read-only verification).

- [ ] **Step 8.1: Confirm all touched files compile in isolation via SourceKit**

The coder's environment runs SourceKit live during edits. Verify:
- No undefined-symbol errors after each task.
- `MLXProvider.swift` imports `CryptoKit` (added by A3 for SHA-256).
- `EnhancementSettingsPanel.swift`'s new `@AppStorage` is bound, the Section renders without compile error.

- [ ] **Step 8.2: Confirm no orphan references to old constants**

```bash
grep -rn "topP: 0.9\|idleEvictSeconds: 600\|max(192" VoiceInk --include="*.swift"
```

Expected: zero matches in `Services/AIEnhancement/`. If grep returns matches in test files or non-MLX provider code, reconcile — A4/A6/A7 should have eliminated all in-scope occurrences.

- [ ] **Step 8.3: Confirm prewarm wiring**

```bash
grep -rn "warmMLX\b\|warmMLXIfSelected\|MLXIdleEvictSeconds\|MLXShortTranscriptCharThreshold\|shortTranscriptCleanupTemplate" VoiceInk --include="*.swift"
```

Expected: each symbol appears ≥2 times (definition + at least one call site).

- [ ] **Step 8.4: Confirm A5 timeout key reuse**

```bash
grep -rn "EnhancementTimeoutSeconds" VoiceInk/Services/AIEnhancement
```

Expected: matches in `AIEnhancementService.swift:74` (existing — for remote APIs) AND `MLXProvider.swift` (new — for A5). Both read the same key.

---

### Task 9: Integration build + post-merge re-capture

**Files:** none (verification + report).

- [ ] **Step 9.1: Single integration build**

```bash
make local
```

Expected: clean build. If it fails:
- Most likely cause: A3's `TokenIterator` driver doesn't match the actual mlx-swift-lm 3.31.3 API. Re-read `Evaluate.swift` in the framework and tighten the call.
- Second-most-likely: A5's `withThrowingTaskGroup` capture-list issue (actor isolation + Sendable). Use `[self]` capture and ensure the inner task body is `@Sendable`.
- Third-most-likely: A2's prompt-template typo or missing `import` in `AIPrompts.swift`.

Per CLAUDE.md cadence, this is the only build run during the packet.

- [ ] **Step 9.2: One smoke dictation pass**

Pick MLX with the active model (Qwen3-4B-Instruct-2507 default). Run one long-ish dictation (100-300 words). Verify in Console:
- `🦾 enhance: total=…s` appears.
- `🦾 enhance: KV-cache MISS` appears (first run after build).
- No `🦾 enhance: TIMEOUT` line.
- No new errors in any subsystem.

Run a second dictation immediately. Verify:
- `🦾 enhance: KV-cache HIT` appears.
- `ttft` is meaningfully lower than the first run's `ttft`.

If both spot-checks pass, the packet is shippable. If either fails, reconcile before merge — the failing fix is the candidate for §Migration policy #11 deferral.

- [ ] **Step 9.3: User-side post-merge re-capture**

After the code commit lands, the user repeats the 5-dictation protocol from §Pre-merge ground-truth gate. The post-W11.A capture lives at:

`docs/superpowers/research/2026-04-29-postW11A-enhance-timings.md`

Side-by-side comparison vs the baseline gives the per-fix yield. The user (or a follow-up packet) can also use these numbers to refine the W10 `expectedLatencySeconds` ranges if they still feel off.

- [ ] **Step 9.4: Coder report to lead**

Send the lead:
- Confirmation of which A-fixes landed (all 7) and which (if any) deferred per §Migration policy #11.
- Build status.
- Smoke-dictation Console log (KV HIT, no TIMEOUT, no errors).
- `EnhancementSettingsPanel.swift` screenshot of the new MLX section (optional but useful).
- Any architectural surprises encountered (especially around A3's TokenIterator driver).

The lead handles the two commits + push + final handoff doc.

---

## Test plan

Per master plan §0 Q10 (test-infra deferred): no `xcodebuild test` runs. Validation is build-only via `make local` (Task 9.1) plus smoke dictation (Task 9.2) plus user-side post-merge re-capture (Task 9.3).

**What `xcodebuild build` runs:**
- Single `make local` invocation at Task 9.1. ~3 min cold; warm rebuilds are seconds.

**What the user does for smoke validation:**
- Coder smoke (Task 9.2): one short + one long dictation immediately post-build, on the default MLX model. Verify `KV-cache MISS` then `KV-cache HIT` log progression.
- User re-capture (Task 9.3): repeat the 5-dictation protocol from §Pre-merge ground-truth gate against the post-merge build. Compare to the baseline doc. Expect:
  - **#1 cold first** total drops by 1.5-4s (A1 prewarm should mostly avoid cold-load if user has `PrewarmModelOnWake = true`; if false, A2 + A3 + A7 still help).
  - **#2 warm short** total drops by 1.5-3s (A2 fast-path fires; A3 cache hits).
  - **#3 warm medium** total drops by 0.5-1.5s (A3 cache hits dominate).
  - **#4 warm long** total drops slightly (A4 + A7; A2 fast-path doesn't fire; A3 cache hits the system prefill).
  - **#5 cold-after-idle** behaves like #1 if eviction fired in those 11 minutes; A6's new 30-min default means eviction does NOT fire if the user keeps the default. **Test scenario change:** the user should re-run #5 with `MLXIdleEvictSeconds = 600` to force eviction and capture the still-cold case for parity with the baseline.
- WARN frequency: post-merge `🦾 enhance: WARN total=…s exceeds 10s ceiling` should fire much less often (most cases now bounded by A5's 7s timeout, well under 10s).
- TIMEOUT log: `🦾 enhance: TIMEOUT after Xs` should fire only when the user sets `EnhancementTimeoutSeconds` aggressively low or hits a true-rambling output. Should be rare.

If any of those expected drops doesn't materialize, the packet is partially regressing — re-investigate and consider §Migration policy #11 deferral of the suspect fix.

---

## Rollback plan

**Single-commit packet → `git revert <code commit sha>` restores the entire pre-W11.A behavior.** Plan doc commit stays (not reverted) so the historical record is preserved.

**Why squashed-not-split (vs. W10's three-commit boundary):**
- W10 swapped three independent registry rows → granular revert per row mattered.
- W11.A's seven fixes are interdependent (A3's KV-cache invalidation interacts with A5's timeout; A1's warm path leans on A6's evict policy; A4 + A7 share the GenerateParameters/heuristic file region). Splitting into seven commits would create a brittle revert matrix where reverting just A3 might leave A5 in an inconsistent state.
- Counter-argument: per §Migration policy #11, the coder may DEFER any A-fix at land time. If that happens, the ACTUAL commit is "W11.A minus the deferred fix". Subsequent packets re-add the deferred fix.

**Per-fix surgical revert** (if a single fix turns out worse):
- **A1 prewarm regress:** comment out the call site in `VoiceInkEngine.swift:206-229` and the `case .mlx` arm in `ModelPrewarmService.shouldPrewarm()`. Keep the helpers (`warmMLX`, `warmMLXIfSelected`) — they're harmless when uncalled.
- **A2 fast-path regress:** flip the `useFastPath` conditional to `false` unconditionally (or set `MLXShortTranscriptCharThreshold = 0`). Restores full-prompt behavior for all cases.
- **A3 KV-cache regress:** in `enhance(...)`, force `cacheReusable = false` always (or set `prefillCacheKey = nil` at the top of every call). Cache becomes one-shot, equivalent to pre-A3.
- **A4 sampler regress:** revert `temperature: 0.0` → `temperature: 0.1, topP: 0.9` (one line).
- **A5 timeout regress:** remove the `withThrowingTaskGroup` wrap. Enhance falls back to "bounded by mlx-swift-lm's max-tokens cap only" (current pre-A5 behavior).
- **A6 evict regress:** in `AIService.swift`, hard-code `idleEvictSeconds: 600` again (one-line revert at the call site). The new AppStorage key + Settings UI become dead — clean up in a follow-up.
- **A7 max_tokens regress:** revert the heuristic to `max(192, min(768, ...))` (one line).

**Detection signals** (which production data tells us a revert is needed):
- User reports cleanup output is visibly worse vs memory of pre-W11.A → A2 (fast-path too eager) or A4 (greedy sampler unexpected) most likely.
- `🦾 enhance: KV-cache HIT` appears but `ttft` doesn't drop → A3's TokenIterator driver isn't actually reusing the cache (the iterator constructor might silently rebuild). Re-investigate; revert A3 if unfixable.
- `🦾 enhance: TIMEOUT` fires on every call → A5's timeout reads the wrong AppStorage key, or `effectiveTimeout` has a unit-conversion bug.
- App memory bloat after a long session → A3's two-slot policy is leaking; check that `reset()` actually frees both slots.
- `🦾 warmMLX failed` log spam → A1's warm path is racing against an in-progress download or a partial cache state. Investigate; revert A1 prewarm if unfixable.

**Blast radius of a full revert:** zero data loss. All edits are in-memory state + AppStorage keys. The user's `MLXIdleEvictSeconds = 1800` AppStorage value would persist after revert but the read code path is gone — harmless dead state. Cleanup in any follow-up that touches the AppDefaults dictionary.

---

## Risks / unknowns

1. **A3 KV-cache TokenIterator driver complexity.** Highest-risk fix in the packet. The mlx-swift-lm 3.31.3 prompt-cache APIs are real (PR #155 confirms) but the exact shape of `TokenIterator(input:model:cache:parameters:)` and how it composes with `ModelContainer.perform` is non-obvious from the existing `container.generate(...)` usage. **Mitigation:** coder spends Task 0 (read-only) reading `Evaluate.swift:585-604` AND `:1184-1208` AND any LLMEval example before touching code. If it looks like reimplementing too much of `runSynchronousGenerationLoop`, defer A3 per §Migration policy #11. Expected yield: -150-400ms ttft on warm 2nd-onward enhance — meaningful but not catastrophic to defer.

2. **A1 prewarm + ModelPrewarmService dependency injection.** The current `ModelPrewarmService` doesn't hold an `AIEnhancementService` reference. Threading one through requires touching the app-level service container (likely `VoiceInkApp.swift` or whatever wires the env objects at app launch). **Mitigation:** if injection is awkward, fall back to `NotificationCenter` posting (`enhancement.warmRequested`) with `AIEnhancementService` as the observer. Trade-off: looser coupling but harder to reason about ordering. Coder picks at land time; flag in report.

3. **A2 fast-path + custom prompt body.** The fast-path swaps the entire system message — including any user-customized prompt body. If the user has a non-default custom prompt active (e.g. their own "Email" template), the fast-path bypasses it and emits cleanup-only output. This may surprise users who expect the active prompt to govern. **Mitigation:** v1 ships the simple heuristic (≤30 tokens AND no context); if reported as confusing, tighten the conditions to require the active prompt be `PredefinedPrompts.defaultPromptId`. Punted to follow-up.

4. **A2 token-count heuristic precision.** `userPrompt.count / 4` is a rough char-to-token estimate — varies 2-3× per language / vocabulary. A 30-token threshold computed via `count <= 120` chars may fast-path 25-token English transcripts but skip 35-token Mandarin transcripts. **Mitigation:** the heuristic's worst case is "fast-path didn't fire when it could have" — which means the user pays the full prompt prefill, which is the exact behavior pre-W11.A. No regression possible; only a missed opportunity. Refine in a follow-up if user reports a specific case.

5. **A1 warm fires while download is in progress.** If the user just opened the picker to download a model and starts a recording before the download completes, `MLXModelDownloader.status(for:)` returns `.downloading` and `warmMLX()` skips early (Step 1.2 check). When the download completes, no automatic warm fires until the next `Task.detached` from a recording-start OR the next `ModelPrewarmService.performPrewarm()` trigger (wake/launch). **Mitigation:** acceptable. The first enhance after download completes pays cold-load — same as pre-W11.A behavior.

6. **A5 wall-clock timeout includes load + prep time.** Per Migration policy #8, the timeout covers the whole `enhance()` call. A user with `EnhancementTimeoutSeconds = 7` who hits a 4s cold-load gets only 3s of generation budget — likely insufficient for a long output. **Mitigation:** A1 + A6 default-to-30-min-evict means cold-load should rarely fire if prewarm is on. If user hits this, raise `EnhancementTimeoutSeconds`. Could be confusing UX; flag in user-facing release notes.

7. **A6 idle-evict slider granularity.** The picker tag stops are 60/300/600/1200/1800/2700/3600/Int.max. If a user has a strong preference for, say, 90s, they have no UI affordance — they'd need to manually edit the `MLXIdleEvictSeconds` AppStorage via `defaults write`. **Mitigation:** v1's stops cover 99% of intent. Custom-stop UI (a free-form number field) is over-engineering for the first cut.

8. **No telemetry on per-fix yield.** We can observe `total=…s` per-cycle but no aggregate metric exists in-app. The user manually compares baseline vs post-merge captures. **Mitigation:** acceptable for a single-user fork. If multi-user telemetry ever lands, A1-A7 each contribute a measurable delta.

9. **Test infra deferred per Q10.** `xcodebuild test` env-blocked. Means no automated regression catch for any of these fixes. **Mitigation:** smoke dictation (Task 9.2) is the gate. If the post-merge re-capture (Task 9.3) shows no improvement, we've shipped a no-op packet — embarrassing but recoverable. Test unblock is a separate session.

10. **AFM (W11.B) and spec-decode (W11.C) interactions.** W11.A doesn't touch AFM or spec-decode paths. When W11.B lands and AFM becomes the primary path, MLX is fallback only. The W11.A wins still help that fallback path (which is what most non-AI-enabled-Mac users hit). When W11.C adds the speculative-decoding toggle, it intersects A3's KV-cache (the speculative draft has its own cache) and A4's greedy decode (speculative decoding requires deterministic target sampling — temp=0.0 is exactly right). So W11.A's choices are **forward-compatible**. Flag for the W11.B/C planners as a constraint.

---

## Out of scope (explicit) for follow-ups

- **AFM (Apple Foundation Models) primary path.** This is W11.B — separate packet. Master plan §2 W11.B has the scope.
- **Speculative decoding for MLX.** This is W11.C — separate packet (master plan §2 W11.C, gated on Q3=c "Use speculative decoding" toggle).
- **`mlx-swift-lm` framework bump.** Research §"Framework compatibility" + R2 §H8 confirm 3.31.3 is the latest; no upgrade needed for any W11.A fix. Stays deferred.
- **Custom-prompt-aware fast-path tightening.** Per §Risks #3, if A2 fast-path surprises users, future packet can require the active prompt be the System Default before fast-path fires. Out of scope for v1.
- **MLX-specific timeout knob (separate from `EnhancementTimeoutSeconds`).** Per Migration policy #7, A5 reuses the existing remote-API timeout key. If user wants different timeouts per provider, that's a follow-up settings expansion.
- **MLX-retry-on-timeout.** Per Migration policy #7, the existing `EnhancementRetryOnTimeout` AppStorage is honored by remote APIs only; A5 treats it as advisory and does NOT retry MLX on timeout. Follow-up if user wants retry.
- **Custom idle-evict stops.** Per §Risks #7, picker stops are fixed; free-form number field is a follow-up.
- **AppStorage migration from old `idleEvictSeconds = 600` hardcoded value.** None needed — old behavior was a code constant, not an AppStorage key. Users land on the new 1800 default at first launch post-W11.A.
- **Telemetry on `🦾 enhance:` line aggregation.** Out of scope; would require a `MetricsRegistry` surface and is a separate packet.
- **`Skip short transcriptions` interaction with A2 fast-path.** Existing `SkipShortEnhancement` AppStorage (default 3 words) bypasses enhance ENTIRELY for very short inputs — runs BEFORE the MLX call site. Orthogonal to A2 (which kicks in only when enhance runs). No interaction; flag in case the user conflates them in a future report.
- **MLX prewarm gating switch separate from `PrewarmModelOnWake`.** Per Migration policy #2. Follow-up if user reports they want MLX-specific prewarm without prewarm for transcription models.
- **Refining W10 `expectedLatencySeconds` placeholders.** Post-W11.A captures might show much-improved latency for the curated lineup. Tightening those ranges is a separate cosmetic packet — not blocking.
- **Test infrastructure unblock.** Per master plan §0 Q10. Separate session.
- **AppStorage key namespacing.** All W11.A AppStorage keys are flat strings (`MLXIdleEvictSeconds`, `MLXShortTranscriptCharThreshold` future, etc.). Future cleanup could namespace under `enhancement.mlx.*`. Out of scope.

---

## Notes for the lead

- **Pre-merge ground-truth gate is the load-bearing wall.** Without the baseline capture, the post-merge re-capture has nothing to compare against — the packet's value is unverifiable. Block the code commit on the `2026-04-29-baseline-enhance-timings.md` file existing.
- **Two commits, not one.** Plan doc lands first (`docs(plans): W11A — pipeline fixes plan`). Code lands after baseline-capture-gate clears (`feat(mlx): W11A — pipeline fixes (...)`).
- **Defer order is real, not theoretical.** A3 is the most likely deferral candidate. If the coder reports that the TokenIterator driver feels half-implemented, defer A3 to a focused follow-up packet — A1 + A2 + A4 + A5 + A6 + A7 still ship a meaningful win.
- **No new tests.** Build is the gate. Per Q10 deferral.
- **One integration build.** Per `feedback_skip_per_packet_builds.md`. Coder does NOT run `make local` during execution.
- **Forward compatibility with W11.B/C.** A4's greedy decode is exactly what speculative decoding (W11.C) needs from the target model. A3's KV-cache reuse is conceptually compatible with the speculative draft's separate cache. Flag for the W11.B/C planners.
- **Open questions:** none. All 10 master-plan questions resolved (§0). Only execution-time discretion left to the coder is the A3 TokenIterator driver shape (Migration policy #5) and the A1 dependency-injection vs notification choice (Risks #2). Both flagged in the report-to-lead at Task 9.4.
