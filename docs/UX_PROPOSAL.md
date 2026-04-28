# VoiceInk UX Proposal — Dynamic-Island-Style Recorder + Polish

**Author:** ui-designer (research only, no code)
**Branch:** `priyanshu/embedded-llm`
**Date:** 2026-04-27
**Scope:** mini recorder visual redesign; secondary settings polish.

---

## 1. Current UI Snapshot

Two recorder modes ship today, picked from Settings → Interface:

- **Notch recorder** (`NotchRecorderView` + `NotchShape`). Anchored to the physical MacBook notch. Pure-black pill, hugs the notch geometry, spring-animates a side expansion (~90px each side during recording, ~110px when live transcript shows). Custom path drawn in `NotchShape.swift` with animatable top/bottom corner radii. Status bar height (≈37pt). Already morphing — already Dynamic-Island-adjacent in skeleton.
- **Mini recorder** (`MiniRecorderView`). Floating pill at the **bottom-center** of the visible frame, fixed 184pt wide → 300pt expanded for live transcript. Plain `RoundedRectangle` corner radius 20→14, flat `Color.black` background, `easeInOut 0.3` only.

Both share `RecorderComponents.swift`: a 15-bar audio visualizer (sine-modulated heights, center-boosted), `ProcessingStatusDisplay` showing the literal word "Transcribing" / "Enhancing" with a 5-dot scrolling indicator, two flanking icon buttons (enhancement prompt + power mode). Live partial transcript renders inside the same surface as a small fading scroll view (`LiveTranscriptView`), masked by a top-edge gradient.

State machine (`RecordingState`): `idle / starting / recording / transcribing / enhancing / busy`. Visual states only express three: collapsed, active, liveText.

Settings (`SettingsView`) is a stock `Form` with `.formStyle(.grouped)` — `LabeledContent`, `Toggle`, `Picker(.segmented)`, custom `ExpandableSettingsRow` for hierarchical toggles. Functional. Apple-default. Zero personality.

## 2. Pain Points

**Recorder:**
- Mini recorder lives at the **bottom** of the screen — wrong end. Eye lives at the menu bar / app content. Bottom anchoring competes with Dock and feels like a Slack toast.
- Pure `Color.black` flat fill. No depth, no material, no ambient light. iOS Dynamic Island reads as glassy/floating because of OLED-deep-black blended with subtle inner gloss; SwiftUI flat black on a desktop wallpaper just looks like a hole.
- Animation is correct in mechanic (spring) but **uniform** — every state transition uses the same response/damping. No staccato vs. legato. Nothing breathes.
- "Transcribing" / "Enhancing" states show literal words + dots. Fine, but boring. Uses no information from the actual model (token rate, model name, time).
- Idle = invisible. No persistent ambient identity. Power Mode is invisible until you open the popover. There's no "you're armed" state.
- 15-bar EQ audio viz is generic. Reads as "audio app" — not specifically VoiceInk.
- Live transcript fades from the top — feels like log spam. No emphasis on the most recent token, no sense of forward motion.
- Failure / error / cancelled states are not visualized (per `RecordingState` they collapse to idle). Dropping straight to invisible after a failure is bad feedback.
- Power Mode badge: an emoji glyph in a button. Reads as placeholder.
- No sense of light or color emitted by the pill — Apple's island casts visible glow on the notch in iOS 17. Ours doesn't.

**Settings:**
- Visually indistinguishable from System Settings. App could be anything.
- No iconography, no section illustration, no color accents. The PowerMode and Enhancement sections deserve more presence.
- The Recorder Style picker is a `.segmented` Picker labeled "Notch" / "Mini" — text-only. Should be **visual previews**.
- Provider/model selection (in MenuBar + EnhancementSettings) is text dropdowns. Provider logos / colored chips would do a lot.
- Onboarding lives in a separate flow that most users will never re-enter — no breadcrumb of "what's possible."

## 3. Headline Proposal — "**Halo**"

Top-anchored, expanding pill that morphs between states. Reuses the existing `NotchShape` skeleton and panel infrastructure — **no new windowing layer**. Replaces the bottom-floating Mini recorder with a top-floating sibling that uses the same component as the notch (so non-notched Macs and external displays get parity).

> One pill. One anchor (top center). One morphing geometry. One light source.

### 3.1 Geometry & Anchoring

```
                       ┌──────────────── menu bar ────────────────┐
                       │                                          │
                       │       (notch on MBP / status bar)        │
                       │                                          │
                       │           ╭──────────────────╮           │  <- idle, ambient halo only
  IDLE                 │           ╰──────────────────╯           │     6×140pt, 1pt high
                       │                                          │
                       │                                          │

                       ┌──────────────── menu bar ────────────────┐
                       │           ╭──────────────────╮           │  <- collapsed pill (default armed)
                       │           │   ▁▃▄▅▆▅▄▃▁     │           │     220×34pt
                       │           ╰──────────────────╯           │
  ARMED / IDLE-VISIBLE │                                          │

                       ┌──────────────── menu bar ────────────────┐
  RECORDING            │  ╭──────────────────────────────────╮   │  <- expanded recording
                       │  │ ✶  ▁▃▆█▆▅▃▁▂▅▇█▇▅▃▁     ●  ✦  │   │     460×42pt
                       │  ╰──────────────────────────────────╯   │
                       │                                          │

                       ┌──────────────── menu bar ────────────────┐
                       │ ╭────────────────────────────────────╮  │
  LIVE TRANSCRIPT      │ │ ✶  ▁▃▆█▆▅▃▁▂▅▇█▇▅▃▁     ●  ✦   │  │     560×100pt
                       │ │ ─────────────────────────────────  │  │
                       │ │ "the dynamic island feels great"   │  │  <- last 2 lines, top fades,
                       │ ╰────────────────────────────────────╯  │     active token glows
```

ASCII can't show it but: imagine the pill **emits a soft luminance** behind itself onto the wallpaper — implemented as an off-screen blurred shadow layer in the panel, color-keyed to state.

### 3.2 State Vocabulary

| State | Geometry | Material | Motion | Identity Cue |
|---|---|---|---|---|
| **Hidden** | not present | — | — | — |
| **Idle-armed** (optional, off by default) | 220×34, r=14 | matte black + 8% inner top gloss | none — sits still | tiny static EQ, 30% opacity |
| **Recording** | 460×42, r=18 | matte black + audio-reactive halo (red→amber depending on level) | breathing spring (response 0.38, damping 0.78) | live waveform, **pulsing red dot** at right |
| **Transcribing** | 460×42, r=18 | matte black + cyan halo at 40% intensity | shimmer pass left→right every 1.4s across the pill border | shimmering "transcribing" — *replace dots indicator with a moving caustic gradient stroke* |
| **Enhancing** | 460×42, r=18 | matte black + violet halo + subtle inner sheen | slow breathe (1.6s in, 1.6s out) | active prompt icon glows at left, model name renders in 9pt all-caps tracked-out at right |
| **Live transcript** | 560×100, r=22 (top), r=28 (bottom) | matte black + subtle bottom gradient veil | slides down with rubber-band overshoot | last-token highlight + parallax scroll |
| **Done / success** | 460×38, r=18 | flash 280ms green halo, then collapse | one decisive tween (0.32s ease-out) | checkmark glyph fade-in |
| **Failed** | 460×42, r=18 | flash 280ms red halo + 6pt horizontal shake | spring 0.5/0.55 | `!` glyph + 1.2s amber dwell, then collapse |
| **Cancelled** | 460×38 → 0 | dim to 30% then collapse | 0.22s ease-in | none |

The ambient **halo** is the move. Apple's Dynamic Island reads premium because the screen above it actually emits subtly. We can fake this in macOS via a panel layer-shadow that's color-tinted, blurred ~24px, offset 0,4. State drives the color. Already `NotchRecorderPanel` sets `hasShadow = false` — flip it to a custom CALayer shadow with state-keyed `shadowColor`.

### 3.3 Material — "Liquid Obsidian"

Replace `Color.black` background with a layered stack:

1. Base: `NSVisualEffectView` with `.hudWindow` material in `.dark` appearance, 92% blur intensity. Gives subtle depth-of-field over wallpaper.
2. Tint layer: `Color.black.opacity(0.78)` — keeps the OLED-deep look but lets blur through.
3. Inner top gloss: 1pt tall linear gradient from `white.opacity(0.06)` → clear, only on the top edge.
4. Inner stroke: 0.5pt `white.opacity(0.08)` to define the silhouette against bright wallpapers.
5. State halo: drop shadow color-keyed (recording: `#FF3B30`@0.18, transcribing: `#5AC8FA`@0.22, enhancing: `#BF5AF2`@0.20, success: `#30D158`@0.26, failure: `#FF453A`@0.32). Blur 24, offset (0, 4).

Net effect: pill reads as a single piece of dark glass that "glows from inside" depending on what it's doing. Distinct from anything else on macOS.

### 3.4 Motion Grammar

Three named springs. Use all three and only these:

```
expand   = spring(response: 0.38, damping: 0.78)   // width/height growth, button reveal
collapse = spring(response: 0.42, damping: 1.00)   // contraction, no overshoot
breathe  = spring(response: 1.60, damping: 0.95).repeatForever(autoreverses: true)  // enhancing
```

Plus two specials:
- **Shimmer**: 1.4s linear gradient sweep across the inner stroke during transcribing. Not a separate animation — a single `TimelineView(.animation)` timeline sampling phase.
- **Shake** (failure): keyframe x-offset {-6, 6, -4, 4, -2, 0} over 0.32s.

Stagger: when expanding from idle → recording, button reveal is delayed 0.09s after the geometry settles (already implemented — keep it). Audio visualizer fades in 0.06s after that.

### 3.5 Audio Visualizer — "Pulse Ribbon"

Today: 15 equal-width bars. Replace with a **Catmull–Rom-smoothed waveform** rendered as a `Path` filled with a vertical gradient. 32 sample points. Active sample (= newest) gets a 4pt halo blur. Net: looks like breath, not Audacity.

Fallback to current bar viz available behind a hidden defaults key for users who prefer it.

### 3.6 Live Transcript — "Streaming Caret"

Replace the gradient-faded scroll view with:

- Last full sentence in 14pt SF Pro Rounded **medium**, white@0.95.
- Previous sentence above it in 12pt, white@0.45.
- A subtle 1.5pt-wide vertical caret bar pulsing at the end of the partial token (white@0.7, 1.1s pulse).
- New tokens fade in over 0.18s with a 1pt rise — feels like text being *exhaled*.

Constraint: do not animate the partial token's character-by-character. Token-level, not character-level. (Character-level animation reads as gimmicky and breaks accessibility.)

### 3.7 Enhancing State — "Prompt Identity"

Currently shows `ProgressAnimation` (5 dots). Instead:

```
  [ prompt-icon glow ]   the live transcript text         [ ʟʟᴀᴍᴀ-3.1 ]
                         being shaped...                  [ enhancing  ]
```

- Left: the active prompt's icon (already in `enhancementService.activePrompt.icon`) renders at full color and breathes (alpha 0.6 ↔ 1.0, 1.6s).
- Right: model identifier in 9pt all-caps tracked +0.12em — `Provider · model` (e.g., `OPENAI · GPT-4O-MINI` or `MLX · LLAMA-3.1-8B`). Source: `aiService.selectedProvider` + `aiService.currentModel`.
- This single change makes the AI feel real and present rather than abstract.

### 3.8 Compatibility With Existing Infrastructure (hard constraint)

Halo is an **adapter**, not a rewrite:

- Keeps `NotchRecorderPanel`, `NotchWindowManager`, and the `NotchShape` skeleton intact.
- Mini recorder migrates from bottom-anchored to top-anchored; its panel logic in `MiniRecorderPanel.calculateWindowMetrics()` flips `yPosition` from `visibleFrame.minY + padding` to `visibleFrame.maxY - height - padding`, and on notched displays auto-snaps below the notch. (~12 LOC change.)
- The recorder-style picker in Settings becomes "Halo (top) / Mini (free-floating)" — visual previews instead of words.
- `RecorderStateProvider` stays the contract. No changes to `VoiceInkEngine`.
- New visual states (`success`, `failed`, `cancelled`) hook off existing transitions: success = recording→idle; failed = transcribing/enhancing→idle when error flag set; cancelled = explicit cancel path. Engine already has the signals — we just stop ignoring them in the view.
- Audio meter (`recorder.audioMeter`) is consumed identically by Pulse Ribbon.

## 4. Settings UI Polish

The Settings form is the first impression after onboarding. It should feel *crafted*, not *configured*.

### 4.1 Sectioned Hero Headers

Replace plain `Section { … } header: Text("Shortcuts")` with a custom `SettingsSectionHeader` component:

```
  ╭───╮
  │ ⌘ │  Shortcuts                                   2 active
  ╰───╯  Trigger recording from anywhere.
```

Each section gets:
- A 28pt rounded-square icon tile in the section's accent color (Shortcuts: indigo, Recording: red, Power Mode: orange, Privacy: green, AI: violet).
- One-line subtitle in 11pt secondary.
- Optional right-aligned status pill ("2 active", "Disabled", "1 model loaded").

This is purely additive — does not break the `Form` structure.

### 4.2 Recorder Style Picker → Visual Previews

Replace:
```swift
Picker("Recorder Style", selection: $recorderUIManager.recorderType) {
  Text("Notch").tag("notch"); Text("Mini").tag("mini")
}
```

with two ~140×88pt selectable cards, each rendering a **live miniature of the actual pill** in idle state. Selection = colored ring + inner shadow. Same pattern as macOS Wallpaper picker. Costs ~80 LOC, reads as 10×.

### 4.3 Provider / Model Chips

In `EnhancementSettingsView` and `MenuBarView`, replace text-only `Text(provider.rawValue)` with a `ProviderChip(provider)` view:

- 16pt provider mark (OpenAI ⭘, Anthropic ✦, Groq ⌬, Apple , MLX ⬡ — use SF Symbols + tinted background squares).
- Provider name in 11pt medium.
- Model name in 11pt regular `.secondary`.
- Connected state shown as a 6pt green dot in the corner.

### 4.4 Power Mode Section — Make It Live

Right now Power Mode is hidden behind an expandable row. The PowerMode list itself is configured via separate views. Instead, render a **horizontal scrollable strip** of the configured Power Modes inside the section, each as a ~72×96pt card showing:

- Emoji
- Power mode name
- App/site icon
- "Active" indicator if currently triggered

Tap to edit. Plus card at the end. Drag to reorder (DnD already exists for prompts — pattern reuse).

### 4.5 Typography System

Currently: system default everywhere. Introduce two voices:

- **Display** (section headers, recorder labels): `SF Pro Rounded` semibold at 17pt — friendly, distinct from System Settings.
- **Body**: `SF Pro Text` regular at 13pt.
- **Mono** (model names, shortcuts, provider IDs): `SF Mono` 10pt all-caps tracked +0.12em.

Three typefaces, three sizes, three weights. Total system. Don't sprawl beyond.

### 4.6 Color & Theme

Currently: `Color.accentColor` only. Introduce a fixed palette of 6 functional accents (used in section icons, halos, and chips):

```
recording   #FF3B30   (system red, but not a Color.red)
transcribe  #5AC8FA   (cyan)
enhance     #BF5AF2   (violet)
success     #30D158   (green)
warn        #FF9F0A   (orange — power mode)
neutral     #8E8E93   (default)
```

Centralize in a `Palette.swift` (new file, ~40 LOC). All color references go through it. Makes future theming trivial.

## 5. First-Cut Implementation Plan (1–2 days)

Files to touch / create. **No code in this doc** — just touchpoints.

**Day 1 — Halo recorder.**

1. **New** `VoiceInk/Views/Recorder/HaloShape.swift` — variant of `NotchShape` that handles both the on-notch and below-notch / no-notch geometries. ~80 LOC.
2. **New** `VoiceInk/Views/Recorder/HaloRecorderView.swift` — replaces both `NotchRecorderView` and `MiniRecorderView` interiors. State-driven. Wires `RecorderStateProvider`, `Recorder`, halo, materials, ribbon, transcript. ~280 LOC.
3. **New** `VoiceInk/Views/Recorder/PulseRibbon.swift` — Catmull-Rom smoothed waveform replacement for `AudioVisualizer`. ~110 LOC.
4. **New** `VoiceInk/Views/Recorder/HaloMaterial.swift` — the layered material stack (NSVisualEffectView wrapper + gradients + halo shadow driver). ~90 LOC.
5. **Edit** `MiniRecorderPanel.swift` — flip yPosition to top, snap below notch. ~12 LOC.
6. **Edit** `NotchRecorderPanel.swift` — wire state-keyed CALayer shadowColor for the halo glow. ~30 LOC.
7. **Edit** `NotchWindowManager.swift` / `MiniWindowManager.swift` — both inject `HaloRecorderView` instead of their respective views. ~10 LOC each.
8. **Edit** `RecorderComponents.swift` — extend `RecorderStatusDisplay` with success/failed/cancelled cases; replace dot indicator with shimmer view. ~80 LOC.
9. **New** `VoiceInk/Views/Common/Palette.swift` — color tokens. ~40 LOC.

Day-1 total: ~750 LOC, mostly new files. Old `MiniRecorderView` + `NotchRecorderView` shrink to ~20-line wrappers around `HaloRecorderView`.

**Day 2 — Settings polish.**

10. **New** `VoiceInk/Views/Settings/SettingsSectionHeader.swift` — icon + title + subtitle + status pill. ~120 LOC.
11. **New** `VoiceInk/Views/Settings/RecorderStylePicker.swift` — visual cards picker. ~140 LOC.
12. **New** `VoiceInk/Views/Common/ProviderChip.swift` — chip component. ~80 LOC.
13. **Edit** `SettingsView.swift` — adopt new section headers in the 6 most-visible sections. ~120 LOC of edits.
14. **Edit** `EnhancementSettingsView.swift` + `EnhancementSettingsPanel.swift` — adopt provider chips. ~60 LOC.
15. **Edit** `MenuBarView.swift` — provider chips in the AI Provider / AI Model menus. ~30 LOC.

Day-2 total: ~550 LOC.

**Total estimate: ~1,300 LOC across ~15 files (≈9 new, ≈6 edited).**

Risk areas:
- NSVisualEffectView inside a `.nonactivatingPanel` with `level = .statusBar + 3` may need experimentation — the panel currently sets `backgroundColor = .clear`, `hasShadow = false`. The blur layer needs to render under the SwiftUI hosting view; `NSHostingController.view.layer` insertion is the lever.
- CALayer shadow on a non-rectangular shape needs `shadowPath` set to the `NotchShape.path` for performance.
- Power Mode strip in Settings depends on `PowerModeManager.configurations` shape — needs a quick check that drag-reorder doesn't conflict with the existing Settings logic.

## 6. Stretch Goals

If the first cut lands well, here's the runway.

### 6.1 Sound design pass

- Recording start: a single 880Hz pluck, 90ms attack, ~140ms decay, 6th-tuned. Currently a system sound — replace with bespoke samples. SoundManager already exists.
- Transcribe complete: a quick 4-note ascending arpeggio in C major (C-E-G-B), ~220ms total, soft.
- Enhance complete: same arpeggio, transposed up a 4th, slightly softer.
- Cancel: descending two-note motif, A-E.
- All under 300ms. Curated, not stock. (CustomSoundSettingsView already exists for user replacement.)

### 6.2 Halo theming

Expose halo color and material intensity as user preferences in Settings:
- 4 presets: **Obsidian** (default), **Frost** (light material), **Aurora** (rainbow shimmer on idle, very playful), **Mono** (no color, ascetic).
- Power users (or marketing) can use this to show off.

### 6.3 Haptics-Adjacent Visual Feedback

There's no Mac haptic engine for trackpads in apps, but we can use **subtle scale pulses** as a haptic-equivalent at key moments:
- Recording starts: pill scales 1.0 → 1.04 → 1.0 in 120ms.
- Tokens commit (every full sentence): 1.0 → 1.012 → 1.0 in 80ms.

Tasteful when calibrated. Off by default; opt-in toggle.

### 6.4 Idle Ambient Mode

Persistent 6×140pt halo line just below the menu bar, only visible when the cursor is near the menu bar. Tells the user "VoiceInk is listening for hotkeys." Off by default. For users who want maximum reassurance.

### 6.5 First-Run Recorder Walkthrough

After onboarding, before they trigger their first recording: a 6-second guided animation of the Halo state-cycle (idle → recording → transcribing → enhancing → done) overlaid with one-line captions. Auto-plays once. Skippable. Re-runnable from Help menu.

### 6.6 Live Transcript "Highlight Reel"

After a long recording ends, replay the last 20 seconds of partial transcripts in a fast-forward as the pill collapses — like the "video processed" moment in iOS Photos. 350ms total, optional, off by default.

### 6.7 Multi-Display Smarts

Halo currently anchors to `NSScreen.main`. Stretch: anchor to the screen that contains the focused app's window. Reduces "where's my recorder?" on multi-monitor setups.

### 6.8 Menu Bar Icon — Animated Identity

Currently a static glyph. State-driven menu bar icon:
- idle: thin static waveform glyph
- recording: animating pulse (60fps via `NSStatusItem.button.image` swap or Core Animation layer)
- transcribing: shimmer
- enhancing: prompt-icon overlay

Subtle but signals "this app is alive" even when the Halo is collapsed.

---

## Open Questions to Validate Before Build

1. **Top vs. bottom anchoring for the Mini variant.** I'm proposing top. User explicitly invoked "Dynamic Island," which is top — but moving the existing Mini recorder is a behavior change for current users. Confirm migration vs. a per-user setting.
2. **Idle-armed visibility.** Should the pill stay visible at low opacity when armed but not recording, or stay fully hidden until hotkey fires? I lean hidden by default (less noise) with an opt-in.
3. **Does `NSVisualEffectView` blur render correctly under a `.statusBar+3` panel?** Needs a 30-min spike before locking the material design.
4. **Color palette acceptance.** The 6 functional accents lock in a strong identity. If the user wants a more monochrome or different chromatic direction, decide before Day 2.
5. **Sound design scope.** Is bespoke audio in or out? It's a force multiplier on the visual work but adds a content production task.
