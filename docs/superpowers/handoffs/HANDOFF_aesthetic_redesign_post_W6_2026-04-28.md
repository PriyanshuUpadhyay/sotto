# Handoff: aesthetic redesign — post-W6, W5/W7 backlog + user-machine verification

**Date:** 2026-04-28
**Branch:** `main`
**Status:** ready-for-execution (5 of 7 redesign packets landed; W5 + W7 remain; user-machine smoke pass on W6 outstanding)

## Goal

Continue the VoiceInk aesthetic redesign. Two redesign packets remain — **W5 (Settings re-skin)** and **W7 (type + sound polish)**. Both depend only on W1 (already shipped) so they can run in parallel. Plus a user-machine visual smoke pass on the W6 changes (segregation grids, ratings chips, EXPERIMENTAL chip, download progress, WARN log path, legacy purge, prompts re-skin) before any of those surfaces are claimed production-tested.

## Work Completed (this session)

### Redesign packets

- [x] **W6 — AI Models + Prompts re-skin + MLX-quality follow-ups** (`3a711a2` plan + `0aef209` impl). 9 files modified, +466/-106. Full lineup of changes:
  - **MLX registry curation.** 4-entry curated lineup. Drops `mlx-community/gemma-3-1b-it-qat-4bit` (regurgitation + capacity ceiling) and `mlx-community/Qwen3.6-27B-4bit` (27B dense exceeds threshold on 32 GB base). Adds `mlx-community/gemma-4-e2b-it-4bit` as fastest tier — same gemma3 model type as the e4b default, no loadability risk. Marks `mlx-community/gemma-4-26b-a4b-it-4bit` `isExperimental: true` (Speed 3, EXPERIMENTAL chip + caution copy in row).
  - **`MLXModelEntry` extended** with `speedRating: Int`, `qualityRating: Int`, `expectedLatencySeconds: ClosedRange<Double>`, `isExperimental: Bool`. Hashable synthesis still works (ClosedRange<Double> is Hashable since Swift 4.2).
  - **`MLXProvider.enhance(...)` WARN log line** on `totalElapsed > 10.0`. Observation-only; does not short-circuit. Format matches existing `🦾 enhance:` instrumentation.
  - **`APIKeyManagementView` segregation.** Provider gallery split into CONFIGURED + AVAILABLE partitions via `aiService.connectedProviders` (single source of truth, AIService.swift:289). Configured puts `selectedProvider` first then alphabetical; available alphabetical. Empty-CONFIGURED branch shows a one-line hint chip.
  - **`MLXModelPickerView` re-skin.** Capsule + ultraThinMaterial chip vocabulary. SF Mono uppercase 0.06em tracking. ACTIVE / EXPERIMENTAL / Speed N/10 / Quality N/10 / latency-range / size chips per row. Download progress shown as a chip-style fill bar with `Palette.accent`.
  - **`ProviderCard` re-skin.** Corner radius 16→14, hover-lift removed (per spec §5#8), `StatusPill` adopted from `APIKeyManagementView` (DRY), single-accent tint migration.
  - **`PromptEditorView` + `EnhancementSettingsPanel` + `EnhancementSettingsView`** chrome re-skinned to W1 glass-chip vocabulary (close / + / gear / Save buttons). Editor body forms untouched.
  - **Legacy MLX cache one-time purge migration** (`MLXModelRegistry.purgeLegacyApplicationSupportModelsIfPresent()`). Sentinel-guarded path-shape check (`lastPathComponent == "MLXModels" && path.contains("/Application Support/")`). Returns Bool — failure path skips the `legacyMLXDirPurged` flag flip so partial cleanup retries on next launch.
  - **Stale `mlx_selected_model_id` wipe** for the two dropped repos. Idempotent, runs every launch.

### Reviewer findings + revisions

- [x] **CRITICAL — purge sentinel** (caught by reviewer-w6, fixed in same packet). Helper sat outside the `#if canImport(MLXLLM)` fence and called `applicationSupportModelsRoot()` whose `#else` stub returns `URL(fileURLWithPath: NSHomeDirectory())` = `~/`. In a non-MLX build (CI / SourceKit indexing / future config), `removeItem(at:)` would have wiped the user's home directory. Fixed via path-shape sentinel inside the function body (defense-in-depth — function callable across build flavors).
- [x] **NIT — Bool return + conditional flag flip.** Plan had unconditional flag-set on partial failure (defended as "next launch should not retry"). Lead's dispatch brief overrode: don't set on failure, otherwise partial cleanup persists. Implementation matches brief.
- [x] **NIT — stale-id wipe.** Added alongside the purge to cover users who had a dropped repo selected pre-W6.
- [x] **NIT — PLE-quant caution on e2b notes.** Plan deliberately skipped UI surfacing of the warning (production e4b already affected without complaints), but new fastest-tier deserves a thread-to-pull. e4b notes untouched.
- [x] **NIT — `formatSecs` dead-branch ternary** in `MLXModelPickerView` collapsed to single `String(format: "%.0f", value)`.

### Pre-W6 research

- [x] **Verified `mlx-community/gemma-4-e2b-it-4bit` exists** and is preferable to `gemma-3n-E2B-it-lm-4bit` (planner's original pick). Same `gemma3` model type as the already-shipping e4b → eliminates loadability risk under bundled mlx-swift-lm 3.31.3.
- [x] **PLE-quant warning surfaced** during research. Discussion at https://huggingface.co/mlx-community/gemma-4-e2b-4bit/discussions/1 reports mlx-community 4-bit quants of Gemma 4 E-series produce degraded output because quantization is applied to PLE (Per-Layer Embedding) layers. Affects e2b (new fastest tier) AND existing e4b (production default). Cleanup task is forgiving (50-200 token output) so production impact is bounded; documented in W6 plan Risks/unknowns §1 with three candidate fixes (drop fastest tier, try OptiQ custom quant, escalate to 8-bit).

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **Bundle MLX-quality follow-ups into W6** | Spec §5#6 already covered AI Models + Prompts re-skin; user's items 1–7 (registry curation, ratings UI, segregation, legacy purge) overlapped naturally. One packet, one planning round, one merge. |
| **Relabel gemma-4-26b-a4b experimental rather than hard-drop** | User said "drop or relabel"; relabel is the conservative read. EXPERIMENTAL chip + caution copy give users informed choice. WARN log line at >10s gives ground-truth feedback for future tightening. The 27B dense was hard-dropped because it has no MoE benefit and no path to ≤10s on 32 GB base. |
| **Swap planner's gemma-3n-E2B → gemma-4-e2b before coder dispatch** | Same `gemma3` model type as the already-loaded e4b default eliminates loadability risk. Newer training generation. Smaller effective param count than e4b → faster. |
| **Accept PLE-quant risk for now** | Existing e4b ships with the same risk and no quality complaints over weeks of production use. Cleanup task is forgiving (50-200 token output). Don't preemptively rip out the e4b default; address in follow-up if user reports quality regression on the new e2b fastest tier. |
| **Defense-in-depth path sentinel inside `purgeLegacyApplicationSupportModelsIfPresent()`** (not `#if canImport(MLXLLM)` fence wrap) | Sentinel keeps the function callable across build flavors. If the underlying `applicationSupportModelsRoot()` ever changes, the sentinel still catches wrong-target cases. The "build green covers both branches" pattern (W3 reviewer's lesson) means we can't assume the production build covers all reachable code paths. |
| **Bool return + conditional flag flip on legacy purge** | Plan defended unconditional flag-set; my dispatch brief contradicted. Brief wins because partial cleanup leaves bytes; flag should only stick on full success. Failure path retries next launch — idempotent, sentinel-bounded, log-instrumented. |
| **PLE-quant caution on e2b only, not e4b** | New fastest tier is the new surface; users picking it for the speed should have a thread to pull if cleanup looks wrong. e4b is the established production default with no complaints; touching its copy invites confusion for marginal benefit. |
| **Per-delete cleanup hook deferred** | One-time migration sufficient. swift-huggingface 0.9.0 lands snapshots under `~/Library/Caches/huggingface/hub/`, leaving no path for the legacy dir to reappear. YAGNI. |
| **Single integration build at merge time** | Per CLAUDE.md cadence rule + `feedback_skip_per_packet_builds.md` memory. No `make local` between tasks; one full build at Task 13. |
| **Worktree-driven workflow with teammates** | Same as W1/W2/W3/W4. Coder + reviewer pair within `.worktrees/w6-mlx-quality`; planner on main (no worktree needed for plan-writing). Single coder-reviewer pair across one revision round. |

## Files Changed (committed; 18 commits ahead of origin, none pushed)

```
0aef209 feat(mlx-w6): AI Models + Prompts re-skin + MLX-quality follow-ups
3a711a2 docs(plans): W6 — AI Models + Prompts re-skin + MLX-quality follow-ups
957ab5f docs(handoffs): post-W3 session handoff for next dispatch
0a3f983 fix(prompt): drop inline example sentences from System Default
da8c699 fix(enhancement): MLX prompt routing + model-picker reactivity
34549de feat(failures): W3 — FailureRegistry routing (Path B architecture)
3b6bf33 docs(plans): W3 failure-routing plan (Path B architecture)
7ec3fb5 feat(recorder): W2 — constellation cluster + state grammar
901aa9e docs(plans): W2 cluster + state grammar plan
904cb8b feat(chrome): W4 — single-accent sidebar nav + retire rainbow PRO badge
8605f16 feat(palette): W1 — single-accent migration + GlassChip primitive
a4068bf docs(known-issues): KI-04 model meta-refusal on real input + KI-05 output wrapping  ← later resolved
5c69269 feat(mlx): add gemma-3-1b-qat-4bit "Fastest" tier to curated registry  ← retired in W6
b6e6ba4 fix(prompt): frame System Default prompt as text-cleanup engine
d0b6b4f chore(repo): ignore .worktrees/ for parallel worktree workflow
db14efa docs(redesign): aesthetic-redesign spec, W1 plan, handoff, known issues
96d794d fix(ui): menu-bar icon + enhancement-failure persistence
fbe6cb4 chore(mlx): migrate to mlx-swift-lm 3.31.3 + swift-huggingface 0.9.0
```

## What Didn't Work

- **Planner's first pick `gemma-3n-E2B-it-lm-4bit` for fastest tier** — would have shipped a model whose `gemma3n` model type isn't proven loadable under bundled mlx-swift-lm 3.31.3. Lead caught at plan-review time; revise round swapped to `mlx-community/gemma-4-e2b-it-4bit` (same gemma3 type as e4b default). Saved a coder iteration.
- **Plan's unconditional `legacyMLXDirPurged = true`** — plan defended this but reviewer-w6 flagged it correctly: partial cleanup persists across launches, leaving stale bytes the user thinks were reclaimed. Dispatch brief had said "only flip on success"; coder followed plan; reviewer caught the gap; coder fixed in revise round.
- **Purge function outside `#if canImport(MLXLLM)` fence** — coder followed plan literal which placed the extension at file-scope. Reviewer-w6 caught the foot-gun: the `#else` stub of `applicationSupportModelsRoot()` returns `~/`, and in a non-MLX build the purge would have wiped the user's home directory. Fixed via defense-in-depth sentinel inside the function body in revise round.
- **Reviewer's `xcodebuild test` attempt** — blocked on three layers: (1) MLXHuggingFaceMacros macro trust prompt (per-machine SPM macro fingerprint, requires Xcode UI); (2) Mac Development signing cert (team V6J6A3VWY2 not in keychain); (3) IPC bootstrap on unsigned bundle (XCTest harness can't establish runner connection without a signed bundle). Same blocks affect any teammate. Recommend running tests from Xcode UI on the user's machine; teammate-driven `xcodebuild test` is not viable under current signing setup.
- **Coder's `open ~/Downloads/VoiceInk.app` for sanity launch** errored -600 (LaunchServices rejecting the local-cert-signed bundle for the `open` URL handler). Direct binary launch via `/Users/priyanshu/Downloads/VoiceInk.app/Contents/MacOS/VoiceInk` works. Workaround for any future teammate sanity launches: skip `open`, use direct exec path.

## Current State

- **Build:** green (`make local` → `** BUILD SUCCEEDED **`). App at `~/Downloads/VoiceInk.app`. Pre-existing SPM/codegen warnings (~111) — none new from W6.
- **Tests:** untested in this session (env-blocked per above). `FailureRegistryTests` 5/5 + `PaletteTests` 2/2 + `VoiceInkUITests` 4/4 last passed at end of W3. The W6 changes don't add new tests but also don't break existing tests at compile time (build green covers test compilation).
- **Disk:** 13 GB free (was 18 GB pre-merge — DerivedData growth from `make local`, plus the new `~/Downloads/VoiceInk.app` build). Tight; consider `xcodebuild clean` or wiping `~/Library/Developer/Xcode/DerivedData/VoiceInk-*` between major sessions if disk pressure becomes blocking.
- **Worktrees:** none. Working tree clean.
- **Branches:** just `main`.
- **Teams:** none active (`aesthetic-w6` torn down via `TeamDelete`).
- **Aesthetic redesign packets:**
  - W1 ✅ landed
  - W4 ✅ landed
  - W2 ✅ landed
  - W3 ✅ landed
  - W6 ✅ landed (this session)
  - **W5 (Settings re-skin)** ❌ not started — depends on W1 ✓
  - **W7 (Type + sound polish)** ❌ not started — depends on W1 ✓
- **Known issues** (`docs/known-issues.md`): KI-01 (stale paste-target state on next transcription), KI-02 (Slack auto-paste silent fail), KI-03 (small-model context-awareness — "doc" → "do g"), KI-06 (gemma-3-1b QAT capacity ceiling — model itself dropped from registry in W6, but the underlying capacity-ceiling pattern stays a known fact about small models).

## Uncommitted Changes

Clean working tree. 18 commits ahead of `origin/main`, none pushed. User pushes manually per session pattern.

## Visual verification gaps (require user-machine pass)

Reviewer-w6 listed 9 spot-checks — none performed yet. Recommend the user walk through these on next launch before any of the W6 surfaces are treated as production-tested:

1. **AI Models tab — segregation.** Settings → AI Enhancement → AI Provider Integration. Confirm CONFIGURED N + AVAILABLE M sections render with correct partitions. Tap an AVAILABLE card → it expands; once configured, it should migrate to CONFIGURED on next refresh / app relaunch.
2. **Empty-CONFIGURED state.** With all credentials wiped + no MLX models downloaded, confirm the one-line hint chip ("No providers configured yet…") renders in the CONFIGURED slot and AVAILABLE shows all gallery providers.
3. **MLX picker — 4 entries + chips.** Expand MLX provider card. Confirm exactly 4 rows: gemma-4-e2b, gemma-4-e4b, Qwen3.5-4B, gemma-4-26b-a4b. Each row has Speed N/10 + Quality N/10 + latency-range + size chips. The 26b row shows EXPERIMENTAL chip + caution copy.
4. **Download progress chip.** Tap Download on the e2b entry. Confirm chip-vocabulary progress bar fills `Palette.accent` left-to-right with `%` text overlay; on completion transitions to a Delete button.
5. **WARN log path.** With the 26b model active and a long-ish dictation, run cleanup. Console.app filter `subsystem == "com.prakashjoshipax.voiceink" AND category == "MLXProvider"` should show `🦾 enhance: WARN total=…s exceeds 10s ceiling for model=…` on slow runs.
6. **Legacy purge.** Pre-create `~/Library/Application Support/com.prakashjoshipax.voiceink/MLXModels/test.bin` then launch. Confirm: (a) directory removed; (b) Console shows `🦾 legacy purge: ✅ removed …`; (c) AppStorage `legacyMLXDirPurged` = true (`defaults read com.prakashjoshipax.voiceink legacyMLXDirPurged`); (d) re-launch — Console shows no purge line (skipped via flag).
7. **Prompts re-skin.** Settings → Enhancement Prompts → click + (glass + button). Editor opens. Confirm header xmark is 8pt rounded glass with hairline stroke; footer Save Changes is `Palette.accent` tinted; top + bottom hairlines render as `Palette.hairlineSoft` rects.
8. **Reduce-Motion.** Toggle Accessibility → Display → Reduce Motion ON. Expanding a ProviderCard should be instant; download progress should still be subtle.
9. **VoiceOver chips.** Cmd+F5 → tab through MLX picker rows. VO should read each chip ("Speed 9/10", "EXPERIMENTAL", etc.).

## Next Steps

1. [ ] **User-machine smoke pass on W6** (above 9 items). Treat as P0 before W5/W7 dispatch.
2. [ ] **Dispatch W5 (Settings re-skin).** Spec §5 row W5: "`EnhancementSettingsView.swift`, `EnhancementSettingsPanel.swift`, `HotkeySettings*`, `AudioInputSettings*`, etc. Existing layout preserved; cards/chips/toggles inherit new tokens; visual diff against old screens captured." Note: W6 already touched `EnhancementSettingsView` and `EnhancementSettingsPanel` chrome — W5's scope on those two narrows to the surfaces W6 didn't touch (Form bodies, toggle / picker rows, section headers). Audit before planning.
3. [ ] **Dispatch W7 (type + sound polish).** Spec §5 row W7: "Find/replace `.rounded` → system in body type; verify SF Mono on state labels; sound cue volume re-tune to match new lighter aesthetic." Cohesion pass; can run in parallel with W5 (file overlap is minimal — W7 is mostly grep-and-replace + asset re-tuning).
4. [ ] **Resolve test infrastructure block** — `MLXHuggingFaceMacros` trust prompt + Mac Development cert + IPC bootstrap. Either fix the local signing setup (add team V6J6A3VWY2 cert to keychain or set `DEVELOPMENT_TEAM=` to user's team) or accept "tests run via Xcode UI only" as the durable pattern. Decision belongs to the user, not a teammate.
5. [ ] **PLE-quant follow-up if quality regression reported** on the new gemma-4-e2b fastest tier. Three candidate fixes flagged in W6 plan Risks/unknowns §1: (a) drop fastest tier entirely, ship 3-entry registry; (b) test `mlx-community/gemma-4-e2b-it-OptiQ-4bit` (custom quant); (c) escalate to 8-bit variants when bundle size budget allows.
6. [ ] **Refine Speed/Quality ratings post-hardware-verification.** All current numbers extrapolated from M4 Pro 24 GB benchmarks (kartit.net) — none from M-series base 32 GB ground-truth. Once user runs dictation cycles on each model, the new WARN log line gives real data to tighten the ratings.
7. [ ] **Disk pressure** at 13 GB free. Not blocking yet; surface again if user reports MLX downloads failing on `preflightDiskSpace`. `xcodebuild clean` or wiping DerivedData would reclaim several GB.

### Recommended dispatch shape for next session

W5 + W7 in parallel is viable. Lead spawns two teams (or one team with two coder-reviewer pairs):

- **W5 packet** — single planner-coder-reviewer cycle. Dependencies: W1 ✓, W6 ✓ (for the `EnhancementSettingsView` / `EnhancementSettingsPanel` audit). Worktree at `.worktrees/w5-settings-reskin`.
- **W7 packet** — same shape. Dependencies: W1 ✓. Worktree at `.worktrees/w7-type-sound-polish`. File overlap with W5 is small (W7 is grep-and-replace + asset re-tuning across many files).

Sequential is also fine if context permits. Per `feedback_skip_per_packet_builds.md` memory: single integration build per packet at merge time, not per-coder/per-reviewer.

## Context the Next Session Needs

- **CLAUDE.md is loaded automatically.** Same rules as W1–W6: spawn TEAMMATES via `TeamCreate` + `Agent({team_name, name})`; skip per-packet builds; never commit without explicit user approval; never `git push --force`.
- **Worktree convention:** `.worktrees/<branch-name>/` (gitignored). Per `superpowers:using-git-worktrees`. `git worktree add .worktrees/<name> -b <name> main`.
- **Build:** `make local`. App lands at `~/Downloads/VoiceInk.app`. `Makefile:73` has `-skipMacroValidation` flag (required for MLXHuggingFaceMacros compiler plugin — don't disturb).
- **Code-signing:** local self-signed cert `voiceink-fork-local`. Falls back to ad-hoc if absent. Tests via `xcodebuild test` need Mac Development cert (team V6J6A3VWY2) + macros-trust prompt acceptance — both env blocks, both require user-machine intervention.
- **Xcode 16 PBXFileSystemSynchronizedRootGroup:** files dropped under `VoiceInk/` and `VoiceInkTests/` are auto-included; **no pbxproj edits needed** for new files. Confirmed in W1/W2/W3/W4/W6.
- **Reviewer rigor expectations:** the W6 reviewer caught a critical foot-gun (purge sentinel) that build-green couldn't see. Pattern continues to work — trust it. Reviewer + coder pair stays for revise rounds within one packet.
- **Teammate naming convention:** ticket-scoped IDs (e.g. `coder-w5`, `reviewer-w5`). Fresh teammate per task per CLAUDE.md "Teammate context lifecycle" rules.
- **Spec is source-of-truth:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens), §5 row W5 + row W7 + §5#8 (`GlassCard` hover-lift removed).
- **Plan files committed alongside impl:** match the W3/W6 pattern (two commits per packet — `docs(plans): …` + `feat(…): …`).
- **PLE-quant warning is documented in W6 plan Risks/unknowns §1.** If the user reports cleanup quality regression on the new e2b fastest tier, that's the canonical thread to pull.
- **18 commits ahead of `origin/main`, none pushed.** User pushes manually. Don't push without explicit instruction.

---

**Tip for the next session:** the user has been doing real-app testing throughout the entire redesign series and has surfaced multiple production bugs (KI-04/05/06, the disk-bloat issue, the gemma-3-1b regurgitation, the gemma-4-26b-a4b stall). The next session should keep the same testing-driven loop — don't claim W5 or W7 done on build-green alone; verify with real dictation cycles + visual smoke before declaring victory.

Handoff saved: `docs/superpowers/handoffs/HANDOFF_aesthetic_redesign_post_W6_2026-04-28.md`

Start next session with:
> Read `docs/superpowers/handoffs/HANDOFF_aesthetic_redesign_post_W6_2026-04-28.md` and continue from where the last session left off.
