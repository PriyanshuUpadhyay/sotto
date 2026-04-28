# W10 — MLX Registry Swap + Sequential Pre-Merge Testing Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.
>
> **CRITICAL pre-merge constraint:** hardware testing is **SEQUENTIAL** — one model downloaded, dictation-cycled, and WARN-line captured at a time. **Never parallel.** Per user instruction in the W10 packet brief.

**Goal:** Replace the curated MLX rewriting lineup with the Apache-2.0 Qwen3 family per the W10 research recommendation. Swap `gemma-4-e2b-it-4bit` (slow per user report) → `Qwen3-1.7B-4bit-DWQ`. Swap `gemma-4-e4b-it-4bit` (slow) → `Qwen3-4B-Instruct-2507-4bit-DWQ-2510`. Hard-drop the experimental `gemma-4-26b-a4b-it-4bit` 14 GB MoE entry per user's "smaller the model, the better the speed" directive. Keep `Qwen3.5-4B-MLX-4bit` (IFEval 89.8 — best in class). Run a sequential one-model-at-a-time hardware pass on the user's M-base 32 GB to refine `expectedLatencySeconds` ranges from research extrapolations to ground truth before final commit.

**Architecture (curated lineup post-W10):**

```
MLXModelRegistry.curated  (3 entries — was 4)
  ├── mlx-community/Qwen3-1.7B-4bit-DWQ          [Fastest tier]
  │     ~0.97 GB · qwen3 type · Apache 2.0 · IFEval ~65-75 (family extrapolation)
  │     replaces: mlx-community/gemma-4-e2b-it-4bit
  │
  ├── mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510   [Default mid]
  │     ~2.26 GB · qwen3 type · Apache 2.0 · IFEval 88.9 · Arena-Hard 43.4
  │     replaces: mlx-community/gemma-4-e4b-it-4bit
  │
  └── mlx-community/Qwen3.5-4B-MLX-4bit                    [High-quality]
        ~3.0 GB · qwen3_5 type · Apache 2.0 · IFEval 89.8
        UNCHANGED — kept (best small-model IFEval in this entire research field)

DROPPED entirely:
  • mlx-community/gemma-4-26b-a4b-it-4bit  (14 GB MoE — user explicitly disprefers; research recommends DROP not relabel)
  • mlx-community/gemma-4-e2b-it-4bit      (replaced — slow per real-world dictation; PLE-quant warning retired)
  • mlx-community/gemma-4-e4b-it-4bit      (replaced — slow per real-world dictation; gemma → Qwen Apache parity)
```

**Architecture (rollback granularity):**

The registry edit MUST land as **three sequential commits** — not one — so any single swap can be reverted via `git revert <sha>` without unwinding the others. Order:

```
commit A:  feat(mlx): drop 26B-a4b experimental tier   ← isolated; lowest blast radius
commit B:  feat(mlx): swap e2b → Qwen3-1.7B-DWQ        ← fastest tier; user-visible default
commit C:  feat(mlx): swap e4b → Qwen3-4B-Instruct-2507 ← mid tier; routes most traffic
```

If any swap surfaces worse than gemma in production, `git revert` of the corresponding commit restores that single entry without touching the other two. See **§Rollback story** below for the user-facing scenario tree.

**Tech Stack:** Swift 5.x, MLX-swift (mlx-swift-lm 3.31.3 + swift-huggingface 0.9.0). No framework bump required — research §"Framework compatibility" confirms every Qwen3 candidate's `model_type: qwen3` is registered in the bundled `LLMTypeRegistry.shared`. Build via `make local` (~3 min cold), once at merge time.

**Spec refs:**
- Research: `docs/superpowers/research/2026-04-29-mlx-rewriting-models.md` (TL;DR table + §"Open follow-ups for the registry-swap packet" #1-6)
- W6 plan precedent: `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` §Migration policy #1 (registry tier semantics) + §Risks/unknowns #2 (M-base ground truth caveat)
- Driver: `docs/superpowers/handoffs/HANDOFF_post_redesign_open_asks_2026-04-29.md` §Ask 3

**CLAUDE.md cadence rules respected:**
- **Single build at merge time.** No `make local` per task; one full integration build at Task 9 (after all three registry edits land).
- **Three commits at merge time.** Lead handles commits; coder leaves edits staged-but-uncommitted with the three-commit boundary noted in the report.
- **No `xcodebuild` per file.** SourceKit handles per-file syntax during edits.
- **Sentence-fragment commits, no emojis in code.** Existing `🦾` log markers in `MLXProvider.swift` are pre-existing instrumentation and stay (W6 precedent).
- **Pre-existing spec-ref comments stay.** New comments only when WHY is non-obvious.

**Sequential hardware testing — non-negotiable.** Per user's explicit instruction in the W10 packet brief: "Just make sure that you are not doing it in parallel." Each model is downloaded, dictation-cycled, and observed via the existing `🦾 enhance: total=…s` notice line and the `🦾 enhance: WARN total=…s exceeds 10s ceiling` warning line (both already wired in `MLXProvider.swift:132-135`) **before** the next model begins downloading. Plan §Tasks 5-7 codifies the exact loop. The coder cannot run dictation; this pass happens on the user's machine only.

---

## File structure

### New files

None. W10 is a registry data-only swap + risk-mitigation observability — no new types, no new views.

### Modified files

- `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift` — swap two `MLXModelEntry` rows + delete one. Update the `enum MLXModelRegistry` doc comment to reflect "three-tier Qwen-only Apache 2.0 lineup as of W10". The `MLXModelEntry` struct itself UNTOUCHED (the four ratings fields added in W6 stay; only their values are rewritten in the new entries). ~+30 LOC, -25 LOC across three commits combined.

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Services/AIEnhancement/MLXModelEntry` struct shape — UNTOUCHED. The W6-introduced `speedRating` / `qualityRating` / `expectedLatencySeconds` / `isExperimental` fields stay; W10 only writes new values into them. Do NOT re-define the struct, the explicit init, or the doc comments on the field declarations.
- `VoiceInk/Services/AIEnhancement/MLXProvider.swift` — UNTOUCHED. The `enhance(...)` body (lines 59-146) is the diagnostic surface we depend on for sequential testing; the existing `🦾 enhance: total=…s` notice (line 132) and `🦾 enhance: WARN total=…s exceeds 10s ceiling` warning (line 134) already capture exactly the data we need per-model. Do NOT add new logging — reuse what's there.
- `VoiceInk/Services/AIEnhancement/AIService.swift` — UNTOUCHED. The MLX provider cache (lines 268-282) re-reads `selectedModelId` from `@AppStorage` and rebuilds an `MLXProvider` per `modelId`, so registry id changes flow through automatically when the user picks a new entry from the picker. No code path needs updating.
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` — UNTOUCHED. The MLX call sites (lines 257, 513) only branch on `MLXProvider.ProviderError`; they don't case on specific model ids.
- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` — UNTOUCHED. The picker reads `MLXModelRegistry.curated` and renders rows generically; new entries render with the same Speed/Quality/latency/size chips as old ones. The W9 FlowLayout chip-strip wrapping handles narrower repo names cleanly. No view code changes for this packet.
- `VoiceInk/Services/AIEnhancement/MLXModelDownloader` (lines 119-207) — UNTOUCHED. `swift-huggingface` resolves any `mlx-community/<repo>` snapshot under the same hub cache layout; new repo ids download via the same path.
- `VoiceInk/Services/AIEnhancement/MLXModelRegistry.purgeLegacyApplicationSupportModelsIfPresent()` (lines 211-258) — UNTOUCHED. The W6 legacy migration is unrelated; runs once on app start.
- All test files (`VoiceInkTests/*.swift`) — W10 ships no new tests. The data swap has no logic surface to unit-test (the picker renders generically; the provider routes generically). The integration build at Task 9 is the gate.
- W9 FlowLayout (`VoiceInk/Views/Common/FlowLayout.swift` if it exists, or wherever `cd05525` landed it) — UNTOUCHED.

---

## Migration policy (resolves ambiguity for each design point)

The lead pinned 7 architecture decisions for this packet. Restated as the authoritative ruleset for the coder.

1. **Curated lineup as of W10 land.** Final three entries in `MLXModelRegistry.curated`, in this order:
   1. `mlx-community/Qwen3-1.7B-4bit-DWQ` — fastest tier replacement.
   2. `mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510` — default mid replacement.
   3. `mlx-community/Qwen3.5-4B-MLX-4bit` — high-quality KEEP.

   Drop entirely: `gemma-4-e2b-it-4bit`, `gemma-4-e4b-it-4bit`, `gemma-4-26b-a4b-it-4bit`. Net: 4 entries → 3.

2. **DWQ-variant preference, plain `-4bit` as fallback.** Both Qwen3-1.7B and Qwen3-4B-Instruct-2507 have a standard `-4bit` and a DWQ (Distilled / Dynamic Weighted Quant) variant. Research §Risks #3 flags DWQ as newer (mlx-lm 0.28.2 conversion, lower download counts than the standard `-4bit`). Picked DWQ for both because the perplexity recovery is meaningful and the Swift loading path is identical (same safetensors format, same `qwen3` type-registry hit). **If pre-merge sequential testing surfaces DWQ-specific issues** (load failure, quality regression vs the gemma baseline, or a runtime error citing weight-shape mismatch), the fallback is a one-token edit per row: `-DWQ` → `` (empty) for 1.7B and `-DWQ-2510` → `` for 4B. See Task 8 below.

3. **Hard-drop the 26B-A4B experimental entry — do not relabel.** W6 plan §Migration policy #3 kept the 26B-A4B entry with `isExperimental: true` because the user had expressed interest in trying it. The W10 research and the W10 packet brief BOTH supersede that — user has now stated "smaller the model, the better the speed" and "skip 13B+ as too slow to be worth testing." We hard-drop. The `isExperimental` field stays on the struct as a future hook (no entries set it after this packet, but that's harmless dead code per W6 §Risks #3).

4. **Do NOT bring back any 13B+ candidates as a fallback.** Per the packet brief explicit instruction. The "Other candidates evaluated" section of the research lists Llama-3.2-3B (Llama community license), Llama-3.2-1B, Phi-3.5-mini-instruct (MIT), and granite-3.3-2b-instruct (Apache 2.0) — all sub-4B. If a Qwen3 candidate fails, fallback options come from THIS sub-4B set, not from any larger-model list. The Llama-3.2-3B Open-Rewrite 40.1 score is tempting per research §"Other candidates evaluated", but the license adds attribution friction and the user has not asked for it.

5. **`expectedLatencySeconds` is a placeholder pre-merge — final values come from sequential hardware testing.** Research §Candidate comparison gives extrapolated bands (1.7B-DWQ: 1-3s; 4B-Instruct-2507: 2-5s) but research §Risks #1 explicitly flags M-base 32 GB ground truth as unmeasured. **Coder lands the placeholder ranges in the registry edits, then the user runs Task 6 dictation cycles on their hardware and reports back the observed `🦾 enhance: total=…s` numbers; the user (or the lead in a follow-up tightening packet) updates the ranges in-place after testing.** The placeholder is honest because the picker chip already says "Expect 1-3s" not "Will take 1.7s" — a band, not a guarantee, matching the W6 plan precedent §Risks #2.

6. **Three-commit boundary for granular revert.** Per the §Architecture rollback note above. Coder leaves the edits as three logical chunks the lead can split into commits A/B/C at merge time. The simplest realization: coder makes three sequential `Edit` calls on `MLXModelRegistry.swift` — first deletes the 26B entry, second swaps e2b → Qwen3-1.7B, third swaps e4b → Qwen3-4B — and the lead splits via `git add -p` if needed. Coder does NOT commit (CLAUDE.md cadence: lead handles commits).

7. **No emoji in registry text.** Notes fields stay plain text. The existing `🦾` markers belong to `MLXProvider.swift` log instrumentation only and don't propagate to `MLXModelEntry.notes` strings (which render in the picker UI). Do NOT add emoji to the new notes copy.

---

## Tasks

### Task 0: Audit + read references

**Files:** none (read-only).

- [ ] **Step 0.1: Confirm the curated registry shape is unchanged from W6**

```bash
grep -n "MLXModelEntry\|curated:\|gemma-4-e2b-it-4bit\|gemma-4-e4b-it-4bit\|Qwen3.5-4B-MLX-4bit\|gemma-4-26b-a4b-it-4bit" VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift
```

Expected: `struct MLXModelEntry: Identifiable, Hashable` at line 10, `static let curated: [MLXModelEntry] =` at line 70, and four `id:` lines for the four current entries (e2b, e4b, Qwen3.5, 26b). If grep returns a different shape (e.g. the array has been edited since W6), reconcile with the lead before proceeding — the diff in this plan assumes the W6 lineup is intact.

- [ ] **Step 0.2: Confirm no other surface depends on the dropped/renamed model ids**

```bash
grep -rn "gemma-4-e2b-it-4bit\|gemma-4-e4b-it-4bit\|gemma-4-26b-a4b-it-4bit" VoiceInk --include="*.swift"
```

Expected: matches ONLY in `MLXModelRegistry.swift` (the four `id:` lines plus the doc-comment example at line 11). If grep surfaces matches in `MLXModelPickerView.swift`, `AIService.swift`, `AIEnhancementService.swift`, or anywhere in `VoiceInkTests/`, reconcile with the lead before editing. The picker reads `MLXModelRegistry.curated` generically; no view should hardcode a model id.

- [ ] **Step 0.3: Confirm the WARN log line format used by the sequential hardware pass**

```bash
grep -n "🦾 enhance: total\|🦾 enhance: WARN" VoiceInk/Services/AIEnhancement/MLXProvider.swift
```

Expected:
- Line 132: `Self.logger.notice("🦾 enhance: total=\(totalElapsed, format: .fixed(precision: 2), privacy: .public)s")`
- Line 134: `Self.logger.warning("🦾 enhance: WARN total=\(totalElapsed, format: .fixed(precision: 2), privacy: .public)s exceeds 10s ceiling for model=\(self.modelId, privacy: .public)")`

Both lines are the diagnostic surface the user will use to fill in `expectedLatencySeconds`. Do NOT modify these.

- [ ] **Step 0.4: Confirm `selectedModelId` reactivity flows through the existing path**

```bash
grep -n "selectedModelId\|notifyMLXSelectionChanged\|mlxProviderCache" VoiceInk/Services/AIEnhancement/AIService.swift VoiceInk/Views/AI\ Models/MLXModelPickerView.swift
```

Expected: the picker writes `selectedModelId` via `@AppStorage("mlx_selected_model_id")` (line 16) and calls `aiService.notifyMLXSelectionChanged()` after selection / download / delete; `AIService.mlxProvider(for:)` (line 273) rebuilds an `MLXProvider` keyed on the new id and evicts the old one (line 277-281). Path is generic over model id — no per-id branching. New Qwen3 ids flow through unchanged.

---

### Task 1: Drop the `gemma-4-26b-a4b-it-4bit` entry (commit A)

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift`

- [ ] **Step 1.1: Delete the experimental MoE entry**

Current (lines 98-107):

```swift
        .init(
            id: "mlx-community/gemma-4-26b-a4b-it-4bit",
            displayName: "Gemma 4 26B-A4B (Experimental)",
            approximateSizeGB: 14.0,
            notes: "MoE 4B-active. Best curated quality. Slow on 32 GB base — may exceed 10s under swap pressure. Try only after a fresh restart.",
            speedRating: 3,
            qualityRating: 9,
            expectedLatencySeconds: 8.0...30.0,
            isExperimental: true
        ),
```

Delete the entire entry including the trailing comma. The `static let curated` array now ends with the `Qwen3.5-4B-MLX-4bit` entry's closing paren + comma → closing paren + (no comma).

After this step: 4 entries → 3.

- [ ] **Step 1.2: Update the `enum MLXModelRegistry` doc comment to reflect the post-drop state (interim — Tasks 2-3 will rewrite further)**

Current (lines 60-69):

```swift
enum MLXModelRegistry {
    /// Curated lineup as of W6 (April 2026). Filtered to entries that meet
    /// the ≤10s wall-clock latency target on M-series base 32 GB for
    /// typical dictation cleanup (50-200 token output). One entry kept
    /// experimental for users who want big-model quality and accept the
    /// swap-pressure cost. All entries verified loadable against the
    /// bundled `mlx-swift-lm` 3.31.3 (gemma3 + gemma3_text + gemma4 +
    /// qwen3_5 model types are registered; the new e2b entry shares the
    /// gemma3 type with the existing e4b default). Ratings basis
    /// documented at `docs/superpowers/plans/W6-mlx-quality-and-segregation.md`.
```

Step 1.2 replacement (this is the interim doc comment after dropping 26B but before swapping e2b/e4b — Task 2.2 / Task 3.2 will iterate). For commit A's clarity:

```swift
enum MLXModelRegistry {
    /// Curated lineup as of W10 (April 2026). Filtered to entries that meet
    /// the ≤10s wall-clock latency target on M-series base 32 GB for
    /// typical dictation cleanup (50-200 token output). The 26B-A4B
    /// experimental tier was dropped per user direction "smaller the model,
    /// the better the speed". All entries verified loadable against the
    /// bundled `mlx-swift-lm` 3.31.3 (gemma3 + qwen3_5 model types are
    /// registered). Ratings basis documented at
    /// `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` (struct
    /// shape) + `docs/superpowers/plans/W10-mlx-registry-swap.md` (current
    /// lineup).
```

If the coder is collapsing all three commits into one diff for a single Edit pass, skip the interim doc comment edit and use the final Task 3.2 version directly.

- [ ] **Step 1.3: Verify no orphan references**

```bash
grep -rn "gemma-4-26b\|26b-a4b\|26B-A4B" VoiceInk --include="*.swift" --include="*.md"
```

Expected matches AFTER Step 1.1: zero in `*.swift`; doc references in plan / handoff `*.md` files are fine. If any Swift file still references `gemma-4-26b`, reconcile with the lead — Task 1 should have removed the only reference.

**Commit A boundary:** edits to `MLXModelRegistry.swift` for Step 1.1 + Step 1.2 form the first revertable unit. Coder leaves uncommitted; lead commits as `feat(mlx): drop 26B-a4b experimental tier (W10)`.

---

### Task 2: Swap `gemma-4-e2b-it-4bit` → `Qwen3-1.7B-4bit-DWQ` (commit B)

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift`

- [ ] **Step 2.1: Replace the fastest-tier entry**

Current (lines 71-79):

```swift
        .init(
            id: "mlx-community/gemma-4-e2b-it-4bit",
            displayName: "Gemma 4 E2B (Fastest)",
            approximateSizeGB: 1.7,
            notes: "Google. Smallest curated entry. Same gemma3 type as the e4b default — already proven loadable. Finishes typical dictation in 1-3s. Replaces gemma-3-1b. Note: 4-bit quant of PLE layers may degrade on long outputs; file an issue if cleanup looks wrong.",
            speedRating: 9,
            qualityRating: 5,
            expectedLatencySeconds: 1.0...3.0
        ),
```

Replace with:

```swift
        .init(
            id: "mlx-community/Qwen3-1.7B-4bit-DWQ",
            displayName: "Qwen 3 1.7B (Fastest)",
            approximateSizeGB: 1.0,
            notes: "Alibaba. Smallest curated entry. Apache 2.0. DWQ quant recovers most 4-bit perplexity loss vs plain -4bit. qwen3 type registered in mlx-swift-lm 3.31.3. Replaces gemma-4-e2b — faster on M-base 32 GB and free of PLE-quant degradation risk.",
            speedRating: 9,
            qualityRating: 6,
            expectedLatencySeconds: 1.0...3.0  // PLACEHOLDER — refine post sequential test (Task 6)
        ),
```

Field-by-field rationale:

| Field | Old | New | Why |
|---|---|---|---|
| `id` | `mlx-community/gemma-4-e2b-it-4bit` | `mlx-community/Qwen3-1.7B-4bit-DWQ` | Apache 2.0 vs gemma; faster per research §1.7B; DWQ variant for quality recovery |
| `displayName` | `Gemma 4 E2B (Fastest)` | `Qwen 3 1.7B (Fastest)` | Aligns label to vendor + size; "(Fastest)" tier marker preserved |
| `approximateSizeGB` | `1.7` | `1.0` | HF reports 968 MB → rounded to 1.0 for the picker chip |
| `notes` | gemma + PLE-quant warning | Qwen3 + Apache + DWQ context | Drops PLE-quant warning (irrelevant — Qwen3 has no per-layer-embedding scheme per research §1.7B "Quant pitfalls"). Adds Apache license signal + DWQ rationale. |
| `speedRating` | `9` | `9` | Same tier — research §1.7B speed band A-B. Keep `9` until sequential test contradicts. |
| `qualityRating` | `5` | `6` | Modest bump per research §"Open follow-ups for the registry-swap packet" #3 (better instruction-tuning vs gemma-E2B class). Conservative — bumps to 6, not 7. |
| `expectedLatencySeconds` | `1.0...3.0` | `1.0...3.0` (PLACEHOLDER) | Same band per research extrapolation. **PLACEHOLDER** — refined in Task 6 from observed `🦾 enhance: total=…s` numbers on user's hardware. The trailing comment makes the placeholder explicit so a future tightening pass can grep `// PLACEHOLDER` and find these. |
| `isExperimental` | (default `false`) | (default `false`) | Stays default. |

- [ ] **Step 2.2: Verify the doc comment is consistent**

If Step 1.2 already landed the W10 doc comment, no edit needed. If the coder deferred Step 1.2 (single-pass Edit strategy), now is when the doc comment text becomes accurate ("gemma3 + qwen3_5 model types are registered" → "qwen3 + qwen3_5 model types are registered" since gemma3 entries are now gone after both Tasks 2 and 3 land).

**Commit B boundary:** edits to `MLXModelRegistry.swift` for Step 2.1 form the second revertable unit. Coder leaves uncommitted; lead commits as `feat(mlx): swap e2b → Qwen3-1.7B-DWQ (W10 fastest tier)`.

---

### Task 3: Swap `gemma-4-e4b-it-4bit` → `Qwen3-4B-Instruct-2507-4bit-DWQ-2510` (commit C)

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift`

- [ ] **Step 3.1: Replace the default mid entry**

Current (lines 80-88):

```swift
        .init(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B Instruct",
            approximateSizeGB: 2.5,
            notes: "Google. Default mid-tier. Strong instruction-following, ~30-50 tok/s on M-series base 32 GB.",
            speedRating: 7,
            qualityRating: 6,
            expectedLatencySeconds: 3.0...7.0
        ),
```

Replace with:

```swift
        .init(
            id: "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510",
            displayName: "Qwen 3 4B Instruct 2507",
            approximateSizeGB: 2.3,
            notes: "Alibaba. Default mid-tier. Apache 2.0. IFEval 88.9 (vs gemma-E4B class ~70-75). Arena-Hard 43.4. DWQ-2510 quant minimizes 4-bit quality loss. qwen3 type registered in mlx-swift-lm 3.31.3.",
            speedRating: 7,
            qualityRating: 8,
            expectedLatencySeconds: 3.0...7.0  // PLACEHOLDER — refine post sequential test (Task 6)
        ),
```

Field-by-field rationale:

| Field | Old | New | Why |
|---|---|---|---|
| `id` | `mlx-community/gemma-4-e4b-it-4bit` | `mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510` | Apache 2.0; IFEval 88.9 vs gemma-E4B class ~70-75 per research §1; same speed tier |
| `displayName` | `Gemma 4 E4B Instruct` | `Qwen 3 4B Instruct 2507` | Vendor + size + variant year (2507 = 2025-July release per HF) |
| `approximateSizeGB` | `2.5` | `2.3` | HF reports 2.26 GB → rounded to 2.3 |
| `notes` | gemma + tok/s extrapolation | Qwen3 + IFEval signal + Apache + DWQ context | Drops the tok/s extrapolation (was already a soft number); leads with the IFEval gain since that's the headline reason for the swap |
| `speedRating` | `7` | `7` | Same band B per research §1. Same tier as gemma-4-e4b in extrapolated tok/s. Keep `7` until sequential test contradicts. |
| `qualityRating` | `6` | `8` | **Material gain** per research §"Open follow-ups" #3 (88.9 IFEval is +10-15 pts vs gemma-E4B class 70-75). Bumps from 6 → 8 to surface the change in the picker UI's Quality chip. |
| `expectedLatencySeconds` | `3.0...7.0` | `3.0...7.0` (PLACEHOLDER) | Same band; **refined post-test** per Task 6. |

- [ ] **Step 3.2: Final doc comment for `enum MLXModelRegistry`**

After all three swaps land, the doc comment should read:

```swift
enum MLXModelRegistry {
    /// Curated lineup as of W10 (April 2026). Three-tier Qwen-only Apache 2.0
    /// lineup. Filtered to entries that meet the ≤10s wall-clock latency
    /// target on M-series base 32 GB for typical dictation cleanup (50-200
    /// token output). The W6-era gemma entries (e2b, e4b) were swapped out
    /// after user-reported real-world slowness; the 26B-A4B experimental
    /// tier was dropped per user direction "smaller the model, the better
    /// the speed". All entries verified loadable against the bundled
    /// `mlx-swift-lm` 3.31.3 (qwen3 + qwen3_5 model types are registered).
    /// Ratings basis: research at
    /// `docs/superpowers/research/2026-04-29-mlx-rewriting-models.md` +
    /// W6 plan at
    /// `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` (struct
    /// shape) + W10 plan at
    /// `docs/superpowers/plans/W10-mlx-registry-swap.md` (current lineup).
    /// `expectedLatencySeconds` ranges are PLACEHOLDER post-merge — refine
    /// from the user's `🦾 enhance: total=…s` log capture during the
    /// sequential pre-merge test pass.
```

- [ ] **Step 3.3: Verify no gemma references remain in registry**

```bash
grep -n "gemma" VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift
```

Expected: zero matches. If grep returns anything, the swap is incomplete — re-check Tasks 1-3.

**Commit C boundary:** edits for Step 3.1 + Step 3.2 form the third revertable unit. Coder leaves uncommitted; lead commits as `feat(mlx): swap e4b → Qwen3-4B-Instruct-2507 (W10 default mid)`.

---

### Task 4: Pre-merge static checks (coder-runnable, no dictation)

**Files:** none (read-only verification).

- [ ] **Step 4.1: Confirm registry data shape compiles**

The coder's environment cannot run dictation, but it CAN run a Swift type-check via SourceKit (which Xcode does live during edits). Verify visually that:
- All three entries have all six fields: `id`, `displayName`, `approximateSizeGB`, `notes`, `speedRating`, `qualityRating`, `expectedLatencySeconds`.
- `isExperimental` is omitted (defaults to `false` via the W6 init) — none of the three new entries are experimental.
- `approximateSizeGB` values are `Double` literals (`1.0`, `2.3`, `3.0` — see also Task 4.3 below for the Qwen3.5 fix-up).
- `expectedLatencySeconds` is a `ClosedRange<Double>` literal (`1.0...3.0`, `3.0...7.0`).
- The `// PLACEHOLDER` comments are present on the two new entries' latency fields.

- [ ] **Step 4.2: Confirm the legacy migration helper is unaffected**

```bash
grep -n "purgeLegacyApplicationSupportModelsIfPresent\|directoryAllocatedSize" VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift
```

Expected: matches at lines ~211, 225, 264 (the W6 helper) — UNCHANGED. W10 only touches the `static let curated` array and its enclosing doc comment.

- [ ] **Step 4.3 (OPTIONAL — research §"Open follow-ups" #1): Fix Qwen3.5 size**

Research notes the existing `Qwen3.5-4B-MLX-4bit` entry advertises 2.5 GB but the actual file is 3.03 GB. This is a cosmetic chip-render fix. Update line 92 (the `approximateSizeGB: 2.5` for the Qwen3.5 entry) to `3.0`. **Bundle decision:** include in commit C if simple, OR leave for a separate cosmetic fix-up packet. Coder's call — flag in the report which path was taken.

If included, also bump `qualityRating` from 6 to 9 per research §"Open follow-ups" #3 ("Qwen3.5-4B-MLX-4bit: Speed 7, Quality 9 — bump in line with IFEval 89.8 leadership"). The two-line update on the Qwen3.5 entry:

```swift
        .init(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit",
            displayName: "Qwen 3.5 4B",
            approximateSizeGB: 3.0,                                   // was 2.5; HF reports 3.03 GB actual
            notes: "Alibaba. Same speed tier as gemma-4-e4b; terse, on-prompt outputs.",
            speedRating: 7,
            qualityRating: 9,                                          // was 6; bumped to reflect IFEval 89.8 best-in-class
            expectedLatencySeconds: 3.0...7.0
        ),
```

If included, this rides on commit C (no separate commit needed — the bump is a numeric refinement, not a swap).

---

### Task 5: Sequential pre-merge hardware test — handoff to user

**Files:** none (this task runs on the user's machine, not in the coder's loop).

The coder cannot run dictation. After Tasks 1-4 land (uncommitted), the lead hands the working tree to the user with the testing protocol below. **The user runs Tasks 5-7; the coder does not.**

- [ ] **Step 5.1: Build the working tree**

```bash
make local
```

Expected: clean build. The registry data swap has no logic surface beyond the type-check in Task 4.1; if the build fails it's a syntax issue in the new entries' `.init(...)` calls — fix and rebuild.

- [ ] **Step 5.2: Launch the app from the build output**

The test pass requires the AI Models settings page to be reachable. No special launch flags.

---

### Task 6: Sequential per-model dictation cycle (user runs on hardware)

**Files:** none — observation pass.

> **CRITICAL:** Per user instruction, this loop is **SEQUENTIAL**. One model at a time:
> downloaded → dictation cycle → log captured → next model.
> **NEVER run two `MLXModelDownloader.download(...)` calls concurrently** from the picker, and never start a second model's download while the first is still active.

For each of the three new entries, in this order — Qwen3-1.7B-4bit-DWQ first (cheapest), Qwen3-4B-Instruct-2507-4bit-DWQ-2510 second, Qwen3.5-4B-MLX-4bit last (already downloaded if user had it from W6+ era):

- [ ] **Step 6.1.X: Download model X**

Open the AI Models settings page. Click `Download` on model X. Wait for the W6 chip-vocabulary progress chip (`MLXModelPickerView.swift:201-222`) to reach 100% and transition to the `Delete` button affordance. **Do not click Download on any other model until this finishes.**

Expected log lines in Console.app (subsystem `com.prakashjoshipax.voiceink`, category `MLXModelDownloader`):
```
🦾 download start: repo=mlx-community/Qwen3-1.7B-4bit-DWQ
…
🦾 download done: repo=mlx-community/Qwen3-1.7B-4bit-DWQ
```

If the download fails — `swift-huggingface` returns an error (most likely revision lookup or 404 on the snapshot path) — see Task 8 (DWQ fallback).

- [ ] **Step 6.2.X: Activate model X**

Click `Use` next to model X (or rely on the auto-activate path in `MLXModelPickerView.refreshAllStatuses` at lines 224-237 if no other model was previously selected). Verify in the picker that the `ACTIVE` chip rendered next to model X's `displayName`.

- [ ] **Step 6.3.X: Run a one-shot dictation cycle**

Speak a representative dictation cleanup input (50-150 spoken words → 100-200 token raw transcript → ~80-150 token cleaned output). Use the same dictation phrasing across all three models so latency is comparable.

Expected log lines (subsystem `com.prakashjoshipax.voiceink`, category `MLXProvider`):
```
🦾 loadModel: id=mlx-community/Qwen3-1.7B-4bit-DWQ
🦾 enhance: model-load took X.XXs (cold)
🦾 enhance: prep=…s maxTokens=… input=…c
🦾 enhance: gen=…s ttft=…s tokens≈… (… tok/s) output=…c
🦾 enhance: total=X.XXs
```

If `total > 10.0`, the warning line ALSO appears:
```
🦾 enhance: WARN total=X.XXs exceeds 10s ceiling for model=mlx-community/Qwen3-1.7B-4bit-DWQ
```

- [ ] **Step 6.4.X: Capture the observed band**

Repeat Step 6.3 two more times (three runs total) to surface variance — first run is cold-cache, runs 2 and 3 are warm. Record the three `total=` numbers.

The observed band → updated `expectedLatencySeconds` is:
- Lower bound = min of the three runs (or warm-run min, whichever the user prefers as the "ideal" anchor).
- Upper bound = max of the three runs, rounded UP to the nearest whole second.

Example: runs of 1.4s / 0.9s / 1.1s → `0.9...2.0` (round up the upper) → register as `1.0...2.0` (clamp to 1.0 lower bound for sane chip rendering — the picker shows "1-2s" via `formatSecs`).

- [ ] **Step 6.5.X: Move to model X+1**

Only after Steps 6.1-6.4 complete for model X, click `Download` on model X+1. Repeat. **Do NOT parallelize.**

- [ ] **Step 6.X: Optional — sanity dictation pass on Qwen3.5-4B (already downloaded)**

If the user had `Qwen3.5-4B-MLX-4bit` downloaded from W6+, no Step 6.1 needed for it — proceed straight to 6.2 / 6.3 / 6.4. Capturing fresh numbers for it is still useful so the picker shows refined ranges across all three entries, not just the two new ones.

---

### Task 7: Refine `expectedLatencySeconds` from observed numbers

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift`

- [ ] **Step 7.1: Edit the two PLACEHOLDER ranges in-place**

For each of the two new entries (Qwen3-1.7B-4bit-DWQ and Qwen3-4B-Instruct-2507-4bit-DWQ-2510), replace the placeholder `expectedLatencySeconds` with the observed band from Task 6.4. Drop the `// PLACEHOLDER — refine post sequential test (Task 6)` trailing comment.

Example post-test diff for Qwen3-1.7B (assuming runs landed at 1.4 / 0.9 / 1.1):

```swift
            expectedLatencySeconds: 1.0...3.0  // PLACEHOLDER — refine post sequential test (Task 6)
```

→

```swift
            expectedLatencySeconds: 1.0...2.0
```

- [ ] **Step 7.2: Optionally re-rate `speedRating` if the observed band is materially off**

If the observed band shows a model is faster or slower than the rating brackets in `MLXModelEntry.speedRating` doc comment imply (lines 16-19 of `MLXModelRegistry.swift`: 9-10 = under 3s; 6-8 = 3-7s; 3-5 = 7-15s), update `speedRating` to match. Keep changes conservative — rounding errors are not a reason to re-rate.

- [ ] **Step 7.3: Land the refinement as part of commit B / commit C as appropriate**

The `Qwen3-1.7B` refinement rides on commit B; the `Qwen3-4B-Instruct-2507` refinement rides on commit C. If the user did Task 4.3 (Qwen3.5 fix-up), refining its band rides on commit C too.

---

### Task 8: DWQ fallback path (only if pre-merge testing surfaces issues)

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift`

If during Task 6.1.X (`MLXModelDownloader.download` call) or Task 6.3.X (`MLXProvider.enhance(...)` call) one of the DWQ variants fails — load error, generate error, or visibly worse output than the gemma baseline — fall back to the plain `-4bit` repo:

| DWQ id | Plain `-4bit` fallback id | Size delta |
|---|---|---|
| `mlx-community/Qwen3-1.7B-4bit-DWQ` | `mlx-community/Qwen3-1.7B-4bit` | same (~968 MB) |
| `mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510` | `mlx-community/Qwen3-4B-Instruct-2507-4bit` | same (~2.26 GB) |

- [ ] **Step 8.1: Edit the failing entry's `id` field**

Strip the `-DWQ` (or `-DWQ-2510`) suffix. Update the `notes` field's "DWQ quant" sentence to remove the DWQ context (it's now plain group-quant). Re-run Task 6 from Step 6.1 for the affected model only.

- [ ] **Step 8.2: Update the doc comment for the entry to reflect the fallback**

Add a one-line note: "Plain -4bit fallback after DWQ variant surfaced load/quality issues during pre-merge test." This preserves the rationale for the next reader.

- [ ] **Step 8.3: Capture WHY in the report to lead**

The lead's commit message for commit B or C should reflect the fallback: e.g., `feat(mlx): swap e2b → Qwen3-1.7B (plain -4bit; DWQ failed pre-merge load)`. The `WHY` is observability for the next engineer who looks at why we picked plain over DWQ.

---

### Task 9: Integration build + handoff

**Files:** none (verification + report).

- [ ] **Step 9.1: Single integration build**

```bash
make local
```

Expected: clean build. Per CLAUDE.md cadence, this is the only build run during the packet. If it fails, the failure is in the registry data shape — re-check Task 4.1.

- [ ] **Step 9.2: One smoke dictation pass on the active model**

Pick whichever model the user has set as active post-Task-6 (probably Qwen3-4B-Instruct-2507 as the default mid). Run one dictation cycle. Verify:
- `🦾 enhance: total=…s` appears within the `expectedLatencySeconds` upper bound.
- Output text is non-empty and reads as a clean rewrite (not the raw input echoed, not garbled, not infinitely repeating).
- No `🦾 MLX generate failed:` error in Console.app.

If the smoke pass fails, the registry edit is broken — revert the affected commit and reproduce.

- [ ] **Step 9.3: Coder report to lead**

Send the lead:
- Confirmation that all three commits' edits are staged (or in the working tree as one diff).
- Whether Task 4.3 (Qwen3.5 cosmetic fix) was bundled in.
- Whether Task 8 (DWQ fallback) was triggered for any model.
- The post-test `expectedLatencySeconds` numbers for both new entries.
- Any Console.app errors observed during Task 6 or 9.2.

The lead handles the three commits + push + final handoff doc.

---

## Risks / unknowns

1. **M-base 32 GB ground truth still partially unmeasured pre-merge.** Same caveat as W6 plan §Risks #2. The `expectedLatencySeconds` PLACEHOLDER strategy in Task 5 (research extrapolations land first; user refines from observed `🦾 enhance: total=…s` numbers) is the mitigation. Worst case: one of the new entries lands at C-band (5-10s) instead of B-band on user's specific hardware. The WARN log already wired in `MLXProvider.swift:134` will surface this at runtime even if the placeholder under-promises. Acceptable.

2. **Qwen3-4B-Instruct-2507 verbosity tendency.** Research §1 cites Artificial Analysis flagging "very verbose" (3.3× median output). For dictation cleanup the existing prompt scaffolding in `AIEnhancementService` already constrains output length, but if the user's prompts allow long-form output the model may drift past target length and inflate `gen` time. **Mitigation:** observe Task 6 output during sequential test; if cleanup output is visibly bloated, revert commit C and use Phi-3.5-mini-instruct (research §"Other candidates evaluated" — MIT licensed, 3.8B, 2.15 GB) as the next fallback candidate. Phi-3.5 is sub-4B, so it's compatible with the small-model directive.

3. **DWQ variant maturity.** Research §Risks #3 flags DWQ as newer (mlx-lm 0.28.2 conversion, lower download counts than standard `-4bit`). **Mitigation:** Task 8 codifies the one-line revert path — strip the `-DWQ` suffix, re-run Task 6 for that model only. Same safetensors format, same Swift loading path, slightly larger perplexity hit.

4. **No published IFEval for Qwen3-1.7B specifically.** The fastest-tier rec leans on Qwen3 family-scaling extrapolation per research §1.7B. **Mitigation:** Task 6.3 dictation cycle is the first-party signal. If the cleanup output during the pre-merge test is visibly worse than the prior gemma-E2B baseline (regurgitation, off-prompt drift, hallucinated content), revert commit B (one-line `git revert <sha>`) and either keep gemma-E2B as the fastest tier OR pick `granite-3.3-2b-instruct-4bit` (Apache 2.0, sub-4B, research §"Other candidates evaluated"). Do NOT fall back to Llama-3.2-1B — the license attribution friction isn't worth a marginal fastest-tier win.

5. **`speedRating` / `qualityRating` are subjective ints.** The research recommends bumps (`Qwen3-1.7B: 6` was `5`; `Qwen3-4B-Instruct-2507: 8` was `6`; `Qwen3.5: 9` was `6`). These are picker-UI display values — worst case is they look slightly off vs the user's perception. Adjustable in any future tightening packet without functional consequences.

6. **`approximateSizeGB` = 1.0 for Qwen3-1.7B-DWQ** is rounded UP from 0.97 GB. The picker chip displays "1.0 GB" via `MLXModelPickerView.formatSecs` — visually identical to "1 GB" in user perception. No risk.

7. **No `mlx-swift-lm` upgrade required.** Research §"Framework compatibility" confirms `qwen3` and `qwen3_5` model types are registered in the bundled 3.31.3. No coupling to Ask 4 (framework bump) — that ask stays deferred.

---

## Rollback story

**Scenario tree** for "what to revert if a swap turns out worse than gemma in production":

| Scenario | What happened | Revert path | Resulting registry |
|---|---|---|---|
| Qwen3-1.7B-DWQ slow / poor quality | Fastest tier regression vs gemma-E2B baseline | `git revert <commit B sha>` | gemma-4-e2b restored; Qwen3-4B + Qwen3.5 stay |
| Qwen3-4B-Instruct-2507 verbose / slow | Default mid regression vs gemma-E4B baseline | `git revert <commit C sha>` | gemma-4-e4b restored; Qwen3-1.7B + Qwen3.5 stay |
| Both Qwen3 swaps regress | Both new tiers worse than gemma | `git revert <commit B sha> <commit C sha>` (two reverts) | gemma-E2B + gemma-E4B + Qwen3.5 — back to W6 lineup minus the dropped 26B |
| User wants 26B back | "I want to test the experimental tier again" | `git revert <commit A sha>` | 26B-A4B re-added to curated; Qwen3 lineup stays |
| All three swaps regress | Catastrophic — every tier worse | `git revert <commit A sha> <commit B sha> <commit C sha>` | Full W6 lineup restored. |

**Why three commits, not one:** revert-of-merge is awkward for granular bisection. With three commits the user (or the next planner) can flip one swap independently — e.g., keep Qwen3.5 + Qwen3-4B, revert just the fastest tier — without touching the other entries.

**Detection signals** (which production data tells us a revert is needed):
- User reports cleanup output is visibly worse than memory of gemma's behavior — quality regression.
- `🦾 enhance: WARN total=…s exceeds 10s ceiling` log fires regularly on the new model — speed regression.
- `🦾 MLX generate failed:` errors with the new model id — load/runtime regression.

**Blast radius of a revert:** zero data loss. `MLXModelRegistry.curated` is in-memory data; the user's `@AppStorage("mlx_selected_model_id")` will hold a stale id pointing at the reverted-out model, but `AIService.mlxProvider(for:)` at line 273 will rebuild a fresh `MLXProvider` for any new id when the user re-picks from the picker. The `MLXModelPickerView.refreshAllStatuses` auto-activate path (lines 230-237) will fall back to the first-downloaded model if the stale id no longer resolves. Worst-case UX: user opens AI Models, sees no `ACTIVE` chip, picks a model again. One click recovery.

**HuggingFace cache implications:** any model the user downloaded for the new lineup stays cached at `~/Library/Caches/huggingface/hub/` after a revert. `MLXModelDownloader.delete(_:)` (line 165) is a manual cleanup affordance via the picker's Delete button — not auto-invoked. No disk leak surprise; the user can clean up via the picker if desired.

---

## Validation steps (summary)

The integration gate is the user-side sequential test pass in Task 6 + the smoke build/dictation in Task 9. Coder-side validation is Task 4 static checks only. There are no new tests to write.

**Coder-side checklist:**
- [x] `MLXModelEntry` struct shape unchanged.
- [x] All three swap entries compile (Task 4.1).
- [x] No orphan references to gemma model ids in any Swift file (Task 1.3, Task 3.3 grep).
- [x] Doc comment reflects W10 lineup (Task 3.2).
- [x] Three logical edit chunks staged (commits A/B/C).
- [x] PLACEHOLDER comments present on the two new entries' latency fields.

**User-side checklist (sequential — never parallel):**
- [ ] Qwen3-1.7B-4bit-DWQ downloads cleanly via the picker.
- [ ] Qwen3-1.7B-4bit-DWQ activates and runs dictation; `🦾 enhance: total=…s` captured ×3.
- [ ] Qwen3-4B-Instruct-2507-4bit-DWQ-2510 downloads cleanly.
- [ ] Qwen3-4B-Instruct-2507 activates and runs dictation; `🦾 enhance: total=…s` captured ×3.
- [ ] (If pre-existing) Qwen3.5-4B-MLX-4bit dictation pass for fresh band numbers.
- [ ] No `🦾 enhance: WARN total=…s exceeds 10s ceiling` lines on any of the three new models for typical dictation length.
- [ ] No `🦾 MLX generate failed:` errors.
- [ ] Output quality matches or exceeds memory of prior gemma behavior (subjective — user's call).

**Build gate:** `make local` after all three commits' edits are present (Task 9.1) — clean build required.

---

## Out of scope

- **`mlx-swift-lm` framework bump (Ask 4).** Research §"Framework compatibility" confirms not needed for any W10 candidate. Stays deferred.
- **Re-quantizing `Qwen3.5-4B-MLX-4bit` from upstream `mlx-lm`.** Research §"Open follow-ups" #5 flags the experimental `pc/fix-qwen35-predicate` quant branch lineage; no production quality regression has surfaced. Defer until/unless the user reports quality issues tied to this entry specifically.
- **MLXModelPickerView UI changes.** Picker renders generically over `MLXModelRegistry.curated`. No view edits this packet.
- **Llama-3.2-3B fallback wiring.** Research §"Other candidates evaluated" cites this as best-published rewriting score (Open-Rewrite 40.1) but with Llama community license attribution friction. If user later wants this option, it's a separate packet (registry add + AI Models page footer attribution line + `LICENSE` mention). Not blocking; flagged.
- **Adding a fourth Apache-2.0 entry** (granite-3.3-2b-instruct or Phi-3.5-mini-instruct). Research §"Other candidates evaluated" treats these as fallback candidates if a Qwen3 entry fails — only added if Task 8 escalates. Otherwise the curated set stays at three.
- **Telemetry/metrics aggregation.** The `🦾 enhance: total=…s` line is observable per-cycle; aggregating it into a histogram or rolling average is a future packet (would justify a `MetricsRegistry` surface, out of scope here).

---

## Notes for the lead

- **Three-commit boundary** is the headline design point. Don't squash. Granular revert is cheap insurance for a user-facing model behavior change.
- **PLACEHOLDER `expectedLatencySeconds`** is honest pre-merge. Coder lands research-extrapolated numbers; user refines from `🦾 enhance: total=…s`. The trailing comment makes future tightening grep-friendly.
- **Sequential is non-negotiable.** Do not parallelize Task 6 across multiple `Download` clicks even if it's faster — user's explicit instruction.
- **No 13B+ fallbacks**, even if the Qwen3 family fails. The fallback chain inside the small-model envelope: Qwen3-DWQ → Qwen3 plain `-4bit` (Task 8) → Phi-3.5-mini-instruct (MIT, 3.8B) → granite-3.3-2b-instruct (Apache, 2B). All from research §"Other candidates evaluated".
- **No new tests.** Data-only swap. Build is the gate.
