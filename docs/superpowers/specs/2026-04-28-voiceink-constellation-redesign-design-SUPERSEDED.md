# VoiceInk Constellation Redesign — Design Spec

**Status:** LOCKED — do not relitigate foundational decisions.
**Branch:** `priyanshu/embedded-llm`
**Date:** 2026-04-28
**Supersedes:** `docs/UX_PROPOSAL.md` recorder section (v1 — single-pill Halo direction).
**Companion:** `docs/UX_IMPL_NOTES.md` (v1 build notes — what already exists).

---

## 1. Overview

VoiceInk's recorder and settings surfaces get a total visual overhaul under the codename **Constellation**. The single morphing pill of the v1 Halo direction is replaced by a distributed system of three independent notch-adjacent pieces — an orb, a chip, a floating card — that together read as one coherent identity while each occupying its own spatial slot. Material vocabulary upgrades from obsidian-only glass to **Adaptive Glass**: a dual-preset system that auto-picks a light or dark variant based on system appearance (and eventually wallpaper luma). Every other surface — settings, menu bar, onboarding, history, license, AI models, dictionary, prompts editor, animated icon, sound design — also adopts the new language. The v1 files that were already built (`Palette`, `HaloMaterial`, `ProviderChip`, `SettingsSectionHeader`, `RecorderStylePicker`) are reused or refactored, not thrown away.

---

## 2. Locked Decisions

Five decisions are final. Specs that reference them do not need to explain them.

**1. Adaptive Glass material.** Two presets — light translucent glass for bright wallpapers, onyx-style dark glass for dark wallpapers. Auto-picked from system appearance; wallpaper luma analysis is v2. Same component, same token names, just an `isDark` flag that swaps the fill/tint values. Builds on `HaloMaterial.swift`.

**2. Constellation recorder.** Three separately-positioned pieces replace the single pill:
- **Left orb** — small pulsing dot, left of the physical notch. State-keyed color. Audio energy modulates radius subtly.
- **Right chip** — small glass chip, right of the notch. Shows active provider and model identity. State-keyed dot color matches orb. Fades when idle.
- **Floating card** — glass card that drops below the notch. Hosts live transcript (recording), engine info (transcribing), prompt + model (enhancing), result preview + paste destination (done).

Each piece is its own window at its own screen position. Choreographed together, visually independent.

**3. Whisper idle state.** No orb, chip, or card when nothing is happening. Just a 60×2pt gradient breath line below the notch (35–85% opacity on a 2.6s sine). Brightens on cursor approach. Dims when cursor is far.

**4. State cycle.** idle (whisper) → recording → transcribing → enhancing → done → idle. Plus failure (red shake on orb + 1.2s amber dwell → idle). **Done is new**: previously the recorder vanished immediately on paste; now shows a 280ms green flash + "Pasted to \<App\>" preview before returning to idle.

**5. Total scope.** All surfaces: recorder, menu bar dropdown, settings, onboarding, history (list + detail), license, AI models / API keys, dictionary, prompts editor, animated menu bar icon, sound design.

---

## 3. Material Spec: Adaptive Glass

### 3.1 Dark Variant ("Onyx") — existing `HaloMaterial` behavior

Current `HaloMaterial.swift` already implements this. Keep as-is, rename the preset constant.

Layer stack (bottom → top):
1. `NSVisualEffectView` — `.hudWindow` material, `.behindWindow` blend, `.dark` appearance, `isEmphasized: false`. Gives desktop blur depth.
2. `Color.black.opacity(0.78)` — preserves OLED-deep look, lets blur breathe.
3. Inner top gloss — 1.5pt-tall `LinearGradient` from `white@0.06 → clear`, top edge only.
4. Inner sheen (enhancing only) — `RadialGradient` from `glowColor@0.22 → clear`, `.plusLighter` blend, `opacity(0.55)`.
5. Stroke — `0.5pt white@0.08` via `shape.stroke(...)`.
6. Halo glow — `.shadow(color: glowColor@α, radius: 24, x: 0, y: 4)`.
7. Lift shadow — `.shadow(color: black@0.45, radius: 14, x: 0, y: 6)`.

### 3.2 Light Variant ("Frost") — new

Layer stack (bottom → top):
1. `NSVisualEffectView` — `.hudWindow` material, `.behindWindow` blend, **system appearance** (no forced `.darkAqua`). Pulls in the light blur.
2. `Color.white.opacity(0.40)` — white tint over the blur; replaces the black fill.
3. Inner top gloss — 1pt-tall `LinearGradient` from `white@0.55 → clear`.
4. Inner sheen (enhancing only) — same `RadialGradient` pattern but at `glowColor@0.14` (softer on light).
5. Stroke — `0.5pt black@0.10` (defines silhouette against bright wallpaper).
6. Halo glow — same color math as dark but `radius: 18, x: 0, y: 3` (slightly tighter — light surfaces scatter differently).
7. Lift shadow — `.shadow(color: black@0.18, radius: 10, x: 0, y: 4)`.

### 3.3 Variant Selection

```
isDarkMaterial = colorScheme == .dark   // environment value, no wallpaper analysis in v1
```

A single `AdaptiveGlassMaterial` view wraps both presets and switches on `isDarkMaterial`. Callers never reference `HaloMaterial` directly — they use `AdaptiveGlassMaterial(shape:, phase:, breathePulse:, showInnerSheen:)`. The underlying struct can keep the `HaloMaterial` internals; only the entry point renames.

### 3.4 Corner Radii

| Surface | Top radius | Bottom radius |
|---|---|---|
| Orb | — (circle) | — |
| Right chip | 8pt | 8pt |
| Floating card, collapsed | 14pt | 20pt |
| Floating card, expanded (liveText) | 14pt | 26pt |
| Floating card, done state | 16pt | 16pt |
| Menu bar glass panel | 12pt | 12pt |
| Settings glass card | 10pt | 10pt |

### 3.5 State-Keyed Glow

Glow attaches to the piece that carries the primary state signal — the **orb** for recording/transcribing/enhancing, the **floating card** for done/failed. The chip gets a subtle matching tint but no large shadow.

| State | Glow color | Alpha | Radius |
|---|---|---|---|
| recording | `Palette.recording` | 0.22 | 24 |
| transcribing | `Palette.transcribe` | 0.26 | 24 |
| enhancing | `Palette.enhance` | 0.28 + breathe×0.06 | 28 |
| done | `Palette.success` | 0.30 | 20 |
| failed | `Palette.recording` | 0.38 | 24 |
| idle | none | 0 | — |

---

## 4. State Grammar

### 4.1 State Table

| State | What's visible | Orb | Chip | Card | Duration / trigger |
|---|---|---|---|---|---|
| **idle** | Whisper breath line only | hidden | hidden | hidden | persistent while no session |
| **recording** | Orb + chip + card (live transcript) | red pulsing, r=5–8pt audio-reactive | provider dot = red, chip fades in | drops down, shows pulse ribbon + partial transcript | while engine `recording` or `starting` |
| **transcribing** | Orb + chip + card | cyan shimmer, r=5pt steady | dot = cyan | shows engine name + shimmer stripe | while engine `transcribing` |
| **enhancing** | Orb + chip + card | violet breathing, r=5–7pt | dot = violet | shows prompt icon + model identity + breathe | while engine `enhancing` |
| **done** | Orb + chip + card (briefly) | green flash 280ms | dot = green | "Pasted to \<App\>" + transcript excerpt | 280ms flash → 800ms dwell → collapse |
| **failed** | Orb + chip | red shake on orb | dot = amber, 1.2s dwell | card collapses | 1.2s amber dwell → idle |

### 4.2 Named Animation Springs

All transitions use exactly these springs. No one-offs.

| Name | Response | Damping | Use |
|---|---|---|---|
| `expand` | 0.38 | 0.78 | orb radius grow, card drop-down, chip fade in |
| `collapse` | 0.42 | 1.00 | orb shrink, card slide up, chip fade out |
| `breathe` | 1.60 | 0.95 | enhancing orb radius pulse (repeat, autoreverses) |
| `shimmer` | n/a | n/a | `TimelineView` linear sweep, 1.4s period, transcribing card |
| `shake` | 0.50 | 0.55 | failure orb x-offset keyframes |

**Whisper breath:** `easeInOut(duration: 2.6).repeatForever(autoreverses: true)` — not a spring. Opacity 0.35 ↔ 0.85.

**Stagger:** on entering recording, card drops 0.09s after orb/chip settle. On collapse, orb leads (0ms), chip follows (60ms), card last (120ms).

### 4.3 Done State Detail

- Engine `idle` transition observed. View layer derives "done" from: last state was `enhancing` or `transcribing`, and `VoiceInkEngine` fires a paste-completion notification.
- 280ms: all three pieces flash green simultaneously.
- 800ms dwell: card shows "Pasted to \<AppName\>" in 11pt SF Pro Rounded + a one-line excerpt of the pasted text.
- Collapse: `collapse` spring, staggered as above.
- Paste target derived from `NSWorkspace.shared.frontmostApplication?.localizedName` at paste time (already available in the paste path — no new engine signal needed).

### 4.4 Failed State Detail

- Engine transitions to `idle` while an error flag is set. View layer detects error: set `HaloPhase` to `.failed` for 1.2s, then transition to `.hidden`.
- Orb: 6-keyframe x-offset shake `{−6, 6, −4, 4, −2, 0}` over 0.32s, then dwell amber for 1.2s.
- Chip: dot color = `Palette.warn`. Fades out with orb at 1.2s mark.
- Card: collapses immediately on shake (no content).

---

## 5. Surface-by-Surface Tickets

Shared context for all tickets:
- **Palette tokens** (all in `Palette.swift`): `recording #FF3B30`, `transcribe #5AC8FA`, `enhance #BF5AF2`, `success #30D158`, `warn #FF9F0A`, `neutral #8E8E93`.
- **Typography** (§6.1): Display = SF Pro Rounded semibold 17pt; Body = SF Pro Text regular 13pt; Mono = SF Mono 10pt all-caps tracking +0.12em.
- **AdaptiveGlassMaterial** (from T1): the refactored `HaloMaterial` supporting light/dark variants.
- **Animation springs** (§4.2): `expand` (0.38/0.78), `collapse` (0.42/1.00), `breathe` (1.60/0.95).
- Dependencies between tickets are listed per-ticket; read only your section.

---

### T1 — Recorder: Constellation

**Scope:** Replace the single HaloRecorderView + single panel with a three-window Constellation system. Also refactor `HaloMaterial` → `AdaptiveGlassMaterial`. This is the highest-blast-radius ticket.

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/Recorder/ConstellationWindowManager.swift` | Manages three panels (orb, chip, card) as a unit. Replaces per-mode window managers. | 200 |
| `VoiceInk/Views/Recorder/OrbPanel.swift` | `NSPanel` + hosting for the left orb. Screen-geometry to place it left of notch. | 80 |
| `VoiceInk/Views/Recorder/OrbView.swift` | Pulsing circle, audio-reactive radius, state-keyed color, glow shadow. | 90 |
| `VoiceInk/Views/Recorder/ChipPanel.swift` | `NSPanel` + hosting for the right chip. Screen-geometry to place it right of notch. | 70 |
| `VoiceInk/Views/Recorder/ChipView.swift` | Glass chip: provider mark + model short-name + state dot. Reuses `ProviderChip` internals. | 80 |
| `VoiceInk/Views/Recorder/CardPanel.swift` | `NSPanel` + hosting for the floating card. Drops below notch. | 90 |
| `VoiceInk/Views/Recorder/CardView.swift` | Glass card: phase-switched content (pulse ribbon → shimmer → enhancing identity → done). Hosts `StreamingCaretTranscript`. | 200 |
| `VoiceInk/Views/Recorder/WhisperView.swift` | Idle breath line: 60×2pt gradient capsule, 2.6s sine opacity, proximity fade. | 60 |

**Files to refactor:**
| File | Change | ~LOC delta |
|---|---|---|
| `HaloMaterial.swift` | Add `isDark` flag + Frost layer stack. Rename public surface to `AdaptiveGlassMaterial`. Keep `HaloMaterial` as a typealias or internal name. | +60 |
| `NotchWindowManager.swift` | Delegate to `ConstellationWindowManager`. Becomes a thin adapter or is deleted if callers migrate directly. | −60 |
| `MiniWindowManager.swift` | Same as above. | −60 |
| `HaloRecorderView.swift` | Keep for floating (non-notch) mode? Or delete and let `ConstellationWindowManager` handle both. Decision: **keep** `HaloRecorderView` as the content of `CardView` (the card panel renders HaloRecorderView internals in floating mode). Reduces delta. | minimal |

**Files to delete:**
- `NotchRecorderView.swift` (deleted in git status — already gone)
- `NotchRecorderView.swift` was already removed; `MiniRecorderView.swift` also deleted. Confirm no remaining callers via `grep`.
- `NotchShape.swift` (deleted in git status — already gone)

**Key components:**

*OrbView:* Circle, diameter 10pt baseline. Audio meter `recorder.audioMeter` (0.0–1.0) maps to diameter 10–16pt via `expand` spring. State color: `Palette.recording/transcribe/enhance/success/warn`. Glow: shadow matching state color at α from §3.5. Pulsing scale animation during `recording` (0.9–1.0, `breathe` spring but with 0.9s period). Hidden (opacity 0, scale 0.5) during idle.

*ChipView:* Glass chip using `AdaptiveGlassMaterial(RoundedRectangle(cornerRadius:8))`. Interior: 6pt state-dot (state color) + provider symbol (SF Symbol, 11pt) + model short label (SF Mono 9pt tracking 1.4). Width = content-driven, min 64pt. Appears/disappears with `expand`/`collapse` spring. During idle: `opacity(0)`.

*CardView:* `AdaptiveGlassMaterial` on a rounded rect (corner radii per §3.4). Phase-switched content:
- `recording`: `PulseRibbon` + `StreamingCaretTranscript` (from existing `HaloRecorderView`)
- `transcribing`: `TranscribingShimmer` + engine name
- `enhancing`: prompt icon + `EnhancingIdentity` label
- `done`: checkmark + "Pasted to \<App\>" + 1-line excerpt
- `failed`: hidden (collapse immediately)

Card drops from `y = notchBottom + 4` at `recording` entry using `expand` spring.

*WhisperView:* Capsule 60×2pt. `LinearGradient` horizontal: `clear → white@0.6 → clear`. Opacity animated between 0.35–0.85 on 2.6s easeInOut repeating. Cursor proximity: `NSEvent.addGlobalMonitorForEvents(.mouseMoved)` → compute distance from cursor to notch center → lerp opacity multiplier 1.0 (near) → 0.6 (far, >200pt). Lives in its own tiny panel (`level: .statusBar + 3`, not in any Constellation panel).

*ConstellationWindowManager:* Single entry point. Holds refs to `OrbPanel`, `ChipPanel`, `CardPanel`, `WhisperPanel`. Has `show(state:)` and `hide()`. On state change: updates phase on each hosted view, triggers ordered animations per §4.2 stagger. Owns `NotificationCenter` observation for `HideNotchRecorder`. Replaces `NotchWindowManager` and `MiniWindowManager` in `RecorderUIManager`.

**Screen geometry:**
- Notch left edge: `screen.frame.midX - notchWidth/2`
- Orb center: `(notchLeftEdge - 14)` from notch left, at notch vertical center
- Chip left edge: `notchRightEdge + 10` from notch right
- Card origin: `screen.frame.midX - cardWidth/2`, `screen.frame.maxY - notchHeight - cardHeight - 4`

**Success criteria:**
- [ ] idle → whisper breath line visible, orb/chip/card hidden
- [ ] recording → orb pulses red, chip shows provider+dot, card shows live transcript
- [ ] transcribing → orb cyan shimmer, card shows engine info + shimmer stripe
- [ ] enhancing → orb breathes violet, card shows prompt + model identity
- [ ] done → all three flash green 280ms, card shows "Pasted to \<App\>", then all collapse
- [ ] failed → orb shakes red + amber dwell 1.2s, chip amber dot, card hidden
- [ ] `AdaptiveGlassMaterial` switches light/dark on system appearance change
- [ ] no orphan windows after hide

**Dependencies:** none (T1 is the base).

---

### T2 — Menu Bar Dropdown

**Scope:** Replace the stock SwiftUI `Menu` + `Toggle` stack in `MenuBarView.swift` with a custom `NSPanel`-backed glass dropdown. State-aware: shows a mini orb mirror during active recording.

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| `VoiceInk/Views/MenuBarView.swift` | Gut the stock Menu body. Replace with a `MenuBarGlassView` hosted in a custom panel via `MenuBarPanelManager`. | −120, +40 |

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/MenuBar/MenuBarGlassView.swift` | Custom glass panel interior. Rows: toggle, ASR model chip, AI provider chip, prompt picker, quick actions. | 200 |
| `VoiceInk/Views/MenuBar/MenuBarPanelManager.swift` | `NSPanel` lifecycle for the dropdown. Shows on status item click. Auto-dismisses on click-outside. | 100 |

**Key components:**
- Panel: `NSPanel` with `AdaptiveGlassMaterial` background. `level = .popUpMenu`. `isMovable = false`. Animates in with `expand` spring (opacity + y-offset +8pt).
- **State mirror strip:** when engine state is `recording/transcribing/enhancing`, a compact 1-line strip at the top of the dropdown shows a miniature orb (6pt circle, state color) + state label ("Recording…", "Transcribing…", "Enhancing…"). Uses `Palette` tokens + SF Pro Rounded 12pt. Hidden during idle.
- **ASR model row:** `ProviderChip` variant for ASR (uses existing chip layout). Tap → popover with model list.
- **AI provider row:** `ProviderChip(provider:, model:, connected:)` — already exists in `ProviderChip.swift`. Tap → popover.
- **Prompt picker:** horizontal scroll of icon-only `ProviderChip`-style cards, one per prompt. Active = state-colored ring.
- **Quick actions:** "Open Settings", "History", "Quit" — SF Pro Rounded 13pt, no icons needed.

**Typography:** SF Pro Rounded semibold 13pt for row labels; SF Mono 10pt for model names; Palette accent for active states.

**Success criteria:**
- [ ] clicking status item shows glass panel with correct adaptive material
- [ ] active-state mirror strip appears during recording/transcribing/enhancing
- [ ] `ProviderChip` renders for both ASR and AI provider rows
- [ ] click-outside dismisses panel
- [ ] panel uses `expand`/`collapse` spring on show/hide

**Dependencies:** T1 (for `AdaptiveGlassMaterial`).

---

### T3 — Settings

**Scope:** Adopt `SettingsSectionHeader` everywhere (currently only in some sections). Wrap each section in a glass card. Replace remaining text pickers with visual cards. Add Power Mode horizontal strip. Typography pass.

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| `VoiceInk/Views/Settings/SettingsView.swift` | Adopt `SettingsSectionHeader` in all sections (currently ~6 of ~12 have it). Wrap `Section` content in `GlassCard`. Typography pass. | +150 |
| `VoiceInk/Views/Views/EnhancementSettingsView.swift` | Power Mode strip (§4.4 of UX_PROPOSAL). `ProviderChip` already present — verify full adoption. | +80 |
| `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` | Glass card wrapper. | +30 |

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/Settings/GlassCard.swift` | Reusable wrapper: `AdaptiveGlassMaterial` + `RoundedRectangle(cornerRadius:10)` + subtle inner stroke. Replaces plain `Section` background in Settings. | 60 |
| `VoiceInk/Views/Settings/PowerModeStrip.swift` | Horizontal `ScrollView` of 72×96pt cards. Each: emoji + name + active indicator. Drag-to-reorder (DnD pattern from existing prompt list). | 120 |

**Key components:**
- `GlassCard`: thin wrapper — pass content as `@ViewBuilder`. On dark: obsidian preset. On light: frost preset. Inner stroke `white@0.08` (dark) or `black@0.06` (light).
- `SettingsSectionHeader`: already complete in `Common/SettingsSectionHeader.swift`. Audit all sections and add missing headers. Reference color assignments: Shortcuts=indigo, Recording=`Palette.recording`, Power Mode=`Palette.warn`, Privacy=`Palette.success`, AI Enhancement=`Palette.enhance`, Appearance=`Palette.neutral`, Feedback/Sound=`Palette.transcribe`.
- Typography pass: all section title Text → SF Pro Rounded semibold 17pt; body rows → SF Pro Text 13pt; model/provider labels → SF Mono 10pt.
- `RecorderStylePicker` already built. Verify it still works with Constellation (cards now say "Constellation (Notch)" and "Constellation (Floating)").

**Success criteria:**
- [ ] every Settings section has a `SettingsSectionHeader`
- [ ] each section content is wrapped in a `GlassCard`
- [ ] Power Mode strip shows horizontal cards with active indicator
- [ ] `RecorderStylePicker` updated to Constellation terminology
- [ ] typography consistent across all sections
- [ ] light/dark material switches on appearance change

**Dependencies:** T1 (for `AdaptiveGlassMaterial`, `GlassCard`).

---

### T4 — Onboarding

**Scope:** Redesign the existing onboarding flow. Adopt glass surfaces. Add an animated state-cycle preview (idle→recording→transcribing→enhancing→done). Does not add a second onboarding — replaces the existing one.

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| Existing onboarding view(s) (locate via `hasCompletedOnboarding` grep) | Adopt `GlassCard` surfaces, `SettingsSectionHeader`-style hero headers, typography system. | varies |

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/Onboarding/StateCyclePreviewView.swift` | Animated mini Constellation demo: mini orb + mini chip + mini card, auto-cycles through all states with 1-line captions. 6-second loop, skippable. | 160 |

**Key components:**
- `StateCyclePreviewView`: uses `TimelineView(.animation)` to drive a `phase` enum through `idle → recording → transcribing → enhancing → done → idle`. Each step: 1.2s dwell. Miniature (50% scale) Orb + Chip + Card rendered as non-interactive previews. Captions in SF Pro Rounded 13pt below.
- Glass surfaces: each onboarding step / card → `GlassCard`. Backdrop uses macOS wallpaper blur (same `VisualEffectBlur` pattern from `HaloMaterial`).
- Reduce Motion: if `accessibilityReduceMotion`, `StateCyclePreviewView` shows a static composite of all three Constellation pieces instead of animating.

**Success criteria:**
- [ ] onboarding uses `GlassCard` throughout
- [ ] `StateCyclePreviewView` auto-cycles all 6 states
- [ ] each state shows orb + chip + card in miniature
- [ ] captions correct per state
- [ ] skippable; re-runnable from Help menu

**Dependencies:** T1 (glass material + Palette), T3 (GlassCard).

---

### T5 — History

**Scope:** Finish `TranscriptionListItem` polish (already partially done per `UX_IMPL_NOTES`). Redesign the detail view as a rich glass card: inline transcript + enhanced text + audio scrub.

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| `VoiceInk/Views/History/TranscriptionListItem.swift` | Audit and complete polish — `Palette` tokens already used; check typography + glass row background. | +30 |

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/History/TranscriptionDetailView.swift` | Full detail view: glass card, tabbed sections (Transcript / Enhanced / Audio), inline audio scrub bar, copy/share actions. | 220 |
| `VoiceInk/Views/History/AudioScrubBar.swift` | Playback scrub: waveform thumbnail (static PNG or bar sparkline) + elapsed/total label + play/pause. Palette accent for playhead. | 80 |

**Key components:**
- Detail view: `GlassCard` full-bleed. Header: date + duration + ASR model chip (compact `ProviderChip` variant). Body: tab bar (`Transcript` | `Enhanced` | `Audio`). Each tab scrollable.
- Transcript tab: SF Pro Text 14pt, `Palette.transcribe` for the title "Transcript".
- Enhanced tab: SF Pro Text 14pt, `Palette.enhance` for the title "Enhanced". If no enhancement: "No enhancement applied" in secondary.
- Audio tab: `AudioScrubBar` + waveform sparkline.
- List items: `GlassCard` row (subtle, low-opacity). State dot: `Palette.success` if enhanced, `Palette.neutral` if not.

**Success criteria:**
- [ ] list items polished — glass row, typography consistent
- [ ] tapping a list item opens detail view
- [ ] detail shows all three tabs
- [ ] audio scrub plays the original audio
- [ ] copy and share actions work from detail

**Dependencies:** T1 (GlassCard), T3 (GlassCard reuse).

---

### T6 — License View

**Scope:** Adopt `GlassCard` + `Palette` + typography. Smaller ticket — structural redesign, not feature work.

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| `VoiceInk/Views/LicenseManagementView.swift` | Wrap sections in `GlassCard`. Adopt typography system. Use `SettingsSectionHeader` for the license section title. `Palette.warn` for expiry warnings, `Palette.success` for active-license state. | +60 |

**Success criteria:**
- [ ] license page uses `GlassCard` + `SettingsSectionHeader`
- [ ] active/expiry states use `Palette` tokens
- [ ] typography consistent with rest of app

**Dependencies:** T1 (GlassCard), T3 (GlassCard reuse).

---

### T7 — AI Models / API Keys

**Scope:** Replace list-based provider view with a provider gallery (visual cards). Inline test-connection per provider. Model browser that loads when a provider is selected.

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| `VoiceInk/Views/AI Models/APIKeyManagementView.swift` | Replace list with `ProviderGallery` component. Add inline `TestConnectionButton`. | −80, +40 |

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/AIModels/ProviderGallery.swift` | Grid of provider cards. Each card: `ProviderChip` (full variant) + connection status dot + "Configure" button. Selection → expands `ModelBrowser` below. | 160 |
| `VoiceInk/Views/AIModels/ModelBrowser.swift` | List of models for the selected provider. Each row: model name (SF Mono), size hint, "Set as Default" button. Filtered by provider. | 120 |
| `VoiceInk/Views/AIModels/TestConnectionButton.swift` | Button that fires a lightweight ping (provider-specific health check). Shows `Palette.success` / `Palette.recording` indicator. 3s timeout. | 60 |

**Key components:**
- `ProviderGallery`: `LazyVGrid` with 3-column layout. Each card ~100×80pt. Uses `GlassCard` backing. `ProviderChip(provider:, model:, connected:)` inside. Selected card gets `Palette.enhance` border ring.
- `ModelBrowser`: appears below gallery as an expanding `GlassCard`. Scrollable list of models. Each row: SF Mono 10pt model name + a "✓ Default" badge if selected.
- API key input: stays as a `SecureField` — existing behavior. Move into a per-provider collapsible section under the card.

**Success criteria:**
- [ ] provider gallery shows all configured providers as cards
- [ ] selecting a provider expands `ModelBrowser`
- [ ] `TestConnectionButton` shows pass/fail within 3s
- [ ] API key entry still works per provider

**Dependencies:** T1 (GlassCard, AdaptiveGlassMaterial), T3 (GlassCard).

---

### T8 — Dictionary

**Scope:** Adopt glass surfaces. Add a rich entry editor with preview.

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| `VoiceInk/Views/Dictionary/DictionarySettingsView.swift` | Wrap list + editor in `GlassCard`. Typography pass. | +50 |

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/Dictionary/DictionaryEntryEditor.swift` | Inline rich editor: word input + pronunciation hint + example sentences. `GlassCard` backed. | 100 |

**Success criteria:**
- [ ] dictionary list uses `GlassCard` rows
- [ ] entry editor uses `GlassCard` + typography system
- [ ] add / delete / edit still works

**Dependencies:** T1 (GlassCard), T3 (GlassCard).

---

### T9 — Prompts Editor

**Scope:** Add inline preview of how a prompt transforms a sample transcript. Adopt glass surfaces.

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| `VoiceInk/Views/PromptEditorView.swift` | Add `PromptPreviewPane` below the editor. Adopt `GlassCard`. Typography pass. | +80 |

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/Prompts/PromptPreviewPane.swift` | Shows a hardcoded sample transcript (2–3 sentences, fixed). Below it, a "Preview →" button fires the active prompt against the sample via the configured AI provider (async). Renders result inline. Uses `Palette.enhance` for the "AI transformed" badge. | 120 |

**Key components:**
- Sample text: `"The quick meeting covered three topics: the roadmap, the budget, and next steps."` — hardcoded, not user-editable in the preview pane.
- Preview fires `aiService.enhance(text: sample, prompt: activePrompt)` → shows spinner (SF Symbol `progress.indicator`) during flight → renders result in `GlassCard` with `Palette.enhance` left-border accent.
- If no provider configured: shows "Configure a provider in AI Models to preview." in secondary.

**Success criteria:**
- [ ] prompt editor has a preview pane
- [ ] preview fires against sample text and shows result
- [ ] loading state visible during enhancement
- [ ] glass card styling consistent with rest of app

**Dependencies:** T1 (GlassCard), T7 (AI provider must be configured for preview to fire).

---

### T10 — Animated Menu Bar Icon

**Scope:** Replace static `NSStatusItem` icon with a state-driven animated icon.

**Files to create:**
| File | Purpose | ~LOC |
|---|---|---|
| `VoiceInk/Views/MenuBar/AnimatedMenuBarIcon.swift` | State-driven icon renderer. Uses `CADisplayLink` + `NSImage` drawing for frame-by-frame animation. | 140 |

**Files to edit:**
| File | Change | ~LOC delta |
|---|---|---|
| Wherever `NSStatusItem.button.image` is set (locate via grep) | Replace static image set with `AnimatedMenuBarIcon.start(state:)` call. | +20 |

**Icon states and descriptions:**

| State | Icon behavior |
|---|---|
| idle | Static waveform glyph (SF Symbol `waveform`, 14pt, `NSColor.controlTextColor`) |
| recording | Pulsing filled circle (red, 8pt) centered in the 18×18 icon area. Pulse: scale 0.8↔1.0, 0.9s easeInOut repeat |
| transcribing | Shimmer sweep across the waveform glyph — achieved via a `CAGradientLayer` mask moving left→right at 1.4s period |
| enhancing | Waveform glyph with a superimposed `sparkles` SF Symbol at 70% opacity, slow fade 0.8↔1.0, 1.8s |

**Implementation note:** `NSStatusItem.button.image` swap at 30fps is the simplest path. Draw each frame to `NSImage` using `NSBezierPath` + `NSColor`. Avoid `NSImageView.layer` animation — SwiftUI hosting in the status item is unreliable at this level.

**Reduce Motion:** if `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`, stay static per state (no animation, just show the state-specific glyph).

**Success criteria:**
- [ ] idle shows static waveform
- [ ] recording shows pulsing red dot
- [ ] transcribing shows shimmer on waveform
- [ ] enhancing shows sparkles overlay
- [ ] reduce motion disables animation

**Dependencies:** T1 (state machine / `HaloPhase` or equivalent enum exposed to the icon).

---

### T11 — Sound Design

**Scope:** Asset production task. Five bespoke audio cues. Not a code ticket — requires audio production and then wiring into `SoundManager`.

**Files to create (assets):**
- `VoiceInk/Resources/Sounds/vk-record-start.aiff` — 880Hz pluck, 90ms attack, 140ms decay, 6th-tuned. ≤300ms total.
- `VoiceInk/Resources/Sounds/vk-record-stop.aiff` — descending two-note (A→E), soft, ≤220ms.
- `VoiceInk/Resources/Sounds/vk-transcribe-complete.aiff` — 4-note ascending arpeggio C-E-G-B, ≤220ms.
- `VoiceInk/Resources/Sounds/vk-enhance-complete.aiff` — same arpeggio transposed up a 4th, slightly softer, ≤220ms.
- `VoiceInk/Resources/Sounds/vk-cancel.aiff` — descending two-note (A→E), dimmer than stop, ≤180ms.

**Wiring (code):**

| File | Change | ~LOC delta |
|---|---|---|
| `SoundManager.swift` (or equivalent — locate via grep) | Add five new sound IDs. Wire `play(.recordStart)` etc. at the correct state-transition callsites. | +40 |

**Notes:**
- `CustomSoundSettingsView` (already exists) allows user replacement — ensure new sound IDs are surfaced there.
- All cues: ≤300ms, curated not stock. Production tools: Logic Pro / Garage Band / or commissioned samples.
- Do not block T1–T10 on this — sounds can be added as a final pass.

**Success criteria:**
- [ ] five sound files present in bundle
- [ ] each fires at the correct state transition
- [ ] user can replace each in `CustomSoundSettingsView`

**Dependencies:** T1 (state machine transitions to hook).

---

## 6. Cross-Cutting Concerns

### 6.1 Typography System

Three voices, three sizes, three weights. No sprawl beyond.

| Role | Font | Size | Weight | Tracking | Use |
|---|---|---|---|---|---|
| Display | SF Pro Rounded | 17pt | Semibold | default | Section headers, recorder card titles |
| Body | SF Pro Text | 13pt | Regular | default | Settings rows, list items, card body |
| Mono | SF Mono | 10pt | Medium | +0.12em (≈1.4 kerning units) | Model names, provider IDs, shortcuts |

Apply via `ViewModifier` or `Font` extension to keep call sites consistent:
```
.font(.system(size: 17, weight: .semibold, design: .rounded))  // Display
.font(.system(size: 13, weight: .regular))                     // Body
.font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.4)  // Mono
```

### 6.2 Wallpaper Analysis (v2)

For v1, `isDarkMaterial` = `colorScheme == .dark` from SwiftUI environment. Wallpaper luma analysis (sample center pixel via `CGWindowListCreateImage` + luminance threshold) is deferred to v2. The `AdaptiveGlassMaterial` API is designed so the picker can be swapped — just change what drives `isDark`.

### 6.3 Accessibility

- **Reduce Motion** (`accessibilityReduceMotion`): All `withAnimation` calls check this. On true: orb/chip/card appear/disappear without scale/spring animations. `StateCyclePreviewView` shows static. `AnimatedMenuBarIcon` shows static per-state glyph.
- **High Contrast** (`accessibilityHighContrast` or `colorSchemeContrast == .increased`): Inner strokes thicken to 1pt; glow shadows reduce opacity by 50%; `Palette` token values themselves stay — they're already distinct.
- **VoiceOver:** Orb, chip, and card panels are `NSPanel` — they're excluded from the accessibility element tree by default (non-activating panels). Confirm `.accessibilityElement(children: .ignore)` is set. The menu bar dropdown (`T2`) must be fully VoiceOver-navigable.
- **Dynamic Type:** Not applicable (macOS). Font sizes are fixed per §6.1.

### 6.4 Failure State Propagation

**Decision for v1: view-layer derivation only.** `VoiceInkEngine` already transitions to `.idle` on error. The view layer will watch for error flag at the transition callsite. `RecorderStateProvider` gets one new property: `var lastError: RecorderError? { get }`. View reads it when `recordingState == .idle` post-transition. This is the minimum blast-radius approach — `VoiceInkEngine` internals untouched.

Engine signals (`publishedFailureReason`, etc.) are v2.

### 6.5 Multi-Display

For v1: Constellation anchors to `NSScreen.main`. On multi-display: the orb/chip/card appear on whatever screen contains the menu bar, which is `NSScreen.main`. Known limitation: if the focused app is on a secondary display, the done-state "Pasted to \<App\>" card still appears on main screen. This is acceptable for v1. Multi-display smarts (anchor to focused app's screen) are v2.

### 6.6 Notch vs. No-Notch

- MacBook with notch: `screen.safeAreaInsets.top > 0`. Orb and chip place relative to physical notch geometry (`auxiliaryTopLeft/RightArea`). Card drops below notch.
- MacBook without notch / external display: no notch. Orb and chip place at top-center pill positions (floating mode). Card drops below menu bar. `WhisperView` centers at top-center.
- `ConstellationWindowManager` detects this at init via `NotchRecorderPanel.calculateWindowMetrics()` geometry — same detection already used.

---

## 7. Migration / Backwards Compatibility

### v1 Files → Disposition

| File | Disposition | Notes |
|---|---|---|
| `Palette.swift` | **Keep as-is** | No changes needed. Add light-variant tokens if Frost needs different values (unlikely — alpha is adjusted at use-site). |
| `HaloMaterial.swift` | **Refactor** → `AdaptiveGlassMaterial` | Add `isDark` flag, Frost layer stack. Public API renamed. Old `HaloMaterial` struct becomes internal or typealias. |
| `HaloShape.swift` | **Keep as-is** | Orb uses `Circle()`, not `HaloShape`. Chip and card use `RoundedRectangle`. `HaloShape` retained for `CardView` floating mode (matches existing pill geometry). |
| `HaloRecorderView.swift` | **Refactor** | Internals (PulseRibbon, StreamingCaretTranscript, EnhancingIdentity, etc.) move into `CardView`. `HaloRecorderView` may be retained as a thin entry point for the card's content or deleted if `CardView` absorbs it entirely. Defer final call to T1 coder. |
| `PulseRibbon.swift` | **Keep** | Reused inside `CardView` for recording state. |
| `ProviderChip.swift` | **Keep** | Reused in `ChipView`, `MenuBarGlassView`, `ProviderGallery`, everywhere. |
| `SettingsSectionHeader.swift` | **Keep** | Adopted in more sections (T3). |
| `RecorderStylePicker.swift` | **Keep, minor edit** | Update card labels to "Constellation (Notch)" / "Constellation (Floating)". |
| `NotchWindowManager.swift` | **Delete or thin adapter** | `ConstellationWindowManager` replaces it. Any remaining callers in `RecorderUIManager` must migrate. |
| `MiniWindowManager.swift` | **Delete or thin adapter** | Same. |
| `NotchRecorderPanel.swift` | **Keep** | `OrbPanel` / `ChipPanel` / `CardPanel` follow its pattern. Or extract a `ConstellationPanel` base class. |
| `MiniRecorderPanel.swift` | **Keep** | `CardPanel` for floating mode follows its metrics pattern. |
| `NotchRecorderView.swift` | **Already deleted** | Confirmed in git status. |
| `MiniRecorderView.swift` | **Already deleted** | Confirmed in git status. |
| `NotchShape.swift` | **Already deleted** | Confirmed in git status. |
| `RecorderStateProvider.swift` | **Minor edit** | Add `var lastError: RecorderError? { get }` (§6.4). |

---

## 8. Out of Scope (v2)

Per the locked decisions, these are explicitly deferred:

- **Idle Ambient Mode** (UX_PROPOSAL §6.4) — persistent glow line when armed but not recording. Whisper is idle-only; ambient mode adds an always-visible cue. Deferred.
- **Highlight Reel** (§6.6) — post-recording partial-transcript fast-forward. Deferred.
- **Multi-Display Smarts** (§6.7) — anchor to focused app's screen. v1 uses `NSScreen.main`. Deferred.
- **Haptics-Adjacent Visual Feedback** (§6.3) — scale pulses at sentence commits. Off by default, not implemented in v1.
- **Wallpaper-based material picking** — luma analysis of desktop wallpaper for auto Frost/Onyx. v1 uses system appearance only. Deferred.
- **Engine-side failure signals** — `VoiceInkEngine` publishing a typed `RecorderError` reason. v1 derives at view layer. Deferred.
- **Halo theming presets** (§6.2 — Obsidian / Frost / Aurora / Mono user-selectable) — v1 auto-picks. User presets are v2.

---

## 9. Open Questions

Items that need answers before implementation starts. Flag to the user / lead agent.

1. **`RecordingState` error signal.** `VoiceInkEngine` currently transitions to `.idle` on failure with no typed error. Where exactly in `VoiceInkEngine.swift` does this happen? Confirm that adding `var lastError: RecorderError?` to `RecorderStateProvider` (computed from engine state) is safe without touching the engine's internal state machine. If the engine does publish an error today via a different mechanism (publisher, notification), use that instead.

2. **Paste completion notification.** The "done" state needs to know when paste completes and which app was pasted to. Is there already a `NotificationCenter` post at the paste callsite? If not, which file handles paste — `VoiceInkEngine`, a paste manager, or the mini recorder shortcut handler? Confirm the callsite before T1 implements done-state triggering.

3. **`RecorderUIManager` shape.** `ConstellationWindowManager` replaces both `NotchWindowManager` and `MiniWindowManager`. Does `RecorderUIManager` hold refs to both, or just one at a time? What's the swap mechanism when the user changes recorder style in Settings? Confirm before T1 refactors.

4. **`AIService.currentModel` type.** `EnhancingIdentity` uses `aiService.currentModel` (a `String`). For the right Chip in Constellation, the chip needs model + provider at all non-idle states, not just enhancing. Is `aiService.selectedProvider` always non-nil when the engine is in `recording` / `transcribing` state (i.e., is a provider always selected even when enhancement is disabled)? Confirm to avoid chip showing a stale or nil provider.

5. **`PowerModeManager.configurations` shape.** `PowerModeStrip` (T3) needs to enumerate configured power modes and support drag-to-reorder. Confirm the existing DnD pattern (referenced as "already exists for prompts") works for power modes too — or if power modes lack a stable ID / ordering mechanism.

6. **`SoundManager` interface.** T11 wires five new sounds. What's the current `SoundManager` API surface — does it take string sound names, enum cases, or file URLs? Locate `SoundManager.swift` before T11 to avoid API mismatch.

7. **On-device ASR + MLX provider simultaneously.** The `ProviderChip` on the right chip shows the AI enhancement provider. If enhancement is disabled, what should the chip show? Options: (a) hide chip entirely during non-enhancing states; (b) show ASR model chip instead; (c) show a neutral "no enhancement" chip. Decide before T1 implements chip content logic.

8. **Notch geometry on external displays.** When a MacBook is closed (lid closed, external display only), `NSScreen.main` changes to the external display. That display has no notch. `ConstellationWindowManager` must handle this gracefully (switch to floating mode). Confirm that `calculateWindowMetrics()` detection (`safeAreaInsets.top > 0`) already covers this correctly or needs an update.
