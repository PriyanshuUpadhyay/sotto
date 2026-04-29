# W13.A — Token Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Reviewer is `superpowers:code-reviewer`.

**Date:** 2026-04-29
**Author:** planner-w13a (team `w11a-pipeline-fixes`, task #2)
**Sources:**
- R4 audit (the WHY for each replacement): `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md`
- Master plan §4 W13: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`
- Vocabulary primitives: `Palette.swift` / `GlassChip.swift` / `GlassCard.swift` / `Animation+Halo.swift` / `AdaptiveGlassBackground.swift` (under `VoiceInk/Views/Common/`)

**Goal:** Mechanical token-vocabulary codemod across the main-app surfaces. No structural rewrites — every edit is a one-line swap from raw Apple/system tokens to the floating-recorder vocabulary primitives. Surfaces that need a *structural* rebuild (Form-host purge, GlassCard wrap, drop-zone reskin, History window non-opaque flip) are explicitly OUT and routed to the W13.B–W13.G packets.

**Architecture (token replacement axes):**

```
Axis                                        Source token (any)                              Target token (vocabulary)
─────────────────────────────────────       ─────────────────────────────────               ─────────────────────────────
A. Live accent                              Color.accentColor                                Palette.accent
                                            Color(.controlAccentColor)                       (= #FF5B3A tangerine, Palette.swift:33)
                                            Color(NSColor.controlAccentColor)

B. Glass strokes / hairlines                Color.white.opacity(~0.16)                       Palette.hairline       (white α0.16)
                                            Color.white.opacity(~0.10–0.12)                  Palette.hairlineSoft   (white α0.10)
                                            Color.white.opacity(~0.20–0.30) inner gloss      Palette.innerHi        (white α0.22)

C. Raw materials → glass primitive          fill(.ultraThinMaterial)                         glassChip(cornerRadius: 8 / 10)
   (when surrounding chrome is rect+stroke) fill(.thinMaterial)                              glassPanel(cornerRadius: 14)

D. .systemFill                              Color(.systemFill)                               Palette.hairline       (treated as stroke proxy)

E. Display type retirement                  .font(.system(... design: .rounded))             drop the design parameter
                                                                                             (Q9: Metrics hero stays — see exclusions)

F. Animation grammar                        .spring(response: 0.38, dampingFraction: 0.78)   Animation.haloExpand
                                            .spring(response: 0.42, dampingFraction: 1.00)   Animation.haloCollapse
                                            .easeInOut(duration: 0.22) phase swap            Animation.haloPhaseCrossfade
                                            .easeInOut(duration: 1.6).repeatForever          Animation.haloBreathe
                                            other ad-hoc literals                            Animation.haloExpand (reveal/select)
                                                                                             Animation.haloCollapse (dismiss/contract)
                                                                                             Animation.haloPhaseCrossfade (sub-150ms swaps)
                                                                                             flag if no token matches → ambiguous, defer

G. Window-bg opaque tokens                  Color(NSColor.windowBackgroundColor)             EXCLUDED from W13.A (W8 already covers
                                            Color(NSColor.controlBackgroundColor)            pane roots; remaining hits are sub-pane
                                                                                             chrome routed to W13.B/C/F)
```

**Tech Stack:** Swift 5.x, SwiftUI, AppKit (`NSColor` only via the call sites we sweep), Xcode 16.x. Build via `make local` (~3 min cold). No new dependencies. No new tests.

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens — single tangerine accent, retire `.rounded` outside designated places, glass hairlines via `Palette.hairline*`), §2.4 (motion grammar — four named tokens), §6.4 (Reduce-Transparency contract). Master plan §4 W13.A.

**Q-decisions honored (from §0 of master plan):**
- **Q7=b** — menubar dropdown stays system-default (`MenuBarExtra(...).menuBarExtraStyle(.menu)`). `Views/MenuBarView.swift` is fully excluded.
- **Q9=a** — `MetricsContent.heroSection` keeps its hero gradient identity, but switches to `Palette.accent`. That swap is **W13.B**'s job (Metrics rebuild repaints the whole hero); W13.A flags but does not touch it.

**CLAUDE.md cadence rules respected:**
- **Single integration build at merge time** (per `feedback_skip_per_packet_builds.md`). No `make local` per task. One `xcodebuild build` at the end.
- **Plan-files-committed-alongside-impl.** This document lands in `docs(plans): W13A — token sweep` followed by `feat(aesthetic): W13A — token sweep` for the codemod.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** Inline doc-comments cite spec §1 / §2.4 + this plan path; no PR numbers.
- **Pre-existing spec-ref comments preserved** (`Palette.swift` §1, `GlassChip.swift` §1, `Animation+Halo.swift:14-17` reviewer note, `HaloMaterial.swift` §2.3 / §6.4).

---

## File structure

### New files

None. W13.A is pure token-vocabulary polish.

### Modified files

(38 files across 6 axes. Per-line swaps detailed in §Replacement table.)

- `VoiceInk/Views/Common/AppIconView.swift` — accent fill + accent shadow (axis A).
- `VoiceInk/Views/Common/CopyIconButton.swift` — controlBackgroundColor sweep flag (axis G — but flagged for W13.G as polish; left alone in A unless coder's grep finds new strokes).
- `VoiceInk/Views/Common/SaveIconButton.swift` — same as CopyIconButton (flag-only).
- `VoiceInk/Views/AudioPlayerView.swift` — accent capsule fill + scrubber + animation literals (axis A + F).
- `VoiceInk/Views/AudioFileRow.swift` — accent selection bg + animation literal (axis A + F).
- `VoiceInk/Views/PermissionsView.swift` — animation literal (axis F).
- `VoiceInk/Views/PromptEditorView.swift` — accent foregroundStyle + raw ultraThinMaterial chip (axis A + C + F). Form-internal hits at lines 286 are deferred to **W13.D**.
- `VoiceInk/Views/PredefinedPromptsView.swift` — flag the controlBackgroundColor card (W13.G owns rebuild). No edit in A.
- `VoiceInk/Views/AI Models/AddCustomModelView.swift` — accent button + accent shadow + accent verify-button (axis A).
- `VoiceInk/Views/AI Models/ModelManagementView.swift` — animation literals only (axis F). Already vocabulary-clean otherwise.
- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` — `Color.white.opacity(0.04 / 0.05 / 0.06)` chip-fills (axis B — ambiguous, see Risks; coder evaluates context).
- `VoiceInk/Views/Settings/RecorderStylePicker.swift` — `Color.white.opacity(...)` strokes / fills (axis B).
- `VoiceInk/Views/Settings/AudioCleanupSettingsView.swift` — animation literals (axis F).
- `VoiceInk/Views/Settings/SettingsView.swift` — animation literals (axis F).
- `VoiceInk/Views/Dictionary/DictionarySettingsView.swift` — animation literals (axis F).
- `VoiceInk/Views/Dictionary/VocabularyView.swift` — animation literal (axis F). The `Color(.windowBackgroundColor).opacity(0.4)` at :173 is a drop-zone affordance flagged for **W13.C**.
- `VoiceInk/Views/Dictionary/WordReplacementView.swift` — animation literals (axis F).
- `VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift` — animation literal (axis F).
- `VoiceInk/Views/History/InlineHistoryView.swift` — animation literals (axis F). Form-internal hits in cardListView (255-298) deferred to **W13.D**.
- `VoiceInk/Views/History/TranscriptionDetailView.swift` — animation literals (axis F).
- `VoiceInk/Views/History/TranscriptionListItem.swift` — controlAccentColor (axis A) + animation literal (axis F).
- `VoiceInk/Views/Components/SlidingPanel.swift` — animation literals (axis F).
- `VoiceInk/Views/Components/PromptSelectionGrid.swift` — animation literal (axis F).
- `VoiceInk/Views/Components/FillerWordsSettingsView.swift` — animation literals (axis F). The raw `.ultraThinMaterial` at :31 is a structural rebuild → flag for **W13.G**.
- `VoiceInk/PowerMode/AppPicker.swift` — accent selection bg (axis A).
- `VoiceInk/PowerMode/EmojiPickerView.swift` — accent stroke + Color.white.opacity(0.8) circle bg (axis A + B).
- `VoiceInk/PowerMode/PowerModeView.swift` — animation literals (axis F).
- `VoiceInk/PowerMode/PowerModeStripView.swift` — animation literals (axis F).
- `VoiceInk/PowerMode/PowerModeConfigView.swift` — `Color.white.opacity(...)` strokes (axis B — fills are ambiguous).
- `VoiceInk/PowerMode/PowerModePopover.swift` — `Color.white.opacity(...)` strokes (axis B — fills are ambiguous).
- `VoiceInk/Notifications/AnnouncementView.swift` — `Color.white.opacity(0.3)` strokeBorder (axis B). HUD context — flag.
- `VoiceInk/Notifications/AppNotificationView.swift` — `Color.white.opacity(0.1)` strokeBorder (axis B). Per-type rainbow recolor is **W13.G**.

### Excluded files (DO NOT touch — explicit list, coder do not drift)

Per dossier exclusions, the following are out-of-bounds for W13.A:

**Floating-bar / recorder cluster (source of truth for the vocabulary itself):**
- `VoiceInk/Views/Recorder/HaloMaterial.swift` — primitive (W1)
- `VoiceInk/Views/Recorder/HaloRecorderView.swift`
- `VoiceInk/Views/Recorder/HaloShape.swift`
- `VoiceInk/Views/Recorder/MiniRecorderPanel.swift` + `MiniWindowManager.swift`
- `VoiceInk/Views/Recorder/NotchRecorderPanel.swift` + `NotchWindowManager.swift`
- `VoiceInk/Views/Recorder/RecorderComponents.swift` (`.linear(duration:1)`, `.easeInOut(duration:0.2)` are recorder-state animations — leave)
- `VoiceInk/Views/Recorder/RecorderStateProvider.swift`
- `VoiceInk/Views/Recorder/AudioVisualizerView.swift`
- `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift` — recorder satellite (audit row #27 routes to **W13.G**)
- `VoiceInk/Views/Recorder/Constellation/*.swift` — full directory; `ClusterMotion.swift` is the cluster-motion grammar source-of-truth (W2)

**Glass primitive files (the vocabulary itself — must not self-reference):**
- `VoiceInk/Views/Common/GlassChip.swift`
- `VoiceInk/Views/Common/GlassCard.swift`
- `VoiceInk/Views/Common/GlassSwitch.swift`
- `VoiceInk/Views/Common/Palette.swift`
- `VoiceInk/Views/Common/Animation+Halo.swift`
- `VoiceInk/Views/Common/AdaptiveGlassBackground.swift`
- `VoiceInk/Views/Common/KeyCapView.swift` — `Color.white.opacity(0.92)` is keyboard-key glyph color, intentional; UNTOUCHED

**Menubar dropdown (Q7=b — system-default):**
- `VoiceInk/Views/MenuBarView.swift`
- `VoiceInk/MenuBarManager.swift` (and any direct dropdown callers)

**Routed to other W13 packets — DO NOT sweep here:**
- `VoiceInk/Views/Metrics/MetricsContent.swift` — W13.B (hero gradient at :179-188; `.rounded` at :155 KEEPS per Q9)
- `VoiceInk/Views/Metrics/MetricCard.swift` — W13.B (full `GlassCard` rewrap; `.rounded` at :31 KEEPS per Q9)
- `VoiceInk/Views/Metrics/HelpAndResourcesSection.swift` — W13.B (full `GlassCard` rewrap; 28pt radius retirement)
- `VoiceInk/Views/Metrics/MetricsSetupView.swift` — W13.B (welcome flow rebuild; controlBackgroundColor + accent buttons + 28pt `.rounded`)
- `VoiceInk/Views/Metrics/PerformanceAnalysisView.swift` + `PerformanceAnalysisPanelView.swift` — W13.B (Metrics dashboard rebuild; `.rounded` hero numerals KEEP per Q9 / W7 brief)
- `VoiceInk/Views/PermissionsView.swift:191` — `.ultraThinMaterial` rebuild → **W13.C** (`PermissionCard` GlassCard wrap)
- `VoiceInk/Views/AudioTranscribeView.swift` — drop-zone (lines 56, 284, 287) + accent capsule buttons (lines 209, 210) + queue Form (lines 103-129) → **W13.C**
- `VoiceInk/Views/EnhancementSettingsView.swift:53-158` (Form host) → **W13.D**
- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift:53-172` (Form host) → **W13.D**
- `VoiceInk/Views/PromptEditorView.swift:224-270, 278-363` (Form panes) → **W13.D**
- `VoiceInk/Views/History/InlineHistoryView.swift:255-298` (cardListView Form) → **W13.D**
- `VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift:46-56` (Form host) → **W13.D**
- `VoiceInk/Views/AudioTranscribeView.swift:103-129` (queue Form) → **W13.D**
- `VoiceInk/Views/AI Models/WhisperModelCardView.swift` — full `GlassCard` rewrap → **W13.E**
- `VoiceInk/Views/AI Models/CloudModelCardView.swift` — same → **W13.E**
- `VoiceInk/Views/AI Models/FluidAudioModelCardView.swift` — same → **W13.E**
- `VoiceInk/Views/AI Models/NativeModelCardView.swift` — same → **W13.E**
- `VoiceInk/Views/AI Models/CustomModelCardView.swift` — same → **W13.E**
- `VoiceInk/Views/AI Models/ProviderCard.swift` — already provider-chip vocab; `motion.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)` is a custom expand/collapse close to `haloExpand` (0.38) but explicitly tuned. Coder note: candidate for `Animation.haloExpand` swap, but spec-locked at 0.32; defer to **W13.E** alongside the ProviderCard rebuild.
- `VoiceInk/HistoryWindowController.swift:54` (`window.backgroundColor = NSColor.windowBackgroundColor`) → **W13.F** (non-opaque NSWindow flip)
- `VoiceInk/Views/History/TranscriptionHistoryView.swift` — `.thinMaterial` search field at :184 + `Color(NSColor.windowBackgroundColor)` at :133, :392 + `Color(NSColor.controlBackgroundColor)` at :321 + `withAnimation(.smooth(duration:0.3))` at :114, :118, :125, :144, :353 → **W13.F**
- `VoiceInk/Models/CustomPrompt.swift` — `extension CustomPrompt { promptIcon ... }` at :138-303 is a hand-rolled radial-glow tile (rainbow gradient + shadow stack). Not a token sweep — major rebuild → **W13.G** (or its own packet — flag).
- `VoiceInk/Transcription/Whisper/WhisperModelManager.swift:444` — `.fill(Color(.controlAccentColor))` is a download-progress bar inside the Whisper model UI. Flag for **W13.E** (rolled into the Whisper card rebuild).
- `VoiceInk/Views/Common/CompactHeroSection.swift:13` — `.foregroundStyle(.blue)` per master plan §4 W13.G — explicit polish bullet. Defer.
- `VoiceInk/Views/AI Models/LanguageSelectionView.swift:152` — controlBackgroundColor pane bg. Already W8-eligible (sub-pane chrome). Flag for **W13.E** if the rebuild touches it; otherwise small polish.

**Tests:**
- `VoiceInkTests/*.swift` and `VoiceInkUITests/*.swift` — out of W13.A scope.

---

## Migration policy (resolves ambiguity for each design point)

1. **`Color.white.opacity(...)` is stroke-side only.** The `Palette.hairline / hairlineSoft / innerHi` tokens are stroke / inner-gloss colors — not chip-fill backplates. When a hit's role is a `RoundedRectangle.fill(Color.white.opacity(0.05))` chip backplate, no Palette token applies. Coder's call: if the entire `RoundedRectangle.fill(...).overlay(stroke)` stack is a hand-rolled `glassChip` reimplementation, REPLACE the whole stack with `.glassChip(cornerRadius: N)` (axis C). If the call is a one-off backplate that doesn't have stroke + inner-gloss + drop-shadow companions, FLAG and leave alone — better handled by a structural rebuild.

2. **Opacity → token mapping is approximate, not exact.** The dossier prescribes ranges (`hairline ~0.16`, `hairlineSoft ~0.10`, `innerHi ~0.22`). Sites within ±0.04 of a token replace; sites outside the band (e.g. `Color.white.opacity(0.30)` on `AnnouncementView.swift:87`) FLAG and leave — they may be intentional accent for a surface (HUD inner gloss can run hotter than 0.22).

3. **`.ultraThinMaterial` swaps to `glassChip` only when the hand-rolled stack is the full chip vocabulary.** The audit calls out 5 sites (PermissionsView, MetricsContent help, AudioTranscribeView drop, EnhancementSettingsView buttons, PromptEditorView triggers) where the inline 5-10 lines duplicate `glassChip()` — but those are W13.B/C/D/E packet rebuilds. W13.A only swaps the **isolated** `.ultraThinMaterial` chip uses where surrounding chrome is already stroke + radius compliant (e.g. `PromptEditorView.swift:103, 472` — confirm in coder review).

4. **Animation token mapping table** (codifying axis F):

| Source literal                                              | Halo token                  | Rationale                                  |
|-------------------------------------------------------------|-----------------------------|--------------------------------------------|
| `.spring(response: 0.3, dampingFraction: 0.7)`              | `Animation.haloExpand`      | Reveal/select — closest to halo 0.38/0.78  |
| `.spring(response: 0.3, dampingFraction: 0.8)`              | `Animation.haloExpand`      | Same axis, slightly stiffer dampening      |
| `.spring(response: 0.2, dampingFraction: 0.7)`              | `Animation.haloExpand`      | Faster reveal — same vocabulary axis       |
| `.smooth(duration: 0.3)`                                    | `Animation.haloExpand`      | Generic "smooth" → reveal-class anim       |
| `.easeInOut(duration: 0.22)`                                | `Animation.haloPhaseCrossfade` | Exact match: phase swaps                   |
| `.easeInOut(duration: 0.15 / 0.18 / 0.20)`                  | `Animation.haloPhaseCrossfade` | Sub-225ms swaps — phase-crossfade band     |
| `.easeInOut(duration: 0.3)`                                 | `Animation.haloExpand`      | Generic reveal at this duration            |
| `.easeInOut(duration: 0.5)`                                 | `Animation.haloExpand`      | Slower reveal — borderline; coder review   |
| `.easeInOut(duration: 0.12 / 0.14)`                         | FLAG — no token             | Sub-150ms — neither phase-crossfade nor expand fits cleanly; document and leave |
| `.easeInOut(duration: 1.6).repeatForever`                   | `Animation.haloBreathe`     | Exact match (the recorder's enhancing breath uses this) |
| `.easeOut(duration: ...halfDuration)` / `.easeIn(duration:...)` (PromptChipPicker custom 2-phase) | FLAG — no token | Two-phase swap with explicit halfDuration; not a recorder-grammar shape |
| `.linear(duration: 1).repeatForever` (RecorderComponents)   | EXCLUDED — recorder cluster | Source of truth                            |
| `motion.reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85)` (ProviderCard) | FLAG → W13.E | Tuned for ProviderCard expand; coder defers to model-card rebuild |

5. **The `withAnimation` wrapper IS in scope.** Both forms (`.animation(.literal, value:)` modifier and `withAnimation(.literal) { ... }` block) get the codemod. The token sweep is grammar-uniform, not call-style-uniform.

6. **`.rounded` retirement is W7's job — already done for chrome.** W13.A re-confirms: re-run `grep -rn "design: \.rounded" VoiceInk` should return **only** the metrics hero / hero-numeral sites that W7 explicitly preserves (MetricCard:31, MetricsContent:155, PerformanceAnalysisView:265, 346, 409, PerformanceAnalysisPanelView:82, 170, 243, MetricsSetupView:21). If a NEW `.rounded` site appears outside those 9, escalate — a regression has landed since W7. Q9=a explicitly preserves the Metrics hero `.rounded`; that's covered by W13.B and W7.

7. **AppNotificationView per-type rainbow → defer.** `.red` for `.error` legibility is per-type semantics, not chrome. Master plan §4 W13.G owns the recolor. W13.A only sweeps the `Color.white.opacity(0.1)` strokeBorder at :114 → `Palette.hairlineSoft`.

8. **AudioPlayerView accent fills.** `Color.accentColor` capsule fill at :208 + scrubber playhead at :213 — these are recording/playback live-state affordances. Replace with `Palette.accent` (single tangerine vocabulary). The `.spring(response:0.3, dampingFraction:0.7)` animations at :447, :513 take `Animation.haloExpand` per the table.

9. **Emoji picker selection — accent vs. system.** `EmojiPickerView.swift:165` `strokeBorder(Color.accentColor)` is a chip selection ring. Replace with `Palette.accent`. The `Color.white.opacity(0.8)` `Circle().fill` at :176 is a per-emoji highlight badge — flag (white α0.8 has no Palette token; likely a bright-on-dark dot which is intentional).

10. **PowerMode `.white.opacity(0.06)` chip-fills.** Backplate fills, no Palette token. Coder leaves alone unless surrounding stack is full `glassChip` shape — in which case swap to `.glassChip(cornerRadius: 10)`. Strokes at `0.10` map to `Palette.hairlineSoft`.

11. **PromptChipPicker custom 2-phase animation (`halfDuration`).** Out of scope for axis F — its `easeOut(halfDuration) → easeIn(halfDuration)` shape is a hand-rolled crossfade, not the recorder grammar. Document; flag for spec amendment if the user wants it under `haloPhaseCrossfade`.

12. **CustomPrompt `promptIcon` extension (Models/CustomPrompt.swift:138-303).** A View-extension that hand-rolls a radial-glow tile with `Color.accentColor` gradient + `Color.white.opacity(0.05–0.30)` strokes + `Color(NSColor.controlBackgroundColor)` backplate. Replacing the accent with `Palette.accent` would be a one-line swap, but the rest of the structure (radial gradient, decorative circles, scaleEffect, blur) is a different vocabulary entirely. **Defer entire file to W13.G or a dedicated packet** — flag in §Follow-ups.

13. **CopyIconButton / SaveIconButton (Common/).** Both use `Color(NSColor.controlBackgroundColor).opacity(0.9)` backplate. The W8 surface map didn't sweep them; not pane-level. Defer to W13.G polish (or coder may add a `glassChip(cornerRadius: 6)` swap if it's truly a chip — flag in self-review).

14. **No new tests.** W13.A is pure visual-vocabulary polish. Existing `PaletteTests` (2) + `FailureRegistryTests` (5) + `VoiceInkUITests` (4) must still pass at the integration build. No regressions to assert programmatically — visual smoke is the gate.

---

## Replacement table

Every line below is a grep-validated hit. **Sweep** = land in W13.A. **Defer** = leave for the named packet. **Flag** = ambiguous; coder evaluates context, sweeps if obvious or leaves with comment.

### Axis A — `Color.accentColor` / `Color(.controlAccentColor)` → `Palette.accent`

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/Common/AppIconView.swift:7` | `Color.accentColor.opacity(0.15)` | `Palette.accent.opacity(0.15)` | **Sweep** | Single-tangerine vocab |
| `VoiceInk/Views/Common/AppIconView.swift:21` | `.accentColor.opacity(0.3)` | `Palette.accent.opacity(0.3)` | **Sweep** | shadow color under app icon |
| `VoiceInk/Views/AudioPlayerView.swift:208` | `Capsule().fill(Color.accentColor)` | `Capsule().fill(Palette.accent)` | **Sweep** | playback CTA |
| `VoiceInk/Views/AudioPlayerView.swift:213` | `.fill(Color.accentColor)` | `.fill(Palette.accent)` | **Sweep** | scrubber playhead |
| `VoiceInk/Views/AudioFileRow.swift:177` | `Color.accentColor.opacity(0.12)` | `Palette.accent.opacity(0.12)` | **Sweep** | tab selection bg |
| `VoiceInk/Views/PromptEditorView.swift:411` | `.foregroundStyle(Color.accentColor)` | `.foregroundStyle(Palette.accent)` | **Sweep** | trigger-word add icon |
| `VoiceInk/PowerMode/AppPicker.swift:61` | `Color.accentColor.opacity(0.08)` | `Palette.accent.opacity(0.08)` | **Sweep** | row selection bg |
| `VoiceInk/PowerMode/EmojiPickerView.swift:165` | `strokeBorder(... Color.accentColor ...)` | `strokeBorder(... Palette.accent ...)` | **Sweep** | chip selection ring |
| `VoiceInk/Views/AI Models/AddCustomModelView.swift:53` | `.background(Color.accentColor)` | `.background(Palette.accent)` | **Sweep** | "Add Custom Model" CTA |
| `VoiceInk/Views/AI Models/AddCustomModelView.swift:57` | `Color.accentColor.opacity(0.3)` | `Palette.accent.opacity(0.3)` | **Sweep** | CTA shadow |
| `VoiceInk/Views/AI Models/AddCustomModelView.swift:146` | `Color(.controlAccentColor)` | `Palette.accent` | **Sweep** | Verify-button fill (w/ secondary fallback) |
| `VoiceInk/Views/AI Models/AddCustomModelView.swift:147` | `Color(.controlAccentColor).opacity(0.2)` | `Palette.accent.opacity(0.2)` | **Sweep** | Verify-button shadow |
| `VoiceInk/Views/History/TranscriptionListItem.swift:101` | `Color(NSColor.controlAccentColor)` | `Palette.accent` | **Sweep** | toggle on-state foreground |
| `VoiceInk/PowerMode/EmojiPickerView.swift:165` (above) | — | — | — | (single line covers both fills) |

**Deferred** (routed to W13.B / W13.C / W13.E):

| File:line | Current | Routes to | Reason |
|---|---|---|---|
| `VoiceInk/Views/Metrics/MetricsContent.swift` (controlAccentColor hero gradient at 179-188) | hero gradient | **W13.B** | Q9=a — recolor to `Palette.accent` happens during full hero rebuild |
| `VoiceInk/Views/Metrics/MetricsSetupView.swift:103, 104, 140, 145` | `Color.accentColor` button + ring + shadow | **W13.B** | Welcome flow rebuild owns this surface |
| `VoiceInk/Views/AudioTranscribeView.swift:209, 210, 284, 287` | `Color(.controlAccentColor)` + `Color.accentColor` | **W13.C** | Drop zone + topBar pill rebuild |
| `VoiceInk/Views/AI Models/WhisperModelCardView.swift:45, 157, 158, 265` | accent stroke + button fill | **W13.E** | Card rewrap to `GlassCard(cornerRadius: 16)` recolors strokes |
| `VoiceInk/Views/AI Models/CloudModelCardView.swift:72, 184, 185, 238` | accent stroke + button fill + verify | **W13.E** | Same |
| `VoiceInk/Views/AI Models/FluidAudioModelCardView.swift:57, 158` | accent stroke + capsule fill | **W13.E** | Same |
| `VoiceInk/Views/AI Models/NativeModelCardView.swift:33` | accent stroke | **W13.E** | Same |
| `VoiceInk/Views/AI Models/CustomModelCardView.swift:36` | accent stroke | **W13.E** | Same |
| `VoiceInk/Transcription/Whisper/WhisperModelManager.swift:444` | `Color(.controlAccentColor)` progress fill | **W13.E** | Inside the Whisper download flow — rolled into model-card packet |
| `VoiceInk/Models/CustomPrompt.swift:148, 149, 177, 220, 365` | accent gradient + accent shadow on prompt-icon tile | **W13.G** (or dedicated packet) | Hand-rolled radial-glow tile — not a token sweep |

### Axis B — `Color.white.opacity(...)` → `Palette.hairline / hairlineSoft / innerHi`

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:84` | `Color.white.opacity(0.12)` | `Palette.hairlineSoft` | **Sweep** | unselected stroke (~0.10 ≈ 0.12) |
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:115, 116, 131` | `Color.white.opacity(0.5)` (3×) | `Palette.innerHi.opacity(2.27)` ❌ — leave | **Flag** | 0.5 has no token; bullet dots are decorative ellipsis on the off-state preview |
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:135` | `Color.white.opacity(0.03)` | leave | **Flag** | 0.03 is a faint backplate; below `hairlineSoft` |
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:157` | `Color.white.opacity(0.9)` | leave | **Flag** | bullet glyph fill — content color |
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:199` | `Color.white.opacity(0.95)` | leave | **Flag** | text color, not chrome |
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:208` | `Color.white.opacity(0.16)` | `Palette.hairline` | **Sweep** | exact 0.16 stroke |
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:217` | `Color.white.opacity(0.85)` | leave | **Flag** | text color |
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:225` | `Color.white.opacity(0.16)` | `Palette.hairline` | **Sweep** | exact 0.16 stroke |
| `VoiceInk/PowerMode/PowerModePopover.swift:199` | `Color.white.opacity(0.06)` (fill) | leave | **Flag** | chip backplate fill, no token |
| `VoiceInk/PowerMode/PowerModePopover.swift:203` | `Color.white.opacity(0.10)` (stroke) | `Palette.hairlineSoft` | **Sweep** | exact 0.10 hairline-soft |
| `VoiceInk/PowerMode/PowerModePopover.swift:280` | `Color.white.opacity(hovering ? 0.10 : 0.04)` (fill) | leave | **Flag** | hover backplate, no token |
| `VoiceInk/PowerMode/PowerModePopover.swift:284` | `Color.white.opacity(hovering ? 0.16 : 0.06)` (stroke) | `hovering ? Palette.hairline : Palette.hairlineSoft` ❌ — **Sweep static cases** — but the ternary is already at the right values; replace literal sub-expressions: `Palette.hairline` for 0.16 branch, leave 0.06 sub-stroke as flag | **Sweep partial** | Hover-only stroke band |
| `VoiceInk/PowerMode/PowerModeConfigView.swift:262` | `Color.white.opacity(0.06)` (fill on emoji button) | leave | **Flag** | chip backplate fill, no token |
| `VoiceInk/PowerMode/PowerModeConfigView.swift:420` | `Color.white.opacity(0.05)` (fill) | leave | **Flag** | chip backplate, no token |
| `VoiceInk/PowerMode/PowerModeConfigView.swift:424` | `Color.white.opacity(0.10)` (stroke) | `Palette.hairlineSoft` | **Sweep** | exact 0.10 |
| `VoiceInk/Views/AI Models/MLXModelPickerView.swift:123, 139, 208` | `Color.white.opacity(0.04 / 0.06 / 0.05)` capsule/rect fills | leave | **Flag** | chip backplate fills — would need full `glassChip` rewrap (W13.E rebuild) |
| `VoiceInk/PowerMode/EmojiPickerView.swift:176` | `Circle().fill(Color.white.opacity(0.8))` | leave | **Flag** | white badge dot, no token |
| `VoiceInk/Notifications/AnnouncementView.swift:87` | `Color.white.opacity(0.3)` strokeBorder | leave | **Flag** | HUD inner gloss — runs hotter than `innerHi` (0.22); intentional |
| `VoiceInk/Notifications/AppNotificationView.swift:114` | `Color.white.opacity(0.1)` strokeBorder | `Palette.hairlineSoft` | **Sweep** | exact 0.10 hairline-soft on HUD card |

**Deferred:**

| File:line | Reason |
|---|---|
| `VoiceInk/Models/CustomPrompt.swift:165, 167, 189, 207, 215, 327, 328, 348` | Hand-rolled radial-glow tile gradient stops → **W13.G** (rebuild) |
| `VoiceInk/Views/AI Models/{Whisper,Cloud,FluidAudio,Native,Custom}ModelCardView.swift:*` (`Color.white.opacity(0.08)`) | Card-stroke fallbacks recolor as part of **W13.E** rewrap |
| `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift:23, 102` | Recorder satellite → **W13.G** |
| `VoiceInk/Views/Common/GlassSwitch.swift:37, 46` | Glass primitive — UNTOUCHED |
| `VoiceInk/Views/Common/Palette.swift:56, 59, 63` | Token source-of-truth — UNTOUCHED |
| `VoiceInk/Views/Common/AdaptiveGlassBackground.swift:82, 83` | Glass primitive — UNTOUCHED |
| `VoiceInk/Views/Common/KeyCapView.swift:55` | Keyboard-key glyph color — intentional |
| `VoiceInk/Views/Recorder/HaloMaterial.swift:224, 231, 233, 239, 240, 246, 247` | Recorder primitive — UNTOUCHED (source of vocabulary) |

### Axis C — Raw `.thinMaterial` / `.ultraThinMaterial` → `glassChip()` / `glassPanel()`

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/PromptEditorView.swift:103` | `.fill(.ultraThinMaterial)` | `.glassChip(cornerRadius: 8)` | **Flag — sweep if surrounding rect+stroke matches** | close-button affordance — confirm in coder review |
| `VoiceInk/Views/PromptEditorView.swift:472` | `.background(.ultraThinMaterial)` | `.glassChip(cornerRadius: 10)` (Capsule shape) | **Flag — sweep if it's a trigger-word chip** | line is past Form close (363); audit row #23 already flags this for `glassChip(10)` |
| `VoiceInk/Views/Components/FillerWordsSettingsView.swift:31` | `.fill(.ultraThinMaterial)` | leave | **Defer → W13.G** | structural rebuild |
| `VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift:25` | `.fill(.ultraThinMaterial)` | leave | **Defer → W13.D** | inside Form-host file |
| `VoiceInk/Views/Components/EnhancementSettingsPanel.swift:32, 196` | `.fill(.ultraThinMaterial)` | leave | **Defer → W13.D** | inside Form-host file (32 is in Form pre-section; 196 is inside Form) |
| `VoiceInk/Views/EnhancementSettingsView.swift:88, 145` | `.fill(.ultraThinMaterial)` | leave | **Defer → W13.D** | inside Form block (53-158) |
| `VoiceInk/Views/PermissionsView.swift:191` | `.fill(.ultraThinMaterial)` | leave | **Defer → W13.C** | `PermissionCard` rebuild owns this |
| `VoiceInk/Views/AI Models/MLXModelPickerView.swift:83` | `.fill(.ultraThinMaterial)` | leave | **Defer → W13.E** | row card rewrap |
| `VoiceInk/Views/Metrics/MetricCard.swift:48` | `.fill(.thinMaterial)` | leave | **Defer → W13.B** | full `GlassCard` rewrap |
| `VoiceInk/Views/Metrics/MetricsContent.swift:332` | `.fill(.thinMaterial)` | leave | **Defer → W13.B** | CopySystemInfoButton in hero rebuild |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:184` | `.fill(.thinMaterial)` | leave | **Defer → W13.F** | History window packet |
| `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift:52` | `.fill(.ultraThinMaterial)` | leave | **Defer → W13.G** | recorder satellite |
| `VoiceInk/Views/PromptEditorView.swift:286` | `.background(.ultraThinMaterial)` | leave | **Defer → W13.D** | inside Form block (278-363) |
| `VoiceInk/Views/Common/GlassChip.swift:38` | `shape.fill(.ultraThinMaterial)` | UNTOUCHED — primitive | — | Source of vocabulary |

### Axis D — `Color(.systemFill)` / `.systemFill`

`grep -rn '\.systemFill' VoiceInk --include="*.swift"` returns **zero hits**. No-op axis for W13.A. Confirmed clean post-W1/W5/W6.

### Axis E — `.font(.system(... design: .rounded))` → drop the design parameter

`grep -rn 'design: \.rounded' VoiceInk --include="*.swift"` returns **9 hits**, all on the metrics + welcome hero numerals which W7 explicitly preserves and Q9=a confirms:

```
VoiceInk/Views/Metrics/MetricCard.swift:31                      — KEEP (hero numeral, W7 + Q9)
VoiceInk/Views/Metrics/MetricsContent.swift:155                 — KEEP (hero formatted-time-saved, Q9)
VoiceInk/Views/Metrics/MetricsSetupView.swift:21                — KEEP (welcome marquee)
VoiceInk/Views/Metrics/PerformanceAnalysisView.swift:265        — KEEP (MetricDisplay)
VoiceInk/Views/Metrics/PerformanceAnalysisView.swift:346        — KEEP (speed-factor)
VoiceInk/Views/Metrics/PerformanceAnalysisView.swift:409        — KEEP (enhancement-time)
VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:82    — KEEP (summary pill)
VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:170   — KEEP (speed-factor)
VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:243   — KEEP (enhancement-time)
```

**Action:** verify the grep returns exactly these 9 sites at sweep time. If a NEW `.rounded` site appears (a body-chrome regression landed after W7), reconcile with lead before sweeping — likely a one-line fix.

### Axis F — Ad-hoc `Animation.spring/smooth/easeInOut` → `Animation.halo*`

Per the migration table in §Migration policy point 4. Detailed per-file sweep:

**Sweep:**

| File:line | Current | Replacement | Rationale |
|---|---|---|---|
| `VoiceInk/Views/AudioPlayerView.swift:232` | `.easeInOut(duration: 0.2)` | `Animation.haloPhaseCrossfade` | sub-225ms swap |
| `VoiceInk/Views/AudioPlayerView.swift:447` | `.spring(response: 0.3, dampingFraction: 0.7)` | `Animation.haloExpand` | reveal axis |
| `VoiceInk/Views/AudioPlayerView.swift:513` | `.spring(response: 0.3, dampingFraction: 0.7)` | `Animation.haloExpand` | reveal axis |
| `VoiceInk/Views/PermissionsView.swift:138` | `.easeInOut(duration: 0.5)` | `Animation.haloExpand` | longer reveal — borderline; coder review |
| `VoiceInk/PowerMode/PowerModeView.swift:196, 202` | `.smooth(duration: 0.3)` (2×) | `Animation.haloExpand` | reveal/select |
| `VoiceInk/PowerMode/PowerModeStripView.swift:181` | `.easeInOut(duration: 0.5).repeatForever(autoreverses: true)` | leave | **Flag — no halo token for forever-reveal** (haloBreathe is 1.6s) |
| `VoiceInk/PowerMode/PowerModeStripView.swift:275` | `.easeInOut(duration: 0.14)` | leave | **Flag — sub-150ms** |
| `VoiceInk/Views/AI Models/ModelManagementView.swift:38, 154` | `.smooth(duration: 0.3)` (2×) | `Animation.haloExpand` | reveal/select |
| `VoiceInk/Views/AI Models/ModelManagementView.swift:131, 286` | `.spring(response: 0.3, dampingFraction: 0.8)` (2×) | `Animation.haloExpand` | filter-pill toggle / row expand |
| `VoiceInk/Views/Settings/AudioCleanupSettingsView.swift:49, 79, 88, 126, 160, 199` | `.easeInOut(duration: 0.2)` (6×) | `Animation.haloPhaseCrossfade` | sub-225ms swaps |
| `VoiceInk/Views/Components/PromptSelectionGrid.swift:48` | `.spring(response: 0.3, dampingFraction: 0.7)` | `Animation.haloExpand` | grid select |
| `VoiceInk/Views/Components/FillerWordsSettingsView.swift:22, 80` | `.easeInOut(duration: 0.2)` (2×) | `Animation.haloPhaseCrossfade` | toggle reveal |
| `VoiceInk/Views/Components/SlidingPanel.swift:17, 21` | `.smooth(duration: 0.3)` (2×) | `Animation.haloExpand` | sliding panel |
| `VoiceInk/Views/Settings/SettingsView.swift:588, 604, 608` | `.easeInOut(duration: 0.2)` (3×) | `Animation.haloPhaseCrossfade` | row expand |
| `VoiceInk/Views/PromptEditorView.swift:544, 563` | `.spring(response: 0.2, dampingFraction: 0.7)` (2×) | `Animation.haloExpand` | icon picker select (line 544 / 563 are AFTER Form close at 363 — IN scope) |
| `VoiceInk/Views/History/InlineHistoryView.swift:86` | `.easeInOut(duration: 0.2)` | `Animation.haloPhaseCrossfade` | selection-bar fade |
| `VoiceInk/Views/History/InlineHistoryView.swift:94, 99, 117, 184, 271, 314, 332` | `.smooth(duration: 0.3)` (7×) | `Animation.haloExpand` | panel expand/collapse |
| `VoiceInk/Views/History/InlineHistoryView.swift:263, 543, 564` | `.easeInOut(duration: 0.2)` / `0.15` (3×) | `Animation.haloPhaseCrossfade` | sub-225ms swaps |
| `VoiceInk/Views/History/TranscriptionDetailView.swift:377, 381` | `.easeInOut(duration: 0.2)` (2×) | `Animation.haloPhaseCrossfade` | status fade in/out |
| `VoiceInk/Views/History/TranscriptionListItem.swift:75` | `.easeOut(duration: 0.18)` | `Animation.haloPhaseCrossfade` | hover lift — sub-225ms |
| `VoiceInk/Views/AudioFileRow.swift:128` | `.easeInOut(duration: 0.2)` | `Animation.haloPhaseCrossfade` | row expand |
| `VoiceInk/Views/Settings/RecorderStylePicker.swift:104` | `.easeInOut(duration: 0.15)` | `Animation.haloPhaseCrossfade` | sub-225ms swap |
| `VoiceInk/Views/Dictionary/DictionarySettingsView.swift:44, 79` | `.smooth(duration: 0.3)` (2×) | `Animation.haloExpand` | section reveal |
| `VoiceInk/Views/Dictionary/VocabularyView.swift:77, 164` | `.easeInOut(duration: 0.2)` (2×) | `Animation.haloPhaseCrossfade` | add-button fade |
| `VoiceInk/Views/Dictionary/WordReplacementView.swift:149` | `.easeInOut(duration: 0.2)` | `Animation.haloPhaseCrossfade` | add-button fade |
| `VoiceInk/Views/Dictionary/WordReplacementView.swift:406` | `.easeInOut(duration: 0.18)` | `Animation.haloPhaseCrossfade` | sub-225ms swap |
| `VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift:215` | `.easeInOut(duration: 0.15)` | `Animation.haloPhaseCrossfade` | mode swap |
| `VoiceInk/Views/AI Models/CloudModelCardView.swift:298, 321` | `.easeInOut(duration: 0.3)` (2×) | `Animation.haloExpand` | (NOTE: this file is W13.E rebuild — animations land in W13.E alongside the rewrap; **defer**) |

**Deferred (Form-internal — W13.D):**

```
VoiceInk/Views/EnhancementSettingsView.swift:76, 111, 132     (3× .smooth(0.3) inside Form 53-158)
VoiceInk/Views/AudioTranscribeView.swift:110, 115, 124         (3× .easeInOut(0.2) inside Form 103-129)
VoiceInk/Views/Components/EnhancementSettingsPanel.swift:83, 87, 115, 132, 213, 215   (inside Form 53-172)
VoiceInk/Views/PromptEditorView.swift:286-area                 (inside Form 278-363; line 286 is .ultraThinMaterial axis C, but Form-internal animations are out)
VoiceInk/Views/History/InlineHistoryView.swift inside cardListView Form (255-298) — none of the animation hits sit inside this range; all current InlineHistoryView animation hits are outside it
```

**Deferred (W13.B / Metrics):**

```
VoiceInk/Views/Metrics/MetricsContent.swift:324, 327, 336, 342, 347     (5× .spring(0.3, 0.7) — copy-confirm)
```

**Deferred (W13.C / AudioTranscribe + Permissions):**

```
VoiceInk/Views/AudioTranscribeView.swift:41, 64, 217, 296                (4× outside Form: 41=clear, 64=drop-target, 217=clear-button, 296=drop-target stroke)
   — these *could* sweep in W13.A but the surrounding chrome rebuild lands in W13.C; coder co-locates with rebuild for review clarity
VoiceInk/Views/PermissionsView.swift:138 (handled above as **Sweep**)
```

**Deferred (W13.D — outside-Form-but-related):**

```
VoiceInk/Views/EnhancementSettingsView.swift:45, 221, 239, 285           (4× outside Form, but in same file as Form-host purge)
   — coder choice: sweep here OR co-locate with W13.D for atomic review; recommend defer
```

**Deferred (W13.E — Provider/Model card rebuilds):**

```
VoiceInk/Views/AI Models/ProviderCard.swift:150, 631                     (.spring(0.32, 0.85) with reduce-motion guard — tuned constant, defer)
VoiceInk/Views/AI Models/CloudModelCardView.swift:298, 321               (above)
```

**Deferred (W13.F):**

```
VoiceInk/Views/History/TranscriptionHistoryView.swift:114, 118, 125, 144, 353  (5× .smooth(0.3))
```

**Recorder cluster — UNTOUCHED:**

```
VoiceInk/Views/Recorder/RecorderComponents.swift:93, 331
VoiceInk/Views/Recorder/Constellation/ClusterMotion.swift:12, 17, 22, 27, 31, 35
VoiceInk/Views/Common/Animation+Halo.swift:21, 24, 28, 32, 141, 170      (token source-of-truth)
```

**Custom 2-phase (no halo token applies — flag):**

```
VoiceInk/Views/Common/PromptChipPicker.swift:125, 129    (.easeOut/.easeIn(halfDuration) — hand-rolled crossfade)
```

### Axis G — `Color(NSColor.windowBackgroundColor)` / `Color(NSColor.controlBackgroundColor)`

Per dossier: "**replacement: `glassPanel()` background; if window is a separate NSWindow ensure isOpaque=false too — but that's W13.F, just flag**". W8 already swept the pane-root `.background(...)` calls (see W8 plan §File structure for the 27 sites). Remaining hits as of 2026-04-29:

| File:line | Current | Disposition | Routes to |
|---|---|---|---|
| `VoiceInk/HistoryWindowController.swift:54` | `window.backgroundColor = NSColor.windowBackgroundColor` | **Defer** | **W13.F** (NSWindow flip) |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:133, 321, 392` | `Color(NSColor.windowBackgroundColor / .controlBackgroundColor)` | **Defer** | **W13.F** |
| `VoiceInk/Views/Metrics/HelpAndResourcesSection.swift:41` | `Color(nsColor: .windowBackgroundColor)` | **Defer** | **W13.B** (full `GlassCard` rewrap) |
| `VoiceInk/Views/Metrics/MetricsSetupView.swift:62` | `Color(NSColor.controlBackgroundColor)` | **Defer** | **W13.B** |
| `VoiceInk/Views/Metrics/PerformanceAnalysisView.swift:159, 432` | `Color(.windowBackgroundColor)` | **Defer** | **W13.B** |
| `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:20, 109` | `Color(NSColor.windowBackgroundColor / .controlBackgroundColor)` | **Defer** | **W13.B** |
| `VoiceInk/Views/AudioTranscribeView.swift:56` | `Color(.windowBackgroundColor).opacity(0.4)` | **Defer** | **W13.C** |
| `VoiceInk/Views/Settings/AudioInputSettingsView.swift:426` | `Color(.windowBackgroundColor).opacity(0.4)` | **Defer** | priority-list chip; **W13.G** polish |
| `VoiceInk/Views/Dictionary/VocabularyView.swift:173` | `Color(.windowBackgroundColor).opacity(0.4)` | **Defer** | **W13.C** (drop-zone family) |
| `VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift:367` | `Color(NSColor.controlBackgroundColor).opacity(0.7)` | **Defer** | **W13.G** polish |
| `VoiceInk/Views/Settings/EnhancementShortcutsView.swift:61` | `Color(NSColor.controlBackgroundColor)` | **Defer** | **W13.G** polish |
| `VoiceInk/Views/PromptEditorView.swift` (none — W8 swept these) | — | — | — |
| `VoiceInk/Views/PredefinedPromptsView.swift:69` | `Color(NSColor.controlBackgroundColor)` | **Defer** | **W13.G** (full template-button rebuild) |
| `VoiceInk/Views/Common/CopyIconButton.swift:13` | `Color(NSColor.controlBackgroundColor).opacity(0.9)` | **Defer** | **W13.G** polish |
| `VoiceInk/Views/Common/SaveIconButton.swift:21` | `Color(NSColor.controlBackgroundColor).opacity(0.9)` | **Defer** | **W13.G** polish |
| `VoiceInk/Views/History/HistoryShortcutTipView.swift:40` | `Color(NSColor.controlBackgroundColor).opacity(0.5)` | **Defer** | **W13.G** polish |
| `VoiceInk/Views/AI Models/AddCustomModelView.swift:157` | `Color(.windowBackgroundColor)` | **Defer** | **W13.E** (rebuild family) |
| `VoiceInk/Views/AI Models/LanguageSelectionView.swift:152` | `Color(NSColor.controlBackgroundColor)` | **Defer** | **W13.E** (rebuild family) |
| `VoiceInk/PowerMode/PowerModeConfigView.swift:349` | `Color(NSColor.controlBackgroundColor)` | **Defer** | **W13.G** polish |
| `VoiceInk/Models/CustomPrompt.swift:152, 153, 315, 316` | `Color(NSColor.controlBackgroundColor).opacity(...)` | **Defer** | **W13.G** (CustomPrompt tile rebuild) |

**Net result for axis G in W13.A: zero sweeps.** All remaining `windowBackgroundColor` / `controlBackgroundColor` hits are downstream of structural rebuilds and route to other packets.

---

## Tasks

### Task 0: Audit + grep validation (read-only)

**Files:** none.

- [ ] **Step 0.1: Re-run all six axis greps and confirm hit counts match this plan**

```bash
# Axis A — Color.accentColor / controlAccentColor
rg -n 'Color\.accentColor|Color\(\.controlAccentColor\)|Color\(NSColor\.controlAccentColor\)' VoiceInk/ --type swift

# Axis B — Color.white.opacity(...)
rg -n 'Color\.white\.opacity\(' VoiceInk/ --type swift

# Axis C — raw materials
rg -n '\.thinMaterial|\.ultraThinMaterial|\.regularMaterial|\.thickMaterial' VoiceInk/ --type swift

# Axis D — systemFill
rg -n '\.systemFill|Color\(\.systemFill\)' VoiceInk/ --type swift

# Axis E — .rounded
rg -n 'design:\s*\.rounded' VoiceInk/ --type swift

# Axis F — ad-hoc animations
rg -n 'Animation\.spring|Animation\.smooth|Animation\.easeInOut|\.spring\(response:|\.smooth\(duration:|\.easeInOut\(duration:|\.easeIn\(duration:|\.easeOut\(duration:|\.linear\(duration:' VoiceInk/ --type swift
rg -n 'withAnimation\(\.' VoiceInk/ --type swift

# Axis G — window-bg
rg -n 'windowBackgroundColor|controlBackgroundColor' VoiceInk/ --type swift
```

If hit counts differ from this plan's classification, escalate to lead. Do not drift.

- [ ] **Step 0.2: Verify the excluded-files list is intact**

```bash
ls VoiceInk/Views/Recorder/ VoiceInk/Views/Recorder/Constellation/
ls VoiceInk/Views/Common/Glass*.swift VoiceInk/Views/Common/Palette.swift VoiceInk/Views/Common/Animation+Halo.swift VoiceInk/Views/Common/AdaptiveGlassBackground.swift VoiceInk/Views/Common/HaloMaterial.swift 2>/dev/null
```

Confirm these files exist and remain UNTOUCHED through the packet.

### Task 1: Axis A — sweep `Color.accentColor` → `Palette.accent`

**Files:** AppIconView, AudioPlayerView, AudioFileRow, PromptEditorView, AppPicker, EmojiPickerView, AddCustomModelView, TranscriptionListItem.

- [ ] Per the **Axis A — Sweep** table above, replace every cited token with `Palette.accent[.opacity(α)]`. Single-line edits. No structural changes.

### Task 2: Axis B — sweep `Color.white.opacity(0.16 / 0.10 / 0.22)` strokes → `Palette.hairline / hairlineSoft / innerHi`

**Files:** RecorderStylePicker (2 strokes), PowerModePopover (1 stroke + partial ternary), PowerModeConfigView (1 stroke), AppNotificationView (1 stroke).

- [ ] Per the **Axis B — Sweep** table above. Leave all flagged fills/decoratives alone; document in self-review.

### Task 3: Axis C — sweep isolated `.ultraThinMaterial` chip stacks → `glassChip()` / `glassPanel()`

**Files:** PromptEditorView (lines 103, 472 — both flag for coder context-eval).

- [ ] Per the **Axis C — Sweep** table above. If surrounding chrome doesn't match the GlassChip vocabulary (rect + stroke + inner gloss), DO NOT swap — flag in self-review and let W13.G handle it.

### Task 4: Axis E — re-confirm `.rounded` is W7-clean

**Files:** none (read-only verification).

- [ ] Re-run the axis E grep. Confirm exactly 9 hits, all in the metrics + welcome hero numerals. If a NEW hit surfaces, escalate to lead.

### Task 5: Axis F — codemod animations to `Animation.halo*` tokens

**Files:** AudioPlayerView, PermissionsView, PowerModeView, ModelManagementView, AudioCleanupSettingsView, PromptSelectionGrid, FillerWordsSettingsView, SlidingPanel, SettingsView, PromptEditorView, InlineHistoryView, TranscriptionDetailView, TranscriptionListItem, AudioFileRow, RecorderStylePicker, DictionarySettingsView, VocabularyView, WordReplacementView, DictionaryQuickAddPanel.

- [ ] Per the **Axis F — Sweep** table above. Use the migration table at §Migration policy point 4 for the source → token mapping. Leave flagged literals (sub-150ms eases, 0.5s repeatForever, custom-tuned springs) alone.

### Task 6: Self-review + grep follow-up

**Files:** none (read-only).

- [ ] Re-run all six axis greps. Document remaining hits — they should ALL match this plan's "Defer" or "Flag" / "UNTOUCHED" classifications.
- [ ] Confirm the excluded-files list still has zero edits.
- [ ] Confirm zero `.rounded` regressions outside the 9 hero-numeral sites.
- [ ] Confirm `Animation+Halo.swift` reviewer note at lines 14-17 is preserved.

### Task 7: Integration build

**Files:** none.

- [ ] Run `make local` (single integration build, per `feedback_skip_per_packet_builds.md`). Expect ~3 min cold; ~30s warm.
- [ ] Confirm zero new warnings related to W13.A edits (the codemod is type-stable; mismatches would surface as compile errors immediately).

### Task 8: Visual smoke pass

**Files:** none.

- [ ] Open the app. Eyeball each of these surfaces under (a) system Light, (b) system Dark, (c) bright wallpaper, (d) dark wallpaper:
  - Settings → Recording (Recorder Style picker — strokes recolor; selection ring `Palette.accent`)
  - Settings → Power Mode → click into a config (emoji button + scenario chips — strokes hairlineSoft)
  - AI Models → Add Custom Model (CTA button tangerine, not blue; verify-button tangerine when filled)
  - History → row hover (animation feels snappier — haloPhaseCrossfade vs ad-hoc ease)
  - Audio Player (transcription detail) — playhead + scrubber tangerine
  - Dictionary → Add Word (animation crispness)
  - HUD `AppNotification` (inner stroke softer post-W13.A)
- [ ] Confirm no surface flickers, no regressed contrast under Reduce-Transparency or Increase-Contrast.

### Task 9: Commit + report to lead

- [ ] Lead handles commits per CLAUDE.md cadence:
  ```
  docs(plans): W13A — token sweep
  feat(aesthetic): W13A — token sweep
  ```
- [ ] Report to lead: `task-id`, edited file list, total LOC delta, smoke-pass observations, any flagged hits left untouched (with reason).

---

## Verification

1. **Build green.** `xcodebuild build` (or `make local`) at Task 7. Zero warnings, zero errors related to W13.A surfaces.
2. **Grep follow-up clean.** All Axis A/B/E hits in W13.A scope are gone; remaining hits all classify as Defer or Untouched per this plan.
3. **Visual smoke green.** Task 8 — every targeted surface reads tangerine-on-glass under all four wallpaper/system-mode permutations.
4. **No primitive drift.** `Palette.swift`, `GlassChip.swift`, `GlassCard.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` are byte-identical pre/post.
5. **No recorder-cluster drift.** `RecorderComponents.swift`, `Constellation/ClusterMotion.swift`, all `Halo*Recorder*` panels are byte-identical pre/post.

---

## Rollback plan

Single-commit packet (`feat(aesthetic): W13A — token sweep`). If a regression surfaces:

```bash
git revert <sha>
```

Reverts cleanly because every edit is a one-line token swap — no companion edits, no schema migrations, no dependency changes. The `docs(plans): W13A — token sweep` commit can stay (the plan document itself is reusable across re-attempts).

If a *partial* regression surfaces (e.g. one specific animation reads wrong post-codemod), rollback the offending file's edit via `git checkout <sha>~1 -- <file>` and re-commit — preserves the rest of the sweep.

---

## Risks

1. **Semantic-token mismatches** (highest). `Color.white.opacity(0.05)` could mean stroke OR fill OR shadow OR backplate depending on the surrounding chrome. The Migration policy point 1 + the `Flag` dispositions in the Replacement table explicitly carve out fills (no Palette token applies). Coder must read context, not blindly substitute. **Mitigation:** every sub-0.10 hit is `Flag` (leave alone); only ~0.10/0.16/0.22 hits sweep automatically.

2. **Animation timing drift** (medium). `Animation.haloExpand` is `spring(response: 0.38, dampingFraction: 0.78)`. Source literals at `spring(0.3, 0.7)` are slightly faster + bouncier. Post-sweep, animations will read ~25ms slower and ~10% less bouncy. **Mitigation:** that's the *point* of the cohesion sweep — recorder grammar wins over per-call-site idiosyncrasy. Visual smoke at Task 8 catches anything off.

3. **`.easeInOut(duration:0.12 / 0.14)` sub-150ms gaps** (low). Two sites (PowerModeStripView:275, EnhancementSettingsView:285) use durations below the `haloPhaseCrossfade` band (0.22s). Replacing with the slower token would visibly slow them down. **Mitigation:** flagged as "no token matches" — leave alone. Spec amendment if user wants a `haloFlash` token at 0.12-0.15s.

4. **Custom-tuned springs in ProviderCard** (low). `spring(0.32, 0.85)` is explicitly tuned for the provider-card expand/collapse. Forcing `haloExpand` (0.38, 0.78) would change the feel. **Mitigation:** routed to W13.E rebuild — coder evaluates alongside the card primitive rewrap.

5. **MenuBarExtra renders custom backgrounds as no-op** (none for W13.A — file excluded). Documented per Q7=b. Future spec extension may revisit.

6. **`Color.white.opacity(0.5+)` inner gloss values on HUD** (low). `AnnouncementView.swift:87` runs at 0.30 — hotter than `Palette.innerHi (0.22)`. The HUD context (always-on-darker-glass) tolerates more inner sheen. **Mitigation:** flag, leave alone. Spec amendment if a `Palette.innerHiHUD` token is ever added.

7. **Build-time surprises** (low). The `Color(.controlAccentColor)` form at `WhisperModelManager.swift:444` is inside a non-View file by directory but does compile against SwiftUI. Sweeping it requires confirming the file imports SwiftUI (it does — confirmed at task time). **Mitigation:** routed to W13.E (model-card rebuild) instead of swept here.

8. **Test-fixture drift** (none for W13.A). `VoiceInkTests/PaletteTests` (2) + `FailureRegistryTests` (5) + `VoiceInkUITests` (4) don't reference any of the surface tokens this packet sweeps. **Mitigation:** integration build (Task 7) catches anything.

---

## Follow-ups for B–G packets

### W13.B — Metrics dashboard rebuild

- Q9=a sign-off: `MetricsContent.heroSection` keeps gradient identity, recolor to `Palette.accent`. Plan owner: B.
- `MetricsContent.swift:155` `.font(.system(size: 36, design: .rounded))` — KEEP (Q9 + W7 brief).
- `MetricCard.swift:31` `.font(.system(size: 24, weight: .black, design: .rounded))` — KEEP.
- `MetricCard.swift:48` `.fill(.thinMaterial)` — full `GlassCard(cornerRadius: 16)` rewrap.
- `HelpAndResourcesSection.swift:41` `Color(nsColor: .windowBackgroundColor)` + 28pt radius — full rewrap.
- `MetricsSetupView.swift:62, 103, 104, 140, 145` — welcome-flow rebuild (controlBackgroundColor + accent buttons + 28pt `.rounded`).
- `PerformanceAnalysisView.swift:159, 432` + `PerformanceAnalysisPanelView.swift:20, 109` — pane chrome.
- `MetricsContent.swift:324, 327, 336, 342, 347` — 5× `.spring(0.3, 0.7)` copy-confirm anims → `Animation.haloExpand`.

### W13.C — Permissions + AudioTranscribe re-skin

- `PermissionsView.swift:191` — `.ultraThinMaterial` → `GlassCard(cornerRadius: 14)` rewrap (PermissionCard).
- `AudioTranscribeView.swift:56, 64, 217, 284, 287, 296` — drop-zone + topBar pill + clear-button rebuild.
- `AudioTranscribeView.swift:209, 210` — accent capsule fills.
- `AudioTranscribeView.swift:103-129` — queue Form → LazyVStack of GlassCards.
- `Dictionary/VocabularyView.swift:173` — drop-zone family.

### W13.D — Form-host purge (5 surfaces)

- `EnhancementSettingsView.swift:53-158` (Form host) → ScrollView/LazyVStack/SettingsCard. Sweeps internal `.ultraThinMaterial` (88, 145) + `.smooth(0.3)` (76, 111, 132) + `.easeInOut(0.2)` (285) along the way.
- `Components/EnhancementSettingsPanel.swift:53-172` (Form host) → same. Sweeps `.ultraThinMaterial` (32, 196) + animations (83, 87, 115, 132, 213, 215).
- `PromptEditorView.swift:224-270, 278-363` (two Form panes) → flat VStack. Sweeps `.ultraThinMaterial` (286).
- `History/InlineHistoryView.swift:255-298` (cardListView Form) → LazyVStack of GlassCards.
- `AudioTranscribeView.swift:103-129` (queue Form) — already in W13.C scope; coder picks one packet (recommend C since it's spatial-co-located with the drop zone rebuild).
- `Dictionary/DictionarySettingsPanel.swift:46-56` (Form host) → migrate.
- `Common/TranscriptionInfoPanel.swift:9-15` (Form host) — small; W13.D sweeps it too.
- `ModelSettingsView.swift:16-107` — large legacy Form; coder evaluates whether it's still reachable (may be retired).

### W13.E — AI Models card unification

- `WhisperModelCardView.swift:36-49, 45, 157, 158, 265` — `HaloMaterial(phase: .hidden)` direct usage → `GlassCard(cornerRadius: 16)`. Card strokes recolor via `Palette.accent` / `Palette.hairline`.
- `CloudModelCardView.swift:63-76, 72, 184, 185, 238, 298, 321` — same.
- `FluidAudioModelCardView.swift:48-60, 57, 158` — same.
- `NativeModelCardView.swift:33` — same.
- `CustomModelCardView.swift:36` — same.
- `MLXModelPickerView.swift:78-90, 83, 123, 139, 208` — row card + chip-fill backplates.
- `AddCustomModelView.swift:157` — `windowBackgroundColor` pane chrome.
- `LanguageSelectionView.swift:152` — `controlBackgroundColor` pane chrome.
- `ProviderCard.swift:150, 631` — custom-tuned spring (0.32, 0.85); coder evaluates whether to migrate to `Animation.haloExpand` or codify a new `Animation.providerExpand` token.
- `Transcription/Whisper/WhisperModelManager.swift:444` — `Color(.controlAccentColor)` download-progress fill → `Palette.accent`.
- `ModelManagementView.swift:105-118` — `Default Model` section uses `.headline / .title2`; replace with `SettingsSectionHeader`.

### W13.F — History window glass + animation codemod

- `HistoryWindowController.swift:54` — `window.backgroundColor = .windowBackgroundColor`. Mirror `WindowManager.configureWindow:36-41` flags (`isOpaque = false`, `backgroundColor = .clear`).
- `TranscriptionHistoryView.swift:133, 184, 295-301, 321, 392` — drop hardcoded `Color(NSColor.windowBackgroundColor / .controlBackgroundColor / .thinMaterial)`. Search field at :184 → `glassChip` (Capsule).
- `TranscriptionHistoryView.swift:114, 118, 125, 144, 353` — 5× `.smooth(0.3)` → `Animation.haloExpand`.

### W13.G — Polish

- `Common/CompactHeroSection.swift:13` — `.foregroundStyle(.blue)` → `Palette.accent` (master plan §4 W13.G bullet).
- `Notifications/AppNotificationView.swift:30-36` — per-type rainbow → `Palette.accent / .success / .warn / .neutral` (master plan §4 W13.G).
- `PowerModeView.swift:84-207` — hero header → `SettingsSectionHeader(icon: "bolt.fill", title:"Power Modes", accent: Palette.warn)` (audit row #28).
- `PromptEditorView.swift:471-478` — trigger-word chips → `glassChip(cornerRadius: 10)` (audit row #23).
- `Recorder/EnhancementPromptPopover.swift:50-66` — backdrop → `glassPanel(cornerRadius: 14)`; drop forced `.dark` colorScheme (audit row #27).
- `PredefinedPromptsView.swift:67-89` — full template-button rebuild → `GlassCard(cornerRadius: 16)`.
- `Models/CustomPrompt.swift:138-303` — `promptIcon` extension full rebuild (radial-glow tile is anti-spec). Could also be its own dedicated packet given the surface area.
- `Common/CopyIconButton.swift:13`, `SaveIconButton.swift:21`, `History/HistoryShortcutTipView.swift:40`, `Settings/EnhancementShortcutsView.swift:61`, `PowerModeConfigView.swift:349`, `Settings/AudioInputSettingsView.swift:426`, `Dictionary/DictionaryQuickAddPanel.swift:367` — `controlBackgroundColor` chip-level affordances.
- `PromptChipPicker.swift:125, 129` — custom 2-phase crossfade. Spec amendment candidate.
- `PowerModeStripView.swift:181, 275`, `EnhancementSettingsView.swift:285` — sub-150ms / 0.5s-repeatForever animations with no halo token. Spec amendment candidate.

### Final spec extension (per master plan §4 W13.G)

After W13.A–G land, amend `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.X (or write `2026-04-29-aesthetic-redesign-W13-deltas.md`) with:
- Codified animation token mapping table (the §Migration policy point 4 table from this plan).
- Confirmation that `Color.white.opacity(...)` chip-fill backplates at 0.04-0.08 are NOT covered by `Palette.hairline*` — those are stroke-side tokens only.
- Q9=a sign-off: Metrics hero gradient retained but tangerine.
- Q7=b sign-off: menubar dropdown stays system-default.

---

## Open questions

None. All Q-decisions resolved at master plan §0 sign-off (Q1-Q11 incl. Q7=b and Q9=a). Risks 1-8 above are acknowledged trade-offs, not unresolved questions.
