# W13.D — Form-host purge (5 surfaces) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` for executing tasks task-by-task. Reviewer: `superpowers:code-reviewer`. Steps use checkbox (`- [ ]`) syntax.

**Date:** 2026-04-30
**Author:** planner-w13d (team `voiceink-phase23`, task #20)
**Scope:** Five surfaces still on `Form { Section { } }` get migrated to the W5 `ScrollView { LazyVStack { SettingsCard } }` (or, where appropriate, a flat `LazyVStack { GlassCard }`) idiom. **Largest diff in W13** — five files touched, ~400-700 net LOC delta. Behavior must be byte-identical: every Toggle / Picker / Button / drag-and-drop wires to the same state, in the same order.

**User-driven priority:** the user just flagged the AI Enhancement layout (the 2-grid Form) as bad-looking. EnhancementSettingsView is the marquee surface; the rest of this packet's work flows from the same idiom swap.

**Sources of truth:**
- R4 audit (the WHY for each rebuild): `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md` §1 row 3, §3 rows 9, 15, 18, 22, 26, §3.1 "`Form { Section }` host" pattern, §4 W13-D.
- Master plan §4 W13.D: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`.
- Sibling shapes: `docs/superpowers/plans/W13A-token-sweep.md` (Sweep/Defer/Flag table style), `docs/superpowers/plans/W13B-metrics-rebuild.md` (per-surface task structure). W13.D is bigger than both — five tables instead of one.
- Pattern to copy: `VoiceInk/Views/Settings/SettingsView.swift:51-71` — the canonical `ScrollView { LazyVStack(spacing: 16) { SettingsCard {...} } }` host that abandoned Form at W5.
- Vocabulary primitives: `VoiceInk/Views/Common/{SettingsCard.swift, SettingsRow.swift, SettingsSectionHeader.swift, GlassCard.swift, GlassChip.swift, Palette.swift, Animation+Halo.swift, AdaptiveGlassBackground.swift}`.
- Spec refs: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens), §2.5 (icon vocabulary), §3.3 (settings card pattern), §6.4 (Reduce-Transparency contract).

**Goal:** every main-app `Form { Section { } header: { SettingsSectionHeader } } .formStyle(.grouped) .scrollContentBackground(.hidden)` host is gone. After this packet, `rg -n 'formStyle\(\.grouped\)' VoiceInk/Views/` returns zero hits in the five target surfaces. The five surfaces speak the same vocabulary as `SettingsView` (W5) — glass cards on the wallpaper-backed pane, no double-layered Form chrome.

**Locked decisions honored:**
- **Behavior preservation is non-negotiable.** Every Toggle, Picker, Button, drag-and-drop, alert, popover, panel, expansion-state, and `@AppStorage` binding continues to function identically. This is a visual-only restructure.
- **No SettingsCard primitive edits.** The primitive is W5's locked vocabulary. If a popover surface needs tighter padding, the consumer uses raw `GlassCard(cornerRadius: 14, padding: 12)` directly — see Risk #1.
- **No spec amendments in this packet.** If a primitive doesn't fit a surface, FLAG and use a documented `GlassCard` direct-use; spec evolution is W13.G's job.
- **W13.C overlap on AudioTranscribeView:** W13.C styles the drop-zone chrome and topBar pill buttons. W13.D purges the queue Form. **W13.D's edits to `AudioTranscribeView.swift` are scoped to lines 98-141 (queueFormView) only.** If W13.C merges first, W13.D rebases its other edits and re-runs Task 0 grep validation. If W13.D merges first, W13.C rebases and re-runs its grep. Coordination via team-lead at merge time.

---

## Prelude — packet shape + commit etiquette

**Shape.** Single coder + reviewer pair under team `voiceink-phase23` post-sign-off (per CLAUDE.md "fresh teammate per task"). Diff bounded to **five Swift files** (`EnhancementSettingsView.swift`, `Components/EnhancementSettingsPanel.swift`, `PromptEditorView.swift`, `History/InlineHistoryView.swift`, `AudioTranscribeView.swift`) plus this plan file plus `AI Models/APIKeyManagementView.swift` (transitively — see Risk #2). Estimated total LOC delta: ~400-700 net edited (insertions roughly balanced by deletions); the five Form blocks shrink, the five LazyVStack blocks expand. No new files. No new SPM deps. No new tokens beyond what `Palette.swift` / `SettingsCard.swift` already expose. No deployment-target change. No test-infra change.

**Commit cadence per `feedback_skip_per_packet_builds.md`.** Coder leaves edits uncommitted in the worktree. Lead runs single integration `make local` at merge time and commits:
```
docs(plans): W13D — Form-host purge (5 surfaces)
feat(aesthetic): W13D — Form-host purge (5 surfaces)
```
Coder does NOT commit. Coder does NOT run `xcodebuild` per task. The integration build is the gate.

**Worktree convention.** Spawn at `.worktrees/w13d/` ABSOLUTE path. Always `cd <main-repo>` before `git worktree add` to avoid cwd-drift.

**Comment policy.** Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code. Inline doc-comments may cite spec §1 / §3.3 + this plan path. Pre-existing spec-ref comments preserved verbatim (`SettingsCard.swift:21-23` "Form-chrome mitigation" comment is the canonical motivation; this packet realizes its second wave).

**Visual verification.** Verified by **screenshot diff per surface**, not by automated tests. Coder runs the visual smoke per Task 12; user runs the post-merge protocol per §Post-merge verification.

**W13.C overlap.** Both packets touch `AudioTranscribeView.swift`. To prevent merge collisions:
- W13.D edits ONLY `queueFormView` body (lines 98-141), the inline `Form` block.
- W13.D LEAVES `emptyStateView` (drop-zone, lines 50-94), `topBar` (lines 144-241), `dropOverlay` (lines 282-297), and the various pill buttons untouched. Those are W13.C territory.
- If W13.C lands first, the file shape may have shifted — re-run Task 0 grep to confirm `Form { … }` block is still in scope.

---

## Per-surface Sweep / Defer / Flag tables

Five tables, one per surface. Each row is one observable concern × disposition. **Sweep** = land in W13.D. **Defer** = explicitly route to a different W13 packet. **Flag — preserve / coder evaluates** = no edit; either spec-canonical already, or context-dependent.

### Surface 1 — `EnhancementSettingsView.swift` (full Form purge — marquee)

**File:** `VoiceInk/Views/EnhancementSettingsView.swift` (~313 lines).

**Current shape:** `Form { Section "Enhancement" { Cleanup-Level VStack } header: { SettingsSectionHeader + gear button }; APIKeyManagementView() (returns its own Section); Section "Enhancement Prompts" { ReorderablePromptGrid } header: { SettingsSectionHeader + plus button } } .formStyle(.grouped) .scrollContentBackground(.hidden) .adaptiveGlassBackground() .slidingPanel(...)`.

**Target shape:** `ScrollView { LazyVStack(spacing: 16) { enhancementCard; aiProviderCard; promptsCard } .padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: 720) } .adaptiveGlassBackground() .slidingPanel(...)`.

| # | Concern | File:line | Current | W13.D Action | Disposition | Rationale |
|---|---|---|---|---|---|---|
| S1.1 | Form host | `:53, :170-172` | `Form { … } .formStyle(.grouped) .scrollContentBackground(.hidden)` | Replace with `ScrollView { LazyVStack(spacing: 16) { … } .padding(.horizontal, 24).padding(.vertical, 20).frame(maxWidth: 720).frame(maxWidth: .infinity) }` mirroring `SettingsView.swift:51-69` | **Sweep** | Master plan §4 W13.D first bullet; spec §3.3; SettingsCard.swift:21-23 form-chrome mitigation note. |
| S1.2 | "Enhancement" Section + gear-button header | `:54-110` | Section with Cleanup Level Picker body + composite header (SettingsSectionHeader **plus** gear button outside the header card) | Wrap Cleanup Level body in `SettingsCard(iconSystemName: "wand.and.stars", iconTint: Palette.accent, title: "Enhancement", subtitle: "Pass transcripts through an LLM before pasting.", statusText: enhancementService.enhanceLevel.displayName, statusTone: enhancementService.enhanceLevel == .none ? .neutral : .positive) { /* picker + level description */ }`. Gear button sits OUTSIDE the SettingsCard, in an HStack alongside it (or as a row inside the card). **Recommended:** put the gear button as a trailing affordance in the card header by overlaying it on the card top-right (preserves spatial association); fallback is row-inside. See Open Question #1. | **Sweep** | Behavior preservation: gear button still toggles `isShowingSettings`; SettingsSectionHeader's status pill takes the level-display string. |
| S1.3 | Cleanup Level picker body | `:55-76` | `VStack { HStack { Text "Cleanup Level" + InfoTip + Spacer }; Picker(.segmented); Text(level.description) }` | KEEP body; relocate inside the SettingsCard's content closure. Drop the inline `Text("Cleanup Level")` heading — the SettingsCard's title now reads "Enhancement" and the picker is the only control. **Alternative:** keep the inline heading if visual rhythm suffers. Coder picks at smoke-test (Task 12). | **Flag — coder picks** | Master plan locked decision Q6=a (4-level picker stays). |
| S1.4 | Gear-button chrome | `:87-107` | `Image gear ... .background(RoundedRectangle 8 .fill(.ultraThinMaterial)).overlay(stroke Palette.hairline)` | KEEP byte-identical. (W13.A flagged this for sweep but explicitly deferred to W13.D `Form-internal hits`. W13.D's job is the Form purge, NOT polishing the button chrome — that's still future polish.) | **Flag — preserve** | W13.A defer routing: `:88, :145` are inside-Form hits. W13.D leaves them alone. Polish lands in W13.G. |
| S1.5 | `APIKeyManagementView()` Section adaptation | `:112-113` (call site) + transitively `AI Models/APIKeyManagementView.swift:88-145` | Returns root `Section { … } header: { SettingsSectionHeader }` — currently meant to be embedded in a Form | **Reshape APIKeyManagementView's body to return `SettingsCard { … }` directly** (drop the `Section`/`header` envelope). Parent call site at `:112-113` becomes `aiProviderCard: aiProviderCard` (the now-`SettingsCard`-shaped child). Opacity treatment (`.opacity(0.8)` when `isEnhancementEnabled` false) is preserved on the parent's call site. | **Sweep** | Single call site (`grep -rn 'APIKeyManagementView()'` returns one hit — `EnhancementSettingsView.swift:112`). Reshaping is local. **Behavior:** the inner `LazyVGrid` of `ProviderCard`s + `expandedProvider` `@State` + `.onAppear` pre-expand logic stays unchanged. |
| S1.6 | "Enhancement Prompts" Section + plus-button header | `:115-168` | Section with ReorderablePromptGrid body + composite header (SettingsSectionHeader **plus** plus button) | Wrap in `SettingsCard(iconSystemName: "text.bubble", iconTint: Palette.accent, title: "Enhancement Prompts", subtitle: "Pick the active style; reorder by drag.", statusText: "\(enhancementService.customPrompts.count)", statusTone: .neutral) { /* ReorderablePromptGrid */ }`. Plus button placement same trade as S1.2 — recommended trailing-affordance overlay; row-inside fallback. | **Sweep** | Master plan §4 W13.D first bullet; behavior preservation: plus button still triggers `openPromptPanel()` + flips `isEditingPrompt`. |
| S1.7 | ReorderablePromptGrid body | `:217-283` | `LazyVGrid` of `prompt.promptIcon(...)` with drag-and-drop and `PromptDropDelegate` | KEEP byte-identical. The grid is content; SettingsCard wraps it. The `.padding(.vertical, 8)` outer padding at `:131` may or may not need to drop (SettingsCard provides 18pt padding). Coder picks at Task 12. | **Flag — preserve, smoke-test padding** | The internal `.spring(0.3, 0.7)` at `:233` and `.easeInOut(0.15)` at `:251` and `.easeInOut(0.12)` at `:297` are **deferred to W13.A's regression catch** if they were missed; for W13.D scope they STAY (these are PromptDropDelegate animations, deeply tied to drag-state UX). Animation codemod is NOT W13.D's job. |
| S1.8 | `.opacity(.0.8)` enabled-gating wrapper | `:113, :169` | `.opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)` on Sections 2 + 3 | KEEP byte-identical, applied to `aiProviderCard` and `promptsCard` instead of Sections | **Sweep — preserved semantics** | UX: dim when enhancement off. Stays. |
| S1.9 | `slidingPanel` modifier | `:174-201` | `.slidingPanel(isPresented:..., width: currentPanelWidth) { ... }` — wires settings + prompt-editor panes | KEEP byte-identical. Hosts the panels. Stays at the outermost layer (after `.adaptiveGlassBackground()`). | **Flag — preserve** | Independent of Form purge. |
| S1.10 | `.frame(minWidth: 500, minHeight: 400)` | `:202` | minimum frame | KEEP — outer frame stays. The new `ScrollView` is unbounded vertically; min frame stays. | **Flag — preserve** | Window-fit. |
| S1.11 | `closePanel()` `.smooth(0.3)` animation | `:45` | `withAnimation(.smooth(duration: 0.3))` | LEAVE for W13.A (Form-internal animation, deferred there at `:45`). | **Defer → W13.A polish** | W13.A explicitly defers `EnhancementSettingsView:45, 76, 88, 111, 132, 221, 239, 285` animations to W13.D for atomic review — but the W13.D scope per master plan §4 is Form purge, not animation codemod. Recommendation: leave for W13.G or a follow-up. Coder may choose to swap inline if zero risk; default is preserve. |

**Deferred (route to other packets):**

| Item | Routes to | Reason |
|---|---|---|
| Animation literals at `:45, :76, :88, :111, :123, :132, :144, :221, :239, :251, :285, :297` | **W13.A regression catch** | W13.A flagged but didn't sweep these; W13.D is Form purge, not animation grammar. Re-route to W13.A polish or W13.G. |
| `.ultraThinMaterial` chrome on gear/plus buttons (`:88, :145`) | **W13.G** | W13.A flagged; not in W13.D's Form-purge scope. |

### Surface 2 — `EnhancementSettingsPanel.swift` (popover Form purge — TRICKIEST FIT)

**File:** `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` (~351 lines).

**Current shape:** `VStack(spacing: 0) { headerHStack (custom — title + xmark close button) .adaptiveGlassBackground(intensity: .panel); Form { Section "Cleanup Level" { Picker.segmented + level.description }; Section "Context" { Toggle clipboard, Toggle screen capture }; Section "Skip Short Transcriptions" (un-headed) { Toggle + chevron + expandable Picker }; Section "Request Timeout" { Picker timeout, Picker on-timeout-action }; if mlx/foundationModels { Section "On-device" { active-path indicator + Picker idle-eviction (mlx-only) + 2 buttons } footer "Each on-device enhancement appends..." }; Section "Shortcuts" { EnhancementShortcutsView() }; Section "Last Sent System Prompt" { LastSystemPromptViewer() } } .formStyle(.grouped) .scrollContentBackground(.hidden) } .tint(Palette.accent)`.

**Constraint:** This is the **popover** the recorder opens (or that EnhancementSettingsView opens via gear button — `slidingPanel` width 400pt). Different layout constraints than the full Settings page:
- 400pt-wide column (not 720pt — too narrow for SettingsCard's default 18pt padding + SettingsSectionHeader's 28pt icon tile + status pill on a single line).
- Already wrapped in a glass-backed pane (`SlidingPanel.swift:31` calls `.adaptiveGlassBackground(intensity: .panel)` on the panel container). Adding another `SettingsCard` (which wraps in `GlassCard` → `HaloMaterial(phase: .hidden)`) on top of that would **double-layer the glass material** — the exact failure mode the SettingsCard.swift:21-23 comment warns about.

**Resolution: do NOT use `SettingsCard` here.** Use a flat `LazyVStack` of un-carded section blocks, each prefixed by a compact section label. Section labels render as 11pt-mono uppercase tracked text (matching `MLXModelPickerView.swift:65-70` conventions and APIKeyManagementView's `sectionLabel(...)` at `:71-86`). The popover IS the card; sections are dividers within it.

**Target shape:** `VStack(spacing: 0) { headerHStack (preserved); ScrollView { LazyVStack(alignment: .leading, spacing: 20) { sectionBlock("CLEANUP LEVEL", info: "...") { picker + level.description }; sectionBlock("CONTEXT") { Toggle clipboard; Toggle screen }; sectionBlock("SHORT TRANSCRIPTIONS") { ... }; sectionBlock("REQUEST TIMEOUT", info: "...") { ... }; if mlx/foundationModels { sectionBlock("ON-DEVICE") { ... } sectionFooter("Each on-device enhancement...") }; sectionBlock("SHORTCUTS") { EnhancementShortcutsView() }; sectionBlock("LAST SENT SYSTEM PROMPT", info: "...") { LastSystemPromptViewer() } } .padding(.horizontal, 20).padding(.vertical, 16) } } .tint(Palette.accent)`.

| # | Concern | File:line | Current | W13.D Action | Disposition | Rationale |
|---|---|---|---|---|---|---|
| S2.1 | Form host | `:56, :265-266` | `Form { … } .formStyle(.grouped) .scrollContentBackground(.hidden)` | Replace with `ScrollView { LazyVStack(alignment: .leading, spacing: 20) { … } .padding(.horizontal, 20).padding(.vertical, 16) }`. Drop `.formStyle(.grouped)` and `.scrollContentBackground(.hidden)`. | **Sweep** | Master plan §4 W13.D second bullet. |
| S2.2 | Header HStack at `:18-53` | `:18-53` | `HStack { Text "Enhancement Settings" + Spacer + xmark close-button } .padding ... .adaptiveGlassBackground(intensity: .panel) .overlay(Rectangle hairline)` | KEEP byte-identical. Header stays as-is — popover top chrome. | **Flag — preserve** | Independent of Form purge. The `.ultraThinMaterial` close-button at `:33-40` is W13.G polish per W13.A defer. |
| S2.3 | Section "Cleanup Level" with InfoTip header | `:56-76` | Section with picker + description body, header `HStack { Text + InfoTip }` | Replace with `sectionBlock(label: "CLEANUP LEVEL", info: "None pastes raw transcripts. Light removes fillers. Medium fixes grammar. High polishes for clarity.") { VStack { picker.segmented; Text(level.description) } }`. | **Sweep** | Behavior preservation: picker bound to `enhancementService.enhanceLevel`. |
| S2.4 | Section "Context" | `:78-96` | Section with two Toggles (clipboard, screenCapture) + header `Text("Context")` | Replace with `sectionBlock(label: "CONTEXT") { VStack(spacing: 12) { Toggle clipboard; Toggle screen } }`. Toggles remain `.toggleStyle(.switch)`. | **Sweep** | Behavior preservation: bindings to `enhancementService.useClipboardContext` and `useScreenCaptureContext`. |
| S2.5 | Section "Skip Short Transcriptions" (no header) | `:98-157` | Un-headed Section with VStack { HStack { Toggle binding + InfoTip + chevron rotation } + tap-gesture + conditional inner Picker { word threshold } } + animation tied to `isShortEnhancementExpanded` | Replace with `sectionBlock(label: "SHORT TRANSCRIPTIONS") { /* the existing VStack body, byte-identical */ }`. The InfoTip stays inline next to the Toggle label as in v1. | **Sweep** | Behavior preservation: Toggle binding logic (`isHandlingToggleChange` + animation chevron) stays untouched. The internal `.easeInOut(0.2)` animations at `:107, :111, :139, :156` STAY — Form-internal animations were W13.A defer; W13.D is purge-only. |
| S2.6 | Section "Request Timeout" | `:159-177` | Section with two Pickers (timeout duration + on-timeout retry) + header `HStack { Text + InfoTip }` | Replace with `sectionBlock(label: "REQUEST TIMEOUT", info: "Set how long to wait...") { VStack(spacing: 12) { Picker timeout; Picker retry } }`. Both Pickers `.pickerStyle(.menu)`. | **Sweep** | Behavior preservation: bindings to `enhancementTimeoutSeconds` + `retryOnTimeout`. |
| S2.7 | Conditional Section "On-device" (mlx/foundationModels only) | `:179-248` | Conditional Section with active-path indicator + idle-eviction Picker (mlx-only) + 2 buttons (open folder, copy CSV path), header `Text("On-device")`, footer "Each on-device enhancement..." | Replace with `if isOnDeviceProvider { sectionBlock(label: "ON-DEVICE") { /* indicator HStack; idle-eviction Picker if .mlx; HStack of 2 buttons */ }; sectionFooter("Each on-device enhancement appends a row to enhancement-timings.csv (timestamp, model, prompt mode, prep/ttft/gen/total seconds, gap, outcome).") }`. | **Sweep** | Behavior preservation: provider-conditional rendering, all bindings, both Button actions (`openTimingsFolder`, `copyTimingsPath`), all `Help` text. The footer renders as `Text(...) .font(.caption) .foregroundColor(.secondary)` — same chrome as v1's `Section { } footer:`. |
| S2.8 | Section "Shortcuts" | `:250-254` | Section { EnhancementShortcutsView() } header: { Text("Shortcuts") } | Replace with `sectionBlock(label: "SHORTCUTS") { EnhancementShortcutsView() }`. | **Sweep** | EnhancementShortcutsView is its own composed View; W13.D doesn't touch it. |
| S2.9 | Section "Last Sent System Prompt" | `:256-263` | Section { LastSystemPromptViewer() } header: { HStack { Text + InfoTip } } | Replace with `sectionBlock(label: "LAST SENT SYSTEM PROMPT", info: "...") { LastSystemPromptViewer() }`. | **Sweep** | LastSystemPromptViewer is private to this file at `:297-351`; left intact. |
| S2.10 | New `sectionBlock` helper | (new) | — | Add a `private func sectionBlock<Content: View>(label: String, info: String? = nil, @ViewBuilder content: () -> Content) -> some View` helper at the bottom of the file. Renders: `VStack(alignment: .leading, spacing: 10) { HStack(spacing: 4) { Text(label).font(.system(size: 10.5, weight: .medium, design: .monospaced)).tracking(0.06 * 10.5).foregroundColor(Palette.onyxMute.opacity(0.7)); if let info { InfoTip(info) }; Spacer() }; content() }`. Mirrors `APIKeyManagementView.sectionLabel(_:count:)` at `:71-86`. | **Sweep — new helper** | Compact section labels for narrow popover; no SettingsCard double-layering. |
| S2.11 | New `sectionFooter` helper | (new) | — | Add a `private func sectionFooter(_ text: String) -> some View` helper at the bottom: `Text(text).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)`. | **Sweep — new helper** | Replaces v1 `Section { } footer:` placement. |
| S2.12 | LastSystemPromptViewer's inner card chrome | `:312-321` | `RoundedRectangle 8 .fill(.ultraThinMaterial) .overlay(stroke Palette.hairlineSoft) .clipShape(...)` | KEEP byte-identical. Its inline glass treatment is sub-content; not part of Form purge. (W13.A flagged but was deferred to W13.D's "inside Form 56-265" — but this is sub-content chrome, NOT the Form host. Conservative: leave for W13.G polish.) | **Flag — preserve** | Polish, not Form purge. |
| S2.13 | `.tint(Palette.accent)` outer | `:268` | applied to outermost VStack | KEEP byte-identical. | **Flag — preserve** | Tints all native controls below. |

### Surface 3 — `PromptEditorView.swift` (two embedded Forms inside an existing GlassCard)

**File:** `VoiceInk/Views/PromptEditorView.swift` (~572 lines).

**Current shape:** `VStack(spacing: 0) { headerBar; splitContent { editorPane (GlassCard { Group { predefinedPromptForm OR customPromptForm } }); PromptLivePreview }; footerBar } .adaptiveGlassBackground(intensity: .panel)`. The `editorPane` already wraps content in `GlassCard(padding: 0)` — but inside, `predefinedPromptForm` (`:223-273`) and `customPromptForm` (`:277-366`) BOTH host `Form { Section ... } .formStyle(.grouped) .scrollContentBackground(.hidden)` panes.

**Constraint:** This Form sits INSIDE a `GlassCard` already (`editorPane` wraps it). So adding more `SettingsCard` chrome would over-glass. **Resolution: drop the Form to a flat `VStack { sectionLabel + content }` pattern**, mirror Surface 2's compact-section idiom (this is also a sub-pane). Don't add SettingsCard. Don't add GlassCard — `editorPane`'s outer GlassCard provides the glass surface.

**Target shape (each Form):** `ScrollView { VStack(alignment: .leading, spacing: 20) { sectionBlock(label: "DETAILS") { /* icon picker + name + description */ }; sectionBlock(label: "INSTRUCTIONS") { /* TextEditor + system-template Toggle */ }; sectionBlock(label: "TRIGGER WORDS", info: "Add words that automatically activate this prompt...") { TriggerWordsEditor }; if .add { sectionBlock(label: "TEMPLATES") { Menu { ... } label: { ... } } } } .padding(.horizontal, 20).padding(.vertical, 16) }`.

| # | Concern | File:line | Current | W13.D Action | Disposition | Rationale |
|---|---|---|---|---|---|---|
| S3.1 | `predefinedPromptForm` Form host | `:224, :271-272` | `Form { Section { Text }; Section { TextEditor + copy-button }; Section { TriggerWordsEditor } } .formStyle(.grouped) .scrollContentBackground(.hidden)` | Replace with `ScrollView { VStack(alignment: .leading, spacing: 20) { sectionBlock(label: "EDITING: \(title.uppercased())") { Text(...).font(.subheadline).foregroundColor(.secondary) }; sectionBlock(label: "SYSTEM PROMPT (READ-ONLY)", info: "...") { VStack { TextEditor; HStack { Spacer; Copy button } } }; sectionBlock(label: "TRIGGER WORDS", info: "...") { TriggerWordsEditor } } .padding(.horizontal, 20).padding(.vertical, 16) }`. | **Sweep** | Master plan §4 W13.D third bullet. |
| S3.2 | `customPromptForm` Form host | `:278, :364-365` | `Form { Section "Details" { icon button + name + description }; Section "Instructions" { TextEditor + Toggle }; Section "Trigger Words" { TriggerWordsEditor }; if .add { Section { Menu } } } .formStyle(.grouped) .scrollContentBackground(.hidden)` | Replace with `ScrollView { VStack(alignment: .leading, spacing: 20) { sectionBlock(label: "DETAILS") { /* HStack icon + TextField; TextField description */ }; sectionBlock(label: "INSTRUCTIONS") { /* TextEditor + Toggle */ }; sectionBlock(label: "TRIGGER WORDS", info: "...") { TriggerWordsEditor }; if case .add = mode { sectionBlock(label: "TEMPLATES") { Menu { ... } } } } .padding(.horizontal, 20).padding(.vertical, 16) }`. | **Sweep** | Master plan §4 W13.D third bullet. |
| S3.3 | `editorPane` outer GlassCard | `:143-154` | `GlassCard(padding: 0) { Group { predefinedPromptForm OR customPromptForm } .frame(maxWidth: .infinity, maxHeight: .infinity) }` | KEEP outer `GlassCard(padding: 0)` wrapper. The inner Form-now-VStack supplies its own padding via `.padding(.horizontal, 20).padding(.vertical, 16)`. Drop `padding: 0` if visual rhythm post-purge feels off — coder picks at smoke-test. | **Flag — preserve, smoke-test** | The outer GlassCard provides the glass surface; the inner ScrollView+VStack provides scroll behavior. |
| S3.4 | Icon-tile button | `:281-292` | Button { Image .background(.ultraThinMaterial) .cornerRadius(10) .overlay(stroke Color.secondary.opacity(0.2)) } + `.popover` | KEEP byte-identical. The `.ultraThinMaterial` chrome at `:286` is W13.A defer to "Form-internal" but is actually a button affordance, not a Form artifact. W13.D doesn't touch it. | **Flag — preserve** | Polish (W13.G). |
| S3.5 | TextField description / name | `:298-303` | `TextField(...).textFieldStyle(.roundedBorder)` (2×) | KEEP byte-identical — controls are primitives. | **Flag — preserve** | Behavior preservation. |
| S3.6 | TextEditor body | `:235-240, :309-322` | TextEditor with `.font(.system(.body, design: .monospaced))` + `.scrollContentBackground(.hidden)` | KEEP byte-identical. | **Flag — preserve** | Behavior preservation. The `.scrollContentBackground(.hidden)` here is on the TextEditor itself (different from Form's modifier); stays. |
| S3.7 | Toggle "Use System Template" | `:324-330` | Toggle.switch with InfoTip | KEEP byte-identical, relocate inside `sectionBlock(label: "INSTRUCTIONS")`. | **Sweep — relocate** | Behavior preservation. |
| S3.8 | TriggerWordsEditor | `:263, :336` | Self-contained subview; pasted into the Trigger Words section | KEEP byte-identical, relocate inside `sectionBlock(label: "TRIGGER WORDS")`. | **Sweep — relocate** | Self-contained. |
| S3.9 | "Start with Template" Menu | `:344-362` | Menu in `if case .add` Section | KEEP byte-identical, relocate inside `sectionBlock(label: "TEMPLATES")`. | **Sweep — relocate** | Self-contained. |
| S3.10 | TriggerWordItemView pill chrome | `:472-477` | `.background(.ultraThinMaterial).cornerRadius(4).overlay(stroke Color.secondary.opacity(0.2))` | KEEP byte-identical. W13.A flagged this for `glassChip(10)` polish but defers to W13.G (R4 row 23). NOT W13.D's job. | **Flag — preserve** | Polish (W13.G). |
| S3.11 | IconPickerPopover body | `:531-572` | Already non-Form (LazyVGrid in ScrollView). | KEEP byte-identical. Out of W13.D scope. | **Flag — preserve, no edit** | Already correct shape. |
| S3.12 | New `sectionBlock` helper at file scope | (new) | — | Add the same `private func sectionBlock(...)` helper as in Surface 2 — but file-scoped here (not nested in PromptEditorView). Both helpers can be **shared** by extracting to a new file `Views/Common/SectionBlock.swift`. **Recommended: keep duplicated helpers in each file** to avoid scope-drift; if reviewer prefers DRY, extract. See Open Question #2. | **Sweep — new helper** | The narrow-popover compact-section idiom; mirrors Surface 2 to keep cognitive parity. |

### Surface 4 — `History/InlineHistoryView.swift` cardListView (Form purge — list region only)

**File:** `VoiceInk/Views/History/InlineHistoryView.swift` (~617 lines).

**Current shape (cardListView only — `:254-301`):** `Form { ForEach(displayedTranscriptions) { Section { HistoryCardRow } }; if hasMoreContent { Section { Button "Load More" } } } .formStyle(.grouped) .scrollContentBackground(.hidden)`.

**Target shape:** `ScrollView { LazyVStack(spacing: 12) { ForEach(displayedTranscriptions) { transcription in GlassCard(cornerRadius: 14) { HistoryCardRow(...) } }; if hasMoreContent { GlassCard(cornerRadius: 14) { Button "Load More" } } } .padding(.horizontal, 16).padding(.vertical, 12) }`.

**Use `GlassCard`, NOT `SettingsCard`.** SettingsCard's purpose is icon-headed settings sections; HistoryCardRows are content cards (no per-row icon-headed section). `GlassCard(cornerRadius: 14)` matches spec §1 panel radius.

| # | Concern | File:line | Current | W13.D Action | Disposition | Rationale |
|---|---|---|---|---|---|---|
| S4.1 | cardListView Form host | `:255, :299-300` | `Form { … } .formStyle(.grouped) .scrollContentBackground(.hidden)` | Replace with `ScrollView { LazyVStack(spacing: 12) { … } .padding(.horizontal, 16).padding(.vertical, 12) }`. | **Sweep** | Master plan §4 W13.D fourth bullet (cardListView region only); R4 §3 row 15. |
| S4.2 | ForEach Sections | `:256-277` | `ForEach { Section { HistoryCardRow(...) } }` | Replace with `ForEach { transcription in GlassCard(cornerRadius: 14) { HistoryCardRow(...) } }`. HistoryCardRow body unchanged. | **Sweep** | Behavior preservation. |
| S4.3 | "Load More" Section | `:279-297` | `if hasMoreContent { Section { Button "Load More" }}` | Replace with `if hasMoreContent { GlassCard(cornerRadius: 14) { Button "Load More" } }`. Button label HStack stays byte-identical. | **Sweep** | Behavior preservation. |
| S4.4 | HistoryCardRow body | `:486-617` | Self-contained card row (timestamp + text + chevron + expanded content with tabs/scroll/audio player) | KEEP byte-identical — content. | **Flag — preserve** | The Capsule-tab affordance at `:574-576` is unrelated to Form purge. |
| S4.5 | topBar (search) | `:152-172` | `HStack { magnifying-glass icon + TextField } .background(Capsule().fill(Color.secondary.opacity(0.08)))` | KEEP byte-identical (R4 row 30 routes the Capsule sweep to W13.F). | **Defer → W13.F** | Search-field re-skin is W13.F's job. |
| S4.6 | selectionBar | `:174-231` | Already `.adaptiveGlassBackground(intensity: .panel)` — clean | KEEP byte-identical. | **Flag — preserve** | Spec-compliant. |
| S4.7 | emptyStateView | `:235-250` | Plain VStack with icons + text | KEEP byte-identical. | **Flag — preserve** | No Form here. |
| S4.8 | panelContent + infoPanelContent | `:303-358` | Sliding panel content (info / analysis) | KEEP byte-identical — out of cardListView scope. | **Flag — preserve** | Master plan scopes W13.D to cardListView only. |
| S4.9 | Padding rhythm trade | (smoke-test) | v1 Form supplies its own grouped insets | Coder picks 16h/12v vs 20h/16v at smoke-test (Task 12). Recommended: 16h/12v for tighter list density. | **Flag — coder picks** | Visual judgment under wallpapers. |

### Surface 5 — `AudioTranscribeView.swift` queueFormView (Form purge — list region only)

**File:** `VoiceInk/Views/AudioTranscribeView.swift` (~357 lines).

**Current shape (queueFormView only — `:98-141`):** `VStack(spacing: 0) { topBar; Divider; Form { ForEach(transcriptionManager.queue) { Section { AudioFileRow(...) } } } .formStyle(.grouped) .scrollContentBackground(.hidden) .safeAreaInset(.bottom) { Text "Drop files anywhere..." } }`.

**Target shape:** `VStack(spacing: 0) { topBar; Divider; ScrollView { LazyVStack(spacing: 12) { ForEach(transcriptionManager.queue) { item in GlassCard(cornerRadius: 14) { AudioFileRow(...) } } } .padding(.horizontal, 16).padding(.vertical, 12) } .safeAreaInset(.bottom) { Text "Drop files anywhere..." } }`.

**Use `GlassCard`, NOT `SettingsCard`.** Same reasoning as Surface 4 — these are file-row content cards, not icon-headed settings sections.

| # | Concern | File:line | Current | W13.D Action | Disposition | Rationale |
|---|---|---|---|---|---|---|
| S5.1 | Form host | `:103, :130-131` | `Form { … } .formStyle(.grouped) .scrollContentBackground(.hidden)` | Replace with `ScrollView { LazyVStack(spacing: 12) { … } .padding(.horizontal, 16).padding(.vertical, 12) }`. | **Sweep** | Master plan §4 W13.D fifth bullet. |
| S5.2 | ForEach Sections | `:104-128` | `ForEach { Section { AudioFileRow(...) } }` | Replace with `ForEach { item in GlassCard(cornerRadius: 14) { AudioFileRow(...) } }`. AudioFileRow body unchanged; all callbacks (`onToggleExpand`, `onRemove`, `onRetry`) byte-identical. | **Sweep** | Behavior preservation. |
| S5.3 | `.safeAreaInset(edge: .bottom)` "Drop files anywhere" hint | `:132-138` | Inside Form's modifier chain | Move modifier from Form-modifier-chain to ScrollView-modifier-chain. Body unchanged. | **Sweep — relocate** | Behavior preservation. |
| S5.4 | topBar | `:144-241` | Custom topBar with file count + add-button + enhancement controls + start/cancel + clear-button | KEEP byte-identical. **W13.C territory** — pill button re-skin is W13.C; W13.D doesn't touch. | **Defer → W13.C** | Coordination boundary per packet brief. |
| S5.5 | emptyStateView (drop zone) | `:50-94` | `RoundedRectangle 12 .fill(.windowBackgroundColor.opacity(0.4))` + dashed accentColor border | KEEP byte-identical. **W13.C territory.** | **Defer → W13.C** | R4 §3 row 17. |
| S5.6 | dropOverlay | `:282-297` | Drop-target accent overlay | KEEP byte-identical. **W13.C territory.** | **Defer → W13.C** | Drop-zone affordance. |
| S5.7 | Internal animation literals | `:41, :64, :110, :115, :124, :217, :296` | `.easeInOut(duration: 0.2 / 0.15)` | LEAVE for W13.A regression catch (or W13.G polish). | **Defer → W13.A or W13.G** | Animation codemod is not W13.D's job. |
| S5.8 | Padding rhythm trade | (smoke-test) | v1 Form supplies its own grouped insets | Coder picks 16h/12v vs 20h/16v at smoke-test. Recommended: 16h/12v matching Surface 4. | **Flag — coder picks** | Visual judgment. |

---

## Tasks

### Task 0 — Audit + grep validation (read-only)

**Files:** none.

- [ ] **Step 0.1: Re-run grep validation against this plan's per-surface tables.**

```bash
# Verify the 5 Form hosts still exist (this packet's targets)
rg -n 'Form \{' VoiceInk/Views/EnhancementSettingsView.swift VoiceInk/Views/Components/EnhancementSettingsPanel.swift VoiceInk/Views/PromptEditorView.swift VoiceInk/Views/History/InlineHistoryView.swift VoiceInk/Views/AudioTranscribeView.swift

# Expected:
#   EnhancementSettingsView.swift:53            (1× — Surface 1)
#   Components/EnhancementSettingsPanel.swift:56 (1× — Surface 2)
#   PromptEditorView.swift:224                  (1× — Surface 3 predefined)
#   PromptEditorView.swift:278                  (1× — Surface 3 custom)
#   History/InlineHistoryView.swift:255         (1× — Surface 4 cardListView)
#   AudioTranscribeView.swift:103               (1× — Surface 5 queue)
# Total: 6 Form blocks across 5 files (PromptEditorView has 2).

# Verify Form modifiers
rg -n 'formStyle\(\.grouped\)|scrollContentBackground\(\.hidden\)' VoiceInk/Views/EnhancementSettingsView.swift VoiceInk/Views/Components/EnhancementSettingsPanel.swift VoiceInk/Views/PromptEditorView.swift VoiceInk/Views/History/InlineHistoryView.swift VoiceInk/Views/AudioTranscribeView.swift

# Verify SettingsCard pattern in SettingsView (the pattern to copy)
rg -n 'SettingsCard\(|LazyVStack\(spacing: 16\)' VoiceInk/Views/Settings/SettingsView.swift | head -20

# Verify APIKeyManagementView is the only call site
rg -n 'APIKeyManagementView()' VoiceInk/ --type swift
# Expected: 1 hit at EnhancementSettingsView.swift:112

# Verify no other Form { } hosts in main-app surfaces (W13.D is the last Form purge)
rg -n 'Form \{' VoiceInk/Views/ --type swift
# Expected: only the 6 sites above (plus DictionarySettingsPanel.swift if present).
```

- [ ] **Step 0.2: Read primitives end-to-end (NO edits).**
  - `VoiceInk/Views/Common/SettingsCard.swift` — confirm signature: `SettingsCard(iconSystemName, iconTint, title, subtitle?, statusText?, statusTone, appearance?, content)`.
  - `VoiceInk/Views/Common/SettingsRow.swift` — confirm `SettingsRow(iconSystemName, label, subtitle?, iconTint, control)`.
  - `VoiceInk/Views/Common/SettingsSectionHeader.swift` — confirm `SettingsSectionHeader(icon, title, subtitle?, accent, statusText?, statusTone)` and `StatusTone = .neutral / .positive / .warning`.
  - `VoiceInk/Views/Common/GlassCard.swift` — confirm `GlassCard(cornerRadius: CGFloat = 16, padding: CGFloat = 14, appearance?, content)`.
  - `VoiceInk/Views/Common/Palette.swift` — confirm `accent`, `onyxFg`, `onyxMute`, `hairline`, `hairlineSoft`, `success` exist.
  - `VoiceInk/Views/Settings/SettingsView.swift:51-71` — the canonical Form-stripped pattern.
  - `VoiceInk/Views/Components/SlidingPanel.swift` — confirm panel width 400 default, `.adaptiveGlassBackground(intensity: .panel)` is applied automatically (so don't re-apply inside).

- [ ] **Step 0.3: Verify W13.C status.**
  - `git log --oneline main -- VoiceInk/Views/AudioTranscribeView.swift | head -5` — note recent edits.
  - If W13.C has merged its AudioTranscribeView edits, verify the queueFormView block is still at `:98-141` (or its post-W13.C equivalent — re-grep).
  - If W13.C is unmerged, proceed; coordinate at integration-build time with team-lead.

- [ ] **Step 0.4: Confirm worktree shape.**
  - `cd /Users/priyanshu/Desktop/Projects/pu/voiceink-fork && git worktree list` — verify clean state.
  - `git worktree add .worktrees/w13d main` (or pick an in-progress branch name; lead manages branch policy).

### Task 1 — EnhancementSettingsView Form purge (Surface 1)

**Files:** `VoiceInk/Views/EnhancementSettingsView.swift`.

- [ ] **Step 1.1: Replace Form host with ScrollView { LazyVStack }.** (S1.1)

  Replace `body` lines 53-173 with:
  ```swift
  var body: some View {
      ScrollView {
          LazyVStack(spacing: 16) {
              enhancementCard
              aiProviderCard
              promptsCard
          }
          .padding(.horizontal, 24)
          .padding(.vertical, 20)
          .frame(maxWidth: 720)
          .frame(maxWidth: .infinity)
      }
      .adaptiveGlassBackground()
      .slidingPanel(...)  // unchanged
      .frame(minWidth: 500, minHeight: 400)
  }
  ```

- [ ] **Step 1.2: Add `enhancementCard` computed property.** (S1.2, S1.3)

  ```swift
  private var enhancementCard: some View {
      ZStack(alignment: .topTrailing) {
          SettingsCard(
              iconSystemName: "wand.and.stars",
              iconTint: Palette.accent,
              title: "Enhancement",
              subtitle: "Pass transcripts through an LLM before pasting.",
              statusText: enhancementService.enhanceLevel.displayName,
              statusTone: enhancementService.enhanceLevel == .none ? .neutral : .positive
          ) {
              VStack(alignment: .leading, spacing: 8) {
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
          }

          // Gear button — overlaid on the card top-right (preserves spatial association)
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
          .padding(.trailing, 14)
          .padding(.top, 14)
      }
  }
  ```

  **Note:** the inline `Text("Cleanup Level")` label disappears — the SettingsSectionHeader title "Enhancement" + level-pill carry that semantic. The InfoTip is dropped from the body (its content moved into the section subtitle). If reviewer pushes back: restore the inline `Text("Cleanup Level") + InfoTip` HStack inside the picker VStack.

- [ ] **Step 1.3: Add `aiProviderCard` computed property.** (S1.5)

  ```swift
  private var aiProviderCard: some View {
      APIKeyManagementView()
          .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
  }
  ```

  And — **Step 1.3.b** — reshape `APIKeyManagementView.swift:88-145` body. Change from `Section { ... } header: { SettingsSectionHeader(...) }` to:
  ```swift
  var body: some View {
      SettingsCard(
          iconSystemName: "sparkles.rectangle.stack",
          iconTint: Palette.accent,
          title: "AI Provider Integration",
          subtitle: "Pick the model that shapes enhanced transcripts.",
          statusText: providerStatusText,
          statusTone: providerStatusTone
      ) {
          VStack(alignment: .leading, spacing: 12) {
              ProviderChip(...)
                  .padding(.bottom, 4)

              let configured = configuredProviders
              if !configured.isEmpty {
                  sectionLabel("CONFIGURED", count: configured.count)
                  LazyVGrid(columns: APIKeyManagementView.columns, spacing: 12) {
                      ForEach(configured, id: \.self) { provider in
                          ProviderCard(...)
                      }
                  }
              } else {
                  Text("No providers configured yet. Pick one below to add a key or download a local model.")
                      .font(.system(size: 11))
                      .foregroundColor(.secondary)
                      .padding(.vertical, 8)
              }

              let unconfigured = unconfiguredProviders
              if !unconfigured.isEmpty {
                  sectionLabel("AVAILABLE", count: unconfigured.count)
                  LazyVGrid(columns: APIKeyManagementView.columns, spacing: 12) {
                      ForEach(unconfigured, id: \.self) { provider in
                          ProviderCard(...)
                              .opacity(0.85)
                      }
                  }
              }
          }
          .padding(.vertical, 4)
      }
      .onAppear {
          if expandedProvider == nil {
              expandedProvider = aiService.selectedProvider
          }
      }
  }
  ```

  **Behavior preservation:** the `ProviderChip` + 2 `LazyVGrid` blocks + `.onAppear` pre-expand all stay byte-identical. Only the outer Section→SettingsCard envelope changes.

- [ ] **Step 1.4: Add `promptsCard` computed property.** (S1.6, S1.7, S1.8)

  ```swift
  private var promptsCard: some View {
      ZStack(alignment: .topTrailing) {
          SettingsCard(
              iconSystemName: "text.bubble",
              iconTint: Palette.accent,
              title: "Enhancement Prompts",
              subtitle: "Pick the active style; reorder by drag.",
              statusText: "\(enhancementService.customPrompts.count)",
              statusTone: .neutral
          ) {
              ReorderablePromptGrid(
                  selectedPromptId: enhancementService.selectedPromptId,
                  onPromptSelected: { prompt in
                      enhancementService.setActivePrompt(prompt)
                  },
                  onEditPrompt: { prompt in
                      openPromptPanel()
                      withAnimation(.smooth(duration: 0.3)) {
                          selectedPromptForEdit = prompt
                      }
                  },
                  onDeletePrompt: { prompt in
                      enhancementService.deletePrompt(prompt)
                  }
              )
              .padding(.vertical, 8)
          }

          // Plus button — overlaid on the card top-right
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
          .padding(.trailing, 14)
          .padding(.top, 14)
      }
      .opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)
  }
  ```

- [ ] **Step 1.5: Verify the rest of EnhancementSettingsView.swift is byte-identical.**
  - `ReorderablePromptGrid` (lines 207-283 pre-edit) UNCHANGED.
  - `PromptDropDelegate` (lines 286-313 pre-edit) UNCHANGED.
  - `closePanel()` / `openPromptPanel()` UNCHANGED.
  - `slidingPanel` modifier wiring UNCHANGED.

**Verify:**
- `rg -n 'Form \{|formStyle\(|scrollContentBackground' VoiceInk/Views/EnhancementSettingsView.swift` returns **0** hits.
- `rg -n 'SettingsCard|ZStack' VoiceInk/Views/EnhancementSettingsView.swift` shows the 3 SettingsCard wrappers + 2 ZStack overlay-buttons.
- The settings panel still opens via gear button. The new-prompt panel still opens via plus button. Cleanup-Level picker still binds to `enhancementService.enhanceLevel`. ReorderablePromptGrid drag-and-drop still works.

### Task 2 — APIKeyManagementView body reshape (Surface 1 transitive dependency)

**Files:** `VoiceInk/Views/AI Models/APIKeyManagementView.swift`.

(Already covered in Task 1 Step 1.3.b. Treat this as a Task-1 sub-step OR break out as a Task 2 if reviewer prefers atomic per-file commits.)

**Verify:**
- `rg -n 'Section \{|header: \{' VoiceInk/Views/AI\ Models/APIKeyManagementView.swift` — no Section/header refs in body.
- `aiService.selectedProvider` switching still works (manual smoke).
- `ProviderCard` expansion via `expandedProvider @Binding` still works.

### Task 3 — EnhancementSettingsPanel Form purge (Surface 2)

**Files:** `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`.

- [ ] **Step 3.1: Replace Form host with ScrollView { LazyVStack }.** (S2.1)

  Replace `body` lines 17-269 with:
  ```swift
  var body: some View {
      VStack(spacing: 0) {
          // Header (unchanged — S2.2)
          HStack(spacing: 12) {
              Text("Enhancement Settings")
                  .font(.headline)
                  .fontWeight(.semibold)
                  .foregroundColor(.primary)

              Spacer()

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
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 16)
          .adaptiveGlassBackground(intensity: .panel)
          .overlay(
              Rectangle()
                  .fill(Palette.hairlineSoft)
                  .frame(height: 1),
              alignment: .bottom
          )

          // Content — replace Form with flat sectionBlock VStack
          ScrollView {
              LazyVStack(alignment: .leading, spacing: 20) {
                  cleanupLevelSection
                  contextSection
                  shortTranscriptionsSection
                  requestTimeoutSection

                  if enhancementService.aiService.selectedProvider == .mlx
                      || enhancementService.aiService.selectedProvider == .foundationModels {
                      onDeviceSection
                  }

                  shortcutsSection
                  lastSystemPromptSection
              }
              .padding(.horizontal, 20)
              .padding(.vertical, 16)
          }
      }
      .tint(Palette.accent)
  }
  ```

- [ ] **Step 3.2: Add the 7 section computed properties.** (S2.3 — S2.9)

  Each follows the pattern below. Bodies are byte-identical to the v1 Section bodies; only the outer envelope changes.

  ```swift
  private var cleanupLevelSection: some View {
      sectionBlock(label: "CLEANUP LEVEL",
                   info: "None pastes raw transcripts. Light removes fillers. Medium fixes grammar. High polishes for clarity.") {
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
      }
  }

  private var contextSection: some View {
      sectionBlock(label: "CONTEXT") {
          VStack(alignment: .leading, spacing: 12) {
              Toggle(isOn: $enhancementService.useClipboardContext) {
                  HStack(spacing: 4) {
                      Text("Clipboard Context")
                      InfoTip("Use clipboard text to understand context for better enhancement.")
                  }
              }
              .toggleStyle(.switch)

              Toggle(isOn: $enhancementService.useScreenCaptureContext) {
                  HStack(spacing: 4) {
                      Text("Screen Context")
                      InfoTip("Capture on-screen text to understand context for better enhancement.")
                  }
              }
              .toggleStyle(.switch)
          }
      }
  }

  private var shortTranscriptionsSection: some View {
      sectionBlock(label: "SHORT TRANSCRIPTIONS") {
          VStack(alignment: .leading, spacing: 0) {
              // ... entire VStack body from v1 lines 100-156, byte-identical
          }
          .animation(.easeInOut(duration: 0.2), value: isShortEnhancementExpanded)
      }
  }

  private var requestTimeoutSection: some View {
      sectionBlock(label: "REQUEST TIMEOUT",
                   info: "Set how long to wait for the AI provider to respond. If no response is received within this duration, you can either fail immediately and paste the original transcription, or retry the request (up to 3 attempts).") {
          VStack(alignment: .leading, spacing: 12) {
              Picker("Timeout duration", selection: $enhancementTimeoutSeconds) {
                  ForEach([3, 5, 7, 10, 15, 20, 30, 40, 50, 60], id: \.self) { seconds in
                      Text("\(seconds) seconds").tag(seconds)
                  }
              }
              .pickerStyle(.menu)

              Picker("On timeout", selection: $retryOnTimeout) {
                  Text("Fail immediately").tag(false)
                  Text("Retry").tag(true)
              }
              .pickerStyle(.menu)
          }
      }
  }

  @ViewBuilder
  private var onDeviceSection: some View {
      VStack(alignment: .leading, spacing: 8) {
          sectionBlock(label: "ON-DEVICE") {
              VStack(alignment: .leading, spacing: 12) {
                  // active-path indicator HStack — byte-identical to v1 :186-197
                  HStack(spacing: 6) {
                      Image(systemName: enhancementService.activeLocalPathDescription.hasPrefix("Apple")
                            ? "applelogo"
                            : "cpu")
                          .foregroundColor(.secondary)
                      Text("Active path:")
                          .foregroundColor(.secondary)
                      Text(enhancementService.activeLocalPathDescription)
                          .foregroundColor(.primary)
                      Spacer()
                  }
                  .font(.callout)

                  // idle-eviction picker — mlx-only (byte-identical to v1 :202-219)
                  if enhancementService.aiService.selectedProvider == .mlx {
                      Picker(selection: $mlxIdleEvictSeconds) {
                          Text("60 seconds").tag(60)
                          Text("5 minutes").tag(300)
                          Text("10 minutes").tag(600)
                          Text("20 minutes").tag(1200)
                          Text("30 minutes").tag(1800)
                          Text("45 minutes").tag(2700)
                          Text("1 hour").tag(3600)
                          Text("Never").tag(Int.max)
                      } label: {
                          HStack(spacing: 4) {
                              Text("Idle eviction")
                              InfoTip("How long the MLX on-device model stays in memory after the last enhancement. Higher values trade memory for fewer cold-load spikes; lower values free memory faster. Applies on the next time the MLX provider is reloaded.")
                          }
                      }
                      .pickerStyle(.menu)
                  }

                  // 2 buttons — byte-identical to v1 :225-240
                  HStack(spacing: 8) {
                      Button(action: openTimingsFolder) {
                          Label("Open timings folder", systemImage: "folder")
                      }
                      .buttonStyle(.bordered)
                      .help("Reveal enhancement-timings.csv in Finder")

                      Button(action: copyTimingsPath) {
                          Label(
                              didCopyTimingsPath ? "Copied!" : "Copy CSV path",
                              systemImage: didCopyTimingsPath ? "checkmark" : "doc.on.doc"
                          )
                      }
                      .buttonStyle(.bordered)
                      .help("Copy the absolute CSV path to the clipboard")
                  }
              }
          }
          sectionFooter("Each on-device enhancement appends a row to enhancement-timings.csv (timestamp, model, prompt mode, prep/ttft/gen/total seconds, gap, outcome).")
      }
  }

  private var shortcutsSection: some View {
      sectionBlock(label: "SHORTCUTS") {
          EnhancementShortcutsView()
      }
  }

  private var lastSystemPromptSection: some View {
      sectionBlock(label: "LAST SENT SYSTEM PROMPT",
                   info: "The exact system prompt sent to the LLM on your last enhancement, including custom vocabulary and any clipboard or screen context that was attached. Useful for debugging why the model did or didn't follow an instruction.") {
          LastSystemPromptViewer()
      }
  }
  ```

- [ ] **Step 3.3: Add `sectionBlock` and `sectionFooter` helpers.** (S2.10, S2.11)

  At file scope, after `LastSystemPromptViewer` (or as private fileprivate utilities at the bottom):

  ```swift
  /// Compact section block for narrow popover surfaces. Renders a
  /// 10.5pt SF-mono uppercase label + optional InfoTip + content stack.
  /// Mirrors `APIKeyManagementView.sectionLabel(_:count:)` vocabulary.
  /// Used in W13.D popover surfaces (EnhancementSettingsPanel +
  /// PromptEditorView panes) where SettingsCard chrome would
  /// double-layer over the panel's existing glass background.
  @ViewBuilder
  private func sectionBlock<Content: View>(
      label: String,
      info: String? = nil,
      @ViewBuilder content: () -> Content
  ) -> some View {
      VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 4) {
              Text(label)
                  .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                  .tracking(0.06 * 10.5)
                  .foregroundColor(Palette.onyxMute.opacity(0.7))
              if let info {
                  InfoTip(info)
              }
              Spacer()
          }
          content()
      }
  }

  private func sectionFooter(_ text: String) -> some View {
      Text(text)
          .font(.caption)
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
  }
  ```

  Note: `sectionBlock` and `sectionFooter` may live as `extension EnhancementSettingsPanel` private helpers, or fileprivate top-level functions. Coder picks; recommend fileprivate top-level for callability across nested computed properties without `self.` prefix.

**Verify:**
- `rg -n 'Form \{|formStyle\(' VoiceInk/Views/Components/EnhancementSettingsPanel.swift` returns **0** hits.
- All 7 sections render at the same vertical order.
- All Toggles, Pickers, Buttons fire the same actions.
- `EnhancementShortcutsView()` and `LastSystemPromptViewer()` continue to render normally.
- The popover still opens via the gear button on EnhancementSettingsView.
- Footer text "Each on-device enhancement appends..." renders BELOW the on-device section, not as a Section footer (visual rhythm differs slightly — verify at smoke-test).

### Task 4 — PromptEditorView Form purge — predefinedPromptForm (Surface 3a)

**Files:** `VoiceInk/Views/PromptEditorView.swift`.

- [ ] **Step 4.1: Replace `predefinedPromptForm` body.** (S3.1)

  Replace `predefinedPromptForm` lines 223-273 with:
  ```swift
  private var predefinedPromptForm: some View {
      ScrollView {
          VStack(alignment: .leading, spacing: 20) {
              sectionBlock(label: "EDITING: \(title.uppercased())") {
                  Text("System prompts ship with VoiceInk. You can view their instructions here and customize trigger words below. To author your own prompt, tap + on the Enhancement Prompts panel.")
                      .font(.subheadline)
                      .foregroundColor(.secondary)
                      .fixedSize(horizontal: false, vertical: true)
              }

              sectionBlock(label: "SYSTEM PROMPT (READ-ONLY)",
                           info: "This is the instruction set sent to the LLM for this prompt. It updates automatically with each VoiceInk release.") {
                  VStack(alignment: .leading, spacing: 10) {
                      ZStack(alignment: .topLeading) {
                          TextEditor(text: .constant(promptText))
                              .font(.system(.body, design: .monospaced))
                              .frame(minHeight: 220)
                              .scrollContentBackground(.hidden)
                              .disabled(true)
                              .opacity(0.95)
                      }

                      HStack {
                          Spacer()
                          Button {
                              let pb = NSPasteboard.general
                              pb.clearContents()
                              pb.setString(promptText, forType: .string)
                          } label: {
                              Label("Copy", systemImage: "doc.on.doc")
                          }
                          .buttonStyle(.bordered)
                          .controlSize(.small)
                      }
                  }
              }

              sectionBlock(label: "TRIGGER WORDS",
                           info: "Add words that automatically activate this prompt. For example, 'summarize', 'email', 'translate'.") {
                  TriggerWordsEditor(triggerWords: $triggerWords)
              }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 16)
      }
  }
  ```

### Task 5 — PromptEditorView Form purge — customPromptForm (Surface 3b)

**Files:** `VoiceInk/Views/PromptEditorView.swift`.

- [ ] **Step 5.1: Replace `customPromptForm` body.** (S3.2)

  Replace `customPromptForm` lines 277-366 with:
  ```swift
  private var customPromptForm: some View {
      ScrollView {
          VStack(alignment: .leading, spacing: 20) {
              sectionBlock(label: "DETAILS") {
                  VStack(alignment: .leading, spacing: 10) {
                      HStack(alignment: .center, spacing: 14) {
                          Button(action: { showingIconPicker = true }) {
                              Image(systemName: selectedIcon)
                                  .font(.system(size: 22))
                                  .foregroundColor(.primary)
                                  .frame(width: 44, height: 44)
                                  .background(.ultraThinMaterial)
                                  .cornerRadius(10)
                                  .overlay(
                                      RoundedRectangle(cornerRadius: 10)
                                          .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                  )
                          }
                          .buttonStyle(.plain)
                          .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                              IconPickerPopover(selectedIcon: $selectedIcon, isPresented: $showingIconPicker)
                          }

                          TextField("Prompt Name", text: $title)
                              .textFieldStyle(.roundedBorder)
                      }

                      TextField("Brief description", text: $description)
                          .textFieldStyle(.roundedBorder)
                  }
              }

              sectionBlock(label: "INSTRUCTIONS") {
                  VStack(alignment: .leading, spacing: 12) {
                      ZStack(alignment: .topLeading) {
                          TextEditor(text: $promptText)
                              .font(.system(.body, design: .monospaced))
                              .frame(minHeight: 160)
                              .scrollContentBackground(.hidden)

                          if promptText.isEmpty {
                              Text("Enter your custom prompt instructions here...")
                                  .font(.system(.body, design: .monospaced))
                                  .foregroundStyle(.tertiary)
                                  .padding(.leading, 5)
                                  .allowsHitTesting(false)
                          }
                      }

                      Toggle(isOn: $useSystemInstructions) {
                          HStack(spacing: 4) {
                              Text("Use System Template")
                              InfoTip("If enabled, your instructions are combined with a general-purpose template to improve transcription quality.\n\nDisable for full control over the AI's system prompt (for advanced users).")
                          }
                      }
                      .toggleStyle(.switch)
                  }
              }

              sectionBlock(label: "TRIGGER WORDS",
                           info: "Add words that automatically activate this prompt. For example, 'summarize', 'email', 'translate'.") {
                  TriggerWordsEditor(triggerWords: $triggerWords)
              }

              if case .add = mode {
                  sectionBlock(label: "TEMPLATES") {
                      Menu {
                          ForEach(PromptTemplates.all, id: \.title) { template in
                              Button {
                                  title = template.title
                                  promptText = template.promptText
                                  selectedIcon = template.icon
                                  description = template.description
                              } label: {
                                  Label(template.title, systemImage: template.icon)
                              }
                          }
                      } label: {
                          Label("Start with Template", systemImage: "sparkles")
                      }
                      .menuStyle(.borderlessButton)
                  }
              }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 16)
      }
  }
  ```

- [ ] **Step 5.2: Add `sectionBlock` helper at file scope.** (S3.12)

  Add the same fileprivate `sectionBlock` helper as Task 3 Step 3.3, but in `PromptEditorView.swift`:
  ```swift
  fileprivate func sectionBlock<Content: View>(
      label: String,
      info: String? = nil,
      @ViewBuilder content: () -> Content
  ) -> some View {
      VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 4) {
              Text(label)
                  .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                  .tracking(0.06 * 10.5)
                  .foregroundColor(Palette.onyxMute.opacity(0.7))
              if let info {
                  InfoTip(info)
              }
              Spacer()
          }
          content()
      }
  }
  ```

  **Note:** if Task 3 already added `sectionBlock` as `fileprivate` in EnhancementSettingsPanel.swift, the Swift compiler treats `fileprivate` as scoped to the file (different file = different symbol — no conflict). Reviewer may push for DRY extraction to `Views/Common/SectionBlock.swift` — see Open Question #2.

**Verify:**
- `rg -n 'Form \{|formStyle\(' VoiceInk/Views/PromptEditorView.swift` returns **0** hits.
- Both `.add` and `.edit` flows render correctly.
- Predefined-prompt view shows the read-only TextEditor + Trigger Words section.
- Custom-prompt view shows Details + Instructions + Trigger Words + (if .add) Templates.
- Save / Cancel button bar still works.
- Icon picker still opens via popover.

### Task 6 — InlineHistoryView cardListView Form purge (Surface 4)

**Files:** `VoiceInk/Views/History/InlineHistoryView.swift`.

- [ ] **Step 6.1: Replace `cardListView` body.** (S4.1, S4.2, S4.3)

  Replace `cardListView` lines 254-301 with:
  ```swift
  private var cardListView: some View {
      ScrollView {
          LazyVStack(spacing: 12) {
              ForEach(displayedTranscriptions) { transcription in
                  GlassCard(cornerRadius: 14) {
                      HistoryCardRow(
                          transcription: transcription,
                          isExpanded: expandedId == transcription.id,
                          isChecked: selectedTranscriptions.contains(transcription),
                          onToggleExpand: {
                              withAnimation(Animation.haloPhaseCrossfade) {
                                  expandedId = expandedId == transcription.id ? nil : transcription.id
                              }
                          },
                          onToggleCheck: { toggleSelection(transcription) },
                          onShowInfo: {
                              panelTranscriptionId = transcription.id
                              panelMode = .info
                              withAnimation(Animation.haloExpand) {
                                  isPanelPresented = true
                              }
                          }
                      )
                  }
              }

              if hasMoreContent {
                  GlassCard(cornerRadius: 14) {
                      Button(action: {
                          Task { await loadMoreContent() }
                      }) {
                          HStack(spacing: 8) {
                              if isLoading {
                                  ProgressView().controlSize(.small)
                              }
                              Text(isLoading ? "Loading..." : "Load More")
                                  .font(.system(size: 13, weight: .medium))
                          }
                          .frame(maxWidth: .infinity)
                          .padding(.vertical, 4)
                      }
                      .buttonStyle(.plain)
                      .disabled(isLoading)
                  }
              }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 12)
      }
  }
  ```

**Verify:**
- `rg -n 'Form \{|formStyle\(' VoiceInk/Views/History/InlineHistoryView.swift` returns **0** hits.
- HistoryCardRow expansion / checkbox toggle / info-panel trigger all work.
- Pagination "Load More" still triggers `loadMoreContent()`.
- Search filter still re-fetches via `onChange(of: searchText)`.
- Selection bar appears at the bottom when items checked.

### Task 7 — AudioTranscribeView queueFormView Form purge (Surface 5)

**Files:** `VoiceInk/Views/AudioTranscribeView.swift`.

- [ ] **Step 7.1: Re-grep for the queueFormView block.** Confirm lines 98-141 still match the v1 shape (W13.C may have shifted them if it merged first).

- [ ] **Step 7.2: Replace `queueFormView` body.** (S5.1, S5.2, S5.3)

  Replace `queueFormView` lines 98-141 with:
  ```swift
  private var queueFormView: some View {
      VStack(spacing: 0) {
          topBar
          Divider()

          ScrollView {
              LazyVStack(spacing: 12) {
                  ForEach(transcriptionManager.queue) { item in
                      GlassCard(cornerRadius: 14) {
                          AudioFileRow(
                              item: item,
                              isExpanded: expandedItemId == item.id,
                              onToggleExpand: {
                                  withAnimation(.easeInOut(duration: 0.2)) {
                                      expandedItemId = expandedItemId == item.id ? nil : item.id
                                  }
                              },
                              onRemove: {
                                  withAnimation(.easeInOut(duration: 0.2)) {
                                      transcriptionManager.removeFromQueue(id: item.id)
                                      if expandedItemId == item.id { expandedItemId = nil }
                                  }
                              },
                              onRetry: {
                                  transcriptionManager.retryItem(id: item.id)
                                  if !transcriptionManager.isProcessingQueue {
                                      transcriptionManager.startProcessing(modelContext: modelContext, engine: engine)
                                  }
                              }
                          )
                      }
                  }
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 12)
          }
          .safeAreaInset(edge: .bottom) {
              Text("Drop files anywhere to add more")
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 8)
          }
      }
  }
  ```

  **Note:** the `queueFormView` name is now a misnomer (no Form). Coder picks: rename to `queueListView` (cleaner) or leave the name (reviewer-friendly diff). Recommend rename to `queueListView`. If renamed, update `body` line 20 reference.

**Verify:**
- `rg -n 'Form \{|formStyle\(' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits.
- AudioFileRow expansion / remove / retry all work.
- Drop-files hint appears at the bottom.
- topBar (start, cancel, clear, AI enhancement controls) untouched.

### Task 8 — Self-review + grep follow-up

**Files:** none (read-only).

- [ ] **Step 8.1: Re-run all the Form-host greps.**
```bash
rg -n 'Form \{' VoiceInk/Views/EnhancementSettingsView.swift VoiceInk/Views/Components/EnhancementSettingsPanel.swift VoiceInk/Views/PromptEditorView.swift VoiceInk/Views/History/InlineHistoryView.swift VoiceInk/Views/AudioTranscribeView.swift
# Expected: 0 hits.

rg -n 'formStyle\(\.grouped\)|scrollContentBackground\(\.hidden\)' VoiceInk/Views/EnhancementSettingsView.swift VoiceInk/Views/Components/EnhancementSettingsPanel.swift VoiceInk/Views/PromptEditorView.swift VoiceInk/Views/History/InlineHistoryView.swift VoiceInk/Views/AudioTranscribeView.swift
# Expected: 0 hits.

# Note: PromptEditorView's TextEditor.scrollContentBackground(.hidden) calls (lines 235-240, 309-322) may still match — they're TextEditor-scoped, NOT Form-scoped. Disregard those hits; they're behavior-preservation.
```

- [ ] **Step 8.2: Confirm primitives byte-identical.**
```bash
git diff main -- VoiceInk/Views/Common/SettingsCard.swift VoiceInk/Views/Common/GlassCard.swift VoiceInk/Views/Common/SettingsRow.swift VoiceInk/Views/Common/SettingsSectionHeader.swift VoiceInk/Views/Common/Palette.swift VoiceInk/Views/Common/Animation+Halo.swift VoiceInk/Views/Common/AdaptiveGlassBackground.swift VoiceInk/Views/Recorder/HaloMaterial.swift
# Expected: empty diff.
```

- [ ] **Step 8.3: Confirm SettingsView byte-identical.**
```bash
git diff main -- VoiceInk/Views/Settings/SettingsView.swift
# Expected: empty diff.
```

- [ ] **Step 8.4: Confirm no recorder-cluster drift.**
```bash
git diff main -- VoiceInk/Views/Recorder/
# Expected: empty diff.
```

- [ ] **Step 8.5: Confirm no other Form purge regressions.**
```bash
rg -n 'Form \{' VoiceInk/Views/ --type swift
# Expected: only Form blocks NOT in W13.D's 5-surface list. (Likely: DictionarySettingsPanel.swift line 46 — flag for future Form-purge follow-up packet, NOT W13.D scope per master plan.)
```

### Task 9 — APIKeyManagementView call-site sanity check

**Files:** none (read-only).

- [ ] **Step 9.1: Re-grep for APIKeyManagementView call sites.**
```bash
rg -n 'APIKeyManagementView' VoiceInk/ --type swift
# Expected: 1 use site (EnhancementSettingsView.swift) + 1 declaration (AI Models/APIKeyManagementView.swift).
```

- [ ] **Step 9.2: Confirm `aiService.selectedProvider` round-trip.**
  - Open Enhancement Settings.
  - Click into a configured provider's card; confirm `aiService.selectedProvider` updates.
  - Click the active provider chip; confirm visual highlight stays in sync.
  - Confirm `expandedProvider` toggle (tap a provider card) still expands/collapses without breaking the SettingsCard wrapping.

### Task 10 — sectionBlock helper sanity check

**Files:** none (read-only).

- [ ] **Step 10.1: Confirm `sectionBlock` is defined exactly twice (Surface 2 + Surface 3) — OR once (extracted to Views/Common/SectionBlock.swift).**
```bash
rg -n 'func sectionBlock' VoiceInk/ --type swift
```

- [ ] **Step 10.2: Confirm both usages render identically** under both onyx and light wallpaper modes (Task 12 visual smoke).

### Task 11 — Behavior sanity check (per surface)

**Files:** none (manual smoke during Task 12, but documented up-front so coder doesn't drift).

For EACH of the 5 surfaces, confirm:

- [ ] **Surface 1 — EnhancementSettingsView:**
  - Cleanup Level picker switches between None / Light / Medium / High.
  - Status pill in section header reflects level.
  - Gear button toggles the EnhancementSettingsPanel popover.
  - Plus button opens PromptEditorView in `.add` mode.
  - APIKeyManagementView (provider grid) renders with ProviderChip + 2 LazyVGrids.
  - ReorderablePromptGrid drag-and-drop reorders prompts.
  - Right-click on a prompt opens context menu (edit / delete).
  - Double-click on a prompt opens PromptEditorView in `.edit(prompt)` mode.
  - `.opacity(0.8)` dimming when enhancement is disabled.

- [ ] **Surface 2 — EnhancementSettingsPanel (popover):**
  - All 4 base sections render (Cleanup Level, Context, Short Transcriptions, Request Timeout).
  - On-Device section ONLY renders when provider is `.mlx` or `.foundationModels`.
  - Idle eviction Picker ONLY renders when provider is `.mlx` (NOT `.foundationModels`).
  - Open timings folder + Copy CSV path buttons fire correctly.
  - Footer "Each on-device enhancement..." renders below ON-DEVICE section.
  - Shortcuts section embeds EnhancementShortcutsView correctly.
  - Last Sent System Prompt embeds LastSystemPromptViewer correctly.
  - Skip Short Transcriptions: tapping the toggle expands/collapses the inner Picker; tapping the row toggles expand without flipping the toggle.
  - Close (xmark) button fires onDismiss.

- [ ] **Surface 3 — PromptEditorView:**
  - Predefined-prompt mode: Editing-as section + read-only TextEditor + Copy button + Trigger Words.
  - Custom-prompt mode: Details (icon + name + description), Instructions (TextEditor + System-Template Toggle), Trigger Words, Templates (only in `.add` mode).
  - Icon picker popover opens from the icon button.
  - Save Changes button writes to the right prompt (add or edit).
  - Cancel button dismisses without saving.
  - Esc closes the panel.

- [ ] **Surface 4 — InlineHistoryView cardListView:**
  - Cards expand / collapse on tap.
  - Checkboxes toggle selection.
  - Info button opens the info panel.
  - "Load More" button paginates.
  - Search filters the visible set.
  - Selection bar appears when items selected.
  - Audio player + tabs (Original / Enhanced) render in expanded view.

- [ ] **Surface 5 — AudioTranscribeView queue:**
  - Queue items render as cards.
  - Expansion (per AudioFileRow) works.
  - Remove / Retry buttons fire correctly.
  - Drop new files appends to queue.
  - "Drop files anywhere to add more" hint appears at bottom.

### Task 12 — Visual smoke pass (coder + reviewer)

**Files:** none.

- [ ] **Step 12.1: Build via `make local && open VoiceInk.app`** (or via Xcode Run).

- [ ] **Step 12.2: For EACH surface, screenshot under all 4 mode/wallpaper combos:**
  - (a) System Light + bright wallpaper
  - (b) System Light + dark wallpaper
  - (c) System Dark + bright wallpaper
  - (d) System Dark + dark wallpaper

  Save under `docs/superpowers/research/2026-04-30-W13D-screenshots/<surface>/<combo>.png`.

- [ ] **Step 12.3: Confirm visually for EACH surface:**

  - **Surface 1 (EnhancementSettingsView):** SettingsCards render onyx-glass on bright wallpaper / light-glass on dark wallpaper. Section headers wear the icon-tile + title + subtitle + status pill chrome. Gear and plus buttons sit at the top-right of their respective cards (or at the documented fallback position if reviewer rejected the overlay placement). No double-Form chrome.

  - **Surface 2 (EnhancementSettingsPanel):** Popover renders as a single glass column (the SlidingPanel surface) with 11pt mono-tracked uppercase section labels. NO double-glass artifact (a card-on-card visual). Sections breathe at 20pt vertical spacing. ON-DEVICE section appears only on `.mlx` / `.foundationModels`.

  - **Surface 3 (PromptEditorView):** editorPane GlassCard renders correctly. Inside: section labels render as 11pt mono-tracked uppercase. Both predefined and custom flows look the same; sections at 20pt spacing.

  - **Surface 4 (InlineHistoryView cardListView):** Cards render as 14pt-radius GlassCards with HistoryCardRow content. NO Form-grouped chrome. Selection bar at the bottom (when applicable) still renders correctly. Pagination button as a card.

  - **Surface 5 (AudioTranscribeView queue):** Cards render as 14pt-radius GlassCards with AudioFileRow content. topBar + emptyStateView untouched. "Drop files anywhere to add more" footer renders at bottom.

- [ ] **Step 12.4: Accessibility sanity:**
  - System Settings → Accessibility → Display → Reduce transparency = ON. Re-open each surface. Glass surfaces fall back to opaque per spec §6.4. Pages remain legible.
  - Increase contrast = ON. Inner strokes become 1pt solid; pages remain legible.
  - Reduce motion = ON. No aggressive scaling/rotation on card expand/collapse.

- [ ] **Step 12.5: Capture any padding/spacing surprises** at smoke-test:
  - Surface 1: ZStack overlay-button placement reads weirdly? Fall back to row-inside (Open Q #1).
  - Surface 4 / 5: 16h/12v outer padding feels cramped? Bump to 20h/16v.
  - Surface 2 / 3: 20pt LazyVStack vertical spacing too tight under narrow popover? Bump to 24pt.
  - Surface 3: editorPane `padding: 0` clips section content too tightly? Bump to `padding: 8` (still leaves room for inner section padding).

### Task 13 — Report to lead

- [ ] Coder reports to `team-lead` via SendMessage:
  - File list edited (5 files): `EnhancementSettingsView.swift`, `Components/EnhancementSettingsPanel.swift`, `PromptEditorView.swift`, `History/InlineHistoryView.swift`, `AudioTranscribeView.swift`.
  - Transitively edited: `AI Models/APIKeyManagementView.swift` (Surface 1 dependency).
  - LOC delta (estimate ~400-700 net edited).
  - Smoke-pass observations per surface (any padding/placement tweaks made vs. recommendations).
  - Open Question resolutions (e.g. "went with overlay button placement on Surface 1; rejected row-inside fallback after smoke-test").
  - Any flagged items left untouched (with reason — typically W13.A defer / W13.G polish).
  - Worktree path for lead's `make local` integration build.
  - W13.C overlap status: did W13.C merge first? Did rebase clean? Or did W13.D merge first?

- [ ] Lead handles commits per CLAUDE.md cadence:
  ```
  docs(plans): W13D — Form-host purge (5 surfaces)   (this file)
  feat(aesthetic): W13D — Form-host purge (5 surfaces)  (the 5+1 source edits)
  ```

- [ ] After lead's `make local` returns green and the merge commit lands, lead runs the **Post-merge verification protocol** below (user-side).

---

## Verification (coder/reviewer side)

1. **Build green.** `xcodebuild build` (or `make local`) at lead's integration step. Zero warnings, zero errors related to W13.D surfaces.
2. **Grep follow-up clean.** Per Task 8 — zero `Form { }` / `formStyle(.grouped)` hits across the 5 surfaces.
3. **Visual smoke green.** Per Task 12 — all five surfaces × four wallpaper/mode combos read as glass-on-wallpaper.
4. **Behavior sanity green.** Per Task 11 — every Toggle, Picker, Button, drag, expand, and panel-open works identically to v1.
5. **No primitive drift.** `SettingsCard.swift`, `GlassCard.swift`, `SettingsRow.swift`, `SettingsSectionHeader.swift`, `Palette.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` byte-identical pre/post.
6. **No SettingsView drift.** The W5 reference host stays byte-identical pre/post (Task 8 Step 8.3).
7. **No recorder-cluster drift.** All `VoiceInk/Views/Recorder/` byte-identical pre/post (Task 8 Step 8.4).
8. **Single APIKeyManagementView call site** still resolves (Task 9).
9. **W13.C boundary respected.** AudioTranscribeView changes are limited to the queueFormView block (lines 98-141 v1 / equivalent post-W13.C). topBar, emptyStateView, dropOverlay byte-identical.

---

## Rollback plan

Single-commit packet (`feat(aesthetic): W13D — Form-host purge (5 surfaces)`). If a regression surfaces post-merge:

```bash
git revert <feat-sha>
```

Reverts cleanly because every edit is bounded to 6 files (5 surfaces + APIKeyManagementView), no schema migrations, no dependency changes, no test-fixture drift, no spec amendments. The `docs(plans): W13D — …` commit can stay (the plan doc is reusable across re-attempts).

If a *partial* regression surfaces (e.g. Surface 4's HistoryCardRow rendering off but Surface 1 is fine), rollback the offending file via:
```bash
git checkout <feat-sha>~1 -- VoiceInk/Views/History/InlineHistoryView.swift
```
…and re-commit. Preserves the rest of the purge.

If a behavior regression surfaces (e.g. ProviderCard expansion broken on Surface 1), the fix is a localized re-check of the SettingsCard envelope vs. the v1 Section envelope — no rollback needed.

---

## Risks

1. **SettingsCard scaling for the popover surface (Surface 2) — HIGH.** This is the trickiest fit. The popover already has `.adaptiveGlassBackground(intensity: .panel)` on its container (`SlidingPanel.swift:31`). Adding `SettingsCard` (= `GlassCard` = `HaloMaterial(phase: .hidden)`) on top of that double-layers the glass material — exactly what `SettingsCard.swift:21-23` warns against. **Resolution:** EnhancementSettingsPanel does NOT use SettingsCard. It uses a flat `LazyVStack` of `sectionBlock(label:info:)` un-carded section blocks (compact mono-tracked uppercase labels). Same idiom for PromptEditorView's two Form panes (Surface 3) since they sit inside `editorPane`'s GlassCard. **Verify at smoke-test:** the popover should read as ONE glass surface with hierarchical sections, NOT cards-on-cards.

2. **APIKeyManagementView body reshape (Surface 1 transitive) — MEDIUM.** Reshaping `body` from `Section { … } header: { SettingsSectionHeader }` to `SettingsCard { ... }` changes the root view envelope. The single call site at `EnhancementSettingsView.swift:112` works either way. Risk: a future call site embeds `APIKeyManagementView()` inside a Form expecting it to be a Section. **Mitigation:** grep confirms only one call site today. If a future packet wants to embed it inside another Form, that packet authors a wrapper (`APIKeyManagementSection`) that re-introduces the Section envelope. Document the shape change in the file's top-of-file comment.

3. **Behavior preservation across 5 surfaces — MEDIUM-HIGH.** Five separate flows with five separate test paths. Any binding wired wrong = regression. **Mitigation:** Task 11 enumerates per-surface behavior checks; Task 12 enforces visual + behavior smoke per surface; Task 8.4 grep-confirms primitive byte-equality. Coder runs every flow once before reporting to lead.

4. **W13.C overlap on AudioTranscribeView — MEDIUM.** Both packets edit the same file. **Mitigation:** strict scope boundary — W13.D ONLY edits queueFormView (lines 98-141 v1). If W13.C lands first, Task 7 Step 7.1 re-greps to confirm scope before editing. If W13.D lands first, W13.C's coder re-greps and merges around W13.D's lines.

5. **Padding rhythm decisions — LOW.** Five surfaces × multiple padding-trade points (overlay-button placement, LazyVStack outer padding, editorPane inner padding, ScrollView padding for cardListView/queueListView). Coder picks at smoke-test (Task 12). Recommended defaults are documented per surface table; each can be tuned after visual review. None blocks merge.

6. **`sectionBlock` helper duplication — LOW.** Defined twice (once in EnhancementSettingsPanel.swift, once in PromptEditorView.swift). DRY-violation but contained. **Resolution:** option to extract to `Views/Common/SectionBlock.swift` if reviewer prefers; default keeps it duplicated to avoid scope drift. See Open Question #2.

7. **`.opacity(0.8)` enabled-gating semantics — LOW.** The v1 wraps Sections 2 + 3 in `.opacity(enhancementService.isEnhancementEnabled ? 1.0 : 0.8)`. Post-purge, this wraps `aiProviderCard` and `promptsCard`. SettingsCard inherits `.opacity` cleanly. Verify visually that the dim-when-disabled state still reads.

8. **Settings panel gear-button placement (Surface 1, S1.2) — LOW.** v1 has the gear button INSIDE the section header HStack, alongside the SettingsSectionHeader. Post-purge, SettingsCard owns its own header — no slot for an external button. Recommended: ZStack(.topTrailing) overlay. Risk: if the SettingsCard chrome is too narrow, the overlay clips. Smoke-test catches this. Fallback: row-inside (place button as the first row of the SettingsCard content).

9. **Missing inline `Text("Cleanup Level")` heading (Surface 1, S1.3) — LOW.** SettingsSectionHeader.title = "Enhancement"; the inline `Text("Cleanup Level")` heading is dropped. Reviewer may push back ("Enhancement / Cleanup Level reads cleaner with both labels"). Smoke-test decides. Fallback: restore the inline heading inside the picker VStack.

10. **PromptEditorView `editorPane` outer GlassCard padding (Surface 3, S3.3) — LOW.** v1: `GlassCard(padding: 0)`. Post-purge: inner ScrollView+VStack supplies 20h/16v. If the outer GlassCard's 0 padding clips the ScrollView's edge, increase to `padding: 8`. Smoke-test catches this.

11. **TextField focus / TextEditor scroll inside ScrollView (Surface 3) — LOW.** SwiftUI's nested ScrollView + TextEditor scrolling can interact awkwardly. v1 had Form's grouped ScrollView wrap; post-purge, the outer ScrollView wraps. **Mitigation:** TextEditor's `.scrollContentBackground(.hidden)` modifier stays. Coder verifies in Task 12 Step 12.4 that scrolling and focus-trap work correctly under both `.add` and `.edit` modes.

12. **HistoryCardRow tap-to-expand inside GlassCard (Surface 4) — LOW.** v1: tap fires inside Form's grouped Section. Post-purge: tap fires inside GlassCard. The `contentShape(Rectangle())` modifier at `:545` should keep the hit-target consistent. Smoke-test the tap area.

13. **AudioFileRow internal interactions (Surface 5) — LOW.** Same as Surface 4 — internal AudioFileRow callbacks should fire identically inside GlassCard. Smoke-test.

14. **Single integration build at merge — DEFERRED.** Per `feedback_skip_per_packet_builds.md`: no per-task `xcodebuild`. Risk: 5-surface diff hits a compile error only at merge. **Mitigation:** Task 0 grep validates scope; coder mentally compiles each surface before moving to the next; reviewer eyeballs the diff before SendMessage to lead. If integration build fails, hot-fix path is per-surface localized.

---

## Open questions for lead

1. **Surface 1 settings gear-button placement — overlay-top-right vs. row-inside-card?** Recommended: ZStack(.topTrailing) overlay (preserves spatial association with the Cleanup Level section). Fallback: as the first row of the SettingsCard content. Same question for the plus button on the Prompts card. Lead picks at sign-off; coder smoke-tests at Task 12 either way.

2. **`sectionBlock` helper — duplicate (EnhancementSettingsPanel + PromptEditorView) or extract to `Views/Common/SectionBlock.swift`?** Recommended: duplicate (avoids scope drift; small ~12-line helper). Acceptable: extract (DRY). If extracted, the new file lands at `Views/Common/SectionBlock.swift` with public `sectionBlock(label:info:content:)` modifier. Lead picks.

3. **Surface 1 inline `Text("Cleanup Level") + InfoTip` — drop or keep?** Recommended: drop (SettingsSectionHeader.title "Enhancement" + status pill carry the semantic; reduces visual redundancy). Fallback: restore inline heading inside the picker VStack. Lead picks; coder smoke-tests.

4. **Surface 4 / Surface 5 GlassCard radius — 14pt vs 16pt?** Spec §1 panel radius is 14pt; SettingsCard default is 16pt. Recommended: 14pt for content cards (HistoryCardRow + AudioFileRow are content panels, not settings sections). Lead picks.

5. **Surface 2 footer text "Each on-device enhancement appends..." — keep below as separate `sectionFooter` or merge into the ON-DEVICE section's sectionBlock as a final body row?** Recommended: keep as separate `sectionFooter` (matches v1 Section { } footer: { ... } visual rhythm). Acceptable: merge inline. Lead picks.

6. **PromptEditorView's `editorPane` outer GlassCard `padding` — 0 vs 8?** v1 uses `GlassCard(padding: 0)` because the inner Form supplies its own grouped insets. Post-purge, the inner ScrollView+VStack supplies 20h/16v — but the outer GlassCard at 0 padding may clip the ScrollView edge. Recommended: try 0 first, bump to 8 at smoke-test if clipping.

7. **AudioTranscribeView `queueFormView` rename to `queueListView`?** Post-purge the name is misleading. Recommended: rename. Acceptable: leave (smaller diff). Lead picks.

8. **W13.C ordering — does W13.D wait for W13.C, or proceed and W13.C rebases?** Per packet brief: "W13.C may merge BEFORE W13.D for AudioTranscribeView styling. W13.D coder must rebase if so." Confirms W13.D proceeds independently and rebases if W13.C lands first. Lead confirms this is still the strategy at sign-off.

---

## Post-merge verification protocol (USER-SIDE)

Run after lead merges `feat(aesthetic): W13D — Form-host purge (5 surfaces)` to main and the build is green.

### Pre-merge baseline (if not done at sign-off)

1. **Capture baseline screenshots:**
   - Open EnhancementSettingsView (Settings → AI Enhancement tab). Screenshot full scroll under Light + Dark + bright/dark wallpaper (4 shots).
   - Open the gear-button popover (EnhancementSettingsPanel). Screenshot under same 4 combos (4 shots).
   - Open the Prompt Editor (plus button → New Prompt). Screenshot custom-prompt mode under same 4 combos (4 shots).
   - Open one predefined prompt (double-click). Screenshot read-only predefined mode under same 4 combos (4 shots).
   - Open the History tab (InlineHistoryView). Screenshot card list with at least 5 transcriptions visible under same 4 combos (4 shots).
   - Open the Audio Transcription tab. Drop a file or two so the queue is visible. Screenshot under same 4 combos (4 shots).

   Total: ~24 baseline screenshots saved to `docs/superpowers/research/2026-04-30-W13D-pre-merge-screenshots/`.

### Per-surface verification

#### Surface 1 — EnhancementSettingsView

2. **Scroll layout:** opens with `ScrollView { LazyVStack }` rhythm; three SettingsCards (Enhancement / AI Provider Integration / Enhancement Prompts) at 16pt vertical spacing.
3. **No double Form chrome:** zero macOS-grouped Section background visible behind any card.
4. **Cleanup Level picker:** segmented control, 4 levels (None / Light / Medium / High). Switching levels updates the section header status pill.
5. **Gear button:** positioned at top-right of Enhancement card. Tap opens EnhancementSettingsPanel popover (Surface 2).
6. **APIKeyManagementView:** ProviderChip + 2 LazyVGrids (CONFIGURED / AVAILABLE) render correctly. Click a provider → `aiService.selectedProvider` updates.
7. **Plus button:** positioned at top-right of Enhancement Prompts card. Tap opens PromptEditorView in `.add` mode (Surface 3).
8. **ReorderablePromptGrid:** all custom prompts render as icon tiles. Drag-and-drop reorders correctly. Right-click opens context menu (Edit / Delete).
9. **Disabled-state dimming:** when AI Enhancement is OFF, AI Provider + Prompts cards visibly dim to 0.8 opacity.

#### Surface 2 — EnhancementSettingsPanel popover

10. **Single glass column:** popover renders as ONE adaptive-glass surface; no card-on-card visual artifacts.
11. **Section labels:** 11pt SF-mono uppercase tracked, dim onyxMute color. Match `MLXModelPickerView` and `APIKeyManagementView.sectionLabel(...)` vocabulary.
12. **Section ordering:** CLEANUP LEVEL → CONTEXT → SHORT TRANSCRIPTIONS → REQUEST TIMEOUT → (ON-DEVICE if mlx/foundationModels) → SHORTCUTS → LAST SENT SYSTEM PROMPT.
13. **Conditional rendering:** ON-DEVICE section renders only when provider is `.mlx` or `.foundationModels`. Idle eviction Picker renders only when `.mlx`.
14. **Footer text:** "Each on-device enhancement appends a row to enhancement-timings.csv (timestamp, model, prompt mode, prep/ttft/gen/total seconds, gap, outcome)." appears immediately below ON-DEVICE section.
15. **Skip Short Transcriptions row:** toggle expands/collapses the inner Picker via tap-anywhere-on-row.
16. **Open timings folder + Copy CSV path buttons:** fire correctly. "Copied!" → "Copy CSV path" reverts after 1.5s.
17. **EnhancementShortcutsView:** embedded in SHORTCUTS section. Configurable shortcuts work.
18. **LastSystemPromptViewer:** embedded in LAST SENT SYSTEM PROMPT section. Inner card chrome (.ultraThinMaterial) untouched.
19. **xmark close button:** dismisses panel via `onDismiss`.

#### Surface 3 — PromptEditorView

20. **Custom-prompt mode (`.add`):** four sections — DETAILS / INSTRUCTIONS / TRIGGER WORDS / TEMPLATES.
21. **Predefined-prompt mode (`.edit(predefined)`):** three sections — EDITING: <name> / SYSTEM PROMPT (READ-ONLY) / TRIGGER WORDS.
22. **Edit-custom mode (`.edit(custom)`):** four sections — DETAILS / INSTRUCTIONS / TRIGGER WORDS (no TEMPLATES).
23. **Icon picker:** popover opens; picking an icon updates `selectedIcon` and closes popover.
24. **TextEditor (custom prompt body):** typing updates `promptText`; placeholder visible when empty.
25. **TextEditor (predefined prompt body):** read-only with 0.95 opacity. Copy button copies text to pasteboard.
26. **TriggerWordsEditor:** add / remove trigger words works.
27. **System Template toggle:** flips `useSystemInstructions`.
28. **Templates Menu:** clicking a template populates `title`, `promptText`, `selectedIcon`, `description` (only in `.add` mode).
29. **Save Changes button:** disabled if title or promptText is empty (custom only); enabled for predefined.
30. **Cancel button + Esc:** dismiss panel without saving.
31. **No double GlassCard:** outer editorPane GlassCard is the ONLY glass layer; inner ScrollView+VStack reads as content on glass.

#### Surface 4 — InlineHistoryView card list

32. **Card list:** GlassCards (14pt radius) at 12pt vertical spacing. NO macOS-grouped Form chrome.
33. **Card expand:** tap a card → expands to show tabs (Original / Enhanced) + scroll text + audio player (if audio).
34. **Card check toggle:** circular checkbox toggles selection. Selection bar appears at the bottom when ≥1 selected.
35. **Info button:** in expanded card → opens info panel (sliding panel from right).
36. **Pagination:** "Load More" GlassCard renders below; tapping triggers `loadMoreContent()`.
37. **Search filter:** typing in topBar search field re-fetches the list.
38. **Selection bar:** "Analyze" / "Export" / "Delete" / Select All / Deselect All work on the selected set.
39. **Empty state:** with no transcriptions, emptyStateView renders unchanged.

#### Surface 5 — AudioTranscribeView queue

40. **Queue list:** GlassCards (14pt radius) at 12pt vertical spacing. NO macOS-grouped Form chrome.
41. **AudioFileRow expansion:** tap → expands to show transcript + actions.
42. **Remove button:** removes item from queue.
43. **Retry button:** retries failed item.
44. **topBar:** unchanged from W13.D's perspective (any changes here are W13.C territory). Verify `Add` / `Start` / `Cancel` / `Clear` / `AI Enhancement Toggle` all work.
45. **Drop new files:** dropping into the visible area appends to queue.
46. **"Drop files anywhere to add more" footer:** renders at the bottom.
47. **Empty state (drop zone):** unchanged from W13.D's perspective (any changes here are W13.C territory).

### Accessibility passes

48. **Reduce Transparency = ON** (System Settings → Accessibility → Display → Reduce transparency). Re-open all 5 surfaces. Glass surfaces fall back to opaque per spec §6.4. All surfaces remain legible.
49. **Increase Contrast = ON.** Inner strokes become 1pt solid. All surfaces remain legible.
50. **Reduce Motion = ON.** No aggressive scaling/rotation on card expand/collapse / panel open/close.
51. **VoiceOver:** for each surface, traverse the focus order; SettingsCard `.accessibilityElement(children: .contain)` should announce the section header → content. SettingsRow `.accessibilityElement(children: .combine)` merges icon + label + subtitle into one announcement; controls remain independently focusable.

### Failure handling

52. **If any check fails**, surface to lead via SendMessage with screenshot + verbal description. Hot-fix paths in §Rollback. Behavior regressions are blocking — visual nits route to W13.G polish.

---

## Follow-ups for adjacent W13 packets

### W13.A — animation grammar codemod regressions

W13.A flagged but explicitly deferred animation literals inside the 5 W13.D surfaces:
- `EnhancementSettingsView.swift:45, 76, 88, 111, 123, 132, 144, 221, 239, 251, 285, 297` — `.smooth(0.3)` / `.spring(0.3, 0.7)` / `.easeInOut(0.15 / 0.12)` (12 sites).
- `Components/EnhancementSettingsPanel.swift:107, 111, 115, 132, 139, 156, 213, 215` — `.easeInOut(0.2)` / `withAnimation(.easeInOut(0.15))` (8 sites).
- `PromptEditorView.swift:544, 563` — `.spring(0.2, 0.7)` (already swapped to `Animation.haloExpand` in v1; verify).
- `History/InlineHistoryView.swift:86, 94, 99, 117, 184, 263, 271, 314, 332, 543, 564` — already mostly swept to `Animation.halo*` in v1 + `:117 = .smooth(0.3)` deferred (verify).
- `AudioTranscribeView.swift:41, 64, 110, 115, 124, 217, 296` — `.easeInOut(0.2 / 0.15)` (7 sites).

Total: ~30 animation-literal sites. Recommend **W13.A regression catch packet** (or fold into W13.G polish) AFTER W13.D merges to grouped-codemod the lot in one commit.

### W13.C — overlap on AudioTranscribeView

W13.D scope is queueFormView (lines 98-141). W13.C scope is emptyStateView (drop zone), topBar (pill buttons), dropOverlay. No file-line overlap, but same file. Coordinate at integration build via team-lead.

### W13.E — AI Models card unification

W13.E rebuilds `WhisperModelCardView`, `CloudModelCardView`, `FluidAudioModelCardView`, `NativeAppleModelCardView`, `CustomModelCardView`, `MLXModelPickerView` row card. Surface 1's APIKeyManagementView body reshape is W13.D scope; the ProviderCard inner cards remain W13.E territory. No overlap.

### W13.F — History window glass + animation codemod

W13.F handles the standalone History window (`HistoryWindowController.swift`, `TranscriptionHistoryView.swift`). Surface 4 (InlineHistoryView cardListView) is the embedded-in-main-window history; it's W13.D scope. The `InlineHistoryView` topBar search Capsule (R4 row 30) is W13.F scope (search-field re-skin). No file-line overlap inside the cardListView.

### W13.G — Polish

Polish targets touched-but-not-edited inside W13.D surfaces:
- `EnhancementSettingsView.swift:88, 145` (`.ultraThinMaterial` button chrome — gear / plus).
- `Components/EnhancementSettingsPanel.swift:33-40` (xmark button chrome).
- `Components/EnhancementSettingsPanel.swift:312-321` (LastSystemPromptViewer's `.ultraThinMaterial` card).
- `PromptEditorView.swift:103, 286, 472` (`.ultraThinMaterial` close button, icon button, trigger-word pill).
- `PromptEditorView.swift:472-477` (TriggerWordItemView pill — R4 row 23 `glassChip(10)` swap).
- `History/InlineHistoryView.swift:574-576` (Capsule tab affordance).

Plus the animation-literal sites noted in W13.A follow-up above. Total: ~10 polish edits + ~30 animation codemod hits.

### Other Form-host surfaces NOT in W13.D

`grep -n 'Form \{' VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift` — line 46 hosts a Form. NOT in master plan §4 W13.D's 5-list. Recommend follow-up packet `W13.D2 — DictionarySettingsPanel Form purge` if user wants exhaustive coverage. Out of scope here.

### Final spec extension (after W13.A-G land, per master plan §4 W13.G)

Amend `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.X (or write `2026-04-30-aesthetic-redesign-W13-deltas.md`) with:
- W13.D `sectionBlock` compact-section idiom: 11pt SF-mono uppercase tracked label + optional InfoTip + content stack. Used in narrow-popover surfaces where SettingsCard chrome would double-layer over panel-glass background. Codify if reviewer adopts this beyond W13.D.
- Locked decision: SettingsCard is for icon-headed settings sections (i.e. `SettingsView`-host pages); content cards (HistoryCardRow / AudioFileRow / model-result cards) use raw `GlassCard(cornerRadius: 14)` without an icon-tile header.
- APIKeyManagementView body reshape: documented as a `SettingsCard`-rooted view (no `Section` envelope); future call sites authoring a Section wrapper need to add their own.
