# W6 — AI Models + Prompts Re-skin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.

**Goal:** Bundle the user's MLX-quality follow-ups into the W6 packet (AI Models + Prompts re-skin per spec §5#6). Tighten the curated MLX lineup to entries that meet the ≤10s latency target on M-series base 32 GB; surface speed/quality ratings inline; segregate the AI Enhancement gallery into Configured vs. Unconfigured sections; re-theme provider chips, status pills, prompt chip picker, prompt editor chrome, and download progress UI to the W1 token vocabulary; add a one-time legacy-MLX-dir cleanup migration; instrument MLX generation to flag >10s stalls so the experimental tier remains honest.

**Architecture (segregation):**

```
EnhancementSettingsView
  └── APIKeyManagementView (Section)
       ├── ProviderChip (active provider preview)
       │
       ├── Configured providers grid          ← aiService.connectedProviders ∩ galleryProviders
       │     - ProviderCard (re-skinned)        sorted: aiService.selectedProvider first, then alphabetical
       │
       └── Unconfigured providers grid        ← galleryProviders \ connectedProviders
             - ProviderCard (re-skinned)        sorted alphabetical
                                                opacity 0.85 to recede; otherwise identical layout
```

The split lives entirely inside `APIKeyManagementView.body`. No new view types; we partition the existing `galleryProviders` list into two `LazyVGrid`s with section labels above each. `aiService.connectedProviders` is the single source of truth for the partition (already filters on API-key presence, MLX downloaded model, Foundation Models availability, ollama connectivity, local CLI configuration — see `AIService.swift:289-309`).

**Architecture (ratings + experimental flag):**

```
MLXModelEntry  (extended)
  + speedRating: Int            1..10
  + qualityRating: Int          1..10
  + expectedLatencySeconds: ClosedRange<Double>
  + isExperimental: Bool
       │
       ├── MLXModelPickerView row
       │     • renders GlassChip("Speed N/10") + GlassChip("Quality N/10")
       │     • EXPERIMENTAL chip (Palette.warn) when isExperimental == true
       │     • size + latency-range copy in caption
       │
       └── MLXProvider (runtime)
             • logs WARN when wall-clock total > 10s ("🦾 enhance: WARN total=…s exceeds 10s ceiling")
             • does NOT auto-block — instrumentation only; data feeds future
               tightening rounds when the user provides hardware verification
```

**Tech Stack:** Swift 5.x, SwiftUI, AppKit, MLX-swift (mlx-swift-lm 3.31.3 + swift-huggingface 0.9.0), Xcode 16.x, Swift Testing. Build via `make local` (~3 min cold). Animations attach via `.animation(_, value:)` / `withAnimation`; never `DispatchQueue.main.asyncAfter`.

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens), §5 row W6 ("AI Models + Prompts re-skin: `MLXModelPickerView.swift`, `ProviderCard.swift`, `PromptEditorView.swift`, `EnhancementSettingsPanel.swift` (chip picker section). Provider chips, status pills, prompt chips re-themed; download progress UI inherits cluster vocabulary."). Plus the user's MLX follow-up batch from `docs/superpowers/handoffs/HANDOFF_aesthetic_redesign_post_W3_2026-04-28.md` "Next Steps" items 1-7.

**Research basis (cite-checked April 2026):**

- `gemma-4-e4b-it-4bit` (~2.5 GB, 4B effective via PLE): ~57 tok/s on M4 Pro 24 GB via Ollama; M2/M3 base 32 GB extrapolates to roughly 30-50 tok/s. Source: [I Tested Every Gemma 4 Model Locally on My MacBook (kartit.net)](https://www.kartit.net/blog/gemma4-local-benchmark.html). For ~150-200-token cleanup output: 3-7s. **Acceptable.**
- `gemma-4-e2b-it-4bit` (~1.7 GB, 2B effective via PLE): same `gemma3` model type as the existing e4b default — already proven loadable under bundled `mlx-swift-lm` 3.31.3. Newer training generation than 3n; PLE architecture absorbed into Gemma 4 E-series. Extrapolated speed parity with E2B-class predecessors (~80-100 tok/s on M-series). 1-3s for cleanup. Source: [mlx-community/gemma-4-e2b-it-4bit](https://huggingface.co/mlx-community/gemma-4-e2b-it-4bit) + [Gemma 4 release notes (HF blog)](https://huggingface.co/blog/gemma4) + [Gemma 4 vs 3 vs 3n comparison (codersera.com)](https://codersera.com/blog/gemma-4-vs-gemma-3-vs-gemma-3n-which-model-makes-the-most-sense-in-2026). **Ideal — fastest tier.** Caveat: see PLE-quant warning in Risks/unknowns #1.
- `Qwen3.5-4B-MLX-4bit` (~2.5 GB, 4B dense): comparable speed to gemma-4-e4b on small models per [Apple Silicon LLM Benchmarks (llmcheck.net)](https://llmcheck.net/benchmarks). **Acceptable.**
- `gemma-4-26b-a4b-it-4bit` (~14 GB, MoE 4B-active): ~2 tok/s on M4 Pro 24 GB with constant swap; on M2/M3 base 32 GB the swap pressure is reduced (≈4-6 GB headroom over weights vs ~6 GB deficit on 24 GB) but still significant for a 14 GB working set against 32 GB total. Source: [kartit.net Gemma 4 local benchmark](https://www.kartit.net/blog/gemma4-local-benchmark.html). Cleanup output at 5-15 tok/s = 10-40s. **Reject per user's >10s threshold; mark `isExperimental: true` with EXPERIMENTAL chip + caution copy rather than hard-removing — gives the user the option to test and surface real numbers via the new diagnostic hook.**
- `Qwen3.6-27B-4bit` (~14 GB, dense — no MoE active-parameter benefit): worse than 26b-a4b on 32 GB base because all 27B params are active per token. No public M-series base 32 GB tok/s figure; extrapolates to under 3 tok/s. **Hard-drop.**
- `gemma-3-1b-it-qat-4bit`: per handoff "Drop inline example sentences from System Default prompt" + `5c69269` reversal — user testing confirms regurgitation + capacity-ceiling failures. **Hard-drop.**

**CLAUDE.md cadence rules respected:**
- **Single build at merge time.** No `make local` per task; one full build at the final task.
- **No commits during execution.** Final step reports to lead; lead handles commits.
- **No `xcodebuild` per file.** SourceKit handles per-file syntax during edits; integration build is the gate.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** All code samples follow this.
- **Pre-existing spec-ref comments stay** (e.g. `Palette.swift` §1 ref, `GlassChip.swift` §1 ref). New comments only when WHY is non-obvious.

---

## File structure

### New files

None. W6 is entirely a re-skin + registry-curation packet. No new types beyond extending an existing struct.

### Modified files

- `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift` — extend `MLXModelEntry` with `speedRating: Int`, `qualityRating: Int`, `expectedLatencySeconds: ClosedRange<Double>`, `isExperimental: Bool` (default `false`). Drop `gemma-3-1b-it-qat-4bit` + `Qwen3.6-27B-4bit` entries. Mark `gemma-4-26b-a4b-it-4bit` experimental. Add `gemma-4-e2b-it-4bit` as fastest tier. Update top doc-comment to reflect the new lineup + cite ratings basis (link to plan file). Add a one-time legacy-dir cleanup function `purgeLegacyApplicationSupportModelsIfPresent()`. ~+90 LOC, -15 LOC.
- `VoiceInk/Services/AIEnhancement/MLXProvider.swift` — add a wall-clock threshold guard at the bottom of `enhance(systemPrompt:userPrompt:)`: emit a WARN log line via the existing logger when `totalElapsed > 10.0`. ~+8 LOC.
- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` — full re-skin to W1 vocabulary: replace `RoundedRectangle(cornerRadius: 8)` row chrome with `GlassChip` panel; replace the inline `Color.accentColor` Capsule "ACTIVE" badge with an SF Mono uppercase chip styled like the W2 anchor chip (`Palette.accent` foreground + 1pt accent stroke); add `Speed N/10` + `Quality N/10` chips; add `EXPERIMENTAL` chip when `model.isExperimental == true`; add latency-range copy ("Expect 4-7s for typical dictation") to the caption; rebuild download/delete buttons to inherit cluster motion vocabulary (progress chip replaces `ProgressView`). ~+120 LOC, -45 LOC.
- `VoiceInk/Views/AI Models/ProviderCard.swift` — corner radius 16 → 14 (panel token); replace the `.rounded`-design `ACTIVE` Capsule with an SF Mono uppercase variant matching the picker chip; replace the connection `Capsule` status pill (lines 211-222) with the existing `StatusPill` component from `APIKeyManagementView.swift` (DRY); remove the 4pt hover lift `.offset(y: hovering ? -4 : 0)` per spec §5#8 ("`GlassCard` hover-lift removed (kept hover, dropped 4pt translate-y)"); keep `onHover` for cursor signal. ~+20 LOC, -22 LOC.
- `VoiceInk/Views/AI Models/APIKeyManagementView.swift` — split the single grid into two grids ("Configured" + "Unconfigured") inside the same `Section`. Add `configuredProviders` + `unconfiguredProviders` computed properties partitioning `galleryProviders` against `aiService.connectedProviders`. Sort: configured puts `aiService.selectedProvider` first then alphabetical; unconfigured is alphabetical. Render small `Text` headers above each grid using SF Mono uppercase tracking 0.06em. Empty state: when `configuredProviders.isEmpty` show a one-line hint chip; when `unconfiguredProviders.isEmpty` omit that grid entirely. ~+70 LOC, -10 LOC.
- `VoiceInk/Views/PromptEditorView.swift` — re-skin header (`headerBar`) + footer (`footerBar`): replace the `Color.secondary.opacity(0.1)` close-button background with a `glassChip(cornerRadius: 8)` modifier; replace `Color(NSColor.windowBackgroundColor)` chrome backings with `Palette.onyxBg`-tinted glass; re-style the IconPickerPopover selected-state stroke to `Palette.accent`. Editor body (Form + TextEditor) UNTOUCHED — functionality preserved per packet brief. ~+25 LOC, -18 LOC.
- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` — header re-skin only (xmark close-button gets `glassChip(cornerRadius: 8)` treatment matching `PromptEditorView`). Body Form UNTOUCHED. ~+8 LOC, -5 LOC.
- `VoiceInk/Views/EnhancementSettingsView.swift` — re-skin the prompt-grid Section: replace the `Palette.accent.opacity(0.16)` `+` button background with `glassChip(cornerRadius: 8)`; replace the `gear` settings button background similarly; ensure SF Mono uppercase tracking on the section's `statusText` (already passes through `SettingsSectionHeader`). The `ReorderablePromptGrid` itself UNTOUCHED — drag/drop logic preserved. ~+12 LOC, -10 LOC.
- `VoiceInk/VoiceInkApp.swift` (or whichever file holds the `VoiceInkApp`/`VoiceInk` `App` struct — coder will grep) — wire a one-time cleanup call: invoke `MLXModelRegistry.purgeLegacyApplicationSupportModelsIfPresent()` from `init()` AFTER the engine + registry are built. Guarded by an `@AppStorage("legacyMLXDirPurged")` Bool sentinel so it runs at most once per install. ~+8 LOC.

### Retired files (delete)

None.

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Services/AIEnhancement/AIService.swift` — `connectedProviders` (line 289) is consumed read-only by W6; we read it from `APIKeyManagementView`. Do not modify the property. The MLX selection write path (`notifyMLXSelectionChanged`, line 331) stays — it's the existing reactivity hook from `da8c699` and W6 picker rows reuse it.
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` — provider routing path (lines 250-263 raw-transcript MLX call site) UNTOUCHED. Re-skin packet; no logic change.
- `VoiceInk/Services/AIEnhancement/MLXProvider.swift` — the `enhance(...)` body, model loading, eviction, and existing `🦾 enhance:` instrumentation UNTOUCHED except for the single new WARN line at the bottom of `enhance(...)`. Do NOT refactor the existing log structure — it's the diagnostic surface.
- `VoiceInk/Views/Common/Palette.swift` — tokens UNTOUCHED. Reuse `accent` / `accentMuted` / `warn` / `success` / `neutral` / `hairline` / `innerHi`. No new tokens introduced by W6.
- `VoiceInk/Views/Common/GlassChip.swift` — modifier UNTOUCHED. Reuse `.glassChip()` and `.glassPanel()` extensions.
- `VoiceInk/Views/Common/ProviderChipStyle.swift` — symbol/tint/displayName tables UNTOUCHED.
- `VoiceInk/Views/Common/SettingsSectionHeader.swift` — UNTOUCHED. APIKeyManagementView reuses it as-is.
- `VoiceInk/Views/Common/ProviderChip.swift` — UNTOUCHED. ProviderCard's header tile is intentionally a separate render (36pt scale vs ProviderChip's smaller pill).
- `VoiceInk/Views/Recorder/Constellation/{ConstellationCluster,ChipPanel,ClusterChips,ClusterMotion,ClusterPhase}.swift` — W2/W3 territory. Do not touch.
- `VoiceInk/Views/AI Models/APIKeyManagementView.swift` `StatusPill` struct (lines 144-182) — UNTOUCHED. ProviderCard adopts it (Task 5) but its definition stays put.
- `VoiceInk/Services/FailureRegistry.swift` / `VoiceInk/Services/FailureEvent.swift` — W3 territory.
- `VoiceInk/Onboarding/CinematicWalkthrough.swift` — onboarding deferred per spec §5 "Out of scope".
- All test files (`VoiceInkTests/*.swift`) — W6 ships no new tests. Existing `PaletteTests` + `FailureRegistryTests` must still pass at the integration build (Task 15).

---

## Migration policy (resolves ambiguity for each design point)

The lead pinned 11 architecture decisions. Restated as the authoritative ruleset for the coder.

1. **Curated lineup as of W6 land.** Final five entries in `MLXModelRegistry.curated`, in this order:
   1. `mlx-community/gemma-4-e2b-it-4bit` — ~1.7 GB, Speed 9, Quality 5, 1.0...3.0s expected, `isExperimental: false`. Replaces the dropped `gemma-3-1b-it-qat-4bit` as the fastest tier; uses the same `gemma3` model type as the production e4b default so loadability under bundled `mlx-swift-lm` 3.31.3 is already proven.
   2. `mlx-community/gemma-4-e4b-it-4bit` — ~2.5 GB, Speed 7, Quality 6, 3.0...7.0s, `false`. Default mid-tier; established working set.
   3. `mlx-community/Qwen3.5-4B-MLX-4bit` — ~2.5 GB, Speed 7, Quality 6, 3.0...7.0s, `false`. Alibaba alternative for the same speed tier.
   4. `mlx-community/gemma-4-26b-a4b-it-4bit` — ~14 GB, Speed 3, Quality 9, 8.0...30.0s, `isExperimental: true`. Kept for users who want to test quality but flagged with EXPERIMENTAL chip + caution copy in the row caption ("Slow on 32 GB base — may exceed 10s. Try only after a fresh restart.").

   Drop entirely: `mlx-community/gemma-3-1b-it-qat-4bit` (regurgitation + capacity-ceiling failures per `0a3f983` + `5c69269` history) and `mlx-community/Qwen3.6-27B-4bit` (27B dense exceeds the spec threshold on 32 GB base; no MoE benefit to recover speed; experimental flag would mislead).

2. **Rating field semantics.**
   - `speedRating: Int` — 1...10 integer. 9-10 = under 3s typical; 6-8 = 3-7s; 3-5 = 7-15s; 1-2 = >15s. Anchored to "typical dictation cleanup output of 50-200 tokens on M-series base 32 GB".
   - `qualityRating: Int` — 1...10 integer. Subjective on instruction-following + correction quality for cleanup tasks. Floor 5 means "usable"; below is dropped from curated.
   - `expectedLatencySeconds: ClosedRange<Double>` — wall-clock window for typical dictation cleanup (50-200 token output). Used in row caption ("Expect 3-7s for typical dictation") AND in the runtime WARN threshold check (Task 4 reads only the upper bound, but the type is a range so the picker row can show min-max instead of a single number).
   - `isExperimental: Bool` — defaults `false`. When `true`, picker row mounts an EXPERIMENTAL chip (`Palette.warn` foreground, glass background) and a one-line caution caption.

3. **Latency filter — relabel, not hard-drop, for the borderline tier.** Spec from user: ≤5s ideal, ≤10s acceptable, >10s reject. The 26B-A4B entry sits in the >10s zone on 32 GB base per research, but the user has expressed interest in trying it (handoff item 1). Per the user's literal instruction "Drop or relabel any model that exceeds the threshold", we **relabel** rather than hard-drop — `isExperimental: true` + warning copy + lower speedRating. The 27B-dense entry is hard-dropped because it has no MoE benefit and no path to ≤10s on 32 GB base. This split (relabel one, drop the other) is the conservative reading of the user's instruction.

4. **Diagnostic instrumentation, not enforcement.** The new WARN log in `MLXProvider.enhance(...)` is observation-only; it does NOT short-circuit generation, raise an error, or skip enhancement. Users who knowingly select the EXPERIMENTAL tier deserve the result they asked for. The WARN line provides ground-truth for future tightening rounds and matches the pattern in the existing `🦾 enhance:` block (lines 99, 128, 132). Format: `🦾 enhance: WARN total=X.XXs exceeds 10s ceiling for model=<id>`.

5. **Segregation criteria.** "Configured" = the provider is in `aiService.connectedProviders` AND in `APIKeyManagementView.galleryProviders`. "Unconfigured" = in `galleryProviders` but NOT in `connectedProviders`. The connectedProviders accessor (AIService.swift:289-309) already encodes the per-provider configuration semantics (API key for keyed providers, downloaded MLX model, ollama liveness, etc.) — do NOT duplicate the logic; reuse it.

6. **Sort order inside each section.**
   - Configured grid: `aiService.selectedProvider` first if it's in the configured set, then the rest sorted by `displayName(for:)` ascending.
   - Unconfigured grid: alphabetical by `displayName(for:)`.
   - Pre-expanded provider on `onAppear` stays as today (the active provider) — segregation does not change which card opens first.

7. **`+` and gear buttons in `EnhancementSettingsView`.** Currently use `Palette.accent.opacity(0.16)` Capsule backgrounds (lines 134-143 + 86-89). Replace with `glassChip(cornerRadius: 8)` for material consistency with the new picker rows. Color (foreground/secondary tint) preserved; only the surface chrome changes. The `ReorderablePromptGrid` body (lines 187-263) is OUT of scope — it's the prompt chip picker grid for the existing `prompt.promptIcon(...)` renderer, which is a separate surface that the spec doesn't list under W6 (it's Prompt-icon authoring, not prompt-chip picker chrome).

8. **`PromptEditorView` re-skin scope.** Header bar (lines 88-112), footer bar (lines 180-202), IconPickerPopover (lines 514-555) are in scope. The split-pane `splitContent` + `editorPane` GlassCard wrapping (lines 116-145) and the inner `predefinedPromptForm` / `customPromptForm` Forms (lines 206-349) are OUT of scope — they're authored content, not chrome. The `TriggerWordsEditor` + `TriggerWordItemView` (lines 379-462) are OUT of scope (W5 territory if anything).

9. **Download progress UI.** Replace the bare `ProgressView(value:)` (`MLXModelPickerView.swift:86-87`) with a chip-vocabulary progress indicator: a `GlassChip` whose width fills proportionally with the download fraction. Use `Palette.accent` for the fill ring and `Palette.hairline` for the empty track. Motion: smooth `.linear(duration: 0.18)` on the fraction-binding change, no spring. Matches the `clusterFadeReduced` / `clusterFade` motion vocabulary in `ClusterMotion.swift:30-35`. Reduce-Motion automatically falls back via SwiftUI's `Material` graceful degradation.

10. **Legacy MLX dir cleanup — one-time migration on app start.** The handoff documented a 9.8 GB orphaned cache at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/MLXModels/` from the mlx-swift 2.x era. Implement as a function in `MLXModelRegistry.swift` (file already references this path via `MLXProvider.applicationSupportModelsRoot()`). Guard with `@AppStorage("legacyMLXDirPurged") private var purged = false` checked from `VoiceInkApp.init()` (or wherever the existing `@StateObject` startup wiring lives — coder greps to find). On first run after upgrade, if the dir exists and is non-empty, recursively delete it and set the flag. Safety: only purge the exact path returned by `applicationSupportModelsRoot()`; never traverse symlinks; log every step via existing `mlxRegistryLogger` so the user can see what was reclaimed in Console.app. Do NOT also wire a per-delete cleanup hook in `MLXModelPickerView.delete(_:)` — the one-time migration is sufficient and per-delete logic risks racing the swift-huggingface cache writes for downloads landing in the new path.

11. **No emoji in code.** Existing `🦾` emoji prefixes in `MLXProvider.swift` log lines are pre-existing user-recognizable instrumentation markers — preserve them in any new log lines added (the new WARN line includes `🦾 enhance: WARN ...` for grep continuity). This is a deliberate exception per CLAUDE.md "no emojis in code" — log instrumentation already established by `fbe6cb4` and unchanged through W3.

---

## Tasks

### Task 0: Audit + read references

**Files:** none (read-only).

- [ ] **Step 0.1: Confirm the curated registry shape**

```bash
grep -n "MLXModelEntry\|curated:" VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift
```

Expected matches: `struct MLXModelEntry: Identifiable, Hashable` + `static let curated: [MLXModelEntry]`. If any other call site also constructs a `MLXModelEntry`, it will need the new fields too — flag for the lead.

- [ ] **Step 0.2: Confirm `connectedProviders` is the right partition source**

```bash
grep -n "connectedProviders" VoiceInk -r --include="*.swift"
```

Expected matches: definition at `VoiceInk/Services/AIEnhancement/AIService.swift:289`, consumers at `PowerMode/PowerModeConfigView.swift:569,577` and `Views/AI Models/APIKeyManagementView.swift:123,130`. If a third surface also depends on it, splitting the gallery doesn't change its semantics — `connectedProviders` is read-only and W6 only adds new readers.

- [ ] **Step 0.3: Confirm the legacy MLXModels path is the right purge target**

```bash
grep -rn "applicationSupportModelsRoot\|MLXModels" VoiceInk --include="*.swift"
```

Expected: declaration in `MLXProvider.swift:197-208` (returns `~/Library/Application Support/<bundle>/MLXModels/`); reference from `MLXModelRegistry.swift:124` (preflight fallback only). The path is correct and there is no other consumer that writes to it — swift-huggingface 0.9.0 lands snapshots under `~/Library/Caches/huggingface/hub/`. Safe to purge in Task 13 once the sentinel guard is wired.

- [ ] **Step 0.4: Confirm no third surface depends on the dropped models**

```bash
grep -rn "gemma-3-1b-it-qat-4bit\|Qwen3.6-27B" VoiceInk --include="*.swift"
```

Expected: only `MLXModelRegistry.swift:24` for the gemma-3-1b entry (no other reference) and zero matches for Qwen3.6-27B (it's already only in the registry). If grep surfaces another file (e.g. a test fixture, a default in `AIService.swift`), reconcile with the lead before proceeding.

- [ ] **Step 0.5: Confirm `VoiceInkApp` `init()` location**

```bash
grep -rn "@main\|@StateObject private var failureRegistry\|init()" VoiceInk/VoiceInkApp.swift VoiceInk/VoiceInk.swift 2>/dev/null | head -20
```

The W3 plan referenced `VoiceInk.swift`; verify the actual filename. Locate the `init()` body where `@StateObject` services are constructed — Task 13 inserts the legacy-dir purge call there.

---

### Task 1: Extend `MLXModelEntry` with rating fields

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift`

- [ ] **Step 1.1: Add the four new fields + member-wise init**

Current (lines 10-15):

```swift
struct MLXModelEntry: Identifiable, Hashable {
    let id: String              // HF repo, e.g. "mlx-community/gemma-4-e4b-it-4bit"
    let displayName: String
    let approximateSizeGB: Double
    let notes: String
}
```

Replace with:

```swift
struct MLXModelEntry: Identifiable, Hashable {
    let id: String              // HF repo, e.g. "mlx-community/gemma-4-e4b-it-4bit"
    let displayName: String
    let approximateSizeGB: Double
    let notes: String

    /// Speed tier on M-series base 32 GB for typical dictation cleanup
    /// (~50-200 token output). 1...10. 9-10 = under 3s; 6-8 = 3-7s;
    /// 3-5 = 7-15s; 1-2 = exceeds 15s. Sourced from research cited in the
    /// W6 plan; refine as users surface real numbers via the WARN log
    /// hook in `MLXProvider.enhance(...)`.
    let speedRating: Int

    /// Subjective quality on instruction-following + correction tasks.
    /// 1...10. Floor 5 = "usable for cleanup"; below 5 is dropped from
    /// the curated set.
    let qualityRating: Int

    /// Expected wall-clock latency window for typical dictation cleanup.
    /// Lower bound = ideal cold-cache hit; upper bound = warm-cache miss
    /// edge. The picker row shows min-max; `MLXProvider` does NOT enforce
    /// this — it logs WARN if `total > 10.0` regardless of which model.
    let expectedLatencySeconds: ClosedRange<Double>

    /// When true, the picker row mounts an EXPERIMENTAL chip + caution
    /// caption. Reserved for entries that exceed the user's >10s reject
    /// threshold but are kept for users who want to test them.
    let isExperimental: Bool

    init(
        id: String,
        displayName: String,
        approximateSizeGB: Double,
        notes: String,
        speedRating: Int,
        qualityRating: Int,
        expectedLatencySeconds: ClosedRange<Double>,
        isExperimental: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.approximateSizeGB = approximateSizeGB
        self.notes = notes
        self.speedRating = speedRating
        self.qualityRating = qualityRating
        self.expectedLatencySeconds = expectedLatencySeconds
        self.isExperimental = isExperimental
    }
}
```

The explicit `init` is required because adding stored properties to a struct without one breaks all existing call sites — `.init(id:displayName:approximateSizeGB:notes:)` would no longer compile. With the explicit init the only call sites that need updating are the curated registry entries themselves (Task 2 below).

---

### Task 2: Update curated registry — drop, relabel, add

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift`

- [ ] **Step 2.1: Update the curated array + doc comment**

Current (lines 17-53 — the entire `enum MLXModelRegistry { ... }` body up to the closing brace):

```swift
enum MLXModelRegistry {
    /// Curated lineup as of April 2026. Three tiers: ~0.7 GB "fastest" (QAT-quantized,
    /// ideal for low-latency cleanup), ~2.5 GB "fast default", and ~14 GB "quality".
    /// All entries verified loadable against the bundled `mlx-swift-lm` 3.31.3
    /// (gemma3 + gemma3_text + gemma4 + qwen3_5 model types are registered).
    static let curated: [MLXModelEntry] = [
        .init(
            id: "mlx-community/gemma-3-1b-it-qat-4bit",
            displayName: "Gemma 3 1B QAT (Fastest)",
            approximateSizeGB: 0.7,
            notes: "Google. Smallest viable. QAT (quantization-aware training) minimizes 4-bit accuracy loss. ~3-5x faster than gemma-4-e4b on M-series."
        ),
        .init(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B Instruct (4-bit)",
            approximateSizeGB: 2.5,
            notes: "Google. Built for on-device. Strong instruction-following, mid-tier latency."
        ),
        .init(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit",
            displayName: "Qwen 3.5 4B (4-bit)",
            approximateSizeGB: 2.5,
            notes: "Alibaba. Same speed tier; terse, on-prompt outputs."
        ),
        .init(
            id: "mlx-community/gemma-4-26b-a4b-it-4bit",
            displayName: "Gemma 4 26B-A4B Instruct (4-bit, MoE)",
            approximateSizeGB: 14.0,
            notes: "Big-model quality at small-model latency (only 4B active params per pass)."
        ),
        .init(
            id: "mlx-community/Qwen3.6-27B-4bit",
            displayName: "Qwen 3.6 27B (4-bit)",
            approximateSizeGB: 14.0,
            notes: "Newest Qwen dense. Best raw quality. ~2-3s per dictation."
        ),
    ]
}
```

Replace with:

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
    static let curated: [MLXModelEntry] = [
        .init(
            id: "mlx-community/gemma-4-e2b-it-4bit",
            displayName: "Gemma 4 E2B (Fastest)",
            approximateSizeGB: 1.7,
            notes: "Google. Smallest curated entry. Same gemma3 type as the e4b default — already proven loadable. Finishes typical dictation in 1-3s. Replaces gemma-3-1b.",
            speedRating: 9,
            qualityRating: 5,
            expectedLatencySeconds: 1.0...3.0
        ),
        .init(
            id: "mlx-community/gemma-4-e4b-it-4bit",
            displayName: "Gemma 4 E4B Instruct",
            approximateSizeGB: 2.5,
            notes: "Google. Default mid-tier. Strong instruction-following, ~30-50 tok/s on M-series base 32 GB.",
            speedRating: 7,
            qualityRating: 6,
            expectedLatencySeconds: 3.0...7.0
        ),
        .init(
            id: "mlx-community/Qwen3.5-4B-MLX-4bit",
            displayName: "Qwen 3.5 4B",
            approximateSizeGB: 2.5,
            notes: "Alibaba. Same speed tier as gemma-4-e4b; terse, on-prompt outputs.",
            speedRating: 7,
            qualityRating: 6,
            expectedLatencySeconds: 3.0...7.0
        ),
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
    ]
}
```

Note the dropped entries: `gemma-3-1b-it-qat-4bit` (regurgitation + capacity ceiling — `0a3f983` history) and `Qwen3.6-27B-4bit` (27B dense, no MoE benefit, exceeds threshold on 32 GB base with no relabel path). The `gemma-4-e2b-it-4bit` addition replaces the dropped fastest tier; it uses the same `gemma3` model type as the existing e4b default, so loadability under bundled `mlx-swift-lm` 3.31.3 is already proven by production traffic. The remaining quality concern (PLE-quant degradation) is documented in Risks/unknowns #1 and is observation-only at this stage — same risk applies to the production e4b default and has not surfaced as a user-reported issue for the cleanup task.

---

### Task 3: Add `purgeLegacyApplicationSupportModelsIfPresent` helper

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift`

- [ ] **Step 3.1: Append the cleanup helper at the bottom of the file**

Insert immediately after the closing brace of the `#endif` block at the bottom of the file (the existing #else / #endif fence around `MLXModelDownloader`):

```swift
// MARK: - Legacy migration

extension MLXModelRegistry {
    /// One-time purge of the mlx-swift 2.x cache directory. The 2.x era stored
    /// snapshots under `~/Library/Application Support/<bundle>/MLXModels/`;
    /// swift-huggingface 0.9.0 (mlx-swift-lm 3.31.3) lands them under
    /// `~/Library/Caches/huggingface/hub/` instead, leaving the legacy dir
    /// orphaned. One install was observed holding 9.8 GB stale here.
    ///
    /// Safety:
    ///   • Only the exact path returned by `MLXProvider.applicationSupportModelsRoot()`
    ///     is touched. No traversal of symlinks; no recursion outside that root.
    ///   • Every step logged via `mlxRegistryLogger` so reclaimed bytes are
    ///     auditable in Console.app.
    ///   • Caller (App init) gates this with `@AppStorage("legacyMLXDirPurged")`
    ///     so it runs at most once per install.
    static func purgeLegacyApplicationSupportModelsIfPresent() {
        let root = MLXProvider.applicationSupportModelsRoot()
        let fm = FileManager.default

        guard fm.fileExists(atPath: root.path) else {
            mlxRegistryLogger.notice("🦾 legacy purge: skip — root not present at \(root.path, privacy: .public)")
            return
        }

        let contents = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        if contents.isEmpty {
            mlxRegistryLogger.notice("🦾 legacy purge: skip — root empty at \(root.path, privacy: .public)")
            return
        }

        let sizeBytes = (try? root.directoryAllocatedSize()) ?? 0
        do {
            try fm.removeItem(at: root)
            mlxRegistryLogger.notice("🦾 legacy purge: ✅ removed \(root.path, privacy: .public) (~\(sizeBytes / 1_073_741_824, privacy: .public) GB)")
        } catch {
            mlxRegistryLogger.error("🦾 legacy purge: ❌ \(error.localizedDescription, privacy: .public)")
        }
    }
}

private extension URL {
    /// Best-effort recursive byte count for logging only. Returns 0 on any
    /// enumeration error — the purge proceeds regardless.
    func directoryAllocatedSize() throws -> Int {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: self,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: keys)
            total += values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0
        }
        return total
    }
}
```

The `directoryAllocatedSize()` helper is local-private to this file — if a similar helper already exists in `Utils/` (unlikely), prefer the existing one; coder confirms via:

```bash
grep -rn "directoryAllocatedSize\|fileAllocatedSizeKey" VoiceInk --include="*.swift"
```

Expected: zero matches before W6 lands.

---

### Task 4: Add MLX latency WARN instrumentation

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/MLXProvider.swift`

- [ ] **Step 4.1: Insert the threshold check**

Current (`enhance(...)`, lines 130-133):

```swift
            try Task.checkCancellation()
            let totalElapsed = Date().timeIntervalSince(totalStart)
            Self.logger.notice("🦾 enhance: total=\(totalElapsed, format: .fixed(precision: 2), privacy: .public)s")
            return output
```

Replace with:

```swift
            try Task.checkCancellation()
            let totalElapsed = Date().timeIntervalSince(totalStart)
            Self.logger.notice("🦾 enhance: total=\(totalElapsed, format: .fixed(precision: 2), privacy: .public)s")
            if totalElapsed > 10.0 {
                Self.logger.warning("🦾 enhance: WARN total=\(totalElapsed, format: .fixed(precision: 2), privacy: .public)s exceeds 10s ceiling for model=\(self.modelId, privacy: .public)")
            }
            return output
```

Observation-only. Does NOT short-circuit generation, raise an error, or skip the return. Provides ground-truth for users + future tightening rounds.

---

### Task 5: Re-skin `MLXModelPickerView` rows with W1 vocabulary

**Files:**
- Modify: `VoiceInk/Views/AI Models/MLXModelPickerView.swift`

- [ ] **Step 5.1: Replace the whole `modelRow(_:)` body**

Current (lines 26-62):

```swift
    @ViewBuilder
    private func modelRow(_ model: MLXModelEntry) -> some View {
        let isActive = selectedModelId == model.id
        let isDownloaded = statuses[model.id] == .downloaded

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayName).font(.body)
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
                Text("\(String(format: "%.1f", model.approximateSizeGB)) GB · \(model.notes)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            useButton(for: model, isDownloaded: isDownloaded, isActive: isActive)
            statusControl(for: model)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.15),
                        lineWidth: isActive ? 1.5 : 1)
        )
    }
```

Replace with:

```swift
    @ViewBuilder
    private func modelRow(_ model: MLXModelEntry) -> some View {
        let isActive = selectedModelId == model.id
        let isDownloaded = statuses[model.id] == .downloaded
        let latency = model.expectedLatencySeconds

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(model.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                if isActive { activeChip }
                if model.isExperimental { experimentalChip }
                Spacer()
                useButton(for: model, isDownloaded: isDownloaded, isActive: isActive)
                statusControl(for: model)
            }

            HStack(spacing: 6) {
                ratingChip(label: "Speed", value: model.speedRating)
                ratingChip(label: "Quality", value: model.qualityRating)
                latencyChip(min: latency.lowerBound, max: latency.upperBound)
                Spacer()
                Text("\(String(format: "%.1f", model.approximateSizeGB)) GB")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.onyxMute)
            }

            Text(model.notes)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isActive ? Palette.accent.opacity(0.10) : Color.clear)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? Palette.accent.opacity(0.55) : Palette.hairline,
                        lineWidth: isActive ? 1.5 : 1)
        )
    }

    private var activeChip: some View {
        Text("ACTIVE")
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(0.06 * 9.5)
            .foregroundColor(Palette.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Palette.accent.opacity(0.16)))
            .overlay(Capsule().stroke(Palette.accent.opacity(0.42), lineWidth: 0.5))
    }

    private var experimentalChip: some View {
        Text("EXPERIMENTAL")
            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            .tracking(0.06 * 9.5)
            .foregroundColor(Palette.warn)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(Palette.warn.opacity(0.16)))
            .overlay(Capsule().stroke(Palette.warn.opacity(0.42), lineWidth: 0.5))
    }

    private func ratingChip(label: String, value: Int) -> some View {
        Text("\(label) \(value)/10")
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(0.06 * 10.5)
            .foregroundColor(Palette.onyxFg)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.white.opacity(0.06))
            )
            .overlay(
                Capsule().stroke(Palette.hairline, lineWidth: 0.5)
            )
    }

    private func latencyChip(min: Double, max: Double) -> some View {
        let text = "\(formatSecs(min))-\(formatSecs(max))s"
        return Text(text)
            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
            .tracking(0.06 * 10.5)
            .foregroundColor(Palette.onyxMute)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.white.opacity(0.04))
            )
            .overlay(
                Capsule().stroke(Palette.hairlineSoft, lineWidth: 0.5)
            )
    }

    private func formatSecs(_ value: Double) -> String {
        value < 10 ? String(format: "%.0f", value) : String(format: "%.0f", value)
    }
```

Note the chip family deliberately reuses `Capsule()` rather than the `.glassChip()` modifier from `GlassChip.swift` because the chips here render INSIDE a panel that already supplies the glass material — nested glassChips would double-stack the inner highlight + shadow per `GlassChip.swift:32-58`. The outer panel uses `.ultraThinMaterial` matching the GlassChip body fill.

- [ ] **Step 5.2: Replace `statusControl(for:)` to swap `ProgressView` for a chip-vocabulary progress bar**

Current (lines 79-99):

```swift
    @ViewBuilder
    private func statusControl(for model: MLXModelEntry) -> some View {
        switch statuses[model.id] ?? .notDownloaded {
        case .notDownloaded:
            Button("Download") { Task { await download(model) } }
                .buttonStyle(.borderedProminent)
        case .downloading(let fraction):
            ProgressView(value: fraction)
                .frame(width: 100)
        case .downloaded:
            Button("Delete") { delete(model) }
                .buttonStyle(.borderless)
        case .failed(let msg):
            VStack(alignment: .trailing, spacing: 2) {
                Text("Failed").font(.caption).foregroundStyle(.red)
                Text(msg).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Button("Retry") { Task { await download(model) } }
                    .controlSize(.small)
            }
        }
    }
```

Replace with:

```swift
    @ViewBuilder
    private func statusControl(for model: MLXModelEntry) -> some View {
        switch statuses[model.id] ?? .notDownloaded {
        case .notDownloaded:
            Button("Download") { Task { await download(model) } }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        case .downloading(let fraction):
            downloadProgressChip(fraction: fraction)
        case .downloaded:
            Button("Delete") { delete(model) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
        case .failed(let msg):
            VStack(alignment: .trailing, spacing: 2) {
                Text("Failed")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.accent)
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 140, alignment: .trailing)
                Button("Retry") { Task { await download(model) } }
                    .controlSize(.small)
            }
        }
    }

    /// W6 chip-vocabulary download progress — replaces the bare ProgressView.
    /// Width 110pt; `Palette.accent` fills the leading portion proportional
    /// to `fraction`; the trailing remainder shows the hairline track. Motion
    /// matches `Animation.clusterFadeReduced` (0.18s linear) so the bar reads
    /// the same as the cluster's collapse vocabulary. Spec §5#6.
    private func downloadProgressChip(fraction: Double) -> some View {
        let clamped = max(0.0, min(1.0, fraction))
        let pct = Int(clamped * 100)
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.05))
                    .overlay(Capsule().stroke(Palette.hairline, lineWidth: 0.5))
                Capsule()
                    .fill(Palette.accent.opacity(0.55))
                    .frame(width: width * clamped)
                    .animation(.linear(duration: 0.18), value: clamped)
                Text("\(pct)%")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 9.5)
                    .foregroundColor(Palette.onyxFg)
                    .padding(.leading, 8)
            }
        }
        .frame(width: 110, height: 18)
    }
```

- [ ] **Step 5.3: Update the file header doc-comment to reference §5#6**

The file currently has no top-level doc-comment. Add at the top, immediately after `import SwiftUI`:

```swift
// MARK: - MLXModelPickerView
//
// On-device model picker rendered inside `ProviderCard`'s `.mlx` expanded
// arm. W6 re-skin: rows show speed + quality ratings + expected latency
// chips inheriting the glass vocabulary; experimental tier surfaces a
// caution chip. Spec §5 row W6 + W6 plan
// `docs/superpowers/plans/W6-mlx-quality-and-segregation.md`.
```

- [ ] **Step 5.4: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/AI\ Models/MLXModelPickerView.swift | head -180
```

Expected: row rebuild with new chip family, status-control swap to GeometryReader-based progress chip, header doc-comment addition.

---

### Task 6: Re-skin `ProviderCard` chrome

**Files:**
- Modify: `VoiceInk/Views/AI Models/ProviderCard.swift`

- [ ] **Step 6.1: Update the card shape to 14pt panel radius + drop the hover lift**

Current (lines 123-154):

```swift
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture { toggleExpand() }

            if isExpanded {
                Divider()
                    .padding(.horizontal, 14)
                expanded
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            HaloMaterial(shape: shape, phase: .hidden)
        )
        .overlay(
            shape.stroke(
                isActive ? tint.opacity(0.55) : tint.opacity(0.18),
                lineWidth: isActive ? 1.5 : 0.5
            )
        )
        .clipShape(shape)
        .offset(y: hovering ? -4 : 0)
        .animation(motion.reduceMotion ? nil : .easeOut(duration: 0.18), value: hovering)
        .animation(motion.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: isExpanded)
        .onHover { hovering = $0 }
        .onAppear { onCardAppear() }
    }
```

Replace with:

```swift
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture { toggleExpand() }

            if isExpanded {
                Divider()
                    .background(Palette.hairlineSoft)
                    .padding(.horizontal, 14)
                expanded
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            HaloMaterial(shape: shape, phase: .hidden)
        )
        .overlay(
            shape.stroke(
                isActive ? Palette.accent.opacity(0.55) : Palette.hairline,
                lineWidth: isActive ? 1.5 : 1
            )
        )
        .clipShape(shape)
        .animation(motion.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: isExpanded)
        .onHover { hovering = $0 }
        .onAppear { onCardAppear() }
    }
```

Three diffs: (a) corner radius 16 → 14 to match spec §1 panel token; (b) `.offset(y: hovering ? -4 : 0)` removed per spec §5#8 ("`GlassCard` hover-lift removed"); (c) the `.easeOut(duration: 0.18) value: hovering` animation goes with the offset removal; (d) stroke color migrates from per-provider `tint` to `Palette.accent` (single-accent post-W1) but remains driven by `isActive`. The `hovering` state is kept (`onHover` still updates it) so a future spec iteration can introduce a non-translate hover signal (e.g. accent-glow swell) without rewiring the boolean.

- [ ] **Step 6.2: Re-skin the ACTIVE badge in the header (lines 188-197)**

Current:

```swift
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .tracking(0.5)
                            .foregroundColor(tint)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(tint.opacity(0.16)))
                            .overlay(Capsule().stroke(tint.opacity(0.32), lineWidth: 0.5))
                    }
```

Replace with:

```swift
                    if isActive {
                        Text("ACTIVE")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .tracking(0.06 * 9.5)
                            .foregroundColor(Palette.accent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Palette.accent.opacity(0.16)))
                            .overlay(Capsule().stroke(Palette.accent.opacity(0.42), lineWidth: 0.5))
                    }
```

Two diffs: (a) `.rounded` design → `.monospaced` per spec §1 ("SF Mono uppercase tracking 0.06em for state labels and chip keys"); (b) the local `tint` constant migrates to `Palette.accent` (single-accent post-W1).

- [ ] **Step 6.3: Replace the inline status-pill block with the existing `StatusPill` component**

Current (lines 209-228):

```swift
            // Status dot + chevron
            HStack(spacing: 8) {
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .foregroundColor(isConnected ? Palette.success : Palette.neutral)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill((isConnected ? Palette.success : Palette.neutral).opacity(0.14))
                    )
                    .overlay(
                        Capsule().stroke((isConnected ? Palette.success : Palette.neutral).opacity(0.32), lineWidth: 0.5)
                    )

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
```

Replace with:

```swift
            HStack(spacing: 8) {
                StatusPill(text: statusText, tone: isConnected ? .positive : .neutral)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
```

`StatusPill` is already defined in `APIKeyManagementView.swift:144-182` and ProviderCard pulls it via the same module — no import needed. DRY win + the existing component already encodes the W1-friendly green/neutral tones.

- [ ] **Step 6.4: Re-tint the provider tile fill from per-provider tint to single accent**

Current (lines 161-169):

```swift
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.18))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(tint.opacity(0.36), lineWidth: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(tint)
            }
            .frame(width: 36, height: 36)
```

Replace with:

```swift
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.accent.opacity(0.18))
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Palette.accent.opacity(0.36), lineWidth: 0.5)
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Palette.accent)
            }
            .frame(width: 36, height: 36)
```

The local `tint` computed property is preserved (still wired to `ProviderChipStyle.tint(for:)` which already returns `Palette.accent` post-W1) — call sites just inline `Palette.accent` directly here for clarity. If `ProviderChipStyle` later re-introduces per-provider tints (per its own forward-looking comment), this site automatically re-uses them via `tint`. Restore by reverting these three lines back to `tint`.

- [ ] **Step 6.5: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/AI\ Models/ProviderCard.swift | head -120
```

Expected: corner radius 16 → 14, hover-lift removed (offset + 0.18s easeOut animation deleted), divider tinted hairlineSoft, stroke uses Palette.accent, ACTIVE badge re-styled mono, status pill collapsed to StatusPill component, provider tile re-tinted single-accent.

---

### Task 7: Segregate AI Enhancement gallery into Configured + Unconfigured sections

**Files:**
- Modify: `VoiceInk/Views/AI Models/APIKeyManagementView.swift`

- [ ] **Step 7.1: Add the partition computed properties + section-label helper**

Insert immediately after `static var galleryProviders: [AIProvider]` (around line 43):

```swift
    /// Subset of `galleryProviders` that the user has configured (API key
    /// present, MLX model downloaded, ollama reachable, etc.). Driven by
    /// `aiService.connectedProviders` — the existing single source of truth
    /// in `AIService.swift:289-309`. Sorted: the active provider first if
    /// it's in the configured set, then alphabetical by display name.
    private var configuredProviders: [AIProvider] {
        let connectedSet = Set(aiService.connectedProviders)
        let gallery = APIKeyManagementView.galleryProviders.filter { connectedSet.contains($0) }
        let active = aiService.selectedProvider
        if gallery.contains(active) {
            let rest = gallery.filter { $0 != active }
                .sorted { ProviderChipStyle.displayName(for: $0) < ProviderChipStyle.displayName(for: $1) }
            return [active] + rest
        }
        return gallery.sorted { ProviderChipStyle.displayName(for: $0) < ProviderChipStyle.displayName(for: $1) }
    }

    /// Complement of `configuredProviders` over `galleryProviders`. Sorted
    /// alphabetical by display name.
    private var unconfiguredProviders: [AIProvider] {
        let connectedSet = Set(aiService.connectedProviders)
        return APIKeyManagementView.galleryProviders
            .filter { !connectedSet.contains($0) }
            .sorted { ProviderChipStyle.displayName(for: $0) < ProviderChipStyle.displayName(for: $1) }
    }

    /// Section label rendered above each grid. SF Mono uppercase tracking
    /// 0.06em — same vocabulary as the cluster's chip keys (spec §1).
    private func sectionLabel(_ text: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundColor(Palette.onyxMute)
            Text("\(count)")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundColor(Palette.onyxMute.opacity(0.7))
            Spacer()
        }
        .padding(.top, 6)
    }
```

- [ ] **Step 7.2: Replace the single `LazyVGrid` with two grids**

Current (lines 45-66):

```swift
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Compact identity preview — chip for the active provider.
                ProviderChip(
                    provider: aiService.selectedProvider,
                    model: providerChipModel,
                    connected: providerChipConnected
                )
                .padding(.bottom, 4)

                LazyVGrid(columns: APIKeyManagementView.columns, spacing: 12) {
                    ForEach(APIKeyManagementView.galleryProviders, id: \.self) { provider in
                        ProviderCard(
                            provider: provider,
                            expandedProvider: $expandedProvider,
                            onActivate: { aiService.selectedProvider = provider }
                        )
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
```

Replace with:

```swift
    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Compact identity preview — chip for the active provider.
                ProviderChip(
                    provider: aiService.selectedProvider,
                    model: providerChipModel,
                    connected: providerChipConnected
                )
                .padding(.bottom, 4)

                // CONFIGURED — providers with credentials / downloaded models.
                let configured = configuredProviders
                if !configured.isEmpty {
                    sectionLabel("CONFIGURED", count: configured.count)
                    LazyVGrid(columns: APIKeyManagementView.columns, spacing: 12) {
                        ForEach(configured, id: \.self) { provider in
                            ProviderCard(
                                provider: provider,
                                expandedProvider: $expandedProvider,
                                onActivate: { aiService.selectedProvider = provider }
                            )
                        }
                    }
                } else {
                    Text("No providers configured yet. Pick one below to add a key or download a local model.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }

                // UNCONFIGURED — providers without credentials / no model downloaded.
                let unconfigured = unconfiguredProviders
                if !unconfigured.isEmpty {
                    sectionLabel("AVAILABLE", count: unconfigured.count)
                    LazyVGrid(columns: APIKeyManagementView.columns, spacing: 12) {
                        ForEach(unconfigured, id: \.self) { provider in
                            ProviderCard(
                                provider: provider,
                                expandedProvider: $expandedProvider,
                                onActivate: { aiService.selectedProvider = provider }
                            )
                            .opacity(0.85)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
```

The 0.85 opacity on unconfigured cards is a soft visual deprioritization — they remain fully interactive (tap to expand + configure). When a user configures one, it transitions to the configured grid on the next render because `connectedProviders` updates via the existing reactivity (API key save, MLX download complete, etc.).

- [ ] **Step 7.3: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/AI\ Models/APIKeyManagementView.swift | head -100
```

Expected: two new computed properties + sectionLabel helper, single LazyVGrid replaced with two LazyVGrids guarded by emptiness checks, empty-state hint for the "no configured providers" case.

---

### Task 8: Re-skin `EnhancementSettingsView` prompt-grid header buttons

**Files:**
- Modify: `VoiceInk/Views/EnhancementSettingsView.swift`

- [ ] **Step 8.1: Re-skin the gear settings button (lines 75-92)**

Current:

```swift
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            isEditingPrompt = false
                            selectedPromptForEdit = nil
                            isShowingSettings.toggle()
                        }
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isShowingSettings ? Palette.accent : .secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Enhancement settings")
```

Replace with:

```swift
                    Button {
                        withAnimation(.smooth(duration: 0.3)) {
                            isEditingPrompt = false
                            selectedPromptForEdit = nil
                            isShowingSettings.toggle()
                        }
                    } label: {
                        Image(systemName: "gear")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(isShowingSettings ? Palette.accent : .secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.ultraThinMaterial)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Palette.hairline, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Enhancement settings")
```

- [ ] **Step 8.2: Re-skin the `+` add-prompt button (lines 126-146)**

Current:

```swift
                    Button {
                        openPromptPanel()
                        withAnimation(.smooth(duration: 0.3)) {
                            isEditingPrompt = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Palette.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Palette.accent.opacity(0.16))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Palette.accent.opacity(0.32), lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Add new prompt")
```

Replace with:

```swift
                    Button {
                        openPromptPanel()
                        withAnimation(.smooth(duration: 0.3)) {
                            isEditingPrompt = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Palette.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Palette.accent.opacity(0.14))
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(.ultraThinMaterial)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Palette.accent.opacity(0.42), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Add new prompt")
```

The `ReorderablePromptGrid` body itself (lines 187-263) stays untouched — that's the prompt-icon authoring grid, not the chrome surface in W6's scope.

---

### Task 9: Re-skin `PromptEditorView` chrome (header / footer / icon picker)

**Files:**
- Modify: `VoiceInk/Views/PromptEditorView.swift`

- [ ] **Step 9.1: Replace the `headerBar` close button (lines 88-112)**

Current:

```swift
    private var headerBar: some View {
        HStack(spacing: 12) {
            Text(headerTitle)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()

            Button(action: dismissPanel) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider().opacity(0.5), alignment: .bottom)
    }
```

Replace with:

```swift
    private var headerBar: some View {
        HStack(spacing: 12) {
            Text(headerTitle)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            Button(action: dismissPanel) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Palette.hairlineSoft)
                .frame(height: 1),
            alignment: .bottom
        )
    }
```

Three diffs: (a) headline font swapped to system 14 semibold (per spec §1 "System for body, prose, main-window content"); (b) close button rebuilt to glass-chip vocabulary with 8pt rounded rectangle replacing the circle background; (c) divider replaced by an explicit `Palette.hairlineSoft` rect for material consistency with the cluster panel chrome.

- [ ] **Step 9.2: Re-skin `footerBar` (lines 180-202)**

Current:

```swift
    private var footerBar: some View {
        HStack {
            Button("Cancel") { dismissPanel() }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                save()
                dismissPanel()
            } label: {
                Text("Save Changes").frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isEditingPredefinedPrompt ? false : (title.isEmpty || promptText.isEmpty))
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
    }
```

Replace with:

```swift
    private var footerBar: some View {
        HStack {
            Button("Cancel") { dismissPanel() }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

            Spacer()

            Button {
                save()
                dismissPanel()
            } label: {
                Text("Save Changes")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(minWidth: 100)
            }
            .buttonStyle(.borderedProminent)
            .tint(Palette.accent)
            .disabled(isEditingPredefinedPrompt ? false : (title.isEmpty || promptText.isEmpty))
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .fill(Palette.hairlineSoft)
                .frame(height: 1),
            alignment: .top
        )
    }
```

Two diffs: (a) `.tint(Palette.accent)` pins the borderedProminent fill to the W1 accent rather than the system accent (which on a re-themed dark window may not match); (b) hairline-soft top divider matches the header bottom divider.

- [ ] **Step 9.3: Re-skin the `IconPickerPopover` selected-state ring (lines 530-538)**

Current:

```swift
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(selectedIcon == icon ? Color(NSColor.windowBackgroundColor) : Color(NSColor.controlBackgroundColor))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(selectedIcon == icon ? Color(NSColor.separatorColor) : Color.secondary.opacity(0.2), lineWidth: selectedIcon == icon ? 2 : 1)
                                )
```

Replace with:

```swift
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selectedIcon == icon ? Palette.accent.opacity(0.14) : Color(NSColor.controlBackgroundColor))
                                .frame(width: 52, height: 52)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selectedIcon == icon ? Palette.accent.opacity(0.55) : Palette.hairlineSoft, lineWidth: selectedIcon == icon ? 1.5 : 1)
                                )
```

Three diffs: (a) corner radius 12 → 10 (chip token per spec §1); (b) selected fill swaps from `windowBackgroundColor` to `Palette.accent` muted (signals state with the W1 vocabulary); (c) selected stroke swaps from `separatorColor` to `Palette.accent.opacity(0.55)` matching the picker row + provider card stroke. The 1.1× scale-up on selection (line 545) stays — it's a behavioral signal, not a chrome token.

---

### Task 10: Re-skin `EnhancementSettingsPanel` close button

**Files:**
- Modify: `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`

- [ ] **Step 10.1: Replace the close button (lines 25-33)**

Current:

```swift
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
```

Replace with:

```swift
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Palette.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Close")
```

Same chrome as the `PromptEditorView` close button in Task 9.1. The two panels share the slidingPanel host; their headers should read identically.

- [ ] **Step 10.2: Replace the bottom hairline of the header (lines 39-41)**

Current:

```swift
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )
```

Replace with:

```swift
            .overlay(
                Rectangle()
                    .fill(Palette.hairlineSoft)
                    .frame(height: 1),
                alignment: .bottom
            )
```

---

### Task 11: Wire one-time legacy MLX dir purge into App init

**Files:**
- Modify: `VoiceInk/VoiceInk.swift` (or `VoiceInk/VoiceInkApp.swift` — coder confirmed location in Task 0.5)

- [ ] **Step 11.1: Add an `@AppStorage` sentinel near the existing app-level keys**

Add a new `@AppStorage` near the other app-level service declarations:

```swift
    @AppStorage("legacyMLXDirPurged") private var legacyMLXDirPurged: Bool = false
```

- [ ] **Step 11.2: Insert the purge call inside `init()` after services are constructed**

Locate the end of the `init()` body (after the FailureRegistry attach + StateObject wrap from W3 Task 13, and before any other side-effect bootstraps). Insert:

```swift
        // One-time migration: reclaim the legacy `MLXModels/` cache from the
        // mlx-swift 2.x era. Sentinel-guarded so it only runs once per install.
        // `swift-huggingface` 0.9.0 lands snapshots under `~/Library/Caches/`
        // instead, leaving the legacy dir orphaned. Spec §5 row W6 + W6 plan.
        if !legacyMLXDirPurged {
            MLXModelRegistry.purgeLegacyApplicationSupportModelsIfPresent()
            legacyMLXDirPurged = true
        }
```

The sentinel is set unconditionally — even if the purge skipped (no dir, empty dir, removeItem error) the next launch should not retry the work. The `mlxRegistryLogger` line in the helper records what happened for the user's audit trail.

---

### Task 12: Compile-error sweep

**Files:** none (verification).

- [ ] **Step 12.1: Confirm all `MLXModelEntry` constructions use the new init**

```bash
grep -rn "MLXModelEntry(" VoiceInk --include="*.swift"
```

Expected matches: only inside `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift` curated array. If any other file constructs an entry, it must be updated to pass the new fields. None expected pre-W6.

- [ ] **Step 12.2: Confirm dropped models are gone from the registry**

```bash
grep -rn "gemma-3-1b-it-qat-4bit\|Qwen3.6-27B" VoiceInk --include="*.swift"
```

Expected: zero matches after Task 2 lands.

- [ ] **Step 12.3: Confirm the legacy purge helper is referenced exactly twice**

```bash
grep -rn "purgeLegacyApplicationSupportModelsIfPresent\|legacyMLXDirPurged" VoiceInk --include="*.swift"
```

Expected matches:
- `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift` (definition)
- `VoiceInk/VoiceInk.swift` (or `VoiceInkApp.swift`) — `@AppStorage` declaration + `if !legacyMLXDirPurged` block + the call (3 lines).

Total ≥ 4 lines.

- [ ] **Step 12.4: Confirm the new MLX WARN line exists**

```bash
grep -n "exceeds 10s ceiling" VoiceInk/Services/AIEnhancement/MLXProvider.swift
```

Expected: one match.

- [ ] **Step 12.5: Confirm `connectedProviders` is read-only and no W6 surface mutates it**

```bash
grep -rn "connectedProviders\s*=" VoiceInk --include="*.swift"
```

Expected: zero matches (the property is a computed accessor — no assignment is valid Swift). If the grep surfaces anything, the segregation logic was implemented incorrectly.

- [ ] **Step 12.6: Confirm `ProviderCard` no longer applies the 4pt hover lift**

```bash
grep -n "offset(y: hovering" VoiceInk/Views/AI\ Models/ProviderCard.swift
```

Expected: zero matches (the line was deleted in Task 6.1).

- [ ] **Step 12.7: Confirm no W6 file introduces an emoji literal in code (excluding the preserved `🦾` log instrumentation)**

```bash
grep -rnE "[\x{1F300}-\x{1FAFF}]" VoiceInk/Views/AI\ Models/MLXModelPickerView.swift VoiceInk/Views/AI\ Models/ProviderCard.swift VoiceInk/Views/AI\ Models/APIKeyManagementView.swift VoiceInk/Views/PromptEditorView.swift VoiceInk/Views/Components/EnhancementSettingsPanel.swift VoiceInk/Views/EnhancementSettingsView.swift 2>/dev/null
```

Expected: zero matches. The `🦾` emoji is only allowed in `MLXProvider.swift` log lines (pre-existing instrumentation marker per migration policy point 11). If grep surfaces an emoji elsewhere, remove it.

---

### Task 13: Full integration build (the gate) + handback

**Files:** none.

- [ ] **Step 13.1: Run `make local`**

```bash
/usr/bin/make local 2>&1 | tail -40
```

Expected last lines:

```
** BUILD SUCCEEDED **
Copying VoiceInk.app to ~/Downloads...
Build complete! App saved to: ~/Downloads/VoiceInk.app
```

If `BUILD FAILED`, scan for `error:` lines:

```bash
grep -nE "^.* error:" /tmp/voiceink-build.log 2>/dev/null | head -20
```

Common diagnostics:
- `missing argument for parameter 'speedRating' in call` → a `MLXModelEntry.init(...)` site outside the curated array exists; locate via `grep -rn "MLXModelEntry(" VoiceInk` and add the new fields.
- `unknown model type 'gemma3'` for the new e2b entry → impossible (the existing e4b default already uses this type and ships green). If it surfaces, the bundled framework version regressed; reconcile with the lead.
- `cannot find 'StatusPill' in scope` → ProviderCard is in the same module as `APIKeyManagementView` (where `StatusPill` is defined); should resolve. If it doesn't, the per-target file membership of `APIKeyManagementView.swift` may be wrong — check Xcode's File Inspector for both files.
- `value of type 'AIService' has no member 'connectedProviders'` → impossible (verified Task 0.2); means the file was unintentionally edited.
- `cannot find 'Palette.hairlineSoft' in scope` → typo; the W1 token is `Palette.hairlineSoft` per `Palette.swift:59`.

- [ ] **Step 13.2: Run the existing test suite (no W6 tests added)**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: all existing tests pass — `PaletteTests` (2), `FailureRegistryTests` (5), `VoiceInkUITests` (4). If `FailureRegistryTests` regress, W6 touched something it shouldn't have.

- [ ] **Step 13.3: Sanity-launch + visual verification**

```bash
/usr/bin/killall VoiceInk 2>/dev/null
open ~/Downloads/VoiceInk.app
sleep 3
ps aux | grep -E "/VoiceInk\.app/Contents/MacOS/VoiceInk" | grep -v grep | head -1
```

Expected: a running process. Manually verify:
- Open Settings → AI Enhancement → AI Provider Integration. Confirm the gallery shows two labeled grids ("CONFIGURED N" and "AVAILABLE M") with the correct partitions.
- Expand the MLX provider card. Confirm 4 curated rows render (gemma-4-e2b, gemma-4-e4b, qwen-3.5-4b, gemma-4-26b-a4b experimental). Each row shows a Speed N/10 chip, Quality N/10 chip, latency-range chip, and size in the right corner.
- Confirm the gemma-4-26b-a4b row shows an EXPERIMENTAL chip (Palette.warn — amber).
- Tap Download on a small model. Confirm the download progress chip fills with `Palette.accent` and shows a percentage; on completion it transitions to a `Delete` button.
- Confirm `gemma-3-1b-it-qat-4bit` and `Qwen3.6-27B-4bit` are NOT present.
- Open Settings → Enhancement Prompts. Click `+`. Confirm the prompt editor panel chrome (header xmark + Save Changes button) renders with the new glass material.
- Confirm `~/Library/Application Support/com.prakashjoshipax.VoiceInk/MLXModels/` does NOT exist after first launch (it was purged on init). Verify in Console.app: `log show --last 5m --predicate 'subsystem == "com.prakashjoshipax.voiceink" AND category == "MLXModelDownloader"'` shows a `🦾 legacy purge:` line.
- If you have the EXPERIMENTAL model downloaded, run a dictation cycle with it active. After enhancement completes, check Console.app for either `🦾 enhance: total=X.XXs` (under 10s — the WARN didn't trigger) OR `🦾 enhance: WARN total=X.XXs exceeds 10s ceiling for model=mlx-community/gemma-4-26b-a4b-it-4bit` (over 10s — confirms the diagnostic hook). Both outcomes are valid; the WARN is observation-only.

- [ ] **Step 13.4: VoiceOver verification**

Cmd+F5 to enable VoiceOver. Tab through the AI Provider Integration section. VO should read each ProviderCard's display name + status. The new EXPERIMENTAL chip on the MLX picker reads as "EXPERIMENTAL". Cmd+F5 to disable.

- [ ] **Step 13.5: Reduce-Motion verification**

System Settings → Accessibility → Display → Reduce Motion ON. Open the AI Models gallery. Expanding a provider card no longer animates with spring; the download progress chip falls back to a static fill (the `.linear(duration: 0.18)` is brief enough that Reduce-Motion doesn't visibly affect it, but the SwiftUI `Material` graceful-degradation kicks in for the glass body). Toggle off.

- [ ] **Step 13.6: Report status to lead — DO NOT commit**

Per CLAUDE.md, no commits during execution. Report:

```
W6 AI Models + Prompts re-skin: BUILD GREEN, TESTS GREEN
- MLX registry: dropped gemma-3-1b + Qwen3.6-27B; added gemma-4-e2b; relabeled gemma-4-26b-a4b experimental
- MLXModelEntry: speedRating, qualityRating, expectedLatencySeconds, isExperimental fields added
- MLXProvider: WARN log on totalElapsed > 10s
- MLXModelPickerView: full row re-skin (glass panel, ratings chips, latency chip, EXPERIMENTAL chip, download progress chip)
- ProviderCard: corner radius 16→14, hover-lift removed, ACTIVE badge SF Mono, status pill via StatusPill, single-accent stroke
- APIKeyManagementView: gallery split into Configured + Available sections
- PromptEditorView + EnhancementSettingsPanel: header xmark + footer Save chrome rebuilt to glass vocabulary
- EnhancementSettingsView: + and gear buttons re-skinned to glass
- Legacy MLXModels dir purged on first launch via @AppStorage sentinel
- Diff: <git diff --stat | tail -1>
```

Lead reviews diff, decides whether to commit. Reviewer (`superpowers:code-reviewer`) gets the diff next; the reviewer pattern enforces fact-checking the rating numbers against the cited research and verifying the Reduce-Motion + VoiceOver paths above.

---

## Self-review

- [x] **Spec coverage.**
  - §1 Material/Tokens: every new chrome surface uses `Palette.accent` + `Palette.hairline` + `.ultraThinMaterial` + 10pt chips / 14pt panels. ✓
  - §5 row W6 — `MLXModelPickerView`, `ProviderCard`, `PromptEditorView`, `EnhancementSettingsPanel` chip-picker section all re-themed. ✓
  - §5 row W6 — provider chips, status pills, prompt chips re-themed. ✓
  - §5 row W6 — download progress UI inherits cluster vocabulary (Palette.accent fill + clusterFade-style 0.18s linear). ✓
  - §5#8 — GlassCard hover-lift removed from ProviderCard. ✓

- [x] **User MLX follow-up coverage (handoff items 1-7).**
  - Item 1 (gemma-4-26b-a4b 30s stall): WARN log instrumentation + EXPERIMENTAL relabel + caution copy. Hardware verification deferred to coder runtime check (Task 13.3). ✓
  - Item 2 (MLX perf research): cited research + ratings encoded as struct fields. ✓
  - Item 3 (drop gemma-3-1b-it-qat-4bit): Task 2 removes from curated. ✓
  - Item 4 (latency filter): Task 2 drops Qwen3.6-27B; relabels gemma-4-26b-a4b. ✓
  - Item 5 (speed/quality ratings UI): Task 5 adds Speed/Quality/Latency chip family. ✓
  - Item 6 (segregation by config state): Task 7 partitions gallery on `connectedProviders`. ✓
  - Item 7 (legacy MLX dir cleanup): Task 3 + Task 11 — one-time migration on app init, sentinel-guarded. ✓

- [x] **Placeholder scan.** No `TBD`, no "implement later", no "similar to Task N", no "add error handling". Every step has exact code, exact file:line, or exact command. The single observation-only concern (PLE-quant garbage-output discussion) is documented in Risks/unknowns #1, not as a deferred plan decision.

- [x] **Type consistency.**
  - `speedRating` / `qualityRating` are Int across the struct, the curated array, and the picker chip render.
  - `expectedLatencySeconds: ClosedRange<Double>` consistent everywhere.
  - `isExperimental: Bool` reads correctly in the picker.
  - `Palette.accent` / `Palette.hairline` / `Palette.hairlineSoft` are the correct symbol names per `Palette.swift`.
  - `StatusPill(text:tone:)` signature matches the existing definition in `APIKeyManagementView.swift:144-182`.
  - `ProviderChipStyle.displayName(for:)` is the correct API per `ProviderChipStyle.swift:59`.

- [x] **Build cadence.** No `make local` between tasks; one full build at Task 13.1 per CLAUDE.md.

- [x] **No commits.** Final step reports to lead.

- [x] **No PR-reference comments in code samples.** All inline doc-comments cite the spec section + this plan path; none reference PR numbers.

- [x] **Pre-existing spec-ref comments preserved.** Palette.swift §1 ref, GlassChip.swift §1 ref, etc. are not modified.

---

## Acceptance criteria

- ✅ `make local` completes with `** BUILD SUCCEEDED **`.
- ✅ `xcodebuild test` passes — all existing tests green.
- ✅ `MLXModelRegistry.curated` contains exactly 4 entries: gemma-4-e2b, gemma-4-e4b, Qwen3.5-4B, gemma-4-26b-a4b (experimental). gemma-3-1b and Qwen3.6-27B are gone.
- ✅ `MLXModelEntry` exposes `speedRating: Int`, `qualityRating: Int`, `expectedLatencySeconds: ClosedRange<Double>`, `isExperimental: Bool`.
- ✅ `MLXModelPickerView` rows show ACTIVE / EXPERIMENTAL / Speed / Quality / Latency chips in SF Mono 0.06em tracking; download progress shows a chip-style bar with `Palette.accent` fill.
- ✅ `ProviderCard` corner radius is 14pt; hover lift removed; ACTIVE badge SF Mono; status renders via shared `StatusPill`; tile fills with `Palette.accent`.
- ✅ `APIKeyManagementView` shows two sections labeled CONFIGURED / AVAILABLE with the correct partitions; selected provider sorts first in CONFIGURED.
- ✅ `PromptEditorView` and `EnhancementSettingsPanel` close-button chrome uses 8pt rounded glass with hairline stroke; PromptEditorView Save Changes button is `Palette.accent` tinted.
- ✅ `EnhancementSettingsView` `+` and gear buttons render with the glass-chip vocabulary.
- ✅ `MLXProvider.enhance(...)` emits a WARN log line on `totalElapsed > 10.0`.
- ✅ On first launch after upgrade, `~/Library/Application Support/com.prakashjoshipax.VoiceInk/MLXModels/` is removed if present; `@AppStorage("legacyMLXDirPurged")` is set; subsequent launches skip the purge.
- ✅ Sweep `grep -rn "gemma-3-1b-it-qat-4bit\|Qwen3.6-27B" VoiceInk --include="*.swift"` returns 0 matches.
- ✅ Sweep `grep -rn "offset(y: hovering" VoiceInk/Views/AI\\ Models/ProviderCard.swift` returns 0 matches.
- ✅ Sweep for emoji literals across the W6 file set (Task 12.7) returns 0 matches.

---

## Risks / unknowns

1. **PLE-quant garbage-output concern.** The discussion at [mlx-community/gemma-4-e2b-4bit#1](https://huggingface.co/mlx-community/gemma-4-e2b-4bit/discussions/1) reports that mlx-community 4-bit quants of Gemma 4 E-series produce degraded ("garbage") output because the quantization is applied to PLE (Per-Layer Embedding) layers that should stay full-precision. This affects:
   - the new `mlx-community/gemma-4-e2b-it-4bit` (W6 fastest tier),
   - the existing `mlx-community/gemma-4-e4b-it-4bit` (current production default — has been shipping for weeks via prior commits),
   - unsloth UD quants (same issue per the discussion thread).

   **Net assessment:** the user has been running e4b in production with no quality-regression report; the cleanup task is forgiving (50-200 token output, instruction-following over creative generation) so the worst-case PLE artifact likely manifests on long-form / creative outputs we don't ask for. The W6 swap (e4b stays + e2b joins) does not make this worse than it already is.

   **Candidate fixes if a regression surfaces post-W6:**
   - (a) Drop the fastest tier entirely; ship the 3-entry registry (e4b + qwen-3.5-4b + 26b-a4b experimental).
   - (b) Test `mlx-community/gemma-4-e2b-it-OptiQ-4bit` (custom quant that handles PLE correctly) and add as the curated fastest tier.
   - (c) Escalate to 8-bit variants when bundle-size budget allows.

   Out of scope for W6: do NOT rip out the e4b default, do NOT switch to unsloth UD quants (same defect), do NOT add OptiQ as a curated entry yet — flag only.

2. **Real-world tok/s on M-series base 32 GB.** All cited numbers are from M4 Pro 24 GB (kartit.net) or M3 Ultra 192 GB (gemma4-ai.com) — neither matches the user's exact target hardware (M2/M3/M4 base 32 GB). The ratings are the planner's best extrapolation; the new WARN log hook (Task 4) provides ground-truth feedback once the user dictates with each model. **If reviewer-w6 has access to the user's machine for a sanity dictation pass, the ratings may need refinement before merge.** Otherwise the ratings ship as conservative defaults and tighten in a follow-up packet.

3. **`gemma-4-26b-a4b-it-4bit` experimental UX.** The plan keeps it relabeled rather than dropped on the user's "drop or relabel" instruction. If the user specifically wanted hard-drop (interpretation differs), drop the entry from Task 2 and the EXPERIMENTAL chip render from Task 5 becomes dead code (harmless — the `if model.isExperimental` block just never matches any registry entry).

4. **`StatusPill` cross-file reference.** `ProviderCard.swift` adopts `StatusPill` defined in `APIKeyManagementView.swift`. Both files are in the same Swift module (target `VoiceInk`), so no import is needed — but if the codebase ever splits these into separate modules, ProviderCard would need an `import APIKeyManagement`. Current single-target setup makes this risk-free.

5. **Per-delete cleanup hook deferred.** The plan implements ONE cleanup path (one-time migration on init) per migration policy point 10. If the user later wants per-delete cleanup ("when MLXModelPickerView.delete runs, also wipe stale state"), it's a small follow-up — but per current understanding the one-time migration plus swift-huggingface 0.9.0 landing in the new path means the legacy dir won't reappear, so per-delete cleanup is YAGNI. Risk: if a user reinstalls an old VoiceInk version that still writes to the legacy path, the sentinel won't re-trigger; they'd need to delete `~/Library/Preferences/com.prakashjoshipax.VoiceInk.plist`'s `legacyMLXDirPurged` key. Acceptable corner case.

6. **`VoiceInk.swift` vs `VoiceInkApp.swift` filename ambiguity.** Task 0.5 grep step locates the actual file. If the App struct lives in a third filename, Task 11 inserts the same code into that file regardless. No risk to plan integrity.

## Estimated effort

~4-5 hours for an engineer familiar with the codebase. ~6-7 hours for a fresh teammate. Most of the work is the picker re-skin (Task 5) and the segregation rebuild (Task 7); the registry edits (Task 2) and the legacy purge (Task 3 + 11) are small. New file count: 0; cross-file rewiring is light because the segregation reuses `connectedProviders` rather than introducing a new partition source.
