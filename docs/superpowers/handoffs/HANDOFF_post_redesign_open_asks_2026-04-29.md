# Handoff: post-redesign open asks + MLX rewriting-model research

**Date:** 2026-04-29
**Branch:** `main`
**Status:** redesign series + cleanups all landed; three open asks for the next session — two design refinements (adaptive glass, MLX picker chip overflow) + one research task (replace Gemma with a faster open-source MLX rewriting model)

## Goal

Continue from a clean post-redesign state. The aesthetic redesign series (W1-W7) and the post-W7 cleanups (KeyboardShortcutView retirement, StreamingCaretTranscript retirement, full CardBackground retirement across AudioInput + Dictionary + ModelManagementView) are all merged. User has tested the live build and:

1. **Likes the design overall.** The strip-out + redesign reads well.
2. **Wants adaptive glass app-wide.** Recorder cluster + chips already adaptive via `GlassAppearance` + `HaloMaterial`; main ContentView background, detail panes, sidebar are still solid (`controlBackgroundColor` + default NavigationSplitView chrome). Wants the same translucent treatment to propagate.
3. **Flagged MLX model picker chip overflow.** Inside the AI Models page, when a user expands the MLX provider card, the model rows show ACTIVE / EXPERIMENTAL / Speed N/10 / Quality N/10 / latency / size chips — too many for the constrained ProviderCard width. The Quality chip gets clipped / hidden.
4. **Reports Gemma is too slow.** Both `gemma-4-e2b-it-4bit` (fastest tier) and `gemma-4-e4b-it-4bit` (default mid) feel slow on real-world dictation. Wants research to identify a faster open-source MLX-supported alternative for text-rewriting / cleanup tasks. Replace Gemma in the curated registry.

## Work Completed (this session — 2026-04-29 dispatch)

- [x] **Build for user testing** (`970b1ad` HEAD). Two `make local` invocations during the session — the post-W7 series build + a refresh after the cleanups landed. App at `~/Downloads/VoiceInk.app` reflects all 28 commits.
- [x] **CardBackground retirement final pass** (`970b1ad`). 2 files / +10 / -93. Migrated 4 ModelManagementView CardBackground call sites (L116, L142, L161, L230) to `.modifier(GlassChip(cornerRadius: ..., paddingH: 0, paddingV: 0))` + `Palette.accent.opacity(0.5)` 1.5pt stroke for selected states. Deleted `VoiceInk/Views/Common/CardBackground.swift` (87 LOC) — both the `CardBackground` struct and its sibling `StyleConstants` retired together. `MetricCardBackground` (different type in `PerformanceAnalysisView.swift`) is intentionally untouched (out of scope; metrics-dashboard surface).
- [x] **All teammates shut down + TeamDelete.** Working tree clean, no orphan teams.

Earlier this session (2026-04-28 → 2026-04-29 boundary):
- [x] **Three small queued cleanups** (`ee9e774`). KeyboardShortcutView orphan retired (-248 LOC); StreamingCaretTranscript + BlinkingCaret retired (-68 LOC); CardBackground migration on AudioInputSettingsView (5 sites) + DictionarySettingsView (2 sites). 4 files / +21 / -324.

## Three Open Asks — Sign-off Needed in the Next Session

### Ask 1 — Adaptive glass app-wide

**User statement:** "We were thinking of doing glass adaptive glass in the app as well. We should do that."

**Lead's recommendation (sent in prior session — needs user sign-off):**

Audit + apply adaptive glass to **3 top-level surfaces** that are currently solid:

1. **Main ContentView background.** Currently `Color(.controlBackgroundColor)` — flat. Switch to `HaloMaterial(shape: ..., phase: .hidden, appearance: detector.current)` or equivalent that adapts per `GlassAppearanceDetector.shared.current`.
2. **Detail-pane wrappers.** Each sidebar destination (Dashboard, AI Models, History, Settings, etc.) currently lays content over a solid background. Wrap each detail surface root in adaptive glass; cards inside already inherit via `.glassChip()` / `.glassPanel()` / `GlassCard` so this just affects the gap area.
3. **Sidebar chrome.** Currently NavigationSplitView default chrome + `VisualEffectView` (NSVisualEffectView in `ContentView.swift:39`). The visual effect view exists but might not adapt to wallpaper luminance the way the recorder cluster does. Verify behavior; align with `GlassAppearanceDetector` if it doesn't.

**Tradeoff lead flagged:** invasive on detail panes — content was designed against opaque backgrounds; some inner cards may need re-tuning to read well over translucent backdrop. Visual smoke pass post-merge essential.

**Open question for next session:** is the 3-surface scope right, or does the user want to redirect (e.g. "actually just the main window, leave the detail panes alone" / "also the menu bar dropdown" / "redo the recorder constellation glass tuning to match this pass")?

**Where to start:** read `VoiceInk/Views/Common/GlassAppearance.swift` + `GlassAppearanceDetector.swift` + `HaloMaterial.swift` to understand the existing adaptive vocabulary. Then audit `ContentView.swift` + each detail pane root for current background colors. Plan a single packet (planner-coder-reviewer) once scope is locked.

### Ask 2 — MLX model picker chip overflow

**User statement:** "the cards for the models available are very small they don't show the score of quality because the horizontal space is very less"

**Lead's recommendation (sent in prior session — needs user sign-off):**

The MLX model row's chip strip (ACTIVE / EXPERIMENTAL / Speed N/10 / Quality N/10 / latency-range / size) is a single horizontal HStack inside a width-constrained ProviderCard. The Quality chip gets clipped / hidden on narrow widths.

**Two solutions on the table:**

- **(a) Wrap chips to a second row via FlowLayout.** Use the existing `VoiceInk/Views/Components/FlowLayout.swift` primitive. Card height grows ~20pt per row but all info preserved.
- **(b) Collapse Speed + Quality into a single combined chip** ("9/5" or "S9 · Q5"). Saves horizontal space, harder to scan visually.

**Lead's preference:** option (a) — FlowLayout. Preserves the W6 vocabulary; combined chip loses the "/10" denominator that anchors the rating in users' minds.

**Where to start:** `VoiceInk/Views/AI Models/MLXModelPickerView.swift` — the row body composing the chip HStack. Wrap with `FlowLayout` (verify the primitive exists at the listed path; if it doesn't, audit for the nearest existing wrap-layout helper).

### Ask 3 — Replace Gemma — research fast open-source MLX rewriting models

**User statement:** "Make sure that we do research on models that are good with rewriting stuff like these and are very fast and supported on MLX architecture. It should be open source, of course. We would want to replace Gemma because it is very slow right now."

**Context for the research:**

- **Use case:** text-rewriting / cleanup of dictation transcripts. Typical input: 50-300 tokens raw transcript (ASR output, possibly with disfluencies / fillers). Typical output: 50-200 token cleaned text. Plus instruction-following for prompt-based enhancement (e.g. "rewrite in formal tone", "fix punctuation only").
- **Target hardware:** Apple Silicon M-series base 32 GB. M2 / M3 / M4 base. NOT M-Pro / M-Max / M-Ultra.
- **Latency targets:** ≤5s ideal, ≤10s acceptable, >10s reject. Current Gemma e2b/e4b reportedly miss the ≤5s ideal.
- **Quality floor:** at least match gemma-4-e4b-it-4bit on instruction-following for cleanup tasks (50-200 token output). Below that = useless for the task.
- **Required: MLX architecture support.** Must be loadable via bundled `mlx-swift-lm 3.31.3` (current bundled version) OR upgradable to a newer mlx-swift-lm. Repo presence on `huggingface.co/mlx-community/*` is a strong signal.
- **Required: open source.** No API/proprietary models (no Claude, GPT-4, Gemini, etc.). MIT / Apache 2.0 / similar permissive license.

**Models worth researching (non-exhaustive list — research should validate + find more):**

- **Qwen2.5 / Qwen3 small variants** — Qwen2.5-1.5B-Instruct, Qwen3-0.6B / 1.7B / 4B (the 4B might be too slow but worth confirming).
- **Phi-3.5-mini-instruct** (~3.8B) — Microsoft, instruction-tuned, generally fast on M-series.
- **Llama-3.2 small variants** — Llama-3.2-1B-Instruct, Llama-3.2-3B-Instruct. Meta, very fast 1B option.
- **TinyLlama-1.1B / TinyLlama 2** — small footprint.
- **SmolLM2-1.7B-Instruct** (HuggingFace) — small, reportedly competitive.
- **Granite 3 small variants** (IBM) — granite-3-2b-instruct etc.
- **DeepSeek-R1-Distill-Qwen-1.5B** — distilled small models from the DeepSeek-R1 release.
- **StableLM-2-1.6B-Zephyr** — Stability AI.

**What to find for each candidate:**

1. **Repo path on `mlx-community`** (e.g. `mlx-community/Qwen3-1.7B-Instruct-4bit`). Verify the repo exists.
2. **Approximate size GB** at 4-bit quant.
3. **Tokens/sec on M-series base 32 GB** (cite source; benchmarks from M-Pro / Ultra are NOT a substitute — extrapolation has been wrong before, see W6 history).
4. **Quality on instruction-following / text-rewriting benchmarks** (MT-Bench, AlpacaEval, IFEval, or custom task evals). Cite sources.
5. **Known quant pitfalls** — Gemma-4 mlx-community quants apply quantization to PLE layers and produce degraded output (see `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` Risks/unknowns §1). Identify if any candidate has a similar known issue.
6. **License** — confirm permissive open-source.

**Output format:** the research should produce a comparison table + recommendation. Plan should land in a doc like `docs/superpowers/research/2026-04-29-mlx-rewriting-models.md` (new directory `research/` is fine — create alongside existing `plans/` + `handoffs/` + `specs/`).

**After research lands:** plan a registry-update packet that swaps the two Gemma curated entries for the recommended replacements. Probably:
- New fastest tier (replace `gemma-4-e2b-it-4bit`)
- New default mid tier (replace `gemma-4-e4b-it-4bit`)
- Keep `Qwen3.5-4B-MLX-4bit` if research confirms still competitive (or replace if a clearly-better Qwen3 variant exists)
- Decide on `gemma-4-26b-a4b-it-4bit` experimental — keep, replace, or hard-drop based on whether any 26B-class alternative meets the latency target

**Where to start the research:** WebSearch / WebFetch first; consult `huggingface.co/mlx-community` collection pages; cross-check benchmarks against the cite-checked sources used in the W6 plan (kartit.net Gemma 4 benchmark, codersera comparison, sudoall.com).

**Caveat — same as W6:** all public benchmarks tend to be on M-Pro 24 GB or M-Ultra. For M-series base 32 GB, the WARN log (already wired in `MLXProvider.enhance(...)` at the >10s threshold) gives ground-truth feedback after the swap; treat researched numbers as conservative estimates.

## Key Decisions From This Session

| Decision | Rationale |
|----------|-----------|
| **Defer adaptive-glass scope decision to next session** | Lead recommended a 3-surface target (main ContentView background + detail-pane wrappers + sidebar chrome alignment) but user hasn't signed off. Per CLAUDE.md exploratory-question rule: present + ask, don't implement. |
| **Defer MLX chip-overflow solution to next session** | Two reasonable options (FlowLayout multi-row vs combined chip); lead leans (a) FlowLayout but user should decide. |
| **Promote model-replacement research to its own dedicated task** | User explicitly asks for it; it gates a registry-update packet that affects production model downloads. Research output becomes the spec for the swap. |
| **Worktree-bash CWD foot-gun is recurring** | Hit it 3 times this session (W5 merge, W7 merge, both cleanup merges). Workaround documented in post-W7 handoff: never run `git worktree remove` while bash CWD is inside that worktree. Always `cd <main-worktree>` first. Future sessions: same. |

## Files Changed (committed; 28 commits ahead of origin, none pushed)

```
970b1ad chore(cleanups): retire CardBackground + StyleConstants — ModelManagementView migration
ee9e774 chore(cleanups): retire KeyboardShortcutView + StreamingCaretTranscript + CardBackground migration on AudioInput + Dictionary
e30ed77 docs(handoffs): complete aesthetic redesign series + monetization strip
260b733 feat(polish): W7 — type + chip vocab + sound cue volume re-tune
c15fa1b docs(plans): W7 — type + sound polish plan
87a08ca feat(settings): W5 — Settings re-skin + GlassCard hover-lift removal
156843d docs(plans): W5 — Settings re-skin plan
de41ed7 chore(cleanup): drop orphan onboarding helper + stale ConstellationCard doc refs
972896a chore(strip): remove license + onboarding + legacy constellation surfaces
b992870 docs(handoffs): post-W6 session handoff for next dispatch
0aef209 feat(mlx-w6): AI Models + Prompts re-skin + MLX-quality follow-ups
3a711a2 docs(plans): W6 — AI Models + Prompts re-skin + MLX-quality follow-ups
... (older — see HANDOFF_aesthetic_redesign_complete_2026-04-28.md for the W1-W4 trail)
```

## What Didn't Work

- **Worktree-bash CWD chains** — recurring foot-gun. Bash `cd` into a worktree, then `git worktree remove .worktrees/X` while still inside that path = `fatal: Unable to read current working directory: No such file or directory`. Workaround: always `cd <main-repo>` BEFORE the worktree remove + branch delete steps. Hit 3 times this session.
- **`xcodebuild test` env-blocked all session** — same triple block (`MLXHuggingFaceMacros` macros-trust prompt + Mac Development cert team V6J6A3VWY2 not in keychain + IPC bootstrap on unsigned bundle). Carried over from W5 + W6 + W7 cycles. Resolution requires user-machine intervention (Xcode UI macros-trust accept + signing config) — NOT a teammate-fixable issue.
- **Gemma performance on real-world dictation** — both gemma-4-e2b-it-4bit (fastest tier) + gemma-4-e4b-it-4bit (default mid) reportedly slow per user. The W6 ratings (Speed 9 / Speed 7 respectively) were extrapolations from M4 Pro 24 GB benchmarks; M-series base 32 GB reality is worse. Drives the Ask 3 research task.

## Current State

- **Build:** green (`make local` → `** BUILD SUCCEEDED **`). App at `~/Downloads/VoiceInk.app`.
- **Tests:** untested in this session (env-blocked). Last green: `FailureRegistryTests` 5/5 + `PaletteTests` 2/2 + `VoiceInkUITests` 4/4 at end of W3.
- **Disk:** 13 GB free or less (multiple `make local` builds since W7; might be lower).
- **Worktrees:** none.
- **Branches:** just `main`.
- **Teams:** none active. All this session's teams torn down.
- **Aesthetic redesign:** ✅ all packets W1-W7 landed.
- **Monetization:** ✅ stripped (license + Polar + Obfuscator + onboarding + legacy constellation).
- **Cleanups:** ✅ KeyboardShortcutView orphan + StreamingCaretTranscript dead code + full CardBackground retirement.

## Uncommitted Changes

Clean working tree. 28 commits ahead of `origin/main`, none pushed.

## Next Steps (priority order)

1. [ ] **Sign off on Adaptive glass scope** (Ask 1). User picks: 3-surface lead recommendation OR redirect.
2. [ ] **Sign off on MLX chip-overflow solution** (Ask 2). User picks: (a) FlowLayout multi-row OR (b) combined Speed/Quality chip OR (c) something else.
3. [ ] **Run the MLX rewriting-model research** (Ask 3). Likely a dedicated research subagent (Explore + WebSearch + WebFetch) producing `docs/superpowers/research/2026-04-29-mlx-rewriting-models.md` or similar. Output gates the registry-swap packet.
4. [ ] **After research lands → plan + execute the registry-swap packet.** Replace Gemma curated entries with the recommended alternatives. Includes any necessary `mlx-swift-lm` upgrade if the chosen models need a newer framework version (the bundled 3.31.3 was specifically picked for the gemma3 model type, see `fbe6cb4`).
5. [ ] **After Asks 1 + 2 sign-off → plan + execute** as either two separate packets (sequential) or one combined packet (in parallel — but adaptive glass affects more files).
6. [ ] **User-machine smoke pass on W5 + W6 + W7 cumulative** (24 items in `HANDOFF_aesthetic_redesign_complete_2026-04-28.md`) — pre-existing TODO; user has tested some surfaces ("looks good") but hasn't gone through the full checklist.
7. [ ] **Test infrastructure unblock** — Xcode UI macros-trust accept + signing config fix. User-side, separate session.

### Recommended dispatch shape for the next session

**Phase 1: Research first.** Spawn an Explore subagent (or general-purpose with Web tools) to do the model research. Output goes to `docs/superpowers/research/`. ~30-60 min depending on depth.

**Phase 2: Concurrent UX work.** Once research is in flight, dispatch the adaptive-glass + chip-overflow packets in parallel teammates (per CLAUDE.md `superpowers:dispatching-parallel-agents` skill). Both have minimal file overlap (adaptive glass touches background materials; chip overflow touches one MLXModelPickerView function). Single integration build per packet at merge time per `feedback_skip_per_packet_builds.md`.

**Phase 3: Registry swap.** Once research + Asks 1 + 2 land, plan + execute the model-registry update packet. This is the larger one — depends on what models the research recommends + whether mlx-swift-lm needs upgrading.

## Context the Next Session Needs

- **CLAUDE.md is loaded automatically.** Same rules: spawn TEAMMATES via `TeamCreate` + `Agent({team_name, name})`; skip per-packet builds (single integration build at merge time); never commit without explicit user approval; never `git push --force`.
- **Worktree convention:** `.worktrees/<branch-name>/` (gitignored). Per `superpowers:using-git-worktrees`. `git worktree add .worktrees/<name> -b <name> main`.
- **Worktree-bash CWD foot-gun** (recurring this session): never run `git worktree remove .worktrees/X` while the bash shell CWD is inside that worktree. Always `cd <main-repo>` before remove + branch-delete steps.
- **Build:** `make local`. App lands at `~/Downloads/VoiceInk.app`. `Makefile:73` `-skipMacroValidation` flag (required for MLXHuggingFaceMacros — don't disturb).
- **Code-signing:** local self-signed `voiceink-fork-local` cert. `xcodebuild test` env-blocked (macros-trust + Mac Development cert + IPC bootstrap) — needs user-machine fix.
- **Xcode 16 PBXFileSystemSynchronizedRootGroup:** files dropped under `VoiceInk/` and `VoiceInkTests/` auto-included; no pbxproj edits needed for new files.
- **Spec is source-of-truth:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens). Adaptive glass work would amend §3.2 (cluster glass) + introduce a new §1.x sub-token if needed. Consider extending the spec rather than ad-hoc design.
- **Strip-out memory:** `~/.claude/projects/-Users-priyanshu-Desktop-Projects-pu-voiceink-fork/memory/project_strip_monetization.md` — future sessions adding features should NOT introduce license / trial / Polar gating.
- **PLE-quant warning** documented in `W6-mlx-quality-and-segregation.md` Risks/unknowns §1. Affects mlx-community gemma-4 4-bit quants. The model-replacement research should explicitly check if candidate models have similar known quant pitfalls.
- **Plan files committed alongside impl:** match the W3/W5/W6/W7 pattern (two commits per packet — `docs(plans): …` + `feat(…): …`).
- **28 commits ahead of `origin/main`, none pushed.** User pushes manually.

### Lead's pending questions for the user

If the new session opens with these unresolved, ask explicitly:

1. **Adaptive glass scope** — confirm 3-surface target (main ContentView background + detail panes + sidebar chrome) OR redirect. Should the menu bar dropdown / recorder panels also get re-tuned, or are those already correct?
2. **MLX chip overflow** — FlowLayout multi-row OR combined chip OR ???
3. **Model research depth** — fixed budget (e.g. 30 min cap) OR thorough (run as long as needed)? Either is fine; lead defaulted to "research subagent owns the depth".
4. **Registry-swap risk tolerance** — willing to upgrade `mlx-swift-lm` to a newer version if the chosen models need it? Or stay on the bundled 3.31.3 (which constrains the candidate pool to anything that loads under it)?
5. **Hardware-truth before merge** — willing to download + test each candidate model on real hardware before the registry swap lands? Or is "build green + extrapolated benchmarks" sufficient and the WARN log catches outliers post-merge?

---

**Tip for the next session:** the user's testing-driven loop has been the most reliable signal-detector this entire redesign. Don't claim Ask 1 / Ask 2 / Ask 3 done without a real-machine validation pass. The Gemma slowdown the user reported is exactly the kind of finding that benchmark tables miss — trust the user's hardware feedback over any cited number.

Handoff saved: `docs/superpowers/handoffs/HANDOFF_post_redesign_open_asks_2026-04-29.md`

Start next session with:
> Read `docs/superpowers/handoffs/HANDOFF_post_redesign_open_asks_2026-04-29.md` and continue from where the last session left off.
