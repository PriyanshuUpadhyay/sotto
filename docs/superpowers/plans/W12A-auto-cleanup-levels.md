# W12.A — Auto Cleanup Levels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.
>
> **Phase 2 packet — first.** W12.A directly addresses the user's "enhance is bad" complaint by replacing the binary on/off enhance toggle with a 4-level dial (None / Light / Medium / High) + diff-of-changes visibility + Undo AI edit. Pairs with W11's perf wins (already merged) so the four levels feel responsive.

**Date:** 2026-04-30
**Scope:** Replace `isAIEnhancementEnabled: Bool` on `PowerModeConfig` and on `AIEnhancementService` with a 4-state `EnhanceLevel` enum. Wire the level through the system-prompt builder so each non-`.none` level injects a per-level cleanup directive. Surface a level picker on (a) global Enhancement Settings, (b) recorder-side Enhancement Settings panel, (c) per-PowerMode config card. Wire the existing `WordDiffEngine` into `TranscriptionDetailView` as a toggleable inline diff between raw and enhanced. Add an "Undo AI edit" button that nulls `enhancedText` (raw is already persisted on `Transcription.text`).

**Sources of truth:**
- R3 audit (the WHY for the dial + diff + Undo): `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` §1 P0-3, §2.B, §3 "Good ideas worth stealing wholesale".
- Master plan §0 (Q6=a — 4 levels) + §3 W12.A scope: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`.
- W11A shape reference: `docs/superpowers/plans/W11A-pipeline-fixes.md`.
- W11.B routing reality (AFM primary on macOS 26+, MLX fallback): the level picker maps to a system-prompt strategy regardless of provider; same level → same directive on AFM, MLX, Ollama, remote APIs.
- Aesthetic spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` (W5 SettingsCard idiom, `Palette.accent` glow, `GlassCard` chrome).

**Goal:** users get a dial they can crank (None / Light / Medium / High) instead of a checkbox; they can see exactly what the model changed (inline diff) and undo it (Undo AI edit) with one click. No model swap — same MLX / AFM / cloud paths serve all four levels via a per-level prompt directive.

---

## Prelude — packet shape + commit etiquette

W12.A is **one logical packet** but its diff straddles model + service + multiple UI surfaces + the plan doc itself. Per CLAUDE.md `feedback_skip_per_packet_builds.md` the lead does ONE integration `make local` at merge time and ONE squashed `feat:` commit.

- `docs(plans): W12A — auto cleanup levels plan` — this file. Lands FIRST, before any code, after lead sign-off.
- `feat(enhance): W12A — cleanup levels + diff view + undo AI edit` — code edits across model + service + 3 UI surfaces. **Single squashed commit** at merge time.

Coder leaves edits uncommitted; lead handles both commits. No per-task build is run during the packet; the integration `make local` runs once at the end (Task 11).

---

## Pre-merge ground-truth gate (USER-SIDE — light)

Unlike W11.A's perf-baseline gate, W12.A is a UX-shape change — there is no quantitative regression baseline to capture. There is, however, a **qualitative reference set** the user should grab so post-merge level semantics can be validated against the user's intuitions.

### Gate condition (light)

Before the coder touches code, the user runs **3 sample dictations** on the current `main` build with enhancement enabled (binary on/off, today). For each:

1. A short casual dictation with fillers ("um, so basically the thing I was trying to say is, you know, that we should ship this on Friday").
2. A medium dictation with grammar issues ("I went to store and buyed three apple, also I forgot the milk and so we will need to go again tomorrow").
3. A long-form thought-stream where style polishing would be valuable (~150-300 words on a topic of choice — e.g. project plan recap).

Capture `(rawTranscript, enhancedTranscript)` pairs into:

`docs/superpowers/research/2026-04-30-w12a-cleanup-reference.md`

The user picks a level mental model: which of these belong at Light, which at Medium, which at High. The post-merge verification (Task 11.3) re-runs each dictation at each level and confirms the dial maps to the user's intent. **This is qualitative — there is no pass/fail threshold.** If the user later disagrees with the level boundaries, the directives in `AIPrompts.cleanupDirective(for:)` (Task 3) are tuned in a follow-up packet.

**Coder does NOT create that file — the user does.** The plan tracks it as a soft pre-merge nice-to-have, not a blocker. The coder may proceed without it; the lead may also choose to drop the gate entirely if the user prefers shipping then tuning.

---

## Architecture (W12.A change list — T1 through T9)

```
Task   Where                                                          Risk
─────  ─────────────────────────────────────────────────────────────  ─────
T1     Define EnhanceLevel enum + per-level directives                 LOW
       VoiceInk/Models/EnhanceLevel.swift (NEW)

T2     Migrate PowerModeConfig.isAIEnhancementEnabled → enhanceLevel   MED
       VoiceInk/PowerMode/PowerModeConfig.swift                        — Codable backward-compat is the
                                                                          load-bearing wall.

T3     Inject per-level directive into system prompt                   LOW
       VoiceInk/Models/AIPrompts.swift                                 — pure additive helper.
       VoiceInk/Services/AIEnhancement/AIEnhancementService.swift

T4     Migrate AIEnhancementService.isEnhancementEnabled → enhanceLevel MED
       VoiceInk/Services/AIEnhancement/AIEnhancementService.swift      — derived Bool keeps ~30 call
       VoiceInk/PowerMode/PowerModeSessionManager.swift                  sites compiling unchanged.

T5     Extend WordDiffEngine with token-level DiffOp output            LOW
       VoiceInk/Services/WordDiffEngine.swift                          — additive function.

T6     Wire diff toggle + Undo AI edit into TranscriptionDetailView    MED
       VoiceInk/Views/History/TranscriptionDetailView.swift            — UI work; SwiftUI AttributedString.

T7     Replace AI Enhancement toggle in EnhancementSettingsView with   LOW
       4-segment level picker
       VoiceInk/Views/EnhancementSettingsView.swift

T8     Add level picker to EnhancementSettingsPanel (recorder-side)    LOW
       VoiceInk/Views/Components/EnhancementSettingsPanel.swift

T9     Replace AI Enhancement toggle in PowerModeConfigView with       LOW
       level picker (inside the existing SettingsCard)
       VoiceInk/PowerMode/PowerModeConfigView.swift
```

**Combined target:** users see a level dial everywhere they used to see a toggle. Each non-`.none` level injects a different system-prompt directive. The diff view + Undo button surface the model's edits in History. No new SPM deps, no model swap, no deployment-target bump (already at 26.0 from W11.B).

---

## Tech Stack

Swift 5.x, SwiftUI, AppKit. **No SPM additions.** macOS 26.0 deployment target (post-W11.B).

T6's diff rendering uses `AttributedString` for the inline-diff variant (since macOS 12 — comfortably under our 26.0 floor). No third-party diff library. The existing `WordDiffEngine.lcsIndexPairs(...)` is reused; we add a sibling function that emits `[DiffOp]` instead of substitution pairs.

Build via `make local` (~3 min cold). One integration build at Task 11, per CLAUDE.md cadence.

---

## Spec refs

- Research: `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` §1 (P0 list — "Auto Cleanup levels + diff view + Undo AI edit"), §2.B (the AI-enhance feature table — Level dial vs binary toggle, Diff view, Undo edit), §3 ("Auto Cleanup as a 4-position dial, not a toggle"), §6 (implementation pointers — "parameterize `AIEnhancementService.swift` enhance prompt with `aggressiveness: .none/.light/.medium/.high`").
- Master plan: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` §0 Q6=a (locked: 4 levels) + §3 W12.A scope (2-3 paragraph sketch).
- Aesthetic spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §3.5 (History detail surface), §3.7 (Settings card vocabulary), §4 (color tokens — `Palette.accent` for primary highlights, `Palette.success`/`Palette.warn` for diff insertions/deletions).
- W11A precedent for plan shape + commit etiquette.

---

## CLAUDE.md cadence rules respected

- **Single integration build at merge time.** No `make local` per task; one full build at Task 11. Per `feedback_skip_per_packet_builds.md`.
- **One squashed commit at merge time.** No per-task commits during execution.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** Existing `🦾` log markers in `MLXProvider.swift` / `AIEnhancementService.swift` are W6 instrumentation and stay; new logs may add `🦾 enhance: level=…` to the existing surface.
- **No new test files.** Per master plan §0 Q10=defer, validation is build-only.
- **No SPM additions, no deployment-target bump.**
- **No pbxproj edits.** Files added under `VoiceInk/` and `VoiceInkTests/` auto-included by Xcode 16 PBXFileSystemSynchronizedRootGroup.

---

## File structure

### New files

- `VoiceInk/Models/EnhanceLevel.swift` (~70 LOC) — defines the enum, per-level `displayName` / `description` / `directive`, `Codable` conformance, `defaultLevel` static, migration helpers (`from(legacyBool:)`).

### Modified files

- `VoiceInk/PowerMode/PowerModeConfig.swift` — T2 migration. Replace stored `isAIEnhancementEnabled: Bool` with `enhanceLevel: EnhanceLevel`. Keep a derived computed `var isAIEnhancementEnabled: Bool { enhanceLevel != .none }` for back-compat with all in-tree call sites that read the bool. Codable: decode new `enhanceLevel` key first; fall back to old `isAIEnhancementEnabled` Bool key (`true → .medium`, `false → .none`). Encode: ALWAYS write `enhanceLevel`, ALSO write `isAIEnhancementEnabled` derived bool for forward-compat with downgrade. ~+35 LOC, -5 LOC.

- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` — T4 migration. Replace stored `@Published isEnhancementEnabled: Bool` with `@Published enhanceLevel: EnhanceLevel`. Derive `var isEnhancementEnabled: Bool { get { enhanceLevel != .none } set { enhanceLevel = newValue ? .medium : .none } }` — non-`@Published`, but `objectWillChange` already fires when `enhanceLevel` changes, so all observers update correctly. T3 prompt injection: `getSystemMessage(for:)` prepends `AIPrompts.cleanupDirective(for: enhanceLevel)` to the existing prompt body. Persistence migration: read `enhanceLevel` raw key on init; if absent, fall back to old `isAIEnhancementEnabled` Bool with the `.medium`/`.none` mapping. ~+35 LOC, -5 LOC.

- `VoiceInk/PowerMode/PowerModeSessionManager.swift` — T4 migration. `ApplicationState.isEnhancementEnabled: Bool` → `enhanceLevel: EnhanceLevel`. Codable: same fallback shape (decode new key, else legacy bool → enum mapping). `applyConfiguration(...)`/`restoreState(...)` write `enhancementService.enhanceLevel = …` instead of the bool. ~+12 LOC, -4 LOC.

- `VoiceInk/Models/AIPrompts.swift` — T3 prompt directive. Add `static func cleanupDirective(for: EnhanceLevel) -> String` returning a short prefix block (3-5 lines) that pins the model on the level's allowed transformations. `.none` returns `""` (caller doesn't invoke when level is `.none` — gated upstream — but defensive). The existing `customPromptTemplate` body stays UNCHANGED; the directive is concatenated onto the front. ~+30 LOC.

- `VoiceInk/Services/WordDiffEngine.swift` — T5 token-level diff. Add `static func tokenLevelDiff(original:edited:) -> [DiffOp]`. New nested enum `DiffOp { case equal(String); case insert(String); case delete(String) }`. Existing `findSingleWordSubstitutions(...)` UNCHANGED — still used by `WordReplacement` autolearn. ~+50 LOC.

- `VoiceInk/Views/History/TranscriptionDetailView.swift` — T6 wire-up. New `@State private var diffMode: DiffMode = .panes` (cases `.panes`, `.inline`). Toolbar/header gains a small segmented picker (Panes / Diff). When `.inline`, `textPanes` is replaced by a single `inlineDiffPane(raw:enhanced:)` rendering an `AttributedString` with insertions tinted `Palette.success` underlined and deletions tinted `Palette.warn` strikethrough. Add "Undo AI edit" button to `actionsRow` (only visible when `transcription.enhancedText != nil`); on tap, sets `transcription.enhancedText = nil`, saves modelContext, shows `"AI edit reverted"` status. ~+95 LOC, -2 LOC.

- `VoiceInk/Views/EnhancementSettingsView.swift` — T7. Replace the existing `Toggle` at line 55-64 with a 4-segment `Picker` bound to `$enhancementService.enhanceLevel`. Use `.pickerStyle(.segmented)` for the 4 cells. Below the picker, surface a one-line description of the active level (`enhanceLevel.description`) so the user understands what each cell does without an InfoTip popover. The existing "Enable Enhancement" header stays — the section icon (`wand.and.stars`) still represents the feature; only the control changes. ~+25 LOC, -10 LOC.

- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` — T8. Add a new `Section` (header "Cleanup Level") with the 4-segment picker bound to `$enhancementService.enhanceLevel` + the level description text below. Inserted as the first Section above "Context" (so it's the first thing the user sees when they open the panel from the recorder). Match the existing Form-Section idiom (this panel is W13.D's purge target, but W13.D hasn't run yet — DO NOT pre-purge to W5 SettingsCard here; that's W13.D's territory). ~+30 LOC.

- `VoiceInk/PowerMode/PowerModeConfigView.swift` — T9. The `aiEnhancementCard` SettingsCard at line 513-545 currently uses `Toggle("AI Enhancement", isOn: $isAIEnhancementEnabled)`. Replace with `Picker("Cleanup Level", selection: $enhanceLevel) { … }.pickerStyle(.segmented)` bound to a new `@State private var enhanceLevel: EnhanceLevel`. Existing `selectedAIProvider` / `selectedAIModel` / `selectedPromptId` reset-to-default logic on toggle stays — fires when level transitions FROM `.none` TO any other case. Builder/save paths use the new state. ~+25 LOC, -8 LOC.

- `VoiceInk/AppDefaults.swift` — register `"enhanceLevel": "medium"` so first-run lands at Medium (matches the migrated default). ~+1 LOC.

### Untouched (explicit list — coder do NOT drift)

- `VoiceInk/Services/WordDiffEngine.swift` `findSingleWordSubstitutions(...)` and its callers (`WordReplacement` autolearn). T5 ADDS a sibling function; it does not modify the existing one.
- `VoiceInk/Models/AIPrompts.swift` `customPromptTemplate`, `assistantMode`, `shortTranscriptCleanupTemplate`. T3 ADDS `cleanupDirective(for:)`; it does not modify the existing 3 templates.
- `VoiceInk/Services/AIEnhancement/MLXProvider.swift`, `AFMProvider.swift`, `AIService.swift` provider implementations — UNTOUCHED. The level affects the system prompt only; providers remain agnostic.
- `VoiceInk/Models/Transcription.swift` schema — UNTOUCHED. `Transcription.text` already holds the raw transcript; `Transcription.enhancedText` already holds the enhanced one. **The "raw alongside enhanced" persistence requirement from the master plan §3 W12.A bullet point is already satisfied by the existing schema.** No SwiftData migration. (Confirmed by grep + read at `VoiceInk/Models/Transcription.swift:13-14`.)
- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` enhance-gate at line 123-126 — UNTOUCHED. The gate reads `enhancementService.isEnhancementEnabled`, which becomes the derived `enhanceLevel != .none`. T4 makes the bool a computed view; the gate's behavior is identical (`.none` → skip enhance, anything else → run enhance with the level's directive injected upstream).
- `VoiceInk/PromptDetectionService.swift`, `MiniRecorderShortcutManager.swift`, `MenuBarView.swift`, `EnhancementPromptPopover.swift`, `RecorderComponents.swift`, `AudioPlayerView.swift`, `AudioTranscribeView.swift`, `AudioFileTranscriptionManager.swift`, `AudioFileTranscriptionService.swift`, `SystemInfoService.swift` call sites that read or write `isEnhancementEnabled` — UNTOUCHED behaviorally. They keep operating on the derived bool. The setter (`isEnhancementEnabled = true`) maps to `.medium`; setter (`= false`) maps to `.none`. Toggling from these surfaces becomes "toggle between None and Medium" which is the natural binary collapse of the 4-level dial.
- All test files (`VoiceInkTests/*.swift`) — W12.A ships no new tests. Per master plan §0 Q10.
- `VoiceInk/Services/ImportExportService.swift` — UNTOUCHED. The import/export flow uses `[PowerModeConfig].self` Codable directly; T2's backward-compat decoder/encoder owns the migration end-to-end. Re-importing an old export with `isAIEnhancementEnabled` only round-trips correctly into `enhanceLevel`. Re-importing a new export into an old build still finds `isAIEnhancementEnabled` (we keep encoding it forward-compat) and behaves correctly.

---

## Migration policy (resolves ambiguity for each design point)

The lead pinned the following architecture decisions for this packet. Restated as the authoritative ruleset for the coder.

1. **Default level on migration: `.medium`.** Existing users with `isAIEnhancementEnabled = true` migrate to `.medium`; `isAIEnhancementEnabled = false` migrates to `.none`. Per master plan §3 W12.A. New installs also default to `.medium` (registered in `AppDefaults.swift`). Rationale: Medium ≈ today's behavior, gives the user a natural "dial down to Light" or "dial up to High" affordance.

2. **The bool is a derived view, not a parallel field.** On `AIEnhancementService` and on `PowerModeConfig`, the source of truth is `enhanceLevel`; `isEnhancementEnabled: Bool` is a non-stored computed accessor (`{ get { enhanceLevel != .none } set { enhanceLevel = newValue ? .medium : .none } }`). All ~30 in-tree call sites that read/write the bool stay unchanged — they implicitly drive the level via `.medium`/`.none`. Reasoning: a clean grep+replace would touch 30+ call sites across recorder UI, menubar, file-transcribe view, audio-player view, prompt-detection service — out of scope for this packet's risk budget. The derived-view approach is reversible (a follow-up packet can grep+replace if reviewer prefers explicit level reads everywhere).

3. **Codable backward-compat is non-negotiable.** Both `PowerModeConfig` and `ApplicationState` (in `PowerModeSessionManager`) have on-disk Codable shapes with `isAIEnhancementEnabled: Bool` baked in. The decoder MUST tolerate both the new `enhanceLevel` key AND the legacy `isAIEnhancementEnabled` key (legacy bool → enum mapping). The encoder MUST write BOTH keys — new builds write the enum (canonical) AND keep writing the legacy bool (so a user who downgrades to a pre-W12.A build doesn't lose their on/off state). Once W12.A has been shipping for ≥3 months we can drop the bool encode in a follow-up.

4. **Level directive → injected at the FRONT of the existing system prompt body, not via `%@` substitution.** The existing `customPromptTemplate` uses a single `%@` for the user's custom prompt body. Adding a second `%@` is fragile (positional formatting hits ordering bugs). Instead: `getSystemMessage(for:)` returns `AIPrompts.cleanupDirective(for: level) + existingBody`. The directive is a 3-5 line block bounded by `<CLEANUP_LEVEL>` tags so the model can clearly distinguish it from the rest of the template. Concatenation is order-stable and trivially testable.

5. **Level directives — proposed initial wording (Task 3 below specifies; flagged for lead refinement after the user-side reference set is captured).** Approximate length: 60-90 tokens each. The exact wording lives in `AIPrompts.swift`; this is the design intent:
   - `.none` — `""` (defensive; never reached because the gate at TranscriptionPipeline:124 short-circuits on `.none`).
   - `.light` — "Apply Light cleanup ONLY: remove disfluencies (um, uh, like, you know, false starts, repeated words). Apply standard punctuation. Preserve the speaker's exact wording, grammar, and tone — do NOT rephrase, do NOT correct grammar, do NOT change vocabulary."
   - `.medium` — "Apply Medium cleanup: remove disfluencies, fix obvious grammar errors (subject-verb agreement, tense consistency), apply standard punctuation, normalize sentence boundaries. Preserve the speaker's vocabulary and tone — do NOT polish style, do NOT reword for concision."
   - `.high` — "Apply High cleanup: remove disfluencies, fix grammar, normalize sentence flow, and tighten prose for clarity and readability. May reword for concision and merge run-on thoughts. Preserve all factual content, names, numbers, and the speaker's intent — do NOT add information, do NOT inject opinions."

   These directives are the design intent; the user-side reference set (Pre-merge gate above) gives the lead a way to refine the wording before W12.A merges. **The coder ships Task 3 with these exact strings; the lead may patch them in-flight before commit, or punt to a follow-up.**

6. **Fast-path (W11.A2 short-transcript template) is level-agnostic for v1.** When `MLXShortTranscriptCharThreshold` (120 chars / ~30 tokens) AND no clipboard/screen context active → fast-path fires regardless of level. The fast-path template is already the lightest possible cleanup ("fix grammar, remove fillers"), which approximately matches `.light` semantics. For `.high` on a short input, the user pays the full prompt prefill (fast-path skipped) — but that scenario is rare (most short dictations are at `.light` or `.medium`). Coder may add a level-aware fast-path skip in a follow-up; out of scope for v1.

   **Concrete rule:** in `AIEnhancementService.makeRequest`, the existing `shouldUseMLXFastPath(text:)` predicate is unchanged. The fast-path template (`shortTranscriptCleanupTemplate`) does NOT get a directive prefix — it's a separate, self-contained prompt. When fast-path fires, the level is implicitly forced to the fast-path's behavior (~`.light`). The standard path injects the directive based on the user's level. Both paths log the chosen level/template for observability.

7. **Diff view shape — inline highlighted single-pane (default for `.inline` mode), with Panes mode preserved as fallback.** TranscriptionDetailView gains a 2-segment picker `[Panes | Diff]`:
   - `Panes` (default; current behavior) — Original on top, Enhanced below, both as their own scroll panes.
   - `Diff` — single scroll pane showing the enhanced text inline with insertions tinted `Palette.success` (green underline) and deletions tinted `Palette.warn` (orange strikethrough). The diff is computed via `WordDiffEngine.tokenLevelDiff(original: raw, edited: enhanced)`.

   The picker default is `.panes` — both panes visible — matching today's behavior. Users opt into `.diff`. Persistence: a per-detail `@State` only (not user-scoped); each time the user opens a detail view, it starts in `.panes`. Out-of-scope follow-up: a `@AppStorage` to remember the user's preferred default.

8. **Undo AI edit — destructive but recoverable.** "Undo AI edit" sets `transcription.enhancedText = nil` and clears `aiEnhancementModelName`, `promptName`, `enhancementDuration`, `aiRequestSystemMessage`, `aiRequestUserMessage` (the related metadata is invalidated alongside; otherwise the History list shows a stale provider chip). The raw `transcription.text` field is the source of truth and is preserved. **Recovery:** the user can hit "Re-enhance" (existing button) to regenerate enhancedText from the raw with the current active prompt + level. There is NO third "undone" state stored — Undo erases the model's edits cleanly. If the user wants the OLD enhanced text back, they re-run enhance.

   **Confirmation prompt:** none. The action is reversible by Re-enhance. Per CLAUDE.md `feedback_no_confirmation_trivial.md` — no "Are you sure?" dialog. The button is labeled "Undo AI edit" with `Image(systemName: "arrow.uturn.backward")` and lives next to "Re-enhance" in the actions row. Visually muted (Palette.neutral) to indicate destructive intent; not styled as primary.

9. **Per-PowerMode picker shape — segmented inside the existing SettingsCard.** PowerModeConfigView's `aiEnhancementCard` uses a `Picker(...).pickerStyle(.segmented)` with 4 cells (None / Light / Medium / High). Below the picker, a one-line `enhanceLevel.description` text. The existing nested controls (`aiProviderPicker`, `aiModelPicker`, `enhancementPromptPicker`, "Context Awareness" Toggle) stay; their visibility gate flips from `if isAIEnhancementEnabled` to `if enhanceLevel != .none`.

10. **Global vs PowerMode level — PowerMode wins when an override is active.** Today, `PowerModeSessionManager.applyConfiguration(...)` writes `enhancementService.isEnhancementEnabled = config.isAIEnhancementEnabled`. Post-W12.A, it writes `enhancementService.enhanceLevel = config.enhanceLevel`. Same precedence — per-PowerMode override REPLACES global state for the duration of the session; `endSession()` restores the global state. This is unchanged behaviorally.

11. **No new AppStorage namespace.** All keys stay flat (`enhanceLevel` for the global service-level default; `enhanceLevel` field inside `PowerModeConfig` Codable). Future cleanup could namespace under `enhancement.level.*`. Out of scope.

12. **No new spec-ref `/* … */` paragraphs in code.** Per CLAUDE.md preference for sentence fragments. New comments use one- or two-line `///` doc-comments above declarations, citing this plan path (`docs/superpowers/plans/W12A-auto-cleanup-levels.md`) only where the WHY is non-obvious (the bool-as-derived-view rationale, the fast-path level-agnosticism, the diff-mode default, the Codable backward-compat shape). The 4 existing `🦾` log markers stay verbatim; new ones may add `🦾 enhance: level=…` to existing `notice` calls.

13. **No emoji in new code.** Existing `🦾` markers stay (W6 instrumentation; documented exception). No new emoji in any added file.

14. **No deployment-target bump.** Already at 26.0 from W11.B. AttributedString diff rendering uses APIs available since macOS 12 — comfortably supported.

15. **Out of scope: Wispr "Custom" cleanup level.** Wispr's actual UI has 4+1 levels — None / Light / Medium / High / Custom. The Custom case sends the user's custom-prompt body. VoiceInk already has a richer custom-prompt library (`CustomPrompt`, `triggerWords`, `PredefinedPrompts`); the user can build any "Custom" cleanup behavior they want via the existing prompt editor. **The `EnhanceLevel` enum is exactly 4 cases; we do NOT add a `.custom` case in v1.** The level is orthogonal to the prompt body — picking `.medium` with a "Translate to Spanish" custom prompt active is a valid combination. Per master plan §0 Q6=a.

---

## Tasks

### Task 0 — Audit + read references

**Files:** none (read-only).

- [ ] **Step 0.1 — Confirm Transcription model already keeps raw**

```bash
grep -n "var text\|var enhancedText" VoiceInk/Models/Transcription.swift
```

Expected: `var text: String` (line 13) holds the raw transcript; `var enhancedText: String?` (line 14) holds the enhanced one. **The raw-alongside-enhanced persistence is already in place.** If the schema differs, stop and request a model migration plan from the lead — the rest of the plan assumes the schema is unchanged.

- [ ] **Step 0.2 — Confirm `isAIEnhancementEnabled` call-site count**

```bash
grep -rn "isAIEnhancementEnabled\|isEnhancementEnabled" VoiceInk --include="*.swift" | wc -l
```

Expected: ~35-45 matches across PowerMode, AIEnhancementService, TranscriptionPipeline, recorder UI, file-transcribe, audio-player, prompt-detection, menubar, system-info. The plan's Migration policy #2 keeps these compiling unchanged (derived bool view). If the count is wildly different (e.g. 100+), reconcile with the lead before proceeding — the bool-view approach stops scaling at some point.

- [ ] **Step 0.3 — Confirm `WordDiffEngine` API**

```bash
grep -n "static func\|enum\|private static" VoiceInk/Services/WordDiffEngine.swift
```

Expected: `static func findSingleWordSubstitutions(...) -> [(original: String, replacement: String)]`, plus private LCS helpers. T5 ADDS a sibling function returning `[DiffOp]` — does NOT modify existing API.

- [ ] **Step 0.4 — Confirm `EnhancementSettingsPanel` is still on Form (not yet W13.D-purged)**

```bash
grep -n "Form\|Section\|SettingsCard" VoiceInk/Views/Components/EnhancementSettingsPanel.swift | head -10
```

Expected: `Form { Section { } }` idiom. T8 inserts a new Section in the existing Form — DO NOT pre-purge to W5 SettingsCard. That's W13.D's territory and out of scope here.

- [ ] **Step 0.5 — Confirm `PowerModeConfigView.aiEnhancementCard` uses SettingsCard**

```bash
grep -n "aiEnhancementCard\|SettingsCard\|isAIEnhancementEnabled" VoiceInk/PowerMode/PowerModeConfigView.swift | head -20
```

Expected: a `private var aiEnhancementCard: some View` returning a `SettingsCard(...) { ... }` block (around line 513-545) with the existing Toggle. T9 swaps the Toggle for a segmented Picker INSIDE the card — preserves the card chrome.

- [ ] **Step 0.6 — Confirm pre-merge gate file existence is optional (per Pre-merge ground-truth gate above)**

```bash
ls -la docs/superpowers/research/2026-04-30-w12a-cleanup-reference.md 2>&1 || echo "absent — soft gate, may proceed"
```

Either outcome is acceptable. If absent, the lead may decide to skip the gate or capture later.

---

### Task 1 — Define `EnhanceLevel`

**Files:**
- Create: `VoiceInk/Models/EnhanceLevel.swift`

- [ ] **Step 1.1 — Write the enum**

```swift
import Foundation

/// 4-level enhancement intensity dial. Replaces the legacy
/// `isAIEnhancementEnabled: Bool` per W12.A (master plan §0 Q6=a).
/// `.none` bypasses enhance entirely; `.light`/`.medium`/`.high` inject a
/// per-level cleanup directive into the system prompt without changing the
/// model lineup. See plan
/// `docs/superpowers/plans/W12A-auto-cleanup-levels.md` §Migration policy #4.
enum EnhanceLevel: String, Codable, CaseIterable, Equatable, Hashable {
    case none
    case light
    case medium
    case high

    /// First-run + migrated default. Existing users with the old
    /// `isAIEnhancementEnabled = true` land here.
    static let `default`: EnhanceLevel = .medium

    /// Short label for picker cells.
    var displayName: String {
        switch self {
        case .none:   return "None"
        case .light:  return "Light"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }

    /// One-line description rendered below the picker. ~50-70 chars.
    var description: String {
        switch self {
        case .none:   return "Paste the raw transcript without AI cleanup."
        case .light:  return "Remove fillers and add punctuation. Keep wording exact."
        case .medium: return "Light cleanup plus grammar fixes. Default for most."
        case .high:   return "Aggressive cleanup with style polishing for clarity."
        }
    }

    /// Map the legacy bool to a level. Used by Codable migration paths.
    static func from(legacyBool: Bool) -> EnhanceLevel {
        legacyBool ? .medium : .none
    }
}
```

- [ ] **Step 1.2 — Confirm no orphan references**

```bash
grep -rn "EnhanceLevel" VoiceInk --include="*.swift"
```

Expected: only the new file (definition). Tasks 2-9 will add call sites.

**Risk:** LOW — pure additive type. No existing behavior touched.

**Verification:** type-check passes.

---

### Task 2 — Migrate `PowerModeConfig`

**Files:**
- Modify: `VoiceInk/PowerMode/PowerModeConfig.swift`

- [ ] **Step 2.1 — Add `enhanceLevel` field, replace stored `isAIEnhancementEnabled`**

```swift
struct PowerModeConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var appConfigs: [AppConfig]?
    var urlConfigs: [URLConfig]?

    /// W12.A: 4-level cleanup intensity. Replaces the legacy stored
    /// `isAIEnhancementEnabled: Bool`. See plan §Migration policy #1.
    var enhanceLevel: EnhanceLevel

    var selectedPrompt: String?
    // … existing fields unchanged …

    /// Derived view of `enhanceLevel` for back-compat with call sites that
    /// haven't migrated yet (Migration policy #2). DO NOT add new readers.
    var isAIEnhancementEnabled: Bool {
        get { enhanceLevel != .none }
        set { enhanceLevel = newValue ? .medium : .none }
    }
```

Update `CodingKeys`:

```swift
enum CodingKeys: String, CodingKey {
    case id, name, emoji, appConfigs, urlConfigs
    case enhanceLevel                    // W12.A canonical
    case isAIEnhancementEnabled          // W12.A legacy fallback
    case selectedPrompt, selectedLanguage, useScreenCapture, selectedAIProvider, selectedAIModel, isAutoSendEnabled, autoSendKey, isEnabled, isDefault, hotkeyShortcut
    case selectedWhisperModel
    case selectedTranscriptionModelName
}
```

- [ ] **Step 2.2 — Update designated initializer**

```swift
init(id: UUID = UUID(), name: String, emoji: String, appConfigs: [AppConfig]? = nil,
     urlConfigs: [URLConfig]? = nil, enhanceLevel: EnhanceLevel = .default,
     selectedPrompt: String? = nil,
     selectedTranscriptionModelName: String? = nil, selectedLanguage: String? = nil,
     useScreenCapture: Bool = false,
     selectedAIProvider: String? = nil, selectedAIModel: String? = nil,
     autoSendKey: AutoSendKey = .none, isEnabled: Bool = true, isDefault: Bool = false,
     hotkeyShortcut: String? = nil) {
    self.id = id
    self.name = name
    self.emoji = emoji
    self.appConfigs = appConfigs
    self.urlConfigs = urlConfigs
    self.enhanceLevel = enhanceLevel
    self.selectedPrompt = selectedPrompt
    self.useScreenCapture = useScreenCapture
    self.autoSendKey = autoSendKey
    self.selectedAIProvider = selectedAIProvider ?? UserDefaults.standard.string(forKey: "selectedAIProvider")
    self.selectedAIModel = selectedAIModel
    self.selectedTranscriptionModelName = selectedTranscriptionModelName ?? UserDefaults.standard.string(forKey: "CurrentTranscriptionModel")
    self.selectedLanguage = selectedLanguage ?? UserDefaults.standard.string(forKey: "SelectedLanguage") ?? "en"
    self.isEnabled = isEnabled
    self.isDefault = isDefault
    self.hotkeyShortcut = hotkeyShortcut
}
```

**Out-of-tree callers** that pass `isAIEnhancementEnabled: Bool` (positional or labeled) need updating. Grep:

```bash
grep -rn "PowerModeConfig(" VoiceInk --include="*.swift"
```

Each call site converts `isAIEnhancementEnabled: bool` → `enhanceLevel: EnhanceLevel.from(legacyBool: bool)` (or directly `.medium`/`.none`). `PowerModeConfigView.swift` line 704 + 719 are known sites; coder grep-walks the rest.

- [ ] **Step 2.3 — Codable decoder with fallback**

```swift
init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(UUID.self, forKey: .id)
    name = try container.decode(String.self, forKey: .name)
    emoji = try container.decode(String.self, forKey: .emoji)
    appConfigs = try container.decodeIfPresent([AppConfig].self, forKey: .appConfigs)
    urlConfigs = try container.decodeIfPresent([URLConfig].self, forKey: .urlConfigs)

    // W12.A: prefer canonical enum key; fall back to legacy bool.
    if let canonical = try container.decodeIfPresent(EnhanceLevel.self, forKey: .enhanceLevel) {
        enhanceLevel = canonical
    } else if let legacyBool = try container.decodeIfPresent(Bool.self, forKey: .isAIEnhancementEnabled) {
        enhanceLevel = .from(legacyBool: legacyBool)
    } else {
        enhanceLevel = .default
    }

    selectedPrompt = try container.decodeIfPresent(String.self, forKey: .selectedPrompt)
    selectedLanguage = try container.decodeIfPresent(String.self, forKey: .selectedLanguage)
    useScreenCapture = try container.decode(Bool.self, forKey: .useScreenCapture)
    selectedAIProvider = try container.decodeIfPresent(String.self, forKey: .selectedAIProvider)
    selectedAIModel = try container.decodeIfPresent(String.self, forKey: .selectedAIModel)
    // … existing autoSend / isEnabled / isDefault / hotkeyShortcut / model-name decode unchanged …
}
```

- [ ] **Step 2.4 — Codable encoder writes both keys (forward compat with downgrade)**

```swift
func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(id, forKey: .id)
    try container.encode(name, forKey: .name)
    try container.encode(emoji, forKey: .emoji)
    try container.encodeIfPresent(appConfigs, forKey: .appConfigs)
    try container.encodeIfPresent(urlConfigs, forKey: .urlConfigs)

    // W12.A: write canonical enum + derived bool. Lets a user who downgrades
    // to a pre-W12.A build still get on/off behavior. Drop the bool encode in
    // a follow-up packet ≥3 months post-W12.A merge.
    try container.encode(enhanceLevel, forKey: .enhanceLevel)
    try container.encode(enhanceLevel != .none, forKey: .isAIEnhancementEnabled)

    try container.encodeIfPresent(selectedPrompt, forKey: .selectedPrompt)
    // … existing fields unchanged …
}
```

- [ ] **Step 2.5 — Verify decoding a legacy export**

Confirm via grep that `ImportExportService` calls `JSONDecoder().decode([PowerModeConfig].self, from: data)`:

```bash
grep -n "PowerModeConfig" VoiceInk/Services/ImportExportService.swift
```

Expected: `[PowerModeConfig]` decode at the import path. Backward-compat is owned by Step 2.3's decoder; ImportExportService itself is unchanged.

**Risk:** MED — Codable migration is the load-bearing wall of T2. Decoder + encoder MUST agree across upgrade and downgrade paths.

**Verification:** type-check passes. Manual: encode a default `PowerModeConfig`, decode, encode again — idempotent. Encode → manually inspect JSON shows BOTH `enhanceLevel: "medium"` and `isAIEnhancementEnabled: true`.

---

### Task 3 — Inject per-level directive into system prompt

**Files:**
- Modify: `VoiceInk/Models/AIPrompts.swift`
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

- [ ] **Step 3.1 — Add `cleanupDirective(for:)` to `AIPrompts`**

In `VoiceInk/Models/AIPrompts.swift`, after the existing `customPromptTemplate` and `shortTranscriptCleanupTemplate`:

```swift
/// W12.A per-level cleanup directive prepended to the standard system
/// prompt body. Maps the user's `EnhanceLevel` selection onto an explicit
/// transformation budget the model is told to respect. See plan
/// `docs/superpowers/plans/W12A-auto-cleanup-levels.md` §Migration policy #5.
static func cleanupDirective(for level: EnhanceLevel) -> String {
    switch level {
    case .none:
        return ""  // defensive — caller short-circuits on .none upstream
    case .light:
        return """
        <CLEANUP_LEVEL>Light</CLEANUP_LEVEL>
        Apply Light cleanup ONLY: remove disfluencies (um, uh, like, you know, false starts, repeated words). Apply standard punctuation. Preserve the speaker's exact wording, grammar, and tone — do NOT rephrase, do NOT correct grammar, do NOT change vocabulary.

        """
    case .medium:
        return """
        <CLEANUP_LEVEL>Medium</CLEANUP_LEVEL>
        Apply Medium cleanup: remove disfluencies, fix obvious grammar errors (subject-verb agreement, tense consistency), apply standard punctuation, normalize sentence boundaries. Preserve the speaker's vocabulary and tone — do NOT polish style, do NOT reword for concision.

        """
    case .high:
        return """
        <CLEANUP_LEVEL>High</CLEANUP_LEVEL>
        Apply High cleanup: remove disfluencies, fix grammar, normalize sentence flow, and tighten prose for clarity and readability. May reword for concision and merge run-on thoughts. Preserve all factual content, names, numbers, and the speaker's intent — do NOT add information, do NOT inject opinions.

        """
    }
}
```

- [ ] **Step 3.2 — Inject directive in `getSystemMessage(for:)`**

In `AIEnhancementService.swift:148-205`, modify `getSystemMessage(for:)` to prepend the directive:

```swift
private func getSystemMessage(for mode: EnhancementPrompt) async -> String {
    // … existing context-section computation unchanged (selectedTextContext,
    //   clipboardContext, screenCaptureContext, customVocabularySection) …

    let levelDirective = AIPrompts.cleanupDirective(for: enhanceLevel)

    if let activePrompt = activePrompt {
        if activePrompt.id == PredefinedPrompts.assistantPromptId {
            return levelDirective + activePrompt.promptText + finalContextSection
        } else {
            return levelDirective + activePrompt.finalPromptText + finalContextSection
        }
    } else {
        let defaultPrompt = allPrompts.first(where: { $0.id == PredefinedPrompts.defaultPromptId }) ?? allPrompts.first!
        return levelDirective + defaultPrompt.finalPromptText + finalContextSection
    }
}
```

The directive is a no-op string for `.none` — defensive only; the gate at `TranscriptionPipeline:124` already prevents enhance from running at `.none`.

- [ ] **Step 3.3 — Log the active level**

In `makeRequest(text:mode:)` add a single notice line near line 217 (after `let systemMessage = await getSystemMessage(for: mode)`):

```swift
logger.notice("🦾 enhance: level=\(self.enhanceLevel.rawValue, privacy: .public)")
```

This appears once per enhance call alongside the existing `🦾 prompt-mode: …` line. Useful for the post-merge verification when the user dictates at each level.

- [ ] **Step 3.4 — Verify no orphan references**

```bash
grep -rn "cleanupDirective\|CLEANUP_LEVEL" VoiceInk --include="*.swift"
```

Expected: definition in `AIPrompts.swift`, call site in `AIEnhancementService.swift:getSystemMessage`. Each used ≥1 time.

**Risk:** LOW — additive prefix on the existing prompt body. The directive's wording may need tuning (Migration policy #5 flags this); the structural change is safe.

**Verification:** type-check passes. Manual: dictate a sentence at each of `.light`/`.medium`/`.high`, open Enhancement Settings panel → "Last Sent System Prompt" disclosure, confirm the directive prefix matches the active level. The output should visibly differ across levels (Light preserves filler-adjacent wording; High polishes).

---

### Task 4 — Migrate `AIEnhancementService` + `PowerModeSessionManager`

**Files:**
- Modify: `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`
- Modify: `VoiceInk/PowerMode/PowerModeSessionManager.swift`

- [ ] **Step 4.1 — Replace `@Published isEnhancementEnabled` with `@Published enhanceLevel`**

In `AIEnhancementService.swift:16-25`, replace:

```swift
@Published var isEnhancementEnabled: Bool {
    didSet {
        UserDefaults.standard.set(isEnhancementEnabled, forKey: "isAIEnhancementEnabled")
        if isEnhancementEnabled && selectedPromptId == nil {
            selectedPromptId = customPrompts.first?.id
        }
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
        NotificationCenter.default.post(name: .enhancementToggleChanged, object: nil)
    }
}
```

with:

```swift
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
```

- [ ] **Step 4.2 — Update `init(...)` to read the canonical key with legacy fallback**

In `AIEnhancementService.swift:83-115` `init(...)`, replace the `self.isEnhancementEnabled = UserDefaults.standard.bool(...)` line:

```swift
// W12.A: prefer canonical enhanceLevel key; fall back to legacy bool key.
if let raw = UserDefaults.standard.string(forKey: "enhanceLevel"),
   let level = EnhanceLevel(rawValue: raw) {
    self.enhanceLevel = level
} else if UserDefaults.standard.object(forKey: "isAIEnhancementEnabled") != nil {
    self.enhanceLevel = .from(legacyBool: UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled"))
} else {
    self.enhanceLevel = .default
}
```

The two-step fallback handles three cases:
- New install with `AppDefaults.registerDefaults()` → `enhanceLevel: "medium"` registered → reads as `.medium`.
- Existing install with `isAIEnhancementEnabled: true` set → reads as `.medium` via the legacy fallback.
- Existing install with `isAIEnhancementEnabled: false` set → reads as `.none` via the legacy fallback.

Then any subsequent writes go through the new `enhanceLevel` setter, which keeps both keys in sync.

- [ ] **Step 4.3 — Update `handleAPIKeyChange` invalidation**

`AIEnhancementService.swift:121-128` currently sets `self.isEnhancementEnabled = false` when API key invalidates. The derived setter handles this — it maps to `enhanceLevel = .none`. **No change needed at this call site.** (Confirms Migration policy #2 in practice.)

- [ ] **Step 4.4 — Migrate `PowerModeSessionManager.ApplicationState`**

In `PowerModeSessionManager.swift:4-12`, replace:

```swift
struct ApplicationState: Codable {
    var isEnhancementEnabled: Bool
    var useScreenCaptureContext: Bool
    var selectedPromptId: String?
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var selectedLanguage: String?
    var transcriptionModelName: String?
}
```

with:

```swift
struct ApplicationState: Codable {
    /// W12.A canonical state. Replaces stored `isEnhancementEnabled: Bool`.
    var enhanceLevel: EnhanceLevel
    var useScreenCaptureContext: Bool
    var selectedPromptId: String?
    var selectedAIProvider: String?
    var selectedAIModel: String?
    var selectedLanguage: String?
    var transcriptionModelName: String?

    enum CodingKeys: String, CodingKey {
        case enhanceLevel
        case isEnhancementEnabled  // legacy fallback
        case useScreenCaptureContext, selectedPromptId, selectedAIProvider
        case selectedAIModel, selectedLanguage, transcriptionModelName
    }

    init(enhanceLevel: EnhanceLevel,
         useScreenCaptureContext: Bool,
         selectedPromptId: String?,
         selectedAIProvider: String?,
         selectedAIModel: String?,
         selectedLanguage: String?,
         transcriptionModelName: String?) {
        self.enhanceLevel = enhanceLevel
        self.useScreenCaptureContext = useScreenCaptureContext
        self.selectedPromptId = selectedPromptId
        self.selectedAIProvider = selectedAIProvider
        self.selectedAIModel = selectedAIModel
        self.selectedLanguage = selectedLanguage
        self.transcriptionModelName = transcriptionModelName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let canonical = try c.decodeIfPresent(EnhanceLevel.self, forKey: .enhanceLevel) {
            enhanceLevel = canonical
        } else if let legacyBool = try c.decodeIfPresent(Bool.self, forKey: .isEnhancementEnabled) {
            enhanceLevel = .from(legacyBool: legacyBool)
        } else {
            enhanceLevel = .default
        }
        useScreenCaptureContext = try c.decode(Bool.self, forKey: .useScreenCaptureContext)
        selectedPromptId = try c.decodeIfPresent(String.self, forKey: .selectedPromptId)
        selectedAIProvider = try c.decodeIfPresent(String.self, forKey: .selectedAIProvider)
        selectedAIModel = try c.decodeIfPresent(String.self, forKey: .selectedAIModel)
        selectedLanguage = try c.decodeIfPresent(String.self, forKey: .selectedLanguage)
        transcriptionModelName = try c.decodeIfPresent(String.self, forKey: .transcriptionModelName)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enhanceLevel, forKey: .enhanceLevel)
        try c.encode(enhanceLevel != .none, forKey: .isEnhancementEnabled)  // forward-compat
        try c.encode(useScreenCaptureContext, forKey: .useScreenCaptureContext)
        try c.encodeIfPresent(selectedPromptId, forKey: .selectedPromptId)
        try c.encodeIfPresent(selectedAIProvider, forKey: .selectedAIProvider)
        try c.encodeIfPresent(selectedAIModel, forKey: .selectedAIModel)
        try c.encodeIfPresent(selectedLanguage, forKey: .selectedLanguage)
        try c.encodeIfPresent(transcriptionModelName, forKey: .transcriptionModelName)
    }
}
```

- [ ] **Step 4.5 — Update `applyConfiguration(...)` and `restoreState(...)`**

In `PowerModeSessionManager.swift:110-148` `applyConfiguration(...)`, replace:

```swift
enhancementService.isEnhancementEnabled = config.isAIEnhancementEnabled
```

with:

```swift
enhancementService.enhanceLevel = config.enhanceLevel
```

Replace the gate `if config.isAIEnhancementEnabled {` with `if config.enhanceLevel != .none {`.

In `PowerModeSessionManager.swift:150-179` `restoreState(...)`, replace:

```swift
enhancementService.isEnhancementEnabled = state.isEnhancementEnabled
```

with:

```swift
enhancementService.enhanceLevel = state.enhanceLevel
```

In the `beginSession(...)` snapshot at line 47-55 and `updateSessionSnapshot()` at line 96-104, replace the `isEnhancementEnabled: enhancementService.isEnhancementEnabled` field with `enhanceLevel: enhancementService.enhanceLevel`.

- [ ] **Step 4.6 — Update `AppDefaults`**

In `VoiceInk/AppDefaults.swift`, add to the registered defaults dictionary (alongside the existing Enhancement keys):

```swift
"enhanceLevel": EnhanceLevel.default.rawValue,  // W12.A — "medium"
```

- [ ] **Step 4.7 — Update `SystemInfoService`**

`SystemInfoService.swift:163` currently reads `UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled")`. Migrate to the canonical key with legacy fallback:

```swift
// W12.A: read canonical level; fall back to legacy bool. Surface in the
// system info display.
let enhanceLevelRaw = UserDefaults.standard.string(forKey: "enhanceLevel")
let enhanceLevel = enhanceLevelRaw.flatMap(EnhanceLevel.init(rawValue:))
    ?? EnhanceLevel.from(legacyBool: UserDefaults.standard.bool(forKey: "isAIEnhancementEnabled"))
let enhancementEnabled = enhanceLevel != .none
```

If `SystemInfoService` formats output for the user, surface the level (e.g., "Cleanup: Medium") rather than the bool. Coder discretion.

- [ ] **Step 4.8 — Verify no orphan references**

```bash
grep -rn "enhanceLevel" VoiceInk --include="*.swift" | wc -l
```

Expected: ≥10 matches across model, service, session manager, AppDefaults, SystemInfoService, plus the UI surfaces (Tasks 7-9).

```bash
grep -rn "isAIEnhancementEnabled\|isEnhancementEnabled" VoiceInk --include="*.swift" | wc -l
```

Expected: similar count to before (Migration policy #2 keeps the bool readers compiling). The count should NOT have dropped to zero — that would mean the derived bool was removed accidentally.

**Risk:** MED — the dual-key migration spans `AIEnhancementService.init`, `AppDefaults`, `PowerModeSessionManager` Codable + `applyConfiguration` + `restoreState`. The on-disk session blob and the `UserDefaults` keys must both round-trip cleanly across upgrade.

**Verification:** type-check passes. Manual:
- Fresh install → `enhanceLevel = .medium` (registered default).
- Pre-W12.A install with `isAIEnhancementEnabled: true` → migrates to `.medium`.
- Pre-W12.A install with `isAIEnhancementEnabled: false` → migrates to `.none`.
- Toggle level via UI → `UserDefaults.standard.string(forKey: "enhanceLevel")` shows new raw value.

---

### Task 5 — Extend `WordDiffEngine` with `tokenLevelDiff`

**Files:**
- Modify: `VoiceInk/Services/WordDiffEngine.swift`

- [ ] **Step 5.1 — Add `DiffOp` enum**

At the top of `WordDiffEngine`:

```swift
extension WordDiffEngine {
    /// W12.A token-level diff op for inline diff rendering. Emitted in
    /// reading order — apply each op in sequence to reconstruct the edited
    /// text, with `.equal` and `.insert` segments visible and `.delete`
    /// segments shown stricken-through. See plan
    /// `docs/superpowers/plans/W12A-auto-cleanup-levels.md` §Task 5.
    enum DiffOp: Equatable {
        case equal(String)
        case insert(String)
        case delete(String)
    }
}
```

- [ ] **Step 5.2 — Add `tokenLevelDiff(...)` function**

```swift
extension WordDiffEngine {
    static func tokenLevelDiff(original: String, edited: String) -> [DiffOp] {
        let origTokens = tokenize(original)
        let editTokens = tokenize(edited)
        guard !origTokens.isEmpty || !editTokens.isEmpty else { return [] }
        if origTokens.isEmpty { return editTokens.map { .insert($0) } }
        if editTokens.isEmpty { return origTokens.map { .delete($0) } }

        let lcsIndices = lcsIndexPairs(origTokens, editTokens)

        var ops = [DiffOp]()
        var oi = 0
        var ei = 0

        for (anchorO, anchorE) in lcsIndices {
            // Tokens in original before anchor that aren't in edited → delete
            while oi < anchorO {
                ops.append(.delete(origTokens[oi]))
                oi += 1
            }
            // Tokens in edited before anchor that aren't in original → insert
            while ei < anchorE {
                ops.append(.insert(editTokens[ei]))
                ei += 1
            }
            // The anchor itself is shared — emit as equal (use the edited
            // form's casing since post-cleanup capitalization wins).
            ops.append(.equal(editTokens[anchorE]))
            oi = anchorO + 1
            ei = anchorE + 1
        }

        // Trailing tail
        while oi < origTokens.count {
            ops.append(.delete(origTokens[oi]))
            oi += 1
        }
        while ei < editTokens.count {
            ops.append(.insert(editTokens[ei]))
            ei += 1
        }

        return ops
    }
}
```

This reuses the existing private `lcsIndexPairs(...)` and `tokenize(...)` helpers — no new infrastructure.

- [ ] **Step 5.3 — Verify call sites**

The new function has no callers yet (T6 will wire it). The existing `findSingleWordSubstitutions(...)` is untouched.

```bash
grep -rn "tokenLevelDiff\|WordDiffEngine.DiffOp" VoiceInk --include="*.swift"
```

Expected: only the new definition. T6 adds the call site.

**Risk:** LOW — additive function. Edge cases (empty input, fully-equal input, fully-disjoint input) handled by Step 5.2's guards.

**Verification:** type-check passes. Manual sanity (in-line, no test file): instantiate via `WordDiffEngine.tokenLevelDiff(original: "the cat sat", edited: "the dog sat")` and confirm output is `[.equal("the"), .delete("cat"), .insert("dog"), .equal("sat")]` (or equivalent given casing preservation).

---

### Task 6 — Diff toggle + Undo AI edit in `TranscriptionDetailView`

**Files:**
- Modify: `VoiceInk/Views/History/TranscriptionDetailView.swift`

- [ ] **Step 6.1 — Add `DiffMode` state**

Inside the `TranscriptionDetailView` struct, alongside existing `@State` declarations:

```swift
private enum DiffMode: String, CaseIterable {
    case panes
    case inline

    var displayName: String {
        switch self {
        case .panes:  return "Panes"
        case .inline: return "Diff"
        }
    }
}

@State private var diffMode: DiffMode = .panes
```

- [ ] **Step 6.2 — Add diff-mode picker to header (or near textPanes)**

Insert a small segmented picker above `textPanes` — only visible when `transcription.enhancedText != nil` (no diff to show otherwise):

```swift
@ViewBuilder
private var diffModePicker: some View {
    if transcription.enhancedText?.isEmpty == false,
       transcription.enhancedText != transcription.text {
        Picker("", selection: $diffMode) {
            ForEach(DiffMode.allCases, id: \.self) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)
        .padding(.bottom, 4)
    }
}
```

Insert `diffModePicker` in `body` between `headerRow` (or `AudioTimelineView` if present) and `textPanes`. Hidden when there's nothing to diff.

- [ ] **Step 6.3 — Branch `textPanes` on `diffMode`**

Replace the existing `textPanes` declaration at line 163-174 with a switch:

```swift
@ViewBuilder
private var textPanes: some View {
    switch diffMode {
    case .panes:
        VStack(alignment: .leading, spacing: 12) {
            textPane(label: "Original",
                     text: transcription.text,
                     accent: Palette.accent)
            if let enhanced = transcription.enhancedText, !enhanced.isEmpty {
                textPane(label: "Enhanced",
                         text: enhanced,
                         accent: Palette.accent)
            }
        }
    case .inline:
        if let enhanced = transcription.enhancedText, !enhanced.isEmpty {
            inlineDiffPane(raw: transcription.text, enhanced: enhanced)
        } else {
            // Fallback — no enhanced text means nothing to diff.
            textPane(label: "Original",
                     text: transcription.text,
                     accent: Palette.accent)
        }
    }
}
```

- [ ] **Step 6.4 — Implement `inlineDiffPane(raw:enhanced:)` with `AttributedString`**

```swift
private func inlineDiffPane(raw: String, enhanced: String) -> some View {
    let ops = WordDiffEngine.tokenLevelDiff(original: raw, edited: enhanced)
    let attributed = renderDiff(ops: ops)

    return VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
            Circle().fill(Palette.accent).frame(width: 6, height: 6)
            Text("AI EDITS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .tracking(0.06 * 9)
            Spacer()
            // Legend
            HStack(spacing: 8) {
                legendChip(color: Palette.success, label: "added")
                legendChip(color: Palette.warn, label: "removed")
            }
            .font(.system(size: 9, weight: .medium))
        }
        ScrollView {
            Text(attributed)
                .font(.system(size: 13, weight: .regular))
                .lineSpacing(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .frame(maxHeight: 360)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.accent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.accent.opacity(0.18), lineWidth: 0.5)
        )
    }
}

private func renderDiff(ops: [WordDiffEngine.DiffOp]) -> AttributedString {
    var out = AttributedString()
    for (idx, op) in ops.enumerated() {
        var seg: AttributedString
        switch op {
        case .equal(let s):
            seg = AttributedString(s)
            seg.foregroundColor = .primary
        case .insert(let s):
            seg = AttributedString(s)
            seg.foregroundColor = Palette.success
            seg.underlineStyle = .single
        case .delete(let s):
            seg = AttributedString(s)
            seg.foregroundColor = Palette.warn
            seg.strikethroughStyle = .single
        }
        out.append(seg)
        if idx < ops.count - 1 {
            out.append(AttributedString(" "))
        }
    }
    return out
}

private func legendChip(color: Color, label: String) -> some View {
    HStack(spacing: 4) {
        Circle().fill(color).frame(width: 6, height: 6)
        Text(label).foregroundColor(.secondary)
    }
}
```

- [ ] **Step 6.5 — Add Undo AI edit button to `actionsRow`**

In the existing `actionsRow` (line 210-244), insert (between `Re-transcribe` and the prompt picker, or alongside Re-enhance — coder discretion; recommended: right after `Re-enhance`):

```swift
if transcription.enhancedText != nil {
    actionButton(
        label: "Undo AI edit",
        icon: "arrow.uturn.backward"
    ) {
        undoAIEdit()
    }
    .disabled(isOperationInProgress)
}
```

- [ ] **Step 6.6 — Implement `undoAIEdit()`**

```swift
private func undoAIEdit() {
    transcription.enhancedText = nil
    transcription.aiEnhancementModelName = nil
    transcription.promptName = nil
    transcription.enhancementDuration = nil
    transcription.aiRequestSystemMessage = nil
    transcription.aiRequestUserMessage = nil
    do {
        try modelContext.save()
        // Snap back to Panes mode — the inline diff has nothing to render
        // once enhancedText is nil.
        diffMode = .panes
        showStatus("AI edit reverted", isError: false)
    } catch {
        showStatus("Failed to revert: \(error.localizedDescription)", isError: true)
    }
}
```

- [ ] **Step 6.7 — Verify**

```bash
grep -rn "tokenLevelDiff\|undoAIEdit\|diffMode\|inlineDiffPane" VoiceInk --include="*.swift"
```

Expected: definitions and call sites within `TranscriptionDetailView.swift` plus the engine definition in `WordDiffEngine.swift`.

**Risk:** MED — UI work touching the most-visible history surface. Edge cases:
- (a) `enhancedText == raw text` (model produced unchanged output) → diff is all `.equal`. Render is fine — the legend still shows + the user sees no insertions/deletions, signaling "model agreed with raw".
- (b) `enhancedText.isEmpty` post-Undo → picker hides, mode auto-snaps to `.panes`.
- (c) Long transcripts (1000+ words) → diff could be slow. The existing `lcsIndexPairs` is O(n*m); for ~500-token transcripts on each side, still fast. If a user complains, profile and consider a Hunt-Szymanski variant in a follow-up.

**Verification:** type-check passes. Manual:
- Open a History entry that has `enhancedText`. Confirm the Diff picker appears.
- Switch to Diff. Confirm insertions are green-underlined, deletions orange-strikethrough.
- Hit Undo AI edit. Confirm the entry's enhanced text disappears, picker hides, status shows "AI edit reverted".
- Hit Re-enhance. Confirm a new enhanced text appears, picker reappears.

---

### Task 7 — Replace toggle in `EnhancementSettingsView` (global Settings)

**Files:**
- Modify: `VoiceInk/Views/EnhancementSettingsView.swift`

- [ ] **Step 7.1 — Replace the Toggle with a Picker**

In `VoiceInk/Views/EnhancementSettingsView.swift:55-64`, replace:

```swift
Toggle(isOn: $enhancementService.isEnhancementEnabled) {
    HStack(spacing: 4) {
        Text("Enable Enhancement")
        InfoTip(...)
    }
}
.toggleStyle(.switch)
```

with:

```swift
VStack(alignment: .leading, spacing: 8) {
    HStack(spacing: 4) {
        Text("Cleanup Level")
            .font(.system(size: 13, weight: .medium))
        InfoTip(
            "Choose how aggressively the AI rewrites your transcript. None pastes the raw transcript verbatim. Light removes fillers. Medium fixes grammar. High polishes for clarity.",
            learnMoreURL: "https://tryvoiceink.com/docs/enhancements-configuring-models"
        )
        Spacer()
    }
    Picker("", selection: $enhancementService.enhanceLevel) {
        ForEach(EnhanceLevel.allCases, id: \.self) { level in
            Text(level.displayName).tag(level)
        }
    }
    .pickerStyle(.segmented)
    .labelsHidden()

    Text(enhancementService.enhanceLevel.description)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
}
```

- [ ] **Step 7.2 — Update the section header status pill**

`SettingsSectionHeader` at line 67-74 currently reads `statusText: enhancementService.isEnhancementEnabled ? "On" : "Off"`. Replace with the level's display name:

```swift
SettingsSectionHeader(
    icon: "wand.and.stars",
    title: "Enhancement",
    subtitle: "Pass transcripts through an LLM before pasting.",
    accent: Palette.accent,
    statusText: enhancementService.enhanceLevel.displayName,
    statusTone: enhancementService.enhanceLevel == .none ? .neutral : .positive
)
```

- [ ] **Step 7.3 — Update opacity gates**

The `.opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)` modifiers at lines 101 + 157 read the derived bool — they keep working (Migration policy #2). DO NOT change them.

**Risk:** LOW — UI shape change inside an existing `Form`. Picker binding to `@Published` property is straightforward.

**Verification:** type-check passes. Manual: open Settings → Enhancement. See the 4-segment picker. Change selection. Confirm:
- Status pill in the header updates from "Medium" → "High" etc.
- Description text below picker updates.
- Setting persists across app relaunch (`UserDefaults.standard.string(forKey: "enhanceLevel")`).

---

### Task 8 — Add level picker to `EnhancementSettingsPanel` (recorder-side)

**Files:**
- Modify: `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`

- [ ] **Step 8.1 — Insert a new Section at the top of the Form**

In `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`, between line 56 (`Form {`) and the existing "Context" Section at line 57, insert:

```swift
Section {
    VStack(alignment: .leading, spacing: 8) {
        Picker("", selection: $enhancementService.enhanceLevel) {
            ForEach(EnhanceLevel.allCases, id: \.self) { level in
                Text(level.displayName).tag(level)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        Text(enhancementService.enhanceLevel.description)
            .font(.caption)
            .foregroundColor(.secondary)
    }
} header: {
    HStack(spacing: 4) {
        Text("Cleanup Level")
        InfoTip("None pastes raw transcripts. Light removes fillers. Medium fixes grammar. High polishes for clarity.")
    }
}
```

This is the FIRST Section in the panel — the user opens this from the recorder and immediately sees the dial.

- [ ] **Step 8.2 — Verify**

```bash
grep -n "enhanceLevel" VoiceInk/Views/Components/EnhancementSettingsPanel.swift
```

Expected: ≥1 binding plus the Section block.

**Risk:** LOW — additive Section in an existing Form. Matches the existing Form-Section idiom (intentionally; W13.D will purge this whole panel to W5 SettingsCard later — DO NOT pre-purge).

**Verification:** type-check passes. Manual: open recorder → tap settings → Enhancement Settings panel. See the new "Cleanup Level" Section at top. Change level → state propagates to the global service.

---

### Task 9 — Replace toggle in `PowerModeConfigView` (per-PowerMode)

**Files:**
- Modify: `VoiceInk/PowerMode/PowerModeConfigView.swift`

- [ ] **Step 9.1 — Replace state declaration**

In `PowerModeConfigView.swift:34`, replace:

```swift
@State private var isAIEnhancementEnabled: Bool
```

with:

```swift
@State private var enhanceLevel: EnhanceLevel
```

- [ ] **Step 9.2 — Update initializers**

`PowerModeConfigView` has two init paths (line 83 for new config, line 99 for editing existing). Update:

- New (line 83): `_enhanceLevel = State(initialValue: .default)` (Medium).
- Existing (line 99): `_enhanceLevel = State(initialValue: latestConfig.enhanceLevel)`.

- [ ] **Step 9.3 — Replace the Toggle in `aiEnhancementCard`**

In `PowerModeConfigView.swift:521-535`, replace:

```swift
Toggle("AI Enhancement", isOn: $isAIEnhancementEnabled)
    .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
    .onChange(of: isAIEnhancementEnabled) { _, newValue in
        if newValue {
            if selectedAIProvider == nil {
                selectedAIProvider = aiService.selectedProvider.rawValue
            }
            if selectedAIModel == nil {
                selectedAIModel = aiService.currentModel
            }
            if selectedPromptId == nil {
                selectedPromptId = enhancementService.allPrompts.first?.id
            }
        }
    }
```

with:

```swift
VStack(alignment: .leading, spacing: 6) {
    HStack {
        Text("Cleanup Level")
            .font(.system(size: 13, weight: .medium))
        Spacer()
    }
    Picker("", selection: $enhanceLevel) {
        ForEach(EnhanceLevel.allCases, id: \.self) { level in
            Text(level.displayName).tag(level)
        }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .onChange(of: enhanceLevel) { _, newValue in
        // Mirror the legacy onChange — when the user dials AWAY from .none,
        // seed defaults so the rest of the card has something to render.
        if newValue != .none {
            if selectedAIProvider == nil {
                selectedAIProvider = aiService.selectedProvider.rawValue
            }
            if selectedAIModel == nil {
                selectedAIModel = aiService.currentModel
            }
            if selectedPromptId == nil {
                selectedPromptId = enhancementService.allPrompts.first?.id
            }
        }
    }
    Text(enhanceLevel.description)
        .font(.caption)
        .foregroundColor(.secondary)
}
```

- [ ] **Step 9.4 — Update the visibility gate**

In `PowerModeConfigView.swift:537`, replace:

```swift
if isAIEnhancementEnabled {
    aiProviderPicker
    aiModelPicker
    enhancementPromptPicker
    Toggle("Context Awareness", isOn: $useScreenCapture)
        .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
}
```

with:

```swift
if enhanceLevel != .none {
    aiProviderPicker
    aiModelPicker
    enhancementPromptPicker
    Toggle("Context Awareness", isOn: $useScreenCapture)
        .toggleStyle(SwitchToggleStyle(tint: Palette.accent))
}
```

- [ ] **Step 9.5 — Update validation guard**

In `PowerModeConfigView.swift:149`, replace:

```swift
if isAIEnhancementEnabled && selectedPromptId == nil {
```

with:

```swift
if enhanceLevel != .none && selectedPromptId == nil {
```

- [ ] **Step 9.6 — Update builder + save paths**

In `PowerModeConfigView.swift:704`, replace:

```swift
isAIEnhancementEnabled: isAIEnhancementEnabled,
```

with:

```swift
enhanceLevel: enhanceLevel,
```

In `PowerModeConfigView.swift:719`, replace:

```swift
updatedConfig.isAIEnhancementEnabled = isAIEnhancementEnabled
```

with:

```swift
updatedConfig.enhanceLevel = enhanceLevel
```

- [ ] **Step 9.7 — Verify**

```bash
grep -n "isAIEnhancementEnabled\|enhanceLevel" VoiceInk/PowerMode/PowerModeConfigView.swift
```

Expected: zero in-tree references to `isAIEnhancementEnabled` STATE in `PowerModeConfigView` (only the derived bool on the model is referenced via `enhanceLevel` migration). `enhanceLevel` references at the @State, init, picker binding, validation guard, and save paths.

**Risk:** LOW — straightforward state-shape change inside an existing SettingsCard. The Toggle → Picker swap preserves the card's chrome and the nested controls.

**Verification:** type-check passes. Manual: open a PowerMode → Configure. See the segmented "Cleanup Level" picker INSIDE the AI Enhancement SettingsCard. Change level → save → confirm the saved config persists with `enhanceLevel: "high"` (or whatever) in the JSON blob.

---

### Task 10 — Static checks (coder-runnable, no build)

**Files:** none (read-only verification).

- [ ] **Step 10.1 — All touched files compile in isolation via SourceKit**

The coder's environment runs SourceKit live. Verify:
- No undefined-symbol errors after each task.
- `EnhanceLevel.swift` imports `Foundation`.
- `TranscriptionDetailView.swift`'s `AttributedString` access compiles (`import SwiftUI` already present).
- No circular imports introduced.

- [ ] **Step 10.2 — No orphan references to old constants**

```bash
grep -rn '"isAIEnhancementEnabled"' VoiceInk --include="*.swift"
```

Expected: matches in `AIEnhancementService.swift` (legacy fallback read + forward-compat write), `PowerModeConfig.swift` (Codable backward-compat). Should NOT appear as a freshly-introduced read in any new code path.

```bash
grep -rn "Toggle.*[Aa]i.*Enhancement\|Toggle.*Enable Enhancement" VoiceInk --include="*.swift"
```

Expected: zero matches (the global Settings page Toggle and the PowerMode card Toggle are both gone). If hits remain in `MenuBarView.swift` / `EnhancementPromptPopover.swift` / `RecorderComponents.swift` / `AudioTranscribeView.swift` — those are the quick-toggle UIs that flip the derived bool. Per Migration policy #2 they STAY (still useful as a binary "off / on at Medium"). Confirm each by visiting the file and verifying the Toggle still works against the derived bool.

- [ ] **Step 10.3 — Confirm `EnhanceLevel` is referenced everywhere it should be**

```bash
grep -rn "EnhanceLevel" VoiceInk --include="*.swift"
```

Expected: matches in
- `Models/EnhanceLevel.swift` (definition)
- `Models/AIPrompts.swift` (cleanupDirective signature)
- `Services/AIEnhancement/AIEnhancementService.swift` (Published property + init)
- `PowerMode/PowerModeConfig.swift` (stored field + Codable)
- `PowerMode/PowerModeSessionManager.swift` (ApplicationState field + Codable)
- `PowerMode/PowerModeConfigView.swift` (@State + Picker + builder)
- `Views/EnhancementSettingsView.swift` (Picker)
- `Views/Components/EnhancementSettingsPanel.swift` (Picker)
- `Services/SystemInfoService.swift` (read-only display)

≥9 distinct files. If any of these is missing, that task wasn't completed.

- [ ] **Step 10.4 — Confirm `WordDiffEngine.tokenLevelDiff` is wired**

```bash
grep -rn "tokenLevelDiff\|WordDiffEngine.DiffOp" VoiceInk --include="*.swift"
```

Expected: matches in `WordDiffEngine.swift` (definition) AND `TranscriptionDetailView.swift` (call site).

- [ ] **Step 10.5 — Confirm Undo AI edit is wired**

```bash
grep -n "undoAIEdit\|Undo AI edit" VoiceInk --include="*.swift" -r
```

Expected: matches in `TranscriptionDetailView.swift` (definition + button label + call site).

---

### Task 11 — Integration build + post-merge verification

**Files:** none (verification + report).

- [ ] **Step 11.1 — Single integration build**

```bash
make local
```

Expected: clean build. If it fails:
- Most likely: a call site that passes positional `isAIEnhancementEnabled:` to `PowerModeConfig(...)` was missed in T2's grep+update. Re-run the grep and patch.
- Second-most-likely: `AttributedString.foregroundColor` API mismatch — confirm SwiftUI import + check if the property is `.foregroundColor` (`AttributedString`) vs the older `.color`.
- Third-most-likely: Codable `init(from:)` signature mismatch in `ApplicationState` — confirm the explicit init coexists with the synthesized memberwise init.

Per CLAUDE.md cadence, this is the only build run during the packet.

- [ ] **Step 11.2 — Coder smoke pass (manual)**

Pick MLX with the active model. Smoke checklist:
- Open Settings → Enhancement. See the 4-segment picker. Default cell selected = Medium.
- Change to Light. Description text updates.
- Dictate "um so I think we should ship this on Friday you know" → enhance runs → output preserves wording, removes fillers ("So I think we should ship this on Friday."). Console shows `🦾 enhance: level=light`.
- Change to High. Re-dictate similar input. Output is more polished. Console shows `🦾 enhance: level=high`.
- Change to None. Dictate. No enhance call fires (existing pipeline gate); raw is pasted.
- Open the resulting History entry. See diff picker (Panes/Diff). Switch to Diff. See insertions green-underlined, deletions orange-strikethrough.
- Tap "Undo AI edit". Confirm enhanced text disappears, picker hides, status "AI edit reverted" appears.
- Tap "Re-enhance" (with current level). Confirm new enhanced text appears.

- [ ] **Step 11.3 — User-side post-merge verification protocol**

After the code commit lands, the user runs the qualitative verification:

1. Pick a sample dictation; run with each of the 4 levels back-to-back.
2. Eyeball outputs: Light preserves wording with punctuation/fillers fix; Medium adds grammar fixes; High polishes prose.
3. If level boundaries don't match the user's intuition, tune the directive strings in `AIPrompts.cleanupDirective(for:)` in a follow-up packet.
4. Open a History entry. Toggle Diff. Confirm insertions/deletions render correctly.
5. Tap Undo AI edit. Confirm the entry reverts to raw and no MLX/AFM activity in CSV.
6. Toggle global level back to None. Dictate. Confirm CSV has no enhance row for that dictation.
7. Configure a PowerMode with `enhanceLevel = .high`. Activate it. Dictate. Confirm CSV row shows the High directive applied.
8. End PowerMode session. Confirm global level restores.

- [ ] **Step 11.4 — Coder report to lead**

Send the lead:
- Confirmation of all 9 tasks completed (or which deferred per §Risks).
- Build status.
- Smoke-dictation Console log (3 levels showing different outputs; Diff render; Undo flow).
- `EnhancementSettingsView` + `PowerModeConfigView` + `EnhancementSettingsPanel` screenshots showing the new pickers (optional but useful).
- Any architectural surprises encountered (especially around AttributedString rendering or the legacy-bool fallback).

The lead handles the two commits + push + final handoff doc.

---

## Test plan

Per master plan §0 Q10 (test-infra deferred): no `xcodebuild test` runs. Validation is build-only via `make local` (Task 11.1) plus smoke dictation (Task 11.2) plus user-side post-merge verification (Task 11.3).

**What `xcodebuild build` runs:**
- Single `make local` invocation at Task 11.1. ~3 min cold; warm rebuilds are seconds.

**What the user does for smoke validation:**
- Coder smoke (Task 11.2): the 8-point checklist above.
- User verification (Task 11.3): the 8-step qualitative protocol.

If any of those expected behaviors don't materialize, the failing task is the candidate for a focused follow-up packet — see §Rollback plan.

---

## Rollback plan

**Single-commit packet → `git revert <code commit sha>` restores the entire pre-W12.A behavior.** Plan doc commit stays (not reverted) so the historical record is preserved.

**Why squashed-not-split:**
- T2 + T4 are tightly coupled (model field + service field + session-manager field all share the legacy-bool fallback story).
- T3 + T7 + T8 + T9 share the EnhanceLevel enum's UI projection.
- T5 + T6 are coupled by the diff render path.
- A per-task commit matrix would create a brittle revert (e.g., reverting T2 alone would leave T9's UI binding to a non-existent `enhanceLevel` field).

**Per-feature surgical revert** (if a single feature turns out worse):
- **Level dial regress:** force `getSystemMessage(for:)` to ignore `enhanceLevel` and always use the unprefixed prompt body. Effectively makes the picker a no-op cosmetic dial. Restores pre-W12.A enhance behavior; keeps the new persistence + UI surfaces alive for a follow-up patch.
- **Diff view regress:** force `diffMode = .panes` always; hide the picker. Effectively hides the inline diff. Panes mode = pre-W12.A behavior.
- **Undo AI edit regress:** comment out the `actionButton(label: "Undo AI edit", ...)` block. The function `undoAIEdit()` becomes dead code; harmless.
- **Per-PowerMode level regress:** in `PowerModeConfigView.swift`, force the picker selection to map 1:1 to `.medium`/`.none` ignoring Light/High. Restores binary behavior for that surface only.

**Detection signals** (which production data tells us a revert is needed):
- User reports cleanup output is visibly worse vs memory of pre-W12.A → directive wording too aggressive at the user's chosen level. Tune `cleanupDirective(for:)`. NOT a revert; a follow-up patch.
- `🦾 enhance: level=…` line shows the wrong level (e.g., user picked High, log shows Medium) → `@Published` binding bug. Investigate; revert T7/T8/T9 if unfixable.
- Diff view crashes on long input → AttributedString construction issue with very large strings. Force `.panes` only as a hotfix.
- Undo AI edit doesn't persist → `modelContext.save()` silently failing. Investigate; revert T6's Undo wiring if unfixable.
- Existing user upgrades and finds enhance is unexpectedly off → migration fallback didn't fire. Re-check `AIEnhancementService.init` and `AppDefaults.registerDefaults()`.

**Blast radius of a full revert:** zero data loss. All edits are in-memory state + AppStorage keys + Codable shapes. The `enhanceLevel` UserDefaults key + the new `enhanceLevel` field in serialized PowerMode configs would persist after revert but read code paths are gone — harmless dead state. The `enhancedText = nil` writes from Undo AI edit are also irreversible (raw is preserved on `Transcription.text`; the user can Re-enhance to regenerate).

---

## Risks / unknowns

1. **Level directives may need tuning after the user-side reference set.** Per Migration policy #5, the proposed directive wording is the design intent; the user's qualitative reference (Pre-merge gate) gives the lead a way to refine. **Mitigation:** ship the v1 wording; tune in a follow-up. The `cleanupDirective(for:)` function is the single point of edit — no other code path needs to change to refine the wording.

2. **Fast-path interaction is level-agnostic.** Per Migration policy #6, the W11.A2 short-transcript fast-path doesn't carry the level directive. A user setting High and dictating "yeah totally" gets the fast-path's light cleanup, NOT high-aggressiveness rewriting. **Mitigation:** acceptable in v1 — short inputs rarely benefit from style polishing. Follow-up: if a user reports the discrepancy, gate the fast-path on `enhanceLevel == .light` only; for `.medium`/`.high` short inputs, fall back to the standard path with directive prefix (still small, since context is empty).

3. **AttributedString render performance on long transcripts.** The diff op array can be large for 1000-word transcripts. Each op becomes an `AttributedString` segment — SwiftUI's text-layout cost scales with run count. **Mitigation:** v1 doesn't paginate or virtualize the diff view. If user reports lag, paginate by paragraph or lazy-render. Out of scope for v1.

4. **Bool-as-derived-view scaling.** Migration policy #2 keeps ~30 call sites compiling unchanged. If subsequent W12 packets (B = Command Mode, C = Snippets, D = Hands-free, E = Scratchpad) add more level-dependent logic, those packets may need explicit level reads instead of bool reads. **Mitigation:** flag for W12.B-E planners. The derived bool is a convenience, not a forever solution.

5. **`PowerModeSessionManager` session-blob upgrade.** A user with an in-flight PowerMode session at the moment of the W12.A upgrade will have their session blob decoded by the new code. Step 4.4's decoder handles the legacy bool → enum migration. **Test:** confirm by setting `PowerModeSessionManager.shared.beginSession(...)` on a pre-W12.A build, then upgrading and observing `recoverSession()` fires `endSession()` cleanly. (Sessions are auto-recovered + cleared on app launch per `PowerModeSessionManager:203-208`.)

6. **`SystemInfoService.swift:163` legacy-bool-only read.** Per Step 4.7, this is migrated to read the canonical key with legacy fallback. **Mitigation:** confirm via grep at Step 10.3.

7. **Quick-toggle surfaces don't gain Light/High.** Per Migration policy #2, the menubar Toggle, the recorder Toggle, the EnhancementPromptPopover Toggle, the AudioTranscribeView Toggle stay binary. Cycling those toggles flips between None and Medium only. **Mitigation:** acceptable — quick-toggle is meant for fast on/off; the dial lives in Settings + Recorder Settings panel + PowerMode config. If user reports they want a 4-level menubar dial, follow-up packet.

8. **`EnhancementPromptPopover.swift`'s "AI Enhancement" Toggle is misleading post-W12.A.** The label still reads "AI Enhancement" (binary semantics) but underneath flips Medium/None. **Mitigation:** rename in a follow-up packet OR update the label string to reflect the dial. Out of scope here — per Migration policy #2, no behavior changes at quick-toggle surfaces in v1.

9. **No telemetry for level usage distribution.** We can't observe which level users settle on. **Mitigation:** acceptable for a single-user fork. The `🦾 enhance: level=…` log line lets the user manually review their CSV (W11.D timing logger) for level patterns.

10. **Test infra deferred per Q10.** `xcodebuild test` env-blocked. Means no automated regression catch for any Codable migration boundary. **Mitigation:** smoke + manual upgrade dance (Task 11.3). If a Codable shape regresses post-merge, blast radius is per-PowerMode (each PowerMode falls back to `.default = .medium` on decode failure — surprising but recoverable).

11. **Diff insertions can collapse the user's whitespace.** Step 5.2's diff is token-level (whitespace-tokenized). Multi-newline / multi-space input collapses to single-space. **Mitigation:** acceptable for v1. Follow-up: tokenize preserving original spacing (would require extending `tokenize(...)` and the rendering loop).

---

## Out of scope (explicit) for follow-ups

- **Wispr "Custom" cleanup level.** Per Migration policy #15. The user's existing custom prompts cover this already.
- **Different model per level.** Per master plan §3 W12.A scope: same model serves all levels. Out of scope; would conflict with W11's perf wins (each level swap would re-prewarm).
- **Per-prompt level override.** A custom prompt might want to force `.high` regardless of the global dial. Not in v1; the global level wins.
- **Level-aware fast-path.** Per Migration policy #6 + Risks #2. Follow-up if user reports the discrepancy.
- **Level UI on quick-toggle surfaces** (menubar, EnhancementPromptPopover, recorder quick toggle, AudioTranscribeView). Per Risks #7-8. Follow-up if user requests.
- **Persistent diff-mode preference.** Currently per-detail-view `@State`; reset to Panes on each open. Follow-up: `@AppStorage`.
- **Whitespace-preserving diff.** Per Risks #11.
- **Side-by-side highlighted diff (third mode).** v1 ships Panes (current side-by-side, no highlighting) + Diff (single-pane inline highlighted). A third "side-by-side highlighted" mode (both Original and Enhanced highlighted) is a polish item.
- **Pagination/virtualization for long diffs.** Per Risks #3.
- **`isAIEnhancementEnabled` Codable + UserDefaults forward-compat dropping.** Per Migration policy #3, drop in a follow-up packet ≥3 months post-W12.A merge.
- **Migrating ~30 call sites from bool reads to explicit level reads.** Per Migration policy #2 + Risks #4. Follow-up if/when W12.B-E packets need finer-grained reads.
- **AppStorage key namespacing.** Future cleanup could namespace under `enhancement.level.*`. Out of scope.
- **Test infrastructure unblock.** Per master plan §0 Q10. Separate session.
- **Other W12 packets (B/C/D/E).** Each gets its own plan file later.

---

## Open questions for lead

1. **Directive wording — review before merge?** Migration policy #5 proposes specific 60-90-token directives for Light/Medium/High. The user's qualitative reference set (Pre-merge gate) gives a pass to validate the wording against intuition. **Choice:** (a) Coder ships the proposed strings as-is, lead refines later in a follow-up; (b) Lead pulls the strings into a quick patch before W12.A merge. Recommend (a) — directive tuning is independent of the structural change; iterating on prompts is faster as a small commit.

2. **Fast-path level integration.** Migration policy #6 says fast-path stays level-agnostic in v1 — short transcripts always get the cleanup-only template regardless of level. **Confirm or flip:** should fast-path skip when `level == .high`, falling back to the standard path with the High directive? My recommendation: keep level-agnostic for v1, follow-up if user reports.

3. **Quick-toggle surfaces (menubar, recorder, popover, file-transcribe).** Migration policy #2 keeps them as binary toggles flipping between None and Medium. **Confirm or expand:** should any of these surface the 4-level dial? Recommend keeping binary — quick-toggle is meant for "instantly off / instantly default-on", not granular control.

4. **Pre-merge gate — capture or skip?** The qualitative reference set is a soft gate (Pre-merge ground-truth gate above). **Confirm:** does the user run the 3-dictation reference capture before code lands, or does the lead defer it to post-merge?

5. **Per-PowerMode picker placement.** T9 puts the Picker INSIDE the existing `aiEnhancementCard` SettingsCard (replacing the Toggle). **Confirm:** picker fits cleanly in the SettingsCard chrome, or extract to its own new SettingsCard for visual separation? My recommendation: keep inside the existing card — the level IS the AI Enhancement on/off, just with more granularity.

6. **`Toggle("AI Enhancement", ...)` label rename.** Per Risks #8, the labels at quick-toggle surfaces still read "AI Enhancement" (binary semantics). **Confirm:** rename to "Cleanup" or similar? Recommend leaving alone for v1; rename in a follow-up.

7. **Removing the `isAIEnhancementEnabled` Codable forward-compat encode.** Migration policy #3 keeps writing the legacy bool for downgrade tolerance. **Confirm timeline:** drop after 3 months? 6? At the next major version? Recommend 3 months — VoiceInk releases frequently and downgrade is rare.

8. **`AttributedString` foreground-color tinting on macOS.** SwiftUI's `Text(AttributedString)` honors `.foregroundColor` reliably on macOS 13+. We're targeting 26.0, so this is comfortably supported. **Confirm:** no concerns about color tinting under Light Mode / High Contrast? Recommend none — `Palette.success` and `Palette.warn` are saturated enough to remain visible.

9. **Diff legend placement.** Step 6.4 puts a tiny legend (`added` green dot, `removed` orange dot) inline in the section header. **Confirm:** legend visible enough OR move to a separate row above the diff text?

---

## Post-merge verification protocol (USER-SIDE)

1. Pick a sample dictation (~50-200 words with fillers + minor grammar issues). Run it with each of the 4 levels back-to-back via the global Settings → Enhancement picker. Eyeball outputs:
   - **None** → raw pasted, no enhance call, no `🦾 enhance:` row in `enhancement-timings.csv`.
   - **Light** → fillers gone, punctuation added, wording untouched.
   - **Medium** → fillers gone, punctuation added, grammar fixed, wording mostly preserved.
   - **High** → fillers gone, punctuation added, grammar fixed, prose tightened (some rewording).
2. Open the History detail of the Medium-enhanced entry. Confirm Diff picker (Panes / Diff) is visible.
3. Toggle to Diff. Confirm:
   - Inserted tokens render in `Palette.success` (green) underline.
   - Deleted tokens render in `Palette.warn` (orange) strikethrough.
   - Equal tokens render at default `.primary`.
   - Legend ("added"/"removed" with colored dots) is visible.
4. Tap "Undo AI edit". Confirm:
   - Enhanced text disappears.
   - Diff picker hides.
   - Status "AI edit reverted" appears for ~2.5s.
   - Re-enhance button still visible.
5. Tap "Re-enhance" (with the current global level still set). Confirm a new enhanced text appears, picker reappears.
6. Toggle global level back to None. Dictate a new sentence. Confirm raw is pasted; no enhance row in CSV.
7. Configure a PowerMode with `enhanceLevel = .high` (per-PowerMode override). Activate it (its bound app or its hotkey). Dictate. Confirm:
   - Console log: `🦾 enhance: level=high`.
   - CSV row reflects High directive (system message includes `<CLEANUP_LEVEL>High</CLEANUP_LEVEL>`).
8. End PowerMode session (deactivate app or end-session action). Confirm global level restores to whatever the user had before activation.
9. Quit + relaunch app. Confirm `enhanceLevel` persists (UserDefaults read at init).
10. Check that legacy users' on/off state migrated cleanly (this only matters for the user's own machine since this is a single-user fork): pre-W12.A `isAIEnhancementEnabled = true` → post-W12.A `enhanceLevel = .medium`.

If any step fails, log the failure mode + which task is implicated, and SendMessage the lead. Tasks 1-9 are independently revertible per §Rollback plan.

---

## Notes for the lead

- **`Transcription` schema is already correct.** The "raw alongside enhanced" persistence requirement is a no-op item — `Transcription.text` (raw) and `Transcription.enhancedText` (enhanced) coexist in the existing model. Confirmed via `VoiceInk/Models/Transcription.swift:13-14`. **No SwiftData migration needed.** The master plan §3 W12.A bullet point that says "Persist raw transcript alongside enhanced (currently only enhanced is kept)" was incorrect — the schema already kept both. Plan reflects this in §File structure / Untouched.
- **`WordDiffEngine` API is substitution-pair-only today.** Existing `findSingleWordSubstitutions(...)` returns `[(original, replacement)]` for the Vocabulary autolearn flow. T5 ADDS a sibling `tokenLevelDiff(...) -> [DiffOp]` for the inline-diff render. Both coexist; no caller of the existing function is touched.
- **Two commits, not one.** Plan doc lands first (`docs(plans): W12A — auto cleanup levels plan`). Code lands after lead sign-off (`feat(enhance): W12A — cleanup levels + diff view + undo AI edit`).
- **No new tests.** Build is the gate. Per Q10 deferral.
- **One integration build.** Per `feedback_skip_per_packet_builds.md`. Coder does NOT run `make local` during execution.
- **Forward-compat with W12.B-E.** The `EnhanceLevel` enum is the source of truth for cleanup intensity; subsequent packets (B = Command Mode rewrites, D = Hands-free) can read the level to decide their own behavior (e.g., Command Mode might force `.medium` regardless of global dial — that decision is W12.B's territory). The derived bool keeps everything compiling for now.
- **Open questions:** 9 above. None block the plan structure; most are wording / placement choices the lead may accept-as-proposed for v1.
