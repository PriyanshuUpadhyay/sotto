# W2 — Cluster + State Grammar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-card Constellation morph with a satellite **chip cluster** (anchor + secondaries + actions) that distinguishes the six recorder states by **motion**, not color, and bridges cleanly to the upcoming W3 FailureRegistry — without breaking the user's RecorderStylePicker choice or the deferred onboarding (CinematicWalkthrough).

**Architecture:** The Constellation recorder (which is the real home of all three RecorderStylePicker selections — `notch`/`mini`/`constellation` already collapse to `ConstellationContainer` via `HaloRecorderView`) is refactored **in place** to the new vocabulary. A new `ConstellationCluster` orchestrator owns a `ClusterPhase` state machine + dwell logic + AppStorage failure-dwell read; a new `ChipPanel` view lays out the anchor + secondaries (single-row default; two-row only for `failed`); per-state `ClusterChip` view-builders consume `Palette.accent` + `.glassChip()` from W1. `ConstellationContainer.swift` collapses to a 12-line shim so panel hosts (`NotchWindowManager`, `MiniWindowManager`) keep their constructor.

The `Halo`/`Mini`/`Notch` styles selectable in `RecorderStylePicker` are **not separate recorder views** — they all route through `HaloRecorderView` → `ConstellationContainer` differing only in `HaloShape.Mode` (`.notch` vs `.floating`). So refactoring Constellation in-place satisfies all three picker entries automatically. The picker preview tile (`ConstellationPreview` in `RecorderStylePicker.swift`) gets re-painted to match the new chip silhouette.

**Tech Stack:** Swift 5.x, SwiftUI, Xcode 16.x, Swift Testing framework. Build via `make local` (~3 min cold). Animations attach via `.animation(_, value:)` patterns + `withAnimation` in `Task { … }` dwells; never `DispatchQueue.main.asyncAfter`.

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Motion), §2 (Structure), §4 (State grammar), §5 surface #1 (recorder cluster).

**CLAUDE.md cadence rules respected:**
- **Single build at merge time.** No `make local` per task; one full build at the final task.
- **No commits during execution.** Final step reports to lead; lead handles commits.
- **No `xcodebuild` per file.** SourceKit/Xcode handles per-file syntax during edits; integration build is the gate.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** All code samples follow this.

---

## File structure

### New files

- `VoiceInk/Views/Recorder/Constellation/ClusterPhase.swift` — `ClusterPhase` enum + `RecordingState` → `ClusterPhase` mapping helper. ~70 LOC.
- `VoiceInk/Views/Recorder/Constellation/ClusterMotion.swift` — sanctioned animations (`ringPulse`, `ringPulseSlow`, `chipShimmer`, `chipBreath`, `clusterFade`) + reduce-motion replacements + `RingPulseDot`, `ChipShimmer`, `ChipBreath` view modifiers. ~140 LOC.
- `VoiceInk/Views/Recorder/Constellation/ChipPanel.swift` — anchor + secondaries layout view. Accepts `ChipDescriptor` array, places anchor at center, fans secondaries left/right by `side`, supports a single trailing action row for `failed`. ~110 LOC.
- `VoiceInk/Views/Recorder/Constellation/ClusterChips.swift` — per-state `ChipDescriptor` factories (`recordingChips`, `transcribingChips`, `enhancingChips`, `doneChips`, `failedChips`) + chip-content view builders for the leading-dot + label rows. ~220 LOC.
- `VoiceInk/Views/Recorder/Constellation/ConstellationCluster.swift` — orchestrator. Derives `ClusterPhase` from `RecorderStateProvider`, holds done-dwell + failed-dwell `Task`s, reads `@AppStorage("failedDwellSeconds")`, exposes `injectFailure(reason:)` test/preview seam (W3 wires `FailureRegistry` to it). Hosts `ChipPanel`. ~300 LOC.

### Modified files

- `VoiceInk/Views/Recorder/Constellation/ConstellationContainer.swift` — collapses to a thin generic shim that delegates body to `ConstellationCluster`, preserving the existing constructor signature so `MiniWindowManager` / `NotchWindowManager` aren't touched. `ConstellationLayout` struct stays (fed into `ConstellationCluster` for anchor positioning).
- `VoiceInk/Views/Recorder/HaloRecorderView.swift` — body unchanged in shape (still calls `ConstellationContainer`). `StreamingCaretTranscript` retained as file-private since the new cluster doesn't render a streaming transcript chip; `ConstellationCard` (legacy onboarding consumer) still uses it.
- `VoiceInk/Views/Settings/RecorderStylePicker.swift` — `ConstellationPreview` re-painted to render the new chip cluster silhouette (anchor + 2 secondaries) instead of orb + chip + card.

### Retired files (delete)

- `VoiceInk/Views/Recorder/Constellation/WhisperLine.swift` — idle is invisible per spec §3 ("No floating chrome at idle"). Sole consumer was `ConstellationContainer`; removing it disconnects the proximity monitor.
- `VoiceInk/Views/Recorder/Constellation/CursorProximityMonitor.swift` — only fed `WhisperLine.proximity`; orphaned after WhisperLine retirement.
- `VoiceInk/Views/Recorder/PulseRibbon.swift` — already orphaned (no consumers, see Task 0 sweep). Drop-in W2 housekeeping.

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Views/Recorder/Constellation/ConstellationCard.swift` — kept verbatim. Used by `CinematicWalkthrough.swift` (onboarding, deferred per spec §5). Marked legacy in docstring (Task 11).
- `VoiceInk/Views/Recorder/Constellation/ConstellationChip.swift` — same. Used by `CinematicWalkthrough.swift`. Marked legacy.
- `VoiceInk/Views/Recorder/Constellation/ConstellationOrb.swift` — same.
- `VoiceInk/Views/Recorder/HaloMaterial.swift` — kept. `HaloPhase` enum survives because `ConstellationCard`/`Chip`/`Orb` (legacy onboarding) consume it. New cluster uses its own `ClusterPhase`. `HaloMaterial` itself remains the GlassCard primitive for W5 settings re-skin.
- `VoiceInk/Views/Recorder/HaloShape.swift` — `HaloShape.Mode` is the panel-position enum, used by `ConstellationLayout` and `RecorderStylePicker`. Untouched.
- `VoiceInk/Views/Recorder/MiniRecorderPanel.swift`, `NotchRecorderPanel.swift`, `MiniWindowManager.swift`, `NotchWindowManager.swift` — host adapters; constructor surface preserved by Task 6's `ConstellationContainer` shim.
- `VoiceInk/Views/Recorder/RecorderComponents.swift`, `AudioVisualizerView.swift`, `EnhancementPromptPopover.swift` — not in the cluster path. Untouched.
- `VoiceInk/Views/Recorder/RecorderStateProvider.swift` — existing `RecorderStateProvider` protocol + `failureReason` extension is sufficient for W2. W3 may extend; W2 does not.
- `VoiceInk/Views/Common/Animation+Halo.swift` — `Animation.haloExpand` (entry spring) preserved per spec §1. `haloCollapse` left in file but no longer consumed by the cluster (legacy onboarding still uses it). New `clusterFade` lives in `ClusterMotion.swift` to keep the new vocabulary self-contained.
- `VoiceInk/Views/Common/GlassChip.swift` — consumed via `.glassChip()` / `.glassPanel()` modifiers; not edited.
- `VoiceInk/Views/Common/Palette.swift` — consumed; not edited.
- `VoiceInk/Views/Onboarding/CinematicWalkthrough.swift` — onboarding deferred per spec §5; relies on legacy `ConstellationCard`/`Chip`/`Orb`. Untouched.

---

## Migration policy (resolves ambiguity for each design point)

The spec states intent at the surface level; this section pins the underlying mechanical decisions so the coder doesn't re-derive them mid-task.

1. **State machine — new enum, not extending `HaloPhase`.**
   - The new orchestrator adopts a fresh `ClusterPhase` with associated values (`.done(appName: String?, preview: String?)`, `.failed(reason: String?)`) so the chip factories don't have to reach back into the state provider for payload.
   - `HaloPhase` stays in `HaloMaterial.swift` for legacy onboarding consumers (`ConstellationCard`/`Chip`/`Orb`). No bridge between `HaloPhase` and `ClusterPhase` is needed because the cluster reads `RecorderStateProvider.recordingState` (a `RecordingState`) directly and maps to `ClusterPhase` itself.
   - `RecordingState.busy` collapses to `.idle` (matches v1 behavior in `ConstellationContainer.derivedPhase`).
   - `liveText` distinction is dropped — spec §4 recording chips don't include a streaming-transcript chip; recording = recording.

2. **Cluster geometry — single HStack default, manual two-row only for failed.**
   - Anchor sits centered. Secondaries are split into `side: .left | .right` at chip-descriptor level; left side renders reversed, right side renders in order, all in one HStack with `spacing: 8`.
   - "Two-row" path is only triggered by `failed` (4 chips: anchor + reason + retry + settings, where reason is prose and likely wraps). The plan implements this as `VStack { row1; row2 }` selected explicitly when `phase == .failed` — not by width measurement.
   - Position: `ChipPanel` is hosted in `ConstellationCluster`'s body; positioning at "centred horizontally, 50pt below menubar baseline" lives on `ConstellationLayout` (extended in Task 5).
   - SwiftUI layout: pure `HStack` + `VStack` — no custom `Layout` protocol implementation. Spec geometry is simple enough that nested stacks suffice; introducing `Layout` would add complexity for no win.

3. **Per-state chip authoring — descriptor + factory pattern.**
   - Chips are `ChipDescriptor` value types (not opaque views). Each carries `id`, `kind` (anchor / secondary / action), `side` (left / right), `motion` (none / ringPulse / ringPulseSlow / shimmer / breath), `dotColor` (Palette.accent vs `.cool`), and a closure `content -> AnyView` (or a lightweight enum `ChipContent` to avoid AnyView). `ChipPanel` renders the descriptors; `ClusterChips.swift` builds the per-state arrays.
   - Data sources:
     - REC + meter (recording anchor): `recorder.audioMeter.averagePower` (Float 0…1).
     - TIME (recording secondary): cluster owns a `recordingStartedAt: Date?` set on phase entry; chip uses `TimelineView(.periodic)` to format `mm:ss`.
     - PROMPT (recording / enhancing secondary): `stateProvider.enhancementService?.activePrompt?.title` + `.icon`.
     - MODEL (transcribing / enhancing secondary): `stateProvider.transcriptionModelLabel` (transcribing) / `aiService.currentModel` + `aiService.selectedProvider` (enhancing).
     - PASTED → \<app\> (done anchor): `event.appName` from the `.done` payload.
     - FAIL + reason (failed anchor + reason chip): from `stateProvider.failureReason` or the `.failed` `ClusterPhase` payload.

4. **Motion implementations — extension on `Animation` + 3 view modifiers.**
   - `ClusterMotion.swift` defines:
     - `Animation.ringPulse = .easeInOut(duration: 0.5).repeatForever(autoreverses: true)` (1.0s full cycle for the ring).
     - `Animation.ringPulseSlow = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)` (1.6s full cycle).
     - `Animation.chipShimmer = .easeInOut(duration: 0.7).repeatForever(autoreverses: true)` (1.4s full).
     - `Animation.chipBreath = .easeInOut(duration: 0.8).repeatForever(autoreverses: true)` (1.6s full).
     - `Animation.clusterFade = .linear(duration: 0.24)`.
   - View modifiers: `RingPulseDot` (renders the dot + animated outer ring; gated on `active: Bool`), `ChipShimmer` (chip α 0.62 ↔ 1.0), `ChipBreath` (outer accent halo cycle; spec calls this "breath halo on chip").
   - **Animations attach on the chip view, not on a layered overlay** — the dot ring is part of the anchor chip's leading content; the shimmer is `.opacity()` on the chip itself; the breath halo is a `.shadow()` cycle on the chip wrapper. This keeps animation lifetimes scoped to the chip's mount lifetime.

5. **Reduce-Motion fallback — `@Environment(\.accessibilityReduceMotion)` + branching on each motion modifier.**
   - Each of the three motion view modifiers reads the env value; when true, returns the static base value (no `repeatForever`, no scale, no ring). The cluster entry/exit transition collapses to `Animation.linear(duration: 0.18)` opacity per spec §1.
   - Existing `AccessibilityMotionMonitor.shared` is the live mirror of the system value; the cluster reads `@Environment(\.accessibilityReduceMotion)` (which SwiftUI keeps in sync from the same NSWorkspace API). Both coexist cleanly — the cluster uses the env value for branching; legacy onboarding code keeps using `AccessibilityMotionMonitor.shared`.

6. **Failure routing seam — `injectFailure(reason:)` on `ConstellationCluster`'s view-model state.**
   - W2 reads `stateProvider.failureReason` (existing accessor) and maps `RecordingState.failed(reason)` → `ClusterPhase.failed(reason: reason)`.
   - Cluster also exposes a `@State private var injectedFailure: String? = nil` and a method `func injectFailure(reason: String)` that sets it. The phase derivation prefers `injectedFailure` over the engine state for the dwell window.
   - W3 is responsible for wiring `FailureRegistry` to call `injectFailure(reason:)`. W2 only stubs the entry point.

7. **Accessibility — single combined element with explicit child order.**
   - Cluster body wraps `ChipPanel` in `.accessibilityElement(children: .combine)`. Each chip emits its own `.accessibilityLabel(...)` so VoiceOver reads them in declaration order: **anchor → reason (failure only) → secondaries → actions** (all four orderings are honored by ordering chips in the descriptor array correctly).
   - Decorative dots and motion are `.accessibilityHidden(true)` — VoiceOver speaks the chip label only, not the visual dot color.

8. **Dwell timings — explicit `Task` cancellation per phase entry.**
   - Recording: phase entry sets `recordingStartedAt = .now`. Phase exit clears it. No timed dwell.
   - Done: 1.2s dwell + 0.24s fade-out. On `lastPasteEvent` change, cancel any in-flight dwell `Task`, set `pendingDone = .done(appName, preview)`, sleep 1.2s, set fade flag (drives `clusterFade` opacity), sleep 0.24s, drop back to `.idle`.
   - Failed: read `@AppStorage("failedDwellSeconds") var failedDwellSeconds: Double = 6.0`. On phase entry to `.failed`, cancel any in-flight task, sleep `failedDwellSeconds`, drop back to `.idle`. (Settings UI lives in W3.)

9. **Existing assets to preserve / fold.**
   - `Animation.haloExpand` — kept; cluster mount uses it for entry: `.transition(.opacity.combined(with: .scale(scale: 0.96)).animation(.haloExpand))`.
   - `Animation.clusterFade` — new, used for cluster exit and per-chip cross-fade between phase changes.
   - `PulseRibbon.swift` — orphaned; retired.
   - `AudioVisualizerView` — not in cluster path; left as-is for `RecorderComponents.swift`.
   - `EnhancementPromptPopover` — not in cluster path; the cluster's PROMPT chip is read-only (a label + icon), no popover. Onboarding flow continues to use the legacy popover via `RecorderComponents`.

10. **Token consumption — strict.**
    - Anchor chip leading dot: `Palette.accent` (recording / enhancing / failed); `Palette.onyxFg.opacity(0.85)` ("white-cool", spec §4) for transcribing.
    - Anchor chip ring (under ringPulse): `Palette.accentGlow` stroke.
    - Secondary chip text: `Palette.onyxFg`; chip key prefix (e.g. `"MODEL"`): `Palette.onyxMute`.
    - Reason chip prose (failed): `Palette.onyxFg`.
    - Action chip (RETRY, OPEN SETTINGS): `Palette.onyxFg` text on `.glassChip()` background.
    - Background hairline (drawn by `.glassChip()`): `Palette.hairline` (already inside the modifier; nothing to wire here).

11. **W3 prep — what the cluster does NOT do.**
    - Does not implement `FailureRegistry`. Does not render the menubar failure-dot variant. Does not provide a Settings UI for `failedDwellSeconds` (only reads the AppStorage value with a 6.0 default).
    - The `injectFailure(reason:)` seam is the only explicit W3 hook.

---

## Tasks

### Task 0: Sweep retired symbols + verify legacy keep-list

**Files:** none (read-only).

- [ ] **Step 0.1: Confirm WhisperLine / CursorProximityMonitor / PulseRibbon have no off-cluster consumers**

```bash
grep -rn "WhisperLine\|CursorProximityMonitor\|PulseRibbon" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift"
```

Expected: matches only inside the three files themselves and inside `ConstellationContainer.swift`. If any other file references them, stop and reconcile with the lead before deleting.

- [ ] **Step 0.2: Confirm ConstellationCard / Chip / Orb still have legacy consumers**

```bash
grep -rn "ConstellationCard\|ConstellationChip\|ConstellationOrb" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift" | grep -v "Constellation/Constellation"
```

Expected: at minimum `Views/Onboarding/CinematicWalkthrough.swift` appears. That's why these three files stay.

- [ ] **Step 0.3: Note the `RecorderStateProvider` API surface**

The cluster will read these properties off `S: RecorderStateProvider & ObservableObject`:
- `recordingState: RecordingState`
- `lastPasteEvent: PasteEvent?`
- `failureReason: String?` (extension)
- `transcriptionModelLabel: String?`
- `enhancementService: AIEnhancementService?`

Plus `recorder.audioMeter.averagePower` and `aiService.selectedProvider` / `aiService.currentModel`. No new protocol requirements are added in W2.

---

### Task 1: Add `ClusterPhase.swift`

**Files:**
- Create: `VoiceInk/Views/Recorder/Constellation/ClusterPhase.swift`

- [ ] **Step 1.1: Write the file**

```swift
import Foundation

// MARK: - ClusterPhase
//
// Cluster-side phase. Distinct from `HaloPhase` (legacy onboarding) so chip
// factories carry payloads inline. Source of truth for cluster grammar:
// docs/superpowers/specs/2026-04-28-aesthetic-redesign.md §4.

enum ClusterPhase: Equatable {
    case idle
    case recording
    case transcribing
    case enhancing
    case done(appName: String?, preview: String?)
    case failed(reason: String?)
}

extension ClusterPhase {
    /// Coarse identity — used for `.id` keys on per-chip transitions so a
    /// failed→failed transition with a different reason does not re-mount
    /// the whole row.
    var identity: String {
        switch self {
        case .idle:         return "idle"
        case .recording:    return "recording"
        case .transcribing: return "transcribing"
        case .enhancing:    return "enhancing"
        case .done:         return "done"
        case .failed:       return "failed"
        }
    }

    var isVisible: Bool {
        switch self {
        case .idle: return false
        default:    return true
        }
    }
}

// MARK: - RecordingState bridge
//
// Engine-side `RecordingState` → cluster `ClusterPhase`. `.busy` collapses to
// `.idle` (matches v1 ConstellationContainer.derivedPhase). `.failed(reason)`
// preserves the reason. `.done` is NOT derived here — done synthesis lives
// on the orchestrator (PasteEvent freshness window).

extension ClusterPhase {
    static func fromEngine(_ state: RecordingState) -> ClusterPhase {
        switch state {
        case .idle, .busy:
            return .idle
        case .starting, .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .enhancing:
            return .enhancing
        case .failed(let reason):
            return .failed(reason: reason)
        }
    }
}
```

- [ ] **Step 1.2: Add file to Xcode project target**

Same path as W1 Task 2.2 — drag into `Views/Recorder/Constellation` group in Xcode and check `VoiceInk` target membership; or use the `xcodeproj` ruby snippet.

```bash
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("VoiceInk.xcodeproj")
target = project.targets.find { |t| t.name == "VoiceInk" }
group = project.main_group
["VoiceInk", "Views", "Recorder", "Constellation"].each do |seg|
  group = group.find_subpath(seg, false) || (raise "missing group #{seg}")
end
file_ref = group.new_reference("ClusterPhase.swift")
target.add_file_references([file_ref])
project.save
'
```

---

### Task 2: Add `ClusterMotion.swift` (animations + view modifiers)

**Files:**
- Create: `VoiceInk/Views/Recorder/Constellation/ClusterMotion.swift`

- [ ] **Step 2.1: Write the file**

```swift
import SwiftUI

// MARK: - Sanctioned animations
//
// Spec §1 + §4. Reduce-Motion: callers branch on
// `@Environment(\.accessibilityReduceMotion)` and substitute `clusterFade`
// (0.18s opacity) — these animations are NEVER applied under Reduce-Motion.

extension Animation {
    /// 1.0s ring pulse — recording / failed dot. Half-period 0.5s.
    static let ringPulse = Animation
        .easeInOut(duration: 0.5)
        .repeatForever(autoreverses: true)

    /// 1.6s ring pulse — enhancing dot. Half-period 0.8s.
    static let ringPulseSlow = Animation
        .easeInOut(duration: 0.8)
        .repeatForever(autoreverses: true)

    /// 1.4s chip α 0.62 ↔ 1.0 shimmer — transcribing chip. Half-period 0.7s.
    static let chipShimmer = Animation
        .easeInOut(duration: 0.7)
        .repeatForever(autoreverses: true)

    /// 1.6s chip breath halo — enhancing chip. Half-period 0.8s.
    static let chipBreath = Animation
        .easeInOut(duration: 0.8)
        .repeatForever(autoreverses: true)

    /// 0.24s linear cluster collapse + per-chip cross-fade. Spec §1.
    static let clusterFade = Animation.linear(duration: 0.24)

    /// 0.18s linear opacity — Reduce-Motion fallback for both directions
    /// (entry, exit, cross-fades). Spec §1.
    static let clusterFadeReduced = Animation.linear(duration: 0.18)
}

// MARK: - RingPulseDot
//
// Leading dot + animated outer ring. The ring scales 1.0 → 1.6 and fades
// 0.55 → 0 across the half-period; the dot itself stays static at full alpha.
// Two cadences: `.fast` (recording/failed, 0.5s half-period) and `.slow`
// (enhancing, 0.8s half-period).

enum RingPulseRate {
    case fast    // recording / failed — 1.0s full cycle
    case slow    // enhancing — 1.6s full cycle
    case none    // transcribing dot has no ring; static disc
}

struct RingPulseDot: View {
    let color: Color
    var rate: RingPulseRate = .fast
    var diameter: CGFloat = 6
    var ringDiameter: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Palette.accentGlow, lineWidth: 1)
                .frame(width: ringDiameter, height: ringDiameter)
                .scaleEffect(pulse ? 1.0 : 0.6)
                .opacity(ringOpacity)
                .opacity(rate == .none ? 0 : 1)

            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .onAppear { applyAnimation() }
        .onChange(of: rate) { _, _ in applyAnimation() }
        .onChange(of: reduceMotion) { _, _ in applyAnimation() }
        .accessibilityHidden(true)
    }

    private var ringOpacity: Double {
        guard rate != .none else { return 0 }
        return pulse ? 0.0 : 0.55
    }

    private func applyAnimation() {
        guard !reduceMotion else {
            pulse = false
            return
        }
        let anim: Animation? = {
            switch rate {
            case .fast: return .ringPulse
            case .slow: return .ringPulseSlow
            case .none: return nil
            }
        }()
        withAnimation(anim) { pulse.toggle() }
    }
}

// MARK: - ChipShimmer
//
// Transcribing chip α cycle 0.62 ↔ 1.0 over 1.4s. Reduce-Motion → static at 1.0.

struct ChipShimmer: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim: Bool = false

    func body(content: Content) -> some View {
        content
            .opacity(active && dim ? 0.62 : 1.0)
            .onAppear { applyAnimation() }
            .onChange(of: active) { _, _ in applyAnimation() }
            .onChange(of: reduceMotion) { _, _ in applyAnimation() }
    }

    private func applyAnimation() {
        if reduceMotion || !active {
            dim = false
            return
        }
        withAnimation(.chipShimmer) { dim.toggle() }
    }
}

// MARK: - ChipBreath
//
// Enhancing chip outer halo cycle. Renders an extra accent shadow whose
// radius+alpha cycles. Reduce-Motion → static mid-amplitude (no animation).

struct ChipBreath: ViewModifier {
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var raised: Bool = false

    func body(content: Content) -> some View {
        content
            .shadow(
                color: Palette.accent.opacity(haloAlpha),
                radius: haloRadius,
                x: 0,
                y: 0
            )
            .onAppear { applyAnimation() }
            .onChange(of: active) { _, _ in applyAnimation() }
            .onChange(of: reduceMotion) { _, _ in applyAnimation() }
    }

    private var haloAlpha: Double {
        guard active else { return 0 }
        if reduceMotion { return 0.32 }
        return raised ? 0.45 : 0.20
    }

    private var haloRadius: CGFloat {
        guard active else { return 0 }
        if reduceMotion { return 10 }
        return raised ? 14 : 8
    }

    private func applyAnimation() {
        if reduceMotion || !active {
            raised = false
            return
        }
        withAnimation(.chipBreath) { raised.toggle() }
    }
}

extension View {
    func chipShimmer(active: Bool) -> some View {
        modifier(ChipShimmer(active: active))
    }

    func chipBreath(active: Bool) -> some View {
        modifier(ChipBreath(active: active))
    }
}
```

- [ ] **Step 2.2: Add to Xcode project target**

Same `xcodeproj` snippet as Task 1.2, with `"ClusterMotion.swift"`.

---

### Task 3: Add `ChipPanel.swift`

**Files:**
- Create: `VoiceInk/Views/Recorder/Constellation/ChipPanel.swift`

- [ ] **Step 3.1: Write the file**

```swift
import SwiftUI

// MARK: - ChipDescriptor
//
// Value-type spec for one chip slot in the cluster. Built per-state by the
// factories in `ClusterChips.swift`; rendered by `ChipPanel`. Carries side +
// motion + content so layout, motion, and content stay decoupled.

struct ChipDescriptor: Identifiable {
    enum Kind { case anchor, secondary, action }
    enum Side { case left, right }
    enum Motion { case none, ringPulseFast, ringPulseSlow, shimmer, breath }
    enum Row { case primary, action }

    let id: String
    let kind: Kind
    let side: Side
    let motion: Motion
    let row: Row
    let view: AnyView

    /// VoiceOver label. Empty string → chip is decorative-hidden.
    let axLabel: String

    init<V: View>(
        id: String,
        kind: Kind = .secondary,
        side: Side = .right,
        motion: Motion = .none,
        row: Row = .primary,
        axLabel: String,
        @ViewBuilder view: () -> V
    ) {
        self.id = id
        self.kind = kind
        self.side = side
        self.motion = motion
        self.row = row
        self.axLabel = axLabel
        self.view = AnyView(view())
    }
}

// MARK: - ChipPanel
//
// Lays out a list of `ChipDescriptor`. Single-row default: anchor in middle,
// secondaries fan out by `side`. Two-row mode (`hasActionRow == true`) adds
// a second row below for action chips — only used by the failed state.
//
// Spec §2 geometry: 8pt spacing between chips. Anchor chip is mounted whether
// or not it carries motion — motion attaches inside the chip view itself.

struct ChipPanel: View {
    let phase: ClusterPhase
    let chips: [ChipDescriptor]

    var body: some View {
        let primary = chips.filter { $0.row == .primary }
        let actions = chips.filter { $0.row == .action }
        let hasActionRow = !actions.isEmpty

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(primary.filter { $0.side == .left }.reversed()) { chip in
                    chipView(chip)
                }
                ForEach(primary.filter { $0.kind == .anchor }) { chip in
                    chipView(chip)
                }
                ForEach(primary.filter { $0.side == .right && $0.kind != .anchor }) { chip in
                    chipView(chip)
                }
            }

            if hasActionRow {
                HStack(spacing: 8) {
                    ForEach(actions) { chip in
                        chipView(chip)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func chipView(_ chip: ChipDescriptor) -> some View {
        let labeled = chip.view
            .accessibilityLabel(chip.axLabel)
            .accessibilityHidden(chip.axLabel.isEmpty)

        labeled
            .id(chip.id)
            .transition(
                .asymmetric(
                    insertion: .opacity.animation(.haloExpand),
                    removal: .opacity.animation(.clusterFade)
                )
            )
    }
}
```

- [ ] **Step 3.2: Add to Xcode project target**

Same pattern as Task 1.2.

---

### Task 4: Add `ClusterChips.swift` (per-state chip factories)

**Files:**
- Create: `VoiceInk/Views/Recorder/Constellation/ClusterChips.swift`

This file is the longest single addition (~220 LOC) — defines the visual content of every chip per state.

- [ ] **Step 4.1: Write the file**

```swift
import SwiftUI

// MARK: - ClusterChips
//
// Per-state factories that produce `[ChipDescriptor]` for the cluster.
// Each factory returns the chips in VoiceOver-priority order:
// anchor → reason (failure only) → secondaries → actions.
//
// Spec §4 chip slate (verbatim):
//   recording   : REC + meter, TIME, PROMPT
//   transcribing: TRANSCRIBING, MODEL
//   enhancing   : ENHANCING, PROMPT, MODEL
//   done        : ✓ PASTED → <app>
//   failed      : FAIL, reason, RETRY, OPEN SETTINGS

enum ClusterChips {
    static func chips(
        phase: ClusterPhase,
        recordingStartedAt: Date?,
        audioLevel: Float,
        promptIcon: String?,
        promptName: String?,
        transcriptionModelLabel: String?,
        enhancementProviderLabel: String?,
        onRetry: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> [ChipDescriptor] {
        switch phase {
        case .idle:
            return []
        case .recording:
            return recordingChips(
                startedAt: recordingStartedAt,
                audioLevel: audioLevel,
                promptIcon: promptIcon,
                promptName: promptName
            )
        case .transcribing:
            return transcribingChips(modelLabel: transcriptionModelLabel)
        case .enhancing:
            return enhancingChips(
                promptIcon: promptIcon,
                promptName: promptName,
                providerLabel: enhancementProviderLabel
            )
        case .done(let appName, _):
            return doneChips(appName: appName)
        case .failed(let reason):
            return failedChips(
                reason: reason,
                onRetry: onRetry,
                onOpenSettings: onOpenSettings
            )
        }
    }

    // MARK: - Recording

    private static func recordingChips(
        startedAt: Date?,
        audioLevel: Float,
        promptIcon: String?,
        promptName: String?
    ) -> [ChipDescriptor] {
        var chips: [ChipDescriptor] = [
            ChipDescriptor(
                id: "rec-anchor",
                kind: .anchor,
                motion: .ringPulseFast,
                axLabel: "Recording, level \(percent(audioLevel))"
            ) {
                anchorChipBody(
                    label: "REC",
                    dotColor: Palette.accent,
                    rate: .fast,
                    trailing: { AnyView(MeterBars(level: audioLevel)) }
                )
            }
        ]

        if let startedAt {
            chips.append(
                ChipDescriptor(
                    id: "rec-time",
                    side: .left,
                    axLabel: "Elapsed time"
                ) {
                    TimeChip(startedAt: startedAt)
                }
            )
        }

        if let promptName, !promptName.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "rec-prompt",
                    side: .right,
                    axLabel: "Prompt \(promptName)"
                ) {
                    KeyValueChip(
                        key: "PROMPT",
                        value: promptName,
                        leadingSymbol: promptIcon
                    )
                }
            )
        }

        return chips
    }

    // MARK: - Transcribing

    private static func transcribingChips(modelLabel: String?) -> [ChipDescriptor] {
        var chips: [ChipDescriptor] = [
            ChipDescriptor(
                id: "trans-anchor",
                kind: .anchor,
                motion: .shimmer,
                axLabel: "Transcribing"
            ) {
                anchorChipBody(
                    label: "TRANSCRIBING",
                    dotColor: Palette.onyxFg.opacity(0.85),
                    rate: .none
                )
                .chipShimmer(active: true)
            }
        ]

        if let modelLabel, !modelLabel.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "trans-model",
                    side: .right,
                    axLabel: "Model \(modelLabel)"
                ) {
                    KeyValueChip(key: "MODEL", value: modelLabel)
                }
            )
        }
        return chips
    }

    // MARK: - Enhancing

    private static func enhancingChips(
        promptIcon: String?,
        promptName: String?,
        providerLabel: String?
    ) -> [ChipDescriptor] {
        var chips: [ChipDescriptor] = [
            ChipDescriptor(
                id: "enh-anchor",
                kind: .anchor,
                motion: .breath,
                axLabel: "Enhancing"
            ) {
                anchorChipBody(
                    label: "ENHANCING",
                    dotColor: Palette.accent,
                    rate: .slow
                )
                .chipBreath(active: true)
            }
        ]

        if let promptName, !promptName.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "enh-prompt",
                    side: .left,
                    axLabel: "Prompt \(promptName)"
                ) {
                    KeyValueChip(
                        key: "PROMPT",
                        value: promptName,
                        leadingSymbol: promptIcon
                    )
                }
            )
        }
        if let providerLabel, !providerLabel.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "enh-model",
                    side: .right,
                    axLabel: "Model \(providerLabel)"
                ) {
                    KeyValueChip(key: "MODEL", value: providerLabel)
                }
            )
        }
        return chips
    }

    // MARK: - Done

    private static func doneChips(appName: String?) -> [ChipDescriptor] {
        let target = appName ?? "clipboard"
        return [
            ChipDescriptor(
                id: "done-anchor",
                kind: .anchor,
                motion: .none,
                axLabel: "Pasted to \(target)"
            ) {
                DoneAnchorChip(appName: target)
            }
        ]
    }

    // MARK: - Failed

    private static func failedChips(
        reason: String?,
        onRetry: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> [ChipDescriptor] {
        var chips: [ChipDescriptor] = [
            ChipDescriptor(
                id: "fail-anchor",
                kind: .anchor,
                motion: .ringPulseFast,
                axLabel: "Failed"
            ) {
                anchorChipBody(
                    label: "FAIL",
                    dotColor: Palette.accent,
                    rate: .fast
                )
            }
        ]

        if let reason, !reason.isEmpty {
            chips.append(
                ChipDescriptor(
                    id: "fail-reason",
                    side: .right,
                    axLabel: reason
                ) {
                    ReasonChip(text: reason)
                }
            )
        }

        chips.append(
            ChipDescriptor(
                id: "fail-retry",
                kind: .action,
                row: .action,
                axLabel: "Retry"
            ) {
                ActionChip(label: "RETRY", action: onRetry)
            }
        )
        chips.append(
            ChipDescriptor(
                id: "fail-settings",
                kind: .action,
                row: .action,
                axLabel: "Open Settings"
            ) {
                ActionChip(label: "OPEN SETTINGS", action: onOpenSettings)
            }
        )
        return chips
    }

    // MARK: - Helpers

    private static func percent(_ level: Float) -> String {
        let v = max(0, min(1, level))
        return "\(Int(v * 100)) percent"
    }

    @ViewBuilder
    private static func anchorChipBody<Trailing: View>(
        label: String,
        dotColor: Color,
        rate: RingPulseRate,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) -> some View {
        HStack(spacing: 6) {
            RingPulseDot(color: dotColor, rate: rate)
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
            trailing()
        }
        .glassChip()
    }
}

// MARK: - Concrete chip subviews

private struct KeyValueChip: View {
    let key: String
    let value: String
    var leadingSymbol: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let leadingSymbol, !leadingSymbol.isEmpty {
                Image(systemName: leadingSymbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Palette.onyxMute)
            }
            Text(key)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 9.5)
                .foregroundStyle(Palette.onyxMute)
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .glassChip()
    }
}

private struct TimeChip: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1.0)) { ctx in
            let elapsed = max(0, ctx.date.timeIntervalSince(startedAt))
            Text(format(elapsed))
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
                .glassChip()
        }
    }

    private func format(_ s: TimeInterval) -> String {
        let total = Int(s)
        let m = total / 60
        let r = total % 60
        return String(format: "%02d:%02d", m, r)
    }
}

private struct MeterBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { i in
                let threshold = Float(i + 1) / 4.0
                Capsule()
                    .fill(level >= threshold ? Palette.accent : Palette.accent.opacity(0.30))
                    .frame(width: 1.5, height: CGFloat(3 + i))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct DoneAnchorChip: View {
    let appName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.accent)
            Text("PASTED")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
            Text("→")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.onyxMute)
            Text(appName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.onyxFg)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .glassChip()
    }
}

private struct ReasonChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(Palette.onyxFg)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 280, alignment: .leading)
            .glassChip()
    }
}

private struct ActionChip: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
        }
        .buttonStyle(.plain)
        .glassChip()
    }
}
```

- [ ] **Step 4.2: Add to Xcode project target**

Same pattern as Task 1.2.

---

### Task 5: Add `ConstellationCluster.swift` (orchestrator)

**Files:**
- Create: `VoiceInk/Views/Recorder/Constellation/ConstellationCluster.swift`

- [ ] **Step 5.1: Write the file**

```swift
import SwiftUI
import AppKit

// MARK: - ConstellationCluster
//
// Orchestrator for the W2 chip cluster (spec §2 + §4). Owns:
//   • RecordingState → ClusterPhase derivation
//   • Done-dwell synthesis (1.2s + 0.24s fade) keyed off PasteEvent
//   • Failed-dwell timer (read AppStorage("failedDwellSeconds"), default 6s)
//   • W3 seam: injectFailure(reason:) — FailureRegistry will call this
//   • ChipPanel composition + accessibility wrapping
//
// Position: anchor centred horizontally below the notch (or virtual notch on
// non-notch displays), 50pt below the menu-bar baseline. Geometry computed
// via ConstellationLayout (extended Task 6) — host panel is full-screen-width
// × 120pt, click-through except on action chips.

struct ConstellationCluster<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    let mode: HaloShape.Mode

    // Settings override (W3 wires Settings UI; W2 only reads).
    @AppStorage("failedDwellSeconds") private var failedDwellSeconds: Double = 6.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Phase state

    @State private var injectedFailure: String? = nil
    @State private var donePayload: (appName: String?, preview: String?)? = nil
    @State private var doneFading: Bool = false
    @State private var doneTask: Task<Void, Never>? = nil
    @State private var failedTask: Task<Void, Never>? = nil
    @State private var recordingStartedAt: Date? = nil

    // MARK: - Body

    var body: some View {
        let layout = ConstellationLayout.current(mode: mode)
        let phase = derivedPhase

        ZStack(alignment: .topLeading) {
            if phase.isVisible {
                ChipPanel(phase: phase, chips: chipsForCurrentPhase(phase))
                    .opacity(doneFading ? 0 : 1)
                    .animation(reduceMotion ? .clusterFadeReduced : .clusterFade,
                               value: doneFading)
                    .position(x: layout.anchorX, y: layout.anchorY)
                    .transition(
                        .opacity.animation(reduceMotion ? .clusterFadeReduced : .haloExpand)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? .clusterFadeReduced : .haloExpand, value: phase.identity)
        .onChange(of: stateProvider.recordingState) { _, newState in
            handleRecordingStateChange(newState)
        }
        .onChange(of: stateProvider.lastPasteEvent) { _, event in
            handlePasteEvent(event)
        }
        .onAppear { handleRecordingStateChange(stateProvider.recordingState) }
    }

    // MARK: - Phase derivation
    //
    // Resolution order (highest priority first):
    //   1. doneFading window (synthesized done-fade)
    //   2. donePayload window (1.2s done dwell)
    //   3. injectedFailure (W3 FailureRegistry seam)
    //   4. engine state via ClusterPhase.fromEngine

    private var derivedPhase: ClusterPhase {
        if doneFading, let payload = donePayload {
            return .done(appName: payload.appName, preview: payload.preview)
        }
        if let payload = donePayload {
            return .done(appName: payload.appName, preview: payload.preview)
        }
        if let reason = injectedFailure {
            return .failed(reason: reason)
        }
        return ClusterPhase.fromEngine(stateProvider.recordingState)
    }

    // MARK: - Chip composition

    private func chipsForCurrentPhase(_ phase: ClusterPhase) -> [ChipDescriptor] {
        ClusterChips.chips(
            phase: phase,
            recordingStartedAt: recordingStartedAt,
            audioLevel: Float(recorder.audioMeter.averagePower),
            promptIcon: stateProvider.enhancementService?.activePrompt?.icon,
            promptName: stateProvider.enhancementService?.activePrompt?.title,
            transcriptionModelLabel: stateProvider.transcriptionModelLabel,
            enhancementProviderLabel: enhancementProviderLabel,
            onRetry: handleRetry,
            onOpenSettings: handleOpenSettings
        )
    }

    private var enhancementProviderLabel: String? {
        let provider = aiService.selectedProvider.rawValue.uppercased()
        let model = aiService.currentModel
            .replacingOccurrences(of: "models/", with: "")
            .uppercased()
        guard !model.isEmpty else { return provider }
        return "\(provider) · \(model)"
    }

    // MARK: - Engine state handling

    private func handleRecordingStateChange(_ state: RecordingState) {
        // Recording start tracker — drives TIME chip elapsed counter.
        switch state {
        case .starting, .recording:
            if recordingStartedAt == nil {
                recordingStartedAt = .now
            }
        default:
            recordingStartedAt = nil
        }

        // Failed-dwell timer.
        if case .failed = state {
            scheduleFailedDwell()
        }
    }

    private func handlePasteEvent(_ event: PasteEvent?) {
        guard let event else { return }
        doneTask?.cancel()
        doneFading = false
        donePayload = (appName: event.appName, preview: event.preview)

        doneTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? .clusterFadeReduced : .clusterFade) {
                doneFading = true
            }
            try? await Task.sleep(for: .milliseconds(240))
            guard !Task.isCancelled else { return }
            donePayload = nil
            doneFading = false
        }
    }

    private func scheduleFailedDwell() {
        failedTask?.cancel()
        let dwell = max(0.5, failedDwellSeconds)
        failedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(dwell * 1000)))
            guard !Task.isCancelled else { return }
            injectedFailure = nil
            // Engine .failed already collapses to .idle on its own
            // (engine-side dwell). Cluster only manages the optional
            // injected failure.
        }
    }

    // MARK: - W3 seam

    /// W3 wires `FailureRegistry.publish(reason:)` to call this.
    /// W2 ships it unwired so the cluster is testable in isolation.
    func injectFailure(reason: String) {
        injectedFailure = reason
        scheduleFailedDwell()
    }

    // MARK: - Action chip handlers

    private func handleRetry() {
        // W2 stub. W3's FailureRegistry will define retry semantics.
        // For now, clear the injected failure so the cluster retracts —
        // the engine state machine handles real recovery via hotkey.
        injectedFailure = nil
    }

    private func handleOpenSettings() {
        // Route to Settings via existing notification surface.
        NotificationCenter.default.post(
            name: NSNotification.Name("voiceInkOpenSettings"),
            object: nil
        )
    }
}
```

- [ ] **Step 5.2: Add to Xcode project target**

Same pattern as Task 1.2.

---

### Task 6: Refactor `ConstellationContainer.swift` to a thin shim

**Files:**
- Modify: `VoiceInk/Views/Recorder/Constellation/ConstellationContainer.swift`

- [ ] **Step 6.1: Replace file contents**

The body of `ConstellationContainer` becomes a single call to `ConstellationCluster`. `ConstellationLayout` is preserved with anchor-position fields added (the layout struct is shared with `ConstellationCluster`).

Open `VoiceInk/Views/Recorder/Constellation/ConstellationContainer.swift` and replace the entire file with:

```swift
import SwiftUI
import AppKit

// MARK: - ConstellationContainer
//
// Thin shim — preserves the constructor surface used by NotchWindowManager /
// MiniWindowManager / HaloRecorderView so panel hosts aren't touched. All
// visual + state logic lives in `ConstellationCluster` (W2).

struct ConstellationContainer<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    let mode: HaloShape.Mode

    var body: some View {
        ConstellationCluster(
            stateProvider: stateProvider,
            recorder: recorder,
            aiService: aiService,
            mode: mode
        )
    }
}

// MARK: - ConstellationLayout
//
// Anchor + layout geometry. Shared between the cluster (anchor positioning)
// and any future host adapters. Spec §2: anchor centred horizontally below
// the notch (or virtual notch on non-notch displays), 50pt below the menu-bar
// baseline.

struct ConstellationLayout {
    let isNotched: Bool
    let notchHeight: CGFloat
    let notchWidth: CGFloat
    let screenWidth: CGFloat

    /// 50pt below menu-bar baseline (spec §2).
    static let anchorBelowMenubar: CGFloat = 50

    static func current(mode: HaloShape.Mode) -> ConstellationLayout {
        guard let screen = NSScreen.main else {
            return ConstellationLayout(
                isNotched: false,
                notchHeight: 24,
                notchWidth: 0,
                screenWidth: 1440
            )
        }
        let safeTop = screen.safeAreaInsets.top
        let isNotched = safeTop > 0
        let notchHeight: CGFloat = isNotched
            ? safeTop
            : NSStatusBar.system.thickness
        let notchWidth: CGFloat = {
            if let l = screen.auxiliaryTopLeftArea?.width,
               let r = screen.auxiliaryTopRightArea?.width {
                return screen.frame.width - l - r
            }
            return 180
        }()
        return ConstellationLayout(
            isNotched: isNotched && mode == .notch,
            notchHeight: notchHeight,
            notchWidth: notchWidth,
            screenWidth: screen.frame.width
        )
    }

    var anchorX: CGFloat { screenWidth / 2 }
    var anchorY: CGFloat { notchHeight + Self.anchorBelowMenubar }
}
```

- [ ] **Step 6.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Recorder/Constellation/ConstellationContainer.swift | head -60
```

Expected: nearly the entire prior file removed (WhisperLine reference, ConstellationOrb / Chip / Card mounts, transitions, breathePulse, derivedPhase, doneActive, etc.). Only the shim + simplified layout struct remain.

---

### Task 7: Update `HaloRecorderView.swift` (verify still compiles)

**Files:**
- Modify (verification only — body should already work): `VoiceInk/Views/Recorder/HaloRecorderView.swift`

- [ ] **Step 7.1: Verify HaloRecorderView body**

Open the file. Confirm the body is:

```swift
var body: some View {
    if isVisible() {
        ConstellationContainer(
            stateProvider: stateProvider,
            recorder: recorder,
            aiService: aiService,
            mode: mode
        )
    }
}
```

The signature is unchanged from pre-W2 (4 inputs: stateProvider, recorder, aiService, mode). `ConstellationContainer` keeps the same shape (Task 6 shim). No edit needed.

- [ ] **Step 7.2: Verify `StreamingCaretTranscript` still has consumers**

```bash
grep -rn "StreamingCaretTranscript" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift"
```

Expected: `ConstellationCard.swift` (legacy onboarding) still uses it. Leave `StreamingCaretTranscript` in `HaloRecorderView.swift` as-is.

---

### Task 8: Retire WhisperLine, CursorProximityMonitor, PulseRibbon

**Files:**
- Delete: `VoiceInk/Views/Recorder/Constellation/WhisperLine.swift`
- Delete: `VoiceInk/Views/Recorder/Constellation/CursorProximityMonitor.swift`
- Delete: `VoiceInk/Views/Recorder/PulseRibbon.swift`

- [ ] **Step 8.1: Verify no remaining references**

```bash
grep -rn "WhisperLine\|CursorProximityMonitor\|PulseRibbon" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift" | grep -v "WhisperLine.swift\|CursorProximityMonitor.swift\|PulseRibbon.swift"
```

Expected: empty (Task 6 already removed the consumers from `ConstellationContainer.swift`). If anything remains, find and remove.

- [ ] **Step 8.2: Delete the files via `git rm`**

```bash
git rm VoiceInk/Views/Recorder/Constellation/WhisperLine.swift
git rm VoiceInk/Views/Recorder/Constellation/CursorProximityMonitor.swift
git rm VoiceInk/Views/Recorder/PulseRibbon.swift
```

- [ ] **Step 8.3: Remove file references from Xcode project**

Open `VoiceInk.xcodeproj` and delete the three references from the navigator (Move to Trash → already deleted, just removes pbxproj entries). Or headless via `xcodeproj`:

```bash
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("VoiceInk.xcodeproj")
target = project.targets.find { |t| t.name == "VoiceInk" }
["WhisperLine.swift", "CursorProximityMonitor.swift", "PulseRibbon.swift"].each do |name|
  refs = project.files.select { |f| f.path&.end_with?(name) }
  refs.each do |ref|
    target.source_build_phase.files_references.delete(ref)
    target.source_build_phase.files.select { |bf| bf.file_ref == ref }.each(&:remove_from_project)
    ref.remove_from_project
  end
end
project.save
'
```

- [ ] **Step 8.4: Verify pbxproj clean**

```bash
grep -cE "WhisperLine\.swift|CursorProximityMonitor\.swift|PulseRibbon\.swift" VoiceInk.xcodeproj/project.pbxproj
```

Expected: 0. If non-zero, repeat Step 8.3.

---

### Task 9: Update `RecorderStylePicker.swift` constellation preview

**Files:**
- Modify: `VoiceInk/Views/Settings/RecorderStylePicker.swift`

The current `ConstellationPreview` (lines 188-274) renders mini orb + chip + card. Replace with anchor + 2 secondaries reflecting the new chip cluster.

- [ ] **Step 9.1: Replace the `ConstellationPreview` struct body**

Open `VoiceInk/Views/Settings/RecorderStylePicker.swift`. Locate `private struct ConstellationPreview: View` (around line 188) and replace its body and helpers (`miniOrb`, `miniChip`, `miniCard`) with:

```swift
private struct ConstellationPreview: View {
    var body: some View {
        VStack(spacing: 6) {
            Spacer().frame(height: 6)
            HStack(spacing: 4) {
                Spacer(minLength: 0)
                miniSecondary(text: "00:14")
                miniAnchor
                miniSecondary(text: "PROMPT")
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var miniAnchor: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(Palette.accent)
                .frame(width: 4, height: 4)
                .shadow(color: Palette.accent.opacity(0.7), radius: 2)
            Text("REC")
                .font(.system(size: 5, weight: .medium, design: .monospaced))
                .tracking(0.3)
                .foregroundStyle(Color.white.opacity(0.95))
        }
        .padding(.horizontal, 4)
        .frame(height: 11)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                )
        )
    }

    private func miniSecondary(text: String) -> some View {
        Text(text)
            .font(.system(size: 5, weight: .medium, design: .monospaced))
            .tracking(0.3)
            .foregroundStyle(Color.white.opacity(0.85))
            .padding(.horizontal, 4)
            .frame(height: 11)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
                    )
            )
    }
}
```

- [ ] **Step 9.2: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Settings/RecorderStylePicker.swift | head -80
```

Expected: removal of `miniOrb`, `miniChip`, `miniCard`; replacement with `miniAnchor`, `miniSecondary`. No other helpers in the file change.

---

### Task 10: Accessibility wiring + verification pass

**Files:** none (verification of Tasks 3, 4, 5).

- [ ] **Step 10.1: Confirm chip-order sequencing**

In `ClusterChips.swift`, every factory returns chips in this order:
1. **Anchor** first.
2. **Reason** chip second (only in `failed`).
3. **Secondaries** next (in left-then-right insertion order — left side renders reversed, but VO reads in array order).
4. **Action** chips last (only in `failed`).

Open `ClusterChips.swift` and walk each factory. Confirm:
- `recordingChips`: anchor → time(left) → prompt(right). VO reads anchor, time, prompt.
- `transcribingChips`: anchor → model(right). VO reads anchor, model.
- `enhancingChips`: anchor → prompt(left) → model(right). VO reads anchor, prompt, model.
- `doneChips`: anchor only. VO reads anchor.
- `failedChips`: anchor → reason(right) → retry(action) → settings(action). VO reads anchor, reason, retry, settings — matches spec §6 line 158.

If any factory breaks this order, fix the array assembly.

- [ ] **Step 10.2: Confirm `accessibilityElement(children: .combine)` lives on `ChipPanel`**

Inspect `ChipPanel.body` — the `.accessibilityElement(children: .combine)` modifier is at the bottom of the VStack. Per-chip labels are set on the inner `chipView(_:)`. The combine pulls them up into one composite element.

- [ ] **Step 10.3: Confirm decorative dots are hidden**

`RingPulseDot` already calls `.accessibilityHidden(true)` (Task 2). `MeterBars` (Task 4) does the same. No additional wiring needed.

---

### Task 11: Mark legacy onboarding files

**Files:**
- Modify: `VoiceInk/Views/Recorder/Constellation/ConstellationCard.swift`
- Modify: `VoiceInk/Views/Recorder/Constellation/ConstellationChip.swift`
- Modify: `VoiceInk/Views/Recorder/Constellation/ConstellationOrb.swift`

These three files survive but are no longer used by the live recorder. Mark them legacy so future drift doesn't reintroduce them into the cluster path.

- [ ] **Step 11.1: ConstellationCard.swift docstring**

At the top of the file, replace the existing first-line doc comment (`// Floating Adaptive Glass card — third satellite ...`) with:

```swift
// MARK: - ConstellationCard (legacy)
//
// Pre-W2 Constellation card. Retained ONLY for `CinematicWalkthrough.swift`
// (onboarding, deferred per spec §5). The live recorder uses
// `ConstellationCluster` + `ChipPanel` instead. Do not add new consumers.
```

- [ ] **Step 11.2: ConstellationChip.swift docstring**

Replace the first MARK block with:

```swift
// MARK: - ConstellationChip (legacy)
//
// Pre-W2 PROVIDER · MODEL capsule. Retained ONLY for `CinematicWalkthrough.swift`
// (onboarding, deferred per spec §5). The live recorder uses chip factories
// in `ClusterChips.swift`. Do not add new consumers.
```

- [ ] **Step 11.3: ConstellationOrb.swift docstring**

Replace the first MARK block with:

```swift
// MARK: - ConstellationOrb (legacy)
//
// Pre-W2 16×16pt state-driven satellite. Retained ONLY for
// `CinematicWalkthrough.swift` (onboarding, deferred per spec §5). The live
// recorder uses `RingPulseDot` inside the anchor chip. Do not add new consumers.
```

- [ ] **Step 11.4: Verify no live-recorder consumers**

```bash
grep -rn "ConstellationCard\|ConstellationChip\|ConstellationOrb" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift" \
  | grep -v "Constellation/ConstellationCard.swift" \
  | grep -v "Constellation/ConstellationChip.swift" \
  | grep -v "Constellation/ConstellationOrb.swift" \
  | grep -v "Onboarding/CinematicWalkthrough.swift"
```

Expected: empty. If anything remains, the cluster refactor is incomplete — fix.

---

### Task 12: Compile-error sweep

**Files:** none (verification).

- [ ] **Step 12.1: Symbol sweep — check the cluster path is self-consistent**

```bash
grep -rn "ConstellationContainer\|ConstellationCluster\|ChipPanel\|ChipDescriptor\|ClusterPhase\|ClusterChips\|RingPulseDot\|chipShimmer\|chipBreath" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift" | head -40
```

Expected: every referenced symbol matches a definition. No "X.swift:N: ConstellationCluster" in a file that hasn't been added.

- [ ] **Step 12.2: HaloPhase + ClusterPhase coexistence sanity**

Both enums exist. Cluster code references `ClusterPhase`. Onboarding + `HaloMaterial` reference `HaloPhase`. They never appear in the same file.

```bash
grep -l "HaloPhase" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift" -r
grep -l "ClusterPhase" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift" -r
```

Expected: the two lists are disjoint, except possibly `RecorderStateProvider.swift` (unaffected) and any test file (none yet).

- [ ] **Step 12.3: AppStorage key sanity**

```bash
grep -rn "failedDwellSeconds" /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/VoiceInk --include="*.swift"
```

Expected: exactly one match — the `@AppStorage("failedDwellSeconds")` in `ConstellationCluster.swift`. W3 will add a Settings UI consumer.

---

### Task 13: Full integration build (the gate)

**Files:** none.

- [ ] **Step 13.1: Run `make local`**

```bash
/usr/bin/make local 2>&1 | tail -40
```

Expected last lines:
```
** BUILD SUCCEEDED **
Copying VoiceInk.app to ~/Downloads...
Build complete! App saved to: ~/Downloads/VoiceInk.app
```

If `BUILD FAILED`, scan for `error:` lines:
```bash
grep -nE "^.* error:" /tmp/voiceink-build.log | head -20
```
- `cannot find 'WhisperLine' in scope` → Task 8 didn't fully strip references; re-run the sweep.
- `cannot find 'ChipDescriptor' in scope` → Task 3 file isn't in the target; check pbxproj for `ChipPanel.swift`.
- `Use of unresolved identifier 'ClusterPhase'` → Task 1 file isn't in the target.
- Any unrelated error → bisect by reverting Task 6's container shim and confirming the legacy path still compiles.

- [ ] **Step 13.2: Sanity-launch the app**

```bash
/usr/bin/killall VoiceInk 2>/dev/null; sleep 1
open ~/Downloads/VoiceInk.app
sleep 3
ps aux | grep -E "/VoiceInk\.app/Contents/MacOS/VoiceInk" | grep -v grep | head -1
```

Expected: a running process. Hit the recorder hotkey; the cluster should appear with REC anchor + TIME + PROMPT (if a prompt is active). Stop the recording — `transcribing` chips appear with shimmer; then `enhancing` with breath halo; then `done` for 1.2s; then collapse.

- [ ] **Step 13.3: Reduce-Motion verification**

System Settings → Accessibility → Display → Reduce Motion ON. Restart the recorder. Expected:
- No ring pulse on the dot (static disc).
- No shimmer on the transcribing chip (full opacity).
- No breath halo on the enhancing chip (static mid-amplitude shadow).
- Cluster mount/unmount uses `clusterFadeReduced` (0.18s opacity).

Toggle Reduce Motion OFF mid-session — the live env value flips and animations resume on the next phase entry.

- [ ] **Step 13.4: VoiceOver order verification**

Cmd+F5 to enable VoiceOver. Trigger a failure (e.g. unplug mic mid-record, or invoke `injectFailure` via a debug menu — W2 ships only the API; manual verification can be done in a future test harness). VO should read: "Failed, \<reason\>, Retry, Open Settings" — matching anchor → reason → action chip order from spec §6.

Cmd+F5 to disable VoiceOver.

- [ ] **Step 13.5: Report status to lead — DO NOT commit**

Per CLAUDE.md, no commits during execution. Report:

```
W2 cluster + state grammar: BUILD GREEN
- New: ClusterPhase, ClusterMotion, ChipPanel, ClusterChips, ConstellationCluster
- Refactored: ConstellationContainer → 12-line shim
- Retired: WhisperLine, CursorProximityMonitor, PulseRibbon
- Legacy-marked: ConstellationCard / Chip / Orb (onboarding only)
- 6 phases render: idle, recording, transcribing, enhancing, done, failed
- Reduce-Motion: 0.18s opacity, no ring/shimmer/breath
- VO order: anchor → reason → secondaries → actions (verified)
- AppStorage: failedDwellSeconds (default 6.0; W3 adds Settings UI)
- W3 seam: ConstellationCluster.injectFailure(reason:) ready
- Diff: <git diff --stat | tail -1>
```

Lead reviews diff, decides whether to commit and dispatch W3.

---

## Self-review

- [x] **Spec coverage.**
  - §1 Material — `clusterFade` 0.24s + `clusterFadeReduced` 0.18s land in `ClusterMotion.swift` (Task 2). `Animation.haloExpand` reused for entry. ✓
  - §2 Structure — anchor centred, secondaries fan out at 8pt, two-row only on `failed`, no idle chrome. `ConstellationLayout.anchorY = notchHeight + 50`. (Tasks 3, 6) ✓
  - §3 Idle — invisible. `ChipPanel` not mounted when `phase == .idle`. (Task 5) ✓
  - §4 State grammar — six phases, motion-keyed. RingPulseDot rate (`.fast` / `.slow` / `.none`), `chipShimmer`, `chipBreath`. (Tasks 2, 4) ✓
  - §4 Reduce-Motion — every modifier branches on `accessibilityReduceMotion`. (Tasks 2, 5) ✓
  - §4 Failure routing — `injectFailure(reason:)` seam stubbed; W3 wires `FailureRegistry`. (Task 5) ✓
  - §6 Accessibility — combined element, anchor → reason → secondaries → actions. (Tasks 3, 4, 10) ✓

- [x] **Placeholder scan.** No `TBD`, no "implement later", no "similar to Task N", no "add error handling". Every step has exact code, exact file:line, or exact command.

- [x] **Type consistency.**
  - `ClusterPhase` only in new files + `ConstellationCluster`. Never collides with `HaloPhase`.
  - `ChipDescriptor`, `ChipPanel`, `ChipDescriptor.Side / Kind / Motion / Row` — used uniformly across Tasks 3, 4, 5.
  - `Palette.accent` / `accentGlow` / `onyxFg` / `onyxMute` — exact spelling matches W1's Task 1 tokens.
  - `.glassChip()` / `.glassPanel()` modifiers — match W1's Task 2 exports.

- [x] **Constructor stability.** `ConstellationContainer<S>` keeps its 4-input constructor (`stateProvider`, `recorder`, `aiService`, `mode`). `MiniWindowManager` and `NotchWindowManager` are not modified.

- [x] **Onboarding compliance.** `ConstellationCard` / `Chip` / `Orb` retained for `CinematicWalkthrough`. Tagged legacy in docstring (Task 11). Onboarding redesign explicitly deferred per spec §5.

- [x] **W3 isolation.** Cluster ships `injectFailure(reason:)` API but does not introduce `FailureRegistry`. AppStorage `failedDwellSeconds` consumed but Settings UI deferred. Menubar dot variant deferred.

- [x] **Build cadence.** No `make local` between tasks; one full build at Task 13.1 per CLAUDE.md.

- [x] **No commits.** Final step reports to lead. CLAUDE.md respected.

- [x] **No emoji in code.** All chip labels are SF Symbol glyphs (`checkmark.circle.fill`) or text (`"PASTED"`, `"→"` is U+2192 typographic arrow not an emoji). Spec uses ✓ in description; the implementation uses `Image(systemName: "checkmark.circle.fill")`.

---

## Acceptance criteria

- ✅ `make local` completes with `** BUILD SUCCEEDED **`.
- ✅ Cluster mounts on recorder hotkey; idle = invisible; six phases (recording, transcribing, enhancing, done, failed) all render with correct chip slate.
- ✅ Recording chip shows REC + meter bars + ringPulse on dot; TIME secondary increments by 1s; PROMPT secondary shows active prompt.
- ✅ Transcribing chip shimmers (α 0.62 ↔ 1.0 over 1.4s); MODEL secondary visible.
- ✅ Enhancing chip breathes (outer halo cycle); PROMPT + MODEL secondaries visible.
- ✅ Done chip shows ✓ PASTED → \<app\>; dwells 1.2s; fades over 0.24s.
- ✅ Failed cluster shows FAIL anchor + reason chip + RETRY + OPEN SETTINGS; dwells `failedDwellSeconds` (default 6.0); RETRY clears injected failure; OPEN SETTINGS posts notification.
- ✅ Reduce-Motion ON → no ring pulse, no shimmer, no breath; 0.18s opacity for entry/exit.
- ✅ VoiceOver order: anchor → reason → secondaries → actions.
- ✅ Sweep `grep -rn "WhisperLine\|CursorProximityMonitor\|PulseRibbon" VoiceInk --include="*.swift"` returns 0 matches.
- ✅ Sweep `grep -rn "ConstellationCard\|ConstellationChip\|ConstellationOrb" VoiceInk --include="*.swift" | grep -v "Constellation/Constellation\|Onboarding/CinematicWalkthrough"` returns 0 matches.
- ✅ `RecorderStylePicker` Constellation tile renders the new chip silhouette (anchor + 2 secondaries).

## Estimated effort

~6-7 hours for an engineer familiar with the codebase. ~9-10 hours for a fresh teammate (most of the time is the 5 new files + Task 6's careful container shim + Task 13 verification cycles, not algorithm complexity).
