# Phase tracking — W11 / W12 / W13 implementation packets

**Source plan:** `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` (decisions §0)
**Live status:** `docs/superpowers/STATUS.md`
**Started:** 2026-04-29 · last updated: 2026-04-30 (Phases 2 + 3 COMPLETE — modulo deferred items)

Status legend: ⬜ pending · 🟡 in_progress · ✅ done · ⏸ blocked / deferred

---

## Phase 1 — W11 (enhance speed real fix)

| Packet | Status | Notes |
|---|---|---|
| **W11.A** — pipeline fixes (A1+A2+A4+A5+A6+A7) | ✅ | Merged 2026-04-29 (`84ac7bf`). A3 deferred. |
| **W11.A.A3 follow-up** — KV-cache reuse for system prefill | ✅ | Merged 2026-04-30 (`201fb8f`). Path B token-diff splitter, gated behind `MLXKVCacheReuseEnabled` UserDefault (default off). chatml templates → full benefit; legacy `[INST]<<SYS>>` skipped via `n<32` floor → standard fallback. CSV writes `promptMode=kvCacheReuse` on hits. |
| **W11.D** — Enhancement timing telemetry (new) | ✅ | Merged 2026-04-30 (`42edcbe`). CSV at `~/Library/Application Support/<bundle>/enhancement-timings.csv`; diagnostic logs for fastPath/prewarm/idle-evict/timeout; UI buttons in Settings. |
| **W11-prompt-fix** — MLX prompt-wrap correctness | ✅ | Merged 2026-04-29 (`3247736`). Unblocks empirical perf measurement (broken prompt was masking timing differences). |
| **W11-models-expand** — registry + auto-detect cache | ✅ | Merged 2026-04-29 (`14f092a`). 5 new curated entries + `MLXModelDownloader.detectInstalledModels()` + DETECTED picker section. |
| **W11.B** — Apple Foundation Models primary path | ✅ | Merged 2026-04-30 (`e228f73`). Deployment target 14.4 → 26.0. AFMProvider replaces FoundationModelsProvider. Routing: AFM-first when `SystemLanguageModel.default.isAvailable`; only `safetyRefusal` falls back to MLX silently, other errors propagate. AFM prewarm wired. CSV `promptMode=afm` populated. Live AFM-disabled fallback path not exercised pre-merge (deferred to user-machine validation). |
| **W11.C** — Speculative decoding opt-in (MLX fallback) | ⏸ | **Deferred 2026-04-30** (no commit; worktree clean). Upstream `mlx-community/speculative-decoding` Package.swift pins `mlx-swift-lm from: "2.29.2"` (<3.0.0 ceiling) — irreconcilable with our `exactVersion 3.31.3` pin needed for qwen3 model_type, KV-cache APIs (W11.A.A3), and `swift-huggingface` 0.9.0 cache layout. Forward options (each its own future packet): (a) fork to `pu-foyer/speculative-decoding` + bump its mlx-swift-lm dep to 3.x and patch any 2→3 source breaks, (b) port the algorithm in-tree against mlx-swift-lm 3.x primitives (~500-1000 LOC), (c) wait for upstream — repo active, last commit 2025-12-08. |

**Phase 1 status — DONE (modulo W11.C upstream blocker):**
1. ✅ W11.D timing telemetry (merged `42edcbe`)
2. ✅ W11.A.A3 KV-cache reuse (merged `201fb8f`, opt-in)
3. ✅ W11.B AFM primary path (merged `e228f73`, deployment target → macOS 26.0)
4. ⏸ W11.C spec-decode opt-in — deferred (upstream SPM SemVer conflict; not a decision we can make on our side)

→ Ready to proceed to Phase 2 (Wispr Flow parity) per master plan §6.

---

## Phase 2 — W12 (Wispr Flow parity)

| Packet | Status | Notes |
|---|---|---|
| **W12.A** — Auto Cleanup levels + diff + Undo | ✅ | Merged 2026-04-30 (`3bf3013`). New `EnhanceLevel` enum (None/Light/Medium/High) replaces stored `isAIEnhancementEnabled: Bool` on `PowerModeConfig` + `AIEnhancementService` via dual-key Codable (decode prefers enum, falls back to legacy bool → .medium/.none; encoder writes both keys for ≥3-month downgrade tolerance) + derived computed `isEnhancementEnabled` accessor (~64 in-tree bool readers compile unchanged). Per-level system-prompt directive injected at front of `customPromptTemplate` body via new `AIPrompts.cleanupDirective(for:)`. `WordDiffEngine.tokenLevelDiff(...) -> [DiffOp]` sibling. `TranscriptionDetailView` gains Panes/Diff 2-segment picker + AttributedString inline diff (insertions `Palette.success` underline, deletions `Palette.warn` strikethrough) + "Undo AI edit" button (clears `enhancedText` + 5 metadata fields, no confirm dialog). Pickers placed at 3 surfaces: global Settings (segmented), recorder-side panel (new top Section), per-PowerMode card (inside existing `aiEnhancementCard`). Master plan correction: `Transcription.text` (raw) + `.enhancedText` already coexisted — no SwiftData migration needed. |
| **W12.B** — Command Mode | ✅ | Merged 2026-04-30 (`852a613`). Caps+9 (Hyper+9) global hotkey → CommandModeService captures selection via SelectedTextService → recorder opens → user dictates instruction → AIEnhancementService.commandModeRewrite splices instruction INSIDE customPromptTemplate's <SYSTEM_INSTRUCTIONS> (W12.A 0759019 lesson honored) → CursorPaster.pasteAtCursor replaces selection (Cmd+V stamps undo on source app stack so system Cmd+Z restores). Provider routing parity with enhance(). Banner pill above recorder + menubar status row. Transcription gains additive optional commandModeSelection + commandModeInstruction. wasCommandMode hoisted for autoSend gate (rewrites never auto-Enter). |
| **W12.C** — Voice Snippets (text expansion) | ✅ | Merged 2026-04-30 (`7cda954`). New SwiftData @Model Snippet (trigger/expansion/tags/isEnabled/timestamps) registered in 3 schema sites. SnippetExpansionService (@MainActor, .shared) with cache + fetchCount probe + manual invalidate. Word-boundary regex (?:\b\|^\|(?<=\s))<escaped>(?:\b\|$\|(?=\s)) handles non-word-leading triggers (`;sig` `:date` `/code` `@addr`). Trigger pattern `^[A-Za-z0-9;:_./@-]{1,32}$` (incl `:`); case-sensitive matching + uniqueness. Pre-enhance splice in TranscriptionPipeline between WordReplacement + AVURLAsset duration — additive, byte-identical when no snippets. New sidebar entry .snippets + SnippetsSettingsView (W5 SettingsCard) + SnippetEditorSheet w/ inline collision rejection. ImportExportService extended via SnippetExportData. |
| **W12.D** — Hands-free + VAD + voice "press enter" | ✅ | Merged 2026-04-30 (`eeee9a5`). KeyboardShortcuts.Name.handsFreeToggle UNBOUND on first run. RMS-gated VAD off Recorder.audioMeter (no silero streaming, no new SPM). Each utterance = separate Transcription row via VoiceInkEngine.commitUtterance(restartAfter:) with bounded spin-wait drain. Post-enhance trigger filter (default `["press enter","submit","send it","send message"]`, case-insensitive whole-suffix match) strips suffix + fires CursorPaster.performAutoSend(.enter) once. 20-min hard cap with auto-stop. Menubar IconState.handsFree (ear.fill, accent-tinted). HandsFreeSettingsView w/ VAD threshold (Low/Med/High = -50/-40/-30 dBFS), silence duration (Quick/Standard/Patient = 1.0/1.5/2.5s), trigger phrase editor. Recorder behavior outside hands-free byte-identical via state != .inactive gates. Sleep observer registered on NSWorkspace.shared.notificationCenter (post-revise C1 fix). |
| **W12.E** — Scratchpad | ✅ | Merged 2026-04-30 (`06242da`). New ⌥+S window with multi-tab + auto-save + 50-version history; doubles as paste-fallback target. 9 new files (ScratchpadDocument @Model, ScratchpadVersion @Model, ScratchpadStore, ScratchpadModelContainerProvider, ScratchpadWindowController, ScratchpadWindow, ScratchpadView, ScratchpadTabEditor, ScratchpadVersionHistorySheet). Tab cap 10 user-created (paste-fallback bypasses for data preservation). Title auto-derived from first 30 chars. Autosave 800ms debounced + flushAll on windowWillClose. Version snapshots every 30s active typing OR tab switch / window close, FIFO evict at 50. Restore is capture-then-replace (reversible). Plain text only. Paste-fallback appends NEW tab in CursorPaster's mustForceClipboard branch ONLY. Dictation-into-place gates BEFORE pasteAtCursor with autoSend suppression. |

---

## Phase 3 — W13 (aesthetic unification)

| Packet | Status | Notes |
|---|---|---|
| **W13.A** — token sweep | ✅ | Merged 2026-04-29 (`e196cda`). 26 files swept across A/B/F axes. C/E/F deferrals routed to later packets. |
| **W13.B** — Metrics dashboard rebuild | ✅ | Merged 2026-04-30 (`25d8bcb`). Hero gradient SHAPE preserved per Q9=a — only source color swaps `Color(nsColor: .controlAccentColor)` → `Palette.accent` (alphas 1.0/0.85/0.70, .topLeading→.bottomTrailing, 24pt + drop shadow byte-identical). MetricCard wraps in `GlassCard(cornerRadius: 16)` and DROPS the `color: Color` parameter at type level (single `Palette.accent` icon tint, all 4 cards). HelpAndResourcesSection swaps to `glassPanel(cornerRadius: 16)` outer + `glassChip(cornerRadius: 10)` inner link rows. CopySystemInfoButton: `Capsule().fill(.thinMaterial)` → `glassChip(cornerRadius: 18)` soft-pill + 5× `spring(0.3, 0.7)` → `Animation.haloExpand`. `.rounded` font dropped from this surface entirely. Adjacent surfaces (`MetricsSetupView`, `PerformanceAnalysisView`, `PerformanceAnalysisPanelView`) deferred — out of W13.B scope. |
| **W13.C** — Permissions + AudioTranscribe | ✅ | Merged 2026-04-30 (`c2ad3aa`). PermissionCard hand-rolled glass → GlassCard(cornerRadius: 14, padding: 20). AudioTranscribeView drop-zone → glassPanel(cornerRadius: 14) + dashed Palette.hairlineSoft strokeBorder + Palette.accent overlay on hover. topBar Add/Clear → glassChip(10); Cancel → Palette.warn glassChip; Start → solid Palette.accent Capsule + accentGlow shadow (primary CTA pattern). AudioFileRow palette swaps only (Form host preserved for W13.D). 4× expand/collapse + clearAll + lastCompleted onChange → Animation.haloExpand. |
| **W13.D** — Form-host purge | ✅ | Merged 2026-04-30 (`864e827`). Largest diff in W13. 5 Form { Section } surfaces purged: EnhancementSettingsView (3 SettingsCards + gear+plus ZStack overlay top-right), EnhancementSettingsPanel popover (flat sectionBlock×7 + sectionFooter — NO SettingsCard, avoids double-glass), PromptEditorView (sectionBlock×3-4 each pane inside editorPane GlassCard), InlineHistoryView cardListView (ScrollView/LazyVStack/GlassCard(14)), AudioTranscribeView queue (queueFormView → queueListView rename + GlassCard(14)). APIKeyManagementView transitive Section→SettingsCard envelope swap. Behavior preservation verified per-surface; every Toggle/Picker/Button/drag-and-drop/alert/popover/panel/expansion/@AppStorage byte-identical. User-flagged AI Enhancement 2-grid layout fixed by this packet. |
| **W13.E** — AI Models cards | ✅ | Merged 2026-04-30 (`5424882`). 5 card files (Whisper incl. ImportedWhisper, Cloud, FluidAudio, Native, Custom) + MLXModelPickerView. Cards with expand-state (Cloud/Custom) use GlassCard(16, padding: 0) preserving inner per-section padding; single-section cards use GlassCard(16, 16) and drop inline padding. Active stroke Palette.accent.opacity(0.55) lineWidth 1.5; rest stroke Palette.hairline lineWidth 1. Capsule CTAs retinted Palette.accent; verify-success → Palette.success. Cloud Divider → Palette.hairlineSoft. WhisperModelManager DownloadProgressView retint inline (track hairlineSoft, fill accent). ProviderCard preserved (vocab-clean since W6). AddCustomModel/APIKeyManagement/LanguageSelection deferred as W13.E2. |
| **W13.F** — History window glass + animation codemod | ✅ | Merged 2026-04-30 (`e040e03`). HistoryWindowController:54 mirror WindowManager.configureWindow flags (isOpaque=false, backgroundColor=.clear). TranscriptionHistoryView 3 sub-pane fills swept (analysis-panel overlay dropped, right-sidebar empty state + selectionToolbar → HaloMaterial(.hidden)). Search field RR8 + .thinMaterial + .padding(10) → glassChip(cornerRadius: 8). 5× .smooth(duration: 0.3) → Animation.haloExpand. PerformanceAnalysisPanelView opaque chrome flagged as W13.B residual debt (folded into W13.G). |
| **W13.G** — Polish + spec extension | ✅ | Merged 2026-04-30 (`4e17cee`). FINAL Phase 3 packet. 9 axes across 15 source files + spec amendment. Axis A: CompactHeroSection .blue → Palette.accent. Axis B: AppNotificationView 3-color palette per lead lock (error/warning Palette.warn, info Palette.accent, success Palette.success — NOT plan's single-accent default). Axis C: 7 chip-affordance closing pass (CopyIconButton, SaveIconButton, HistoryShortcutTipView, EnhancementShortcutsView, AudioInputSettings priority chip, PowerModeConfigView, DictionaryQuickAddPanel) — inlined glass recipe on small geometries where modifier padding would balloon. Axis D: TriggerWordItem glassChip(10), EnhancementPromptPopover glassPanel(14) + dropped forced-dark, PredefinedPromptsView GlassCard(16). Axis E: CustomPrompt.promptIcon family rebuild (radial-glow + decorative circles DELETED, replaced with GlassCard(14, 0) + 1.5pt selection ring + accent glow rad 18; method signature byte-identical). Axis F: PowerModeView heroHeader → SettingsSectionHeader(icon: bolt.fill, accent: Palette.warn). Axis G: PromptChipPicker 2-phase + PowerModeStripView breathing/drag SANCTIONED in spec §1.X.W13.9. Axis I: PerformanceAnalysisPanelView fold-in (lines :20/:69-71/:107-114; per-tile rainbow refs at :171/185/199/208/244/251 LEFT for W13.B3 follow-up). Spec amendment APPENDED in-place to 2026-04-28-aesthetic-redesign.md: §1.X.W13.1-9 (9 subsections) + §2.4-W13 halo token mapping. AppNotificationView shake/pulse motion deferred follow-up (spec aspiration). |

---

## Carryover (separate sessions)

- Test-infrastructure unblock — `xcodebuild test` env-blocked (Mac Development cert + macros-trust + IPC bootstrap). User-machine fix.
- Push to origin — currently 45 commits ahead; user pushes manually.

---

## How this doc updates

- After each packet merges to `main`, flip its row to ✅ + record the merge commit short-SHA.
- Phase 1 row order = sequencing order. Phase 2/3 row order = recommended dispatch order from master plan §6.
- New packets discovered mid-phase get inserted into their phase table with a `(new)` annotation.
- Carryover items only move out of "carryover" if user explicitly redirects.
