# W8 — Adaptive Glass App-Wide Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.

**Goal:** Propagate the recorder's adaptive-glass vocabulary (`HaloMaterial` + `GlassAppearanceDetector`) to every solid-background main-window surface in the app. User instruction: "do glass scope on everything" — broader than the 3-surface lead recommendation. In practice: introduce one new app-shell primitive (`AdaptiveGlassBackground`), opt the main `NSWindow` into non-opaque so behind-window blur reveals wallpaper, then replace `Color(NSColor.controlBackgroundColor)` / `Color(NSColor.windowBackgroundColor)` on **27 sites** spanning detail-pane roots, sub-pane bands, sliding-panel chrome, and the recorder enhancement popover. MenuBar dropdown is explicitly out of scope (system NSMenu chrome is not skinnable). Cards inside the panes (already W1 `GlassCard` / `glassChip` / `glassPanel`) keep their existing translucency; the **gap area** behind them flips from opaque → adaptive glass.

**Architecture (surface vocabulary map):**

```
Tier                                          Current treatment                                Target treatment
─────────────────────────────────────────     ─────────────────────────────────                ────────────────────────────────────
A. Main window shell                          NSWindow opaque, controlBackgroundColor          NSWindow non-opaque + clear bg, AdaptiveGlassBackground at SwiftUI root
B. Detail-pane roots (10 surfaces)            .background(controlBackgroundColor)              .adaptiveGlassBackground()
C. Sub-pane flush bands (5 sites)             .background(windowBackgroundColor)               removed — rely on inherited pane glass
D. Sliding-panel chrome (10 sites)            .background(windowBackgroundColor)               .adaptiveGlassBackground(intensity: .panel)
E. Recorder popover (1 site)                  .background(Color.black)                         GlassCard(appearance: .onyx) wrap
F. Sidebar (NavigationSplitView default)      system .sidebar vibrancy — already translucent   verify; no edit unless smoke pass shows seam
G. MenuBar dropdown                           native NSMenu (`.menuBarExtraStyle(.menu)`)      OUT OF SCOPE — not skinnable
H. Recorder cluster panels                    HaloMaterial onyx/light                          OUT OF SCOPE — already adaptive
I. AppNotification / Announcement panels      VisualEffectView .hudWindow                      OUT OF SCOPE — already glass
```

**Architecture (`AdaptiveGlassBackground` primitive):**

```
AdaptiveGlassBackground (new ViewModifier — VoiceInk/Views/Common/AdaptiveGlassBackground.swift)
├── @ObservedObject detector = GlassAppearanceDetector.shared
├── if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
│       → Color(NSColor.controlBackgroundColor)            (opaque fallback, no NSVisualEffect)
├── else if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
│       → Color(NSColor.windowBackgroundColor)             (opaque, per HaloMaterial spec §6.4 contract)
└── else
        → ZStack
            ├── VisualEffectBlur                            (reuses recorder's NSViewRepresentable)
            │     material:      .fullScreenUI            (deeper-tinted than .hudWindow; less halo, more weight)
            │     blendingMode:  .behindWindow             (sees wallpaper through transparent NSWindow)
            │     appearanceName: detector.current → .aqua / .darkAqua
            └── tint overlay
                  appearance == .onyx  → Color.black.opacity(0.42)
                  appearance == .light → Color.white.opacity(0.18)
```

**Two intensities, one modifier:**
- `.adaptiveGlassBackground()` — default. For pane roots (Tier B). Deep tint, subtle behind-window blur.
- `.adaptiveGlassBackground(intensity: .panel)` — for sliding-panel chrome (Tier D). Slightly higher fill alpha (onyx 0.52 / light 0.26) so the panel reads as a "stepped-up" surface above the underlying pane.

The numeric tints are derived from `HaloMaterial`'s onyx/light fill ramp (0.78 / 0.32 for chips → halved for full-bleed surfaces because the surface area is much larger and the user reads cards on top, not the bg itself). Locked values; do not hand-tune per pane.

**Architecture (window transparency — gating decision):**

```
WindowManager.configureWindow (current)               WindowManager.configureWindow (W8)
─────────────────────────────────                     ─────────────────────────────────
window.backgroundColor = .windowBackgroundColor      window.backgroundColor = .clear
window.isOpaque         = true                       window.isOpaque         = false
window.titlebarAppearsTransparent = true             (unchanged — already transparent)
window.titleVisibility            = .hidden          (unchanged)
```

**Why non-opaque:** the recorder cluster's wallpaper-through glass works because its NSPanel is `.clear` + `isOpaque = false`. To replicate that on the main app, the same two flags flip. With them flipped + `AdaptiveGlassBackground` at the SwiftUI root (or at each pane root, redundant but safe), wallpaper bleeds through the gap area that the cards-on-top don't cover. Without flipping them, the SwiftUI `VisualEffectBlur(.behindWindow)` paints over the opaque window background and the wallpaper never reads — Option D (system-adaptive `.regularMaterial`) would be the only viable fallback and the user's "adaptive glass" intent (per the recorder's wallpaper-luminance adaptation via `GlassAppearanceDetector`) would be lost.

**Tradeoff acknowledged (this is the #1 risk):** non-opaque main windows on macOS occasionally show edge-shadow artifacts during resize, and translucent backgrounds can reduce text contrast on busy wallpapers. Mitigations:
1. The two accessibility branches above already cover the "I want opaque" preference users.
2. Detail-pane content sits on `GlassCard` / `glassChip` / `glassPanel` which already have their own backstops — the pane bg only shows in the gap.
3. The `material: .fullScreenUI` is the most opaque NSVisualEffectView material that still picks up wallpaper hue; chosen specifically to keep cards readable. (Alternative materials and why rejected: `.hudWindow` is too thin for full-bleed; `.windowBackground` is opaque and defeats the point; `.contentBackground` is appearance-only, doesn't track wallpaper luminance well.)
4. Visual smoke pass at Task 23 is mandatory and must include both bright + dark wallpapers, both system Light/Dark, Reduce-Transparency on, and High-Contrast on.

**Tech Stack:** Swift 5.x, SwiftUI, AppKit (`NSWindow` flags + `NSVisualEffectView`), Xcode 16.x. Build via `make local` (~3 min cold). Reuses existing `VisualEffectBlur` + `GlassAppearanceDetector` from W1; no new dependencies. No new tests (pure visual surface migration; existing `PaletteTests` (2) + `FailureRegistryTests` (5) + `VoiceInkUITests` (4) must still pass at integration build).

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens — "Translucent glass refraction stays. What changes: edges, palette, type, geometry."), §2.3 (recorder's onyx/light glass vocabulary — re-applied here), §3.2 (cluster glass — referenced for material constants), §6.1 (wallpaper-luminance detector), §6.4 (Reduce-Transparency / High-Contrast contracts). W8 adds a new sub-section §1.X "Adaptive glass app-wide" via Task 22 — extends rather than supersedes.

**Handoff refs:** `docs/superpowers/handoffs/HANDOFF_post_redesign_open_asks_2026-04-29.md` — Ask 1 ("Adaptive glass app-wide"). The handoff lead-recommended a 3-surface scope (main ContentView + detail panes + sidebar chrome). User redirected: "do glass scope on everything" — this plan honors the broader scope. The lead's "invasive on detail panes" caveat is preserved as risk #1 below.

**CLAUDE.md cadence rules respected:**
- **Single integration build at merge time.** No `make local` per task; one full build at Task 22 (after primitive + all 27 surfaces land).
- **No commits during execution.** Coder reports to lead at Task 23; lead handles commits.
- **No `xcodebuild` per file.** SourceKit handles per-file syntax during edits.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** Inline doc-comments cite spec §1 / §2.3 / §6.1 / §6.4 + this plan path; do not reference PR numbers.
- **Pre-existing spec-ref comments preserved.** `Palette.swift` §1, `GlassChip.swift` §1, `HaloMaterial.swift` §2.3 + §6.4, `GlassAppearance.swift` §6.1 stay untouched. New `AdaptiveGlassBackground.swift` cites §1 + §6.1 + §6.4 + this plan.

---

## File structure

### New files

- `VoiceInk/Views/Common/AdaptiveGlassBackground.swift` — new view modifier. Two intensities (`.pane`, `.panel`). Reads `GlassAppearanceDetector.shared.current` for wallpaper-adaptive appearance. Branches once on Reduce-Transparency / High-Contrast and falls back to opaque palette tokens. Reuses existing `VisualEffectBlur` from `HaloMaterial.swift`. ~95 LOC.

### Modified files

- `VoiceInk/WindowManager.swift` — `configureWindow` (lines 19-44). Flip `window.backgroundColor = .windowBackgroundColor` (line 32) → `.clear`; flip `window.isOpaque = true` (line 37) → `false`. Add a one-line doc comment citing spec §1 + this plan path. ~+3 LOC, -2 LOC. Blast radius: every pane in the main window inherits a transparent host.
- `VoiceInk/Views/ContentView.swift` — verification + cleanup. The pre-existing `VisualEffectView` struct (lines 37-53) is unused (defined but never applied) — flag it: either retire (delete, drop ~17 LOC) OR leave as-is for downstream callers if any landed since plan-time. Coder runs `grep -rn "VisualEffectView(" VoiceInk` to confirm zero call sites; if zero, delete. Add `.adaptiveGlassBackground()` to NavigationSplitView body (line 122) as a defensive backstop in case a future detail pane forgets to apply its own. ~+1 LOC, -17 LOC (if the unused struct is retired).
- `VoiceInk/Views/MetricsView.swift:12` — replace `.background(Color(.controlBackgroundColor))` with `.adaptiveGlassBackground()`. ~+0 LOC, -0 LOC (single-line swap).
- `VoiceInk/Views/Metrics/MetricsContent.swift:41` + `:141` — drop both `.background(Color(.windowBackgroundColor))` lines (now flush with the pane glass via inheritance from `MetricsView`). ~-2 LOC.
- `VoiceInk/Views/AI Models/ModelManagementView.swift:57` — replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`. ~+0 LOC, -0 LOC.
- `VoiceInk/Views/AI Models/ModelManagementView.swift:95` — sliding-panel header band. Replace `.background(Color(NSColor.windowBackgroundColor))` with `.adaptiveGlassBackground(intensity: .panel)`. ~+0 LOC, -0 LOC.
- `VoiceInk/Views/History/InlineHistoryView.swift:88` — pane root. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`.
- `VoiceInk/Views/History/InlineHistoryView.swift:106` — overlay panel content. Replace `.background(Color(NSColor.windowBackgroundColor))` with `.adaptiveGlassBackground(intensity: .panel)`.
- `VoiceInk/Views/History/InlineHistoryView.swift:230` — empty-state overlay. Drop `Color(NSColor.windowBackgroundColor)` flush band (inherits glass).
- `VoiceInk/Views/History/InlineHistoryView.swift:343` + `:350` — selection-bar chrome. The `:343` `Color.secondary.opacity(0.1)` chip stroke is a chip-level token (preserve), but the surrounding `:350` selection-bar wrapper bg `Color(NSColor.windowBackgroundColor)` swaps to `.adaptiveGlassBackground(intensity: .panel)` so the bar reads as a stepped-up overlay above the pane glass.
- `VoiceInk/Views/EnhancementSettingsView.swift:161` — Form-grouped pane root. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`. The `.scrollContentBackground(.hidden)` already in place (line 160) is required (it disables Form's default opaque background); preserve.
- `VoiceInk/Views/AudioTranscribeView.swift:24` — pane root. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`. The empty-state drop-target chrome at lines 56 + 426 (`Color(.windowBackgroundColor).opacity(0.4)` rounded fill) stays — it's a drop-zone affordance, not a pane bg.
- `VoiceInk/Views/Settings/AudioInputSettingsView.swift:14` — pane root. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`. Line 426 priority-list chip fill stays (chip-level).
- `VoiceInk/Views/Dictionary/DictionarySettingsView.swift:41` — pane root. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`.
- `VoiceInk/PowerMode/PowerModeView.swift:89` — pane root. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`.
- `VoiceInk/PowerMode/PowerModeView.swift:124` — heroHeader band. Drop `.background(Color(NSColor.windowBackgroundColor))` (flush with pane glass via inheritance).
- `VoiceInk/PowerMode/PowerModeView.swift:134` — emptyState wrapper. Drop `.background(Color(NSColor.controlBackgroundColor))` (inherits pane glass).
- `VoiceInk/Views/PermissionsView.swift:295` — ScrollView. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`.
- `VoiceInk/Views/Settings/SettingsView.swift:70` — pane root. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.adaptiveGlassBackground()`.
- `VoiceInk/Views/Components/SlidingPanel.swift:31` — primitive sliding-panel chrome. Replace `.background(Color(NSColor.windowBackgroundColor))` with `.adaptiveGlassBackground(intensity: .panel)`. Blast radius: every host using `slidingPanel(...)` (DictionarySettingsView, EnhancementSettingsView, ModelManagementView, PowerModeView). The `Divider()` overlay at line 32 stays — chrome separator distinct from panel-bg.
- `VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift:37` — root. Replace `.background(Color(NSColor.windowBackgroundColor))` with `.adaptiveGlassBackground(intensity: .panel)`.
- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift:44` — root. Replace `.background(Color(NSColor.windowBackgroundColor))` with `.adaptiveGlassBackground(intensity: .panel)`.
- `VoiceInk/Views/PromptEditorView.swift:78` — root. Replace `.background(Color(NSColor.windowBackgroundColor))` with `.adaptiveGlassBackground(intensity: .panel)`.
- `VoiceInk/Views/PromptEditorView.swift:115` — header band. Drop `.background(Color(NSColor.windowBackgroundColor))` (inherits panel glass via the root).
- `VoiceInk/Views/PromptEditorView.swift:214` — footer band. Drop same.
- `VoiceInk/Views/PromptEditorView.swift:288` — icon-picker grid item bg. Replace `.background(Color(NSColor.controlBackgroundColor))` with `.background(.ultraThinMaterial)` (chip-level, not pane-level — uses the existing W1 chip vocabulary instead of the new app-wide modifier). ~+0 LOC, -0 LOC.
- `VoiceInk/Views/PromptEditorView.swift:474` — same icon-picker host. Same chip-level swap.
- `VoiceInk/Views/PromptEditorView.swift:553` — selected-icon fill. The current `selectedIcon == icon ? Palette.accent.opacity(0.14) : Color(NSColor.controlBackgroundColor)` swap to `selectedIcon == icon ? Palette.accent.opacity(0.14) : Color.clear` so the unselected state inherits the icon-picker glass.
- `VoiceInk/PowerMode/PowerModeConfigView.swift:182` — header band. Drop `.background(Color(NSColor.windowBackgroundColor))` (inherits panel glass via SlidingPanel).
- `VoiceInk/PowerMode/PowerModeConfigView.swift:216` — footer band. Drop same.
- `VoiceInk/PowerMode/PowerModeConfigView.swift:235` — scrollBody. Drop `.background(Color(NSColor.controlBackgroundColor))` (inherits panel glass).
- `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift:50` — popover content bg. Replace `.background(Color.black)` with `GlassCard`-style backing. Specifically: wrap the existing `VStack` with a `RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial)` + `Palette.hairline` 1pt overlay + opt the popover into `.environment(\.colorScheme, .dark)` (already on line 51 — preserve). The popover is anchored to the recorder orb on the floating recorder window; behind-window blur via the existing recorder transparent panel takes care of wallpaper. ~+5 LOC, -1 LOC.
- `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` — append a new sub-section `§1.X Adaptive glass app-wide` documenting the new primitive + window-transparency contract. Cite this plan path (`docs/superpowers/plans/W8-adaptive-glass-app-wide.md`). ~+25 LOC. Spec extension only — does not contradict §1 or §6.4.

### Retired files (delete)

- *Optional retirement* — `VoiceInk/Views/ContentView.swift` lines 37-53 (`struct VisualEffectView`). Confirmed unused via grep. Coder runs the verify step (Task 3 Step 3.2) and deletes only if zero call sites. -17 LOC if retired.

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Views/Recorder/HaloMaterial.swift` — recorder material primitive. The `VisualEffectBlur` `NSViewRepresentable` here is **reused** by the new modifier (imported, not duplicated). Do not edit `HaloMaterial.swift`.
- `VoiceInk/Views/Common/GlassAppearance.swift` / `GlassAppearanceDetector.swift` — appearance vocabulary + detector. Reused as-is; do not edit.
- `VoiceInk/Views/Common/GlassChip.swift` / `GlassCard.swift` — primitives for cards inside panes. Untouched — they already render their own backdrop.
- `VoiceInk/Views/Common/Palette.swift` — token vocabulary. Untouched. (The new modifier hard-codes onyx/light tint values to the spec §2.3 ramp; not a Palette concern.)
- `VoiceInk/Views/Common/SettingsCard.swift` / `SettingsRow.swift` / `SettingsSectionHeader.swift` — primitives. Untouched. Their inner `GlassCard` already renders translucent over whatever the pane root provides.
- `VoiceInk/Views/MenuBarView.swift` — `.menuBarExtraStyle(.menu)` projects flat `Button`/`Toggle`/`Menu`/`Divider` items onto NSMenuItems. Container `.background(...)` does NOT render under `.menu` style (per the file's own doc-comment). **OUT OF SCOPE.**
- `VoiceInk/PowerMode/PowerModePopover.swift` — already on NSPopover vibrant chrome + `GlassCard(.light)` hero (P2.H / spec §3.12). The line 49 `Color.black.opacity(0.001)` is a hit-region marker, NOT a chrome bg — preserve.
- `VoiceInk/Views/Recorder/Constellation/*.swift` / `MorphingRecorderPanel.swift` / `NotchRecorderPanel.swift` / `MiniRecorderPanel.swift` — recorder cluster surfaces. Already adaptive glass. The notch/mini panels already set `backgroundColor = .clear` + `isOpaque = false` on their NSPanels — same flags now propagate to the main window.
- `VoiceInk/Notifications/AppNotificationView.swift` / `AnnouncementView.swift` — already use `VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)` for HUD glass. Different vocabulary (HUD-style, transient toasts) — out of W8 scope. The legacy `VisualEffectView` struct in `ContentView.swift` is a candidate for retirement (see Task 3 verify); these notification surfaces import it. If retired, those imports need to follow — Task 3 also confirms zero downstream importers OR leaves the struct in place.
- `VoiceInk/HistoryWindowController.swift` — separate NSWindow. Out of W8 main-app-shell scope; would need its own `configureWindow` flip for full parity. Flag as a follow-up risk in §Risks/unknowns below.
- `VoiceInk/Views/Dictionary/DictionaryQuickAddPanel.swift` — separate floating NSPanel for quick-add hotkey. Already uses `VisualEffectView(material: .popover, blendingMode: .behindWindow)` (line 180). Out of scope (already glass).
- `VoiceInk/Views/Dictionary/WordReplacementView.swift` — text-input `.textBackgroundColor` fills (lines 572, 606, 632). These are text-field chrome, not pane-level. Untouched — text input legibility is not negotiable.
- `VoiceInk/Views/AI Models/LanguageSelectionView.swift:152` — opens via sheet/popover within ModelManagementView. The pane-root inheritance via SlidingPanel's panel-glass should propagate; if visual smoke pass shows a seam, fold into a follow-up.
- `VoiceInk/Views/AI Models/AddCustomModelView.swift:53` — `Color.accentColor` button bg. Chip-level; out of scope.
- `VoiceInk/Views/Settings/EnhancementShortcutsView.swift:61` — `KeyChip` row chip fill (`Color(NSColor.controlBackgroundColor)`). System-adaptive chip token, exempted in W5. Untouched.
- `VoiceInk/Views/Common/CopyIconButton.swift:13` / `SaveIconButton.swift:21` — small icon button chrome. Chip-level; untouched.
- `VoiceInk/Views/Components/FillerWordsSettingsView.swift` — already W5-migrated to `.ultraThinMaterial` + `Palette.hairlineSoft`. Untouched.
- `VoiceInk/PowerMode/PowerModeActivePill.swift` / `PowerModeStripView.swift` — chip surfaces. Already glass via W7. Untouched.
- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` — W6 surface; W9 is its own packet (chip overflow). Untouched here.
- `VoiceInk/Models/CustomPrompt.swift:152-153` + `:315-316` — `LinearGradient` over `Color(NSColor.controlBackgroundColor).opacity(0.95)` for prompt-card preview backdrop. Inside a card preview that scrolls in a list; chip-level (not pane). Untouched.
- `VoiceInk/Views/Metrics/HelpAndResourcesSection.swift:41` — single resource-card fill (`Color(nsColor: .windowBackgroundColor)`). Chip-level; untouched.
- `VoiceInk/Views/Metrics/PerformanceAnalysisView.swift` / `PerformanceAnalysisPanelView.swift` — metrics dashboard sub-surfaces. Already W7-aware (hero-numeral preserves). Their internal `.controlBackgroundColor` fills (PerformanceAnalysisView:159, PerformanceAnalysisPanelView:20, etc.) are Charts-host chrome — Charts rendering against translucent bg is risky. **Untouched — hard-flag in Risks.**
- `VoiceInk/Views/Metrics/MetricsSetupView.swift` — onboarding empty-state hero. The `.background(Color(NSColor.textBackgroundColor))` on line 42 is a textfield bg; line 62 `.controlBackgroundColor` is the empty-state wrapper. Untouched in W8 — the user's feedback didn't flag onboarding, and the spec §5 explicitly defers onboarding ("First-launch impression is mismatched until follow-up. Acceptable.").
- `VoiceInk/Views/EnhancementSettingsView.swift:234` — `Palette.accent.opacity(0.25)` drop-target stroke. Already W5-migrated. Untouched.
- `VoiceInk/Views/AudioFileRow.swift` / `Components/PromptLivePreview.swift` / similar list-item rows — chip-level or row-level chrome. Untouched.
- `VoiceInk/Views/History/TranscriptionHistoryView.swift:133/321/392` — separate window (`HistoryWindowController`); see §Untouched HistoryWindow flag above.
- `VoiceInk/Views/Common/SettingsCard.swift` `#Preview` host backgrounds (lines 102, 110) — preview-only; untouched.
- `VoiceInk/Views/Common/SettingsRow.swift` / `KeyCapView.swift` / `MenuBarIconRenderer.swift` / `GlassSwitch.swift` / `GlassCard.swift` `#Preview` host backgrounds — preview-only; untouched. `Color(red: 0.06, ...)` and `Color(red: 0.93, ...)` literals are previews against the `Palette.onyxBackground` / a light-mode counterpart for preview canvases only.
- All test files (`VoiceInkTests/*.swift`) — W8 ships no new tests. Existing PaletteTests + FailureRegistryTests + VoiceInkUITests must still pass at integration build (Task 22).

---

## Migration policy (resolves ambiguity for each design point)

The following decisions are locked. The coder follows them mechanically; do not relitigate.

1. **Window transparency is the gating change.** Without `window.isOpaque = false` + `window.backgroundColor = .clear` in `WindowManager.configureWindow`, the SwiftUI `VisualEffectBlur(.behindWindow)` paints over an opaque window background and the wallpaper never reads. Therefore Task 2 (window flip) must land FIRST, before any pane root flips. If Task 2 is rolled back, every pane that flipped to `.adaptiveGlassBackground()` will render as translucent-on-system-bg only — degraded but not broken.

2. **Two intensities, locked alphas.** `intensity: .pane` (default) → onyx fill α 0.42 / light fill α 0.18 over `.fullScreenUI` blur. `intensity: .panel` → onyx α 0.52 / light α 0.26 (steps up the contrast for sliding-panel chrome). Do NOT introduce a third intensity in W8; if a future surface needs different tuning, it lives in a follow-up packet.

3. **High-Contrast / Reduce-Transparency branch ONCE.** The new modifier reads `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` and `accessibilityDisplayShouldIncreaseContrast` at the top of its body. If either is true, return an opaque palette token (control-bg for Reduce-Transparency, window-bg for High-Contrast — matching the existing `HaloMaterial.AdaptiveGlass.contrastedFill` contract from spec §6.4). Per-pane callers do NOT branch — the modifier owns it.

4. **Sub-pane flush bands get DROPPED, not migrated.** When a pane like `MetricsContent` paints its own sub-band `.background(Color(.windowBackgroundColor))` over the pane root, the band is now a redundant double-layer that hides the pane glass. Drop the band entirely. Inheritance from the pane root carries the glass. Affected sites: `MetricsContent:41, :141`, `PowerModeView:124, :134`, `InlineHistoryView:230`, `PromptEditorView:115, :214`, `PowerModeConfigView:182, :216, :235`. (Note: `InlineHistoryView:106` + `:350` and `ModelManagementView:95` are NOT flush bands — they are stepped-up panel chrome and DO need `.adaptiveGlassBackground(intensity: .panel)`. Per-site classification is in the Modified files list above; do not generalize.)

5. **Chip-level fills stay.** Any `Color(NSColor.controlBackgroundColor)` or `Color(NSColor.windowBackgroundColor)` used as a CHIP fill (chip-sized RoundedRectangle inside a card or row) is OUT of scope. Only pane-level + panel-level surfaces flip. Chip-level examples preserved: `CopyIconButton:13`, `SaveIconButton:21`, `EnhancementShortcutsView:61` (`KeyChip` row), `AudioInputSettingsView:426` (priority-list chip), `HelpAndResourcesSection:41`, `CustomPrompt.swift` gradient backdrops, `WordReplacementView` text-field chrome.

6. **`PromptEditorView`'s icon picker is a chip-LIST not a pane.** Lines 288 + 474 + 553 host the icon-picker grid. Each grid cell is a chip; the surrounding container uses pane-bg. Decision: swap chip cells from `controlBackgroundColor` to `.ultraThinMaterial` (chip-level W1 vocab) + clear unselected fill. This keeps the icon-picker's hover/select grammar intact while inheriting the pane's adaptive glass on the gap.

7. **Recorder `EnhancementPromptPopover` is the one off-shell glass site.** It's not a pane, not a sliding panel, not a chip — it's an NSPopover anchored to the recorder cluster orb. Wrapped in `.environment(\.colorScheme, .dark)` for white-on-onyx text. Switch from `Color.black` to a `RoundedRectangle.fill(.ultraThinMaterial)` + `Palette.hairline` overlay (W1 vocabulary, not the new modifier — popovers are too small to need the full `AdaptiveGlassBackground` machinery).

8. **NavigationSplitView default sidebar chrome stays.** Per Apple's docs + observed behavior, `.listStyle(.sidebar)` already renders with a system-vibrant translucent sidebar material on macOS. With the main window flipped to non-opaque, the sidebar gets a true behind-window blur for free. **Do not apply `.adaptiveGlassBackground()` to the sidebar List.** Verification step in Task 3 confirms reads cleanly; only edit if smoke pass shows a regression.

9. **`ContentView.swift`'s legacy `VisualEffectView` struct.** Per `grep -rn "VisualEffectView(" VoiceInk` (Task 3 Step 3.2), the only call sites are inside `AppNotificationView.swift:105` and `AnnouncementView.swift:79`. Therefore: **DO NOT delete the struct.** Revise the suggestion in `Modified files` above accordingly — mark for removal "if zero call sites" and verify the call-site count first. Coder reports: if 2 call sites (notifications use it), retain the struct in place; if 0, delete. Either is acceptable; the struct is small and the deletion is a cleanup, not a correctness fix.

10. **Spec extension at Task 22.** New sub-section `§1.X` extends §1 (Material/Tokens) without mutating the locked recorder vocabulary. Documents: `AdaptiveGlassBackground` modifier signature, two intensities + their alpha ramp, window-transparency contract, accessibility branch decision tree. Cross-references plan + handoff. Filing under the spec keeps the source-of-truth honest.

11. **No emoji in code, no PR-reference comments.** All inline doc-comments cite spec §1 / §6.1 / §6.4 + this plan path; do not reference PR numbers or emojis. The pre-existing `🦾` in `MLXProvider.swift` (W6 instrumentation) is the documented exception — unchanged here.

12. **`HistoryWindowController` flagged but NOT in scope.** It's a separate NSWindow opened from the menu bar dropdown. To get parity, its `configureWindow` would need the same flip as `WindowManager`. **Flagged in Risks/unknowns #4** below. If the user wants History-window glass too, that's a follow-up packet.

13. **Charts rendering on translucent bg risk.** `PerformanceAnalysisView` / `PerformanceAnalysisPanelView` host SwiftUI Charts. Charts have their own opaque chart-background by default; if the parent pane goes glass, Charts may render with white-tile backgrounds against translucent surroundings. **Decision for W8: leave Performance Analysis sub-views opaque (their `.controlBackgroundColor` and `.windowBackgroundColor` fills stay)**, since they live INSIDE `MetricsContent` and the Charts host needs a stable bg for legibility. Listed in §Untouched. If the user objects post-merge, a follow-up packet adds explicit Chart bg styling + flips them too.

14. **Form-grouped scroll content.** `EnhancementSettingsView` (Form { Section { } }) uses `.scrollContentBackground(.hidden)` (line 160) — that's the one-line hack that lets the Form's grouped section bg disappear so the parent's `.background(...)` shows through. **Do not remove `.scrollContentBackground(.hidden)`.** It's load-bearing for W8 to read correctly.

15. **`SettingsView`'s pane is a `ScrollView { LazyVStack }` of `SettingsCard` islands** (post-W5). The cards already glass over a solid pane bg — flipping the pane bg to glass means cards-on-glass-on-wallpaper. Visually: cards float more. Spec §1 hairline + inner highlight on cards already provide enough silhouette; no card re-tuning needed unless smoke pass disagrees.

---

## Tasks

### Task 0: Audit + sweep references

**Files:** none (read-only).

- [ ] **Step 0.1: Confirm the 27-site surface inventory**

Run:

```bash
grep -rn "Color(NSColor\.\(control\|window\)BackgroundColor\|Color(\\.\(control\|window\)BackgroundColor" \
  VoiceInk --include="*.swift" | grep -v "VoiceInkTests\|#Preview"
```

Expected: ~30+ matches. Reconcile against the Modified files list. Sites in scope are those classified as Tier B/C/D/E in the architecture map. Sites flagged as chip-level / preview-only / Charts-host / text-input / out-of-scope (per the Untouched list) must NOT be modified.

If a NEW site appears (a file landed since plan-time), reconcile with the lead before proceeding.

- [ ] **Step 0.2: Confirm `MenuBarView` is system-NSMenu and not skinnable**

```bash
grep -n "menuBarExtraStyle" VoiceInk/VoiceInk.swift
```

Expected: line ~391, `.menuBarExtraStyle(.menu)`. If the value is `.window` (was the legacy glass popover that got reverted), W8's MenuBar-out-of-scope claim is wrong — escalate to lead before proceeding.

- [ ] **Step 0.3: Confirm `VisualEffectView` struct call sites in ContentView**

```bash
grep -rn "VisualEffectView(" VoiceInk --include="*.swift" | grep -v "ContentView.swift\|VisualEffectBlur"
```

Expected: 2 matches in `AppNotificationView.swift:105` and `AnnouncementView.swift:79`. If exactly those 2, the struct is in use — DO NOT delete (per Migration policy #9). If 0, delete. Coder reports the count.

- [ ] **Step 0.4: Confirm window-transparency precedent**

```bash
grep -rn "isOpaque = false\|backgroundColor = \.clear\|backgroundColor = NSColor\.clear" VoiceInk --include="*.swift"
```

Expected: matches in `NotchRecorderPanel.swift:29 + :115`, `MiniRecorderPanel.swift:27`, `DictionaryQuickAddPanel.swift:78`, `WindowManager.swift:32` (currently `.windowBackgroundColor`, will flip in Task 2). Confirms the recorder + quick-add panels already do exactly the flip W8 applies to the main window.

- [ ] **Step 0.5: Confirm `GlassAppearanceDetector` is wired**

```bash
grep -rn "GlassAppearanceDetector\.shared" VoiceInk --include="*.swift" | head
```

Expected: matches in `HaloMaterial.swift`, `GlassCard.swift`, `ConstellationContainer.swift`, possibly others. Confirms the detector singleton is the right shared source for the new modifier.

- [ ] **Step 0.6: Confirm `accessibilityDisplay*` API references**

```bash
grep -rn "accessibilityDisplayShouldReduceTransparency\|accessibilityDisplayShouldIncreaseContrast" VoiceInk --include="*.swift"
```

Expected: 4 matches inside `HaloMaterial.swift` for High-Contrast (lines 120-123 + 276 + 284). No existing Reduce-Transparency reference in the codebase — W8 introduces the first one. Confirms there's no cross-feature ownership concern; the new modifier owns Reduce-Transparency handling for the app shell.

---

### Task 1: New primitive — `AdaptiveGlassBackground.swift`

**Files:**
- Create: `VoiceInk/Views/Common/AdaptiveGlassBackground.swift`

- [ ] **Step 1.1: Write the new modifier file**

Create the file with the full content below. Imports `SwiftUI` + `AppKit`. References `GlassAppearanceDetector` and `VisualEffectBlur` (both pre-existing). Comments cite spec §1 + §2.3 + §6.1 + §6.4 + this plan.

```swift
import SwiftUI
import AppKit

// MARK: - AdaptiveGlassBackground (W8 — adaptive glass app-wide)
//
// View modifier that paints an adaptive-glass background on a full-bleed
// surface (pane root / sliding-panel root / popover host). Mirrors the
// recorder's HaloMaterial vocabulary (spec §2.3) — onyx-vs-light variant
// driven by `GlassAppearanceDetector.shared.current`. Diverges from
// HaloMaterial only in:
//   • shape: full-bleed Rectangle, not a clipped RoundedRectangle.
//   • inner stroke / sheen / drop-shadow: omitted — too noisy at pane scale.
//   • intensity: a 2-step ramp (.pane / .panel) for layered surfaces
//     (panel sits over pane → slightly higher fill alpha to read as
//     stepped-up).
//
// Reuses `VisualEffectBlur` from `Recorder/HaloMaterial.swift` to avoid
// duplicating the NSViewRepresentable wrapper.
//
// Accessibility branches once at the top of the body:
//   • Reduce-Transparency on  → opaque Color(NSColor.controlBackgroundColor)
//                                (system-adaptive, matches preference)
//   • Increase-Contrast on    → opaque Color(NSColor.windowBackgroundColor)
//                                (matches HaloMaterial.AdaptiveGlass.contrastedFill
//                                 contract, spec §6.4)
//   • Else (default)          → VisualEffectBlur(.fullScreenUI / .behindWindow)
//                                + tint overlay keyed to detector.current.
//
// Window-transparency contract:
//   The host NSWindow MUST have `isOpaque = false` + `backgroundColor = .clear`
//   for `.behindWindow` blending to reveal wallpaper. WindowManager.configureWindow
//   sets these flags (W8 plan Task 2). Without them, the modifier degrades to
//   a translucent overlay over the window's own background — still readable,
//   but the wallpaper-luminance adaptation reads as system-appearance only.
//
// Spec refs:
//   docs/superpowers/specs/2026-04-28-aesthetic-redesign.md §1, §2.3, §6.1, §6.4
//   docs/superpowers/plans/W8-adaptive-glass-app-wide.md

enum AdaptiveGlassIntensity {
    /// Detail-pane root — the gap area behind cards. Lower fill alpha.
    case pane
    /// Sliding-panel chrome — the stepped-up surface above a pane.
    /// Higher fill alpha so the panel reads as a distinct layer.
    case panel
}

struct AdaptiveGlassBackground: ViewModifier {
    var intensity: AdaptiveGlassIntensity = .pane

    @ObservedObject private var detector = GlassAppearanceDetector.shared

    func body(content: Content) -> some View {
        content.background(backdrop)
    }

    @ViewBuilder
    private var backdrop: some View {
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

        if reduceTransparency {
            Color(NSColor.controlBackgroundColor)
        } else if highContrast {
            Color(NSColor.windowBackgroundColor)
        } else {
            ZStack {
                VisualEffectBlur(
                    material: .fullScreenUI,
                    blendingMode: .behindWindow,
                    appearanceName: detector.current == .light ? .aqua : .darkAqua
                )
                tint
            }
        }
    }

    private var tint: Color {
        switch (detector.current, intensity) {
        case (.onyx,  .pane):  return Color.black.opacity(0.42)
        case (.onyx,  .panel): return Color.black.opacity(0.52)
        case (.light, .pane):  return Color.white.opacity(0.18)
        case (.light, .panel): return Color.white.opacity(0.26)
        }
    }
}

extension View {
    /// Paints an adaptive-glass backdrop suitable for a detail-pane root or
    /// a sliding-panel chrome. Branches on Reduce-Transparency / High-Contrast
    /// per spec §6.4. See `AdaptiveGlassBackground` for the contract.
    func adaptiveGlassBackground(intensity: AdaptiveGlassIntensity = .pane) -> some View {
        modifier(AdaptiveGlassBackground(intensity: intensity))
    }
}

// MARK: - Previews

#if DEBUG
private struct AdaptiveGlassBackgroundPreviewBody: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Detail pane root").font(.system(size: 13, weight: .semibold))
            GlassCard(cornerRadius: 14, padding: 16) {
                Text("Card on glass").frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 320)
        }
        .padding(40)
    }
}

#Preview("Onyx pane") {
    AdaptiveGlassBackgroundPreviewBody()
        .adaptiveGlassBackground()
        .frame(width: 480, height: 360)
}

#Preview("Onyx panel") {
    AdaptiveGlassBackgroundPreviewBody()
        .adaptiveGlassBackground(intensity: .panel)
        .frame(width: 480, height: 360)
}
#endif
```

Verify the file lands under `VoiceInk/Views/Common/`. Xcode 16's `PBXFileSystemSynchronizedRootGroup` auto-includes new files in `VoiceInk/`; no project file edit needed.

- [ ] **Step 1.2: SourceKit syntax check**

Open the file in Xcode. Confirm no red squiggle (the file references `GlassAppearanceDetector` from `GlassAppearance.swift`, `VisualEffectBlur` from `Recorder/HaloMaterial.swift`, and `GlassCard` from `Common/GlassCard.swift` — all in the same module, no imports needed).

If Xcode is not in use, run a Swift syntax check via the bundled tools:

```bash
xcrun swiftc -parse VoiceInk/Views/Common/AdaptiveGlassBackground.swift -sdk $(xcrun --show-sdk-path) -target arm64-apple-macos14.0 2>&1 | head -20
```

Expected: silent (no syntax errors). Linker errors about missing types are fine — `parse` doesn't link.

- [ ] **Step 1.3: Diff inspection**

```bash
git --no-pager status VoiceInk/Views/Common/AdaptiveGlassBackground.swift
git --no-pager diff --stat VoiceInk/Views/Common/AdaptiveGlassBackground.swift
```

Expected: file shown as untracked (new file) with ~95 LOC.

---

### Task 2: Window transparency in `WindowManager.swift`

**Files:**
- Modify: `VoiceInk/WindowManager.swift`

- [ ] **Step 2.1: Flip `isOpaque` + `backgroundColor` in `configureWindow`**

Current (lines 28-37):

```swift
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.title = "VoiceInk"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = true
```

Replace with:

```swift
        let requiredStyleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.styleMask.formUnion(requiredStyleMask)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // W8 — adaptive glass app-wide. Non-opaque + clear bg so the SwiftUI
        // root's `.adaptiveGlassBackground()` (NSVisualEffectView .behindWindow)
        // can reveal wallpaper through the gap behind cards. Spec §1 / §6.1 /
        // docs/superpowers/plans/W8-adaptive-glass-app-wide.md.
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.title = "VoiceInk"
        window.collectionBehavior = [.fullScreenPrimary]
        window.level = .normal
        window.isOpaque = false
```

Two value flips + a 4-line doc-comment cite. No structural change.

- [ ] **Step 2.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/WindowManager.swift
```

Expected: 2 value-line diffs + 4 added doc-comment lines. No other changes. The `windowDidBecomeKey` / `windowWillClose` delegate methods stay untouched.

---

### Task 3: ContentView verification + (optional) `VisualEffectView` retire

**Files:**
- Modify: `VoiceInk/Views/ContentView.swift`

- [ ] **Step 3.1: Add backstop `.adaptiveGlassBackground()` at NavigationSplitView root**

Current (line 122):

```swift
        .navigationSplitViewStyle(.balanced)
        .frame(width: 950)
```

Replace with:

```swift
        .navigationSplitViewStyle(.balanced)
        // W8 backstop — every detail pane applies its own
        // `.adaptiveGlassBackground()`, but if a future pane forgets, this
        // ensures the gap area still glasses correctly. The sidebar's own
        // `.listStyle(.sidebar)` chrome takes precedence on its column;
        // detail-pane backgrounds cover the detail column. Plan W8.
        .adaptiveGlassBackground()
        .frame(width: 950)
```

The sidebar chrome (the .sidebar list style on the leading column) renders its own translucent vibrant material on top of this backstop — it should NOT be visually affected. Verification step at Task 23 smoke-pass.

- [ ] **Step 3.2: Confirm `VisualEffectView` struct call-site count**

Run:

```bash
grep -rn "VisualEffectView(" VoiceInk --include="*.swift" | grep -v "ContentView\.swift" | grep -v "VisualEffectBlur"
```

Expected: 2 matches — `AppNotificationView.swift:105` and `AnnouncementView.swift:79`.

**Decision branch:**
- If exactly 2 matches: **DO NOT delete the `VisualEffectView` struct.** It's load-bearing for the notification surfaces. Leave lines 37-53 of `ContentView.swift` as-is.
- If 0 matches: delete lines 37-53 (the `VisualEffectView` struct definition). Both notification files would be using the new `VisualEffectBlur` from `HaloMaterial.swift` instead — confirm via a follow-up grep.
- If >2 matches: a new caller landed since plan-time. Reconcile with lead before proceeding.

- [ ] **Step 3.3: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/ContentView.swift
```

Expected (assuming 2 call sites preserved): single one-line addition (`.adaptiveGlassBackground()`) + the doc-comment block. No deletions.

---

### Task 4: Migrate `MetricsView` + drop `MetricsContent` flush bands

**Files:**
- Modify: `VoiceInk/Views/MetricsView.swift`
- Modify: `VoiceInk/Views/Metrics/MetricsContent.swift`

- [ ] **Step 4.1: Replace `MetricsView` pane root**

Current (line 12):

```swift
            .background(Color(.controlBackgroundColor))
```

Replace with:

```swift
            .adaptiveGlassBackground()
```

- [ ] **Step 4.2: Drop `MetricsContent.swift` ScrollView flush band**

Current (line 41):

```swift
                    }
                    .background(Color(.windowBackgroundColor))
                }
```

Replace with:

```swift
                    }
                }
```

(Drops the `.background(...)` modifier line entirely. The pane glass now shows through the GeometryReader+ScrollView wrapper.)

- [ ] **Step 4.3: Drop `MetricsContent.swift` empty-state flush band**

Current (line 141):

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
```

Replace with:

```swift
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

- [ ] **Step 4.4: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/MetricsView.swift VoiceInk/Views/Metrics/MetricsContent.swift
```

Expected: 1 line change in `MetricsView.swift`, 2 line removals in `MetricsContent.swift`.

**Note:** `PerformanceAnalysisView.swift:159` and `PerformanceAnalysisPanelView.swift:20` (Charts hosts) are intentionally NOT migrated — see Migration policy #13. The Charts chart-host needs an opaque bg.

---

### Task 5: Migrate `ModelManagementView` (root + sliding-panel header)

**Files:**
- Modify: `VoiceInk/Views/AI Models/ModelManagementView.swift`

- [ ] **Step 5.1: Replace pane root (line 57)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

- [ ] **Step 5.2: Replace settings-panel header band (line 95)**

Current:

```swift
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
```

Replace with:

```swift
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .adaptiveGlassBackground(intensity: .panel)
            .overlay(
```

- [ ] **Step 5.3: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/AI\ Models/ModelManagementView.swift
```

Expected: 2 line-swaps.

---

### Task 6: Migrate `InlineHistoryView` (4 sites)

**Files:**
- Modify: `VoiceInk/Views/History/InlineHistoryView.swift`

- [ ] **Step 6.1: Replace pane root (line 88)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

- [ ] **Step 6.2: Replace overlay panel content bg (line 106)**

```swift
                    .background(Color(NSColor.windowBackgroundColor))
```

→

```swift
                    .adaptiveGlassBackground(intensity: .panel)
```

- [ ] **Step 6.3: Drop empty-state overlay flush band (line 230)**

Current:

```swift
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()
```

Replace with:

```swift
            Color.clear
                .ignoresSafeArea()
```

(The empty-state surface inherits the pane glass via `InlineHistoryView`'s root.)

- [ ] **Step 6.4: Replace selection-bar wrapper bg (line 350)**

```swift
            .background(Color(NSColor.windowBackgroundColor))
```

→

```swift
            .adaptiveGlassBackground(intensity: .panel)
```

(Selection bar reads as a stepped-up overlay above the pane glass.)

- [ ] **Step 6.5: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/History/InlineHistoryView.swift
```

Expected: 4 line swaps. The line 343 `Color.secondary.opacity(0.1)` chip stays (chip-level token).

---

### Task 7: Migrate `EnhancementSettingsView`

**Files:**
- Modify: `VoiceInk/Views/EnhancementSettingsView.swift`

- [ ] **Step 7.1: Replace Form pane root (line 161)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

The pre-existing `.scrollContentBackground(.hidden)` (line 160) is the load-bearing line that lets Form's grouped section bg drop out — verify it's still there. Per Migration policy #14: do NOT remove.

- [ ] **Step 7.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/EnhancementSettingsView.swift
```

Expected: 1 line swap.

---

### Task 8: Migrate `AudioTranscribeView`

**Files:**
- Modify: `VoiceInk/Views/AudioTranscribeView.swift`

- [ ] **Step 8.1: Replace pane root (line 24)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

The empty-state drop-target chrome at line 56 + line 426 stays — drop-zone affordance, not a pane bg.

- [ ] **Step 8.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/AudioTranscribeView.swift
```

Expected: 1 line swap.

---

### Task 9: Migrate `AudioInputSettingsView`

**Files:**
- Modify: `VoiceInk/Views/Settings/AudioInputSettingsView.swift`

- [ ] **Step 9.1: Replace pane root (line 14)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

The line 426 priority-list chip fill stays (chip-level).

- [ ] **Step 9.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Settings/AudioInputSettingsView.swift
```

Expected: 1 line swap.

---

### Task 10: Migrate `DictionarySettingsView`

**Files:**
- Modify: `VoiceInk/Views/Dictionary/DictionarySettingsView.swift`

- [ ] **Step 10.1: Replace pane root (line 41)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

- [ ] **Step 10.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Dictionary/DictionarySettingsView.swift
```

Expected: 1 line swap.

---

### Task 11: Migrate `PowerModeView` (3 sites)

**Files:**
- Modify: `VoiceInk/PowerMode/PowerModeView.swift`

- [ ] **Step 11.1: Replace pane root (line 89)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

- [ ] **Step 11.2: Drop heroHeader flush band (line 124)**

Current:

```swift
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
```

Replace with:

```swift
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
    }
```

(Drops the hero header's solid `windowBackgroundColor` band — inherits the pane glass via the root.)

- [ ] **Step 11.3: Drop emptyState wrapper flush band (line 134)**

Current:

```swift
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
```

Replace with:

```swift
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
```

- [ ] **Step 11.4: Diff inspection**

```bash
git --no-pager diff VoiceInk/PowerMode/PowerModeView.swift
```

Expected: 1 line swap + 2 line removals.

---

### Task 12: Migrate `PermissionsView`

**Files:**
- Modify: `VoiceInk/Views/PermissionsView.swift`

- [ ] **Step 12.1: Replace ScrollView bg (line 295)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

- [ ] **Step 12.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/PermissionsView.swift
```

Expected: 1 line swap.

---

### Task 13: Migrate `SettingsView`

**Files:**
- Modify: `VoiceInk/Views/Settings/SettingsView.swift`

- [ ] **Step 13.1: Replace pane root (line 70)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground()
```

- [ ] **Step 13.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Settings/SettingsView.swift
```

Expected: 1 line swap.

---

### Task 14: Migrate `SlidingPanel` primitive

**Files:**
- Modify: `VoiceInk/Views/Components/SlidingPanel.swift`

- [ ] **Step 14.1: Replace primitive panel chrome (line 31)**

Current:

```swift
                    panelContent()
                        .frame(width: panelWidth)
                        .frame(maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                        .overlay(Divider(), alignment: .leading)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: -2, y: 0)
```

Replace with:

```swift
                    panelContent()
                        .frame(width: panelWidth)
                        .frame(maxHeight: .infinity)
                        .adaptiveGlassBackground(intensity: .panel)
                        .overlay(Divider(), alignment: .leading)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: -2, y: 0)
```

Single-line swap. Blast radius: every host using `slidingPanel(...)`. The Divider overlay + shadow stay untouched (chrome separator + drop-shadow are independent of bg).

- [ ] **Step 14.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Components/SlidingPanel.swift
```

Expected: 1 line swap.

---

### Task 15: Migrate sliding-panel content surfaces

**Files:**
- Modify: `VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift`
- Modify: `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`

- [ ] **Step 15.1: `DictionarySettingsPanel` root (line 37)**

```swift
            .background(Color(NSColor.windowBackgroundColor))
```

→

```swift
            .adaptiveGlassBackground(intensity: .panel)
```

- [ ] **Step 15.2: `EnhancementSettingsPanel` root (line 44)**

```swift
            .background(Color(NSColor.windowBackgroundColor))
```

→

```swift
            .adaptiveGlassBackground(intensity: .panel)
```

- [ ] **Step 15.3: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift VoiceInk/Views/Components/EnhancementSettingsPanel.swift
```

Expected: 2 line swaps total.

---

### Task 16: Migrate `PromptEditorView` (root + bands + icon-picker)

**Files:**
- Modify: `VoiceInk/Views/PromptEditorView.swift`

- [ ] **Step 16.1: Replace root (line 78)**

```swift
        .background(Color(NSColor.windowBackgroundColor))
```

→

```swift
        .adaptiveGlassBackground(intensity: .panel)
```

- [ ] **Step 16.2: Drop header band (line 115)**

Current:

```swift
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
```

Replace with:

```swift
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(
            Rectangle()
```

(Drops the redundant header band — inherits panel glass.)

- [ ] **Step 16.3: Drop footer band (line 214)**

Apply the same pattern to the footerBar (line 214 vicinity — the `.background(Color(NSColor.windowBackgroundColor))` inside the footerBar). Drop it.

- [ ] **Step 16.4: Switch icon-picker grid item bg to `.ultraThinMaterial` (line 288 vicinity)**

Current (the icon-picker grid cells use `.background(Color(NSColor.controlBackgroundColor))` for their hover state):

```swift
                            .background(Color(NSColor.controlBackgroundColor))
```

Replace with:

```swift
                            .background(.ultraThinMaterial)
```

Apply the same swap at line 474 vicinity (the wider icon-picker grid host) and adjust line 553's selected-state branch from:

```swift
                                .fill(selectedIcon == icon ? Palette.accent.opacity(0.14) : Color(NSColor.controlBackgroundColor))
```

to:

```swift
                                .fill(selectedIcon == icon ? Palette.accent.opacity(0.14) : Color.clear)
```

(Unselected state is now `Color.clear` so the underlying ultra-thin material shows through; selected stays Palette.accent.)

- [ ] **Step 16.5: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/PromptEditorView.swift
```

Expected: 1 root swap + 2 band drops + 3 icon-picker swaps. Reconcile against the actual line numbers in the live file (they may have shifted slightly).

---

### Task 17: Migrate `PowerModeConfigView` sheet

**Files:**
- Modify: `VoiceInk/PowerMode/PowerModeConfigView.swift`

- [ ] **Step 17.1: Drop header band (line 182)**

Current:

```swift
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider().opacity(0.5), alignment: .bottom)
```

Replace with:

```swift
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Divider().opacity(0.5), alignment: .bottom)
```

- [ ] **Step 17.2: Drop footer band (line 216)**

Current:

```swift
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider().opacity(0.5), alignment: .top)
```

Replace with:

```swift
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .overlay(Divider().opacity(0.5), alignment: .top)
```

- [ ] **Step 17.3: Drop scrollBody bg (line 235)**

```swift
        .background(Color(NSColor.controlBackgroundColor))
```

→

(Delete the line entirely. The scrollBody inherits panel glass via the SlidingPanel root.)

- [ ] **Step 17.4: Investigate line 352 (icon-picker fill)**

Line 352 hosts a grid item fill `Color(NSColor.controlBackgroundColor)`:

```swift
                            .fill(Color(NSColor.controlBackgroundColor))
```

Decision: same as `PromptEditorView` icon-picker. Replace with:

```swift
                            .fill(.ultraThinMaterial)
```

Coder verifies the surrounding context is the emoji/icon picker grid before swapping. If it's a different surface (e.g. a card chrome), preserve.

- [ ] **Step 17.5: Diff inspection**

```bash
git --no-pager diff VoiceInk/PowerMode/PowerModeConfigView.swift
```

Expected: 3 line removals + 1 line swap.

---

### Task 18: Migrate `EnhancementPromptPopover` (recorder popover)

**Files:**
- Modify: `VoiceInk/Views/Recorder/EnhancementPromptPopover.swift`

- [ ] **Step 18.1: Swap popover root bg (line 50)**

Current:

```swift
        .frame(width: 200)
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
```

Replace with:

```swift
        .frame(width: 200)
        .frame(maxHeight: 340)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 1)
                )
        )
        .environment(\.colorScheme, .dark)
```

The W1 chip vocabulary applied at popover scale. Keeps the dark colorScheme so existing white-on-onyx text reads correctly.

- [ ] **Step 18.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Recorder/EnhancementPromptPopover.swift
```

Expected: 1 line swap → 8-line glass-backing block.

---

### Task 19: Spec extension — append `§1.X Adaptive glass app-wide`

**Files:**
- Modify: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md`

- [ ] **Step 19.1: Append a new sub-section after the existing §1**

Locate the end of §1 (after the "Type:" / "Motion:" lines). Append a new sub-section:

```markdown
### 1.X Adaptive glass app-wide (W8 extension, 2026-04-29)

The recorder cluster's glass vocabulary (HaloMaterial onyx/light + GlassAppearanceDetector wallpaper-luminance adaptation) propagates to the main-window app shell. Specifically:

**Window contract.** The main NSWindow runs non-opaque + clear bg (set in `WindowManager.configureWindow`). This permits NSVisualEffectView `.behindWindow` blending to reveal wallpaper through the gap area behind cards.

**New primitive: `AdaptiveGlassBackground` view modifier.** Located at `VoiceInk/Views/Common/AdaptiveGlassBackground.swift`. Two intensities:

| Intensity | Use | Onyx tint α | Light tint α |
|---|---|---:|---:|
| `.pane`  | Detail-pane root (gap behind cards)         | 0.42 | 0.18 |
| `.panel` | Sliding-panel chrome (stepped-up over pane) | 0.52 | 0.26 |

Material: `.fullScreenUI` over `.behindWindow` blending. Appearance: `GlassAppearanceDetector.shared.current → .aqua / .darkAqua`. Reuses recorder's `VisualEffectBlur` `NSViewRepresentable`.

**Accessibility branches.** Per §6.4 contract:
- `accessibilityDisplayShouldReduceTransparency` → opaque `Color(NSColor.controlBackgroundColor)`. NSVisualEffectView is suppressed.
- `accessibilityDisplayShouldIncreaseContrast` → opaque `Color(NSColor.windowBackgroundColor)`. Matches the pre-existing `HaloMaterial.AdaptiveGlass.contrastedFill` contract.

**Surface inventory (W8 packet — 27 sites).**
- Detail-pane roots (10): MetricsView, ModelManagementView, InlineHistoryView, EnhancementSettingsView, AudioTranscribeView, AudioInputSettingsView, DictionarySettingsView, PowerModeView, PermissionsView, SettingsView.
- Sliding-panel chrome (10): SlidingPanel primitive, DictionarySettingsPanel, EnhancementSettingsPanel, PromptEditorView root + bands + icon-picker, PowerModeConfigView header/footer/body, ModelManagementView settings-panel header.
- Recorder popover (1): EnhancementPromptPopover.
- Sub-pane flush bands dropped (5): MetricsContent, PowerModeView heroHeader/emptyState, InlineHistoryView empty-state, PromptEditorView header/footer.
- Window flag (1): WindowManager.configureWindow flips isOpaque + backgroundColor.

**Out-of-scope surfaces (W8 explicit non-targets).**
- `MenuBarView` (system NSMenu via `.menuBarExtraStyle(.menu)` — not skinnable).
- `HistoryWindowController` (separate NSWindow — needs its own configureWindow flip; tracked as W8 follow-up).
- `PerformanceAnalysisView` / `PerformanceAnalysisPanelView` (Charts hosts — opaque bg required for chart legibility).
- Recorder cluster panels (already adaptive via HaloMaterial).
- Notification panels (`AppNotificationView` / `AnnouncementView` — already use HUD glass).

**Plan reference:** `docs/superpowers/plans/W8-adaptive-glass-app-wide.md`.
```

- [ ] **Step 19.2: Diff inspection**

```bash
git --no-pager diff docs/superpowers/specs/2026-04-28-aesthetic-redesign.md
```

Expected: ~30 added lines under §1. No mutations to existing §1 / §2 / §6 content.

---

### Task 20: Audit sweep — confirm no missed solid-bg surfaces

**Files:** none (read-only).

- [ ] **Step 20.1: Re-run the surface-inventory grep**

```bash
grep -rn "Color(NSColor\.\(control\|window\)BackgroundColor\|Color(\\.\(control\|window\)BackgroundColor" \
  VoiceInk --include="*.swift" | grep -v "VoiceInkTests\|#Preview"
```

Compare against Task 0 Step 0.1 baseline. Expected delta: every Tier B / C / D / E site listed in Modified files is gone (replaced or removed). Sites that remain:

- Chip-level / row-level / drop-target / text-field / Charts-host / preview-only / out-of-scope per Untouched list.

If any Tier B/C/D site STILL reads as a solid-bg, escalate before marking the audit clean.

- [ ] **Step 20.2: Confirm `VisualEffectBlur` is the only NSVisualEffectView wrapper used app-wide**

```bash
grep -rn "NSVisualEffectView\|VisualEffectBlur\|VisualEffectView" VoiceInk --include="*.swift" | head -30
```

Expected: matches inside `Recorder/HaloMaterial.swift` (`VisualEffectBlur` definition + uses), `Common/AdaptiveGlassBackground.swift` (W8 new — uses `VisualEffectBlur`), `ContentView.swift` (legacy `VisualEffectView` struct + uses inside `Notifications/AppNotificationView.swift` + `Notifications/AnnouncementView.swift`). No other wrappers should exist.

---

### Task 21: Risks/unknowns final scrub

**Files:** none (read-only).

- [ ] **Step 21.1: Confirm Reduce-Transparency / High-Contrast simulator is available**

The visual smoke pass at Task 23 will toggle these system prefs. Pre-flight: confirm the user's machine settings UI has both toggles ("System Settings → Accessibility → Display → Reduce Transparency / Increase Contrast"). If the user wants pre-merge visual evidence, screenshots before + after with each toggle on/off cover the §6.4 contract.

- [ ] **Step 21.2: Confirm wallpaper choices for smoke pass**

Coder + reviewer should agree on a wallpaper pair for the smoke pass:
- **Bright wallpaper** (luminance > 0.6) → forces detector to `.light`. The detail-pane glass should read with white tint α 0.18 + light NSAppearance.
- **Dark wallpaper** (luminance < 0.6) → detector falls back to system-aqua/darkAqua. The detail-pane glass should read with black tint α 0.42.
- **Toggle between in-session** to confirm `GlassAppearanceDetector.refresh()` correctly re-publishes the new appearance on `NSWorkspace.activeSpaceDidChangeNotification`.

---

### Task 22: Integration build

**Files:** none (build only).

- [ ] **Step 22.1: Run a full `make local`**

```bash
make local
```

Expected: `** BUILD SUCCEEDED **`. Build time ~3 min cold. App lands at `~/Downloads/VoiceInk.app`.

If the build fails:
- Compile errors in `AdaptiveGlassBackground.swift` → recheck Task 1 Step 1.2 (SourceKit syntax check). Most likely missing `import AppKit` or a typo in `VisualEffectBlur` parameter names.
- Compile errors in any pane file → most likely the `.adaptiveGlassBackground()` call is in the wrong place (e.g., applied to a non-`View` type). Reconcile against the line numbers in Modified files.

- [ ] **Step 22.2: Existing tests stay green**

If the `xcodebuild test` env is unblocked (per the recurring W5/W6/W7 macros-trust + signing issue): run the existing tests and confirm `PaletteTests` (2/2), `FailureRegistryTests` (5/5), `VoiceInkUITests` (4/4) still pass. W8 ships no new tests.

If env still blocked (per the post-W7 handoff "carried over from W5 + W6 + W7 cycles" note): document the env-blocked status and defer test verification to a later session. Do NOT block W8 merge on test env unblock.

---

### Task 23: Visual smoke pass + final report

**Files:** none (visual verification only).

- [ ] **Step 23.1: Launch the app and verify the main window**

```bash
open -a "VoiceInk" --new
```

Expected:
- Sidebar (left column) renders with system `.sidebar` translucent vibrancy. Wallpaper should bleed through behind row text.
- Detail pane (right column) renders with adaptive glass per detector. Switch wallpaper to bright → detail pane shifts to `.light` tint. Switch to dark → falls back to onyx tint.
- No edge-shadow artifacts during window resize.
- No black or system-fill seam at the titlebar / pane gap.

- [ ] **Step 23.2: Smoke each detail pane**

Click through the sidebar items and verify each pane root reads as adaptive glass:

| Pane | Verify |
|---|---|
| Dashboard (MetricsView) | Hero text reads cleanly; Charts in PerformanceAnalysisView still opaque (intentional) |
| AI Models (ModelManagementView) | Provider cards float over glass; settings panel slides in with stepped-up panel glass |
| History (InlineHistoryView) | Top-bar + selection-bar + transcript rows readable; panel slides in with stepped-up glass |
| Settings | All `SettingsCard` islands float over glass; `.scrollContentBackground(.hidden)` works correctly |
| Enhancement (EnhancementSettingsView) | Form sections render against glass; sliding panel stepped-up |
| Power Mode (PowerModeView) | Hero header + strip view readable; empty-state GlassCard reads cleanly; sheet panel stepped-up |
| Permissions (PermissionsView) | PermissionCard glass reads against glass-on-glass — watch for low-contrast |
| Audio Input (AudioInputSettingsView) | Device cards readable; priority list chips legible |
| Dictionary (DictionarySettingsView) | Word/replacement section content readable; sliding settings panel stepped-up |
| Transcribe Audio (AudioTranscribeView) | Empty-state drop target visible against glass; queue rows readable when populated |

For any pane that reads low-contrast (cards-on-glass-on-wallpaper):
- If a single inner card needs a contrast bump, that's a follow-up packet (W8.1).
- Do NOT re-tune the pane glass alpha in W8 — values are locked in `AdaptiveGlassBackground` per Migration policy #2.

- [ ] **Step 23.3: Smoke the recorder + popovers**

- Trigger recording. Recorder cluster reads correctly (no regression — recorder uses HaloMaterial, not the new modifier).
- Open the recorder enhancement popover (anchored to the recorder orb). The popover's new ultraThinMaterial backing reads cleanly; white text legible.
- Open Power Mode popover. Already-existing GlassCard hero reads correctly (no regression).

- [ ] **Step 23.4: Toggle Reduce-Transparency**

System Settings → Accessibility → Display → Reduce Transparency: ON.

Expected: every pane root + sliding panel reads as opaque `controlBackgroundColor`. NSVisualEffectView fully suppressed. No glass anywhere.

Toggle OFF. Expected: glass returns immediately on next pane re-render (no app restart needed).

- [ ] **Step 23.5: Toggle Increase-Contrast**

System Settings → Accessibility → Display → Increase Contrast: ON.

Expected: every pane root + sliding panel reads as opaque `windowBackgroundColor`. Hairlines on cards inside become 1pt solid (per existing `HaloMaterial` High-Contrast contract).

Toggle OFF. Expected: glass returns.

- [ ] **Step 23.6: Capture before/after evidence**

For the handoff doc that follows the W8 merge:
- 2 wallpaper pairs (bright + dark) × 3 surfaces (Settings, AI Models, History) = 6 screenshots.
- 1 Reduce-Transparency screenshot (any pane).
- 1 High-Contrast screenshot (any pane).

Total: 8 screenshots. Saved to a temporary folder; the handoff scribe attaches them to `docs/superpowers/handoffs/HANDOFF_W8_*.md`.

- [ ] **Step 23.7: Final report to lead**

Coder reports to the lead via SendMessage:
- **Surfaces migrated:** 27 sites + 1 window flag + 1 spec extension.
- **Build status:** `make local` SUCCEEDED.
- **Tests:** env-blocked / passing (whichever).
- **Smoke pass:** all 10 panes verified, recorder verified, accessibility branches verified.
- **Flagged risks delivered (see §Risks/unknowns):** any pane where smoke pass surfaced legibility concerns; HistoryWindowController seam (still opaque); Charts hosts intentionally opaque.
- **Outstanding:** any pane that the user wants re-tuned post-merge (follow-up W8.1 packet).

Lead handles commits per cadence rule.

---

## Risks/unknowns

1. **Detail-pane content tuned for opaque backgrounds — readability regression risk.** Cards inside the panes (`GlassCard` / `glassChip` / `glassPanel`) already render translucent. Layered on adaptive glass, the cards-on-glass-on-wallpaper stack may read low-contrast on busy wallpapers. **Mitigation:** the tint alphas (0.42 onyx pane / 0.18 light pane) were chosen specifically to keep cards legible — `.fullScreenUI` material is one of the more opaque NSVisualEffectView materials. If the smoke pass at Task 23 surfaces specific cards that read low-contrast, those become the W8.1 follow-up packet (per-card contrast bump or backdrop-fill α tweak — NOT a global tint re-tune in W8).

2. **Window-edge shadow artifacts on resize.** Non-opaque NSWindows occasionally show a 1-pixel edge artifact during live-resize. **Mitigation:** none in W8. If visible during smoke pass, document for follow-up; the same artifact occurs in many production glass apps (Things, Spline). Acceptable cost.

3. **Sidebar chrome interaction.** NavigationSplitView's `.sidebar` list style renders its own translucent vibrant material. With the window non-opaque, the sidebar gets a true wallpaper-blur for free. **Risk:** if SwiftUI's default sidebar material doesn't auto-adapt to `GlassAppearanceDetector`'s appearance flip (it follows system Light/Dark only), the sidebar may read inconsistently with the detail pane on bright wallpapers. **Mitigation:** Task 23 smoke pass verifies. If a regression, follow-up packet wraps the sidebar `List` with explicit material override. Out of W8 scope.

4. **`HistoryWindowController` separate window — out of scope.** Opens via menu bar dropdown into a fresh NSWindow with its own configureWindow flow (currently `window.backgroundColor = NSColor.windowBackgroundColor`). To match the main app, the same `isOpaque = false` + `.clear` bg flip is needed. **Decision for W8:** flagged + deferred. The history window opens infrequently and the user's stated scope ("the app") has been interpreted as the main window. Follow-up packet W8.2 if user wants parity.

5. **Charts hosts intentionally opaque (`PerformanceAnalysisView` / `PerformanceAnalysisPanelView`).** SwiftUI Charts render with their own chart-area backgrounds; sitting them over translucent surfaces produces "white tile" artifacts. **Mitigation in W8:** these sub-views keep their `.controlBackgroundColor` fills. The cost: a visible seam where the Charts host meets the surrounding adaptive glass. Documented in Migration policy #13. If the user objects post-merge, a follow-up packet adds explicit Chart bg styling + flips them.

6. **`MenuBarView` is system-NSMenu only.** Per the file's own doc-comment + `.menuBarExtraStyle(.menu)`, container backgrounds don't render. **Result:** the menu bar dropdown stays exactly as-is. Not a "missed surface" — a "non-skinnable surface". User feedback flag if they expected it.

7. **Reduce-Transparency / Increase-Contrast handling untested at scale.** W8 is the first packet to introduce `accessibilityDisplayShouldReduceTransparency` branch logic. The existing `HaloMaterial` only branches on Increase-Contrast. **Risk:** users with one of these prefs on may see a different behavior on the new app shell vs. the recorder cluster (which doesn't react to Reduce-Transparency). Decision: align — the `HaloMaterial` recorder material doesn't support Reduce-Transparency today, but adding that to recorder is out of W8 scope (would need a separate spec amendment + recorder smoke pass). Documented as a known asymmetry; W8 only fixes the app shell.

8. **Material choice — `.fullScreenUI` may not be available on older macOS.** `.fullScreenUI` is macOS 10.10+. Project targets macOS 14.0+ (per `target arm64-apple-macos14.0` in W8 syntax check). No deployment-target issue. If the project's actual minimum changes, recheck.

9. **Wallpaper sampling under user privacy preferences.** `NSWorkspace.shared.desktopImageURL(for:)` may return `nil` if the user has a screen-sharing or privacy guard active. The detector already falls back to system appearance in this case (`systemFallback()`). No new failure mode introduced by W8.

10. **Build cadence: single integration build.** W8 is 27 file touches across 19+ files (including spec). Per CLAUDE.md, no per-file `make local` runs. Coder commits all edits, then runs Task 22 build once. If the build fails, diagnose by file-by-file syntax check via SourceKit / `swiftc -parse` — not by partial reverts.

---

## Out of scope / explicit non-targets

These are not bugs, not oversights, not "we'll get to them later" — they are decisions:

- **MenuBar dropdown** — system NSMenu, not skinnable.
- **Recorder cluster panels** — already adaptive glass via HaloMaterial.
- **AppNotification / Announcement HUD panels** — already glass via VisualEffectView.
- **PowerMode popover hero** — already glass via GlassCard(.light) + NSPopover vibrant chrome.
- **Charts hosts (PerformanceAnalysisView et al.)** — opaque bg required.
- **Text-input chrome** (`textBackgroundColor` fills in WordReplacementView, etc.) — readability not negotiable.
- **Chip-level fills** (KeyChip, priority-list, drop-target, icon-button chrome) — chip vocabulary already W1-correct.
- **Preview-only `Color(red: 0.06, ...)` literals** in `#Preview` blocks — preview canvases.
- **`HistoryWindowController` separate window** — follow-up W8.2.
- **Recorder Reduce-Transparency support** — follow-up packet (out of W8 shell scope).
- **W8.1 / W8.2 contrast bumps for specific cards** — gated on Task 23 smoke-pass findings.
- **Onboarding surfaces (`MetricsSetupView`)** — explicitly deferred per spec §5 ("Onboarding flow. First-launch impression is mismatched until follow-up. Acceptable.").

---

## Self-review

- [x] **Spec coverage.** Every spec §1 / §2.3 / §6.1 / §6.4 reference traceable to a task. New §1.X added at Task 19 captures the W8 vocabulary.
- [x] **Placeholder scan.** No "TBD", "implement later", "add appropriate error handling", "similar to Task N" — every task ships exact line refs + concrete Swift snippets.
- [x] **Type consistency.** `AdaptiveGlassBackground` modifier signature `.adaptiveGlassBackground(intensity:)` consistent across Task 1 (definition) + Tasks 4-19 (call sites). `AdaptiveGlassIntensity` enum with cases `.pane` and `.panel` referenced consistently.
- [x] **Surface count.** 10 detail-pane roots + 10 sliding-panel sites + 5 sub-pane band drops + 1 popover + 1 window flag + 1 spec extension = 28 distinct edits across 19+ files. (The plan summary line says "27 sites" which counts surfaces unified per-file; the discrepancy is the spec extension counted separately.)
- [x] **Reduce-Motion.** Out of scope — W8 introduces no animations. The new modifier is a static background.
- [x] **Accessibility.** Reduce-Transparency + Increase-Contrast both branch correctly. Documented in Migration policy #3 + the new modifier file.
- [x] **No emoji in code, no PR-references in comments.** Every inline doc-comment cites spec section + plan path only.
- [x] **Single integration build.** Task 22 only.
- [x] **Hard-flagged risks.** 10 items in §Risks/unknowns. Each ties back to a specific Task or to a follow-up packet number (W8.1 / W8.2).

---

## Open follow-ups (post-W8)

1. **W8.1 — per-card contrast bumps** if Task 23 smoke pass surfaces low-contrast cards on busy wallpapers. Single-card surface inventory; likely 0-5 sites.
2. **W8.2 — `HistoryWindowController` separate window** to match main-window contract.
3. **W8.3 — Charts host glass treatment** if user objects to the opaque-Chart seam.
4. **W8.4 — recorder Reduce-Transparency support** to harmonize with the new app-shell behavior.
5. **W8.5 — onboarding glass** when the deferred onboarding flow is revisited (per spec §5).

---

**End of W8 plan.**
