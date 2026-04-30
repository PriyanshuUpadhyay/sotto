# VoiceInk Aesthetic Redesign — Spec

**Date:** 2026-04-28
**Author:** brainstorm-driven (iterative-visual-mockups, 5/5 foundations locked)
**Mockups:** `.superpowers/brainstorm/31419-1777360539/content/{material,structure,idle,state-cycle,scope}.html`
**Scope tier:** B · Recommended (~3 coder/reviewer pairs · 1.5–2 weeks)

## Brief

The current "Constellation / Dynamic-Island" recorder feels stale. The user kept the **glass material** but rejected the **rainbow palette + soft pill geometry + Apple-DI-shaped morph** that came with it. Goal: refresh the entire app's visual identity around a single coherent vocabulary — without re-architecting motion, type, or icon set from scratch.

## 1. Material — Adaptive Glass with Onyx-grade discipline

**Locked.** Translucent glass refraction stays. What changes: edges, palette, type, geometry.

### Tokens (concrete, replace existing values where they conflict)

```swift
// Palette.swift — retire transcribe-blue / enhance-violet
static let accent       = Color(hex: 0xFF5B3A)   // single live-state accent
static let accentMuted  = Color(hex: 0xFF5B3A).opacity(0.42)
static let accentGlow   = Color(hex: 0xFF5B3A).opacity(0.55)
static let onyxBg       = Color(hex: 0x0A0A0D)
static let onyxFg       = Color(hex: 0xEDEDF0)
static let onyxMute     = Color(hex: 0x8A8A93)
static let hairline     = Color.white.opacity(0.16)
static let hairlineSoft = Color.white.opacity(0.10)
static let innerHi      = Color.white.opacity(0.22)
// remove: Palette.recording (red), Palette.transcribe (blue), Palette.enhance (violet)
```

### Glass primitive (replaces `HaloMaterial` / `GlassCard`'s soft variants)

```
backdrop-filter:    blur(28pt) saturate(1.4)
fill:               rgba(20,20,28, 0.55)
border:             1px hairline (white α 0.16)
inner highlight:    inset 0 1.5pt 0 white α 0.22
shadow:             0 14pt 36pt black α 0.55
corner radius:      10pt for chips, 14pt for panels (NEVER 999pt pills)
```

**Type:** SF Mono uppercase tracking 0.06em for state labels and chip keys. System (`-apple-system`) for prose, body, and main-window content. Retire `.rounded` design tokens for state surfaces.

**Motion:** existing `Animation.haloExpand` (0.38s spring, damping 0.78) is kept for entry; **0.24s linear fade** added for cluster collapse. Reduce-Motion → swap to 0.18s opacity for both directions, no scale.

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

### 1.X.W13 W13 polish + cohesion deltas (2026-04-30)

The W13.A–G packet sweep closed the main-app cohesion gap with the floating-recorder vocabulary. The deltas below CODIFY decisions made during W13 sign-off and the merge of each packet. Source plans: `docs/superpowers/plans/W13{A..G}-*.md`.

**§1.X.W13.1 Hero corner radius 24pt sanctioned exception (Q9=a)**

§1 caps panels at 14-16pt corner radius. The Metrics/Dashboard hero section (`MetricsContent.heroSection`) carries dashboard centerpiece identity at 24pt corner radius — sanctioned exception. Applies only to "hero / dashboard centerpiece" surfaces (one per major destination, not per card). Plan reference: `W13B-metrics-rebuild.md` Q9=a.

NOT sanctioned: 28pt+ radii anywhere (HelpAndResourcesSection at v1's 28pt was retired in W13.B). NOT sanctioned: 24pt on regular `GlassCard` / `GlassChip` surfaces.

**§1.X.W13.2 Single-accent metric icon palette (W13.B)**

Metric card / dashboard pill icon backgrounds key to a SINGLE palette token. Default: `Palette.accent`. Motion (or progress-bar fill) is the discriminator across cards, not per-card hue. Spec §1's rainbow palette retirement extends to data-vis chrome.

Sanctioned non-state alternates: `Palette.success` (true completion / positive metric), `Palette.warn` (active power-mode signal), `Palette.neutral` (idle baseline). NEVER `.indigo / .teal / .mint / .purple / .yellow / .orange / .red / .green / .blue` direct refs.

**§1.X.W13.3 `glassPanel(cornerRadius: 16)` canonical Help/Resources idiom**

Help / Resources / Tip panels (e.g. `HelpAndResourcesSection`, `HistoryShortcutTipView`) use `glassPanel(cornerRadius: 16)` with inner link rows at `glassChip(cornerRadius: 10)`. Hairline strokes via `Palette.hairline` (outer) and `Palette.hairlineSoft` (inner separator). No outer shadow beyond what the primitive provides. Plan reference: `W13B-metrics-rebuild.md` HelpAndResourcesSection rebuild.

**§1.X.W13.4 Soft-pill `glassChip(cornerRadius: 18)` button capsules (W13.B)**

Button capsule chrome standardized at `glassChip(cornerRadius: 18)`. Replaces the `.thinMaterial` Capsule + ad-hoc spring affordance. Examples: CopySystemInfoButton, MetricsView footer button, History selection-bar "Clear" button. Reduce-Motion contract preserved (no per-button bespoke spring overrides).

**§1.X.W13.5 Family-aligned strokes for AI Models cards (W13.E)**

AI Models card family (Whisper / Cloud / FluidAudio / Native / Custom) uses uniform stroke vocabulary:
- Active card (selected / current): 1.5pt `Palette.accent` border + 0.55 alpha glow shadow rad 18.
- Rest card: 1pt `Palette.hairline` border, no glow.
- Card body: `GlassCard(cornerRadius: 16)` (no `HaloMaterial(phase: .hidden)` direct usage).
- Strokes NEVER use `Color.accentColor` or `Color.white.opacity(...)` directly — always `Palette.accent` / `Palette.hairline*`.

Plan reference: `W13E-ai-models-cards.md`. Same vocabulary applies to `CustomPrompt.promptIcon` tile family (W13.G axis E rebuild) and to the predefined-prompt template buttons.

**§1.X.W13.6 Flat sectionBlock pattern for popover / editorPane surfaces (W13.D)**

`Form { Section }` host is RETIRED for main-app + popover settings surfaces. Migrated to `ScrollView { LazyVStack(spacing: 16) { SettingsCard {...} } }` per `SettingsView.swift:51-71` (W5 pattern). Surfaces affected: EnhancementSettingsView, EnhancementSettingsPanel, PromptEditorView editor panes, InlineHistoryView card list, AudioTranscribeView queue, DictionarySettingsPanel.

`Form { Section }` is preserved ONLY where macOS system controls (NSPicker / NSStepper / NSColorWell) require Form context for layout correctness. Plan reference: `W13D-form-host-purge.md`.

**§1.X.W13.7 HUD notification three-color palette + motion discriminator (W13.G)**

`AppNotificationView` per-type colors collapse to a three-token palette + motion as discriminator. Icon, CTA chip backplate, and progress-bar fill all key to:
- `.error` → `Palette.warn`
- `.warning` → `Palette.warn`
- `.info` → `Palette.accent`
- `.success` → `Palette.success`

Motion is an ADDITIONAL discriminator on top of color, not a replacement: `.error` / `.warning` shake on present, `.success` pulse, `.info` quiet. The progress-bar decrement rate (derived from `duration:` parameter) further discriminates urgency: shorter `duration` for `.error` (fast decrement), longer for `.info`. VoiceOver / iconName retains semantic accessibility (xmark.octagon.fill, exclamationmark.triangle.fill, info.circle.fill, checkmark.circle.fill).

Plan reference: `W13G-polish-spec-extension.md` axis B; lead lock 2026-04-30.

**§1.X.W13.8 Q7=b menubar dropdown system-default (restated)**

Menubar dropdown stays system-default (`MenuBarExtra(...).menuBarExtraStyle(.menu)`). The `.window` glass popover variant was attempted and reverted per user request (sparse content + system-menu cohesion trade-off favors system-default). `MenuBarView.swift` and `MenuBarManager.swift` are OUT of all aesthetic-cohesion sweeps. Plan reference: master plan §0 Q7=b.

**§1.X.W13.9 Animation token sanctioned exceptions (W13.G axis G)**

Three animation literals are sanctioned exceptions to the §2.4 halo token grammar:

| File:line | Literal | Use | Reason for exception |
|---|---|---|---|
| `Common/PromptChipPicker.swift:125, 129` | `easeOut(0.2) → easeIn(0.2)` (2-phase, total 0.4s) | Selection pulse (scaleEffect + accent shadow ramp-up + ramp-down) | No current halo token has 2-phase ramp-up/ramp-down shape. Reduce-Motion guard is in place at `:122`. |
| `PowerMode/PowerModeStripView.swift:181` | `easeInOut(0.5).repeatForever(autoreverses: true)` | Active-mode warn dot pulse | 0.5s active-mode urgency is intentionally faster than `haloBreathe (1.6s)` enhancing-state breath. Reduce-Motion guard at `:179-180`. |
| `PowerMode/PowerModeStripView.swift:275` | `easeInOut(0.14)` | Drag-drop reorder micro-animation | Sub-150ms; below the `haloPhaseCrossfade (0.22s)` band. No Reduce-Motion guard (flag for follow-up). |

Future evolution: if these patterns recur, codify as `Animation.haloPulseTwoPhase` / `Animation.haloAttentionBreathe` / `Animation.haloMicro` in `Animation+Halo.swift`. W13.G defers token addition; current literals are sanctioned via this section.

### 2.4-W13 Source-literal → Halo token mapping (canonical)

W13.A established the source-literal → halo-token mapping; codified here as the canonical reference. New surfaces must NOT introduce ad-hoc `spring` / `smooth` / `easeInOut` literals; use the named token.

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

Recorder cluster animations (`.linear(duration: 1).repeatForever` etc.) are EXCLUDED — recorder is the source of truth for halo tokens, not a consumer.

## 2. Structure — Constellation satellite cluster

**Locked.** Replaces the single morphing pill with a cluster of small chips.

### Geometry

- **Anchor chip** — owns the live state (REC, TRANSCRIBING, ENHANCING). Always present during a non-idle state.
- **Secondary chips** — context (TIME, PROMPT, MODEL). Mount/unmount per state.
- **Action chips** — only during failed state (RETRY, OPEN SETTINGS).
- **Anchor position:** centred horizontally below the notch (or top-center on non-notch displays). 50pt below the menu-bar baseline. Z-order above main app windows, below modals.
- **Secondary chips fan out** to anchor's left and right at 8pt spacing. Two-row layout when ≥3 chips fit poorly in one row.
- **No persistent anchor at idle.** Cluster fades to nothing.

### Existing Swift surfaces this replaces

| Old | New |
|---|---|
| `MorphingRecorderPanel.swift` | `ConstellationCluster.swift` (new) — orchestrator |
| `ConstellationCard.swift` (single morph) | `ChipPanel.swift` (new) — anchor + secondaries layout |
| `HaloMaterial` (used as recorder bg) | `GlassChip` view modifier (new) — wraps the locked tokens |
| `GlassCard` (recorder card variant) | retained for main-window settings cards (re-themed via tokens) |

## 3. Idle — Invisible

**Locked.** No floating chrome at idle.

- The menubar waveform holds readiness signal:
  - **white solid** — armed and ready
  - **tangerine tint** — recording in progress
  - **tangerine + small dot overlay** — unresolved failure (until ack via Settings or successful retry)
- New: `MenuBarIconRenderer.image(for:)` adds a `.failed` overlay variant — small tangerine dot in upper-right corner of the waveform glyph. Driven by `FailureRegistry.unresolvedCount > 0`.

## 4. State grammar — single accent, motion distinguishes

**Locked.** Single tangerine across all live states. Motion is the state-discriminator.

| State | Chips | Anchor motion | Dwell | Notes |
|---|---|---|---|---|
| **idle** | none | — | — | cluster hidden; menubar waveform white |
| **recording** | REC + meter, TIME, PROMPT | tangerine `ringPulse 1.0s` on dot | until user stops | menubar waveform tangerine |
| **transcribing** | TRANSCRIBING, MODEL | white-cool dot, `shimmer 1.4s` (chip α 0.62↔1.0) | model-bound | accent stays tangerine but dot recolors white-cool |
| **enhancing** | ENHANCING, PROMPT, MODEL | tangerine dot `ringPulseSlow 1.6s` + `breath` halo on chip | model-bound | softer ring, longer period |
| **done** | ✓ PASTED → \<app\> | static, no motion | 1.2s, then 0.24s fade | tangerine check-in-circle |
| **failed (branch)** | anchor (FAIL label tangerine), reason chip (prose), RETRY, OPEN SETTINGS | `ringPulse 1.0s` aggressive | **6s default** · override in Settings (**3s / 6s / Until-dismissed**) | menubar dot persists past dismissal |

### Reduce-Motion fallback

All animations replaced with single-step opacity 0→1 over 0.18s. Ring pulse → static glow. Shimmer / breath → static state-color.

### Failure routing — single source of truth

```
TranscriptionPipeline (or any layer) ──► FailureRegistry.publish(reason:)
                                                  │
                                ConstellationCluster observes
                                                  │
                                ┌─────────────────┴─────────────────┐
                       failed-state cluster              menubar waveform overlay
                       (12s dwell + actions)             (persists until resolved)
```

Retire: `NotificationManager.shared.showNotification(type: .warning)` for enhancement-fail path. The cluster IS the notification surface.

## 5. Scope — B (Recommended)

### Surfaces in scope

1. **Recorder cluster** — primary; replaces `MorphingRecorderPanel`.
2. **Menubar icon** — failure-dot overlay variant.
3. **Failure routing** — new `FailureRegistry`; pipeline calls swapped.
4. **Main window chrome** — sidebar hairline, tighter radii, retire rainbow palette accents in nav.
5. **Settings panes** — re-skin to new tokens; no layout rework.
6. **AI Models page** — re-skin (provider chip, status pills) to new tokens.
7. **Prompts editor** — re-skin (chip picker, edit fields) to new tokens.
8. **Card primitive** — `GlassCard` hover-lift removed (kept hover, dropped 4pt translate-y); `GlassChip` view modifier introduced.
9. **Type pass** — replace `.rounded` with system across body; SF Mono for state labels.
10. **Palette retirement** — drop `Palette.recording / .transcribe / .enhance`; replace with `Palette.accent`.

### Out of scope (deferred · confirmed by user 2026-04-28)

- **Onboarding flow.** First-launch impression is mismatched until follow-up. Acceptable.
- **History detail view density rework.** Stays current.
- **App icon / Marketing site.**
- **Sound design re-tune.** Cues stay as-is; future polish pass.

### Work packets

Each is one coder/reviewer pair. Packets 1 and 4 must land first; the rest can run in parallel after.

| # | Packet | Files | Acceptance |
|---|---|---|---|
| **W1** | Token foundation | `Palette.swift` (new tokens, retire old), `GlassChip.swift` (new modifier), `Theme.swift` (ramp file if needed) | Build clean. All call sites of `Palette.recording / .transcribe / .enhance` migrated to `Palette.accent` or removed. |
| **W2** | Cluster + state grammar | `ConstellationCluster.swift`, `ChipPanel.swift`, motion modifiers, retire `MorphingRecorderPanel.swift` and the per-state phase view code | All 6 states render; reduce-motion path verified; cluster fans in/out per spec dwells. |
| **W3** | Failure routing | `FailureRegistry.swift` (new), `TranscriptionPipeline` swap, `MenuBarIconRenderer` failed-dot variant | Failure surfaces on cluster + menubar dot; persists across dismiss; clears on retry-success or manual ack. |
| **W4** | Main window chrome + sidebar | `ContentView.swift`, sidebar primitives, top-level cards | Hairline tokens, single-accent navigation, no rainbow palette in sidebar/section headers. |
| **W5** | Settings re-skin | `EnhancementSettingsView.swift`, `EnhancementSettingsPanel.swift`, `HotkeySettings*`, `AudioInputSettings*`, etc. | Existing layout preserved; cards/chips/toggles inherit new tokens; visual diff against old screens captured. |
| **W6** | AI Models + Prompts re-skin | `MLXModelPickerView.swift`, `ProviderCard.swift`, `PromptEditorView.swift`, `EnhancementSettingsPanel.swift` (chip picker section) | Provider chips, status pills, prompt chips re-themed; download progress UI inherits cluster vocabulary. |
| **W7** | Type + sound polish | Find/replace `.rounded` → system in body type; verify SF Mono on state labels; sound cue volume re-tune to match new "lighter" aesthetic | No `.rounded` outside designated places; chip labels uniformly SF Mono. |

**Build cadence:** per the user's CLAUDE.md memory, **single build at merge time** — not per-coder/per-reviewer. Coders push branches; one integration build at the end of each packet.

## 6. Spec self-review

- [x] **Placeholders.** None — concrete tokens, file names, dwell timings, motion specs.
- [x] **Contradictions.** Single-accent across all live states ↔ "transcribing dot is white-cool". Resolution: anchor chip stays tangerine-bordered; only the dot recolors for transcribe to read as a non-active capture state. Documented above.
- [x] **Ambiguity.**
  - Failure dwell default = **6s**, override **3s / 6s / Until-dismissed** in Settings. Settings UI for this is in W3, not deferred.
  - "Cluster on non-notch displays" — anchor positioned 50pt below menu-bar baseline regardless. No notch dependency.
  - Failure dot on menubar — clears on **retry success** OR **opening Settings** (auto-ack, no explicit dismiss button needed). If user navigates away without resolving, dot returns on next launch.
- [x] **Scope creep guard.** Onboarding, history density, app icon, marketing — explicitly out. Anyone proposing them gets pointed back here.
- [x] **Reduce-Motion.** Spec'd: 0.18s opacity, no scale, no ring pulse.
- [x] **Accessibility.** Cluster VoiceOver order: anchor → reason (if failure) → secondaries → actions. Each chip has its own `axElement`; cluster wrapped in single `axGroup` so VoiceOver reads "VoiceInk recording, level meter active" as one.

## 7. Handoff

1. User reviews this spec; calls out anything to refine.
2. Once approved → invoke `superpowers:writing-plans` to convert each work packet into a step-by-step implementation plan.
3. Spawn paired coder/reviewer teammates per packet (W1 first; W4 in parallel; W2/W3/W5/W6/W7 once W1 lands).
4. Single integration build at the end of each packet (per CLAUDE.md cadence rule).
5. Final cohesion pass: visual diff old-vs-new across all in-scope surfaces; capture before/afters in `docs/superpowers/handoffs/`.
