# Handoff: aesthetic redesign — post-W3, MLX quality follow-ups + W5/W6/W7 backlog

**Date:** 2026-04-28
**Branch:** `main`
**Status:** ready-for-execution (4 of 7 redesign packets landed; user-driven follow-ups queued for next session)

## Goal

Continue the VoiceInk aesthetic redesign. Immediate priority is the user's MLX-quality + AI-Enhancement-page follow-up batch, which folds naturally into **W6 (AI Models + Prompts re-skin)** per spec §5#6. After that, W5 (Settings re-skin) and W7 (type + sound polish) remain. The user wants this dispatched via teammate-driven workflow with worktrees, parallel where dependencies allow.

## Work Completed (this session)

### Redesign packets

- [x] **W1 — Token foundation** (`8605f16`). 29 files, +315/-157. Single-tangerine accent (#FF5B3A) + GlassChip / GlassPanel primitives + retired rainbow Palette tokens. PaletteTests added (Swift Testing).
- [x] **W4 — Main window chrome** (`904cb8b`). 2 files, +7/-6. PRO badge → accent, sidebar `.tint(.accent)` for single-accent navigation, cornerRadius 4 → 10.
- [x] **W2 — Cluster + state grammar** (`7ec3fb5`). 13 files, +1035/-786 (net 711-line reduction). Constellation refactor: `ConstellationCluster` orchestrator + `ChipPanel` layout + `ClusterChips` factories + `ClusterMotion` + new `ClusterPhase` enum. `ConstellationContainer` collapsed to a 15-line shim. Retired `CursorProximityMonitor` + `PulseRibbon`; legacy-marked `WhisperLine` / Card / Chip / Orb (kept for `CinematicWalkthrough` onboarding, deferred per spec §5).
- [x] **W3 — FailureRegistry routing (Path B architecture)** (`34549de`). 15 files, +467/-152. Engine no longer holds `.failed` state at all; emits `FailureEvent`s via `failurePublisher: PassthroughSubject`. New `FailureRegistry` (`VoiceInk/Services/FailureRegistry.swift`) is the single source of truth for unresolved failures. Cluster + menubar dot subscribe and pick their own visualization lifetime. Settings UI picker (3s / 6s / Until-dismissed → `Double.infinity` sentinel). Auto-ack on Settings open (`.navigateToDestination` listener) + retry success (engine `runPipeline` clean-tail clearAll guarded by `failurePublishedDuringRun` flag).

### Post-W3 fixes

- [x] **MLX prompt routing fix** (`da8c699`). Two real runtime bugs caught during local testing:
  - System Default prompt referenced `<TRANSCRIPT>` literally but `AIEnhancementService.swift:250-254` deliberately passes raw transcript (no XML wrapper) to MLX/Foundation Models providers. Mismatch caused KI-04 (meta-refusal: "I cannot fulfill this request because no transcript was provided") and KI-05 (XML wrapping) and pure hallucination (random API/async paragraph). Fix: rewrote prompt provider-agnostic — replaced every `<TRANSCRIPT>` with "the dictation"; added explicit no-wrapping / no-preamble / no-empty-output rules.
  - `aiService.currentModel` for `.mlx` returned stale `selectedModels[.mlx]` because picker only writes `mlx_selected_model_id` AppStorage and never goes through `selectModel(_:)`. Cluster's MODEL chip + ProviderCard showed wrong model after switch. Fix: `currentModel` for `.mlx` reads `mlx_selected_model_id` directly. New `notifyMLXSelectionChanged()` method on `AIService` triggers `objectWillChange.send()` since AppStorage doesn't auto-publish through `ObservableObject`. Wired at all 4 picker sites (Use button, first-downloaded auto-activate, post-download auto-select, delete-clears).

- [x] **Drop inline example sentences from System Default prompt** (`0a3f983`). User reported: dictating "this is a test" returned "The meeting is on Wednesday." — that's the literal right-hand side of the prompt's backtracking-correction example. gemma-3-1b QAT regurgitates inline example output verbatim. Fix: stripped the demonstrative example sentence from the backtracking-correction bullet + tightened parenthetical examples in smart-formatting / list-detection bullets. Rules intact, just no demonstrable sentences for small models to grab onto.

### Disk + ops

- [x] **Removed orphaned legacy MLX cache** at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/MLXModels/` (~9.8 GB). Held duplicate `gemma-4-e4b-it-4bit` from the mlx-swift 2.x era. Free disk: 7.9 GB → 18 GB. User can now download larger models (was blocked on 15 GB downloads by `preflightDiskSpace` correctly throwing).

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| **Path B architecture for failure routing** (engine fires-and-forgets, FailureRegistry remembers, each visualization picks lifetime) | Spec §3 wants menubar dot persistent until ack; spec §4 wants cluster dwell 3s/6s/Until-dismissed. One engine timer can't satisfy both. Engine refactor removes UX timing leak; future error categorization, per-failure retry, history pane all live cleanly in registry. |
| **`Double.infinity` AppStorage sentinel for "Until-dismissed"** | Single key (`failedDwellSeconds`) instead of dual key + enum string. Cluster's `failedTask` gates auto-ack on `dwell.isFinite`. |
| **Engine takes `FailureRegistry` init param for success-tail `clearAll()`** (not for publishing — registry subscribes to `failurePublisher` externally) | Pure external would require additional notification infrastructure for one call. Engine knowing about registry for success-ack is acceptable; publishing stays decoupled. |
| **`RecordingState.failed` REMOVED entirely** | Failure is no longer a state, it's an event. Removing simplifies pattern matching; planner-w3's grep audit caught 4 consumers I missed. `ClusterPhase.failed` itself retained — that's the cluster's internal phase, sourced from registry. |
| **Refactor `ConstellationContainer` in-place** (not a new orchestrator file) | All 3 `RecorderStylePicker` entries (notch/mini/constellation) collapse to `ConstellationContainer` via `HaloShape.Mode`; refactoring once gives all three styles for free. Constructor signature preserved so `MiniWindowManager` / `NotchWindowManager` need zero edits. |
| **Drop inline example sentences from System Default prompt** | Small models (gemma-3-1b QAT) regurgitate the example output verbatim. Tradeoff: KI-03 (small models lacking context-awareness) might mildly regress on edge cases like "doc → document" if the model becomes too conservative. Acceptable — regurgitation was severe (literal unrelated content), conservative cleanup is mild. If KI-03 returns, reintroduce examples in a clearly-marked few-shot section, not inline. |
| **Pre-existing spec-ref comments stay** (e.g. `ClusterPhase.swift:7`, `GlassChip.swift:8`, `MenuBarIconRenderer.swift:8`) | Per CLAUDE.md "no PR-reference comments" — but spec section pointers are durable (point to a checked-in source-of-truth doc). Different from packet identifiers like "W3 / Path B" which fade; those got scrubbed during W3. |
| **Worktree-driven workflow with teammates** | Per CLAUDE.md teammate rules. Each packet got planner-coder-reviewer cycles in `.worktrees/<branch>` with `TeamCreate` + `Agent` calls. Single integration build per packet at merge time (per `feedback_skip_per_packet_builds.md` memory). |

## Files Changed (committed; 15 commits ahead of origin, none pushed)

```
0a3f983 fix(prompt): drop inline example sentences from System Default
da8c699 fix(enhancement): MLX prompt routing + model-picker reactivity
34549de feat(failures): W3 — FailureRegistry routing (Path B architecture)
3b6bf33 docs(plans): W3 failure-routing plan (Path B architecture)
7ec3fb5 feat(recorder): W2 — constellation cluster + state grammar
901aa9e docs(plans): W2 cluster + state grammar plan
904cb8b feat(chrome): W4 — single-accent sidebar nav + retire rainbow PRO badge
8605f16 feat(palette): W1 — single-accent migration + GlassChip primitive
a4068bf docs(known-issues): KI-04 model meta-refusal on real input + KI-05 output wrapping  ← KI-04/05 later resolved
5c69269 feat(mlx): add gemma-3-1b-qat-4bit "Fastest" tier to curated registry  ← user reports 1b is "useless", scheduled for removal
b6e6ba4 fix(prompt): frame System Default prompt as text-cleanup engine
d0b6b4f chore(repo): ignore .worktrees/ for parallel worktree workflow
db14efa docs(redesign): aesthetic-redesign spec, W1 plan, handoff, known issues
96d794d fix(ui): menu-bar icon + enhancement-failure persistence
fbe6cb4 chore(mlx): migrate to mlx-swift-lm 3.31.3 + swift-huggingface 0.9.0
```

## What Didn't Work

- **Adding `<TRANSCRIPT>` placeholder references to system prompt** (`b6e6ba4`) — broke MLX path because `AIEnhancementService.swift:250-254` deliberately passes raw transcript (no wrapper) to MLX/Foundation Models providers. The system prompt referenced a placeholder name that didn't exist in the user message → small models confused → KI-04 / KI-05 / hallucination. Resolved in `da8c699` via provider-agnostic prompt rewrite.
- **Inline example sentence in backtracking-correction bullet** (`The meeting is on Tuesday, sorry not that, actually Wednesday → The meeting is on Wednesday.`) — gemma-3-1b QAT regurgitated the right-hand side verbatim regardless of user input. Resolved in `0a3f983` via example removal.
- **`gemma-3-1b-it-qat-4bit` as "Fastest" tier registry default** (added in `5c69269`) — user testing confirms it's too low-quality even with corrected prompt. Should be REMOVED next session per user.
- **Engine 1.4s `failedDwellSeconds` baked into `VoiceInkEngine`** — designed for the retired red-shake-amber-fade animation that no longer exists. Fossil. Removed in W3 (`34549de`) via Path B refactor.
- **`scheduleFailedDwell` polling loop in `RecorderUIManager.dismissMiniRecorder`** — bounded panel teardown by 1.4s engine dwell. Removed in W3; teardown now unconditional.
- **Plan-vs-reality on WhisperLine retirement** — W2 plan listed it as "Retired" claiming "sole consumer was ConstellationContainer," but coder-w2's Task 0 sweep caught a second consumer at `Onboarding/CinematicWalkthrough.swift:186`. Reclassified to "Legacy-kept" mid-execution.
- **Reviewer-w3 caught two runtime bugs build-green couldn't see**:
  - `runPipeline` tail `clearAll()` ran unconditionally → wiped registry one frame after publish. Fixed via `failurePublishedDuringRun` instance flag.
  - Cluster's `@EnvironmentObject FailureRegistry` not injected at `MiniWindowManager` / `NotchWindowManager` (NSHostingController-rooted panels don't inherit env from `WindowGroup` / `MenuBarExtra`). Would have crashed on first ⌘⌥V. Fixed by adding registry init param to both panel managers + plumbing via `RecorderUIManager.showRecorderPanel`.

## Current State

- **Build:** green (`make local` → `** BUILD SUCCEEDED **`). App at `~/Downloads/VoiceInk.app`. Two pre-existing warnings (mlx-swift_Cmlx bundle creator, Info.plist in Copy Bundle Resources) — benign, not introduced by this work.
- **Tests:** `FailureRegistryTests` 5/5 pass (Swift Testing). `PaletteTests` 2/2 pass. `VoiceInkUITests` 4/4 pass (after one-time Touch ID grant for the test bundle's UI Automation entitlement).
- **Disk:** 18 GB free (legacy MLXModels gone). `~/.cache/huggingface/hub/` has 6.2 GB of transcription/audio models (Parakeet, Whisper, ECAPA2, etc. — keep these, they're real). No MLX LLMs currently cached (user deleted them all via the picker).
- **Worktrees:** none. Working tree clean. Branches: just `main`.
- **Teams:** none active (all teammates from W1/W2/W3/W4 cycles shut down + `TeamDelete`d).
- **Aesthetic redesign packets:**
  - W1 ✅ landed
  - W4 ✅ landed
  - W2 ✅ landed
  - W3 ✅ landed
  - **W5 (Settings re-skin)** ❌ not started — depends on W1 ✓
  - **W6 (AI Models + Prompts re-skin)** ❌ not started — depends on W1 ✓; user's MLX follow-ups fold here
  - **W7 (Type + sound polish)** ❌ not started — depends on W1 ✓; cohesion pass last
- **Known issues** (`docs/known-issues.md`): KI-01 (stale paste-target state on next transcription), KI-02 (Slack auto-paste silent fail), KI-03 (small-model context-awareness — "doc" → "do g"), KI-06 (gemma-3-1b QAT capacity ceiling). KI-04 + KI-05 RESOLVED — removed from file.

## Uncommitted Changes

Clean working tree. 15 commits ahead of `origin/main`, none pushed.

## Next Steps

The user's explicit ask for the next session — bundle it as a refined **W6 packet** (AI Models + Prompts re-skin) since the work overlaps. They want it dispatched via teammates with worktrees, parallel where dependencies allow. Approximate plan:

1. [ ] **Investigate gemma-4-26b-a4b 30s-no-enhancement issue.** User reports the 27B-class model hangs / produces nothing on 32 GB MBP base. Check `MLXProvider.swift` logs (`🦾 enhance:` log lines), generation timeouts, model load timing. If 27B can't fit RAM-comfortably on 32 GB, expect heavy swap → 30s+ stalls. May need to drop or relabel.

2. [ ] **Research MLX-LLM performance on Apple Silicon 32 GB base.** External research:
   - gemma-4-e4b-it-4bit (~2.5 GB, 4B effective via PLE) — current default
   - gemma-4-26b-a4b-it-4bit (~14 GB, MoE 4B active) — quality tier, suspected 32 GB issue
   - qwen-3.5-4b (~2.5 GB) — fast tier
   - qwen-3.6-27b (~14 GB) — quality tier
   - gemma-3n-E2B-it-lm-4bit (alternate fast option per prior session's notes)
   - Real-world tokens/sec + first-token latency on M2/M3/M4 base 32 GB.
   Land findings in `MLXModelEntry` extension fields (e.g. `speedRating: Int`, `qualityRating: Int`).

3. [ ] **Remove `gemma-3-1b-it-qat-4bit` from `MLXModelRegistry.curated`** — `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift:21+`. User testing: regurgitates prompt examples even with the example-removal fix. Confirmed too low-capacity for cleanup task.

4. [ ] **Filter registry by latency target.** Spec from user: ≤5s ideal, ≤10s acceptable, >10s reject. Drop or relabel any model that exceeds the threshold on base 32 GB.

5. [ ] **Add speed/quality ratings UI to `MLXModelPickerView.swift`.** Display each curated model with `Speed: 8/10` and `Quality: 6/10` style ratings. Use the new `Palette.accent` + `.glassChip()` vocabulary from W1.

6. [ ] **Segregate AI Enhancement page by configuration state.** Spec from user:
   - **Top section:** providers WITH config (API key entered, MLX model downloaded, etc.)
   - **Bottom section:** providers without config (placeholder rows for user to fill in)
   - Likely lives in `EnhancementSettingsView.swift` or `ProviderCard.swift` — read both and decide. Use `aiService.connectedProviders` (`AIService.swift:289`) as the "configured" set.

7. [ ] **Add legacy-path cleanup hook.** When `MLXModelPickerView` calls `delete(_:)`, also clean any leftover state at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/MLXModels/<repoId>/` if present. Prevents future users from hitting the disk-bloat trap. Or: one-time migration on app start that wipes the entire legacy directory if found. Either is small.

8. [ ] **Continue redesign:** dispatch **W5 (Settings re-skin)** + **W7 (type + sound polish)** as separate packets after W6 lands. W5 sweeps remaining rainbow leftovers (W4 left a triaged list: PermissionsView, TrialMessageView for Dashboard banner, etc.). W7 is the cohesion pass: `.rounded` font replacement, sound-cue volume re-tune.

### Recommended dispatch shape for next session

Following the pattern from this session (W1 → W4 → W2 → W3):

- **TeamCreate** `aesthetic-w6` (or `w6-mlx-quality` if treating as a refined sub-packet).
- **planner-w6** (general-purpose, background, no worktree) — write `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` covering items 1–6 above. Plan file follows W1/W2/W3 plan format (~14-18 tasks, exact code snippets, single integration build at the gate, no commits during execution).
- **coder-w6** (general-purpose, background, in `.worktrees/w6-mlx-quality`) — execute the plan after planner reports done. Same constraints as W2/W3 coders.
- **reviewer-w6** (`superpowers:code-reviewer`, background, in same worktree) — fresh-eyes pass after coder reports BUILD GREEN. Enforce the latency-research methodology + fact-check the model performance claims (don't trust planner's research without verification on the actual hardware).
- **W5 + W7 in parallel** is possible after W6 lands — file overlap is small (`EnhancementSettingsView.swift` is in W6's scope; W5/W7 touch different settings views + cohesion polish). But sequential is also fine if context permits.

## Context the Next Session Needs

- **CLAUDE.md is loaded automatically.** Key rules in scope: spawn TEAMMATES via `TeamCreate` + `Agent({team_name, name})`; skip per-packet builds (single integration build at merge time per `feedback_skip_per_packet_builds.md`); never commit without explicit user approval; never `git push --force`.
- **Worktree convention:** `.worktrees/<branch-name>/` (gitignored, added to `.gitignore` as `d0b6b4f`). Per superpowers:using-git-worktrees skill. `git worktree add .worktrees/<name> -b <name> main`.
- **Build:** `make local` (~3 min cold, ~30 s incremental). App copies to `~/Downloads/VoiceInk.app`. `Makefile:73` has `-skipMacroValidation` flag (required for `MLXHuggingFaceMacros` compiler plugin — don't disturb).
- **Code-signing:** local self-signed cert `voiceink-fork-local` (login keychain). Don't disturb the signing config in `pbxproj`. Falls back to ad-hoc if absent.
- **Xcode 16 PBXFileSystemSynchronizedRootGroup:** files dropped under `VoiceInk/` and `VoiceInkTests/` are auto-included in the target. **No pbxproj edits needed for new files.** This pattern recurred in W1/W2/W4/W3 — every coder hit it; each plan's xcodeproj-add step was a no-op.
- **Team task list pollution:** `TaskList` shows the active team's tasks, not the conversation's tasks. After `TeamDelete`, the conversation's task list comes back empty (TeamDelete cleans both). Don't rely on tasks across team boundaries; use git as source of truth.
- **Idle teammate notifications are noise.** Per CLAUDE.md "Be patient with idle teammates! Don't comment on their idleness until it actually impacts your work." Just hold for content messages.
- **Reviewer rigor expectations:** the W3 reviewer caught two runtime bugs build-green couldn't see — runPipeline tail unguarded `clearAll()` + recorder-panel envObject injection gap. The reviewer pattern WORKS; trust it. Pair: same coder-reviewer across revision rounds within one packet.
- **Test bundle Touch ID grant:** running `xcodebuild test` triggers a one-time UI Automation authorization prompt for new test bundles. Accept it; future runs are silent.
- **Spec is source-of-truth:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens), §2 (Structure/Cluster), §3 (Idle/menubar), §4 (state grammar), §5 (surface inventory + work packets W1–W7).
- **The user's frustration matters.** They've been doing real-app testing throughout the session and surfacing real bugs (KI-04/05/06, the disk-bloat issue, the 1B regurgitation, the 27B latency). The next session should keep the same testing-driven loop — don't hide behind build-green; verify with real dictation cycles.

---

**Tip for the next session:** the user's specific MLX work folds nicely into W6's existing scope (per spec §5#6: "AI Models page — re-skin (provider chip, status pills) to new tokens" + "Prompts editor — re-skin"). Treat the user's items 1–7 above as the **content** of W6, not a separate packet. Saves a planning round and keeps packet count clean.

Handoff saved: `docs/superpowers/handoffs/HANDOFF_aesthetic_redesign_post_W3_2026-04-28.md`

Start next session with:
> Read `docs/superpowers/handoffs/HANDOFF_aesthetic_redesign_post_W3_2026-04-28.md` and continue from where the last session left off.
