# W13.G — Polish + final spec extension

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Reviewer is `superpowers:code-reviewer`.

**Date:** 2026-04-30
**Author:** planner-w13g (team `voiceink-phase23`)
**Sources:**
- Master plan §4 W13.G + final-spec-extension note: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`
- R4 audit (rows 8 / 28 / 23 / 27 / 25 / 32 / 33; §3.1 anti-pattern table; §4 W13-G bullet list): `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md`
- W13.A–F sibling plans (§Follow-ups for adjacent W13 packets): `W13A-token-sweep.md`, `W13B-metrics-rebuild.md`, `W13C-permissions-audiotranscribe.md`, `W13D-form-host-purge.md`, `W13E-ai-models-cards.md`, `W13F-history-window-glass.md`
- Vocabulary primitives: `Palette.swift` / `GlassChip.swift` / `GlassCard.swift` / `Animation+Halo.swift` / `AdaptiveGlassBackground.swift` (under `VoiceInk/Views/Common/`)
- Existing spec doc to amend: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md`

**Goal:** close out Phase 3 by sweeping every leftover surface that didn't fit W13.A-F, then codify the W13-era spec deltas. Visual-only + spec-doc updates. No primitive drift, no schema changes, no SPM changes, no deployment-target change.

**Q-decisions honored (from master plan §0):**
- **Q9=a** (hero gradient on `Palette.accent`) — already landed in W13.B; codified in §Spec amendment.
- **Q7=b** (menubar dropdown stays system-default) — restated in §Spec amendment.
- **Q8=a** (History as separate window) — already landed in W13.F; out of W13.G.

**CLAUDE.md cadence rules respected:**
- **Single integration build at merge time** (per `feedback_skip_per_packet_builds.md`). One `xcodebuild build` at the end.
- **Plan-files-committed-alongside-impl.** This document lands in `docs(plans): W13G — polish + spec extension` followed by `feat(aesthetic): W13G — polish + spec extension` for the visual codemod and `docs(specs): W13 deltas — append §1.X / §2.4` for the spec amendment.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** Inline doc-comments cite spec §1 / §2.4 + this plan path; no PR numbers.
- **Pre-existing spec-ref comments preserved** (`Palette.swift` §1, `GlassChip.swift` §1, `Animation+Halo.swift:14-17` reviewer note, `HaloMaterial.swift` §2.3 / §6.4).

**Architecture (axes):**

```
Axis                                          Source                                       Target
──────────────────────────────────────        ──────────────────────────────────           ───────────────────────────
A. CompactHeroSection icon                    .foregroundStyle(.blue)                       .foregroundStyle(Palette.accent)
B. AppNotificationView per-type rainbow       .red/.yellow/.blue/.green per case            .accent (error/warning/info)
                                                                                            .success (success)
                                                                                            motion (progress bar) is discriminator
C. controlBackgroundColor / windowBackgroundColor   chip-level affordances                  glassChip / glassPanel / drop modifier
   chip-level affordances                                                                    (W13.A axis-G defer table closing pass)
D. Hand-rolled glass / Apple-system cards     PromptChipPicker chips, EnhancementPromptPopover     glassChip(cornerRadius: 10)
                                              backdrop, PredefinedPromptsView buttons       glassPanel(cornerRadius: 14)
                                                                                            GlassCard(cornerRadius: 16)
E. CustomPrompt.promptIcon radial-glow tile   accentColor radial gradient + decorative      GlassCard(cornerRadius: 14) + Palette.accent
                                              circles + accent shadow + windowBg backplate   tile family
F. PowerModeView hero header                  plain HStack `.system(28, .bold)`             SettingsSectionHeader (bolt.fill + Palette.warn)
G. Animation residual flags                   PromptChipPicker easeOut/easeIn(halfDuration: 0.2)    new spec token: haloPulseTwoPhase
                                              PowerModeStripView easeInOut(0.5).repeatForever       new spec token: haloAttentionBreathe
                                              PowerModeStripView easeInOut(0.14)                    new spec token: haloMicro (sub-150ms)
H. Final spec extension                       —                                              append §1.X.W13 to existing aesthetic-redesign.md
                                                                                              (Option B: write -deltas.md companion — see Open Q3)
```

**Tech Stack:** Swift 5.x, SwiftUI, AppKit (`NSColor` only via the call sites we sweep), Xcode 16.x. Build via `make local` (~3 min cold). No new deps. No new tests.

---

## File structure

### New files

- `docs/superpowers/specs/2026-04-30-aesthetic-redesign-W13-deltas.md` — **Conditional on Open Q3.** If lead picks Option A (append in-place), this file is NOT created and the deltas land directly in `2026-04-28-aesthetic-redesign.md` §1.X. If Option B (separate companion), this file lands.
- (Optional) `VoiceInk/Views/Common/Animation+Halo.swift` gains 1-3 new tokens — pending Open Q4. Default: do NOT add new tokens; flag existing literals in spec as sanctioned exceptions per axis G.

### Modified files

(13-15 surfaces across axes A-F. Per-line edits detailed in §Replacement table.)

- `VoiceInk/Views/Common/CompactHeroSection.swift` — `.blue` → `Palette.accent` (axis A; touches Permissions + AudioInputSettings + DictionarySettings simultaneously).
- `VoiceInk/Notifications/AppNotificationView.swift` — per-type rainbow recolor (axis B).
- `VoiceInk/Views/Common/CopyIconButton.swift` — `controlBackgroundColor` chip → `glassChip(cornerRadius: 14)` Capsule (axis C).
- `VoiceInk/Views/Common/SaveIconButton.swift` — same treatment as CopyIconButton (axis C).
- `VoiceInk/Views/History/HistoryShortcutTipView.swift` — `controlBackgroundColor` 12pt card + `accentColor` icon → `glassPanel(cornerRadius: 12)` + `Palette.accent` (axis C + A residual).
- `VoiceInk/Views/Settings/EnhancementShortcutsView.swift` — `controlBackgroundColor` row chrome → `glassPanel(cornerRadius: 10)` (axis C).
- `VoiceInk/Views/Settings/AudioInputSettingsView.swift:426` — priority-list chip `controlBackgroundColor` → `glassChip(cornerRadius: 10)` (axis C).
- `VoiceInk/PowerMode/PowerModeConfigView.swift:349` — `controlBackgroundColor` chrome → `glassPanel(cornerRadius: 12)` (axis C).
- `VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift:367` — `controlBackgroundColor` chrome → `glassPanel(cornerRadius: 12)` (axis C).
- `VoiceInk/Views/PromptEditorView.swift` — TriggerWordItemView (lines 470-478) `.ultraThinMaterial` 4pt → `glassChip(cornerRadius: 10)` (axis D).
- `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift` — `.ultraThinMaterial` 12pt + forced `.dark` colorScheme (lines 50-58) → `glassPanel(cornerRadius: 14)` + drop force-dark (axis D).
- `VoiceInk/Views/PredefinedPromptsView.swift` — full template-button rebuild → `GlassCard(cornerRadius: 16)` + tinted icon tile (axis D).
- `VoiceInk/Models/CustomPrompt.swift` — `promptIcon` extension (lines 138-303) full rebuild — radial-glow tile family → flat `GlassCard(cornerRadius: 14)` + `Palette.accent` selection state + spec-clean icon tile (axis E). **Largest single edit in this packet.**
- `VoiceInk/PowerMode/PowerModeView.swift` — heroHeader (lines 103-124) → `SettingsSectionHeader(icon: "bolt.fill", title: "Power Modes", accent: Palette.warn)` (axis F).
- `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` — append §1.X.W13 deltas section (axis H, Option A).

### Excluded files (DO NOT touch — drift guard)

Per master-plan scope and prior packet routing:

**Out of scope — separate packets / open questions:**
- W13.D (Form-host purge) — in review by reviewer-w13d. Touch nothing in EnhancementSettingsView, EnhancementSettingsPanel, PromptEditorView Form panes (`:223-366`), InlineHistoryView cardListView (`:255-298`), AudioTranscribeView queue Form, DictionarySettingsPanel.
- Tabbed-settings UX (Task #14) — open question (Open Q1) for lead. Default: do NOT widen scope; ship as W13.H if user picks fold-here.
- `Metrics/PerformanceAnalysisPanelView.swift:20, 109` — flagged in W13.F as W13.B residual debt. **Recommendation:** fold into W13.G (see Open Q2). If Open Q2 picks fold-here, this file enters the modified list. Default in this plan: **fold-into-W13.G**, since the alternative (separate W13.B2/B3) duplicates a 2-line sweep into its own packet for marginal gain.
- `Metrics/PerformanceAnalysisPanelView.swift:69-71` rainbow `(.indigo, .teal, .mint)` summary pills — flagged sub-bullet of the same fold-into-W13.G recommendation. If folded in, sweep to single `Palette.accent` icon palette + motion as discriminator (mirrors W13.B MetricCard family-aligned-icon decision).
- `Metrics/MetricsSetupView.swift` welcome rebuild — W13.B2 territory per W13.B §Follow-ups. Out of W13.G scope unless lead pulls forward (no recommendation here).
- `Metrics/PerformanceAnalysisView.swift` (the full hosted view, not the panel) — W13.B3 territory. Out of W13.G scope.

**Floating-bar / recorder cluster — UNTOUCHED (source of vocabulary):**
- `VoiceInk/Views/Recorder/HaloMaterial.swift`, `HaloRecorderView.swift`, `HaloShape.swift`
- `VoiceInk/Views/Recorder/MiniRecorderPanel.swift`, `MiniWindowManager.swift`
- `VoiceInk/Views/Recorder/NotchRecorderPanel.swift`, `NotchWindowManager.swift`
- `VoiceInk/Views/Recorder/RecorderComponents.swift` (recorder-state animations stay)
- `VoiceInk/Views/Recorder/RecorderStateProvider.swift`
- `VoiceInk/Views/Recorder/AudioVisualizerView.swift`
- `VoiceInk/Views/Recorder/Constellation/*.swift` (full directory)
- (Note: `EnhancementPromptPopover.swift` IS in scope here — it's a recorder satellite popover, not a recorder cluster panel; spec §1.X line 47 puts it in W8 but its glass treatment was deferred to W13.G per W13.A.)

**Glass primitive files — UNTOUCHED (vocabulary itself):**
- `VoiceInk/Views/Common/GlassChip.swift`, `GlassCard.swift`, `GlassSwitch.swift`, `Palette.swift`, `Animation+Halo.swift` (UNLESS Open Q4 picks "add tokens" — in which case Animation+Halo.swift gains 1-3 named tokens with spec sources), `AdaptiveGlassBackground.swift`, `KeyCapView.swift`, `HaloMaterial.swift`.

**Menubar dropdown (Q7=b — system-default):**
- `VoiceInk/Views/MenuBarView.swift`, `VoiceInk/MenuBarManager.swift`.

**Tests:**
- `VoiceInkTests/*.swift` and `VoiceInkUITests/*.swift` — out of W13.G scope.

---

## Migration policy (resolves ambiguity for each design point)

1. **`controlBackgroundColor` chip-level affordances split into two patterns.** When the affordance is a circle/capsule with a single fill + clipShape (Copy/SaveIconButton 28pt circle, AudioInputSettingsView priority chip), swap to `glassChip(cornerRadius: 14)` (Capsule) or `glassChip(cornerRadius: 10)` (small chip). When the affordance is a rect-with-stroke card (HistoryShortcutTipView 12pt + separatorColor stroke, EnhancementShortcutsView, PowerModeConfigView, DictionaryQuickAddPanel), swap to `glassPanel(cornerRadius: 10/12/14)` per local geometry.

2. **AppNotificationView per-type recolor — preserve `.error` semantics via motion, not red.** The HUD progress bar at `:121` becomes the per-type discriminator: faster decrement on `.error` (existing duration parameter already drives this), slower on `.info`. Icon + CTA chip text + progress bar all key to `Palette.accent` for `.error/.warning/.info`, `Palette.success` for `.success`. Verbal/screen-reader semantics retained via `iconName` (xmark.octagon.fill, exclamationmark.triangle.fill, info.circle.fill, checkmark.circle.fill) — VoiceOver still reads "error", "warning", etc. **Open Q5 (legibility):** lead picks whether to retain `.red` for `.error` as a sanctioned exception (high-stakes error legibility) or unify to tangerine across the board. **Recommendation:** unify — recorder cluster's "failed" state already uses tangerine + motion (HaloShake) and has shipped under W3; HUD failure is a strict subset.

3. **PermissionCard CTA button (R4 row 6) — KEEP solid `Palette.accent` capsule per W13.C decision.** W13.C explicitly preserved this as primary CTA. Open Q6 from W13.C ("keep solid or wrap in glassChip + accentMuted?") deferred to W13.G; this plan recommends KEEP. Lead can override.

4. **PermissionCard icon tile geometry drift (R4 row 7) — sweep to `SettingsSectionHeader` constants.** Current: 10pt rad / 44×44 / 0.18 fill / 0.36 stroke 0.5pt. Target per spec §2.6: 7pt rad / 28×28 / 0.16 fill / 0.32 stroke 0.5pt — but the PermissionCard icon hosts a 20pt SF symbol that needs ~44pt frame for legibility. **Recommendation:** narrow the drift but preserve the 44×44 size. New constants: 7pt rad / 44×44 / 0.16 fill / 0.32 stroke 0.5pt. Functional `Palette.success` / `Palette.warn` tint stays per spec §1 (non-state semantics retained).

5. **CompactHeroSection icon — single-line `.blue` → `Palette.accent` swap.** Touches Permissions, AudioInputSettings, DictionarySettings call sites simultaneously. No per-call-site override needed.

6. **EnhancementPromptPopover — drop forced `.dark` colorScheme.** The recorder satellite should follow `GlassAppearanceDetector` (light/dark wallpaper detection) like every other glass surface. After swap to `glassPanel(cornerRadius: 14)`, the inner text foregrounds at `:82, :85, :13, :92` use white-with-opacity which read correctly only on dark glass. Risk: under bright wallpaper, glass goes to `.aqua` variant and white-on-light text becomes unreadable. **Mitigation:** swap inner text colors to `Palette.onyxFg` / `Palette.onyxMute` (which read correctly on both onyx and light glass per recorder-cluster shipped behavior). The `.green` checkmark at `:92` becomes `Palette.success` (sanctioned non-state).

7. **PredefinedPromptsView template buttons — full rebuild.** Replace cardBackground/cardStroke/cardShadowColor (lines 67-89) with `GlassCard(cornerRadius: 16)`. Inner icon tile (lines 32-40) `unemphasizedSelectedTextBackgroundColor` 10pt rect → `Palette.accent.opacity(0.16)` fill + `Palette.accent.opacity(0.32)` stroke (mirrors `SettingsSectionHeader` icon tile vocabulary). Title + description type stays.

8. **CustomPrompt.promptIcon (Models/CustomPrompt.swift:138-303) — full tile family rebuild.** Replace radial-glow + decorative-blurred-circles + accent-shadow stack with flat `GlassCard(cornerRadius: 14)` + `Palette.accent` selection ring + W13.E-aligned hairline strokes. Selected state: 1.5pt `Palette.accent` border + 0.55 alpha glow shadow (mirrors W13.E AI Models card vocabulary). Rest state: 1pt `Palette.hairline`. Icon stays at the 20pt SF symbol with `Palette.accent` (selected) / `Palette.onyxFg` (rest) tint. Mic-glyph + selected-checkmark sub-bullets at `:239-262` recolor to `Palette.accent` (selected) / `Palette.onyxMute` (rest). Add-prompt + edit/delete tile variants at `:300-380` get the same treatment.

9. **PowerModeView heroHeader → `SettingsSectionHeader`.** Use `SettingsSectionHeader(icon: "bolt.fill", title: "Power Modes", accent: Palette.warn)` per master plan §4 W13.G + R4 row 28. The InfoTip at `:110-113` migrates into a sibling row below the SettingsSectionHeader (mirrors `SettingsView.swift` Privacy section pattern). The "Switch context automatically..." subtitle at `:116-118` becomes the SettingsSectionHeader's `subtitle:` parameter (verify primitive supports it; if not, render as `.font(.system(size: 13)) .foregroundColor(.secondary)` row below the header).

10. **Animation residual flags — DO NOT codemod, document.** Three sites have no current halo token:
    - `Common/PromptChipPicker.swift:125, 129` — `easeOut(halfDuration: 0.2) → easeIn(halfDuration: 0.2)` (total 0.4s 2-phase pulse)
    - `PowerMode/PowerModeStripView.swift:181` — `easeInOut(0.5).repeatForever` (warn pulse)
    - `PowerMode/PowerModeStripView.swift:275` — `easeInOut(0.14)` (drag-drop micro-animation)
    
    Default: leave literals, sanction in spec amendment as documented exceptions. Open Q4 covers whether to add new halo tokens (`haloPulseTwoPhase` / `haloAttentionBreathe` / `haloMicro`) instead.

11. **PerformanceAnalysisPanelView fold-in (Open Q2 = fold-here-recommended).** If Open Q2 picks fold-here:
    - `:20` — drop `.background(Color(NSColor.windowBackgroundColor))` modifier line entirely (mirror W13.F's `:133` treatment).
    - `:109` — `Color(NSColor.controlBackgroundColor)` system-info row backplate → `glassPanel(cornerRadius: 10)`. Quaternary stroke at `:112` → `Palette.hairlineSoft`.
    - `:69-71` rainbow summary pills (.indigo / .teal / .mint) → single `Palette.accent` (or keep functional differentiation via `Palette.accent` / `Palette.success` / `Palette.neutral`; recommend single accent, motion is discriminator).
    - `:82` `design: .rounded` numeral KEEPS per Q9=a + W7 (chart numeral exception).
    
    If Open Q2 picks defer, this file stays UNTOUCHED and routes to W13.B3 / a future packet.

12. **Spec amendment scope (Open Q3 = append-in-place recommended).** §1.X.W13 deltas section appended to `2026-04-28-aesthetic-redesign.md` after the existing §1.X (W8 extension). New subsection numbers: §1.X.W13.1 (Q9=a hero exception), §1.X.W13.2 (single-accent metric icon palette), §1.X.W13.3 (`glassPanel(cornerRadius: 16)` Help/Resources idiom), §1.X.W13.4 (soft-pill `glassChip(18)` button capsules), §1.X.W13.5 (family-aligned strokes for AI Models cards), §1.X.W13.6 (flat sectionBlock pattern for popover/editorPane surfaces), §1.X.W13.7 (single-accent HUD notification + motion discriminator), §1.X.W13.8 (Q7=b menubar restated), §1.X.W13.9 (animation token sanctioned exceptions). Plus a §2.4-W13 sub-section listing the Halo token mapping table from W13.A migration policy point 4 (canonicalize so future packets don't re-litigate). Spec amendment commits separately from the codemod commit.

13. **No new tests.** W13.G is pure visual-vocabulary polish + spec-doc updates. Existing `PaletteTests` (2) + `FailureRegistryTests` (5) + `VoiceInkUITests` (4) must still pass at the integration build. No regressions to assert programmatically — visual smoke is the gate.

---

## Replacement table

Every line below is a grep-validated hit. **Sweep** = land in W13.G. **Defer** = leave for the named packet. **Flag** = ambiguous; coder evaluates context.

### Axis A — `CompactHeroSection` icon `.blue` → `Palette.accent`

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/Common/CompactHeroSection.swift:13` | `.foregroundStyle(.blue)` | `.foregroundStyle(Palette.accent)` | **Sweep** | Single-line edit. Touches Permissions / AudioInputSettings / DictionarySettings call sites simultaneously. Master plan §4 W13.G explicit bullet. |

### Axis B — `AppNotificationView` per-type rainbow → single accent + motion

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Notifications/AppNotificationView.swift:31` | `case .error: return .red` | `case .error: return Palette.accent` | **Sweep** (default) / **Flag** if Open Q5 picks retain-red | Spec §1 single-accent live-state vocabulary; recorder cluster failure also uses tangerine + HaloShake motion as discriminator. |
| `VoiceInk/Notifications/AppNotificationView.swift:32` | `case .warning: return .yellow` | `case .warning: return Palette.accent` | **Sweep** | Same. |
| `VoiceInk/Notifications/AppNotificationView.swift:33` | `case .info: return .blue` | `case .info: return Palette.accent` | **Sweep** | Same. |
| `VoiceInk/Notifications/AppNotificationView.swift:34` | `case .success: return .green` | `case .success: return Palette.success` | **Sweep** | Sanctioned non-state semantic per spec §1. |
| `VoiceInk/Notifications/AppNotificationView.swift:68` | `.background(type.iconColor.opacity(0.15))` | (unchanged — `iconColor` now resolves to `Palette.accent` / `Palette.success`) | **Sweep — by transitive update** | CTA chip backplate inherits the recolor for free. |
| `VoiceInk/Notifications/AppNotificationView.swift:69` | `.clipShape(RoundedRectangle(cornerRadius: 6))` | `.glassChip(cornerRadius: 8)` (replace background+clipShape stack) | **Flag — sweep if surrounding chrome matches** | Polish: 6pt below spec's 10pt chip minimum; bring in line. Coder may keep 6pt rad if it visually reads better as a small inline chip. |
| `VoiceInk/Notifications/AppNotificationView.swift:121` | `Rectangle().fill(type.iconColor.opacity(0.8))` (progress bar) | (unchanged — `iconColor` transitive update) | **Sweep — by transitive update** | Progress bar tangerine (or success-green for `.success`) matches body chrome. |

### Axis C — `controlBackgroundColor` / `windowBackgroundColor` chip-level affordances

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/Common/CopyIconButton.swift:13` | `.background(Color(NSColor.controlBackgroundColor).opacity(0.9)) .clipShape(Circle())` | `.glassChip(cornerRadius: 14)` (Capsule shape via `cornerRadius: 999` if `glassChip` exposes that, OR keep Circle clipShape and apply `glassPanel(cornerRadius: 14)` background-only) | **Sweep** | 28pt circle chip; W13.A axis-G defer routed here. |
| `VoiceInk/Views/Common/SaveIconButton.swift:21` | `.background(Color(NSColor.controlBackgroundColor).opacity(0.9)) .clipShape(Circle())` | Same as CopyIconButton | **Sweep** | Mirrors. |
| `VoiceInk/Views/History/HistoryShortcutTipView.swift:10` | `.foregroundColor(.accentColor)` (icon) | `.foregroundColor(Palette.accent)` | **Sweep** (axis A residual hit) | W13.A axis-A defer routed here. |
| `VoiceInk/Views/History/HistoryShortcutTipView.swift:40` | `RoundedRectangle 12 .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))` | `glassPanel(cornerRadius: 12)` (replace background+overlay stack) | **Sweep** | W13.F §Follow-ups routed here; W13.A axis-G defer table also routed here. |
| `VoiceInk/Views/History/HistoryShortcutTipView.swift:43-44` | `.strokeBorder(Color(NSColor.separatorColor).opacity(0.3), lineWidth: 1)` | (subsumed into `glassPanel`) | **Sweep — by transitive replacement** | `glassPanel` modifier provides hairline. |
| `VoiceInk/Views/Settings/EnhancementShortcutsView.swift:61` | `.fill(Color(NSColor.controlBackgroundColor))` | `glassPanel(cornerRadius: 10)` (replace fill + any companion stroke) | **Sweep** | W13.A axis-G defer routed here. |
| `VoiceInk/Views/Settings/AudioInputSettingsView.swift:426` | `.fill(Color(.windowBackgroundColor).opacity(0.4))` | `glassChip(cornerRadius: 10)` | **Sweep** | priority-list chip; W13.A axis-G defer routed here. |
| `VoiceInk/PowerMode/PowerModeConfigView.swift:349` | `.fill(Color(NSColor.controlBackgroundColor))` | `glassPanel(cornerRadius: 12)` | **Sweep** | W13.A axis-G defer routed here. |
| `VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift:367` | `.fill(Color(NSColor.controlBackgroundColor).opacity(0.7))` | `glassPanel(cornerRadius: 12)` | **Sweep** | W13.A axis-G defer routed here. |

### Axis D — Hand-rolled glass / Apple-system cards → primitives

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/PromptEditorView.swift:472-477` | `.background(.ultraThinMaterial) .cornerRadius(4) .overlay(stroke Color.secondary.opacity(0.2))` (TriggerWordItemView) | `.glassChip(cornerRadius: 10)` | **Sweep** | R4 row 23; W13.A axis-C defer flagged for context-eval; line is past Form close (Form ends at :363) so W13.D form purge does NOT cover it. |
| `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift:50-58` | `.fill(.ultraThinMaterial) .overlay(stroke Palette.hairline 1pt) cornerRadius 12pt + .environment(\.colorScheme, .dark)` | `glassPanel(cornerRadius: 14)` (replace background stack) — DROP the `.environment(\.colorScheme, .dark)` line | **Sweep** | R4 row 27; recorder satellite. Inner text foregrounds at `:13, :82, :85, :92` recolor to `Palette.onyxFg / .onyxMute / .accent / .success` per Migration policy point 6. |
| `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift:23` | `.background(Color.white.opacity(0.1))` (Divider) | `.background(Palette.hairlineSoft)` | **Sweep** | W13.A axis-B defer; α 0.1 → exact `hairlineSoft` token. |
| `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift:82, 85` | `.foregroundColor(.white.opacity(0.4 / 0.7 / 0.9))` | `.foregroundColor(isDisabled ? Palette.onyxMute : Palette.onyxFg)` | **Sweep — by Migration policy point 6** | Drop forced-dark requires light-glass legibility. `Palette.onyxFg` reads on both variants per shipped recorder cluster. |
| `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift:92` | `.foregroundColor(isDisabled ? .green.opacity(0.7) : .green)` | `.foregroundColor(isDisabled ? Palette.success.opacity(0.7) : Palette.success)` | **Sweep** | Sanctioned non-state semantic. |
| `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift:102` | `.background(isSelected ? Color.white.opacity(0.1) : Color.clear)` | `.background(isSelected ? Palette.hairlineSoft : Color.clear)` | **Sweep** | α 0.1 → exact `hairlineSoft`. |
| `VoiceInk/Views/PredefinedPromptsView.swift:32-40` (icon tile) | `RoundedRectangle 10 .fill(Color(NSColor.unemphasizedSelectedTextBackgroundColor)) + Image .foregroundColor(Color(NSColor.labelColor))` | `RoundedRectangle 10 .fill(Palette.accent.opacity(0.16)) .overlay(stroke Palette.accent.opacity(0.32) 0.5pt) + Image .foregroundColor(Palette.accent)` | **Sweep** | Mirrors `SettingsSectionHeader` icon tile vocabulary. |
| `VoiceInk/Views/PredefinedPromptsView.swift:67-89` (cardBackground / cardStroke / cardShadowColor) | `RoundedRectangle 16 .fill(controlBackgroundColor) + LinearGradient stroke separator + shadowColor` | `GlassCard(cornerRadius: 16)` | **Sweep** | R4 row 25; full Apple-system card → primitive. |
| `VoiceInk/Views/PredefinedPromptsView.swift:38, 51` | `.foregroundColor(Color(NSColor.labelColor))` / `.foregroundColor(Color(NSColor.secondaryLabelColor))` | `.foregroundColor(.primary)` / `.foregroundColor(.secondary)` | **Sweep — token cleanup** | Drop NSColor wrappers for SwiftUI semantic colors (already system-adaptive). |

### Axis E — `CustomPrompt.promptIcon` radial-glow tile family rebuild

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Models/CustomPrompt.swift:143-181` (selected-state RoundedRectangle 14 + accentColor LinearGradient + accentColor shadow) | `GlassCard(cornerRadius: 14)` + selection ring `RoundedRectangle 14 .stroke(Palette.accent, lineWidth: 1.5)` + glow shadow `Palette.accent.opacity(0.55)` rad 18 | **Sweep** | R4 §1 anti-pattern: hand-rolled radial-glow tile is anti-spec. Mirror W13.E family-aligned-strokes vocabulary (active 1.5pt / 0.55 alpha; rest hairline 1pt). |
| `VoiceInk/Models/CustomPrompt.swift:184-200` (decorative blurred Circle radial gradient) | DELETE entirely | **Sweep** | Decorative noise; not in spec. |
| `VoiceInk/Models/CustomPrompt.swift:202-210` (Image symbol `.foregroundColor(isSelected ? .white : .accentColor)`) | `.foregroundColor(isSelected ? Palette.accent : Palette.onyxFg)` | **Sweep** | Selected state inverts to accent (matches PromptChipPicker selected vocabulary at `Common/PromptChipPicker.swift:60`). |
| `VoiceInk/Models/CustomPrompt.swift:215-225` (blurred glow Circle .fill `Color.accentColor.opacity(0.5)` when selected) | DELETE entirely | **Sweep** | Glow is now the GlassCard's selection-ring shadow above; no per-tile blur Circle. |
| `VoiceInk/Models/CustomPrompt.swift:241, 250` (mic-glyph + checkmark `.foregroundColor(.accentColor.opacity(0.9))` / `.secondary.opacity(0.7)`) | `.foregroundColor(isSelected ? Palette.accent : Palette.onyxMute)` | **Sweep** | Sub-bullet recolor. |
| `VoiceInk/Models/CustomPrompt.swift:300-385` (add-prompt + edit/delete tile variants) | Same treatment: `GlassCard(cornerRadius: 14)` + `Palette.accent` selection + `Palette.hairline` rest | **Sweep** | Tile family unification. |
| `VoiceInk/Models/CustomPrompt.swift:152-153, 315-316` (`Color(NSColor.controlBackgroundColor).opacity(0.95 / 0.85)` as gradient stops) | DELETE entirely (subsumed into `GlassCard`) | **Sweep** | W13.A axis-G defer routed here. |

**Risk note:** `CustomPrompt.swift` is a Models-layer file with a SwiftUI extension. The extension method signature stays identical (`func promptIcon(isSelected:onTap:onEdit:onDelete:) -> some View`) — call sites at `EnhancementSettingsView` / `EnhancementSettingsPanel` / `PromptChipPicker` (post-W13.D) need zero changes. Verify by grep at Task 0.

### Axis F — `PowerModeView` heroHeader → `SettingsSectionHeader`

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/PowerMode/PowerModeView.swift:103-124` (`heroHeader`) | `VStack { HStack { Text "Power Modes" .system(28, .bold) + InfoTip } + Text "Switch context..." .system(14) }` | `SettingsSectionHeader(icon: "bolt.fill", title: "Power Modes", subtitle: "Switch context automatically based on the active app or website.", accent: Palette.warn)` + InfoTip rendered as sibling row below | **Sweep** | R4 row 28; master plan §4 W13.G bullet. **Verify** `SettingsSectionHeader` primitive supports `subtitle:` parameter; if not, render subtitle as sibling row (`.font(.system(size: 13)).foregroundColor(.secondary)`). |

**Verify:** `SettingsSectionHeader` API at `VoiceInk/Views/Common/SettingsSectionHeader.swift:29-79` — Task 0 grep confirms `init(icon:title:subtitle:accent:)` shape. If `subtitle:` is absent, fall back to inline `Text` row (no primitive change in this packet — primitive evolution is W13.G post-merge).

### Axis G — Animation residual flags (DOCUMENT, do NOT codemod)

| File:line | Current | Disposition | Rationale |
|---|---|---|---|
| `VoiceInk/Views/Common/PromptChipPicker.swift:125, 129` | `.easeOut(duration: 0.2)` → `.easeIn(duration: 0.2)` (2-phase, total 0.4s) | **Document — sanctioned exception OR add `Animation.haloPulseTwoPhase` token** (Open Q4) | Custom 2-phase ramp-up + ramp-down for selection pulse; no current halo token shape matches. |
| `VoiceInk/PowerMode/PowerModeStripView.swift:181` | `.easeInOut(duration: 0.5).repeatForever(autoreverses: true)` | **Document — sanctioned exception OR add `Animation.haloAttentionBreathe` token** (Open Q4) | 0.5s breathe is 0.31× the rate of `haloBreathe (1.6s)`; intentional (active-mode pulse is more urgent than enhancing-state breath). |
| `VoiceInk/PowerMode/PowerModeStripView.swift:275` | `.easeInOut(duration: 0.14)` | **Document — sanctioned exception OR add `Animation.haloMicro` token** (Open Q4) | Sub-150ms drag-drop micro-animation; below `haloPhaseCrossfade` band (0.22s). |

### Axis H — Final spec extension (append §1.X.W13 deltas)

See §Spec amendment section below. Lands as a separate `docs(specs)` commit AFTER the W13.G feat commit.

### Axis I — PerformanceAnalysisPanelView fold-in (CONDITIONAL on Open Q2)

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:20` | `.background(Color(NSColor.windowBackgroundColor))` | DROP modifier line entirely | **Sweep — if Open Q2 picks fold-here** | Mirrors W13.F TranscriptionHistoryView:133 sweep. |
| `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:69-71` | `.indigo / .teal / .mint` per-pill rainbow | single `Palette.accent` (or kept-functional `Palette.accent / .success / .neutral`; recommend single accent) | **Sweep — if Open Q2 picks fold-here** | Mirrors W13.B family-aligned icon palette decision. |
| `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:107-114` | `RoundedRectangle 10 .fill(Color(NSColor.controlBackgroundColor)) + .stroke(Color(NSColor.quaternaryLabelColor).opacity(0.3))` | `glassPanel(cornerRadius: 10)` | **Sweep — if Open Q2 picks fold-here** | Hairline via primitive. |

---

## Tasks

### Task 0: Audit + grep validation (read-only)

**Files:** none.

- [ ] **Step 0.1: Re-run all axis greps and confirm hit counts match this plan**

```bash
# Axis A — CompactHeroSection .blue
rg -n 'foregroundStyle\(\.blue\)' VoiceInk/Views/Common/CompactHeroSection.swift

# Axis B — AppNotificationView per-type rainbow
rg -n 'case \.error|case \.warning|case \.info|case \.success' VoiceInk/Notifications/AppNotificationView.swift

# Axis C — controlBackgroundColor / windowBackgroundColor (W13.G subset)
rg -n 'windowBackgroundColor|controlBackgroundColor' VoiceInk/Views/Common/CopyIconButton.swift VoiceInk/Views/Common/SaveIconButton.swift VoiceInk/Views/History/HistoryShortcutTipView.swift VoiceInk/Views/Settings/EnhancementShortcutsView.swift VoiceInk/Views/Settings/AudioInputSettingsView.swift VoiceInk/PowerMode/PowerModeConfigView.swift VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift

# Axis D — hand-rolled glass for sweep targets
rg -n '\.ultraThinMaterial' VoiceInk/Views/PromptEditorView.swift VoiceInk/Views/Recorder/EnhancementPromptPopover.swift
rg -n 'controlBackgroundColor|unemphasizedSelectedTextBackgroundColor|separatorColor|shadowColor' VoiceInk/Views/PredefinedPromptsView.swift

# Axis E — CustomPrompt promptIcon
rg -n 'Color\.accentColor|controlBackgroundColor|RoundedRectangle\(cornerRadius: 14\)' VoiceInk/Models/CustomPrompt.swift

# Axis F — PowerModeView heroHeader API check
rg -n 'init\(icon|init\(icon:title|init\(icon:title:subtitle' VoiceInk/Views/Common/SettingsSectionHeader.swift

# Axis G — flagged animation literals (verify they exist; do NOT sweep)
rg -n 'halfDuration|easeInOut\(duration: 0\.5\)\.repeatForever|easeInOut\(duration: 0\.14\)' VoiceInk/Views/Common/PromptChipPicker.swift VoiceInk/PowerMode/PowerModeStripView.swift

# Axis I (conditional on Open Q2)
rg -n 'windowBackgroundColor|controlBackgroundColor|\.indigo|\.teal|\.mint' VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift
```

- [ ] **Step 0.2: Verify excluded-files list is intact**

```bash
ls VoiceInk/Views/Recorder/ VoiceInk/Views/Recorder/Constellation/
ls VoiceInk/Views/Common/Glass*.swift VoiceInk/Views/Common/Palette.swift VoiceInk/Views/Common/Animation+Halo.swift VoiceInk/Views/Common/AdaptiveGlassBackground.swift VoiceInk/Views/Common/HaloMaterial.swift VoiceInk/Views/Common/KeyCapView.swift VoiceInk/Views/MenuBarView.swift
```

- [ ] **Step 0.3: Verify CustomPrompt.promptIcon call-site signature unchanged**

```bash
rg -n 'promptIcon\(isSelected:' VoiceInk/ --type swift
```

Expect: 4-6 call sites; method signature preserved means zero call-site edits.

- [ ] **Step 0.4: Resolve Open Q1 / Q2 / Q3 / Q4 / Q5 / Q6 with lead.** Do NOT sweep until decisions are recorded in this plan's checked-off Open Questions section. Default routes if lead silent: Q1 = W13.H (defer tabbed-settings); Q2 = fold-into-W13.G; Q3 = append-in-place; Q4 = no new tokens (sanction exceptions); Q5 = unify-to-tangerine (sweep .red to .accent); Q6 = keep-solid-CTA (W13.C decision).

### Task 1: Axis A — `CompactHeroSection` icon swap

**Files:** `VoiceInk/Views/Common/CompactHeroSection.swift`.

- [ ] Replace line 13 `.foregroundStyle(.blue)` with `.foregroundStyle(Palette.accent)`. One-line edit.

### Task 2: Axis B — `AppNotificationView` per-type recolor

**Files:** `VoiceInk/Notifications/AppNotificationView.swift`.

- [ ] Per the **Axis B** table. Lines 31-35 swap to `Palette.accent` / `Palette.success`. CTA chip backplate (`:68`) and progress bar (`:121`) inherit transitively. Optional polish (`:69`): `glassChip(cornerRadius: 8)` if surrounding chrome reads chip-like; coder evaluates.
- [ ] **If Open Q5 picks retain-red:** revert line 31 `.error` to `.red` ONLY. Document in self-review.

### Task 3: Axis C — `controlBackgroundColor` chip-level affordance sweep

**Files:** CopyIconButton, SaveIconButton, HistoryShortcutTipView, EnhancementShortcutsView, AudioInputSettingsView, PowerModeConfigView, DictionaryQuickAddPanel.

- [ ] Per the **Axis C** table. Each is a localized 2-5 line edit (background + companion stroke replacement).
- [ ] HistoryShortcutTipView: also recolor icon at `:10` `.accentColor` → `Palette.accent` (axis A residual). Drop the `Divider().padding(.vertical, 4)` if the new `glassPanel` already provides a visual separator (or keep — visual smoke decides at Task 9).

### Task 4: Axis D — Hand-rolled glass / Apple-system card sweep

**Files:** PromptEditorView (TriggerWordItemView), EnhancementPromptPopover, PredefinedPromptsView.

- [ ] **TriggerWordItemView** (`PromptEditorView.swift:472-477`): replace `.background(.ultraThinMaterial).cornerRadius(4).overlay(stroke ...)` stack with `.glassChip(cornerRadius: 10)`.
- [ ] **EnhancementPromptPopover** (`EnhancementPromptPopover.swift:50-58`): replace background stack with `glassPanel(cornerRadius: 14)`. **DROP** `.environment(\.colorScheme, .dark)` at `:58`. Recolor inner text at `:13, :82, :85` to `Palette.onyxFg` / `Palette.onyxMute` per Migration policy point 6. Recolor checkmark at `:92` to `Palette.success`. Recolor Divider background at `:23` and selection background at `:102` to `Palette.hairlineSoft`.
- [ ] **PredefinedTemplateButton** (`PredefinedPromptsView.swift:24-90`): full rebuild. Replace cardBackground/cardStroke/cardShadowColor (lines 67-89) with `GlassCard(cornerRadius: 16)`. Recolor icon tile at `:32-40` to `Palette.accent.opacity(0.16)` fill + `Palette.accent.opacity(0.32)` stroke 0.5pt + `Palette.accent` foreground. Replace `Color(NSColor.labelColor)` / `secondaryLabelColor` with `.primary` / `.secondary`.

### Task 5: Axis E — `CustomPrompt.promptIcon` tile family rebuild

**Files:** `VoiceInk/Models/CustomPrompt.swift`.

- [ ] Per the **Axis E** table. Replace selected-state radial-glow + decorative-circles + accent-shadow with `GlassCard(cornerRadius: 14)` + selection ring `RoundedRectangle 14 .stroke(Palette.accent, lineWidth: 1.5)` + glow shadow `Palette.accent.opacity(0.55)` rad 18.
- [ ] DELETE decorative blurred circles at `:184-200` and selection-state glow Circle at `:215-225`.
- [ ] Recolor icon foreground at `:202-210` to `isSelected ? Palette.accent : Palette.onyxFg`.
- [ ] Recolor mic-glyph + checkmark sub-bullets at `:241, :250` to `isSelected ? Palette.accent : Palette.onyxMute`.
- [ ] Apply same treatment to add-prompt + edit/delete tile variants at `:300-385`.
- [ ] **Verify** call-site signature `promptIcon(isSelected:onTap:onEdit:onDelete:)` byte-identical pre/post (Task 0.3 confirms).

### Task 6: Axis F — `PowerModeView` heroHeader migration

**Files:** `VoiceInk/PowerMode/PowerModeView.swift`.

- [ ] Replace lines 103-124 with `SettingsSectionHeader(icon: "bolt.fill", title: "Power Modes", subtitle: "Switch context automatically based on the active app or website.", accent: Palette.warn)`.
- [ ] **If `subtitle:` parameter does not exist on the primitive** (verify at Task 0.4): render subtitle as sibling Text row below the SettingsSectionHeader. DO NOT modify `SettingsSectionHeader.swift` in this packet — primitive evolution is post-merge follow-up.
- [ ] Migrate the InfoTip at `:110-113` into a sibling row (mirror SettingsView Privacy section pattern).
- [ ] Adjust outer padding if needed to match content gutter (`MetricsView` / `SettingsView` use `28v / 32h`).

### Task 7: Axis I — PerformanceAnalysisPanelView fold-in (CONDITIONAL)

**Files:** `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift`.

- [ ] **Only if Open Q2 picks fold-into-W13.G:**
  - Drop `.background(Color(NSColor.windowBackgroundColor))` at `:20` entirely.
  - Replace `:107-114` `RoundedRectangle 10 .fill(Color(NSColor.controlBackgroundColor)) .overlay(stroke quaternaryLabelColor)` with `glassPanel(cornerRadius: 10)`.
  - Sweep `:69-71` rainbow summary pills `.indigo / .teal / .mint` to single `Palette.accent`.
  - PRESERVE `design: .rounded` numeral at `:82` (Q9=a + W7 chart-numeral exception).

### Task 8: Axis G — animation residual flags (document only, no codemod)

**Files:** none (verification + spec amendment).

- [ ] Confirm three flagged sites (`PromptChipPicker.swift:125, 129`; `PowerModeStripView.swift:181, 275`) are byte-identical pre/post W13.G.
- [ ] **If Open Q4 picks add-tokens:** add `Animation.haloPulseTwoPhase` / `haloAttentionBreathe` / `haloMicro` to `Animation+Halo.swift` and update the three sites. Default: no changes (sanction in spec).

### Task 9: Self-review + grep follow-up

**Files:** none (read-only).

- [ ] Re-run all axis greps from Task 0.1. Confirm:
  - `rg -n 'foregroundStyle\(\.blue\)' VoiceInk/Views/Common/CompactHeroSection.swift` returns ZERO hits.
  - AppNotificationView `case .error/.warning/.info` no longer return `.red/.yellow/.blue`.
  - The 7 `controlBackgroundColor` / `windowBackgroundColor` chip-affordance hits from Task 3 are gone.
  - PromptEditorView TriggerWordItemView no longer references `.ultraThinMaterial`.
  - EnhancementPromptPopover no longer forces `.colorScheme = .dark`.
  - PredefinedPromptsView no longer references `controlBackgroundColor / unemphasizedSelectedTextBackgroundColor / shadowColor / separatorColor`.
  - CustomPrompt `promptIcon` no longer references `Color.accentColor` (uses `Palette.accent`).
  - PowerModeView heroHeader uses `SettingsSectionHeader`.
- [ ] Confirm excluded-files list (Task 0.2) byte-identical pre/post.
- [ ] Confirm `.rounded` grep still returns 9 hits (W13.A re-confirmation; +0 from W13.G unless Open Q2 fold-in adds none either).
- [ ] Confirm `Animation+Halo.swift` reviewer note at lines 14-17 is preserved.
- [ ] Confirm Axis G flagged sites byte-identical (unless Open Q4 picks add-tokens).

### Task 10: Spec amendment

**Files:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` (Option A) OR `docs/superpowers/specs/2026-04-30-aesthetic-redesign-W13-deltas.md` (Option B, new file). See Open Q3.

- [ ] Append §1.X.W13 deltas section per §Spec amendment below. Lands as separate `docs(specs)` commit.
- [ ] Append §2.4-W13 Halo token mapping table (canonicalize from W13.A migration policy point 4).
- [ ] If Open Q4 picks add-tokens, also include the new token spec lines.

### Task 11: Integration build

**Files:** none.

- [ ] Run `make local` (single integration build, per `feedback_skip_per_packet_builds.md`). Expect ~3 min cold; ~30s warm.
- [ ] Confirm zero new warnings related to W13.G edits.

### Task 12: Visual smoke pass

**Files:** none.

- [ ] Open the app. Eyeball each surface under (a) system Light, (b) system Dark, (c) bright wallpaper, (d) dark wallpaper:
  - **Permissions / AudioInput / Dictionary settings hero** — CompactHeroSection icon now tangerine, not blue.
  - **App notifications** — trigger one of each type (error / warning / info / success). Icon, CTA chip, progress bar all tangerine for first three; success-green for `.success`. Motion (progress bar decrement rate) discriminates.
  - **History detail empty state** — HistoryShortcutTipView now glass-on-wallpaper, command-circle icon tangerine.
  - **Copy/Save buttons** — anywhere they appear (TranscriptionDetailView, History sidebar). Glass chip, not opaque control-background circle.
  - **Power Mode hero** — SettingsSectionHeader with bolt.fill icon, amber tile.
  - **PromptEditorView trigger words** — chips read as glass capsules at 10pt rad with hairline.
  - **EnhancementPromptPopover** (recorder satellite — invoke from MiniRecorder when `isEnhancementEnabled` toggles open) — backdrop reads as glass panel; under bright wallpaper, text is legible (no white-on-light failure).
  - **PredefinedPromptsView** (open via "Add prompt from template" in EnhancementSettingsView) — template buttons read as `GlassCard`s with tangerine icon tiles.
  - **CustomPrompt tiles** (PromptChipPicker grid) — flat glass tile, tangerine selection ring + glow on selected, hairline on rest. No more rainbow gradient.
  - **(if Open Q2 fold-in)** Performance Analysis panel — header no longer paints opaque windowBg; system-info row backplate is glass; summary pills tangerine.
- [ ] Confirm under **Reduce Motion** (Accessibility → Display → Reduce motion = ON):
  - PromptChipPicker pulse no longer fires (existing motion guard at `:122`).
  - PowerModeStripView active pulse no longer breathes (existing motion guard at `:179-180`).
  - Drop-drop animation (PowerModeStripView:275) still fires (no motion guard there — flag for spec extension if user reports).
- [ ] Confirm under **Reduce Transparency** (Accessibility → Display → Reduce transparency = ON):
  - All swept `glassChip` / `glassPanel` / `GlassCard` surfaces fall back to opaque per spec §6.4 contract.
  - HistoryShortcutTipView, CopyIconButton, SaveIconButton legible.
- [ ] Confirm under **Increase Contrast**:
  - Hairlines at sub-strokes still readable.
  - PermissionCard CTA still passes contrast (Palette.accent on white text — verify if Open Q6 changed it; default keep-solid is unchanged).

### Task 13: Commit + report to lead

- [ ] Lead handles commits per CLAUDE.md cadence:
  ```
  docs(plans): W13G — polish + spec extension
  feat(aesthetic): W13G — polish + spec extension
  docs(specs): W13 deltas — append §1.X.W13 / §2.4-W13
  ```
- [ ] Report to lead: task ID, edited file list, total LOC delta, smoke-pass observations, any flagged hits left untouched (with reason), Open Question resolutions used.

---

## Verification

1. **Build green.** `xcodebuild build` (or `make local`) at Task 11. Zero warnings, zero errors related to W13.G surfaces.
2. **Grep follow-up clean.** All swept hits gone; only sanctioned exceptions remain (Axis G flagged sites + any Open Q deferrals).
3. **Visual smoke green.** Task 12 — every targeted surface reads tangerine-on-glass under all four wallpaper/system-mode permutations + reduce-motion/transparency/contrast accessibility paths.
4. **No primitive drift.** `Palette.swift`, `GlassChip.swift`, `GlassCard.swift`, `Animation+Halo.swift` (unless Open Q4 picks add-tokens), `AdaptiveGlassBackground.swift`, `HaloMaterial.swift`, `KeyCapView.swift`, `SettingsSectionHeader.swift` are byte-identical pre/post.
5. **No recorder-cluster drift.** `RecorderComponents.swift`, `Constellation/ClusterMotion.swift`, all `Halo*Recorder*` panels byte-identical.
6. **No Form-host disruption.** W13.D scope (EnhancementSettingsView, EnhancementSettingsPanel, PromptEditorView Form panes, InlineHistoryView cardListView, AudioTranscribeView queue, DictionarySettingsPanel) byte-identical.
7. **No menubar drift.** `MenuBarView.swift`, `MenuBarManager.swift` byte-identical.
8. **CustomPrompt API stability.** `promptIcon(isSelected:onTap:onEdit:onDelete:) -> some View` signature byte-identical; call sites at EnhancementSettingsView / EnhancementSettingsPanel / PromptChipPicker untouched.
9. **Spec amendment commit lands cleanly.** `docs(specs)` commit applies §1.X.W13 deltas without conflict; existing spec sections §1, §1.X (W8), §2-§7 byte-identical.

---

## Rollback plan

Three commits (`docs(plans)` + `feat(aesthetic)` + `docs(specs)`). If a regression surfaces:

```bash
git revert <feat-sha>
```

Reverts cleanly because every code edit is a localized token / structural swap with no companion edits, no schema migrations, no dependency changes. The `docs(plans)` and `docs(specs)` commits can stay (re-runnable across re-attempts).

If a *partial* regression surfaces (e.g. CustomPrompt tile rebuild looks wrong but other axes are fine), rollback the offending file's edit via `git checkout <sha>~1 -- <file>` and re-commit — preserves the rest of the sweep.

The spec amendment commit is independent — it can be reverted in isolation if a spec delta turns out to be over-stated.

---

## Risks

1. **EnhancementPromptPopover light-glass legibility regression** (medium). Dropping `.environment(\.colorScheme, .dark)` means the recorder satellite popover follows `GlassAppearanceDetector`. Under a bright wallpaper, glass goes to `.aqua` light variant. Inner text colors at `:82, :85, :92` currently use `.white.opacity(...)` — readable on dark, illegible on light. **Mitigation:** swap text to `Palette.onyxFg / .onyxMute` per Migration policy point 6; these tokens read on both variants per shipped recorder cluster behavior. Visual smoke at Task 12 catches under-bright-wallpaper edge case.

2. **CustomPrompt tile rebuild visual regression** (medium). Largest single edit in the packet. Removing decorative blurred circles + radial gradient + per-tile blur Circle changes the silhouette from "celebratory glow card" to "flat glass tile with selection ring + shadow." User has been seeing the celebratory variant since v1. **Mitigation:** mirrors W13.E AI Models card vocabulary (which user signed off on at W13.E merge); selection-state still glows via `Palette.accent.opacity(0.55)` shadow, just at lower amplitude than radial gradient.

3. **PowerModeView heroHeader subtitle parameter** (low). If `SettingsSectionHeader` doesn't expose `subtitle:`, fallback to sibling Text row. Coder verifies at Task 0.4. **Mitigation:** sibling row pattern is the SettingsView Privacy section default; zero primitive drift.

4. **AppNotificationView .error retain-red ambiguity** (low — Open Q5). Lead may pick retain-red for HUD error legibility (recorder cluster failure uses tangerine + HaloShake; HUD failure has no motion shake). **Mitigation:** Open Q5 default is unify-to-tangerine but coder can revert line 31 only if lead picks retain-red.

5. **PerformanceAnalysisPanelView fold-in scope creep** (low — Open Q2). If lead picks fold-here, this packet's diff grows by ~3 surfaces. **Mitigation:** Open Q2 default is fold-here-recommended (mirrors W13.F's residual-debt principle: small adjacent sweeps belong with the polish packet, not as their own micro-packet).

6. **Spec amendment in-place vs companion file** (low — Open Q3). Append-in-place keeps single source of truth; companion file makes deltas easier to diff/revert. **Mitigation:** default append-in-place (single file is the W8 §1.X precedent); lead can override.

7. **Reduce-Motion guard missing on PowerModeStripView:275** (low). Drag-drop micro-animation has no `motion.reduceMotion` guard. Not a W13.G regression (pre-existing), but flagged for spec amendment as sanctioned exception OR add a guard. **Mitigation:** Open Q4 covers; default is sanction in spec.

8. **`.rounded` numerals across Performance Analysis surfaces** (low). If Open Q2 fold-in lands, line `:82` `design: .rounded` numeral KEEPS per Q9=a + W7 chart-numeral exception. Coder must NOT sweep this; the 9-`.rounded` baseline holds.

---

## Spec amendment

This is the literal text to append to `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` after the existing §1.X (W8 extension) — OR to write into a new `docs/superpowers/specs/2026-04-30-aesthetic-redesign-W13-deltas.md` if Open Q3 picks Option B.

**Header for either option:**

```markdown
### 1.X.W13 W13 polish + cohesion deltas (2026-04-30)

The W13.A–G packet sweep closed the main-app cohesion gap with the floating-recorder vocabulary. The deltas below CODIFY decisions made during W13 sign-off and the merge of each packet. Source plans: `docs/superpowers/plans/W13{A..G}-*.md`.
```

**§1.X.W13.1 Hero corner radius 24pt sanctioned exception (Q9=a)**

```markdown
**§1 caps panels at 14-16pt corner radius.** The Metrics/Dashboard hero
section (`MetricsContent.heroSection`) carries dashboard centerpiece
identity at 24pt corner radius — sanctioned exception. Applies only to
"hero / dashboard centerpiece" surfaces (one per major destination, not
per card). Plan reference: `W13B-metrics-rebuild.md` Q9=a.

NOT sanctioned: 28pt+ radii anywhere (HelpAndResourcesSection at v1's 28pt
was retired in W13.B). NOT sanctioned: 24pt on regular `GlassCard` /
`GlassChip` surfaces.
```

**§1.X.W13.2 Single-accent metric icon palette (W13.B)**

```markdown
**Metric card / dashboard pill icon backgrounds key to a SINGLE palette
token.** Default: `Palette.accent`. Motion (or progress-bar fill) is the
discriminator across cards, not per-card hue. Spec §1's rainbow palette
retirement extends to data-vis chrome.

Sanctioned non-state alternates: `Palette.success` (true completion /
positive metric), `Palette.warn` (active power-mode signal),
`Palette.neutral` (idle baseline). NEVER `.indigo / .teal / .mint /
.purple / .yellow / .orange / .red / .green / .blue` direct refs.
```

**§1.X.W13.3 `glassPanel(cornerRadius: 16)` canonical Help/Resources idiom**

```markdown
**Help / Resources / Tip panels (e.g. `HelpAndResourcesSection`,
`HistoryShortcutTipView`) use `glassPanel(cornerRadius: 16)` with inner
link rows at `glassChip(cornerRadius: 10)`.** Hairline strokes via
`Palette.hairline` (outer) and `Palette.hairlineSoft` (inner separator).
No outer shadow beyond what the primitive provides. Plan reference:
`W13B-metrics-rebuild.md` HelpAndResourcesSection rebuild.
```

**§1.X.W13.4 Soft-pill `glassChip(cornerRadius: 18)` button capsules (W13.B)**

```markdown
**Button capsule chrome standardized at `glassChip(cornerRadius: 18)`.**
Replaces the `.thinMaterial` Capsule + ad-hoc spring affordance. Examples:
CopySystemInfoButton, MetricsView footer button, History selection-bar
"Clear" button. Reduce-Motion contract preserved (no per-button bespoke
spring overrides).
```

**§1.X.W13.5 Family-aligned strokes for AI Models cards (W13.E)**

```markdown
**AI Models card family (Whisper / Cloud / FluidAudio / Native / Custom)
uses uniform stroke vocabulary:**
- Active card (selected / current): 1.5pt `Palette.accent` border + 0.55
  alpha glow shadow rad 18.
- Rest card: 1pt `Palette.hairline` border, no glow.
- Card body: `GlassCard(cornerRadius: 16)` (no `HaloMaterial(phase: .hidden)`
  direct usage).
- Strokes NEVER use `Color.accentColor` or `Color.white.opacity(...)`
  directly — always `Palette.accent` / `Palette.hairline*`.

Plan reference: `W13E-ai-models-cards.md`. Same vocabulary applies to
`CustomPrompt.promptIcon` tile family (W13.G axis E rebuild) and to the
predefined-prompt template buttons.
```

**§1.X.W13.6 Flat sectionBlock pattern for popover / editorPane surfaces (W13.D)**

```markdown
**`Form { Section }` host is RETIRED for main-app + popover settings
surfaces.** Migrated to `ScrollView { LazyVStack(spacing: 16) { SettingsCard
{...} } }` per `SettingsView.swift:51-71` (W5 pattern). Surfaces affected:
EnhancementSettingsView, EnhancementSettingsPanel, PromptEditorView editor
panes, InlineHistoryView card list, AudioTranscribeView queue,
DictionarySettingsPanel.

`Form { Section }` is preserved ONLY where macOS system controls (NSPicker
/ NSStepper / NSColorWell) require Form context for layout correctness.
Plan reference: `W13D-form-host-purge.md`.
```

**§1.X.W13.7 Single-accent HUD notification (W13.G)**

```markdown
**`AppNotificationView` per-type colors collapse to single accent +
motion as discriminator.** Icon, CTA chip backplate, progress-bar fill
all key to:
- `Palette.accent` for `.error`, `.warning`, `.info`.
- `Palette.success` for `.success`.

Motion (progress-bar decrement rate, derived from `duration:` parameter)
discriminates urgency: shorter `duration` for `.error` (fast decrement),
longer for `.info`. VoiceOver / iconName retains semantic accessibility.

Plan reference: `W13G-polish-spec-extension.md` axis B. **Sanctioned
exception (open):** if HUD `.error` legibility tests show tangerine fails
the high-stakes attention threshold, retain `.red` for `.error` ONLY and
document here.
```

**§1.X.W13.8 Q7=b menubar dropdown system-default (restated)**

```markdown
**Menubar dropdown stays system-default (`MenuBarExtra(...).menuBarExtraStyle(.menu)`).**
The `.window` glass popover variant was attempted and reverted per user
request (sparse content + system-menu cohesion trade-off favors
system-default). `MenuBarView.swift` and `MenuBarManager.swift` are OUT
of all aesthetic-cohesion sweeps. Plan reference: master plan §0 Q7=b.
```

**§1.X.W13.9 Animation token sanctioned exceptions (W13.G axis G)**

```markdown
**Three animation literals are sanctioned exceptions to the §2.4 halo
token grammar:**

| File:line | Literal | Use | Reason for exception |
|---|---|---|---|
| `Common/PromptChipPicker.swift:125, 129` | `easeOut(0.2) → easeIn(0.2)` (2-phase, total 0.4s) | Selection pulse (scaleEffect + accent shadow ramp-up + ramp-down) | No current halo token has 2-phase ramp-up/ramp-down shape. Reduce-Motion guard is in place at `:122`. |
| `PowerMode/PowerModeStripView.swift:181` | `easeInOut(0.5).repeatForever(autoreverses: true)` | Active-mode warn dot pulse | 0.5s active-mode urgency is intentionally faster than `haloBreathe (1.6s)` enhancing-state breath. Reduce-Motion guard at `:179-180`. |
| `PowerMode/PowerModeStripView.swift:275` | `easeInOut(0.14)` | Drag-drop reorder micro-animation | Sub-150ms; below the `haloPhaseCrossfade (0.22s)` band. No Reduce-Motion guard (flag for follow-up). |

**Future evolution:** if these patterns recur, codify as `Animation.haloPulseTwoPhase` /
`Animation.haloAttentionBreathe` / `Animation.haloMicro` in
`Animation+Halo.swift`. W13.G defers token addition; current literals are
sanctioned via this section.
```

**§2.4-W13 Halo token mapping table (canonicalize from W13.A migration policy)**

```markdown
### 2.4-W13 Source-literal → Halo token mapping (canonical)

W13.A established the source-literal → halo-token mapping; codified here
as the canonical reference. New surfaces must NOT introduce ad-hoc
`spring` / `smooth` / `easeInOut` literals; use the named token.

| Source literal                                              | Halo token                  |
|-------------------------------------------------------------|-----------------------------|
| `.spring(response: 0.3, dampingFraction: 0.7)`              | `Animation.haloExpand`      |
| `.spring(response: 0.3, dampingFraction: 0.8)`              | `Animation.haloExpand`      |
| `.spring(response: 0.2, dampingFraction: 0.7)`              | `Animation.haloExpand`      |
| `.smooth(duration: 0.3)`                                    | `Animation.haloExpand`      |
| `.easeInOut(duration: 0.22)`                                | `Animation.haloPhaseCrossfade` |
| `.easeInOut(duration: 0.15 / 0.18 / 0.20)`                  | `Animation.haloPhaseCrossfade` |
| `.easeInOut(duration: 0.3)`                                 | `Animation.haloExpand`      |
| `.easeInOut(duration: 0.5)` (NON-repeating)                 | `Animation.haloExpand` (borderline; reviewer eval) |
| `.easeInOut(duration: 1.6).repeatForever`                   | `Animation.haloBreathe`     |
| `.easeInOut(duration: 0.5).repeatForever`                   | (sanctioned exception per §1.X.W13.9) |
| `.easeInOut(duration: 0.14)` and shorter                    | (sanctioned exception per §1.X.W13.9) |
| 2-phase `easeOut(halfDuration) + easeIn(halfDuration)`      | (sanctioned exception per §1.X.W13.9) |

Recorder cluster animations (`.linear(duration: 1).repeatForever` etc.)
are EXCLUDED — recorder is the source of truth for halo tokens, not a
consumer.
```

---

## Open questions for lead

1. **Fold tabbed-settings UX (Task #14) into W13.G or run as W13.H?**
   - Default (this plan): defer to **W13.H**. W13.G is polish + spec extension; tabbed-settings is a structural IA change deserving its own spec amendment + brainstorm.
   - Alternative: fold here. Adds 5-10 surfaces to the diff, expands scope from polish to IA-rebuild.
   - **Recommendation:** W13.H. Lead picks.

2. **PerformanceAnalysisPanelView opaque chrome — fold into W13.G or split as W13.B2?**
   - Default (this plan): **fold into W13.G** (axis I, conditional). Mirrors W13.F's residual-debt-belongs-with-polish-packet principle. The diff is 3 surfaces (3 lines + 3 rainbow recolors); W13.B2 would duplicate ceremony for marginal gain.
   - Alternative: defer to W13.B2. Master plan §4 W13.B doesn't include PAPV; W13.B's plan §Follow-ups recommends W13.B2/B3 splits.
   - **Recommendation:** fold into W13.G. Lead picks.

3. **Spec amendment — append to existing spec doc or write new `-deltas.md` companion?**
   - Default (this plan): **Option A append-in-place**. Single source of truth; mirrors W8 §1.X precedent (added in-place when W8 landed).
   - Alternative: Option B `2026-04-30-aesthetic-redesign-W13-deltas.md` companion file. Easier to diff/revert; keeps the original spec doc frozen at v1.
   - **Recommendation:** Option A append-in-place. Lead picks.

4. **Animation codemod scope — sweep to halo* tokens (add new ones if needed) or sanction as exceptions?**
   - Default (this plan): **sanction as exceptions** in spec §1.X.W13.9. Three flagged sites have legitimate "no current token fits" geometry; adding tokens is spec evolution beyond polish scope.
   - Alternative: add `Animation.haloPulseTwoPhase` (0.4s 2-phase) / `Animation.haloAttentionBreathe` (0.5s repeat) / `Animation.haloMicro` (0.14s) to `Animation+Halo.swift`, sweep call sites. ~10 LOC primitive change + 3 call-site edits.
   - **Recommendation:** sanction. Adding tokens is a spec evolution; defer to a future `aesthetic-redesign` packet if these patterns recur.

5. **AppNotificationView `.error` retain-red as sanctioned exception or unify to tangerine?**
   - Default (this plan): **unify to tangerine**. Recorder cluster failure already uses `Palette.accent` + HaloShake motion as discriminator; HUD failure is a strict subset.
   - Alternative: retain `.red` for `.error` ONLY (high-stakes legibility threshold). Document as sanctioned exception in §1.X.W13.7.
   - **Recommendation:** unify. Lead picks; coder reverts line 31 only if lead overrides.

6. **PermissionCard CTA button — keep solid `Palette.accent` capsule or wrap in `glassChip` + `accentMuted`?**
   - Default (this plan): **keep solid** (W13.C's preserved decision; W13.G inherits).
   - Alternative: wrap in `glassChip(cornerRadius: 10)` with `Palette.accentMuted` fill + `Palette.accent` foreground. R4 §1 row 6 originally suggested this. Reads less "primary CTA," more "polished chip."
   - **Recommendation:** keep solid. Primary CTA semantics matter; cohesion gain from chip-wrap is marginal.

---

## Follow-ups for adjacent W13 packets

### W13.B2 (recommended split per W13.B §Follow-ups)
- `Metrics/MetricsSetupView.swift:62, 103, 104, 140, 145` — welcome-card chrome + accent buttons + 28pt corner radius + `.rounded` welcome marquee. NOT W13.G scope unless lead overrides.

### W13.B3 (recommended split per W13.B §Follow-ups)
- `Metrics/PerformanceAnalysisView.swift:159, 432, 265, 346, 409` — full hosted view (charts surface, NOT the panel). Charts hosts have W8 OOS rule (opaque bg required for chart legibility). Plan needs careful spec read. NOT W13.G scope (unless Open Q2 explicitly fold-in pulls it forward, which the recommendation does NOT).

### W13.H (open — only if Open Q1 picks fold-tabbed-settings-here = NO)
- Tabbed-settings UX (Task #14): structural IA rebuild. Brainstorm + spec amendment + multi-packet implementation. Out of all W13.A-G scope.

### Phase 4 / spec evolution (deferred)
- `Animation+Halo.swift` token additions if Open Q4 retains sanction-as-exception (default) and the patterns recur in W14+.
- `SettingsSectionHeader.swift` `subtitle:` parameter if W13.G axis F finds it absent (Task 6 verifies).
- Reduce-Motion guard for `PowerModeStripView.swift:275` drag-drop micro-animation (Open Q4 / spec §1.X.W13.9 follow-up).

---
