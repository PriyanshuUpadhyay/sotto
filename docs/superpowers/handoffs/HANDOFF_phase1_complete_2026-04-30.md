# Handoff — Phase 1 complete, awaiting user direction on Phase 2/3

**Date:** 2026-04-30
**Branch:** `main`
**Status:** Phase 1 (W11 enhance speed) closed (modulo W11.C upstream blocker). Phase 3 partial start (W13.A only). Phase 2 not started. 54 commits ahead of `origin/main`, none pushed.

## Goal

Continue from a clean post-Phase-1 state. The user has the consolidated build at `~/Downloads/VoiceInk.app` (mtime 2026-04-30 10:24 IST) but flagged a Settings-visibility quirk that's the immediate next thing to resolve. After that, Phase 2 (Wispr Flow parity) or Phase 3 remainder (aesthetic B-G) is open for dispatch.

## Source of truth — read these first

1. `docs/superpowers/STATUS.md` — top-level state, Phase 1 closeout table with merge SHAs.
2. `docs/superpowers/PHASE-TRACKING.md` — full per-packet status matrix W11 / W12 / W13. Updated as packets merge.
3. `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` — research-backed master plan + the 10 user-signed-off decisions in §0.
4. Research bundle (R1-R4) under `docs/superpowers/research/2026-04-29-*.md` — comparison tables, eval numbers, vocabulary specs, full source audit.
5. Per-packet plans under `docs/superpowers/plans/W*A.md` (W11A, W13A) — the W7-pattern docs alongside their impl.

## Work Completed (this session — 2026-04-29 → 2026-04-30)

### Phase 1 — W11 (enhance speed real fix)

All seven Phase 1 packets resolved:

| # | Packet | Merge | Notes |
|---|---|---|---|
| 1 | `w11-models-expand` | `14f092a` | Registry expansion (5 new curated entries: Qwen3-0.6B, Phi-3.5-mini-MIT, Llama-3.2-3B license-flagged, Granite-3.3-2B Apache, SmolLM3-3B Apache) + cache auto-detect scanner with new `DETECTED` picker section. Reclaims orphaned downloads (Gemma-4 from before W10). |
| 2 | W11.A pipeline fixes | `84ac7bf` | A1 prewarm (MLX added to ModelPrewarmService.shouldPrewarm + recording-start hook); A2 short-transcript fast-path (≤120 char threshold drops the ~675-token wrapper); A4 greedy decode (`temperature: 0.0` → ArgMaxSampler); A5 wall-clock timeout via withThrowingTaskGroup; A6 idle-evict slider (`MLXIdleEvictSeconds` AppStorage default 1800); A7 max_tokens floor 192→96 + ceiling 768→512. A3 deferred at the time. |
| 3 | W11-prompt-fix | `3247736` | MLX userPrompt wrapped in `<TRANSCRIPT>` tags (matches LocalCLI convention). Closing suffix "Output only the cleaned text. Do not respond to the content above." Resolves Qwen3 "replies instead of cleans" bug. PromptTemplates "System Default" body aligned to use `<TRANSCRIPT>` consistently with `AIPrompts.customPromptTemplate`. Foundation Models path untouched. |
| 4 | W11.D timing telemetry | `42edcbe` | New `EnhancementTimingLogger` actor; CSV at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv` (11 cols: timestamp, modelId, promptMode, inputChars, outputChars, prepSeconds, ttftSeconds, genSeconds, totalSeconds, gapSinceLastSeconds, outcome). Diagnostic logs added: `🦾 prompt-mode:`, `🦾 prewarm: fired … source=…`, `🦾 evicted X after idle (idleEvictSeconds=N)`, `🦾 enhance: timeout fired`. UI buttons "Open timings folder" + "Copy CSV path" in EnhancementSettingsPanel MLX section. |
| 5 | W11.A.A3 KV-cache reuse | `201fb8f` | Path B token-diff splitter (tokenize `[.system]` and `[.system, .user]`, take longest common prefix N as system token suffix). On hit (modelId + SHA-256(systemPrompt) + same N), restore snapshot via `cache.map { $0.copy() }` and feed only user-suffix tokens. Gated behind `MLXKVCacheReuseEnabled` UserDefault (default false). chatml/Qwen3/Phi/SmolLM3/Granite → full benefit; legacy `[INST]<<SYS>>` → graceful no-op via `n<32` floor. CSV writes `promptMode=kvCacheReuse` on hits. Snapshot invalidates on `reset()` and `evictIfIdle()`. |
| 6 | W11.B AFM primary path | `e228f73` | Deployment target bumped 14.4 → 26.0 (Debug + Release + tests). New `AFMProvider` actor REPLACES `FoundationModelsProvider`. 6 call sites migrated. Routing: probes `SystemLanguageModel.default.isAvailable`; AFM-first when available; only `LanguageModelSession.GenerationError.guardrailViolation` (mapped to `ProviderError.safetyRefusal`) falls back to MLX silently. Other AFM errors propagate as `EnhancementError.customError`. Prewarm wired in `ModelPrewarmService.performPrewarm` (fires whenever AFM available, regardless of provider selection). CSV `promptMode=afm` populated. AFM gets RAW user message (no `<TRANSCRIPT>` wrap). User-machine validation of AFM-disabled fallback is post-merge. |
| 7 | W11.C spec-decode | ⏸ deferred (no commit) | `mlx-community/speculative-decoding` Package.swift pins `mlx-swift-lm from: "2.29.2"` (`<3.0.0` ceiling); we're locked to `exactVersion 3.31.3` for qwen3 model_type + KV-cache APIs + swift-huggingface 0.9.0 cache layout. SemVer ranges don't intersect. Three forward options in tracker: (a) fork `pu-foyer/speculative-decoding` mirror + bump dep + patch source breaks, (b) port algorithm in-tree (~500-1000 LOC), (c) wait for upstream (active repo, last commit 2025-12-08). |

### Phase 3 partial start (one packet)

| Packet | Merge | Notes |
|---|---|---|
| W13.A token sweep | `e196cda` | 26 files swept across A axis (`Color.accentColor` → `Palette.accent`, 13 sites), B axis (`Color.white.opacity(α)` → semantic `Palette.hairline*` / `Palette.innerHi`, 4 strokes), F axis (ad-hoc `Animation.spring/smooth/easeInOut` → `Animation.halo*` named tokens, ~30 sites). Floating-bar surfaces, glass primitives, menubar, Metrics hero gradient (Q9=a → W13.B), Form-internal sites (W13.D), AI Models card chrome (W13.E), History window opacity (W13.F) all explicitly excluded per per-axis Sweep/Defer/Flag table in `docs/superpowers/plans/W13A-token-sweep.md`. |

### Research + planning artifacts (committed)

- 4 research docs (R1-R4) under `docs/superpowers/research/2026-04-29-*.md` — `dba243d`
- Master plan `2026-04-29-W11-W13-master-plan.md` with locked decisions §0 — `dba243d`
- Per-packet plans `W11A-pipeline-fixes.md`, `W13A-token-sweep.md` — `dc4d4fd`, `e6c4cf0`
- Phase tracker `PHASE-TRACKING.md` — `20b503d` (initial) + updates each merge
- STATUS doc kept in sync with tracker — last sync `bf98101`

## Open Items — Sign-off / Action Needed in the Next Session

### Item 1 — Settings visibility gating (immediate; user just flagged)

**User statement (verbatim, this session):** *"Is there an option to see which one is active. mlx or afm?? Also i dont see a slider in the settings."*

**Diagnosis:** `EnhancementSettingsPanel.swift:158` gates the entire MLX-related Section behind `enhancementService.aiService.selectedProvider == .mlx`. That section contains:
- `Active path: <Apple Foundation Models | MLX (...)>` indicator
- `Idle eviction` Picker (60s … Never)
- `Open timings folder` + `Copy CSV path` buttons
- `MLXKVCacheReuseEnabled` toggle is presumably nearby (need to verify in code)

If the user has selected `.foundationModels` directly as the provider, the entire MLX section is hidden. Same if they're on a remote API provider. **The `Active path` indicator should appear regardless of selection** because W11.B routes AFM-first whenever the user is on `.mlx` AND when on `.foundationModels`. The current gating means the indicator is invisible exactly when AFM is the more interesting case.

**Lead's recommendation:** small fix packet — extend the gating to `.mlx || .foundationModels` for at least the active-path indicator. Alternatively split the "On-device path status" out of the MLX section entirely and show it whenever any local-only provider is active. ~10 LOC, single file.

**Open question for the user:** confirm the fix shape — (a) extend the existing section's gating, (b) split the indicator into its own always-visible row above the provider-selector area, or (c) leave as-is and document that "select MLX provider to see status."

### Item 2 — Validation pass on the consolidated build

**User has the binary** at `~/Downloads/VoiceInk.app` mtime 2026-04-30 10:24 IST — covers all of Phase 1.

**What to capture:** rows in the CSV at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv` across multiple enhancement runs at varying gap intervals. Specifically the question "5s gap vs 15min gap" should now show:
- A `gapSinceLastSeconds` column populated
- Different `prepSeconds` / `ttftSeconds` profiles when AFM is the active path vs when MLX is
- `promptMode` column reflecting whether fastPath / standard / kvCacheReuse / afm fired

If A1 prewarm doesn't show up as faster cold-after-idle vs cold-on-launch in the CSV, user can opt to drop A1 in a small follow-up. Don't preempt — wait for empirical data.

### Item 3 — Phase 2 / Phase 3 dispatch direction

**Phase 2 (Wispr Flow parity, 5 P0 features), recommended start: W12.A** — Auto Cleanup levels (None / Light / Medium / High) + diff view + Undo AI edit. Directly addresses the "enhance is bad" complaint by giving a dial instead of binary toggle. `WordDiffEngine` already exists. Highest user-leverage of any P0. Pairs naturally with Phase 1's perf wins.

**Phase 3 remainder (aesthetic B-G), recommended start: W13.B** — Metrics dashboard rebuild. First surface a new user sees. Worst aesthetic-cohesion offender per R4 audit (raw `.thinMaterial` cards + system-blue gradient + `.rounded` font). Per Q9=a user signed off "keep gradient, switch from controlAccentColor to `Palette.accent` glow."

**Both packets have zero file overlap** — can run parallel teams (per `superpowers:dispatching-parallel-agents`).

## Key Decisions From This Session (locked)

| Decision | Rationale |
|---|---|
| **Q1=b: bump deployment target macOS 14.4 → 26.0** | AFM is the primary fast path on hardware where Apple Intelligence is enabled; reduces what we have to maintain on the MLX side. User explicitly chose this in the §5 sign-off. |
| **Q3=c: spec-decode as opt-in Settings toggle** | Single switch instead of registry visibility; turns out moot given the W11.C deferral, but the design is in place if/when we revisit. |
| **Q5: Caps+9 (Hyper+9) for Command Mode hotkey** | User has Hyper via Karabiner — Hyper+9 = Cmd+Ctrl+Opt+Shift+9 → near-zero app collisions. Locked for W12.B. |
| **Q6=a: 4-level Auto Cleanup dial (None/Light/Medium/High)** | Matches Wispr mental model. Simpler than binary + tone picker option. Locked for W12.A. |
| **Q10: defer test infra unblock** | Build-only validation continues; `xcodebuild test` env-block (Mac Development cert + macros-trust + IPC bootstrap) carries over. |
| **W11.A.A3 implementation approach: Path B token-diff** | Reviewer + coder agreed Path B is more robust than Path A (template-aware suffix-only diff) for handling chatml vs legacy template families. |
| **W11.C deferral via APPROVE-DEFER** | Hard SemVer wall on upstream's mlx-swift-lm pin. Three forward options documented; not a decision we can make on our side. |
| **Skip-confirmation memory** | Saved as `feedback_no_confirmation_trivial.md`. After sign-off, dispatch trivially next packet without asking for permission. |

## Files Changed (this session — committed)

54 commits ahead of `origin/main`. Phase-1 implementation commits:

```
bf98101 docs(superpowers): STATUS — sync with Phase 1 final state
641d07d docs(superpowers): tracker — W11.C deferred (upstream SPM block)
0fa58e6 docs(superpowers): tracker — W11.B merged, W11.C next
e228f73 feat(afm): W11.B — Apple Foundation Models primary path on macOS 26+
82e0698 docs(superpowers): tracker — W11.A.A3 merged, W11.B next
201fb8f feat(mlx): W11.A.A3 — KV-cache reuse for system prefill (opt-in)
20b503d docs(superpowers): add phase tracker + W11.D landed status
42edcbe feat(mlx): W11D — enhancement timing telemetry + diagnostic logs
3247736 fix(mlx): wrap user prompt in <TRANSCRIPT> tags + align prompt convention
84ac7bf feat(mlx): W11A — pipeline fixes (prewarm + fast-path + greedy + timeout + idle-evict + max-tokens; A3 deferred)
e196cda feat(aesthetic): W13A — token sweep across main-app surfaces
14f092a feat(mlx): expand registry + auto-detect installed models
e6c4cf0 docs(plans): W13A — token sweep plan
dc4d4fd docs(plans): W11A — pipeline fixes plan
dba243d docs(superpowers): W11 deep research + W11/W12/W13 master plan + status
```

## What Didn't Work

- **`mlx-community/speculative-decoding` SPM ingestion** — hard SemVer conflict (its `from: "2.29.2"` ceiling vs our `exactVersion 3.31.3` floor). Coder verified the package exists, has the right Swift API, even has community benchmarks at 81.4 tok/s with 76.3% acceptance — none of which matters when SwiftPM resolution can't reconcile the dep range. Documented as W11.C ⏸ in `PHASE-TRACKING.md`. Don't re-attempt without one of the three forward options committed.
- **Stale TaskList readings** — reviewers periodically reported task #N still in_progress when it was actually completed; pattern is they polled at the wrong moment OR their cached state was stale. Workaround: a single nudge SendMessage from lead unsticks them. Happened 4× in this session.
- **Worktree path drift via persistent Bash cwd** — `git worktree add .worktrees/X` with a relative path resolved against whatever cwd was last `cd`-ed to. Created a nested worktree inside another worktree once. Workaround: always use absolute paths for `git worktree add`, or `cd <main-repo>` before. Documented inline in handoffs starting next session.
- **Disk-full panic from coders running before integration build** — coder reported "117 MiB free" while system actually had 46 GiB free. Stale `df` reading or transient state. Workaround: lead probes `df -h /System/Volumes/Data` from main thread and reassures. Happened once on W11.A coder.
- **`xcodebuild test` env-block** — same triple block carrying from W3+: macros-trust prompt + Mac Development cert team V6J6A3VWY2 not in keychain + IPC bootstrap on unsigned bundle. Build-only validation throughout this session. User-machine fix.

## Current State

- **Build:** green at `main` HEAD `bf98101`. App at `~/Downloads/VoiceInk.app` (mtime 2026-04-30 10:24 IST) covers all of Phase 1.
- **Tests:** untested in this session (env-blocked). Last green: `FailureRegistryTests` 5/5 + `PaletteTests` 2/2 + `VoiceInkUITests` 4/4 at end of W3.
- **Disk:** 46 GiB free on data volume (last check this session).
- **Worktrees:** none.
- **Branches:** just `main`.
- **Teams:** none active.
- **Aesthetic redesign:** W1-W8 + W13.A landed. W13.B-G remaining.
- **Monetization:** ✅ stripped (license + Polar + Obfuscator + onboarding + legacy constellation). Per `~/.claude/projects/<this>/memory/project_strip_monetization.md` — don't re-introduce.
- **Telemetry:** ✅ live. CSV at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv`. Will populate on every MLX enhance (and AFM enhance once user is on macOS 26 + Apple Intelligence enabled).
- **Routing path on macOS 26 + AI on:** AFM primary, MLX fallback on safety refusal.
- **Routing path on macOS 26 + AI off:** MLX direct (the W11.B fallback path; not yet end-to-end exercised pre-merge but routing discipline verified statically).

## Uncommitted Changes

Clean working tree. 54 commits ahead of `origin/main`, none pushed.

## Next Steps (priority order)

1. [ ] **Fix Settings visibility gating** (Item 1 above). Single-file fix; either dispatch a tiny coder packet OR do it in-tree without a team since it's <10 LOC. Lead leans dispatch a coder per project pattern but it's overkill for this size.
2. [ ] **User runs the validation pass** (Item 2). Capture CSV rows at varying gap intervals. Lead reads them on next session start.
3. [ ] **User picks Phase 2 vs Phase 3 dispatch** (Item 3). Lead recommends starting both in parallel: W12.A (Auto Cleanup levels + diff + Undo) + W13.B (Metrics dashboard rebuild). Zero file overlap, can run parallel teams.
4. [ ] **W11.C revisit** when one of the three forward options crosses the cost/benefit threshold (likely not until Phase 2 + 3 are well-along).
5. [ ] **A1 prewarm sanity-check from CSV** — if cold-after-idle and warm rows show identical timings even after prompt-fix, drop A1 in a small follow-up. Save the lines of code.
6. [ ] **User-machine smoke pass** on the cumulative Phase 1 surface.
7. [ ] **Test infrastructure unblock** — separate session per Q10.

### Recommended dispatch shape for the next session

**Phase A (immediate fix):** dispatch a small coder team for Settings visibility gating per Item 1. ~10 LOC; coder + reviewer pair sequenced; no planner needed. Should land within 30 minutes.

**Phase B (parallel kickoff):** dispatch W12.A + W13.B as two parallel teams. Each has its own coder + reviewer. Per `feedback_skip_per_packet_builds.md`, single integration build per packet at merge. W12.A is the higher-impact one but W13.B is simpler — can use that as a pilot for any new patterns.

**Phase C (after both Phase B packets land):** sequence W12.B → W12.C → W12.D → W12.E for Phase 2; W13.C → W13.D → W13.E → W13.F → W13.G for Phase 3. Some can parallelize within phase (e.g. W12.C is the most isolated; can run alongside W12.B).

## Context the Next Session Needs

- **CLAUDE.md is loaded automatically.** Same rules: spawn TEAMMATES via `TeamCreate` + `Agent({team_name, name})`; skip per-packet builds (single integration build at merge time); never commit without explicit user approval; never `git push --force`.
- **Worktree convention:** `.worktrees/<branch-name>/`. Per `superpowers:using-git-worktrees`. Use ABSOLUTE paths for `git worktree add` to dodge the cwd-drift foot-gun (hit once this session).
- **CWD foot-gun:** never run `git worktree remove .worktrees/X` while the bash shell CWD is inside that worktree. Always `cd <main-repo>` first. Recurring across sessions.
- **Build:** `make local` from main path. App lands at `~/Downloads/VoiceInk.app`. `Makefile:73` has `-skipMacroValidation` flag (required for MLXHuggingFaceMacros — don't disturb).
- **Code-signing:** local self-signed `voiceink-fork-local` cert. `xcodebuild test` env-blocked.
- **Xcode 16 PBXFileSystemSynchronizedRootGroup:** files dropped under `VoiceInk/` and `VoiceInkTests/` auto-included; no pbxproj edits needed for new files (verified again this session with `AFMProvider.swift` + `EnhancementTimingLogger.swift`).
- **Spec is source-of-truth:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` — extend rather than ad-hoc. R4 vocabulary spec at `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md` §2 captured the floating-bar tokens explicitly; W13.B-G should reference it.
- **Plan files committed alongside impl:** match the W3/W5/W6/W7 pattern (two commits per packet — `docs(plans): WX — …` + `feat(…): WX — …`).
- **Memory:** auto-memory at `~/.claude/projects/-Users-priyanshu-Desktop-Projects-pu-voiceink-fork/memory/` includes the user-feedback "skip confirmation prompts on trivial decisions" rule plus the strip-monetization project rule. Both honored in this session.
- **Telemetry CSV columns** (W11.D): `timestamp, modelId, promptMode, inputChars, outputChars, prepSeconds, ttftSeconds, genSeconds, totalSeconds, gapSinceLastSeconds, outcome`. promptMode enum: `standard | fastPath | kvCacheReuse | afm | specDecode` (specDecode reserved but unreachable while W11.C is deferred).
- **Provider routing summary (post-W11.B):** user selects `.mlx` → AFM-first if `SystemLanguageModel.default.isAvailable`, MLX fallback on `safetyRefusal` only. User selects `.foundationModels` → AFM directly. User selects remote API provider → unchanged.
- **54 commits ahead of `origin/main`, none pushed.** User pushes manually.

### Lead's pending questions for the user

If the new session opens with these unresolved, ask explicitly:

1. **Settings visibility fix shape** (Item 1) — extend MLX section gate / split into always-visible row / leave as-is.
2. **Phase 2/3 dispatch direction** (Item 3) — start W12.A + W13.B in parallel? Different pair? Defer one phase entirely?
3. **W11.C forward path** — stay deferred (revisit later) / pick a forward option (fork+bump / in-tree port / wait-for-upstream).
4. **A1 prewarm fate** — once CSV has data, drop or keep?
5. **Push to origin?** 54 commits behind; unchanged from prior sessions where user explicitly pushes manually.

---

**Tip for the next session:** the user's testing-driven loop continues to be the most reliable signal-detector. Don't claim Item 1 / Item 3 done without a real-machine validation pass. The Qwen3 "replies instead of cleans" bug from earlier this session is exactly the kind of finding that survives all the static analysis in the world but only surfaces under live use — trust empirical CSV data over any extrapolated benchmark.

Handoff saved: `docs/superpowers/handoffs/HANDOFF_phase1_complete_2026-04-30.md`

Start next session with:
> Read `docs/superpowers/handoffs/HANDOFF_phase1_complete_2026-04-30.md` and continue from where the last session left off.
