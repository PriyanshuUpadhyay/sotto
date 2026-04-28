# VoiceInk App-Wide Visual Redesign — Design Spec

**Date:** 2026-04-28
**Branch:** `priyanshu/embedded-llm`
**Status:** Proposed — awaiting user sign-off (visual mockups already approved in brainstorm 22968-1777317412)
**Scope:** Total — every user-facing surface
**Predecessors:**
- `docs/UX_PROPOSAL.md` — original "Halo" recorder proposal (partially landed; basis for typography + palette)
- `docs/UX_IMPL_NOTES.md` — what landed in v1, deferred items, palette rationale
**Approved mockups:**
- `.superpowers/brainstorm/22968-1777317412/content/visual-direction.html` — material lane (Adaptive Glass)
- `.superpowers/brainstorm/22968-1777317412/content/notch-concepts-v2.html` — Constellation
- `.superpowers/brainstorm/22968-1777317412/content/idle-state.html` — Whisper
- `.superpowers/brainstorm/22968-1777317412/content/state-cycle.html` — five-state grammar
- `.superpowers/brainstorm/22968-1777317412/content/scope.html` — Total scope (option C)

---

## 1. Summary

VoiceInk's visual identity gets one cohesive language across all surfaces.

- Material vocabulary: **Adaptive Glass** — light variant on bright wallpapers, onyx on dark. Glass everywhere — recorder, menu bar dropdown, settings cards, onboarding, history rows, license card.
- Recorder geometry: **Constellation** — single Halo pill replaced by three discrete satellites (state orb, provider chip, floating glass card).
- Idle: **Whisper** — 60×2pt ambient breath line below notch. Hover-aware.
- State grammar: five named states (idle / recording / transcribing / enhancing / done), plus `failed`. Color-keyed across orb + chip + card. Three named springs for motion.
- Sound: 5 bespoke audio cues replacing system sounds.
- Menu bar icon: state-driven swap (idle/recording/transcribing/enhancing).

Boldness brief from user: "Constellation is sexy" — embrace distinctive identity, no half-measures, no trend-chasing. Commit to the language.

---

## 2. Foundations

### 2.1 Palette

No change. 6 tokens from `VoiceInk/Views/Common/Palette.swift`:

| Token | Hex | Use |
|---|---|---|
| `recording` | `#FF3B30` | record orb, halo glow, recording-state chip dot |
| `transcribe` | `#5AC8FA` | transcribe orb, shimmer sweep |
| `enhance` | `#BF5AF2` | enhance orb, breathe glow |
| `success` | `#30D158` | done flash, connected-state dot |
| `warn` | `#FF9F0A` | failure dwell amber, Power Mode icon |
| `neutral` | `#8E8E93` | idle baseline, unselected |

Alpha applied at use site. `HaloIntensity` enum (soft 0.18 / medium 0.22 / strong 0.28) covers most cases. Rationale already documented in `UX_IMPL_NOTES.md` §4 — don't duplicate.

### 2.2 Typography

Three voices. Pinned, do not sprawl.

- **Display** — `SF Pro Rounded`, semibold, 17pt. Section headers, recorder card titles, hero labels.
- **Body** — `SF Pro Text`, regular, 13pt. Settings labels, transcript text, history rows.
- **Mono identity** — `SF Mono`, medium, 9–10pt, all-caps, tracked +0.12em (≈1.4 in SwiftUI `tracking`). Provider/model identifiers, ASR engine names, license keys.

One additional weight for emphasis only: Display 14pt semibold for sub-section headers inside settings cards.

### 2.3 Adaptive Glass material

Two variants. App auto-picks. Detection method (see §6.1) decides between them per-surface.

#### Onyx Glass (dark variant — default for recorder, dark-mode surfaces)

Layer stack (bottom → top):
1. `NSVisualEffectView` — `.hudWindow` material, `.behindWindow` blending, `.darkAqua` appearance. Already implemented in `HaloMaterial.VisualEffectBlur`.
2. Translucent obsidian fill — `Color.black @ 0.78` (current value, holds).
3. Inner top gloss — 1.5pt linear gradient, `white@0.30 → transparent`, only on top edge. Existing implementation uses 1pt @ 0.06 — bump to 1.5pt @ 0.30 per mockup (see `notch-concepts-v2.html` `.drop-body::before`).
4. Inner stroke — 0.5pt `white@0.16` (currently 0.08, raise per mockup).
5. Subtle bottom inner stroke — 0.5pt `white@0.05` for depth cue (new).
6. Inner sheen (enhancing only) — radial violet, blendMode `.plusLighter`. Existing.
7. State-keyed outer halo — 24px blur, color from `HaloPhase.glowColor`, alpha from `HaloPhase.glowAlpha`. Existing.
8. Soft black drop shadow — 14px blur, offset (0, 6), `black@0.45`. Existing.

#### Light Glass (light variant — settings on bright system appearance, light-mode surfaces)

Layer stack:
1. `NSVisualEffectView` — `.hudWindow` / `.behindWindow` / `.aqua`.
2. Translucent fill — `white @ 0.32`.
3. Inner top gloss — 1.5pt linear gradient `white@0.70 → white@0.18`.
4. Inner stroke — 0.5pt `white@0.55`.
5. Subtle bottom inner stroke — 0.5pt `white@0.18`.
6. State-keyed outer halo — same 24px blur, color-keyed, alpha 0.20–0.32.
7. Soft black drop shadow — 24px blur, offset (0, 8), `black@0.18`.

#### Backdrop filter equivalence

`backdrop-filter: blur(20-28px) saturate(1.4)` from mockups maps to `NSVisualEffectView` material `.hudWindow` — its blur radius is fixed by the system (~22px). Saturation lift is achieved via `isEmphasized = false` plus an optional CIFilter overlay (`CIColorControls` saturation 1.4) on the layer. Not strictly required for v1 — `.hudWindow` saturation reads close enough.

#### Fallback

If `NSVisualEffectView` blur fails to composite (rare; some virtual displays, screen recording artifacts), the translucent fill + inner gloss + stroke still produce a recognizable glass silhouette. No additional code path needed — this is what current `HaloMaterial` already does.

### 2.4 Animation grammar

Three named springs. Use only these. No ad-hoc `easeInOut` durations except where listed.

```
expand   = spring(response: 0.38, dampingFraction: 0.78)   // expand, reveal, morph-up
collapse = spring(response: 0.42, dampingFraction: 1.00)   // contract, dismiss, morph-down
breathe  = easeInOut(duration: 1.6).repeatForever(autoreverses: true)   // enhancing
```

Plus four specials (limited use):

- **Shimmer** — 1.6s `TimelineView(.animation)` sampling phase. Sweeps gradient L→R across cards/strokes during transcribing.
- **Shake** — keyframe x-offset `{-6, 6, -4, 4, -2, 0}` over 0.32s. Failure state.
- **Pulse** — `scale 1.0 → 1.18 → 1.0` over 1.0s, eased, repeating. Recording orb.
- **Breath-orb** — `scale 1.0 → 1.15 → 1.0` over 1.6s. Enhancing orb.

Phase crossfade — 0.22s `easeInOut`, opacity + `scale 0.96 → 1.0`. Used for orb color crossfades and card content swap between phases.

Sequencing — when a state expands the constellation (idle → recording), satellites stagger:
- t=0.00: orb fades in + scales from 0.85 → 1.0
- t=0.06: chip fades in
- t=0.09: card drops in (translateY -8 → 0)

Collapse reverses with `collapse` spring.

### 2.5 Iconography

SF Symbols only. No custom iconography in v1.

Section icons keyed to palette tokens:
- Recording → `mic.fill` on `recording` tint
- Shortcuts → `command` on `enhance` tint
- Power Mode → `bolt.fill` on `warn` tint
- Privacy → `lock.fill` on `success` tint
- AI → `sparkles` on `enhance` tint
- Audio → `waveform` on `transcribe` tint
- Dictionary → `book.closed.fill` on `transcribe` tint
- License → `key.fill` on `warn` tint

State icons (card content):
- transcribing → `waveform.badge.magnifyingglass`
- enhancing → active prompt's icon (already in `enhancementService.activePrompt.icon`)
- done → `checkmark.circle.fill`
- failed → `exclamationmark.triangle.fill`

---

## 3. Per-surface specs

### 3.1 Recorder — Constellation

**Goal:** replace single-pill Halo with three discrete glass satellites. Each piece does one job. Cinematic, alive, uniquely VoiceInk.

**Layout (notched display):**

```
   ┌─ menu bar ──────────────────────────────────┐
   │  [orb 16x16]    ⎡ physical notch ⎤  [chip] │   ← satellites at notch row
   │                                              │
   │            ╭────────────────────╮            │   ← floating glass card
   │            │   <state content>  │            │     280pt × min 56pt
   │            ╰────────────────────╯            │
   │                                              │
   │       (whisper line on idle only)            │
   └──────────────────────────────────────────────┘
```

**Layout (non-notched / external display):** same three-piece composition centered horizontally at `visibleFrame.maxY - padding`. Orb + chip flank a virtual notch (24pt gap) so the shape is recognizable without a physical notch.

**Components (all new, replace `HaloRecorderView` interior):**

- `ConstellationOrb` — 16×16 circle. State-driven fill + glow shadow (14px inner, 28px outer). Recording = pulse 1.0s; transcribing = shimmer (opacity 0.55↔1.0, 1.4s); enhancing = breath-orb (scale 1.0↔1.15, 1.6s); done = static green for 280ms then fade; failed = shake then 1.2s amber dwell. Outer 1.5pt `white@0.25` ring (from mockup `.const-orb::after`). Audio-meter modulation: orb radius +/-1pt with `recorder.audioMeter` during recording (subtle, scaled).

- `ConstellationChip` — glass capsule, ~20pt height × intrinsic width, 10pt corner radius. Contains: 5pt color dot (mirrors orb state) + 9pt mono provider name (CLAUDE / OPENAI / MLX). Outer halo box-shadow color-keyed to state (alpha 0.30–0.40). Visible during recording / transcribing / enhancing / done. Hidden during idle.

- `ConstellationCard` — Adaptive Glass surface, 280pt wide, min 56pt tall, 22pt corner radius. State-driven content (see §3.1 phase content table). Card itself breathes during enhancing (`scale 1.0 ↔ 1.012`, 1.6s). Crossfades content with 0.22s opacity + scale 0.96→1 between phases. Drops in from top with `translateY -8 → 0` on appear; exits with collapse spring.

**Phase content table:**

| Phase | Card content | Card motion | Orb | Chip |
|---|---|---|---|---|
| idle | hidden | — | hidden | hidden |
| recording | live transcript (existing `StreamingCaretTranscript`) + blinking caret | static | red, pulse 1.0s | red dot |
| transcribing | `[icon] Transcribing\nWHISPER · LARGE-V3` | cyan shimmer sweep across card every 1.6s | cyan, shimmer | cyan dot |
| enhancing | `[prompt-icon] Enhancing with <prompt name>\nCLAUDE · SONNET-4-6` | breath scale 1.0↔1.012, 1.6s | violet, breath-orb | violet dot |
| done | `✓ Pasted to <app>\n"<1-line preview>"` (italic) | static, 280ms–1s dwell | green flash 280ms | green dot |
| failed | `! Transcription failed` / `! Enhancement failed` + brief recovery hint | static | red shake → amber dwell 1.2s | red dot |

**Idle (Whisper):**

- 60×2pt gradient line, `white@0 → white@0.5 → white@0` horizontal, 8px `white@0.35` glow shadow.
- 2.6s sine breath: opacity 0.35 → 0.85, `scaleX 0.85 → 1.0`.
- Hover-aware: `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` on a 30Hz throttled timer. Distance from cursor to menu bar baseline (`screen.frame.height - cursor.y`):
  - distance > 200pt → opacity multiplier 0
  - 200pt ≥ distance > 60pt → linear ramp 0 → 1
  - distance ≤ 60pt → opacity multiplier 1

**Panel infrastructure (keep, do not rewrite):**

- `NotchRecorderPanel` / `MiniRecorderPanel` stay. Shape becomes irrelevant — the constellation pieces don't share a single silhouette.
- Three sub-panels OR one panel with three SwiftUI views in a `ZStack` anchored absolutely. **Decision:** one panel, three sub-views. Cheaper. Panel size = full top strip (screen-width × ~120pt). Hit-test passthrough except on the three satellite frames.

**Files to touch:**
- New: `VoiceInk/Views/Recorder/Constellation/ConstellationOrb.swift` (~120 LOC)
- New: `VoiceInk/Views/Recorder/Constellation/ConstellationChip.swift` (~110 LOC)
- New: `VoiceInk/Views/Recorder/Constellation/ConstellationCard.swift` (~260 LOC)
- New: `VoiceInk/Views/Recorder/Constellation/WhisperLine.swift` (~80 LOC)
- New: `VoiceInk/Views/Recorder/Constellation/ConstellationContainer.swift` (~140 LOC) — orchestrator
- Edit: `VoiceInk/Views/Recorder/HaloRecorderView.swift` — gut interior, delegate to `ConstellationContainer`. Keep file as adapter (~50 LOC down from 580).
- Edit: `VoiceInk/Views/Recorder/NotchRecorderPanel.swift`, `MiniRecorderPanel.swift` — frame sizing for full top strip (~30 LOC each).
- Edit: `VoiceInk/Views/Recorder/RecorderStateProvider.swift` — extend with `displayPhase: HaloPhase` that includes `.done` and `.failed`. Engine signal mapping (~40 LOC).
- New: `VoiceInk/Views/Recorder/CursorProximityMonitor.swift` (~80 LOC) — hover-aware whisper.

### 3.2 Menu Bar dropdown

**Goal:** replace stock SwiftUI `Menu` / `Toggle` chrome with a custom Adaptive Glass popover. Quick controls without diving into Settings.

**Layout:** ~360pt wide × ~420pt tall popover, glass material, 16pt corner radius.

```
╭─ glass card (Adaptive) ────────────────────╮
│ [VoiceInk wordmark] · [v1.x.x mono]        │
│                                              │
│ ┌─ Models ──────────────────────────────┐ │
│ │ TRANSCRIPTION                            │ │
│ │ [ProviderChip: WHISPER · LARGE-V3]       │ │
│ │ ENHANCEMENT                              │ │
│ │ [ProviderChip: CLAUDE · SONNET-4-6]      │ │
│ └─────────────────────────────────────────┘ │
│                                              │
│ AI ENHANCEMENT  [glass switch ●━━━━━]       │
│                                              │
│ PROMPT                                      │
│ ┌──┐ ┌──┐ ┌──┐ ┌──┐  ← horizontal chips    │
│ │📝│ │💬│ │🔧│ │✦│                        │
│ └──┘ └──┘ └──┘ └──┘                        │
│                                              │
│ RECENT                                      │
│ • "the dynamic island feels great"          │
│ • "remind me to email the team"             │
│                                              │
│ [Settings] [Quit]                           │
╰────────────────────────────────────────────╯
```

**Components:**
- Glass switch — replace `Toggle` with custom — 36×20pt capsule, knob 16pt, accent on. Animates with `expand` spring.
- Prompt chips — horizontal `ScrollView`, 56×56pt rounded squares, prompt icon centered, glass background, selection ring in `enhance` tint.
- Recent transcriptions — pulled from `LastTranscriptionService`. 2 most recent, italic 12pt, truncated to 1 line.

**Motion:** popover appears with `expand` spring, scale 0.96 → 1.0 + opacity 0 → 1, 0.32s.

**Files:**
- Edit: `VoiceInk/Views/MenuBarView.swift` — full rewrite (~400 LOC up from current ~150).
- New: `VoiceInk/Views/Common/GlassCard.swift` (~100 LOC) — reusable glass surface (used here + Settings + License).
- New: `VoiceInk/Views/Common/GlassSwitch.swift` (~80 LOC).
- New: `VoiceInk/Views/Common/PromptChipPicker.swift` (~120 LOC).

### 3.3 Settings View

**Goal:** sectioned glass cards. Each section becomes a glass island. Rich row components inside.

**Layout:** sidebar unchanged. Right pane = scrollable stack of glass cards, each containing one logical section.

```
[sidebar]   ┌─ glass card ────────────────────────────╮
            │ [icon tile] Recording                    │
            │ Trigger and capture audio.               │
            │ ────────────────────────────             │
            │ [icon] Hotkey               [⌘⇧V] [edit]│
            │ [icon] Pause media          [switch]     │
            │ [icon] Mute system mic      [switch]     │
            ╰──────────────────────────────────────────╯

            ┌─ glass card ────────────────────────────╮
            │ [icon tile] AI Enhancement               │
            │ Shape transcripts with prompts + LLMs.   │
            │ ...                                       │
```

**Components:**
- `SettingsCard` — wraps `Section { ... }`. Glass material. 14pt internal padding. Adaptive variant.
- `SettingsRow` — replaces `LabeledContent`. Layout: `[16pt icon tile] [label + optional 11pt subtitle] [spacer] [control]`. Icon tile uses section accent.
- Keyboard shortcut display — rich key cap rendering. Each key as 24×24 mono glass cap with key glyph (e.g. `⌘`, `⇧`, `V`). Caps separated by 4pt spacing.
- Recorder Style picker — already exists (`RecorderStylePicker.swift`). Extend with a third "preview" of the Constellation orb so users see what they're picking. (Currently shows two cards — Halo top vs. Mini.)

**Motion:** card hover-lift — 4pt translate-y on hover, 0.18s ease. Selection ring on focused card in `accent` palette token.

**Files:**
- Edit: `VoiceInk/Views/Settings/SettingsView.swift` — wrap each `Section` in `SettingsCard` (~180 LOC of edits).
- New: `VoiceInk/Views/Common/SettingsCard.swift` (~80 LOC).
- New: `VoiceInk/Views/Common/SettingsRow.swift` (~110 LOC).
- New: `VoiceInk/Views/Common/KeyCapView.swift` (~70 LOC).
- Edit: `VoiceInk/Views/Settings/RecorderStylePicker.swift` — add Constellation preview tile (~40 LOC).

### 3.4 Onboarding flow

**Goal:** cinematic walkthrough showing the constellation in action. Replaces the current text-step onboarding pages.

**Sequence (auto-plays once on first launch):**
1. **Welcome** (1.5s) — wordmark fades in, whisper line breathes below.
2. **Record** (1.5s) — orb fades in red, pulses; card drops in with placeholder transcript building character-by-character.
3. **Transcribe** (1.5s) — orb morphs to cyan; card content swaps to "Transcribing WHISPER · LARGE-V3" with shimmer.
4. **Enhance** (1.5s) — orb morphs to violet; card swaps to "Enhancing with Default Mode CLAUDE · SONNET-4-6"; breathes.
5. **Done** (0.5s) — orb flashes green; card shows "Pasted to Notes — '...'".
6. **Caption layer** — one-line caption fades in/out per stage: "Press hotkey to record" / "AI transcribes locally or in cloud" / "Enhancement shapes the result" / "Pasted automatically into the focused app".

Total: 6.5s. Skippable. Re-runnable from `Help → Show Tutorial`.

**Layout:** full-screen overlay during first-launch. Glass card panel hosting the animation, ~600×320pt centered.

**Existing onboarding views (keep, refresh):**
- `OnboardingView.swift` — wrap in glass card, replace stock backgrounds.
- `OnboardingPermissionsView.swift` — each permission becomes a glass-card row with icon tile + status pill (granted = success, pending = warn).
- `OnboardingModelDownloadView.swift` — model picker as glass cards (one per model), download progress as a horizontal glass progress bar.
- `OnboardingTutorialView.swift` — wraps the new cinematic walkthrough.

**Files:**
- New: `VoiceInk/Views/Onboarding/CinematicWalkthrough.swift` (~280 LOC).
- Edit: existing 4 onboarding files (~80 LOC each = ~320 LOC).

### 3.5 History — list + detail

**Goal:** list rows already polished (`TranscriptionListItem.swift`). Detail view is stock SwiftUI — needs glass card + provider chip header + audio playback timeline.

**List:** keep current row treatment. Apply glass material to row backgrounds (alternating light/dark variant). Hover-lift micro-animation.

**Detail (`TranscriptionDetailView.swift`):**
```
┌─ glass card ────────────────────────────────────────╮
│ [thumbnail/waveform]   2026-04-28 · 11:42           │
│ [ProviderChip: CLAUDE]   2:14 duration              │
│                                                       │
│ ────────────────────────────                         │
│  ▶ ━━━━━━━━━●━━━━━━━━━━━  0:32 / 2:14               │
│                                                       │
│ Original                                              │
│ "umm so the dynamic island feels great…"             │
│                                                       │
│ Enhanced                                              │
│ "The dynamic island feels great."                    │
│                                                       │
│ [Copy] [Re-enhance] [Delete]                         │
╰─────────────────────────────────────────────────────╯
```

**Components:**
- Audio timeline — custom waveform render + scrubbable progress.
- Original vs Enhanced — side-by-side or stacked, with diff highlighting (later).
- Provider chip — reuse `ProviderChip`.

**Files:**
- Edit: `VoiceInk/Views/History/TranscriptionDetailView.swift` (~200 LOC of edits).
- Edit: `VoiceInk/Views/History/TranscriptionHistoryView.swift` — apply glass to list container (~30 LOC).
- New: `VoiceInk/Views/History/AudioTimelineView.swift` (~150 LOC).

### 3.6 License view

**Goal:** plain `Form` becomes a hero card.

**Layout:**
```
┌─ glass card (large) ──────────────────────────────╮
│           [hero illustration: glowing key]         │
│                                                     │
│           VoiceInk Pro                              │
│           [License pill: ACTIVE]                    │
│                                                     │
│  License key                                        │
│  ╭──────────────────────────────────────────╮     │
│  │ XXXX-XXXX-XXXX-XXXX (mono)               │     │
│  ╰──────────────────────────────────────────╯     │
│                                                     │
│  [Activate] [Manage subscription]                  │
╰────────────────────────────────────────────────────╯
```

**Components:**
- License pill — capsule with 3 states: ACTIVE (success), TRIAL (transcribe), EXPIRED (warn).
- Hero illustration — SF Symbol `key.fill` at 80pt, gradient fill (warn → enhance), with subtle glow shadow.

**Files:**
- Edit: `VoiceInk/Views/LicenseView.swift`, `LicenseManagementView.swift` (~100 LOC each).

### 3.7 AI Models / API Keys

**Goal:** provider gallery. Each provider as a glass card with its tint. Expandable to show available models + key entry.

**Layout:** grid (2 columns), each cell = provider card.

```
╭─ Anthropic ──────╮  ╭─ OpenAI ────────╮
│ [✦ logo tile]    │  │ [⭘ logo tile]   │
│ Claude            │  │ OpenAI           │
│ [● connected]     │  │ [○ no key]       │
│ 4 models          │  │ Add key →         │
│ [⌄ expand]        │  │                   │
╰──────────────────╯  ╰─────────────────╯
```

Expanded card shows:
- API key entry (obscured input)
- Available models list (glass rows, selectable)
- Test connection button

**Components:**
- `ProviderCard` — wraps `ProviderChip` at larger scale + state + expand.
- Reuse provider tint logic from `ProviderChip.swift`.

**Files:**
- Edit: `VoiceInk/Views/AI Models/APIKeyManagementView.swift` (~250 LOC).
- New: `VoiceInk/Views/AI Models/ProviderCard.swift` (~180 LOC).
- Edit existing card files (CloudModelCardView, ModelCardView, etc.) — apply glass treatment (~30 LOC each, 6 files).

### 3.8 Dictionary

**Goal:** stock list of `WordReplacement` entries → rich entry editor with glass cards per entry, hover-to-edit, drag to reorder.

**Layout:** scrollable column of glass-card entries.

```
╭─ entry ──────────────────────────────────────╮
│ [≡ drag handle]                               │
│ FROM: gpt-four         TO: GPT-4              │
│ Context: technical writing                     │
│ [edit] [delete]                                │
╰──────────────────────────────────────────────╯
```

Hover reveals edit / delete. Drag handle on left for reorder.

**Files:**
- Edit: `VoiceInk/Views/Dictionary/DictionarySettingsView.swift` (~150 LOC).
- Edit: `VoiceInk/Views/Dictionary/WordReplacementView.swift` (~100 LOC).

### 3.9 Prompts Editor

**Goal:** inline live preview pane. Edit prompt on left, watch the same example transcript get re-enhanced on the right whenever the prompt changes.

**Layout:** split — 50/50 horizontal.

```
╭─ glass card ─────────────╮  ╭─ glass card ─────────────╮
│ Prompt                    │  │ Preview                   │
│ ╭──────────────────────╮ │  │ EXAMPLE INPUT             │
│ │ You are a writing    │ │  │ "umm so the…"             │
│ │ assistant. Make…     │ │  │                            │
│ │ <textarea>           │ │  │ ENHANCED OUTPUT           │
│ ╰──────────────────────╯ │  │ "Sure, the…"              │
│                           │  │ [● enhancing…]            │
╰──────────────────────────╯  ╰──────────────────────────╯
```

Right panel re-runs enhancement on debounce (1.2s after last edit). Live status dot follows constellation grammar — violet during enhance, green flash on result.

**Files:**
- Edit: `VoiceInk/Views/PromptEditorView.swift` (~250 LOC).
- New: `VoiceInk/Views/Components/PromptLivePreview.swift` (~180 LOC).

### 3.10 Custom Sounds + sound design

**Goal:** ship 5 bespoke audio cues. Replace system sounds.

| Cue | Sound | Trigger | Duration |
|---|---|---|---|
| start | 880Hz pluck, 90ms attack, 140ms decay, 6th-tuned | Recording starts | ~230ms |
| transcribe-complete | C–E–G–B arpeggio (C major), soft | ASR finishes, before enhance | ~220ms |
| enhance-complete | Same arpeggio +4th, slightly softer | Enhancement finishes, just before paste | ~220ms |
| cancel | Descending two-note: A → E | User cancels recording | ~180ms |
| fail | Two-note minor: F → Db | Engine error | ~220ms |

All under 300ms. Curated bespoke samples (not stock). Stored as `.aiff` in `VoiceInk/Resources/Sounds/`.

**Custom Sounds Settings view:**
- Glass cards per sound — name, waveform preview, [▶ play] [Replace] [Reset].
- User can override with their own sample (already supported by `CustomSoundManager`).

**Files:**
- New: 5 `.aiff` files in `VoiceInk/Resources/Sounds/`.
- Edit: `VoiceInk/SoundManager.swift` — wire new defaults (~30 LOC).
- Edit: `VoiceInk/Views/Settings/CustomSoundSettingsView.swift` — glass cards + waveform preview (~180 LOC).

### 3.11 Animated menu bar icon

**Goal:** state-driven icon. Subtle, signals app is alive.

| State | Icon | Animation |
|---|---|---|
| idle | thin static waveform glyph | none |
| recording | filled waveform | pulse 1.0s scale 1.0↔1.08 |
| transcribing | shimmer waveform | shimmer alpha 0.55↔1.0, 1.4s |
| enhancing | sparkle overlay | violet glow tint, 1.6s breath |

Implementation: `NSStatusItem.button.image` swap on state change. Animations driven by `CALayer` on the button — `NSImage` + `CAKeyframeAnimation`. State source: `RecorderStateProvider`.

**Files:**
- Edit: `VoiceInk/StatusBarController.swift` (or existing menu bar icon handler — search for `NSStatusItem`) (~120 LOC).
- New: 4 `.pdf`/SF Symbol-rendered base icons OR programmatic `NSImage` builders in a new `MenuBarIconRenderer.swift` (~100 LOC).

---

### 3.12 Power Mode

**Goal:** Power Mode (per-context profile system — different prompts/models per app or website) gets the language across all four of its surfaces. Reference: `docs/UX_PROPOSAL.md` §4.4.

**Surfaces:**

1. **Settings strip** — replaces today's expandable row. Horizontal scrollable strip of glass cards. Each card: emoji + name + app icon + active indicator (`Palette.warn` dot pulsing if currently triggered). Plus card at the end opens add flow. Drag-to-reorder.
2. **Recorder popover** — opens from `RecorderPowerModeButton` on the constellation orb's chip. Glass card with active mode hero (large emoji + name + app icon + "Auto-detected from <app>"), quick-switch list of other modes as glass rows, footer button "Configure Power Modes" jumps to Settings strip.
3. **Add/edit configuration view** — full glass card hero. Emoji picker glass-popover. App picker via existing `AppPicker.swift`. URL trigger field with mono styling. Prompt + model selection use `ProviderChip` and `PromptChipPicker` from §3.2.
4. **Active-mode pill in constellation** — when a Power Mode is matched during active states (recording / transcribing / enhancing), a small `PowerModeActivePill` (emoji + name in mono caps) fades into the constellation card. 220ms cross-fade when the matched mode flips. Tappable — opens the popover.

**Material:** `GlassCard` everywhere. `Palette.warn` for active indicator. Emoji at native font size (display 17pt rounded for cards, 24pt for hero).

**Motion:** strip cards hover-lift via `GlassCard`. Active pill fades 220ms. Add flow uses `Animation.haloExpand` (§2.4). Active-indicator dot pulses on a 1.0s sine.

**Files (full breakdown in plan P2.H):**
- New: `VoiceInk/PowerMode/PowerModeStripView.swift`, `VoiceInk/PowerMode/PowerModeActivePill.swift`.
- Edit: `PowerModePopover.swift`, `PowerModeConfigView.swift`, `PowerModeView.swift`. Recorder integration in the Phase 1 orchestrator's successor.

---

## 4. Delighters catalog

Itemized. Most are 30–80 LOC each, layered on top of base components.

- **Recording start pulse** — orb scale 1.0 → 1.04 → 1.0 in 120ms, eased. (existing pattern from UX_PROPOSAL §6.3)
- **Token commit pulse** — every full-sentence boundary in live transcript: card scale 1.0 → 1.012 → 1.0 in 80ms. Triggered when partial transcript ends in `.`, `?`, `!`. Tasteful.
- **Done state preview** — green flash on orb + card content shows pasted target app + 1-line preview, dwells 280ms–1s, configurable.
- **Failure shake + amber dwell** — 0.32s shake + 1.2s amber dwell, then collapse. Card content shows "Transcription failed" / "Enhancement failed" + recovery hint (e.g. "Check API key in Settings").
- **Hover-aware whisper** — invisible when cursor far from menu bar; brightens linearly as cursor approaches. (§3.1)
- **First-run cinematic walkthrough** — auto-plays once. (§3.4)
- **Empty-state illustrations** — poetic glass cards for: history empty ("No transcriptions yet — press hotkey to begin"), no API keys ("Add a provider to enable AI enhancement"), no Power Modes ("Configure per-app behavior in Power Modes"). Each with an SF Symbol hero (60pt, palette-tinted) + one-line copy.
- **Hover-lift on cards** — 4pt translate-y on hover, 0.18s. Settings cards, history rows, AI Models cards.
- **Provider chip glow on switch** — when user changes the active provider/model, the chip pulses a single time in `enhance` tint over 0.4s.

**Confetti on first transcription?** Decision: **no**. Too gimmicky for the language we're committing to. The Constellation is the celebration.

---

## 5. File touchpoints

| Surface | New files (count + approx LOC) | Edited files (count + approx LOC) |
|---|---|---|
| Recorder (Constellation) | 6 / ~790 | 4 / ~150 |
| Menu Bar | 3 / ~300 | 1 / ~400 |
| Settings | 3 / ~260 | 2 / ~220 |
| Onboarding | 1 / ~280 | 4 / ~320 |
| History | 1 / ~150 | 2 / ~230 |
| License | 0 | 2 / ~200 |
| AI Models | 1 / ~180 | 7 / ~430 |
| Dictionary | 0 | 2 / ~250 |
| Prompts | 1 / ~180 | 1 / ~250 |
| Sound | 5 audio + 0 swift | 2 / ~210 |
| Menu bar icon | 1 / ~100 | 1 / ~120 |
| Common (shared) | 4 / ~370 | 0 |

**Totals:** ~21 new Swift files (~2,810 LOC) + 5 audio assets, ~28 edited files (~2,780 LOC of edits). Roughly 5,600 LOC moved end-to-end.

---

## 6. Risks + open questions

### 6.1 Wallpaper luminance detection — RESOLVED

**Decision:** option 3 (hybrid) — system appearance as default, override if wallpaper top-strip luminance contradicts.

Sample once on launch + on `NSWorkspace.activeSpaceDidChangeNotification`. ~15ms cost per screen change. `NSWorkspace.shared.desktopImageURL(for: screen)` → average luminance of top 60pt strip.

### 6.2 NSVisualEffectView fallbacks — addressed

`HaloMaterial` already layers translucent fill + gloss + stroke on top of blur view; fallback path verified during v1 Halo build (`UX_IMPL_NOTES.md` §3). Will hold for new surfaces. No further investigation needed.

### 6.3 Sound sample sourcing — RESOLVED

**Decision:** synthesize via `AVAudioEngine` at runtime. No external assets, parametric, zero IP risk, infinitely tweakable.

Pluck = single sine + envelope. Arpeggios = sine triads with attack/decay envelopes. ~200 LOC. All five cues (start, transcribe-complete, enhance-complete, cancel, fail) under 300ms each.

### 6.4 Accessibility — addressed in spec

- **Reduce Motion** — respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`. Pulses, breaths, shimmers, shakes all become static color swaps. Whisper line stops breathing — fades to mid-opacity static.
- **High Contrast** — respect `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast`. Glass tints become opaque; inner strokes become 1pt solid; halo glows hidden (replaced by 2pt solid border in state color).
- **VoiceOver** — every satellite gets an `accessibilityLabel`. Orb: "VoiceInk recording, red". Chip: "Provider Claude, model Sonnet 4.6". Card: state + content read aloud.
- **Color-blind** — every state has an icon companion (mic / waveform / sparkles / check / triangle), not just color.

### 6.5 Failure-state engine signal — RESOLVED

**Decision:** add `RecordingState.failed(reason: String)` to the engine's state machine. ~30 LOC engine change. Required for the failure visuals the user signed off on (red shake on orb, 1.2s amber dwell, then collapse to idle).

Engine work scheduled in Phase 1 alongside the Constellation recorder so the view layer has the signal it needs.

### 6.6 Cursor proximity monitor — power cost

Global mouse monitor at 30Hz polling is cheap (~0.1% CPU) but still continuously running. Mitigation: pause monitor when app is in background (`NSApp.isActive == false`).

---

## 7. Implementation phases

Three phases, ~1 week each. Parallelizable via teammate pairs (per `scope.html` Total option — ~6 pairs).

### Phase 1 — Foundations + Constellation (Week 1)

**Goal:** Constellation recorder ships. New shared components in place.

Touchpoints:
- §2.3 Adaptive Glass material — extend `HaloMaterial` with light variant.
- §2.4 Animation grammar — codify named springs in `Animation+Halo.swift`.
- §3.1 Constellation recorder — full state grammar, three satellites, Whisper line, hover monitor.
- §6.5 Engine `failed` signal — required for the failed visual state.

Pairs: 1 coder/reviewer for material + grammar; 1 pair for Constellation recorder; 1 pair for engine signal.

### Phase 2 — Menu Bar + Settings + Onboarding (Week 2)

**Goal:** highest-traffic settings surfaces redesigned.

Touchpoints:
- §3.2 Menu Bar dropdown.
- §3.3 Settings View — glass cards, rows, key caps, Constellation preview tile.
- §3.4 Onboarding — cinematic walkthrough + refresh existing 4 onboarding files.
- §3.11 Animated menu bar icon — wires off the same state provider as Phase 1.

Pairs: 1 pair Menu Bar + icon; 1 pair Settings; 1 pair Onboarding.

### Phase 3 — History + License + AI Models + Dictionary + Prompts + Sound (Week 3)

**Goal:** total scope. Every surface in the language.

Touchpoints:
- §3.5 History detail.
- §3.6 License view.
- §3.7 AI Models / API Keys gallery.
- §3.8 Dictionary entry editor.
- §3.9 Prompts editor live preview.
- §3.10 Sound design — synthesize cues + Custom Sounds settings polish.

Pairs: 1 pair History + License; 1 pair AI Models + Dictionary; 1 pair Prompts; 1 pair Sound.

---

## Decisions log (resolved 2026-04-28)

All foundational decisions resolved during brainstorm + this spec pass. Nothing blocking implementation.

| # | Decision | Resolution | Where |
|---|---|---|---|
| 1 | Material | Adaptive Glass — light on bright wallpapers, onyx on dark | §2.3 |
| 2 | Wallpaper detection | Hybrid: system appearance default + sampled top-strip luminance override | §6.1 |
| 3 | Notch geometry | Constellation — three satellites (orb / chip / card) replace single pill | §3.1 |
| 4 | Idle state | Whisper — breath line only; orb / chip / card all hidden during idle | §3.1, `idle-state.html` |
| 5 | State cycle | 5 states (idle → recording → transcribing → enhancing → done) + `failed` | §3.1, `state-cycle.html` |
| 6 | Failure visuals | Red shake on orb 0.32s + 1.2s amber dwell, then collapse to idle | §3.1, §4 |
| 7 | Engine `failed(reason:)` | Approved — added to state machine in Phase 1 (~30 LOC) | §6.5 |
| 8 | Sound sourcing | Synthesize via AVAudioEngine — no asset shipping, parametric | §3.10, §6.3 |
| 9 | Confetti on first transcription | No — too gimmicky; not in delighters catalog | §4 |
| 10 | Scope | Total — every surface in the language | §3 (12 surfaces incl. Power Mode) |
| 11 | Boldness | "Constellation is sexy" — distinctive, no half-measures, no trend-chasing | §1 |
