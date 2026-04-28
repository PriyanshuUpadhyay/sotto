# VoiceInk App-Wide Visual Redesign — Implementation Plan

> **For dispatchers:** This plan decomposes the spec at `docs/superpowers/specs/2026-04-28-app-visual-redesign-design.md` into work packets sized for a single coder + reviewer teammate pair (~1–2 days each). Use `superpowers:subagent-driven-development` to dispatch packets per the sequencing in the final section. Steps inside a packet use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship VoiceInk's cohesive Adaptive-Glass + Constellation visual language across all 11 user-facing surfaces in three phases (~3 weeks).

**Architecture:** Three foundations land first (light-variant glass material, named animation springs, engine `failed` signal). Constellation recorder lands on top of those in Phase 1. Phase 2 propagates the language to the highest-traffic settings surfaces (menu bar, Settings, onboarding) using a shared `GlassCard` primitive. Phase 3 covers the long tail (history, license, AI Models gallery, dictionary, prompts, sound).

**Tech stack:** Swift 5 / SwiftUI on macOS 14+, `NSVisualEffectView` (`.hudWindow` material), `NSPanel` + `NSHostingController` for the recorder, `NSStatusItem` for the menu bar, `AVAudioEngine` for synthesized sound cues. Existing palette in `VoiceInk/Views/Common/Palette.swift`. Existing material foundation in `VoiceInk/Views/Recorder/HaloMaterial.swift`.

**Spec citation convention:** every packet cites the relevant spec sections (e.g. "§3.1") and any predecessor doc lines so reviewers verify against source.

---

## Top-level dependency graph

```
Phase 1 (foundations + recorder)
  P1.A (light glass)  ──┐
  P1.B (animation)    ──┼─→ P1.D, P1.E, P1.F  ──→ P1.G (orchestrator)
  P1.C (engine fail)  ──┘                          │
                                                    ↓
                                                 P1.H (whisper + cursor monitor)
                                                    │
                                                    ↓
Phase 2 (must wait for Phase 1 — consumes light glass + animations)
  P2.A (glass primitives) ──→ P2.B, P2.D
  P2.C (menu bar icon) ────── independent of P2.A (uses P1.A only)
  P2.D (settings cards/rows) ──→ P2.E
  P2.F (cinematic walkthrough) ──→ P2.G

Phase 3 (must wait for Phase 2.A — consumes GlassCard primitive)
  P3.A (history)        independent
  P3.B (license)        independent
  P3.C (AI models)      independent
  P3.D (dictionary)     independent
  P3.E (prompts)        independent
  P3.F (sound synth) ──→ P3.G (custom sounds settings)
```

Phase boundaries are hard — Phase 2 cannot start until Phase 1.A, 1.B, and 1.C land on `main`. Phase 3 cannot start until P2.A (glass primitives) lands on `main`. Within a phase, packets without arrows between them parallelize freely.

---

## Phase 1 — Foundations + Constellation (Week 1)

**Phase goal:** Constellation recorder ships. Light-variant glass material, named springs, and the `RecordingState.failed(reason:)` signal land first because everything downstream depends on them.

### Phase 1 dependency table

| Packet | Title | Depends on | Parallelizable with |
|---|---|---|---|
| P1.A | Adaptive Glass — light variant | — | P1.B, P1.C |
| P1.B | Animation grammar | — | P1.A, P1.C |
| P1.C | Engine `failed(reason:)` signal | — | P1.A, P1.B |
| P1.D | Constellation orb | P1.A, P1.B, P1.C | P1.E, P1.F, P1.H |
| P1.E | Constellation chip | P1.A, P1.B | P1.D, P1.F, P1.H |
| P1.F | Constellation card | P1.A, P1.B, P1.C | P1.D, P1.E, P1.H |
| P1.G | Constellation orchestrator | P1.D, P1.E, P1.F | (sequential — last in phase) |
| P1.H | Whisper line + cursor monitor | P1.A, P1.B | P1.D, P1.E, P1.F |

---

### P1.A — Adaptive Glass material (light variant + appearance detection)

**Spec:** §2.3, §6.1.

**Goal:** extend `HaloMaterial` to render either Onyx or Light variant per a `GlassAppearance` enum. Add hybrid wallpaper-luminance detection.

**Files to create:**
- `VoiceInk/Views/Common/GlassAppearance.swift` (~80 LOC) — enum (`onyx`, `light`) + `GlassAppearanceDetector` actor that samples `NSWorkspace.shared.desktopImageURL(for:)` once at launch and on `NSWorkspace.activeSpaceDidChangeNotification`. Top-60pt strip average luminance > 0.6 → `light`, else falls back to system appearance (`NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua])`).

**Files to edit:**
- `VoiceInk/Views/Recorder/HaloMaterial.swift` — add `appearance: GlassAppearance` parameter (default `.onyx` for source-compat). Branch each layer (fill, gloss, stroke, secondary stroke, shadow) on appearance per spec §2.3 Light Glass layer stack. Bump existing onyx values per spec: top gloss 1pt @ 0.06 → 1.5pt @ 0.30 (spec §2.3 #3); inner stroke 0.5pt white@0.08 → white@0.16 (spec §2.3 #4). Add new bottom inner stroke 0.5pt white@0.05 (spec §2.3 #5). Light variant: white@0.32 fill, 1.5pt white@0.70→0.18 top gloss, 0.5pt white@0.55 inner stroke, 0.5pt white@0.18 bottom stroke, 24px black@0.18 shadow at offset (0, 8).
- Same file — define `enum AdaptiveGlass` with three High-Contrast constants per resolved Q #5 + spec §6.4: `contrastedFill` (opaque palette token for the surface state), `contrastedStroke` (1pt solid in state color), `contrastedHaloDisabled: Bool` (true → suppress halo glow). All surfaces consume these when `NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` is true. ~10 LOC.
- Same file — extend `HaloPhase` enum with `.failed` and `.done` cases (originally scoped to P1.C, moved here 2026-04-28 per scope split — `HaloMaterial.swift` is P1.A's file so the enum extension belongs in this packet, not P1.C). Update `glowColor` switch: `.failed → Palette.recording`, `.done → Palette.success`. Update `glowAlpha` switch with appropriate intensities (`.failed` peaks at HaloIntensity.strong during the engine's amber dwell, `.done` is HaloIntensity.medium briefly). ~15 LOC.

**Approx LOC:** ~190 (80 new + ~110 edited).

**Acceptance criteria:**
- Build succeeds. Existing recorder still renders identically when `appearance: .onyx` is the default (visual regression check: notch + mini recorder both still match v1 screenshots in dark mode).
- New `HaloMaterial(appearance: .light, ...)` test harness (a SwiftUI preview in `HaloMaterial.swift`) renders white/silver glass with the light-variant layer stack visible.
- `GlassAppearanceDetector.current()` returns `.onyx` on a black wallpaper, `.light` on a white wallpaper. Verify by swapping `System Settings → Wallpaper` and printing the result via a temporary log line.
- Reduce-Motion / High-Contrast paths unaffected (spec §6.4) — material strokes don't depend on motion settings.

**Risks:** Wallpaper sampling races with launch (if `desktopImageURL` returns nil before WorkspaceDidActivate fires). Mitigation: detector exposes `@Published var current` with `.onyx` default and re-publishes when sampling completes.

**Reviewer focus:**
- Onyx variant's existing pixel-perfect appearance is preserved (no accidental drift in the bumped gloss/stroke values across notched + non-notched modes).
- Light-variant layer order matches spec §2.3 exactly — fill below gloss below **inner sheen** below strokes (sheen above strokes per spec §2.3 #6, this is a real ordering trap).
- Wallpaper-detection fallback: when luminance ≤ 0.6, return `systemFallback()` (NOT a hardcoded `.onyx`) so dark wallpapers still respect the user's appearance preference.
- `GlassAppearanceDetector` cleans up `NSWorkspace.shared.notificationCenter` observers in `deinit` (no leaks).
- 15ms sampling cost claim: verify via `os_signpost` or a one-shot `CFAbsoluteTimeGetCurrent()` log around `sampleLuminance(...)`.
- `AdaptiveGlass.contrastedFill / contrastedStroke / contrastedHaloDisabled` are exposed as a namespace so downstream packets can branch on `accessibilityDisplayShouldIncreaseContrast` uniformly (no per-surface re-computation of contrast logic).

**Worktree:** safe — single-file extension + one new file.

---

### P1.B — Animation grammar codification

**Spec:** §2.4.

**Goal:** named springs become the only sanctioned motion vocabulary. Cite-able from every recorder + settings + onboarding view.

**Files to create:**
- `VoiceInk/Views/Common/Animation+Halo.swift` (~90 LOC). Three named animations:
  ```swift
  extension Animation {
      static let haloExpand   = Animation.spring(response: 0.38, dampingFraction: 0.78)
      static let haloCollapse = Animation.spring(response: 0.42, dampingFraction: 1.00)
      static let haloBreathe  = Animation.easeInOut(duration: 1.6).repeatForever(autoreverses: true)
      static let haloPhaseCrossfade = Animation.easeInOut(duration: 0.22)
  }
  ```
  Plus four motion-token structs: `HaloShimmer` (TimelineView phase sampling 1.6s), `HaloShake` (keyframe x-offsets `{-6, 6, -4, 4, -2, 0}` over 0.32s), `HaloPulse` (scale 1.0↔1.18 over 1.0s repeat), `HaloBreathOrb` (scale 1.0↔1.15 over 1.6s repeat).
- Each motion token reads `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` and short-circuits to a static color/scale value (spec §6.4).

**Files to edit:** none (greenfield).

**Approx LOC:** ~90.

**Acceptance criteria:**
- Build succeeds; SwiftUI preview renders each token visibly motion-correct (eyeball a 5s preview).
- Toggle System Settings → Accessibility → Display → Reduce Motion ON. Re-launch preview. All four motion tokens become static (no movement, no opacity flicker).
- Constants exactly match spec §2.4 numerics — reviewer must diff numerics line-by-line.

**Risks:** `repeatForever(autoreverses:)` retain-cycle concerns when bound to `@State` — mitigation is to reuse the standard SwiftUI `.animation(.haloBreathe, value: phase)` pattern, never an explicit `withAnimation` block.

**Reviewer focus:**
- Reduce-Motion branch on every token (not just one). Add a unit-test-style preview that flips the env var.
- No magic numbers leaked to call sites — every animation must come from `Animation+Halo.swift`.

**Worktree:** safe.

---

### P1.C — Engine `RecordingState.failed(reason:)` signal

**Spec:** §6.5, §3.1 phase content table.

**Goal:** engine surfaces failure to the view layer so the failed visual state (red shake → 1.2s amber dwell → collapse to idle) can render. `UX_IMPL_NOTES.md` §"Known limitations (v1)" explicitly flagged this as the missing engine signal.

**Files to edit:**
- `VoiceInk/Transcription/Engine/RecordingState.swift` — add `case failed(reason: String)`. Update `Equatable` synthesis (associated value compares by reason string).
- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` (~lines 84–254) — at every `recordingState = .idle` site that follows an error path, replace with `recordingState = .failed(reason: <error description>)` then schedule a 1.4s dispatch back to `.idle`. Specifically: lines 106 (transcription error), 113 (transcription cancelled), 148 (recording start failure), 208 (mid-recording failure), 254 (engine init failure). Pull the actual error message from the existing `do/catch` `error.localizedDescription`.
- `VoiceInk/Transcription/Engine/RecorderUIManager.swift:117,151,165` — same pattern: `.busy` → `.failed(reason:)` on error branches; `.failed → .idle` after dwell.
- `VoiceInk/Views/Recorder/RecorderStateProvider.swift` — extend protocol to expose `var failureReason: String? { get }` (computed: `if case .failed(let r) = recordingState { return r }; return nil`).
- ~~`VoiceInk/Views/Recorder/HaloMaterial.swift` — extend `HaloPhase` enum~~ **MOVED to P1.A scope 2026-04-28.** `HaloMaterial.swift` is P1.A's file; the `HaloPhase` extension naturally lives there. P1.C's branch will not independently compile until P1.A merges (`HaloRecorderView` references `HaloMaterial`). This is acknowledged scope coupling — wave 1 reaches a buildable integration only after P1.A + P1.C both land on the integration branch.

**Approx LOC:** ~95 (engine ~50, state provider ~10, plus call-site edits ~35; HaloPhase extension's ~25 LOC moved to P1.A).

**Acceptance criteria:**
- Build succeeds **once P1.A also lands** (P1.C's branch alone won't compile because `HaloRecorderView` references `HaloMaterial` which is on P1.A's branch). Engine + view-protocol changes themselves are syntactically correct and compatible.
- Existing transcribe + enhance paths unchanged in happy-path flows.
- Force a transcription failure (disconnect network mid-enhance with a cloud provider) — engine surfaces `.failed` for ~1.4s before reverting to `.idle`. Verify by adding a temporary `print` in `RecorderStateProvider`.
- All five error sites in `VoiceInkEngine.swift` map to `.failed(reason:)` with non-empty reason strings.
- Engine `Equatable` conformance still compiles (associated-value compare).

**Risks:** the existing `RecorderUIManager` may auto-collapse the recorder panel on `.busy`/`.idle` transitions; confirm the new `.failed` state keeps the panel visible during dwell. Mitigation: route `.failed` to "show panel" branch in `RecorderUIManager` alongside `.recording/.transcribing/.enhancing`.

**Reviewer focus:**
- Every existing call site that read `recordingState == .idle` or `.busy` gets reviewed for whether it now needs to handle `.failed` too. Use Grep to enumerate.
- The 1.4s dwell timer is cancelled if a new recording starts mid-dwell (no stale `.idle` reset stomping a fresh `.recording`).
- Failure reasons are user-readable (not stack traces / Swift error reflection garbage).

**Worktree:** **NOT safe in isolation** — touches engine and view-layer protocol simultaneously. Land on `main` directly via PR, or merge worktree before P1.D/E/F start.

---

### P1.D — `ConstellationOrb`

**Spec:** §3.1 (orb component), §2.4 (motion tokens).

**Goal:** 16×16pt circle, state-driven fill + glow, audio-meter modulation during recording.

**Files to create:**
- `VoiceInk/Views/Recorder/Constellation/ConstellationOrb.swift` (~140 LOC). Inputs: `phase: HaloPhase`, `audioMeter: Float` (0…1), `appearance: GlassAppearance`. State map:
  - `.recording` → red, `HaloPulse` (1.0s scale 1.0↔1.18 — but orb-scale only; spec says pulse 1.0s for orb)
  - `.transcribing` → cyan, opacity shimmer 0.55↔1.0 over 1.4s (use `HaloShimmer` token in opacity mode)
  - `.enhancing` → violet, `HaloBreathOrb` (1.0↔1.15 over 1.6s)
  - `.done` → green static for 280ms then opacity 1→0 over 220ms
  - `.failed` → red `HaloShake` 0.32s → amber dwell 1.2s → fade
  - `.hidden`, `.armed` → opacity 0
  - Audio modulation: orb radius offset = `audioMeter * 1.0pt`, applied as `.scaleEffect(1.0 + audioMeter * 0.06)` only during `.recording`.
  - Outer 1.5pt `white@0.25` ring (spec §3.1 — `.const-orb::after`).
  - Inner glow (14px) + outer glow (28px) shadows, both color-keyed via `phase.glowColor`.

**Files to edit:** none.

**Approx LOC:** ~140.

**Acceptance criteria:**
- SwiftUI preview cycles through all six phases on a 12s timer; visual matches `state-cycle.html` mockup row-by-row.
- During `.recording`, orb diameter visibly responds to a sliding `audioMeter` slider (0…1).
- `.failed` shake is exactly 0.32s, then 1.2s amber dwell, then fade — not configurable, hardcoded to spec.
- Reduce Motion: orb becomes a static color disc (no pulse, no breath, no shake).
- VoiceOver label: "VoiceInk recording, red" / "...transcribing, cyan" / etc. (spec §6.4).

**Risks:** `HaloShake` keyframes may collide with `.scaleEffect` audio modulation if both modify the same transform. Mitigation: nest in two separate `.modifier(...)` calls.

**Reviewer focus:**
- Phase transitions use `Animation.haloPhaseCrossfade` (0.22s) — not ad-hoc easeInOut.
- Audio meter modulation is gated to `.recording` only (no glow flicker during transcribing/enhancing).
- 14px inner + 28px outer shadow values match spec.

**Worktree:** safe.

---

### P1.E — `ConstellationChip`

**Spec:** §3.1 (chip component).

**Goal:** glass capsule with color dot + mono provider/model identifier.

**Files to create:**
- `VoiceInk/Views/Recorder/Constellation/ConstellationChip.swift` (~120 LOC). Inputs: `phase: HaloPhase`, `providerLabel: String` (e.g. "CLAUDE"), `modelLabel: String` (e.g. "SONNET-4-6"), `appearance: GlassAppearance`. Layout: 20pt height, intrinsic width, 10pt corner radius. Content (left to right): 5pt color dot (mirrors orb state) + 4pt gap + `Text("\(providerLabel) · \(modelLabel)")` in `SF Mono` medium 9pt all-caps tracking 1.4 (spec §2.2 mono identity). Glass background via existing `HaloMaterial` with `appearance` plumbed through. Outer halo box-shadow color-keyed to state, alpha 0.30–0.40 (spec §3.1).
- Visibility: hidden during `.idle`, `.hidden`, `.armed`. Visible during `.recording`, `.transcribing`, `.enhancing`, `.done`, `.failed`.

**Files to edit:** none.

**Approx LOC:** ~120.

**Acceptance criteria:**
- SwiftUI preview shows chip at all 6 visible phases. Dot color matches orb. Label legible at 9pt mono on both onyx and light glass.
- Provider/model strings come from caller — orchestrator (P1.G) wires them from `aiService.selectedAIProvider` + `aiService.currentModel`.
- VoiceOver label: "Provider Claude, model Sonnet 4.6" (palette-tinted dot is decorative, marked `accessibilityHidden`).

**Risks:** intrinsic-width chip may flicker layout when label changes mid-flight (e.g. provider switch during recording). Mitigation: animate width with `Animation.haloExpand`.

**Reviewer focus:**
- Mono tracking — `tracking(1.4)` is 0.12em × 9pt × ~1.3 (verify reads close to `letter-spacing: 0.12em` in mockup).
- Chip glass uses `HaloMaterial`, NOT a one-off `Color.black.opacity(0.78)` shortcut.

**Worktree:** safe.

---

### P1.F — `ConstellationCard`

**Spec:** §3.1 (card component + phase content table).

**Goal:** Adaptive Glass surface, 280pt × min 56pt, 22pt corner radius, state-driven content.

**Files to create:**
- `VoiceInk/Views/Recorder/Constellation/ConstellationCard.swift` (~280 LOC). Inputs: `phase: HaloPhase`, `partialTranscript: String`, `pasteTargetAppName: String?`, `donePreview: String?`, `failureReason: String?`, `activePromptIcon: String`, `activePromptName: String`, `transcriptionEngineLabel: String` (e.g. "WHISPER · LARGE-V3"), `enhancementProviderLabel: String` (e.g. "CLAUDE · SONNET-4-6"), `appearance: GlassAppearance`.
- Phase content (matches spec table exactly):
  - `.recording` (with partial) → existing `StreamingCaretTranscript` from `HaloRecorderView.swift:533` + blinking caret, static card.
  - `.transcribing` → `Image(systemName: "waveform.badge.magnifyingglass")` + Display 17pt "Transcribing" + Mono 9pt `transcriptionEngineLabel`. Cyan shimmer sweep across card via `HaloShimmer` (1.6s).
  - `.enhancing` → `Image(systemName: activePromptIcon)` + Display 17pt "Enhancing with \(activePromptName)" + Mono 9pt `enhancementProviderLabel`. Card breathes via `HaloBreathOrb` adapted to scale 1.0↔1.012.
  - `.done` → `Image(systemName: "checkmark.circle.fill")` + Display 17pt "Pasted to \(pasteTargetAppName ?? "clipboard")" + Body italic 13pt `donePreview` (1-line truncated). Static, dwell 280ms–1s.
  - `.failed` → `Image(systemName: "exclamationmark.triangle.fill")` + Display 17pt "Transcription failed" or "Enhancement failed" (branch on `failureReason` content) + Body 13pt recovery hint.
  - `.idle`, `.hidden`, `.armed` → card hidden (zero-opacity, not in layout).
- Drop-in motion: `translateY -8 → 0` + opacity 0 → 1 over `Animation.haloExpand` (0.38s spring).
- Exit motion: `Animation.haloCollapse` (0.42s spring) on disappear.
- Phase crossfade: 0.22s `Animation.haloPhaseCrossfade` for content swap, with scale 0.96 → 1.0.
- Material: `HaloMaterial(shape: RoundedRectangle(cornerRadius: 22), phase: phase, appearance: appearance)`.

**Files to edit:** none. (Reuses `StreamingCaretTranscript` from `HaloRecorderView.swift:533` — module-internal so reuse works without a move.)

**Approx LOC:** ~280.

**Acceptance criteria:**
- SwiftUI preview cycles through all 6 phases. Content renders exactly per spec table.
- Drop-in animation visible on first transition out of `.idle`.
- Crossfade between phases (e.g. `.transcribing` → `.enhancing`) is the 0.22s `Animation.haloPhaseCrossfade`, not a hard cut.
- Fixed 280pt width, dynamic height ≥ 56pt.
- Reduce Motion: shimmer + breath swapped to static color tint; drop-in becomes immediate fade.
- VoiceOver: card labels read full content (e.g. "Enhancing with Default Mode using Claude Sonnet 4.6").

**Risks:** `StreamingCaretTranscript` may have its own animation that competes with the card's crossfade — verify by reading `HaloRecorderView.swift:533` first.

**Reviewer focus:**
- Phase content table compliance — every row of spec §3.1 phase content table accounted for, reviewer ticks them off.
- Mono label tracking matches the chip (9pt, all-caps, 1.4 tracking).
- 280pt fixed width — not "ideal width," not "min 280" — exactly 280pt.

**Worktree:** safe.

---

### P1.G — Constellation orchestrator

**Spec:** §3.1 (panel infrastructure decision: one panel, three sub-views).

**Goal:** replace `HaloRecorderView` interior with a `ConstellationContainer` that anchors the three satellites in a `ZStack` over a screen-width × ~120pt panel; gut `HaloRecorderView` from 580 LOC down to ~50 LOC adapter; resize panels to top-strip; map `RecordingState` (incl. new `.failed`, `.done`) to `HaloPhase`.

**Files to create:**
- `VoiceInk/Views/Recorder/Constellation/ConstellationContainer.swift` (~160 LOC). Inputs: `stateProvider`, `recorder`, `aiService`, `enhancementService`, `mode: HaloShape.Mode`. Lays out:
  - Orb pinned to notch row, x-offset to ~26% (notch mode) or screen-center − 100pt (mini mode).
  - Chip pinned to notch row, x-offset to ~74% / screen-center + 100pt.
  - Card centered horizontally, y = notch baseline + 12pt.
  - Hit-test passthrough except on the three satellite frames (spec §3.1 panel infrastructure).
- Maps `RecordingState` → `HaloPhase`:
  - `.idle` → `.hidden`
  - `.starting`, `.recording` → `.recording` (or `.liveText` if `partialTranscript` non-empty — preserve v1 behavior)
  - `.transcribing` → `.transcribing`
  - `.enhancing` → `.enhancing`
  - `.busy` → previous phase frozen (preserve v1)
  - `.failed(reason:)` → `.failed`
  - Add new `.done` case derived from a brief view-layer flag set when paste completes — orchestrator subscribes to a `NotificationCenter` post (or inject a `@Published var lastPasteEvent` on `RecorderStateProvider`). **Decision per spec §3.1 done state:** add `RecorderStateProvider.lastPasteEvent: PasteEvent?` (struct with `appName: String`, `preview: String`, `timestamp: Date`). Orchestrator infers `.done` for ≤1s after a fresh `lastPasteEvent`.

**Files to edit:**
- `VoiceInk/Views/Recorder/HaloRecorderView.swift` — strip interior; replace with `ConstellationContainer(...)`. Down from 579 LOC to ~60 LOC adapter that wires inputs.
- `VoiceInk/Views/Recorder/NotchRecorderPanel.swift` — frame becomes screen-width × 120pt anchored at top strip (spec §3.1 panel decision). ~30 LOC.
- `VoiceInk/Views/Recorder/MiniRecorderPanel.swift` — same panel resize, ~30 LOC.
- `VoiceInk/Views/Recorder/RecorderStateProvider.swift` — add `lastPasteEvent: PasteEvent?` published property. Concrete impl (the engine wrapper) wires it from the existing paste-completion path in `CursorPaster.swift`.
- `VoiceInk/CursorPaster.swift` — emit `PasteEvent` on successful paste (existing code path; add ~15 LOC).
- Delete: nothing — `HaloShape.swift` stays since the chip + card use rounded-rect shape, not a notch silhouette, so `NotchShape` is no longer used by the recorder; **keep** the file regardless (other call sites?). Verify with Grep first.

**Approx LOC:** ~360 (160 new + 200 edited/stripped).

**Acceptance criteria:**
- Build succeeds. App launches.
- Trigger recorder: orb fades in red + pulses, chip fades in 60ms later showing current provider, card drops in 90ms later with placeholder for live transcript.
- Speak → live transcript fills card (StreamingCaretTranscript still works).
- Stop → orb morphs cyan, card content swaps to "Transcribing WHISPER · LARGE-V3" with shimmer.
- Enhancement runs → orb morphs violet, card swaps to "Enhancing with \<prompt\> CLAUDE · SONNET-4-6", card breathes.
- Paste lands → orb flashes green for 280ms; card shows "Pasted to \<app\> — '\<preview\>'" for ~1s; collapse.
- Force a failure (network kill mid-enhance) → orb red shake → 1.2s amber dwell → collapse.
- Test on notched MacBook + non-notched / external display — both layouts recognizable per spec §3.1 notched/non-notched layouts.
- Reduce Motion + High Contrast both respected.

**Risks:**
- `CursorPaster` may already post a notification — Grep first; reuse if so.
- Panel resize may break window-level / hit-testing (`statusBar+3` level). Test with menu bar interactions still working through the passthrough region.
- 60/90ms stagger timings (spec §2.4) need to be exact.

**Reviewer focus:**
- The four spec §2.4 sequencing timings — t=0.00 orb, t=0.06 chip, t=0.09 card — are encoded as `.delay(0.06)` / `.delay(0.09)` modifiers on the chip + card transitions, NOT as `DispatchQueue.main.asyncAfter`.
- `HaloRecorderView.swift` shrinks to a thin adapter. Old logic (deeply nested `Group { ... }` ZStacks, breathePulse `@State`, popover plumbing) is moved or removed cleanly — no orphaned imports / unused state.
- Hit-test passthrough verified: clicking on the menu bar through the panel region still hits the menu bar.
- `lastPasteEvent` source-of-truth lives on `RecorderStateProvider`, not duplicated in `ConstellationContainer`.

**Worktree:** **NOT safe in isolation** — touches 6 files including engine-adjacent `CursorPaster.swift`. Land on `main` after P1.D, P1.E, P1.F, P1.H all merged.

---

### P1.H — Whisper line + cursor proximity monitor

**Spec:** §3.1 (idle / Whisper), §6.6 (cursor monitor power cost).

**Goal:** ambient breath line below notch when idle; opacity ramps with cursor distance to the menu bar.

**Files to create:**
- `VoiceInk/Views/Recorder/Constellation/WhisperLine.swift` (~90 LOC). 60×2pt rounded-rect, 3-stop horizontal gradient `white@0 → white@0.5 → white@0`, 8px `white@0.35` glow shadow. Animation: 2.6s sine breath — opacity 0.35↔0.85 + scaleX 0.85↔1.0. Visible only when `phase == .idle` (or `.hidden`). Light-variant override: gradient inverts to `black@0 → black@0.4 → black@0`, glow becomes black@0.18.
- `VoiceInk/Views/Recorder/Constellation/CursorProximityMonitor.swift` (~110 LOC). Class with `@Published var proximity: Double` (0…1). Adds `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)` on a 30Hz throttled timer. Computes distance from cursor to menu bar baseline (`screen.frame.height - cursor.y`):
  - `> 200pt` → `proximity = 0`
  - `60..200pt` → linear ramp 0 → 1
  - `≤ 60pt` → `proximity = 1`
  - Pauses when `NSApp.isActive == false` (spec §6.6).
  - Cleanup in `deinit`.

**Files to edit:**
- `VoiceInk/Views/Recorder/Constellation/ConstellationContainer.swift` (created in P1.G) — add `WhisperLine` to ZStack, opacity multiplier = `proximity` from monitor.

**Approx LOC:** ~210.

**Acceptance criteria:**
- App at idle: whisper line visible only when cursor approaches menu bar; invisible when cursor parked at bottom of screen.
- Distance ramp matches spec: at 200pt distance, proximity ≈ 0; at 130pt, proximity ≈ 0.5; at 60pt, proximity = 1.
- `Activity Monitor` shows < 1% CPU with cursor moved continuously across the screen.
- App backgrounded (CMD+Tab away): cursor monitor pauses (verify with `print` in `proximity` setter — no events).
- Reduce Motion: line stops breathing, holds at mid-opacity (0.6) when proximity = 1.
- VoiceOver: line is decorative (`accessibilityHidden(true)`).

**Risks:** `addGlobalMonitorForEvents` requires no special permissions for mouse-moved (unlike key events), but verify on a clean install. 30Hz throttle: use `Timer` or a sample-coalescing pattern.

**Reviewer focus:**
- Background-pause logic actually pauses (no leaked events).
- Distance computation accounts for multi-display setups (use the screen containing the cursor, not main screen).
- Line gradient/glow visually matches `idle-state.html` mockup at the spec luminances.

**Worktree:** safe.

---

## Phase 2 — Menu Bar + Settings + Onboarding (Week 2)

**Phase goal:** highest-traffic settings surfaces redesigned. **Hard prerequisite:** P1.A, P1.B, P1.C must be on `main` — Phase 2 surfaces consume both `GlassAppearance` and `Animation.haloExpand`. The new `GlassCard` primitive lands first (P2.A) so all other Phase 2 packets parallelize on top of it.

### Phase 2 dependency table

| Packet | Title | Depends on | Parallelizable with |
|---|---|---|---|
| P2.A | Common glass primitives | P1.A | (sequential — first in phase) |
| P2.B | Glass menu bar dropdown | P2.A | P2.C, P2.D, P2.F |
| P2.C | Animated menu bar icon | P1.B | P2.B, P2.D, P2.F |
| P2.D | Settings glass cards + rows | P2.A | P2.B, P2.C, P2.F |
| P2.E | Settings key caps + style picker | P2.D | (after P2.D only) |
| P2.F | Onboarding cinematic walkthrough | P2.A | P2.B, P2.C, P2.D |
| P2.G | Onboarding existing-step refresh | P2.A, P2.F | (after P2.F only) |
| P2.H | Power Mode redesign | P1.G, P2.A | P2.E, P2.G |

---

### P2.A — Common glass primitives

**Spec:** §3.2 (`GlassCard`, `GlassSwitch`), §3.2 prompt chips (`PromptChipPicker`).

**Goal:** three reusable primitives that every Phase 2/3 surface consumes.

**Files to create:**
- `VoiceInk/Views/Common/GlassCard.swift` (~110 LOC). Generic wrapper: `GlassCard<Content: View>(cornerRadius: CGFloat = 16, padding: CGFloat = 14, appearance: GlassAppearance? = nil, content: () -> Content)`. Resolves `appearance` from `GlassAppearanceDetector` if `nil`. Layered as `HaloMaterial(shape: RoundedRectangle(cornerRadius: cornerRadius), phase: .hidden, appearance: resolved)` + 4pt hover-lift on `.onHover` (spec §4 hover-lift on cards).
- `VoiceInk/Views/Common/GlassSwitch.swift` (~90 LOC). 36×20pt capsule, knob 16pt. Inputs: `Binding<Bool>`, `tint: Color = Palette.enhance`. Animates with `Animation.haloExpand` on toggle.
- `VoiceInk/Views/Common/PromptChipPicker.swift` (~140 LOC). Horizontal `ScrollView`, prompt chips at 56×56pt rounded-square glass background. Inputs: `prompts: [CustomPrompt]`, `selectedID: Binding<UUID?>`. Selection ring in `Palette.enhance` tint, 2pt. Pulse on selection change (single 0.4s violet pulse — spec §4 "Provider chip glow on switch").

**Files to edit:** none.

**Approx LOC:** ~340.

**Acceptance criteria:**
- SwiftUI preview for each primitive renders correctly on both onyx and light variants.
- `GlassCard` hover-lift visible on cursor enter, smoothly returns to rest on exit (4pt translate-y, 0.18s ease).
- `GlassSwitch` toggle animates with the named expand spring (0.38s).
- `PromptChipPicker` selection ring is 2pt `Palette.enhance`; selection change triggers a single visible pulse over 0.4s.
- Reduce Motion: hover-lift becomes immediate; pulse becomes immediate color change.
- VoiceOver: `GlassSwitch` is announced as a switch with on/off state; `PromptChipPicker` chips are buttons with prompt name labels.

**Risks:** `GlassCard` wrapping arbitrary content may force unexpected layout (intrinsic sizing). Mitigation: the wrapper exposes both `padding` and the option to omit it.

**Reviewer focus:**
- `GlassCard` does NOT duplicate the layered material — it composes `HaloMaterial`.
- `GlassSwitch` knob uses `Animation.haloExpand`, not `.easeInOut`.
- Prompt chip selection ring color is the named token (`Palette.enhance`), not a hex value.

**Worktree:** safe.

---

### P2.B — Glass menu bar dropdown

**Spec:** §3.2.

**Goal:** replace stock SwiftUI menu chrome in `MenuBarView.swift` with a 360×420pt Adaptive Glass popover.

**Files to edit:**
- `VoiceInk/Views/MenuBarView.swift` — rewrite from current 256 LOC to ~440 LOC. Top: VoiceInk wordmark + version mono. Sections per spec §3.2 layout: Models (transcription `ProviderChip` + enhancement `ProviderChip`), AI Enhancement toggle (`GlassSwitch`), Prompt picker (`PromptChipPicker`), Recent transcriptions (2 most recent from `LastTranscriptionService`, italic 12pt body, 1-line truncate), Settings + Quit buttons.
- Background: `GlassCard(cornerRadius: 16)` at full popover bounds.
- Entry motion: scale 0.96 → 1.0 + opacity 0 → 1 over `Animation.haloExpand` (0.32s).
- Existing `MenuBarManager.openMainWindowAndNavigate(to:)` wired to "Settings" button.

**Files to create:** none (consumes P2.A).

**Approx LOC:** ~440.

**Acceptance criteria:**
- Build succeeds. Click menu bar icon → glass popover appears with the entry animation.
- All controls functional: AI toggle persists, prompt picker switches active prompt, Settings button opens main window, Quit terminates.
- Recent transcriptions show 2 most recent from `LastTranscriptionService`.
- Both onyx and light glass variants render (test on dark + light wallpapers).
- VoiceOver navigates: wordmark → version → models section → toggle → prompt chips → recent → buttons. No skipped focus zones.

**Risks:** `LastTranscriptionService` may not exist at the name shown in spec — Grep first; fallback to `TranscriptionHistoryView`'s data source if so.

**Reviewer focus:**
- All `Toggle` calls replaced with `GlassSwitch`.
- All `Menu` chrome stripped (no leftover stock dividers).
- Popover scale/opacity entry uses `Animation.haloExpand`.

**Worktree:** safe.

---

### P2.C — Animated menu bar icon

**Spec:** §3.11.

**Goal:** state-driven `NSStatusItem.button.image` that reflects engine `RecordingState`.

**Files to create:**
- `VoiceInk/Views/Common/MenuBarIconRenderer.swift` (~120 LOC). Programmatic `NSImage` builders for 4 states using SF Symbols rendered to `NSImage` at 18×18pt template-image style:
  - `.idle` → `waveform` thin, monochrome.
  - `.recording` → `waveform` filled, `Palette.recording` accent (template image w/ tint, since menu bar icons honor system).
  - `.transcribing` → `waveform` with shimmer alpha 0.55↔1.0 over 1.4s via `CAKeyframeAnimation` on the layer.
  - `.enhancing` → `sparkles` overlay with 1.6s breath glow (CABasicAnimation on `shadowOpacity`).

**Files to edit:**
- `VoiceInk/AppDelegate.swift` (or wherever `NSStatusItem` is created — Grep `NSStatusItem` to confirm). Add a `RecordingStateObserver` that subscribes to `engine.$recordingState` (Combine) and swaps `statusItem.button.image` + applies the corresponding `CALayer` animation. ~100 LOC.

**Approx LOC:** ~220.

**Acceptance criteria:**
- Trigger recorder: menu bar icon swaps idle → recording (filled, red-tint pulse 1.0s scale 1.0↔1.08) → transcribing (shimmer) → enhancing (sparkle breath) → idle.
- All four animations honor Reduce Motion (static color swap only).
- Icon stays 18pt square — no layout jitter in menu bar.
- Works in both light and dark menu bar (template image).

**Risks:** `CAKeyframeAnimation` on `NSStatusItem.button.layer` may not animate if the button rebuilds itself on click. Mitigation: re-attach animations on `NSWindow.didBecomeKeyNotification` or after each image swap.

**Reviewer focus:**
- State observer cleanup (no leaked Combine subscriptions).
- Animation durations exactly match spec (1.0s pulse, 1.4s shimmer, 1.6s breath).

**Worktree:** safe — touches `AppDelegate.swift` + one new file.

---

### P2.D — Settings glass cards + rich rows

**Spec:** §3.3.

**Goal:** wrap each Settings `Section` in `GlassCard`, replace `LabeledContent` with rich `SettingsRow`.

**Files to create:**
- `VoiceInk/Views/Common/SettingsCard.swift` (~90 LOC). Wraps a Settings section with header (icon tile + title + subtitle), divider, content. Inputs: `iconSystemName: String`, `iconTint: Color`, `title: String`, `subtitle: String`, content view builder.
- `VoiceInk/Views/Common/SettingsRow.swift` (~120 LOC). Layout: `[16pt icon tile w/ section accent] [Display 13pt label + optional 11pt body subtitle] [Spacer] [control view]`. Inputs: `iconSystemName: String`, `label: String`, `subtitle: String?`, `iconTint: Color`, control content builder.

**Files to edit:**
- `VoiceInk/Views/Settings/SettingsView.swift` — wrap each existing `Section { ... }` in `SettingsCard`. Replace `LabeledContent` calls with `SettingsRow`. Map section icons + tints per spec §2.5 iconography. ~220 LOC of edits across the existing 544-line file.

**Approx LOC:** ~430.

**Acceptance criteria:**
- Build succeeds. Settings opens. Every section is a glass card with icon tile + title + subtitle.
- Each row uses `SettingsRow` with the section's accent tint applied to the row icon.
- Hover-lift visible on each card (4pt translate-y, 0.18s).
- All controls (toggles, hotkey recorders, pickers) still functional.
- Both onyx and light glass variants render (light wallpaper test).
- VoiceOver navigation: card title → subtitle → row label (with subtitle if present) → control.

**Risks:** existing `SettingsView.swift` mixes Form chrome with custom views — wrapping in `GlassCard` may double-layer backgrounds. Mitigation: strip Form's default group background via `.formStyle(.grouped)` removal or `.scrollContentBackground(.hidden)`.

**Reviewer focus:**
- Every `Section` block in the old `SettingsView` accounted for in the new layout (no orphan settings).
- Iconography tints match spec §2.5 table exactly.
- `LabeledContent` references gone (Grep to verify).

**Worktree:** safe — single-feature scope, but file touches large.

---

### P2.E — Settings key caps + Constellation tile in Recorder Style picker

**Spec:** §3.3 (key caps), §3.3 (RecorderStylePicker extension).

**Goal:** rich keyboard shortcut display + add Constellation preview tile to `RecorderStylePicker`.

**Files to create:**
- `VoiceInk/Views/Common/KeyCapView.swift` (~80 LOC). 24×24pt mono glass cap rendering a single key (e.g. `⌘`, `⇧`, `V`, `Space`). Glass background via `HaloMaterial` (rounded-rect 6pt corner), 4pt internal padding, key glyph in `SF Mono` medium 11pt. Composer view `KeyCombo(keys: ["⌘","⇧","V"])` that lays out caps with 4pt spacing.

**Files to edit:**
- `VoiceInk/Views/Settings/RecorderStylePicker.swift` — add a third tile alongside existing Halo / Mini cards. Tile renders a 60×40pt mini-Constellation (orb + chip + card miniature, all static at the .recording phase) so users see what they're picking. ~50 LOC.
- `VoiceInk/Views/Settings/SettingsView.swift` — find the hotkey display location (currently a plain `Text("⌘⇧V")` or similar — Grep `hotkey` / `keyboard`); replace with `KeyCombo`. ~30 LOC.

**Approx LOC:** ~160.

**Acceptance criteria:**
- Hotkey display shows three glass key caps with 4pt separators (e.g. `[⌘] [⇧] [V]`).
- Recorder Style picker shows three tiles: Halo, Mini, Constellation. Selection persists via `@AppStorage`.
- Tile preview for Constellation visibly differs from Halo/Mini.
- Reduce Motion: any tile micro-animation (existing) honors.

**Risks:** existing `RecorderStylePicker` may be a 2-card hardcoded layout — extend cleanly or refactor to a small for-each.

**Reviewer focus:**
- Key-cap glyphs use Unicode symbols (⌘, ⇧, ⌥, ⌃) not custom SF Symbol icons.
- Constellation preview is recognizably a mini version of the real recorder, not a placeholder rectangle.

**Worktree:** safe.

---

### P2.F — Onboarding cinematic walkthrough

**Spec:** §3.4.

**Goal:** auto-playing 6.5s sequence showing Constellation in action, replacing stock onboarding text steps for the headline page.

**Files to create:**
- `VoiceInk/Views/Onboarding/CinematicWalkthrough.swift` (~300 LOC). Full-screen overlay glass card 600×320pt centered. Six stages on a `Timer.scheduledTimer` with explicit timings:
  - Welcome (1.5s) — wordmark fade-in + whisper line breath.
  - Record (1.5s) — orb fade-in red + pulse + card drops in with placeholder transcript building char-by-char.
  - Transcribe (1.5s) — orb morph cyan + card swap "Transcribing WHISPER · LARGE-V3" + shimmer.
  - Enhance (1.5s) — orb morph violet + card swap "Enhancing with Default Mode CLAUDE · SONNET-4-6" + breath.
  - Done (0.5s) — orb green flash + card "Pasted to Notes — '...'".
  - Caption layer — 4 captions fade in/out per stage: "Press hotkey to record" / "AI transcribes locally or in cloud" / "Enhancement shapes the result" / "Pasted automatically into the focused app".
- Skip button bottom-right.
- Reuses `ConstellationOrb`, `ConstellationCard` from P1.D / P1.F (orb / chip / card scaled inside overlay).

**Files to edit:** none (greenfield).

**Approx LOC:** ~300.

**Acceptance criteria:**
- Overlay auto-plays 6.5s end-to-end on first launch.
- Skippable mid-flight via skip button.
- Re-runnable from a `Help → Show Tutorial` menu item (P2.G wires this).
- Reduce Motion: stages still cycle but no orb pulse / shimmer / breath / drop-in (static color swaps).
- VoiceOver: each stage has a description that's read aloud, captions are also announced.

**Risks:** timing the six stages with overlapping animations is fragile. Mitigation: each stage encapsulated as its own `View` with explicit `.task { try await Task.sleep(...) }` lifecycle.

**Reviewer focus:**
- Total runtime is exactly 6.5s ± 100ms.
- Caption fade-in/out doesn't overlap stage transitions (causes visual chop).
- Reused Constellation components match the real recorder's appearance (no divergent local copies).

**Worktree:** safe.

---

### P2.G — Onboarding existing-step refresh

**Spec:** §3.4.

**Goal:** glass-card treatment for the four existing onboarding files; Help menu wiring for P2.F's walkthrough.

**Files to edit:**
- `VoiceInk/Views/Onboarding/OnboardingView.swift` (current 373 LOC) — wrap each step in `GlassCard`. Add CinematicWalkthrough as the welcome step. ~80 LOC of edits.
- `VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift` (current 484 LOC) — each permission row becomes a `GlassCard` with icon tile + status pill (granted = `Palette.success`, pending = `Palette.warn`). ~120 LOC.
- `VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift` (current 229 LOC) — model picker as glass cards (one per model), download progress as horizontal glass progress bar. ~80 LOC.
- `VoiceInk/Views/Onboarding/OnboardingTutorialView.swift` (current 202 LOC) — embed `CinematicWalkthrough` as the playable tutorial. ~50 LOC.
- `VoiceInk/AppDelegate.swift` — add Help menu item "Show Tutorial" that opens an `OnboardingTutorialView` window. ~20 LOC.

**Approx LOC:** ~350.

**Acceptance criteria:**
- First launch: cinematic walkthrough plays, then permissions, then model download, then tutorial recap.
- Permission rows show status pills with correct colors.
- Help → Show Tutorial replays the walkthrough at any time.
- All four onboarding files use GlassCard, not stock SwiftUI list/form chrome.
- Reduce Motion + High Contrast respected throughout.

**Risks:** existing onboarding may have hardcoded step navigation that doesn't accept the new cinematic-first flow. Mitigation: read each file before editing; if step navigation is rigid, wrap rather than restructure.

**Reviewer focus:**
- Onboarding flow is functional end-to-end (permissions actually grant, models actually download).
- No double-card layering (a `GlassCard` inside a `Form` background reads as muddy).

**Worktree:** safe.

---

### P2.H — Power Mode redesign

**Spec:** §3.12 (added 2026-04-28). Reference: `docs/UX_PROPOSAL.md` §4.4 for design intent (horizontal scrollable strip of Power Mode cards).

**Goal:** the entire Power Mode subsystem in the new language — Settings strip, recorder popover, add/edit configuration view, active-mode pill in the constellation.

**Files to create:**
- `VoiceInk/PowerMode/PowerModeStripView.swift` (~220 LOC). Horizontal scrollable strip of glass cards in Settings. Each card: emoji + name + app icon (via `NSWorkspace.shared.icon(forFile:)`) + active indicator (animated `Palette.warn` dot if currently triggered). Plus card at the end opens add flow. Drag-to-reorder via `.onDrop` (existing pattern in `PromptEditorView`). State driven by `PowerModeManager.configurations`.
- `VoiceInk/PowerMode/PowerModeActivePill.swift` (~50 LOC). Tiny chip rendered in the constellation card during active states when a Power Mode is matched. Reads `PowerModeStateProvider.activeMode`. Shows emoji + name in mono caps. Fades in 220ms when mode flips.

**Files to edit:**
- `VoiceInk/PowerMode/PowerModePopover.swift` — full glass treatment via `GlassCard`. Active mode hero at top (large emoji + name + app icon + "Auto-detected from Cursor.app"). Quick-switch list of other modes below as glass rows. Footer button "Configure Power Modes" jumps to Settings strip. ~180 LOC.
- `VoiceInk/PowerMode/PowerModeConfigView.swift` — add/edit form rebuilt as glass card hero. Emoji picker glass-popover. App picker uses existing `AppPicker.swift` but wrapped in glass row. URL trigger field with monospace styling per §2.2. Prompt + model selection use `ProviderChip` and `PromptChipPicker` from P2.A. ~140 LOC of edits.
- `VoiceInk/PowerMode/PowerModeView.swift` — settings container. Replace expandable-row scaffolding with the horizontal strip (`PowerModeStripView`). Hero header: "Power Modes" + subtitle "Switch context automatically based on the active app or website." ~50 LOC.
- `VoiceInk/Views/Recorder/HaloRecorderView.swift` (or its successor after P1.G) — wire `PowerModeActivePill` into the constellation card slot during enhancing/recording when an active mode is matched. ~20 LOC.

**Approx LOC:** ~660.

**Acceptance criteria:**
- Settings → Power Modes shows horizontal scrollable strip of glass cards. Each card shows emoji + name + app icon + active indicator.
- Plus card opens the add flow as a glass-card hero (`PowerModeConfigView`).
- Drag-to-reorder works; order persists across launches.
- Recorder popover (Power Mode button on the pill) opens the redesigned glass popover. Active mode rendered as hero. Quick-switch tappable.
- When focus switches to a matching app, `PowerModeActivePill` fades into the constellation card during the next recording. Tapping it opens the popover.
- Both light + onyx glass variants render. Reduce Motion + High Contrast respected.

**Risks:**
- `PowerModeManager.configurations` may not expose the order-mutating API needed for drag-to-reorder. Read first; if not, add a minimal `move(from:to:)` method (~15 LOC) but stay surgical.
- Active-mode detection is global (`ActiveWindowService.swift`); `PowerModeActivePill` must subscribe to its publisher to avoid polling.
- `PowerModeConfigView` rewrite must keep all existing config fields working — the data model is shared.

**Reviewer focus:**
- All existing Power Mode functionality (auto-detect, prompt switching, model overrides) still works after the rewrite.
- Active pill doesn't appear when no Power Mode is matched (don't pollute the constellation card).
- App icons rendered crisply at @2x — `NSWorkspace.shared.icon(forFile:)` returns variable sizes.
- Glass card layering inside the recorder popover doesn't muddle (popover already lives on a glass surface; the inner card needs a transparent background).

**Worktree:** safe (all files are within `PowerMode/` directory + 1 recorder file).

---

## Phase 3 — Long-tail surfaces (Week 3)

**Phase goal:** every remaining surface in the language. **Hard prerequisite:** P2.A (`GlassCard`) on `main`. All Phase 3 packets are independent of each other (except P3.G depends on P3.F's sound synth).

### Phase 3 dependency table

| Packet | Title | Depends on | Parallelizable with |
|---|---|---|---|
| P3.A | History list + detail | P2.A | P3.B, P3.C, P3.D, P3.E, P3.F |
| P3.B | License view glass refresh | P2.A | P3.A, P3.C, P3.D, P3.E, P3.F |
| P3.C | AI Models / API Keys gallery | P2.A | P3.A, P3.B, P3.D, P3.E, P3.F |
| P3.D | Dictionary entry editor | P2.A | P3.A, P3.B, P3.C, P3.E, P3.F |
| P3.E | Prompts editor live preview | P2.A | P3.A, P3.B, P3.C, P3.D, P3.F |
| P3.F | AVAudioEngine sound synthesis | — | P3.A, P3.B, P3.C, P3.D, P3.E |
| P3.G | Custom Sounds settings polish | P3.F, P2.A | (after P3.F only) |

---

### P3.A — History list + detail

**Spec:** §3.5.

**Goal:** keep current row treatment; apply glass material to row backgrounds; rebuild detail view as glass card hero with audio timeline.

**Files to create:**
- `VoiceInk/Views/History/AudioTimelineView.swift` (~170 LOC). Custom waveform + scrubbable progress. Inputs: `audioFile: URL`, `duration: TimeInterval`, `currentTime: Binding<TimeInterval>`. Renders waveform via `AVAudioFile` sample reading (existing pattern in `AudioPlayerView.swift`).

**Files to edit:**
- `VoiceInk/Views/History/TranscriptionDetailView.swift` — full rebuild as `GlassCard` hero per spec §3.5 layout. Top: thumbnail + timestamp + `ProviderChip` + duration. Audio timeline below. Original / Enhanced text panes stacked. Action buttons row (Copy / Re-enhance / Delete). ~220 LOC.
- `VoiceInk/Views/History/TranscriptionHistoryView.swift` — list container gets glass background; rows stay (already polished per `UX_IMPL_NOTES.md`). Hover-lift via `GlassCard` wrapper. ~30 LOC.
- `VoiceInk/Views/History/TranscriptionListItem.swift` — minimal: ensure background is transparent so list glass shows through. ~10 LOC.

**Approx LOC:** ~430.

**Acceptance criteria:**
- History list shows alternating-luminance glass row backgrounds, hover-lift visible.
- Detail view loads selected transcription as glass card with all fields populated.
- Audio timeline plays + scrubs correctly (test with a 2:14 sample).
- Original vs Enhanced text both visible and distinguishable.
- Provider chip in detail header shows correct provider/model from the transcription record.

**Risks:** `AudioPlayerView.swift` already exists — Grep first; reuse / extend rather than reinvent waveform reader.

**Reviewer focus:**
- Glass appearance is detected per surface (light vs onyx) — not hardcoded.
- Timeline scrubbing is performant (no full re-render on every drag tick).

**Worktree:** safe.

---

### P3.B — License view glass refresh

**Spec:** §3.6.

**Goal:** plain `Form` becomes a hero glass card with license pill + hero illustration.

**Files to edit:**
- `VoiceInk/Views/LicenseView.swift` — wrap in large `GlassCard`. Hero: `Image(systemName: "key.fill")` at 80pt with linear gradient `Palette.warn → Palette.enhance` + 24px glow shadow. Title "VoiceInk Pro" Display 24pt. License pill (`ACTIVE` = `Palette.success`, `TRIAL` = `Palette.transcribe`, `EXPIRED` = `Palette.warn`). Mono license-key field. Activate / Manage subscription buttons. ~100 LOC.
- `VoiceInk/Views/LicenseManagementView.swift` — same glass treatment for management UI. ~100 LOC.

**Approx LOC:** ~200.

**Acceptance criteria:**
- Build succeeds. License view shows hero + pill + key + buttons in glass card.
- License pill color matches state (test with each of the 3 states).
- Hero gradient is visible and tasteful (warn → enhance not muddy).
- Both light + onyx glass variants render.

**Risks:** existing license-view button hooks (Activate / Manage subscription) must remain functional — don't accidentally drop the actions during the rewrite.

**Reviewer focus:**
- All three pill states verified.
- Hero gradient uses palette tokens, not raw hex.

**Worktree:** safe.

---

### P3.C — AI Models / API Keys gallery

**Spec:** §3.7.

**Goal:** provider gallery — 2-column grid, each cell a glass card with provider tint + expand-to-edit.

**Files to create:**
- `VoiceInk/Views/AI Models/ProviderCard.swift` (~200 LOC). Grid cell: provider logo tile (SF Symbol or asset), provider name, status dot (`Palette.success` connected / `Palette.neutral` no key), model count, expand chevron. Expanded state: API key entry (obscured), available models list (glass rows, selectable), Test Connection button. Reuses `ProviderChip` styling at larger scale.

**Files to edit:**
- `VoiceInk/Views/AI Models/APIKeyManagementView.swift` — full rewrite as 2-column `LazyVGrid` of `ProviderCard`. ~280 LOC.
- `VoiceInk/Views/AI Models/CloudModelCardView.swift` — glass background. ~30 LOC.
- `VoiceInk/Views/AI Models/CustomModelCardView.swift` — glass background. ~30 LOC.
- `VoiceInk/Views/AI Models/FluidAudioModelCardView.swift` — glass background. ~30 LOC.
- `VoiceInk/Views/AI Models/ModelCardView.swift` — glass background. ~30 LOC.
- `VoiceInk/Views/AI Models/NativeModelCardView.swift` — glass background. ~30 LOC.
- `VoiceInk/Views/AI Models/WhisperModelCardView.swift` — glass background. ~30 LOC.

**Approx LOC:** ~660.

**Acceptance criteria:**
- AI Models tab shows 2-column grid of provider cards.
- Each card's status dot reflects whether the provider has a valid API key.
- Expand reveals key entry + model list + Test Connection.
- Test Connection actually works (issues a real API call to the provider, surfaces success/failure).
- Provider tints visually distinct (Anthropic, OpenAI, Ollama, FoundationModels, MLX, LocalCLI).

**Risks:** seven file edits in one packet — large blast radius. Each card view's existing logic (download progress, language selection) must remain intact. Mitigation: glass-background change is purely cosmetic — no logic edits.

**Reviewer focus:**
- All seven provider sub-views render in glass without logic regression.
- API key entry remains obscured (`SecureField`).
- Test Connection error states are user-readable.

**Worktree:** **NOT safe in isolation** — 8 files touched. Land via PR with manual smoke-test of each provider.

---

### P3.D — Dictionary entry editor

**Spec:** §3.8.

**Goal:** stock list of `WordReplacement` entries → rich glass-card entries with hover-to-edit, drag to reorder.

**Files to edit:**
- `VoiceInk/Views/Dictionary/DictionarySettingsView.swift` (~180 LOC of edits). Replace the current list with a scrollable column of `GlassCard`-wrapped entries. Each entry shows: drag handle (`Image(systemName: "line.3.horizontal")`) + FROM/TO + context + edit/delete buttons. Hover reveals edit/delete (alpha 0 → 1 on `.onHover`). Drag handle wires to `.onDrag` / `.onDrop` for reorder.
- `VoiceInk/Views/Dictionary/WordReplacementView.swift` (~120 LOC of edits). Inline edit mode swaps row content to two `TextField`s + save button.

**Approx LOC:** ~300.

**Acceptance criteria:**
- Dictionary tab shows entries as glass cards.
- Hover reveals edit/delete buttons.
- Drag handle reorders entries; order persists via existing `@AppStorage` / SwiftData backing.
- Add / Edit / Delete all functional.
- Reduce Motion: hover reveal becomes immediate.

**Risks:** existing `EditReplacementSheet.swift` may conflict with inline edit. Decide: either keep sheet-based edit and add a "Edit" button that opens it, or do inline edit and remove sheet. Recommend inline (sheet feels heavy for 2-field edit).

**Reviewer focus:**
- Drag handles functional on macOS 14+ SwiftUI.
- Reorder persistence verified (close + reopen Settings shows same order).

**Worktree:** safe.

---

### P3.E — Prompts editor live preview

**Spec:** §3.9.

**Goal:** split editor — prompt on left, live-enhanced preview on right with debounced re-run.

**Files to create:**
- `VoiceInk/Views/Components/PromptLivePreview.swift` (~210 LOC). Inputs: `prompt: CustomPrompt`, `exampleInput: String` (a stock 1-paragraph "umm so the dynamic island feels great" sample), `aiService: AIService`, `enhancementService: AIEnhancementService`. Debounces prompt changes by 1.2s, then runs enhancement. Status dot follows constellation grammar (violet during enhance, green flash on result). Renders EXAMPLE INPUT block + ENHANCED OUTPUT block + status dot.

**Files to edit:**
- `VoiceInk/Views/PromptEditorView.swift` — convert to 50/50 horizontal split. Left: existing prompt editor wrapped in `GlassCard`. Right: `PromptLivePreview`. ~280 LOC of edits.

**Approx LOC:** ~490.

**Acceptance criteria:**
- Editing the prompt body waits 1.2s then triggers a single enhancement run on the example input.
- Status dot animates per phase (violet enhancing, green flash on result).
- Output text updates inline in the preview pane.
- Re-edit during enhancement cancels the prior in-flight run (no overlapping calls).
- Reduce Motion: status dot becomes static color swap.

**Risks:** API cost — every prompt edit costs an LLM call. Mitigation: debounce 1.2s, plus a "Pause live preview" toggle in the preview pane.

**Reviewer focus:**
- Cancellation logic for in-flight enhancement is verified (no leaked tasks).
- 1.2s debounce is exact, not "around 1s."
- Status grammar matches Constellation phases (same colors, same animation tokens).

**Worktree:** safe.

---

### P3.F — AVAudioEngine sound synthesis (5 cues)

**Spec:** §3.10, §6.3.

**Goal:** synthesize 5 audio cues at runtime — no asset shipping, parametric.

**Files to create:**
- `VoiceInk/Audio/CueSynthesizer.swift` (~220 LOC). `AVAudioEngine` + `AVAudioSourceNode` based. 5 functions:
  - `playStart()` — 880Hz sine pluck, 90ms attack, 140ms decay, 6th-tuned overtone. ~230ms total.
  - `playTranscribeComplete()` — C4–E4–G4–B4 arpeggio (C major), soft, attack/decay envelopes. ~220ms.
  - `playEnhanceComplete()` — C4–E4–G4–B4 arpeggio +4th (F4–A4–C5–E5), slightly softer. ~220ms.
  - `playCancel()` — A4 → E4 descending two-note. ~180ms.
  - `playFail()` — F4 → Db4 minor descending. ~220ms.
- All cues use the same envelope helper (linear attack, exponential decay).

**Files to edit:**
- `VoiceInk/SoundManager.swift` — replace asset-based playback with `CueSynthesizer` calls. Existing `playStartSound` / `playStopSound` / `playEscSound` redirect to new cues. Add `playTranscribeComplete`, `playEnhanceComplete`, `playFail`. Wire to engine state transitions in `RecorderUIManager`. ~80 LOC edited (down from current 140 + 50 new wiring).
- `VoiceInk/Transcription/Engine/RecorderUIManager.swift` — call `playTranscribeComplete` after transcription, `playEnhanceComplete` after enhancement, `playFail` on `.failed`. ~30 LOC.

**Approx LOC:** ~330.

**Acceptance criteria:**
- All 5 cues audibly play under 300ms each.
- Cues sound musical (not glitchy / clicking from envelope discontinuities).
- Cues fire on correct triggers (test full record → transcribe → enhance → paste flow; expect all 4 happy-path cues; force a failure for the 5th).
- `isSoundFeedbackEnabled = false` mutes all cues (existing toggle still works).
- No `.aiff` / `.wav` files added to bundle (verify with `git status`).

**Risks:** `AVAudioEngine` startup latency on first cue (~50–100ms). Mitigation: warm the engine at app launch via a silent zero-amplitude pre-roll.

**Reviewer focus:**
- Engine lifecycle: engine started once, kept alive, not torn down between cues.
- Volume normalization — all 5 cues at consistent loudness (test with system volume).
- No clicks/pops from missing fade-in/out.

**Worktree:** safe.

---

### P3.G — Custom Sounds settings polish

**Spec:** §3.10 (Custom Sounds Settings view).

**Goal:** glass cards per cue with waveform preview + Play / Replace / Reset buttons.

**Files to edit:**
- `VoiceInk/Views/Settings/CustomSoundSettingsView.swift` (~200 LOC of edits). For each of the 5 cues, render a `GlassCard` with: cue name + description + 60pt waveform preview (sample the synthesized cue's audio buffer once, render as horizontal lollipop bars) + ▶ Play button + Replace button (file picker for user override) + Reset button.
- Reuses existing `CustomSoundManager` for user-override storage.

**Approx LOC:** ~200.

**Acceptance criteria:**
- Settings → Custom Sounds shows 5 glass cards (one per cue).
- ▶ Play button plays the synthesized cue (if no override) or user-picked file.
- Replace opens file picker; selected file persists per `CustomSoundManager`.
- Reset clears the override and reverts to synthesized cue.
- Waveform preview is recognizably the cue's shape (not a generic placeholder).

**Risks:** waveform preview sampling may be slow if it runs synchronously on view appear. Mitigation: cache previews in `CustomSoundManager` after first render.

**Reviewer focus:**
- All 5 cues represented (start, transcribe-complete, enhance-complete, cancel, fail).
- Override + reset round-trip works.
- Waveform render is not blocking the main thread (use `Task.detached`).

**Worktree:** safe.

---

## Pair sequencing

Order in which the team-lead spawns coder/reviewer pairs to maximize parallelism without violating dependencies.

### Week 1 (Phase 1)

**Day 1, parallel batch 1 (3 pairs):**
- Pair `coder-p1a` + `reviewer-p1a` — P1.A (light glass material).
- Pair `coder-p1b` + `reviewer-p1b` — P1.B (animation grammar).
- Pair `coder-p1c` + `reviewer-p1c` — P1.C (engine `failed` signal).

**Day 2–3, parallel batch 2 (4 pairs, after batch 1 lands on `main`):**
- Pair `coder-p1d` + `reviewer-p1d` — P1.D (orb).
- Pair `coder-p1e` + `reviewer-p1e` — P1.E (chip).
- Pair `coder-p1f` + `reviewer-p1f` — P1.F (card).
- Pair `coder-p1h` + `reviewer-p1h` — P1.H (whisper + cursor monitor).

**Day 4, sequential (1 pair, after batch 2 lands):**
- Pair `coder-p1g` + `reviewer-p1g` — P1.G (orchestrator).

### Week 2 (Phase 2)

**Day 1, sequential (1 pair):**
- Pair `coder-p2a` + `reviewer-p2a` — P2.A (glass primitives).

**Day 2–3, parallel batch (4 pairs, after P2.A):**
- Pair `coder-p2b` + `reviewer-p2b` — P2.B (menu bar dropdown).
- Pair `coder-p2c` + `reviewer-p2c` — P2.C (animated menu bar icon).
- Pair `coder-p2d` + `reviewer-p2d` — P2.D (settings cards + rows).
- Pair `coder-p2f` + `reviewer-p2f` — P2.F (cinematic walkthrough).

**Day 4, parallel (3 pairs):**
- Pair `coder-p2e` + `reviewer-p2e` — P2.E (key caps + style picker tile).
- Pair `coder-p2g` + `reviewer-p2g` — P2.G (onboarding refresh).
- Pair `coder-p2h` + `reviewer-p2h` — P2.H (Power Mode redesign).

### Week 3 (Phase 3)

**Day 1–3, parallel (5 pairs, all independent except P3.G):**
- Pair `coder-p3a` + `reviewer-p3a` — P3.A (history).
- Pair `coder-p3b` + `reviewer-p3b` — P3.B (license).
- Pair `coder-p3c` + `reviewer-p3c` — P3.C (AI Models gallery).
- Pair `coder-p3d` + `reviewer-p3d` — P3.D (dictionary).
- Pair `coder-p3e` + `reviewer-p3e` — P3.E (prompts live preview).
- Pair `coder-p3f` + `reviewer-p3f` — P3.F (sound synthesis).

**Day 4, sequential (1 pair, after P3.F):**
- Pair `coder-p3g` + `reviewer-p3g` — P3.G (custom sounds settings).

**Pane budget:** 12 panes (6 concurrent coder/reviewer pairs). All planned waves fit — no chunking needed. Phase 3's 6-pair parallel batch is the largest, exactly at the cap.

---

## Worktree strategy summary

| Packet | Worktree-safe? | Rationale |
|---|---|---|
| P1.A | yes | single-file extension + 1 new |
| P1.B | yes | greenfield |
| P1.C | **no** | engine + view-protocol crosscut |
| P1.D, E, F, H | yes | greenfield component files |
| P1.G | **no** | 6 files, engine-adjacent |
| P2.A | yes | greenfield |
| P2.B, C, D, E, F, G, H | yes | single-feature scope each |
| P3.A, B, D, E, F, G | yes | single-feature scope each |
| P3.C | **no** | 8 files (gallery + 7 card views) |

Non-safe packets (P1.C, P1.G, P3.C) land via PR to `main` with manual smoke-test before downstream packets start.

---

## Spec coverage checklist

Verifying every spec section maps to at least one packet:

| Spec § | Topic | Packet(s) |
|---|---|---|
| §2.1 | Palette | reused across all (no packet — already in `Palette.swift`) |
| §2.2 | Typography | enforced in P1.E, P1.F, P2.D, P2.E, P3.A, P3.B |
| §2.3 | Adaptive Glass | P1.A |
| §2.4 | Animation grammar | P1.B |
| §2.5 | Iconography | P2.D (section icons), P1.F (state icons) |
| §3.1 | Constellation recorder | P1.D, P1.E, P1.F, P1.G, P1.H |
| §3.2 | Menu bar dropdown | P2.A, P2.B |
| §3.3 | Settings | P2.D, P2.E |
| §3.4 | Onboarding | P2.F, P2.G |
| §3.5 | History | P3.A |
| §3.6 | License | P3.B |
| §3.7 | AI Models | P3.C |
| §3.8 | Dictionary | P3.D |
| §3.9 | Prompts editor | P3.E |
| §3.10 | Sound | P3.F, P3.G |
| §3.11 | Animated menu bar icon | P2.C |
| §3.12 | Power Mode | P2.H |
| §4 | Delighters | embedded in P1.D (recording start pulse, token commit pulse, failure shake), P2.A (hover-lift, provider chip glow), P1.H (hover-aware whisper), P2.F (cinematic walkthrough), empty-state illustrations TBD per surface |
| §6.1 | Wallpaper detection | P1.A |
| §6.2 | NSVisualEffectView fallback | P1.A (already proven in v1) |
| §6.3 | Sound synth | P3.F |
| §6.4 | Accessibility | every packet's acceptance criteria includes Reduce Motion + High Contrast + VoiceOver |
| §6.5 | Engine `failed` signal | P1.C |
| §6.6 | Cursor monitor power cost | P1.H |
| §7 | Phases | this plan's structure |

**Empty-state illustrations** (§4 delighter) — folded into the relevant packets:
- History empty state → P3.A.
- No API keys → P3.C.
- No Power Modes → P2.H (the strip's plus-card *is* the empty-state CTA).

---

## Open questions — RESOLVED 2026-04-28

1. **`LastTranscriptionService` exact name** — Grep before P2.B starts; coder-p2b is responsible for the verification + adapting to the canonical data source (likely the existing SwiftData query used by `TranscriptionHistoryView`). No team-lead action needed.

2. **`HaloShape.swift` retention after P1.G** — RESOLVED: delete if zero call sites remain after P1.G lands. coder-p1g performs the cleanup as part of the orchestrator packet's PR.

3. **Power Mode UI in scope** — RESOLVED: included as **P2.H** (added 2026-04-28). User confirmed Total scope encompasses Power Mode. P2.H redesigns the Settings strip, recorder popover, add/edit view, and adds an active-mode pill to the constellation.

4. **`accessibilityDisplayOptionsDidChangeNotification` propagation** — RESOLVED: every motion/contrast token subscribes live via `NotificationCenter.default.publisher(for:)` so toggling system accessibility settings updates the running app without restart. P1.B owns the central subscription helper; downstream packets consume it.

5. **High-Contrast variant numerics** — RESOLVED: P1.A defines centralized constants (`AdaptiveGlass.contrastedFill`, `AdaptiveGlass.contrastedStroke`, `AdaptiveGlass.contrastedHaloDisabled`) so all surfaces respond uniformly when High Contrast is on.

6. **Pane capacity** — RESOLVED: 12 panes (6 pairs concurrent). No wave-chunking needed.

4. **`accessibilityDisplayShouldReduceMotion` polling** — `NSWorkspace` notification name for changes is `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`. Each packet's motion tokens should subscribe; the packet plan currently mentions reading once. Reviewers should confirm token changes propagate live, not just on app launch.

5. **High Contrast verification** — spec §6.4 says glass tints become opaque, halo glows hidden. Concrete numerics aren't specified. Recommend P1.A defines the high-contrast variant constants centrally so downstream packets (P2.A, P3.A–G) reuse them.

6. **Pane capacity** — confirm with team-lead the actual tmux pane budget so Phase 1 batch 2 (4 pairs) and Phase 3 (5+ pairs) wave-chunking is sized correctly.
