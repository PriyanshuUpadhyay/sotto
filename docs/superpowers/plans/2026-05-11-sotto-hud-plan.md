# Sotto HUD Implementation Plan (Pair: HUD)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the notch recorder HUD to the Sotto vocabulary: TacticalGlass material, Bay layout (single panel, 3 subviews — capsule + L/R stalactites), Acid Lime accent, Symmetric Glass chips, 7-state morphology with view-side `.done` / `.failed` lifetimes, Invisible idle via `orderOut`.

**Architecture:** Keep `NotchRecorderPanel`'s sacred single-panel topology (`collectionBehavior` / `level` / `styleMask` / `handleActiveSpaceChange`). Replace `ConstellationCluster`'s single-anchor layout with a `BayHUDView` that mounts 3 fixed-x-offset subviews into the same SwiftUI tree. Material vocabulary moves to a `TacticalGlass` primitive that wraps existing `HaloMaterial`. Engine-side `RecordingState` stays unchanged; the `RecorderUIManager` extends `HaloPhase` mapping with view-lifetime rules for `.done` (1.5s hold) and `.failed` (until-dismissed). Mini recorder path is OUT OF SCOPE — Bay is `.notch` mode only.

**Tech Stack:** SwiftUI 5 (macOS 14.4+), `NSPanel` / `NSHostingController` bridging, Combine, `TimelineView`, SF Mono. No new runtime deps.

**Source spec:** `docs/superpowers/specs/2026-05-11-sotto-ui-redesign-design.md`. Sections referenced: §1 (material), §1.X (a11y), §2 (structure), §3 (idle), §4 (state grammar), §5.4 (menubar wiring — coordinate with MENUBAR pair), §6.1 surface 4, Appendix B (spikes), Appendix C.HUD.

**Coordination:** MENUBAR pair consumes `HaloPhase` updates. SETTINGS pair owns `PredefinedPrompts` / `customPrompts` truncation rule (B.ModeList — settled here at 9 chars uppercase, hide-when-nil).

---

## File Structure

### Created files

- `VoiceInk/Theme/MotionTokens.swift` — pure value types (`MotionTokens.pulse`, `.bars`, `.sweep`, `.breathe`, `.blink`, `.dotJump`, `.spin`). No model-layer imports.
- `VoiceInk/Theme/TacticalGlass.swift` — `struct TacticalGlass<S: Shape>: View` wrapping `HaloMaterial` with Sotto-tuned defaults. Geometry tokens (`Geometry.cornerRadiusNotch = 8`, `.cornerRadiusZero = 0`, `.cornerRadiusGlass = 2`).
- `VoiceInk/Views/Recorder/Bay/BayHUDView.swift` — root SwiftUI view replacing `ConstellationContainer` for `.notch` mode. Owns `@StateObject RecorderUIState`, hosts 3 subviews.
- `VoiceInk/Views/Recorder/Bay/RecorderUIState.swift` — single observable; published `phase: HaloPhase`, `recordingStartedAt`, `audioLevel`, `firstAudioObserved`, `activePromptLabel`, `errorCode`, `lastPasteEvent`.
- `VoiceInk/Views/Recorder/Bay/BayCapsule.swift` — central 220×44 capsule. Dispatches per-state subview by `phase`.
- `VoiceInk/Views/Recorder/Bay/BayLeftStalactite.swift` — left chip (PROMPT). Visible during `.recording` / `.liveText`.
- `VoiceInk/Views/Recorder/Bay/BayRightStalactite.swift` — right chip (`▸ SAVE` during recording, `▸ UNDO` during committed). Mouse-actionable.
- `VoiceInk/Views/Recorder/Bay/States/ArmingContent.swift` — empty capsule + breathing lime border + "LISTENING".
- `VoiceInk/Views/Recorder/Bay/States/RecordingContent.swift` — red dot pulse + 5 lime audio bars + `REC mm:ss`.
- `VoiceInk/Views/Recorder/Bay/States/TranscribingContent.swift` — cyan L→R sweep + frozen faint bars + "TRANSCRIBING…".
- `VoiceInk/Views/Recorder/Bay/States/EnhancingContent.swift` — violet halo breath + faint violet bars + "ENHANCING…".
- `VoiceInk/Views/Recorder/Bay/States/CommittedContent.swift` — green ✓ + halo + label.
- `VoiceInk/Views/Recorder/Bay/States/FailContent.swift` — red ✗ + error code blink.
- `VoiceInk/Views/Recorder/Bay/Atoms/AudioBars.swift` — 5-bar lime equalizer (animated under `.recording`, frozen under `.transcribing`).
- `VoiceInk/Views/Recorder/Bay/Atoms/RecDot.swift` — pulsing red dot.
- `VoiceInk/Views/Recorder/Bay/Atoms/CyanSweep.swift` — masked gradient sweep.
- `VoiceInk/Views/Recorder/Bay/Atoms/MonoLabel.swift` — SF-Mono uppercase label with +0.16em tracking.
- `VoiceInk/Transcription/Engine/FirstAudioGate.swift` — VAD-gated first-audio observer reading from `Recorder.audioMeter` + raw `CoreAudioRecorder.averagePower`.

### Modified files

- `VoiceInk/Views/Common/Palette.swift` — rename `accent` → `brandAcid` recolored to `#D4FF3A`; add `recRed`, `commitGreen`, `transCyan`, `enhViolet`; keep `accentMuted`/`accentGlow`/`success`/`warn`/`neutral`/`hairline`/`hairlineSoft`/`innerHi`/`onyx*` as-is.
- `VoiceInk/Views/Recorder/HaloMaterial.swift` — re-key `HaloPhase.glowColor` to new state-tokened palette; activate `.armed` glow alpha; no structural changes to the 8-layer compose pipeline.
- `VoiceInk/Views/Recorder/HaloRecorderView.swift` — branch `mode == .notch` → `BayHUDView`; `.mini` continues to use `ConstellationContainer` (out of scope here).
- `VoiceInk/Transcription/Engine/RecorderUIManager.swift` — add `@Published var phase: HaloPhase`; add view-lifetime tracking (`.done` 1.5s, `.failed` until-dismissed) driven off `engine.$recordingState` + `failureRegistry.$current` + `engine.lastPasteEvent`; activate `.armed` between `.starting` and first-audio.
- `VoiceInk/Views/Recorder/RecorderStateProvider.swift` — add `var firstAudioObserved: Bool { get }` to the protocol so `BayHUDView` can read it from the engine instead of re-implementing the gate.
- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` — wire `FirstAudioGate` so `firstAudioObserved` flips during `.recording`; reset on `.idle`.
- `VoiceInk/Views/Recorder/NotchRecorderPanel.swift` — leave topology intact; no edits to `init`, `calculateWindowMetrics`, `handleActiveSpaceChange`. (File is the sacred keeper. Spec §6.1 says rename file when SETTINGS pair lands `Sotto/Views/...` move; that rename is RENAME-pair scope, not HUD.)

### Out of scope

- `MiniRecorderPanel.swift` / `MiniWindowManager.swift` — Mini path keeps `ConstellationCluster`. Bay is `.notch` only.
- `ConstellationCluster.swift` / `ClusterChips.swift` / `ChipPanel.swift` — not deleted; remain the Mini path's renderer.
- App rename, bundle ID, brew, Sparkle — RENAME pair.
- Menubar icon rendering — MENUBAR pair. HUD only publishes the `HaloPhase` they read.

---

## PR Strategy

Six landable chunks onto integration branch `redesign/sotto`. Each PR must build green and pass smoke; visuals progress from "tokens + scaffolding present, no visible change" (PR1) to "full Bay shipping" (PR6).

| PR | Group | What ships | Visible change |
|---|---|---|---|
| PR1 | A | Palette rename + state tokens; `TacticalGlass` primitive; `MotionTokens`. Mini + existing Notch still render via `ConstellationCluster`. | Tangerine → lime in existing chips/halo (color recolor side-effect). |
| PR2 | B | `BayHUDView` + 3 stalactite-frame subviews mount under `.notch` mode behind a feature flag default OFF. ConstellationCluster stays default. | Hidden until flag flipped. |
| PR3 | C | `RecorderUIManager.phase` + view-lifetime extensions; `FirstAudioGate`; `.armed` activation. | Hidden — published phase observable, no consumer yet. |
| PR4 | D | Per-state Bay content views wired in; flag flipped ON. | Bay HUD shipping for `.notch` users. |
| PR5 | E | A11y — Reduce Motion fallbacks; VoiceOver labels; ✓/✗ glyph rendering verified; HC via existing AdaptiveGlass. | A11y-only. |
| PR6 | F | Spike outputs codified — multi-monitor anchoring, arming-skip threshold, key-pass-through tests, full-screen policy doc, undo-collision rule. | Bug fixes / behavior pins. Flag removed. |

> **Feature flag:** `UserDefaults.standard.bool(forKey: "SottoBayHUDEnabled")` default `false`. Branch in `HaloRecorderView.swift`. PR6 deletes the flag.

---

## Open questions (resolve before PR2)

1. **B.MultiMonitor anchoring policy** — anchor Bay to notch display always, or follow keyboard focus? Plan currently writes "follow `NSScreen.main` like existing `NotchRecorderPanel.calculateWindowMetrics()`, document behavior on external-only setups." Confirm with team-lead.
2. **B.ArmingSkip threshold** — if mic init <16ms, skip `.armed` and jump straight to `.recording`? Measure-then-decide step is in Group F. v1 default: ALWAYS render arming briefly (≥120ms) so the entry isn't jarring; skip only if measurements show <16ms is common.
3. **B.UndoCollision** — hotkey re-fire within the 1.5s `.done` window: new recording wins (recommended by spec). HUD pair commits to this in Group F.
4. **Mini path future** — out of scope here. Plan recommends a follow-up: retire `ConstellationCluster` once Bay is stable. Not in this plan.

---

## Group A — Material primitives

**Goal:** New color/geometry/motion tokens + `TacticalGlass` primitive land with zero behavior change beyond a tangerine → lime recolor in already-shipping surfaces.

### Task A1: Rename `Palette.accent` → `Palette.brandAcid` and recolor

**Files:**
- Modify: `VoiceInk/Views/Common/Palette.swift:32-43`
- Modify (sweep): all call sites of `Palette.accent` / `Palette.accentMuted` / `Palette.accentGlow`

- [ ] **Step 1: Inventory call sites**

Run: `grep -rn 'Palette\.accent\|Palette\.accentMuted\|Palette\.accentGlow' VoiceInk/`
Expected: ~30–60 hits across `Views/Recorder/`, `Views/Settings/`, `Views/Common/`.

- [ ] **Step 2: Add `brandAcid` + state tokens at top of `Palette` enum**

Edit `VoiceInk/Views/Common/Palette.swift` — insert after the `neutral` constant (~line 25):

```swift
    /// #D4FF3A — Acid Lime brand accent (Sotto). Wordmark stop, selected row,
    /// section labels, prompt glyph, CTA halo, HUD audio bars.
    /// Source of truth: docs/superpowers/specs/2026-05-11-sotto-ui-redesign-design.md §1.4.
    static let brandAcid = Color(red: 0.831, green: 1.000, blue: 0.227)

    /// #D4FF3A α 0.42 — muted lime fill (chip backgrounds).
    static let brandAcidMuted = Color(red: 0.831, green: 1.000, blue: 0.227).opacity(0.42)

    /// #D4FF3A α 0.55 — lime glow (halo end frames, shadow tints).
    static let brandAcidGlow = Color(red: 0.831, green: 1.000, blue: 0.227).opacity(0.55)

    /// #FF3B30 — recording dot + fail state.
    static let recRed = Color(red: 1.000, green: 0.231, blue: 0.188)

    /// #30D158 — committed (already aliased via `success`; named alias for spec parity).
    static let commitGreen = Color(red: 0.188, green: 0.820, blue: 0.345)

    /// #5AC8FA — transcribing sweep + capsule border.
    static let transCyan = Color(red: 0.353, green: 0.784, blue: 0.980)

    /// #BF5AF2 — enhancing halo breath + arc spin.
    static let enhViolet = Color(red: 0.749, green: 0.353, blue: 0.949)
```

- [ ] **Step 3: Rewrite the existing `accent` / `accentMuted` / `accentGlow` constants as type-aliases to the new tokens**

```swift
    @available(*, deprecated, renamed: "brandAcid", message: "Use Palette.brandAcid (Sotto). Will be removed once all call sites migrate.")
    static let accent = brandAcid

    @available(*, deprecated, renamed: "brandAcidMuted")
    static let accentMuted = brandAcidMuted

    @available(*, deprecated, renamed: "brandAcidGlow")
    static let accentGlow = brandAcidGlow
```

Rationale: deprecated aliases keep the build green while sweep happens incrementally. Final removal is one of the last steps of Group A.

- [ ] **Step 4: Build & verify deprecation warnings appear**

Run: `make local` (per project memory — VoiceInk build via Make).
Expected: build succeeds; ~30–60 deprecation warnings on `Palette.accent` call sites.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Views/Common/Palette.swift
git commit -m "feat(hud): add brandAcid + state tokens; alias accent → brandAcid (deprecated)"
```

### Task A2: Sweep `Palette.accent` call sites to `Palette.brandAcid`

**Files:** all `*.swift` files in `VoiceInk/` flagged by the grep in A1.

- [ ] **Step 1: Sed-style sweep**

Use `Edit` with `replace_all: true` on each file flagged by the grep, replacing `Palette.accent` with `Palette.brandAcid`, `Palette.accentMuted` with `Palette.brandAcidMuted`, `Palette.accentGlow` with `Palette.brandAcidGlow`. Do not use shell `sed` (project rule — Edit tool preferred).

- [ ] **Step 2: Build clean**

Run: `make local`. Expected: zero deprecation warnings from the sweep set.

- [ ] **Step 3: Remove deprecated aliases**

Edit `VoiceInk/Views/Common/Palette.swift` — delete the three `@available(*, deprecated, ...)` shims added in A1 step 3.

- [ ] **Step 4: Build clean**

Run: `make local`. Expected: green.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/
git commit -m "refactor(hud): sweep Palette.accent → Palette.brandAcid; drop deprecated aliases"
```

### Task A3: Re-key `HaloPhase.glowColor` to state-tokened palette

**Files:**
- Modify: `VoiceInk/Views/Recorder/HaloMaterial.swift:21-48`

- [ ] **Step 1: Rewrite the `glowColor` switch**

Edit `VoiceInk/Views/Recorder/HaloMaterial.swift:22-34` — replace the switch body with the spec §4.2 mapping:

```swift
    var glowColor: Color {
        switch self {
        case .hidden:                   return .clear
        case .armed:                    return Palette.brandAcid     // breathing lime
        case .recording, .liveText:     return Palette.recRed         // red dot + halo
        case .transcribing:             return Palette.transCyan      // cyan sweep
        case .enhancing:                return Palette.enhViolet      // violet halo breath
        case .failed:                   return Palette.recRed         // red error blink
        case .done:                     return Palette.commitGreen    // green confirm halo
        }
    }
```

- [ ] **Step 2: Update `glowAlpha` for `.armed`**

Edit `VoiceInk/Views/Recorder/HaloMaterial.swift:38-46` — change `.armed` from `0.10` to `0.45` (breathing range 0.4–0.9 per spec §4.2). The alpha is still gated by the breathe driver; this is the *peak*.

```swift
        case .armed:                    return 0.45
```

- [ ] **Step 3: Build, then visually verify `HaloMaterial` previews**

Run: `make local`. Then open `VoiceInk/Views/Recorder/HaloMaterial.swift` in Xcode and trigger the SwiftUI `#Preview` blocks (`Onyx — recording`, `Onyx — enhancing`, etc.). Expected: recording preview now red, enhancing preview now violet.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Views/Recorder/HaloMaterial.swift
git commit -m "feat(hud): re-key HaloPhase glow colors to spec §4.2 state tokens"
```

### Task A4: Add `MotionTokens.swift`

**Files:**
- Create: `VoiceInk/Theme/MotionTokens.swift`

- [ ] **Step 1: Create directory + file**

Run: `mkdir -p VoiceInk/Theme`.

Write `VoiceInk/Theme/MotionTokens.swift`:

```swift
import SwiftUI

// MARK: - MotionTokens
//
// Pure value types. NO model-layer imports. Source of truth: spec §4.3.
// Each token = (duration, easing, repeatStyle). Caller composes via
// `.repeatForever(autoreverses:)` / `.delay(_:)` as needed.

enum MotionTokens {

    /// 1.0s red dot pulse (recording).
    static let pulse: Animation = .easeInOut(duration: 1.0)

    /// 0.8–1.1s staggered bar bounce (recording audio bars).
    /// Caller selects per-bar duration in `[0.8, 1.1]` and `.delay(_:)` offsets
    /// for the staggered effect.
    static let barsRangeMin: Double = 0.8
    static let barsRangeMax: Double = 1.1

    /// 1.4s cyan sweep L→R (transcribing).
    static let sweep: Animation = .linear(duration: 1.4)

    /// 1.6s violet halo breath (enhancing).
    static let breathe: Animation = .easeInOut(duration: 1.6)

    /// 1.2s arming border breathe.
    static let arming: Animation = .easeInOut(duration: 1.2)

    /// 0.8s red error blink (fail).
    static let blink: Animation = .easeInOut(duration: 0.8)

    /// 200ms dot bounce (transcribing menubar fallback; HUD does not use).
    static let dotJump: Animation = .easeOut(duration: 0.2)

    /// 1.6s violet arc spin (enhancing menubar; HUD does not use).
    static let spin: Animation = .linear(duration: 1.6)

    // MARK: - Cross-state durations

    /// Capsule + chip enter transition (180ms ease-out).
    static let stateEnter: Animation = .easeOut(duration: 0.18)

    /// Capsule + chip exit transition (140ms ease-in).
    static let stateExit: Animation = .easeIn(duration: 0.14)

    /// Committed-state hold before fade-out (1.5s).
    static let committedHold: TimeInterval = 1.5

    /// Committed fade-out (400ms).
    static let committedFade: Animation = .easeOut(duration: 0.4)

    // MARK: - Reduce Motion fallback

    /// 200ms opacity-only fade for users with Reduce Motion enabled.
    /// Every multi-second loop must degrade to this.
    static let reducedFade: Animation = .easeInOut(duration: 0.2)
}
```

- [ ] **Step 2: Build**

Run: `make local`. Expected: green; file compiles as a leaf module.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Theme/MotionTokens.swift
git commit -m "feat(hud): add MotionTokens — pure-value motion atoms per spec §4.3"
```

### Task A5: Add `TacticalGlass<S: Shape>` primitive + geometry tokens

**Files:**
- Create: `VoiceInk/Theme/TacticalGlass.swift`

- [ ] **Step 1: Write the wrapper**

Write `VoiceInk/Theme/TacticalGlass.swift`:

```swift
import SwiftUI

// MARK: - SottoGeometry
//
// Geometry tokens from spec §1.2. Constants exposed as a namespace so all
// Sotto surfaces (HUD, Settings, Main, Onboarding) consume the same values.

enum SottoGeometry {
    /// 2pt — matte app surfaces.
    static let cornerRadiusGlass: CGFloat = 2

    /// 8pt — Bay capsule + chips (bottom-only; hard top edge).
    static let cornerRadiusNotch: CGFloat = 8

    /// 6pt — Bay stalactites (slightly tighter than capsule).
    static let cornerRadiusStalactite: CGFloat = 6

    /// 0pt — brackets, dividers, tiles.
    static let cornerRadiusZero: CGFloat = 0

    /// 0.5pt — hairline border weight.
    static let hairline: CGFloat = 0.5

    /// 4pt — base spacing unit.
    static let spacingUnit: CGFloat = 4
}

// MARK: - TacticalGlass
//
// Sotto's primary material primitive. Thin wrapper over `HaloMaterial` that
// (a) fixes the spec defaults (onyx appearance, notch radius)
// (b) gives downstream callers a single import surface.
// Reviewers compare rendered output against `HaloMaterial` previews — the
// 8-layer compose remains the contract.

struct TacticalGlass<S: Shape>: View {
    let shape: S
    let phase: HaloPhase
    var breathePulse: Double = 0
    var showInnerSheen: Bool = false
    var appearance: GlassAppearance = .onyx

    var body: some View {
        HaloMaterial(
            shape: shape,
            phase: phase,
            breathePulse: breathePulse,
            showInnerSheen: showInnerSheen,
            appearance: appearance
        )
    }
}

// MARK: - Convenience initializers

extension TacticalGlass where S == BottomRoundedRectangle {
    /// Bay-style bottom-rounded glass — matches notch bottom-radius, hard top edge.
    static func bay(phase: HaloPhase, radius: CGFloat = SottoGeometry.cornerRadiusNotch) -> some View {
        TacticalGlass<BottomRoundedRectangle>(
            shape: BottomRoundedRectangle(bottomRadius: radius),
            phase: phase
        )
    }
}

// MARK: - BottomRoundedRectangle
//
// Hard top edge + rounded bottom corners. Spec §1.2 cornerRadiusNotch is
// "8pt bottom-only" — `RoundedRectangle` rounds all four corners, so we draw
// the path manually.

struct BottomRoundedRectangle: Shape {
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(bottomRadius, min(rect.width, rect.height) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(0), endAngle: .degrees(90),
                 clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r),
                 radius: r, startAngle: .degrees(90), endAngle: .degrees(180),
                 clockwise: false)
        p.closeSubpath()
        return p
    }
}
```

- [ ] **Step 2: Build**

Run: `make local`. Expected: green.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Theme/TacticalGlass.swift
git commit -m "feat(hud): add TacticalGlass primitive + BottomRoundedRectangle shape"
```

### Task A6: Open PR #1 (Group A)

- [ ] **Step 1: Push branch + open PR**

Branch name: `redesign/sotto-hud-a-material-primitives`.

```bash
git push -u origin redesign/sotto-hud-a-material-primitives
gh pr create --base redesign/sotto --title "HUD A — material primitives (palette + tokens + TacticalGlass)" --body "Group A of HUD plan. Adds Acid Lime palette tokens, MotionTokens, TacticalGlass primitive + BottomRoundedRectangle. No HUD behavior change; tangerine → lime recolor side-effect is visible in existing Mini & Notch surfaces. Spec: docs/superpowers/specs/2026-05-11-sotto-ui-redesign-design.md §1."
```

---

## Group B — Bay structure

**Goal:** New `BayHUDView` renders 3 fixed-x-offset subviews into the existing `NotchRecorderPanel`. Gated behind `SottoBayHUDEnabled` flag, default off. Existing `ConstellationCluster` stays the default for both Notch and Mini.

### Task B1: Add `RecorderUIState` observable

**Files:**
- Create: `VoiceInk/Views/Recorder/Bay/RecorderUIState.swift`

- [ ] **Step 1: Create dir + write file**

Run: `mkdir -p VoiceInk/Views/Recorder/Bay/States VoiceInk/Views/Recorder/Bay/Atoms`.

Write `VoiceInk/Views/Recorder/Bay/RecorderUIState.swift`:

```swift
import SwiftUI
import Combine

// MARK: - RecorderUIState
//
// Single observable for the Bay HUD subtree. Bridges engine-side
// `RecordingState` + view-side `HaloPhase` lifetimes (sourced from
// `RecorderUIManager.phase`) + per-state payload (audio level, prompt name,
// error code, paste event). All three Bay subviews observe this object.
//
// Lives for the lifetime of the BayHUDView subtree — not the app. Unmounts
// when `phase == .hidden` and the SwiftUI tree returns `EmptyView`.

@MainActor
final class RecorderUIState: ObservableObject {
    @Published var phase: HaloPhase = .hidden
    @Published var audioLevel: Double = 0
    @Published var recordingStartedAt: Date?
    @Published var activePromptLabel: String?     // §2.3 — already-truncated 9-char uppercase, or nil
    @Published var errorCode: String?              // §4.2 fail — "ERR · NO_DEVICE" etc.
    @Published var lastPasteAppName: String?
}
```

- [ ] **Step 2: Build**

Run: `make local`.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Views/Recorder/Bay/RecorderUIState.swift
git commit -m "feat(hud): add RecorderUIState — Bay subtree observable"
```

### Task B2: Add `BayHUDView` shell + 3 stalactite stubs

**Files:**
- Create: `VoiceInk/Views/Recorder/Bay/BayHUDView.swift`
- Create: `VoiceInk/Views/Recorder/Bay/BayCapsule.swift`
- Create: `VoiceInk/Views/Recorder/Bay/BayLeftStalactite.swift`
- Create: `VoiceInk/Views/Recorder/Bay/BayRightStalactite.swift`

- [ ] **Step 1: Write `BayHUDView.swift`**

```swift
import SwiftUI

// MARK: - BayHUDView
//
// Root of the Sotto notch HUD subtree. Mounts into the same NSHostingView
// rooted by NotchRecorderPanel.contentView — replaces ConstellationContainer
// for `.notch` mode only (`.mini` still uses ConstellationContainer).
//
// Layout (spec §2.2): three fixed-x-offset subviews on a ZStack the size of
// the full-width strip panel. Y-offset measured from top of panel
// (=top of screen, since NotchRecorderPanel is anchored to screen.maxY).

struct BayHUDView<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @ObservedObject var uiManager: RecorderUIManager
    @StateObject private var ui = RecorderUIState()

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let screenWidth = NSScreen.main?.frame.width ?? 1440
        let centerX = screenWidth / 2

        ZStack(alignment: .topLeading) {
            // Central capsule — 220×44, centered horizontally, 22pt from top.
            BayCapsule(ui: ui)
                .frame(width: 220, height: 44)
                .position(x: centerX, y: 22 + 22)   // y = top-offset + half-height

            // Left stalactite — 78×28, x = centerX − 118, y = 38 (+ half-height).
            BayLeftStalactite(ui: ui)
                .frame(width: 78, height: 28)
                .position(x: centerX - 118, y: 38 + 14)
                .allowsHitTesting(false)   // display-only

            // Right stalactite — 78×28, x = centerX + 118, y = 38.
            // Mouse-actionable — opt this subview out of the panel-wide
            // ignoresMouseEvents passthrough via .allowsHitTesting(true).
            BayRightStalactite(ui: ui)
                .frame(width: 78, height: 28)
                .position(x: centerX + 118, y: 38 + 14)
                .allowsHitTesting(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(ui.phase == .hidden ? 0 : 1)
        // Single withAnimation driver — every state change animates
        // capsule + both chips together.
        .animation(reduceMotion ? MotionTokens.reducedFade : MotionTokens.stateEnter,
                   value: ui.phase)
        .onAppear { syncFromManager() }
        .onChange(of: uiManager.phase) { _, _ in syncFromManager() }
        .onChange(of: stateProvider.recordingState) { _, _ in syncFromManager() }
        .onChange(of: recorder.audioMeter.averagePower) { _, lvl in
            ui.audioLevel = lvl
        }
    }

    private func syncFromManager() {
        ui.phase = uiManager.phase
        ui.recordingStartedAt = uiManager.recordingStartedAt
        ui.activePromptLabel = uiManager.formattedActivePromptLabel
        ui.errorCode = uiManager.currentErrorCode
        ui.lastPasteAppName = uiManager.lastPasteAppName
    }
}
```

> Note: `uiManager.phase`, `uiManager.recordingStartedAt`, `uiManager.formattedActivePromptLabel`, `uiManager.currentErrorCode`, `uiManager.lastPasteAppName` are added in Group C (Task C1).

- [ ] **Step 2: Write `BayCapsule.swift` stub**

```swift
import SwiftUI

struct BayCapsule: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        TacticalGlass.bay(phase: ui.phase)
            .overlay(content)
    }

    @ViewBuilder
    private var content: some View {
        switch ui.phase {
        case .hidden:           EmptyView()
        case .armed:            ArmingContent(ui: ui)
        case .recording, .liveText: RecordingContent(ui: ui)
        case .transcribing:     TranscribingContent(ui: ui)
        case .enhancing:        EnhancingContent(ui: ui)
        case .done:             CommittedContent(ui: ui)
        case .failed:           FailContent(ui: ui)
        }
    }
}

// Placeholder content views — implemented in Group D.
struct ArmingContent: View      { @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
struct RecordingContent: View   { @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
struct TranscribingContent: View{ @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
struct EnhancingContent: View   { @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
struct CommittedContent: View   { @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
struct FailContent: View        { @ObservedObject var ui: RecorderUIState; var body: some View { Color.clear } }
```

> Group D replaces each placeholder body. Stubs here so Group B can land green.

- [ ] **Step 3: Write `BayLeftStalactite.swift` (PROMPT chip)**

```swift
import SwiftUI

struct BayLeftStalactite: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        if shouldShow {
            TacticalGlass(
                shape: BottomRoundedRectangle(bottomRadius: SottoGeometry.cornerRadiusStalactite),
                phase: ui.phase
            )
            .overlay(
                Text(ui.activePromptLabel ?? "")
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .tracking(0.16 * 10.5)
                    .foregroundStyle(Palette.brandAcid)
                    .accessibilityLabel("Prompt \(ui.activePromptLabel ?? "")")
            )
            .transition(.opacity.animation(MotionTokens.stateEnter))
        }
    }

    private var shouldShow: Bool {
        guard let label = ui.activePromptLabel, !label.isEmpty else { return false }
        switch ui.phase {
        case .recording, .liveText: return true
        default: return false
        }
    }
}
```

- [ ] **Step 4: Write `BayRightStalactite.swift` (SAVE / UNDO chip)**

```swift
import SwiftUI

struct BayRightStalactite: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        if let action = currentAction {
            Button(action: action.handler) {
                TacticalGlass(
                    shape: BottomRoundedRectangle(bottomRadius: SottoGeometry.cornerRadiusStalactite),
                    phase: ui.phase
                )
                .overlay(
                    Text("\u{25B8} \(action.label)")    // U+25B8 ▸ tappable glyph
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .tracking(0.16 * 10.5)
                        .foregroundStyle(Palette.brandAcid)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(action.label)
            .transition(.opacity.animation(MotionTokens.stateEnter))
        }
    }

    private struct Action {
        let label: String
        let handler: () -> Void
    }

    private var currentAction: Action? {
        switch ui.phase {
        case .recording, .liveText:
            return Action(label: "SAVE") {
                NotificationCenter.default.post(name: .voiceInkSaveRecording, object: nil)
            }
        case .done:
            return Action(label: "UNDO") {
                NotificationCenter.default.post(name: .voiceInkUndoLastPaste, object: nil)
            }
        default:
            return nil
        }
    }
}

extension Notification.Name {
    static let voiceInkSaveRecording = Notification.Name("voiceInkSaveRecording")
    static let voiceInkUndoLastPaste = Notification.Name("voiceInkUndoLastPaste")
}
```

> Wiring the `save` / `undo` notification handlers is engine-side work — out of scope here. The HUD posts the intent; receiver lives in `VoiceInkEngine` / `RecorderUIManager` and is a follow-up ticket. Spec §2.3 lists the chips but engine handlers are not in HUD scope.

- [ ] **Step 5: Build**

Run: `make local`. Expected: green. (Will fail until C1 lands `uiManager.phase` etc. — temporarily stub by changing `BayHUDView` to read `uiManager.recorderType` or hardcode `.hidden`; revert in C1.)

> **Workaround for build green in this PR:** in `BayHUDView.syncFromManager()`, replace the body with `ui.phase = .hidden` so the new manager fields aren't required yet. Group C wires the real reads.

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Views/Recorder/Bay/
git commit -m "feat(hud): scaffold BayHUDView + capsule + stalactite stubs (mount unwired)"
```

### Task B3: Wire `BayHUDView` into `HaloRecorderView` behind feature flag

**Files:**
- Modify: `VoiceInk/Views/Recorder/HaloRecorderView.swift`

- [ ] **Step 1: Add the branch**

Edit `VoiceInk/Views/Recorder/HaloRecorderView.swift` — extend the body:

```swift
struct HaloRecorderView<S: RecorderStateProvider & ObservableObject, WM: ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @ObservedObject var windowManager: WM
    var isVisible: () -> Bool
    var mode: HaloShape.Mode

    @AppStorage("SottoBayHUDEnabled") private var bayEnabled: Bool = false

    var body: some View {
        if isVisible() {
            if mode == .notch && bayEnabled {
                BayHUDViewHost(
                    stateProvider: stateProvider,
                    recorder: recorder,
                    aiService: aiService
                )
            } else {
                ConstellationContainer(
                    stateProvider: stateProvider,
                    recorder: recorder,
                    aiService: aiService,
                    mode: mode
                )
            }
        }
    }
}

/// Host wrapper — pulls `RecorderUIManager` out of the environment so we
/// don't have to touch `NotchWindowManager`'s constructor surface.
private struct BayHUDViewHost<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @EnvironmentObject var uiManager: RecorderUIManager

    var body: some View {
        BayHUDView(
            stateProvider: stateProvider,
            recorder: recorder,
            aiService: aiService,
            uiManager: uiManager
        )
    }
}
```

- [ ] **Step 2: Inject `RecorderUIManager` env-object in `NotchWindowManager`**

Edit `VoiceInk/Views/Recorder/NotchWindowManager.swift:19-39` — add `.environmentObject(RecorderUIManagerProvider.shared.manager)` to the `AnyView(...)` block. Or pass `uiManager` through the constructor; check what `VoiceInk.swift` line ~158 provides at the call site.

> Check the actual `RecorderUIManager` initialization site:

Run: `grep -n 'RecorderUIManager()' VoiceInk/VoiceInk.swift`. The `@StateObject` lives on the App's `body`, so it must be passed into `NotchWindowManager.init` and injected as env-object.

Decision: modify `NotchWindowManager.init` to accept `uiManager: RecorderUIManager`, store it weakly, and inject via `.environmentObject(uiManager)`. Update the one caller (`RecorderUIManager.showRecorderPanel` line ~104).

- [ ] **Step 3: Build**

Run: `make local`. Expected: green; Bay subtree not visible (flag is off).

- [ ] **Step 4: Manual smoke test**

Run: `make reload`. Trigger recording via hotkey. Expected: existing ConstellationCluster renders as before — Bay subtree is dormant.

Flip the flag manually via `defaults write com.prakashjoshipax.VoiceInk SottoBayHUDEnabled -bool YES` and restart. Expected: empty Bay subtree mounts (no visible content — placeholders are `Color.clear`); ConstellationCluster does NOT render.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Views/Recorder/HaloRecorderView.swift VoiceInk/Views/Recorder/NotchWindowManager.swift
git commit -m "feat(hud): wire BayHUDView into HaloRecorderView behind SottoBayHUDEnabled flag"
```

### Task B4: Open PR #2 (Group B)

- [ ] **Step 1: Push + open PR**

Branch: `redesign/sotto-hud-b-structure`.

```bash
git push -u origin redesign/sotto-hud-b-structure
gh pr create --base redesign/sotto --title "HUD B — Bay structure scaffold (gated)" --body "Group B. Adds RecorderUIState + BayHUDView + 3 stalactite subviews mounting into NotchRecorderPanel's existing single-panel topology. Gated behind SottoBayHUDEnabled flag (default off). Placeholder per-state content (Color.clear) — Group D fills them in. Spec: §2."
```

---

## Group C — State machinery

**Goal:** `RecorderUIManager` publishes a single `phase: HaloPhase` that respects view-lifetime rules (`.done` 1.5s, `.failed` until-dismissed) and activates `.armed`. First-audio detection gates `.armed → .recording` transition.

### Task C1: Extend `RecorderUIManager` with phase + view-lifetime state

**Files:**
- Modify: `VoiceInk/Transcription/Engine/RecorderUIManager.swift`

- [ ] **Step 1: Add the published phase + payload fields**

Edit `VoiceInk/Transcription/Engine/RecorderUIManager.swift` — insert after `@Published var miniRecorderError` (~line 8):

```swift
    // MARK: - Bay HUD phase observable
    //
    // View-lifetime HaloPhase. Engine-side `RecordingState` collapses to
    // `.idle` on commit and on failure; the Bay HUD needs `.done` to dwell
    // 1.5s and `.failed` to persist until dismissed. This property is the
    // single source of truth for the BayHUDView subtree.

    @Published var phase: HaloPhase = .hidden
    @Published var recordingStartedAt: Date?
    @Published var formattedActivePromptLabel: String?
    @Published var currentErrorCode: String?
    @Published var lastPasteAppName: String?

    private var phaseObservers = Set<AnyCancellable>()
    private var doneHoldTask: Task<Void, Never>?
```

- [ ] **Step 2: Wire engine → phase mapping**

Add a private method to `RecorderUIManager`:

```swift
    private func setupPhaseObservers(engine: VoiceInkEngine, registry: FailureRegistry) {
        // 1. Engine recordingState → phase (the common case).
        engine.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.mapEngineState(state, engine: engine)
            }
            .store(in: &phaseObservers)

        // 2. Failure event → .failed (overrides engine state).
        registry.$current
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                if let event {
                    self.currentErrorCode = Self.errorCode(from: event)
                    self.phase = .failed
                } else if self.phase == .failed {
                    self.phase = .hidden
                    self.currentErrorCode = nil
                }
            }
            .store(in: &phaseObservers)

        // 3. Paste event → .done (1.5s hold then idle).
        engine.$lastPasteEvent
            .compactMap { $0 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.beginDoneHold(appName: event.appName)
            }
            .store(in: &phaseObservers)
    }

    private func mapEngineState(_ state: RecordingState, engine: VoiceInkEngine) {
        // Don't clobber view-lifetime states.
        if phase == .done || phase == .failed { return }

        switch state {
        case .idle, .busy:
            phase = .hidden
            recordingStartedAt = nil
        case .starting:
            phase = .armed
            if recordingStartedAt == nil { recordingStartedAt = .now }
        case .recording:
            // Arming → recording gated by first-audio. If FirstAudioGate
            // hasn't fired yet, hold .armed. Once observed, flip.
            phase = engine.firstAudioObserved ? .recording : .armed
            if recordingStartedAt == nil { recordingStartedAt = .now }
        case .transcribing:
            phase = .transcribing
        case .enhancing:
            phase = .enhancing
        }

        formattedActivePromptLabel = Self.formatPromptLabel(
            engine.enhancementService?.activePrompt?.title
        )
    }

    private func beginDoneHold(appName: String?) {
        doneHoldTask?.cancel()
        lastPasteAppName = appName
        phase = .done
        doneHoldTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(MotionTokens.committedHold))
            guard !Task.isCancelled, let self else { return }
            if self.phase == .done {
                self.phase = .hidden
                self.lastPasteAppName = nil
            }
        }
    }

    /// Spec §2.3: truncate to 9 chars uppercase; hide chip if nil/empty.
    private static func formatPromptLabel(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let upper = raw.uppercased()
        if upper.count <= 9 { return upper }
        let idx = upper.index(upper.startIndex, offsetBy: 9)
        return String(upper[..<idx])
    }

    /// Spec §4.2: fail shows `ERR · {DOMAIN}_{REASON}` monospace uppercase.
    /// Engine emits free-text reasons today; this is a heuristic mapping.
    /// HUD spike B.ErrorCodes can refine after telemetry; v1 mapping below.
    private static func errorCode(from event: FailureEvent) -> String {
        let r = event.reason.uppercased()
        if r.contains("MODEL")          { return "ERR · NO_MODEL" }
        if r.contains("DEVICE") || r.contains("MIC") { return "ERR · NO_DEVICE" }
        if r.contains("NETWORK")        { return "ERR · NETWORK" }
        if r.contains("AUDIO")          { return "ERR · NO_AUDIO" }
        return "ERR · UNKNOWN"
    }
```

- [ ] **Step 3: Call `setupPhaseObservers` from `configure`**

Edit `RecorderUIManager.configure(...)` (line 67-73):

```swift
    func configure(engine: VoiceInkEngine, recorder: Recorder, failureRegistry: FailureRegistry) {
        self.engine = engine
        self.recorder = recorder
        self.failureRegistry = failureRegistry
        setupNotifications()
        setupFailureCueObserver(registry: failureRegistry)
        setupPhaseObservers(engine: engine, registry: failureRegistry)
    }
```

- [ ] **Step 4: Add manual-dismiss hook**

Spec §4.2 fail row: "click HUD or icon → idle". Add a public method:

```swift
    /// Manually dismiss `.failed` state (called when user clicks the HUD,
    /// menubar icon, or the chip). Acks the registry too.
    func dismissFailedPhase() {
        guard phase == .failed else { return }
        failureRegistry?.acknowledgeCurrent()
        // The registry sink will flip phase back to .hidden.
    }
```

> If `FailureRegistry.acknowledgeCurrent()` does not exist, add a thin wrapper — `acknowledge(self.current?.id)`. Confirm by reading `FailureRegistry.swift`.

- [ ] **Step 5: Revert the `BayHUDView.syncFromManager` workaround from B2 step 5**

Edit `VoiceInk/Views/Recorder/Bay/BayHUDView.swift` — restore the real reads.

- [ ] **Step 6: Build**

Run: `make local`. Expected: green.

- [ ] **Step 7: Smoke test**

Run: `make reload`. Flip flag on, trigger record → stop → paste cycle. Expected: nothing renders yet (state content is still `Color.clear`), but the `phase` transitions can be verified via Console.app subsystem `com.prakashjoshipax.voiceink` category `RecorderUIManager` — log additions are step 8.

- [ ] **Step 8: Add diagnostic logging**

In `setupPhaseObservers`, log every phase transition:

```swift
        $phase
            .removeDuplicates()
            .sink { [weak self] new in
                self?.logger.notice("phase → \(String(describing: new), privacy: .public)")
            }
            .store(in: &phaseObservers)
```

Verify in Console.app: phase transitions `.hidden → .armed → .recording → .transcribing → .enhancing → .done → .hidden` over a typical record.

- [ ] **Step 9: Commit**

```bash
git add VoiceInk/Transcription/Engine/RecorderUIManager.swift VoiceInk/Views/Recorder/Bay/BayHUDView.swift
git commit -m "feat(hud): RecorderUIManager publishes HaloPhase with view-lifetime rules (.done 1.5s, .failed dismiss)"
```

### Task C2: Add `FirstAudioGate`

**Files:**
- Create: `VoiceInk/Transcription/Engine/FirstAudioGate.swift`
- Modify: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`
- Modify: `VoiceInk/Views/Recorder/RecorderStateProvider.swift`

- [ ] **Step 1: Write the gate**

Write `VoiceInk/Transcription/Engine/FirstAudioGate.swift`:

```swift
import Foundation
import Combine

// MARK: - FirstAudioGate
//
// Detects the first non-silent audio frame after `start()`. Spec §4.2:
// `.armed → .recording` flips on first audio. Threshold pinned at
// -50 dBFS provisionally (B.FirstAudio spike). Reset on every fresh
// `start()` call.

@MainActor
final class FirstAudioGate: ObservableObject {
    /// dBFS threshold below which a frame counts as silence. Spec B.FirstAudio.
    static let silenceThreshold: Float = -50.0

    /// `true` once a frame above threshold has been observed since `start()`.
    @Published private(set) var observed: Bool = false

    func start() {
        observed = false
    }

    /// Called on every audio-meter tick from `CoreAudioRecorder` /
    /// `Recorder.startMonitoringMeter`. Threshold check is one-way:
    /// observed flips false→true and stays.
    func consume(rawDb: Float) {
        if observed { return }
        if rawDb >= Self.silenceThreshold {
            observed = true
        }
    }

    func reset() {
        observed = false
    }
}
```

- [ ] **Step 2: Wire into `VoiceInkEngine`**

Edit `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` — add a property:

```swift
    /// Spec §4.2 first-audio gate. `RecorderUIManager.mapEngineState` reads
    /// `firstAudioObserved` to decide whether to render `.armed` or `.recording`.
    let firstAudioGate = FirstAudioGate()

    var firstAudioObserved: Bool { firstAudioGate.observed }
```

Find the `toggleRecord(...)` start branch and the recording-stop branch in `VoiceInkEngine.swift`:
- On record start → call `firstAudioGate.start()`.
- On record stop / cancel → call `firstAudioGate.reset()`.

Find the audio-meter tick (likely in `Recorder.startMonitoringMeter` ~line 200) and have it forward the raw dB:

In `Recorder.swift:204` after `let averagePower = recorder.averagePower`, post via NotificationCenter or expose a closure. Cleanest path: add a closure property on `Recorder`:

```swift
    /// Forwarded raw dB on each meter tick. `VoiceInkEngine` sets this in
    /// its init to feed the FirstAudioGate.
    var onRawAudioDb: ((Float) -> Void)?
```

Then in the meter loop: `onRawAudioDb?(averagePower)`.

In `VoiceInkEngine.init` (or `configure`):
```swift
        recorder.onRawAudioDb = { [weak self] db in
            Task { @MainActor in self?.firstAudioGate.consume(rawDb: db) }
        }
```

- [ ] **Step 3: Extend `RecorderStateProvider`**

Edit `VoiceInk/Views/Recorder/RecorderStateProvider.swift:57-72` — add:

```swift
    /// Spec §4.2: first-audio gate. View layer reads this to decide whether
    /// to render `.armed` or `.recording` during the `.starting` / early-
    /// `.recording` engine window.
    var firstAudioObserved: Bool { get }
```

Already conformed by `VoiceInkEngine` via the computed property above. Add a mock implementation in any test/stub provider.

- [ ] **Step 4: Build**

Run: `make local`. Expected: green.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Transcription/Engine/FirstAudioGate.swift VoiceInk/Transcription/Engine/VoiceInkEngine.swift VoiceInk/Recorder.swift VoiceInk/Views/Recorder/RecorderStateProvider.swift
git commit -m "feat(hud): FirstAudioGate (-50dBFS) gates .armed → .recording transition"
```

### Task C3: Open PR #3 (Group C)

- [ ] **Step 1: Push + open PR**

Branch: `redesign/sotto-hud-c-state-machinery`.

```bash
git push -u origin redesign/sotto-hud-c-state-machinery
gh pr create --base redesign/sotto --title "HUD C — RecorderUIManager.phase + FirstAudioGate" --body "Group C. RecorderUIManager publishes a single HaloPhase with view-lifetime rules (.done 1.5s hold, .failed until-dismissed, .armed activated). FirstAudioGate (-50dBFS) gates .armed→.recording. No visible change; Bay subtree still renders Color.clear placeholders. Spec: §4.1, §4.2, Appendix B.FirstAudio."
```

---

## Group D — Per-state implementation

**Goal:** Replace each placeholder content view in `BayCapsule` with the spec §4.2 visuals. Flip the feature flag on at PR end.

### Task D1: `RecDot` + `AudioBars` atoms

**Files:**
- Create: `VoiceInk/Views/Recorder/Bay/Atoms/RecDot.swift`
- Create: `VoiceInk/Views/Recorder/Bay/Atoms/AudioBars.swift`
- Create: `VoiceInk/Views/Recorder/Bay/Atoms/MonoLabel.swift`

- [ ] **Step 1: `MonoLabel.swift`**

```swift
import SwiftUI

struct MonoLabel: View {
    let text: String
    var size: CGFloat = 11
    var tracking: CGFloat = 0.16
    var color: Color = Palette.brandAcid

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .bold, design: .monospaced))
            .tracking(tracking * size)
            .foregroundStyle(color)
            .accessibilityLabel(text)
    }
}
```

- [ ] **Step 2: `RecDot.swift`**

```swift
import SwiftUI

struct RecDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    var body: some View {
        Circle()
            .fill(Palette.recRed)
            .frame(width: 8, height: 8)
            .scaleEffect(reduceMotion ? 1 : (pulse ? 1.15 : 0.9))
            .opacity(reduceMotion ? 1 : (pulse ? 1 : 0.7))
            .animation(reduceMotion ? nil : MotionTokens.pulse.repeatForever(autoreverses: true),
                       value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 3: `AudioBars.swift`**

5 lime bars, heights modulated by `ui.audioLevel`, with staggered 0.8–1.1s ease-in-out animation. Spec §4.2.

```swift
import SwiftUI

struct AudioBars: View {
    let level: Double         // normalized 0…1
    let frozen: Bool          // `true` during .transcribing — bars hold last value, faint
    let tint: Color           // .brandAcid during .recording, .transCyan when frozen

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(tint.opacity(frozen ? 0.35 : 1))
                    .frame(width: 2.5, height: heightFor(index: i))
            }
        }
        .onAppear { if !reduceMotion && !frozen { phase = 1 } }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                   value: phase)
        .accessibilityHidden(true)
    }

    private func heightFor(index i: Int) -> CGFloat {
        // Staggered per-bar phase by index. Cap height range 6–18pt.
        let stagger = Double(i) * 0.18
        let base = reduceMotion ? 0.5 : 0.4 + 0.6 * (0.5 + 0.5 * sin(phase * .pi + stagger))
        let scaled = base * level.clamped(to: 0.2...1.0)
        return CGFloat(6 + scaled * 12)
    }
}

private extension Double {
    func clamped(to r: ClosedRange<Double>) -> Double { min(max(self, r.lowerBound), r.upperBound) }
}
```

- [ ] **Step 4: Build + commit**

```bash
git add VoiceInk/Views/Recorder/Bay/Atoms/
git commit -m "feat(hud): add RecDot, AudioBars, MonoLabel atoms"
```

### Task D2: `ArmingContent` — breathing lime border + LISTENING

**Files:**
- Modify: `VoiceInk/Views/Recorder/Bay/States/ArmingContent.swift` (split out from BayCapsule.swift stub)

- [ ] **Step 1: Extract `ArmingContent` to its own file**

```swift
// VoiceInk/Views/Recorder/Bay/States/ArmingContent.swift
import SwiftUI

struct ArmingContent: View {
    @ObservedObject var ui: RecorderUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: Double = 0.4

    var body: some View {
        HStack(spacing: 8) {
            // Ghost dot pulses
            Circle()
                .fill(Palette.brandAcid.opacity(reduceMotion ? 0.7 : breath))
                .frame(width: 6, height: 6)

            MonoLabel(text: "LISTENING", size: 10.5)
        }
        .onAppear {
            guard !reduceMotion else { return }
            breath = 0.9
        }
        .animation(reduceMotion ? nil : MotionTokens.arming.repeatForever(autoreverses: true),
                   value: breath)
        .accessibilityLabel("Listening")
        .accessibilityAddTraits(.isHeader)
    }
}
```

- [ ] **Step 2: Delete the stub `ArmingContent` from `BayCapsule.swift`**

Remove the placeholder line `struct ArmingContent: View { ... Color.clear ... }` from `BayCapsule.swift`.

- [ ] **Step 3: Build + smoke test**

`make reload`, flag on, trigger recording. Expected: brief `LISTENING` capsule before audio kicks in.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Views/Recorder/Bay/
git commit -m "feat(hud): ArmingContent — breathing lime border + LISTENING label"
```

### Task D3: `RecordingContent` — red dot + 5 bars + REC mm:ss

**Files:**
- Create: `VoiceInk/Views/Recorder/Bay/States/RecordingContent.swift`

- [ ] **Step 1: Write content**

```swift
import SwiftUI

struct RecordingContent: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        HStack(spacing: 10) {
            RecDot()
            AudioBars(level: ui.audioLevel, frozen: false, tint: Palette.brandAcid)
            if let startedAt = ui.recordingStartedAt {
                ElapsedLabel(startedAt: startedAt)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(axLabel)
    }

    private var axLabel: String {
        guard let started = ui.recordingStartedAt else { return "Recording" }
        let elapsed = Int(Date().timeIntervalSince(started))
        return "Recording, \(elapsed / 60) minutes \(elapsed % 60) seconds"
    }
}

private struct ElapsedLabel: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1.0)) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(startedAt))
            let m = Int(elapsed) / 60
            let s = Int(elapsed) % 60
            MonoLabel(text: String(format: "REC %02d:%02d", m, s), size: 10.5, color: Palette.brandAcid)
        }
    }
}
```

- [ ] **Step 2: Delete stub from `BayCapsule.swift`**

- [ ] **Step 3: Build + smoke test**

Trigger recording, talk → bars animate, timer counts up, red dot pulses.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Views/Recorder/Bay/
git commit -m "feat(hud): RecordingContent — RecDot + AudioBars + REC mm:ss"
```

### Task D4: `TranscribingContent` — cyan sweep + frozen bars

**Files:**
- Create: `VoiceInk/Views/Recorder/Bay/Atoms/CyanSweep.swift`
- Create: `VoiceInk/Views/Recorder/Bay/States/TranscribingContent.swift`

- [ ] **Step 1: `CyanSweep.swift`**

```swift
import SwiftUI

struct CyanSweep: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t: Double = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(
                colors: [.clear, Palette.transCyan.opacity(0.6), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: w * 0.35)
            .offset(x: reduceMotion ? 0 : (-w * 0.35 + (w + w * 0.35) * t))
            .opacity(reduceMotion ? 0.4 : 1)
            .onAppear { if !reduceMotion { t = 1 } }
            .animation(reduceMotion ? nil : MotionTokens.sweep.repeatForever(autoreverses: false),
                       value: t)
        }
        .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: `TranscribingContent.swift`**

```swift
import SwiftUI

struct TranscribingContent: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        ZStack {
            CyanSweep()
            HStack(spacing: 10) {
                AudioBars(level: ui.audioLevel, frozen: true, tint: Palette.transCyan)
                MonoLabel(text: "TRANSCRIBING…", size: 10.5, color: Palette.transCyan)
            }
        }
        .accessibilityLabel("Transcribing")
    }
}
```

- [ ] **Step 3: Build + smoke test**

Trigger record → stop. Expected: cyan band sweeps L→R 1.4s while transcription runs.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Views/Recorder/Bay/
git commit -m "feat(hud): TranscribingContent — cyan sweep + frozen bars"
```

### Task D5: `EnhancingContent` — violet halo breath

**Files:**
- Create: `VoiceInk/Views/Recorder/Bay/States/EnhancingContent.swift`

- [ ] **Step 1: Write content**

```swift
import SwiftUI

struct EnhancingContent: View {
    @ObservedObject var ui: RecorderUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breath: Double = 0.25

    var body: some View {
        HStack(spacing: 10) {
            AudioBars(level: 0.3, frozen: true, tint: Palette.enhViolet)
            MonoLabel(text: "ENHANCING…", size: 10.5, color: Palette.enhViolet)
        }
        // Breathe overlay — modulates the TacticalGlass via HaloMaterial's
        // `showInnerSheen` path. Achieved by sending breathePulse upward.
        .preference(key: BreathePulseKey.self, value: reduceMotion ? 0.5 : breath)
        .onAppear { if !reduceMotion { breath = 0.6 } }
        .animation(reduceMotion ? nil : MotionTokens.breathe.repeatForever(autoreverses: true),
                   value: breath)
        .accessibilityLabel("Enhancing")
    }
}

struct BreathePulseKey: PreferenceKey {
    static var defaultValue: Double = 0
    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}
```

- [ ] **Step 2: Pipe breathe pulse into `BayCapsule`**

Edit `BayCapsule.swift` — wire `.onPreferenceChange(BreathePulseKey.self)` to a local state, and pass it as `breathePulse:` to `TacticalGlass.bay(...)`. Update the convenience init to accept the param:

```swift
struct BayCapsule: View {
    @ObservedObject var ui: RecorderUIState
    @State private var breathePulse: Double = 0

    var body: some View {
        TacticalGlass(
            shape: BottomRoundedRectangle(bottomRadius: SottoGeometry.cornerRadiusNotch),
            phase: ui.phase,
            breathePulse: breathePulse,
            showInnerSheen: ui.phase == .enhancing
        )
        .overlay(content)
        .onPreferenceChange(BreathePulseKey.self) { breathePulse = $0 }
    }
    // ... content @ViewBuilder unchanged
}
```

- [ ] **Step 3: Build + smoke test**

Trigger record → stop → wait for enhance. Expected: violet inner-sheen breathes 1.6s.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Views/Recorder/Bay/
git commit -m "feat(hud): EnhancingContent — violet halo breath via BreathePulseKey preference"
```

### Task D6: `CommittedContent` — green ✓ + halo

**Files:**
- Create: `VoiceInk/Views/Recorder/Bay/States/CommittedContent.swift`

- [ ] **Step 1: Write**

```swift
import SwiftUI

struct CommittedContent: View {
    @ObservedObject var ui: RecorderUIState

    var body: some View {
        HStack(spacing: 8) {
            // ✓ glyph — shape-based affordance (colorblind-safe, spec §1.X).
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Palette.commitGreen)

            MonoLabel(
                text: ui.lastPasteAppName.map { "PASTED → \($0.uppercased())" } ?? "PASTED",
                size: 10.5,
                color: Palette.commitGreen
            )
        }
        .accessibilityLabel(ui.lastPasteAppName.map { "Committed, pasted to \($0)" } ?? "Committed")
    }
}
```

- [ ] **Step 2: Build + smoke test**

Full record-paste cycle. Expected: green ✓ + label hold 1.5s, then HUD fades out. `▸ UNDO` chip visible in right stalactite during the hold.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Views/Recorder/Bay/
git commit -m "feat(hud): CommittedContent — green ✓ + PASTED → <app>"
```

### Task D7: `FailContent` — red ✗ + error code blink

**Files:**
- Create: `VoiceInk/Views/Recorder/Bay/States/FailContent.swift`

- [ ] **Step 1: Write**

```swift
import SwiftUI

struct FailContent: View {
    @ObservedObject var ui: RecorderUIState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var uiManager: RecorderUIManager
    @State private var blink: Bool = false

    var body: some View {
        Button(action: { uiManager.dismissFailedPhase() }) {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.recRed)
                    .opacity(reduceMotion ? 1 : (blink ? 1 : 0.4))

                MonoLabel(
                    text: ui.errorCode ?? "ERR · UNKNOWN",
                    size: 10.5,
                    color: Palette.recRed
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear { if !reduceMotion { blink = true } }
        .animation(reduceMotion ? nil : MotionTokens.blink.repeatForever(autoreverses: true),
                   value: blink)
        .accessibilityLabel("Failed, \(ui.errorCode ?? "unknown"). Tap to dismiss.")
    }
}
```

- [ ] **Step 2: Force a failure (no transcription model selected) and smoke**

Disable all transcription models in Settings, trigger record. Expected: `ERR · NO_MODEL` blinks until clicked.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Views/Recorder/Bay/
git commit -m "feat(hud): FailContent — red ✗ + error code blink, click-to-dismiss"
```

### Task D8: Flip the feature flag on by default

**Files:**
- Modify: `VoiceInk/Views/Recorder/HaloRecorderView.swift`

- [ ] **Step 1: Change default**

Edit `VoiceInk/Views/Recorder/HaloRecorderView.swift` — change `@AppStorage("SottoBayHUDEnabled") private var bayEnabled: Bool = false` to `= true`.

- [ ] **Step 2: Smoke test**

`make reload` on a clean user defaults (or wipe the key). Expected: Bay renders by default for Notch users.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Views/Recorder/HaloRecorderView.swift
git commit -m "feat(hud): default SottoBayHUDEnabled to true"
```

### Task D9: Open PR #4 (Group D)

- [ ] **Step 1: Push + open PR**

Branch: `redesign/sotto-hud-d-per-state`.

```bash
git push -u origin redesign/sotto-hud-d-per-state
gh pr create --base redesign/sotto --title "HUD D — per-state Bay content (flag on)" --body "Group D. Implements ArmingContent / RecordingContent / TranscribingContent / EnhancingContent / CommittedContent / FailContent. Atoms: RecDot, AudioBars, MonoLabel, CyanSweep. Flag SottoBayHUDEnabled defaults true. Spec: §4.2 state table."
```

---

## Group E — Accessibility

**Goal:** Reduce Motion fallbacks verified for every loop; VoiceOver labels on every Bay subview; ✓ / ✗ glyphs read independently of color; HC verified via existing `AdaptiveGlass`.

### Task E1: Audit Reduce Motion fallbacks

**Files:**
- Verify across all `States/*.swift` + `Atoms/*.swift`.

- [ ] **Step 1: System Settings → Accessibility → Display → Reduce Motion → ON**

`make reload`. Run through full state cycle. Expected per spec §1.X:
- `arming` breathe → static dot, label visible.
- `recording` dot pulse → static dot.
- `recording` bars → static 50% height.
- `transcribing` sweep → faint static cyan tint.
- `enhancing` breath → static violet inner sheen.
- `fail` blink → static red ✗.
- All state transitions → 200ms opacity-only fade.

Any state still animating → file as a fix-it in this PR.

- [ ] **Step 2: Fix any gaps**

For each animation token not gated by `reduceMotion`, add the gate. Pattern:
```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// ...
.animation(reduceMotion ? nil : MotionTokens.xxx, value: ...)
```

- [ ] **Step 3: Commit per fix**

### Task E2: VoiceOver labels on all Bay subviews

- [ ] **Step 1: Enable VO + cmd-F5**

Navigate across the HUD with VO. Expected per spec §1.X:
- Capsule announces state on transition: `"Recording, 0:12"`, `"Transcribing"`, `"Enhancing"`, `"Committed, pasted to Mail"`, `"Failed, ERR NO_MODEL. Tap to dismiss."`
- Left stalactite: `"Prompt {NAME}"` when visible.
- Right stalactite during `.recording`: `"Save"`. During `.done`: `"Undo"`.

- [ ] **Step 2: Fix gaps**

Each `*Content` view should have an explicit `.accessibilityLabel(...)` covering the full state announcement. `AccessibilityNotification.announcement(...)` on phase transition is the ceiling — defer to a follow-up unless trivial.

- [ ] **Step 3: Commit**

### Task E3: High Contrast smoke

- [ ] **Step 1: System Settings → Accessibility → Display → Increase Contrast → ON**

`make reload`. Expected per spec §1.X: `AdaptiveGlass` branch in `HaloMaterial` fires — opaque fills, 1pt solid strokes in state color, halo glows suppressed. Bay subviews inherit this for free (they use TacticalGlass which wraps HaloMaterial).

Any visible regression (e.g. bars or chip text becomes unreadable on the opaque surface) → file as fix-it.

- [ ] **Step 2: Commit fixes**

### Task E4: Open PR #5 (Group E)

Branch: `redesign/sotto-hud-e-a11y`.

```bash
git push -u origin redesign/sotto-hud-e-a11y
gh pr create --base redesign/sotto --title "HUD E — accessibility (RM, VO, HC, color-safe glyphs)" --body "Group E. Verifies Reduce Motion fallbacks on every loop, VoiceOver state announcements, High Contrast via existing AdaptiveGlass branch. Spec §1.X."
```

---

## Group F — Spikes + open-behavior pins

**Goal:** Resolve Appendix B spikes in HUD scope and codify the chosen behavior. Remove `SottoBayHUDEnabled` flag.

### Task F1: B.MultiMonitor — multi-monitor anchoring

**Files:**
- Modify: `VoiceInk/Views/Recorder/NotchRecorderPanel.swift:76-103` (`calculateWindowMetrics`)

- [ ] **Step 1: Manually test 3 setups**

(a) Notched MBP only.
(b) Notched MBP + external monitor — external is `.main` via System Settings → Displays → Main Display.
(c) External-only (clamshell mode).

Run through full record cycle on each. Document where the Bay anchors.

- [ ] **Step 2: Decide policy**

Default: follow `NSScreen.main`. On non-notch displays, fallback to the existing `180pt` virtual notch (already in code at line 89). Bay width is 220pt — wider than 180pt → adjust virtual-notch width to ≥220 for non-notch displays.

Edit `calculateWindowMetrics` line 84-90:

```swift
        let notchWidth: CGFloat = {
            if let left = screen.auxiliaryTopLeftArea?.width,
               let right = screen.auxiliaryTopRightArea?.width {
                return screen.frame.width - left - right
            }
            // Spec §2.2: Bay capsule is 220pt. Non-notch displays use a virtual
            // notch sized to the Bay so positioning math doesn't underrun.
            return 240
        }()
```

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Views/Recorder/NotchRecorderPanel.swift
git commit -m "fix(hud): widen virtual-notch fallback to 240pt for Bay on non-notch displays"
```

### Task F2: B.ArmingSkip — measure mic-init times

- [ ] **Step 1: Add timing log**

In `VoiceInkEngine.toggleRecord` start branch, capture `startTimestamp = Date()`. In `FirstAudioGate.consume` first-flip, log `Date().timeIntervalSince(startTimestamp)`.

- [ ] **Step 2: Sample 20 invocations across mic types**

Built-in + USB + Bluetooth. Record min/p50/p95.

- [ ] **Step 3: Pin policy**

If p95 < 16ms → arming is invisible noise; skip directly to `.recording`. Implement by setting `recordingStartedAt` before flipping phase, and not entering `.armed` in `mapEngineState`.

If p95 ≥ 16ms (likely — Bluetooth alone can be 200ms+) → always render `.armed` until first audio.

Plan default: **render `.armed` always**, minimum 120ms (so even fast mics show entrance). Implement via:

```swift
        case .starting:
            phase = .armed
            // ...

        case .recording:
            // Hold .armed for at least 120ms so fast mics still show the
            // entrance. Then flip on first audio.
            if let started = recordingStartedAt,
               engine.firstAudioObserved,
               Date().timeIntervalSince(started) >= 0.12 {
                phase = .recording
            } else {
                phase = .armed
            }
```

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Transcription/Engine/RecorderUIManager.swift
git commit -m "fix(hud): hold .armed ≥120ms even on fast mic init (B.ArmingSkip resolution)"
```

### Task F3: B.KeyHandlingDictation — verify pass-through

- [ ] **Step 1: Test Return / Esc pass-through**

Set `RecorderType = notch`. Open Mail → start record → type `Return`. Expected: Return goes to Mail (line break / send), NOT to the panel.

Repeat in Slack (`Return` sends), VSCode (`Esc` exits insert mode).

Spec §2.4 says `.nonactivatingPanel` + `canBecomeKey = false` already guarantees this; the `KeyablePanel` superclass overrides `canBecomeKey` to `true` but `NotchRecorderPanel` then overrides back to `false`. Verify the override holds.

If any test fails → file ticket; consider not extending from `KeyablePanel` (it's only there for the Mini path).

- [ ] **Step 2: Document result in PR description; no code change expected**

### Task F4: B.FullScreenPolicy — Zoom screen-share visibility

- [ ] **Step 1: Test under Zoom screen-share + Keynote present mode**

Start Zoom call → share screen → trigger record. Expected: Bay visible to the remote viewer (collectionBehavior `.fullScreenAuxiliary` allows this).

Confirm with user this is the intended behavior. If not → opt out of `.fullScreenAuxiliary` during screen-share via a `CGGetActiveDisplayList` check. Spec says "Confirm screen-sharing visibility is intended (user-confirmable)" — likely intended (parity with menubar visibility).

- [ ] **Step 2: Document result in PR description; default policy = visible**

### Task F5: B.UndoCollision — hotkey within 1.5s

- [ ] **Step 1: Test**

Trigger record → stop → during `.done` 1.5s hold, fire hotkey again.

Expected per spec recommendation: new recording wins. Verify `beginDoneHold` Task is cancelled by the new `mapEngineState(.starting)` path. If not, add explicit cancel:

```swift
    private func mapEngineState(_ state: RecordingState, engine: VoiceInkEngine) {
        if state == .starting && phase == .done {
            doneHoldTask?.cancel()
            phase = .hidden
            lastPasteAppName = nil
        }
        // ... existing switch ...
    }
```

- [ ] **Step 2: Commit**

```bash
git commit -am "fix(hud): cancel .done hold when new recording starts (B.UndoCollision)"
```

### Task F6: B.HitTest — verify right stalactite hit-test

- [ ] **Step 1: Test**

During `.recording`, hover the right stalactite — expect cursor to remain default arrow (button hit-test active). During `.transcribing` (chip collapsed), hover the same region — expect cursor to pass through to whatever's underneath.

Verify via `BayRightStalactite.allowsHitTesting(true)` on the panel level — since the rest of the panel is `ignoresMouseEvents = true`, the SwiftUI subview only receives events because of the `.allowsHitTesting` opt-in, but `NSPanel.ignoresMouseEvents` may still drop AT THE PANEL LEVEL.

This is the spec-flagged spike. If the chip is not clickable:

Option A — toggle `panel.ignoresMouseEvents` dynamically based on phase: `panel.ignoresMouseEvents = (phase != .recording && phase != .done)`.

Option B — split the right stalactite into a sibling NSPanel that does receive events. Rejected by spec (single-panel topology).

Option A implementation: extend `NotchWindowManager` with a `setMouseEventsEnabled(_ on: Bool)` method; wire to `RecorderUIManager.$phase` sink.

- [ ] **Step 2: Implement Option A if needed**

```swift
// NotchWindowManager.swift — add:
    func setIgnoresMouseEvents(_ ignores: Bool) {
        panel?.ignoresMouseEvents = ignores
    }

// RecorderUIManager.swift — in setupPhaseObservers, after the existing $phase sink:
        $phase
            .receive(on: DispatchQueue.main)
            .sink { [weak self] new in
                let interactive = (new == .recording || new == .liveText || new == .done || new == .failed)
                self?.notchWindowManager?.setIgnoresMouseEvents(!interactive)
            }
            .store(in: &phaseObservers)
```

- [ ] **Step 3: Verify menu-bar click still passes through during `.hidden` / `.armed` / `.transcribing` / `.enhancing`**

- [ ] **Step 4: Commit**

```bash
git commit -am "fix(hud): per-phase panel.ignoresMouseEvents toggle for chip hit-test (B.HitTest)"
```

### Task F7: B.ModeList — confirm 9-char truncation

Already implemented in C1 step 2 (`formatPromptLabel`). SETTINGS pair must agree — coordinate.

- [ ] **Step 1: SendMessage to team-lead**

Confirm 9-char truncation with SETTINGS pair (lock value already in code).

### Task F8: Remove `SottoBayHUDEnabled` feature flag

- [ ] **Step 1: Delete the `@AppStorage` line + branch**

Edit `HaloRecorderView.swift` — collapse the branch:

```swift
    var body: some View {
        if isVisible() {
            if mode == .notch {
                BayHUDViewHost(stateProvider: stateProvider, recorder: recorder, aiService: aiService)
            } else {
                ConstellationContainer(stateProvider: stateProvider, recorder: recorder, aiService: aiService, mode: mode)
            }
        }
    }
```

- [ ] **Step 2: Commit**

```bash
git commit -am "chore(hud): remove SottoBayHUDEnabled feature flag (Bay shipping)"
```

### Task F9: Open PR #6 (Group F)

Branch: `redesign/sotto-hud-f-spikes`.

```bash
git push -u origin redesign/sotto-hud-f-spikes
gh pr create --base redesign/sotto --title "HUD F — spike resolutions + flag removal" --body "Group F. Resolves Appendix B spikes: MultiMonitor (240pt virtual-notch), ArmingSkip (always render ≥120ms), KeyHandlingDictation (verified pass-through), FullScreenPolicy (visible under screen-share by design), UndoCollision (new recording wins), HitTest (per-phase panel.ignoresMouseEvents toggle), ModeList (9-char uppercase confirmed). Flag SottoBayHUDEnabled removed. Spec: Appendix B."
```

---

## Self-Review

### Spec coverage

- [x] §1 Material — TacticalGlass (A5), brandAcid + state tokens (A1), HaloPhase glow re-key (A3), MotionTokens (A4).
- [x] §1.2 Geometry — SottoGeometry tokens in A5.
- [x] §1.3 Typography — MonoLabel in D1.
- [x] §1.4 Color tokens — A1.
- [x] §1.6 Glyph rule — `▸` in BayRightStalactite (B2 step 4), `›` is not used in HUD (sidebar surface — SETTINGS pair).
- [x] §1.X Accessibility — Group E in full + per-state RM gates in D2–D7.
- [x] §2 Structure — Group B (Bay layout, single panel, 3 subviews, single state observable, single withAnimation driver, hit-test opt-in, multi-monitor in F1).
- [x] §3 Idle — `orderOut(nil)` already in `NotchWindowManager.hide()` line 67; SwiftUI subtree unmounts via `phase == .hidden` opacity gate in BayHUDView (B2). Mini-cursor reveal is implicitly NOT implemented (correct per spec).
- [x] §4 State grammar — Group C (mapping), Group D (per-state visuals), C1 step 2 (engine→view bridge), C2 (first-audio), F2 (arming-skip), F5 (undo collision).
- [x] §4.2 Reduce Motion — Group E + per-state gates.
- [x] §4.2 Color-blind ✓/✗ — D6, D7.
- [x] §4.3 Motion atoms — A4.
- [x] §5.4 MENUBAR coordination — coordinator note in header; `RecorderUIManager.$phase` is the observable both pairs read.
- [x] Appendix B spikes (HUD-scope) — Group F.
- [x] Appendix C.HUD file map — every cited file/line is touched.

### Placeholder scan

No "TBD", "implement later", "add appropriate error handling", or "similar to Task N" placeholders. Each step contains either real code or a concrete shell command.

Open questions (top of plan) explicitly flagged as PRE-PR2 decisions to resolve with team-lead, not as in-step placeholders.

### Type consistency

- `RecorderUIState` props referenced consistently across BayCapsule / BayLeftStalactite / BayRightStalactite / ArmingContent / RecordingContent / etc. — `phase`, `audioLevel`, `recordingStartedAt`, `activePromptLabel`, `errorCode`, `lastPasteAppName`.
- `RecorderUIManager` public surface: `phase`, `recordingStartedAt`, `formattedActivePromptLabel`, `currentErrorCode`, `lastPasteAppName`, `dismissFailedPhase()`.
- `FirstAudioGate` API: `start()`, `consume(rawDb:)`, `reset()`, `observed`.
- `MotionTokens` keys: `pulse`, `sweep`, `breathe`, `arming`, `blink`, `dotJump`, `spin`, `stateEnter`, `stateExit`, `committedHold`, `committedFade`, `reducedFade`, `barsRangeMin`, `barsRangeMax`.
- `Palette` adds: `brandAcid`, `brandAcidMuted`, `brandAcidGlow`, `recRed`, `commitGreen`, `transCyan`, `enhViolet`.
- `SottoGeometry` keys: `cornerRadiusGlass`, `cornerRadiusNotch`, `cornerRadiusStalactite`, `cornerRadiusZero`, `hairline`, `spacingUnit`.

Names are stable across the plan. No `clearLayers()` vs `clearFullLayers()` drift.

---

## Total

**Tasks:** 31 across 6 groups.
**Steps:** ~140.
**PRs:** 6 onto `redesign/sotto` integration branch.
**Estimated effort:** Bay is the heaviest pair — 2.5–3 weeks for one coder-reviewer pair, given the spike work in Group F.
