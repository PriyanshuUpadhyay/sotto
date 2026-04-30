# Handoff — Phases 2 + 3 complete; carryover follow-ups for next session

**Date:** 2026-04-30
**Branch:** `main` at `db14e5f` (in sync with `origin/main`, working tree clean)
**Status:** Phases 2 + 3 ✅ done. Phase 1 ✅ done modulo W11.C deferred. No active worktrees. No active teammates.

## Goal

This session shipped the entire Phase 2 (Wispr Flow parity) and Phase 3 (aesthetic unification) packet roster — 12 feature packets + 2 fixes. Next session inherits a clean post-Phases-2/3 state with several small follow-up items + 1 deferred packet (W11.C) + 3 user-side / brainstorm items.

## Source of truth — read these first

1. `docs/superpowers/PHASE-TRACKING.md` — every packet's merge SHA + scope; updated to reflect Phase 2/3 complete.
2. `docs/superpowers/STATUS.md` — top-level state (may be slightly stale; sync if you touch).
3. `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` — research-backed master plan + 10 user-signed-off decisions in §0.
4. `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` — extended in-place by W13.G with §1.X.W13.1-9 + §2.4-W13 halo token mapping (the canonical aesthetic spec).
5. Per-packet plans under `docs/superpowers/plans/W*.md` — every packet has a plan doc landed alongside its impl commit.
6. Prior handoff: `docs/superpowers/handoffs/HANDOFF_phase1_complete_2026-04-30.md` — Phase 1 closeout + open items at start of this session.

## Work Completed (this session — 14 commits to origin/main)

### Phase 2 (Wispr Flow parity) — 5/5 packets

| Packet | Merge | Notes |
|---|---|---|
| **W12.A** Auto Cleanup levels + diff + Undo | `3bf3013` | EnhanceLevel enum (None/Light/Medium/High) replaces stored `isAIEnhancementEnabled: Bool` via dual-key Codable + derived bool accessor (~64 in-tree readers compile unchanged). Per-level system-prompt directive. WordDiffEngine.tokenLevelDiff sibling. TranscriptionDetailView gains Panes/Diff picker + AttributedString inline diff + "Undo AI edit" button. Pickers at 3 surfaces. |
| **W12.B** Command Mode | `852a613` | Caps+9 (Hyper+9) hotkey → SelectedTextService captures → recorder opens → user dictates instruction → AIEnhancementService.commandModeRewrite splices instruction INSIDE customPromptTemplate's `<SYSTEM_INSTRUCTIONS>` (W12.A 0759019 lesson). Cmd+V stamps undo on source app stack so system Cmd+Z restores. Provider routing parity. Banner pill + menubar status. Transcription gains additive optional commandModeSelection + commandModeInstruction. wasCommandMode autoSend gate. |
| **W12.C** Voice Snippets | `7cda954` | New SwiftData @Model Snippet registered in 3 schema sites. SnippetExpansionService (@MainActor, .shared) with cache + fetchCount probe. Word-boundary regex `(?:\b\|^\|(?<=\s))<escaped>(?:\b\|$\|(?=\s))` handles non-word-leading triggers (`;sig` `:date` `/code` `@addr`). Pre-enhance splice in TranscriptionPipeline — additive, no-op when no snippets. New sidebar entry + SnippetsSettingsView (W5 SettingsCard) + SnippetEditorSheet w/ inline collision rejection. ImportExportService extended via SnippetExportData. |
| **W12.D** Hands-free + VAD + voice "press enter" | `eeee9a5` | KeyboardShortcuts.Name.handsFreeToggle UNBOUND on first run (user binds explicitly). RMS-gated VAD off Recorder.audioMeter. Each utterance = separate Transcription via VoiceInkEngine.commitUtterance. Default trigger phrases `["press enter","submit","send it","send message"]` (case-insensitive whole-suffix). 20-min hard cap. Menubar IconState.handsFree (`ear.fill` accent-tinted). HandsFreeSettingsView w/ VAD threshold + silence duration + trigger editor. **Critical post-revise C1 fix:** sleep observer registered on `NSWorkspace.shared.notificationCenter`, NOT `NotificationCenter.default` (was silently dead). Recorder behavior outside hands-free byte-identical via `state != .inactive` gates. |
| **W12.E** Scratchpad | `06242da` | New ⌥+S window — multi-tab + autosave + 50-version history; doubles as paste-fallback target. 9 new files. Tab cap 10 user-created (paste-fallback bypasses for data preservation). Title auto-derived from first 30 chars. Autosave 800ms debounced; flushAll on windowWillClose. Version snapshots every 30s active typing OR tab switch / window close. Plain text only. Paste-fallback appends NEW tab in CursorPaster's `mustForceClipboard` branch ONLY (happy path byte-identical). Dictation-into-place gates BEFORE pasteAtCursor + suppresses autoSend. |

### Phase 3 (aesthetic unification) — 7/7 packets (A landed pre-session; B-G this session)

| Packet | Merge | Notes |
|---|---|---|
| **W13.A** Token sweep | `e196cda` (pre-session) | Already merged before this session. |
| **W13.B** Metrics dashboard rebuild | `25d8bcb` | Hero gradient SHAPE preserved per Q9=a; only color swaps `controlAccentColor` → `Palette.accent` (alphas 1.0/0.85/0.70 + 24pt + drop shadow byte-identical). MetricCard → GlassCard(16); drops `color: Color` parameter. Single Palette.accent icon tint. HelpAndResourcesSection → glassPanel(16). CopySystemInfoButton → glassChip(18) soft-pill + 5× `spring(0.3,0.7)` → Animation.haloExpand. |
| **W13.C** Permissions + AudioTranscribe | `c2ad3aa` | PermissionCard → GlassCard(14, 20). Drop-zone → glassPanel(14) + dashed Palette.hairlineSoft strokeBorder. topBar Add/Clear → glassChip(10); Cancel → Palette.warn glassChip; Start → solid Palette.accent Capsule + accentGlow shadow. AudioFileRow palette swaps only (Form host preserved for W13.D). |
| **W13.D** Form-host purge | `864e827` | **FIXES the user-flagged "AI Enhancement 2-grid layout looks bad" complaint.** Largest diff in W13. 5 surfaces purged: EnhancementSettingsView (3 SettingsCards + gear+plus ZStack overlay), EnhancementSettingsPanel popover (flat sectionBlock×7 — NO SettingsCard, avoids double-glass over the popover's existing adaptiveGlassBackground), PromptEditorView, InlineHistoryView cardListView, AudioTranscribeView queue (queueFormView → queueListView). APIKeyManagementView transitive Section→SettingsCard. |
| **W13.E** AI Models cards | `5424882` | 5 card files + MLXModelPickerView. Multi-section cards (Cloud/Custom) GlassCard(16, padding: 0) preserving inner per-section padding; single-section cards GlassCard(16, 16). Active stroke `Palette.accent.opacity(0.55)` 1.5pt; rest `Palette.hairline` 1pt. Capsule CTAs Palette.accent; verify-success Palette.success. WhisperModelManager DownloadProgressView retint. ProviderCard preserved (vocab-clean since W6). |
| **W13.F** History window glass + animation codemod | `e040e03` | HistoryWindowController:54 mirror WindowManager.configureWindow flags. TranscriptionHistoryView 3 sub-pane fills swept. Search field → glassChip(8). 5× `.smooth(0.3)` → Animation.haloExpand. |
| **W13.G** Polish + spec extension | `4e17cee` | FINAL Phase 3 packet. 9 axes across 15 source files + spec amendment. AppNotificationView 3-color palette (error/warning Palette.warn, info Palette.accent, success Palette.success — NOT plan's single-accent default). 7 chip-affordance closing pass. CustomPrompt.promptIcon family rebuild (radial-glow + decorative circles DELETED, replaced with GlassCard(14, 0) + 1.5pt selection ring + accent glow rad 18; method signature byte-identical). PowerModeView heroHeader → SettingsSectionHeader. **Spec amendment APPENDED in-place to `2026-04-28-aesthetic-redesign.md`: §1.X.W13.1-9 (9 subsections) + §2.4-W13 halo token mapping table.** |

### Phase 1.5 fixes (mid-session)

| Item | Merge | Notes |
|---|---|---|
| Settings visibility (Item 1 from prior handoff) | `b463a0f` | Extended On-device section gate to `.mlx \|\| .foundationModels` so Active-path indicator is visible regardless of provider selection. Renamed "MLX (on-device)" → "On-device". Idle-eviction picker stays gated to `.mlx`. |
| Prompt-fragmentation fix | `0759019` | W12.A's `cleanupDirective` was prepended OUTSIDE customPromptTemplate's `<SYSTEM_INSTRUCTIONS>` block. Qwen3-Instruct fragmented the prompt and regressed to chat-instruct mode on question-shaped dictations. Fix: splice directive INSIDE the wrapper via `%@` substitution. Plus: assistant mode exempt from directive (assistant is meant to RESPOND, not clean). |

## Key Decisions (locked this session)

| Decision | Rationale |
|---|---|
| **W12.A Codable shape: dual-key encoder, dual-key decoder w/ legacy fallback** | Decode prefers `enhanceLevel` enum, falls back to `isAIEnhancementEnabled: Bool → .medium/.none`; encode writes BOTH for ≥3-month downgrade tolerance. Drop the bool encode in a follow-up packet 3 months post-W12.A merge. |
| **W12.A derived `isEnhancementEnabled` accessor** | Keeps ~64 in-tree bool readers compiling unchanged (recorder Toggle, menubar Toggle, file-transcribe, popover, prompt-detection, etc.). Quick-toggle UIs flip None ↔ Medium. Reversible if reviewer prefers explicit level reads later. |
| **Prompt directives must splice INSIDE `<SYSTEM_INSTRUCTIONS>`, never prepend OUTSIDE** | Qwen3-Instruct fragments prompts into separate "tasks" and regresses to chat-instruct mode when directive sits at top with bare content tags (`<CLEANUP_LEVEL>Medium</CLEANUP_LEVEL>` was the trigger). W12.B's commandModeTemplate honored this lesson from the start. **Future packets that splice prompt content MUST use `String(format: customPromptTemplate, ...)` or analogous — NEVER raw concatenation outside the wrapper.** |
| **W12.D sleep observer center** | `NSWorkspace.willSleepNotification` posts on `NSWorkspace.shared.notificationCenter`, NOT `NotificationCenter.default`. Wrong center = silently dead observer. Reviewer caught this; codebase has 4 prior sites that get it right. |
| **W13.D popover surface uses flat `sectionBlock`, NOT SettingsCard** | EnhancementSettingsPanel popover has its own `adaptiveGlassBackground(intensity: .panel)` + PromptEditorView's `editorPane` is already a GlassCard. Wrapping with SettingsCard would double-layer glass material. Flat un-carded sections with 11pt SF-mono uppercase labels (mirroring `MLXModelPickerView` / `APIKeyManagementView.sectionLabel`). Plan author flagged this as the trickiest fit. |
| **AppNotificationView 3-color palette** | error/warning → `Palette.warn`; info → `Palette.accent`; success → `Palette.success`. Lead override of plan's single-accent default. Color is the primary semantic signal; collapsing all severities to one accent loses error legibility. Motion (shake/pulse) was an aspirational add — deferred to follow-up packet. |
| **Worktree path discipline (cwd-drift foot-gun)** | W12.B coder drifted edits into main TWICE despite warnings. Root cause: Edit/Write tools take ABSOLUTE paths that bypass shell cwd; python `open()` calls with relative paths resolve against bash cwd which can re-anchor between long tool calls. **Mandatory rule going forward:** every Edit/Write/Bash-python path must be prefixed with `/Users/priyanshu/Desktop/Projects/pu/voiceink-fork/.worktrees/<branch>/`. Pre-edit guard: `git -C <main-repo> status --short` should be empty. Brief every coder spawn with this rule explicitly. |
| **Skip per-packet builds; single integration build at merge time** | Per `feedback_skip_per_packet_builds.md`. Coder leaves edits uncommitted; reviewer checks; lead does ONE `make local` at merge. Honored across all 12 packets this session. |
| **Same-pair iteration on REVISE** | coder + reviewer pair stays bonded for ONE packet across revise rounds. Did NOT respawn on revise rounds. Confirmed by 2 successful revise-then-approve cycles (W13.E Cloud Divider; W12.D sleep observer). |

## Files Changed (this session)

14 commits to `origin/main` since prior handoff. Per-packet diffs on master plan compliance — see `docs/superpowers/PHASE-TRACKING.md` for the per-packet stat tables. Aggregate: ~5500 LOC inserted, ~1200 LOC deleted (gross, not all unique — some packets evolved each other's changes).

```
db14e5f docs(superpowers): tracker — Phases 2 + 3 COMPLETE
4e17cee feat(aesthetic): W13G — Polish + final spec extension
eeee9a5 feat(handsfree): W12D — Hands-free + VAD + voice "press enter"
06242da feat(scratchpad): W12E — Scratchpad
ce30eec docs(plans): W13G — Polish + final spec extension
852a613 feat(commandmode): W12B — Command Mode (highlight + voice rewrite)
864e827 feat(aesthetic): W13D — Form-host purge (5 surfaces → SettingsCard)
7cda954 feat(snippets): W12C — Voice Snippets (text expansion)
5424882 feat(aesthetic): W13E — AI Models card unification
c2ad3aa feat(aesthetic): W13C — Permissions + AudioTranscribe styling
e040e03 feat(aesthetic): W13F — History window glass + animation codemod
39f18e8 docs(plans): W13D — Form-host purge
92437f5 docs(plans): W12E — Scratchpad
10ae37c docs(plans): W12D — Hands-free + VAD
f3e70a5 docs(plans): W12B — Command Mode
ae548ee docs(plans): W13E — AI Models cards
a2c2286 docs(plans): W12C — Voice Snippets
1bddd2b docs(plans): W13C — Permissions + AudioTranscribe
1125c3f docs(plans): W13F — History window glass
0759019 fix(enhance): splice level directive INSIDE customPromptTemplate
1a2312d docs(superpowers): tracker — W12.A + W13.B merged
3bf3013 feat(enhance): W12A — auto cleanup levels + diff view + Undo AI edit
25d8bcb feat(aesthetic): W13B — Metrics / Dashboard rebuild
ab4e4a1 docs(plans): W12A — Auto Cleanup levels
4dab585 docs(plans): W13B — Metrics / Dashboard rebuild
b463a0f fix(settings): show On-device section for both .mlx and .foundationModels
```

## What Didn't Work

- **cwd-drift foot-gun (twice).** W12.B coder edited main's working tree instead of `.worktrees/w12b/` despite an URGENT correction message after the first instance. Root cause: bash python `open(rel_path, 'w')` re-anchors cwd between long-running tool calls. **Mitigation in coder briefs going forward:** explicit absolute-path-with-worktree-prefix rule + pre-edit `git -C <main> status` guard. Lead recovered both incidents by `git diff > /tmp/leak.patch && git apply` to the worktree. Documented in §Key Decisions.
- **W12.A initial directive injection regressed Qwen3-Instruct.** Prepending the cleanup directive outside the `<SYSTEM_INSTRUCTIONS>` wrapper let the model fragment its task understanding and respond to question-shaped dictations instead of cleaning them. Fixed at `0759019`. The user noticed within minutes of the W12.A install. Lesson: "directive injection sites must be inside strong framing" is now a hard rule for any future prompt-touching packet.
- **Reviewer flagged plan-doc imprecision (NIT-3 on W12.C).** Plan claimed `;sig` in `"assignment;sig"` skips because "neither side is whitespace nor edge" but `\b` actually fires at the `t/;` (word/non-word) transition. Practical impact nil since whisper rarely produces glued tokens, but worth noting plan docs aren't infallible — reviewer's superpowers:code-reviewer skill catches them when paired with code review.
- **Rebase conflicts on multi-touch files.** W12.B + W12.C + W12.D + W12.E all touched TranscriptionPipeline.swift (different lines but high merge conflict probability). W12.D's rebase needed manual resolution to combine W12.B's `wasCommandMode` gate + W12.E's Scratchpad gate + W12.D's `triggerHit` override into one coherent autoSend block. **For future multi-packet phases that touch shared infrastructure, sequence merges deliberately + plan rebase resolution upfront.**
- **W13.D's AudioTranscribeView rebase conflict against W13.C's palette swaps.** Resolved by taking W13.D's structural changes (ScrollView/LazyVStack/GlassCard) + W13.C's animation tokens (`.haloExpand`).

## Current State

- **Build:** green at `main` HEAD `db14e5f`. App at `~/Downloads/VoiceInk.app` carries everything.
- **Tests:** untested in this session (env-blocked per Q10 carryover). Last green: `FailureRegistryTests` 5/5 + `PaletteTests` 2/2 + `VoiceInkUITests` 4/4 at end of W3.
- **Disk:** healthy.
- **Worktrees:** none.
- **Branches:** just `main`.
- **Teams:** none active. `voiceink-phase23` team file may still exist on disk; clean up via TeamDelete next session if needed.
- **Master plan packet roster:** all of Phases 1-3 done modulo W11.C deferred.
- **Spec:** `2026-04-28-aesthetic-redesign.md` extended in-place by W13.G (§1.X.W13.1-9 + §2.4-W13). It is the canonical aesthetic spec going forward.
- **Telemetry CSV:** `~/Library/Application Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv`. User has not yet captured the validation rows requested last session (Task #11 still pending).

## Uncommitted Changes

Clean working tree. 0 commits ahead of `origin/main`. All 14 session commits pushed.

## Next Steps (priority order — pick what's compelling)

### P0 — User-side empirical capture (gates other decisions)

1. [ ] **Task #11 — fill the CSV.** Run dictations at varying gap intervals on `~/Downloads/VoiceInk.app`. Captures `gapSinceLastSeconds` + `prepSeconds` + `ttftSeconds` + `genSeconds` profiles for AFM (when active) vs MLX (fallback). Drives:
   - **A1 prewarm fate decision.** If cold-after-idle and warm rows show identical timings even after the prompt-fix, drop A1 in a small follow-up. Save the lines of code.
   - **Directive wording iteration for W12.A levels.** The Light/Medium/High strings are shipped as-proposed; user can refine post-empirical-data if any level is too aggressive or too soft on real dictations.

### P1 — Functional bug fixes + small polish follow-ups

2. [ ] **Task #13 — RecorderStylePicker selection bug.** User reported the Interface picker (Halo Notch / Halo Floating / Constellation) at `SettingsView.swift:321` doesn't actually switch the active recorder. Picker is bound to `$recorderUIManager.recorderType`. Need to trace whether (a) the `@Published` write fires, (b) the recorder window observer reacts, (c) the actual recorder swap happens. ~30 min investigation.
3. [ ] **AppNotificationView shake/pulse motion.** W13.G spec §1.X.W13.7 promises `.haloShake()` on present for `.error`/`.warning` + `.haloPulse()` on `.success`, but coder shipped without motion (color is doing primary discrimination). Either implement the motion modifiers OR soften the spec to "iconography discriminates; motion reserved for future evolution." 1-line spec edit OR ~30 LOC motion impl.
4. [ ] **W13.B3 — PerformanceAnalysisPanelView per-tile rainbow refs.** W13.G axis I covered the chrome (lines :20/:69-71/:107-114) but the per-section model headers at lines `:171/185/199/208/244/251` still use rainbow tints. Small follow-up packet (~15 LOC).
5. [ ] **W13.E2 — AddCustomModel/APIKeyManagement/LanguageSelection.** Aesthetic unification on the 3 surfaces W13.E explicitly deferred. Small follow-up packet (~50 LOC).

### P2 — Brainstorm-then-plan (UX/feature decisions)

6. [ ] **Task #14 — Tabbed-settings UX (potential W13.H).** User proposed tabbed Settings nav with config-availability highlights (e.g. tab is highlighted if user has configured that section). Replaces the 2-column grid layout. Substantive IA change — needs `superpowers:brainstorming` pass first to scope, then a per-packet plan, then impl. NOT a polish packet.
7. [ ] **W11.C — speculative decoding revisit.** Three forward options: (a) fork `pu-foyer/speculative-decoding` + bump `mlx-swift-lm` to 3.x + patch source breaks, (b) port the algorithm in-tree against mlx-swift-lm 3.x primitives (~500-1000 LOC), (c) wait for upstream (last commit 2025-12-08; active repo). Cost/benefit only worth revisiting if the user's CSV data shows MLX path is the dominant slow surface — AFM is primary on macOS 26+ so spec-decode mostly helps the AFM-disabled fallback path.

### P3 — Infrastructure carryover (separate session)

8. [ ] **Test infrastructure unblock (Q10 carryover).** `xcodebuild test` env-block: macros-trust prompt + Mac Development cert team V6J6A3VWY2 not in keychain + IPC bootstrap on unsigned bundle. User-machine fix; needs interactive auth flows. Separate session.
9. [ ] **Drop legacy `isAIEnhancementEnabled` Codable encode.** Per W12.A Migration policy #3, drop the legacy bool encode 3 months post-merge (2026-07-30). One-line edit in `PowerModeConfig.swift` + `AIEnhancementService` + `PowerModeSessionManager.ApplicationState`. Schedule a future-self reminder.

## Context the Next Session Needs

- **CLAUDE.md is loaded automatically.** Same rules: spawn TEAMMATES via `TeamCreate` + `Agent({team_name, name})`; skip per-packet builds (single integration build at merge time); never commit without explicit user approval (this session was explicit "you can push the commits to origin main, yes" upfront — verify scope per session); never `git push --force`; close teammates the moment they finish.
- **Worktree convention:** `.worktrees/<branch-name>/`. Use ABSOLUTE paths for `git worktree add` to avoid cwd-drift. **Brief every coder spawn with the worktree-prefix rule + pre-edit `git -C <main> status` guard** (recurring foot-gun across sessions).
- **Build:** `make local` from main path. App lands at `~/Downloads/VoiceInk.app`. `Makefile:73` has `-skipMacroValidation` flag (required for MLXHuggingFaceMacros).
- **Code-signing:** local self-signed `voiceink-fork-local` cert. `xcodebuild test` env-blocked (carryover).
- **Xcode 16 PBXFileSystemSynchronizedRootGroup:** files dropped under `VoiceInk/` and `VoiceInkTests/` auto-included; no pbxproj edits needed for new files.
- **Spec is source of truth:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` — extended in-place by W13.G with §1.X.W13.1-9 + §2.4-W13 halo token mapping. Future aesthetic packets reference these new sections.
- **Plan files committed alongside impl:** match the W3/W5/W6/W7/W11A/W12A/W13A pattern (two commits per packet — `docs(plans): WX — …` first, then `feat(…): WX — …` after impl review-approve-build).
- **Memory:** auto-memory at `~/.claude/projects/-Users-priyanshu-Desktop-Projects-pu-voiceink-fork/memory/` includes `feedback_skip_per_packet_builds.md`, `feedback_no_confirmation_trivial.md`, `project_strip_monetization.md`. All honored this session. Consider adding a new memory: "directive injection sites must be inside strong framing — never prepend outside `<SYSTEM_INSTRUCTIONS>`."
- **Telemetry CSV columns** (W11.D): `timestamp, modelId, promptMode, inputChars, outputChars, prepSeconds, ttftSeconds, genSeconds, totalSeconds, gapSinceLastSeconds, outcome`. promptMode enum: `standard | fastPath | kvCacheReuse | afm | specDecode` (specDecode reserved but unreachable while W11.C is deferred).
- **Provider routing summary (current):** user selects `.mlx` → AFM-first if `SystemLanguageModel.default.isAvailable`, MLX fallback on `safetyRefusal` only. User selects `.foundationModels` → AFM directly. User selects remote API provider → unchanged. (This was W11.B's design; nothing changed in Phase 2/3.)
- **Multi-packet shared-infrastructure conflict pattern:** TranscriptionPipeline + HotkeyManager + AppDefaults + VoiceInk.swift Schema were touched by 4+ packets each. Future phases that re-touch these need explicit sequencing — order merges by least-impact first, rebase later packets onto each prior merge, resolve conflicts manually combining each packet's intent.
- **AppNotificationView aspiration:** spec §1.X.W13.7 promises shake/pulse motion not yet implemented. Either implement (small follow-up) or soften the spec wording.
- **W13.E + W13.G deferred items:** AddCustomModel/APIKeyManagement/LanguageSelection (W13.E2) + PerformanceAnalysisPanelView per-tile rainbows (W13.B3). Both are small follow-up packets if the user wants closure on remaining aesthetic items.

### Lead's pending questions for the user (next session opens)

If the new session opens cold, ask explicitly:

1. **Push status confirmation:** `db14e5f` is on origin/main. Anything to roll back? (Default: no, ship it.)
2. **Empirical capture:** has the CSV been populated since last session? If yes, paste rows; lead reads + decides A1 prewarm fate.
3. **Bug fix priority:** RecorderStylePicker (Task #13) is a real user-facing bug. Schedule it before any new feature work.
4. **Polish follow-ups:** W13.B3 + W13.E2 + AppNotificationView motion — bundle as one W13.H polish packet, or do separately, or defer indefinitely?
5. **Tabbed-settings UX (Task #14):** brainstorm now or hold?
6. **W11.C revisit:** still deferred unless CSV evidence motivates a forward option.

---

**Tip for the next session:** The `superpowers:dispatching-parallel-agents` flow + the per-packet plan-then-impl-then-review cadence proved out across 12 packets this session. Worktree-per-packet + sequential merges + rebase-on-conflict is the canonical pattern. Don't break it. The cwd-drift foot-gun is a hard liability — any new coder briefs MUST have the worktree-prefix rule explicitly stated.

Handoff saved: `docs/superpowers/handoffs/HANDOFF_phases23_complete_2026-04-30.md`

Start next session with:
> Read `docs/superpowers/handoffs/HANDOFF_phases23_complete_2026-04-30.md` and continue from where the last session left off.
