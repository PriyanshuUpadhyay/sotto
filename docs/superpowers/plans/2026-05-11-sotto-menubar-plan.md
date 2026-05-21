# Sotto MENUBAR — Stateful Menubar Icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the static `Image(nsImage:)` menubar glyph with a 7-state SwiftUI `MenubarGlyph` (Canvas + Path) hosted in `MenuBarExtra` label, driven by `RecordingStateObserver`, with VoiceOver announcements on state transition. Provide a Path B fallback (extended `MenuBarIconRenderer` static-NSImage builders driven by timer snapshots) that activates only if the macOS-14.4 animation spike fails.

**Architecture:**
1. Path A (default): pure SwiftUI inside `MenuBarExtra { … } label: { MenubarGlyph(state:) }`. Animations driven by `TimelineView(.animation)` so state-keyed loops persist across menu-bar snapshot re-renders.
2. `RecordingStateObserver.IconState` grows three view-lifetime cases (`.arming`, `.committed`, `.fail`) fed by HUD pair's `HaloPhase` via an injected `CurrentValueSubject<HaloPhase, Never>` (Combine bridge — HUD pair owns the source; MENUBAR pair owns the sink).
3. Two-stroke brand glyph (mark in `.primary`, underscore in `Palette.brandAcid`) drawn via `Path`. Per-state overlays (`BouncingDots`, `ArcSpinner`, corner `Circle`, fail `!`) composited via `ZStack`.
4. Accessibility: `accessibilityLabel` per state + one-shot `AccessibilityNotification.announcement` on each transition.
5. Path B fallback: extend existing `MenuBarIconRenderer` static builders + a `Timer.publish` snapshot loop that updates `Image(nsImage:)` 8×/sec. Stateful but not smooth; lime underscore + corner dots preserved.

**Tech Stack:** SwiftUI 5 (macOS 14.4+), Combine, AppKit (`NSAppearance`, `NSWorkspace`), `MenuBarExtra` with `.menuBarExtraStyle(.menu)`, `TimelineView(.animation)`, XCTest for state-mapping tests.

**Spec anchors:** §1.X (a11y), §4.2 (state table), §5.2 (glyph proportions), §5.3 (size/tint contract), §5.4 (single-path commitment), §6.1 surface 3, Appendix B.MenubarSpike / B.DarkLightFlip, Appendix C.MENUBAR.

**Dependencies (must verify before each task):**
- **RENAME pair:** bundle-ID rename owns `MenuBarExtra` ownership — Path A requires the renamed bundle to be in place for `MenuBarExtra` identity. Confirm `PRODUCT_BUNDLE_IDENTIFIER` switched before Step 4.
- **ICON pair:** Path B fallback needs glyph-base asset(s) if Canvas spike fails. Path A draws via `Path` — no asset dependency. Only invoked in Step 7.
- **HUD pair:** owns `HaloPhase` lifetime + `Palette.brandAcid` token (renamed from `Palette.accent`). Steps 1, 2, 3 reference `Palette.brandAcid`; if HUD pair has not yet renamed, the MENUBAR pair adds a local `Color(red: 0.831, green: 1.0, blue: 0.227)` constant inside `MenubarGlyph.swift` with a `// TODO(HUD): switch to Palette.brandAcid once renamed` comment — but this is the only place that fallback constant may appear.

---

## File Structure

**Create:**
- `VoiceInk/Views/Common/MenubarGlyph.swift` — SwiftUI Canvas/Path glyph view + per-state overlay views + appearance observer. ~250 lines.
- `VoiceInkTests/MenubarGlyphTests.swift` — pure-logic tests for `IconState` mapping + accessibility-label generation.

**Modify:**
- `VoiceInk/Views/Common/MenuBarIconRenderer.swift`:
  - Extend `IconState` enum (add `.arming`, `.committed`, `.fail`).
  - Extend `RecordingStateObserver` to consume `HaloPhase` (new `bind(toHalo:)` method).
  - Replace `MenuBarIcon` body — swap `Image(nsImage:)` for `MenubarGlyph(state:)`.
  - Extend `accessibilityLabel` for new states.
  - Path B only: add `arming()`, `committed()`, `failedBadge()` static-NSImage builders. Skipped if spike passes.

**Untouched:**
- `VoiceInk/VoiceInk.swift` lines 476–502 — `MenuBarExtra` mount + `.menuBarExtraStyle(.menu)`. The label-closure body resolves `MenuBarIcon(observer:)` which now internally renders `MenubarGlyph`. No structural change needed.
- `VoiceInk/Views/MenuBarView.swift` — dropdown contents. Out of scope.

---

## Task 0: SPIKE — verify Canvas/Path animation inside MenuBarExtra label

**Goal:** Confirm (a) `TimelineView(.animation)` loops keep running inside the `MenuBarExtra` label closure across menu-bar snapshot extractions, (b) battery cost of a 1.6s repeat-forever animation is acceptable, (c) the glyph reads on both dark and light menubars on macOS 14.4. If any of (a)/(b)/(c) fail, the implementation switches to Path B (Step 7).

**Files:**
- Create: `VoiceInk/Views/Common/MenubarGlyphSpike.swift` (DEBUG-only, deleted in Step 7 cleanup or kept under `#if DEBUG` after Step 4)

- [ ] **Step 1: Write the spike harness**

Create `VoiceInk/Views/Common/MenubarGlyphSpike.swift`:

```swift
#if DEBUG
import SwiftUI

/// Spike harness — Appendix B.MenubarSpike. Verifies that a Canvas/Path view
/// inside MenuBarExtra label animates persistently on macOS 14.4 via
/// TimelineView(.animation). Deleted or gated behind a launch flag after the
/// spike is resolved.
struct MenubarGlyphSpike: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let phase = (sin(t * 2 * .pi / 1.6) + 1) / 2   // 0…1 over 1.6s
            Canvas { ctx, size in
                let stroke = Color.primary.opacity(0.4 + 0.6 * phase)
                let mark = Path(CGRect(
                    x: size.width * 0.41,
                    y: size.height * 0.15,
                    width: size.width * 0.18,
                    height: size.height * 0.55
                ))
                ctx.fill(mark, with: .color(stroke))
                let underscore = Path(CGRect(
                    x: 0,
                    y: size.height * 0.78,
                    width: size.width,
                    height: size.height * 0.14
                ))
                ctx.fill(underscore, with: .color(.init(red: 0.831, green: 1.0, blue: 0.227)))
            }
            .frame(width: 18, height: 18)
        }
    }
}
#endif
```

- [ ] **Step 2: Temporarily mount spike in MenuBarExtra label**

In `VoiceInk/VoiceInk.swift` around line 495, temporarily replace `MenuBarIcon(observer:)` with `MenubarGlyphSpike()` behind a `#if DEBUG` block. Keep the diff trivial — this is throwaway.

```swift
} label: {
    #if DEBUG
    MenubarGlyphSpike()
    #else
    MenuBarIcon(observer: appDelegate.recordingStateObserver)
    #endif
}
```

- [ ] **Step 3: Build and run; observe**

Run: `make local` (or `make reload`).
Open Activity Monitor → Energy tab → filter by `Sotto` (or `VoiceInk` pre-RENAME).

Acceptance checks:
1. **Animation persistence:** menubar glyph alpha breathes 0.4↔1.0 continuously for ≥ 60 seconds with the menubar NOT being clicked. (If macOS pauses repaints when the bar is idle, the breath visibly resumes/restarts on hover — that pattern counts as PASS but should be noted.)
2. **Battery:** average energy impact reading after 60s of breath < 1.0 (qualitative — should be `Low`).
3. **Dark menubar:** glyph mark visible against `.darkAqua` menubar.
4. **Light menubar:** switch System Settings → Appearance → Light. Glyph mark still readable (mark renders `.primary` so it auto-flips).
5. **Wallpaper hostility:** set wallpaper to a white photograph (light menubar can become near-white). Mark still visible (or flag for §5.3 1pt-outline mitigation later).

- [ ] **Step 4: Record spike result**

Append to `W14F_smoke_test_results.md` (or create `docs/superpowers/handoffs/HANDOFF_menubar_spike_2026-05-11.md` if smoke results doc is sealed):

```markdown
## MenubarSpike (B.MenubarSpike) — 2026-05-11

- Path A viable: YES / NO
- Animation persistence: <observation>
- Battery (Activity Monitor Energy column after 60s breath): <reading>
- Dark menubar: <PASS / FAIL>
- Light menubar: <PASS / FAIL>
- Hostile wallpaper: <PASS / NEEDS-OUTLINE-MITIGATION / FAIL>

Decision: proceed with Path A / fall back to Path B.
```

- [ ] **Step 5: Branch decision**

- If **Path A viable** → revert the `MenuBarExtra` label change (keep `MenuBarIcon(observer:)` calling site, delete or guard `MenubarGlyphSpike`), then proceed to Task 1.
- If **Path A NOT viable** → skip Tasks 1–6 entirely and jump to Task 7 (Path B fallback). Document the failure mode in the handoff for ICON pair (they may need to ship additional asset variants).

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Views/Common/MenubarGlyphSpike.swift VoiceInk/VoiceInk.swift docs/superpowers/handoffs/HANDOFF_menubar_spike_2026-05-11.md
git commit -m "spike(menubar): verify Canvas/Path animation in MenuBarExtra label (B.MenubarSpike)"
```

---

## Task 1: MenubarGlyph Canvas view — two-stroke mark + lime underscore

**Path A only.** Skip if Step 5 selected Path B.

**Files:**
- Create: `VoiceInk/Views/Common/MenubarGlyph.swift`
- Test: `VoiceInkTests/MenubarGlyphTests.swift`

- [ ] **Step 1: Write the failing test for glyph proportions**

Create `VoiceInkTests/MenubarGlyphTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import VoiceInk

final class MenubarGlyphTests: XCTestCase {
    func test_glyphProportions_matchSpec_5_2() {
        // Spec §5.2: mark 0.18S × 0.55S, underscore 1.00S × 0.14S, gap 0.08S.
        let s: CGFloat = 18
        XCTAssertEqual(MenubarGlyph.markWidthRatio, 0.18, accuracy: 0.001)
        XCTAssertEqual(MenubarGlyph.markHeightRatio, 0.55, accuracy: 0.001)
        XCTAssertEqual(MenubarGlyph.underscoreWidthRatio, 1.00, accuracy: 0.001)
        XCTAssertEqual(MenubarGlyph.underscoreHeightRatio, 0.14, accuracy: 0.001)
        XCTAssertEqual(MenubarGlyph.gapRatio, 0.08, accuracy: 0.001)
        XCTAssertEqual(
            MenubarGlyph.markHeightRatio
            + MenubarGlyph.gapRatio
            + MenubarGlyph.underscoreHeightRatio,
            0.77,
            accuracy: 0.001,
            "Mark + gap + underscore should equal 0.77S (vertically centred with 0.115S top/bottom)"
        )
        _ = s  // silence unused
    }
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `xcodebuild test -scheme VoiceInk -only-testing:VoiceInkTests/MenubarGlyphTests/test_glyphProportions_matchSpec_5_2`
Expected: FAIL with "Cannot find 'MenubarGlyph' in scope".

- [ ] **Step 3: Implement MenubarGlyph base**

Create `VoiceInk/Views/Common/MenubarGlyph.swift`:

```swift
import SwiftUI
import AppKit

// MARK: - MenubarGlyph
//
// Pure-SwiftUI two-stroke brand mark drawn via Path. Spec §5.2.
//
// 18×18pt canvas. Mark (vertical bar) renders Color.primary so it auto-flips
// against light/dark menubars. Underscore stays Palette.brandAcid in both
// modes per §5.3 (lime is the brand-mark; non-template at every menubar size).
//
// State overlays (BouncingDots, ArcSpinner, corner dots, fail !) composited
// on top via ZStack in MenubarGlyphContainer. This struct draws ONLY the
// base mark + underscore.

struct MenubarGlyph: View {
    /// 0…1 — caller-supplied alpha for breathe motion (arming state). Default 1.0.
    var alpha: Double = 1.0

    /// Whether the mark fills (recording = white-on-black inverse) or strokes
    /// (default). Spec §4.2 row 3.
    var markFilled: Bool = true

    /// Whether the underscore renders. Spec §4.2 row 5 hollows the mark during
    /// `enhancing` — but the underscore stays. Always true at v1; reserved for
    /// future "ghost" idle treatments.
    var underscoreVisible: Bool = true

    // Spec §5.2 — proportions exposed as static constants for test access.
    static let markWidthRatio: CGFloat = 0.18
    static let markHeightRatio: CGFloat = 0.55
    static let underscoreWidthRatio: CGFloat = 1.00
    static let underscoreHeightRatio: CGFloat = 0.14
    static let gapRatio: CGFloat = 0.08

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let totalH = (Self.markHeightRatio + Self.gapRatio + Self.underscoreHeightRatio) * s
            let topInset = (s - totalH) / 2.0

            // Mark — centred horizontally.
            let markW = Self.markWidthRatio * s
            let markH = Self.markHeightRatio * s
            let markRect = CGRect(
                x: (s - markW) / 2.0,
                y: topInset,
                width: markW,
                height: markH
            )
            let mark = Path(roundedRect: markRect, cornerRadius: markW * 0.15)
            if markFilled {
                ctx.fill(mark, with: .color(Color.primary.opacity(alpha)))
            } else {
                ctx.stroke(mark, with: .color(Color.primary.opacity(alpha)), lineWidth: 1.2)
            }

            // Underscore — full width, below mark + gap.
            guard underscoreVisible else { return }
            let usY = topInset + markH + Self.gapRatio * s
            let usH = Self.underscoreHeightRatio * s
            let usRect = CGRect(x: 0, y: usY, width: s, height: usH)
            let us = Path(roundedRect: usRect, cornerRadius: usH * 0.3)
            ctx.fill(us, with: .color(Palette.brandAcid.opacity(alpha)))
        }
        .frame(width: 18, height: 18)
    }
}
```

> **HUD-dep guard:** if `Palette.brandAcid` does not yet exist (HUD pair has not landed the rename), add the following constant at the top of `MenubarGlyph.swift` and use it everywhere `Palette.brandAcid` appears in this file:
>
> ```swift
> // TODO(HUD): replace with Palette.brandAcid once HUD pair renames Palette.accent.
> private let _brandAcidFallback = Color(red: 0.831, green: 1.0, blue: 0.227)
> ```
>
> Use `_brandAcidFallback` instead of `Palette.brandAcid`. Update in a follow-up commit when HUD lands.

- [ ] **Step 4: Run test — verify it passes**

Run: `xcodebuild test -scheme VoiceInk -only-testing:VoiceInkTests/MenubarGlyphTests/test_glyphProportions_matchSpec_5_2`
Expected: PASS.

- [ ] **Step 5: Add a SwiftUI preview**

Append to `MenubarGlyph.swift`:

```swift
#if DEBUG
#Preview("MenubarGlyph — Dark") {
    MenubarGlyph()
        .frame(width: 64, height: 64)
        .padding()
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("MenubarGlyph — Light") {
    MenubarGlyph()
        .frame(width: 64, height: 64)
        .padding()
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
```

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Views/Common/MenubarGlyph.swift VoiceInkTests/MenubarGlyphTests.swift
git commit -m "feat(menubar): MenubarGlyph Canvas/Path base — two-stroke mark + lime underscore"
```

---

## Task 2: Extend RecordingStateObserver.IconState — `.arming`, `.committed`, `.fail`

**Files:**
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift:28-54, 173-220`
- Test: `VoiceInkTests/MenubarGlyphTests.swift`

- [ ] **Step 1: Write failing tests for the new IconState mapping**

Append to `VoiceInkTests/MenubarGlyphTests.swift`:

```swift
extension MenubarGlyphTests {
    func test_iconState_fromHaloPhase_armed_mapsTo_arming() {
        XCTAssertEqual(
            MenuBarIconRenderer.IconState(haloPhase: .armed),
            .arming
        )
    }

    func test_iconState_fromHaloPhase_done_mapsTo_committed() {
        XCTAssertEqual(
            MenuBarIconRenderer.IconState(haloPhase: .done),
            .committed
        )
    }

    func test_iconState_fromHaloPhase_failed_mapsTo_fail() {
        XCTAssertEqual(
            MenuBarIconRenderer.IconState(haloPhase: .failed),
            .fail
        )
    }

    func test_iconState_handsFreeBeatsHaloPhase() {
        // handsFree active overrides any halo phase — same precedence as
        // the existing init(handsFree:recordingState:).
        let state = MenuBarIconRenderer.IconState(
            handsFree: .listening,
            recordingState: .idle,
            haloPhase: .recording
        )
        XCTAssertEqual(state, .handsFree)
    }

    func test_iconState_haloPhase_done_beats_recordingState_idle() {
        // After commit, engine returns to .idle but view-side HaloPhase holds
        // .done for 1.5s. The menubar must reflect .committed during that hold.
        let state = MenuBarIconRenderer.IconState(
            handsFree: .inactive,
            recordingState: .idle,
            haloPhase: .done
        )
        XCTAssertEqual(state, .committed)
    }
}
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `xcodebuild test -scheme VoiceInk -only-testing:VoiceInkTests/MenubarGlyphTests`
Expected: FAIL — "Type 'MenuBarIconRenderer.IconState' has no member 'arming'" / no `init(haloPhase:)` etc.

- [ ] **Step 3: Extend IconState enum**

Edit `VoiceInk/Views/Common/MenuBarIconRenderer.swift` lines 28-54. Replace the `IconState` enum:

```swift
    /// Icon state — derived from engine `RecordingState` + view-side `HaloPhase`
    /// (which holds `.done` for 1.5s post-commit and `.failed` until dismissed).
    /// Hands-free overrides both.
    enum IconState: Equatable {
        case idle
        case arming         // HaloPhase.armed — pre-first-audio breathe
        case recording
        case transcribing
        case enhancing
        case committed      // HaloPhase.done — 1.5s green dot post-commit
        case fail           // HaloPhase.failed — red ! until dismissed
        case handsFree      // W12.D

        /// Engine-only init — legacy callers without HaloPhase. Maps engine
        /// states; .arming / .committed / .fail are view-lifetime states
        /// unreachable from engine alone.
        init(_ state: RecordingState) {
            switch state {
            case .recording:    self = .recording
            case .transcribing: self = .transcribing
            case .enhancing:    self = .enhancing
            default:            self = .idle
            }
        }

        /// HaloPhase-only init — view-side states.
        init(haloPhase: HaloPhase) {
            switch haloPhase {
            case .hidden:                        self = .idle
            case .armed:                         self = .arming
            case .recording, .liveText:          self = .recording
            case .transcribing:                  self = .transcribing
            case .enhancing:                     self = .enhancing
            case .done:                          self = .committed
            case .failed:                        self = .fail
            }
        }

        /// Combined init. Precedence: hands-free > halo-phase view state
        /// > engine state. Halo-phase view-state cases that aren't covered by
        /// `.hidden` always win over engine state because engine returns to
        /// .idle immediately on commit/fail while the HUD holds the view state.
        init(
            handsFree: HandsFreeSessionState,
            recordingState: RecordingState,
            haloPhase: HaloPhase
        ) {
            if handsFree != .inactive {
                self = .handsFree
                return
            }
            switch haloPhase {
            case .hidden:
                self.init(recordingState)
            default:
                self.init(haloPhase: haloPhase)
            }
        }

        /// Legacy combined init without HaloPhase — preserved so existing
        /// callers still compile during the rollout window. Delegates to the
        /// 3-arg form with `.hidden` (no view-state override).
        init(handsFree: HandsFreeSessionState, recordingState: RecordingState) {
            self.init(
                handsFree: handsFree,
                recordingState: recordingState,
                haloPhase: .hidden
            )
        }
    }
```

- [ ] **Step 4: Extend RecordingStateObserver to consume HaloPhase**

Edit `VoiceInk/Views/Common/MenuBarIconRenderer.swift` lines 173-220. Replace the class body. Add a `haloPhaseSubject` property + a `bind(toHalo:)` method that wires a publisher provided by `RecorderUIManager` (HUD pair).

```swift
final class RecordingStateObserver: ObservableObject {
    @Published private(set) var iconState: MenuBarIconRenderer.IconState = .idle
    @Published private(set) var unresolvedFailures: Int = 0

    private var stateCancellable: AnyCancellable?
    private var registryCancellable: AnyCancellable?

    // View-side phase published by RecorderUIManager (HUD pair). Defaults to
    // `.hidden` so engine state drives behavior until HUD wires its publisher.
    private let haloPhaseSubject = CurrentValueSubject<HaloPhase, Never>(.hidden)
    private var haloCancellable: AnyCancellable?

    @MainActor
    func bind(to engine: VoiceInkEngine) {
        stateCancellable?.cancel()
        stateCancellable = Publishers.CombineLatest3(
            engine.$recordingState,
            HandsFreeSessionService.shared.$state,
            haloPhaseSubject
        )
        .receive(on: DispatchQueue.main)
        .map { recordingState, handsFreeState, haloPhase in
            MenuBarIconRenderer.IconState(
                handsFree: handsFreeState,
                recordingState: recordingState,
                haloPhase: haloPhase
            )
        }
        .removeDuplicates()
        .sink { [weak self] next in
            self?.iconState = next
        }
    }

    @MainActor
    func bind(toRegistry registry: FailureRegistry) {
        registryCancellable?.cancel()
        registryCancellable = registry.$unresolvedCount
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] next in
                self?.unresolvedFailures = next
            }
    }

    /// HUD pair calls this with a publisher of `HaloPhase` so the menubar
    /// reflects view-lifetime states (`.armed`, `.done`, `.failed`) that the
    /// engine doesn't expose. Until called, haloPhaseSubject stays `.hidden`
    /// and engine state alone drives the icon — backward-compatible.
    @MainActor
    func bind<P: Publisher>(toHalo publisher: P) where P.Output == HaloPhase, P.Failure == Never {
        haloCancellable?.cancel()
        haloCancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] phase in
                self?.haloPhaseSubject.send(phase)
            }
    }

    deinit {
        stateCancellable?.cancel()
        registryCancellable?.cancel()
        haloCancellable?.cancel()
    }
}
```

- [ ] **Step 5: Wire bind(toHalo:) at app startup**

In `VoiceInk/VoiceInk.swift`, find the existing `recordingStateObserver.bind(to: engine)` and `.bind(toRegistry: failureRegistry)` calls in `AppDelegate` (or wherever they currently live — `grep -n 'recordingStateObserver.bind' VoiceInk/`). Add immediately after:

```swift
recordingStateObserver.bind(toHalo: recorderUIManager.$haloPhase)
```

> If `RecorderUIManager` does not yet expose `@Published var haloPhase: HaloPhase` — coordinate with HUD pair. Their plan must publish it. If their commit lands after MENUBAR's, ship Step 5 in a follow-up; the new code is no-op until the publisher is wired (haloPhaseSubject stays `.hidden`).

- [ ] **Step 6: Run tests — verify they pass**

Run: `xcodebuild test -scheme VoiceInk -only-testing:VoiceInkTests/MenubarGlyphTests`
Expected: PASS (all 7 tests).

- [ ] **Step 7: Commit**

```bash
git add VoiceInk/Views/Common/MenuBarIconRenderer.swift VoiceInk/VoiceInk.swift VoiceInkTests/MenubarGlyphTests.swift
git commit -m "feat(menubar): extend IconState with arming/committed/fail + HaloPhase binding"
```

---

## Task 3: Per-state overlay subviews — BouncingDots, ArcSpinner, CornerBadge, FailGlyph

**Files:**
- Modify: `VoiceInk/Views/Common/MenubarGlyph.swift`

- [ ] **Step 1: Add BouncingDots subview**

Append to `MenubarGlyph.swift`:

```swift
// MARK: - State overlays
//
// Each overlay is a self-contained TimelineView-driven SwiftUI view. They
// composite on top of (or in place of) MenubarGlyph in MenubarGlyphContainer.

/// Transcribing state — 3 dots, vertical phase-offset translation.
/// Spec §4.2 row 4 ("glyph swaps to 3 bouncing dots").
struct BouncingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<3) { i in
                    let phase = (t + Double(i) * 0.18).truncatingRemainder(dividingBy: 0.9) / 0.9
                    let dy = sin(phase * 2 * .pi) * 2.0
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 3.2, height: 3.2)
                        .offset(y: -dy)
                }
            }
            .frame(width: 18, height: 18)
        }
    }
}
```

- [ ] **Step 2: Add ArcSpinner subview**

Append:

```swift
/// Enhancing state — 270° arc rotating 1.6s linear over a hollow mark.
/// Spec §4.2 row 5.
struct ArcSpinner: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: 1.6)) / 1.6 * 360
            Canvas { ctx, size in
                let s = min(size.width, size.height)
                let inset: CGFloat = 2.5
                let rect = CGRect(
                    x: (size.width - s) / 2 + inset,
                    y: (size.height - s) / 2 + inset,
                    width: s - inset * 2,
                    height: s - inset * 2
                )
                var path = Path()
                path.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: rect.width / 2,
                    startAngle: .degrees(angle),
                    endAngle: .degrees(angle + 270),
                    clockwise: false
                )
                ctx.stroke(path, with: .color(Color.primary), lineWidth: 1.2)
            }
            .frame(width: 18, height: 18)
        }
    }
}
```

- [ ] **Step 3: Add CornerBadge subview**

Append:

```swift
/// Recording (red, pulsing 1.0s) / committed (green, static) corner dot.
/// Drawn in the upper-right of the 18pt canvas. Spec §4.2 rows 3 and 6.
struct CornerBadge: View {
    enum Kind {
        case redPulse, greenStatic, redStatic
        var color: Color {
            switch self {
            case .redPulse, .redStatic: return Color(red: 1.0, green: 0.231, blue: 0.188)
            case .greenStatic:          return Color(red: 0.188, green: 0.820, blue: 0.345)
            }
        }
    }

    let kind: Kind

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let alpha: Double = {
                switch kind {
                case .redPulse:
                    return 0.5 + 0.5 * sin(t * 2 * .pi)   // 1.0s pulse
                case .greenStatic, .redStatic:
                    return 1.0
                }
            }()
            ZStack(alignment: .topTrailing) {
                Color.clear
                Circle()
                    .fill(kind.color.opacity(alpha))
                    .frame(width: 4, height: 4)
                    .padding(.top, 1)
                    .padding(.trailing, 1)
            }
            .frame(width: 18, height: 18)
        }
    }
}
```

- [ ] **Step 4: Add FailGlyph subview**

Append:

```swift
/// Fail state — red `!` overlay + red corner badge. Spec §4.2 row 7.
struct FailGlyph: View {
    var body: some View {
        ZStack {
            Text("!")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color(red: 1.0, green: 0.231, blue: 0.188))
            CornerBadge(kind: .redStatic)
        }
        .frame(width: 18, height: 18)
    }
}
```

- [ ] **Step 5: Add MenubarGlyphContainer — top-level state-routing view**

Append:

```swift
// MARK: - MenubarGlyphContainer
//
// Routes IconState to the per-state composition. This is the view the
// MenuBarExtra label closure hosts.

struct MenubarGlyphContainer: View {
    let state: MenuBarIconRenderer.IconState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch state {
        case .idle:
            MenubarGlyph()
        case .arming:
            if reduceMotion {
                MenubarGlyph(alpha: 0.75)   // static, no breathe
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let breathe = 0.55 + 0.45 * (sin(t * 2 * .pi / 1.2) + 1) / 2
                    MenubarGlyph(alpha: breathe)
                }
            }
        case .recording:
            ZStack {
                MenubarGlyph(markFilled: true)
                if reduceMotion {
                    CornerBadge(kind: .redStatic)
                } else {
                    CornerBadge(kind: .redPulse)
                }
            }
        case .transcribing:
            BouncingDots()   // already opacity-only-friendly; spec accepts as-is
        case .enhancing:
            ZStack {
                MenubarGlyph(markFilled: false)   // hollow
                if !reduceMotion {
                    ArcSpinner()
                }
            }
        case .committed:
            ZStack {
                MenubarGlyph()
                CornerBadge(kind: .greenStatic)
            }
        case .fail:
            FailGlyph()
        case .handsFree:
            // Preserve existing hands-free affordance — ear-fill template via
            // the legacy NSImage builder. SwiftUI bridge via Image(nsImage:).
            Image(nsImage: MenuBarIconRenderer.image(for: .handsFree))
        }
    }
}
```

- [ ] **Step 6: Add previews for each state**

Append:

```swift
#if DEBUG
private struct MenubarStatePreviewGrid: View {
    var body: some View {
        let states: [MenuBarIconRenderer.IconState] = [
            .idle, .arming, .recording, .transcribing,
            .enhancing, .committed, .fail, .handsFree
        ]
        VStack(spacing: 14) {
            ForEach(Array(states.enumerated()), id: \.offset) { _, s in
                HStack {
                    Text(String(describing: s)).font(.system(.caption, design: .monospaced))
                        .frame(width: 100, alignment: .leading)
                    MenubarGlyphContainer(state: s).frame(width: 18, height: 18)
                    MenubarGlyphContainer(state: s).frame(width: 64, height: 64)
                }
            }
        }
        .padding(24)
    }
}

#Preview("All states — Dark") {
    MenubarStatePreviewGrid()
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("All states — Light") {
    MenubarStatePreviewGrid()
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
```

- [ ] **Step 7: Build + visual check**

Run: `make local`
Acceptance: Xcode preview canvas shows all 8 states. Recording pulses red, transcribing dots bounce, enhancing arc spins, committed shows green dot, fail shows `!`. Idle/arming/handsFree render as expected.

- [ ] **Step 8: Commit**

```bash
git add VoiceInk/Views/Common/MenubarGlyph.swift
git commit -m "feat(menubar): per-state overlays — BouncingDots, ArcSpinner, CornerBadge, FailGlyph"
```

---

## Task 4: Replace MenuBarIcon body — swap NSImage for MenubarGlyphContainer

**Files:**
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift:230-259`

**Pre-flight:** confirm RENAME pair has landed the bundle-ID change (`mdfind "kMDItemCFBundleIdentifier == 'com.sotto.Sotto'"` returns the build product) OR the user has explicitly authorised proceeding before RENAME.

- [ ] **Step 1: Replace MenuBarIcon body**

Edit `VoiceInk/Views/Common/MenuBarIconRenderer.swift` lines 230-259. Replace the entire `MenuBarIcon` struct:

```swift
// MARK: - MenuBarIcon (SwiftUI label for MenuBarExtra)
//
// Hosts MenubarGlyphContainer — pure-SwiftUI Canvas/Path mark with state
// overlays driven by TimelineView. Spec §5.4 single-path commitment.
//
// Path B fallback (extended MenuBarIconRenderer static-NSImage builders) is
// available via `MenuBarIcon.usePathBFallback = true` at build time if the
// macOS-14.4 animation spike (Appendix B.MenubarSpike) fails.

struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver

    var body: some View {
        Group {
            if Self.usePathBFallback {
                // Path B — static NSImage per state, timer-snapshot updated.
                Image(
                    nsImage: MenuBarIconRenderer.image(
                        for: observer.iconState,
                        unresolvedFailures: observer.unresolvedFailures
                    )
                )
            } else {
                // Path A — pure SwiftUI.
                ZStack {
                    MenubarGlyphContainer(state: observer.iconState)
                    if observer.unresolvedFailures > 0 && observer.iconState != .fail {
                        // Failure registry badge overlays non-fail states.
                        CornerBadge(kind: .redStatic)
                    }
                }
                .frame(width: 18, height: 18)
            }
        }
        .accessibilityLabel(Text(accessibilityLabel))
    }

    /// Compile-time switch. Default false (Path A). Flip to true only if
    /// Task 0 spike showed Path A unviable on macOS 14.4.
    static let usePathBFallback: Bool = false

    var accessibilityLabel: String {
        let base: String = {
            switch observer.iconState {
            case .idle:         return "Sotto idle"
            case .arming:       return "Sotto listening"
            case .recording:    return "Sotto recording"
            case .transcribing: return "Sotto transcribing"
            case .enhancing:    return "Sotto enhancing"
            case .committed:    return "Sotto committed, paste available"
            case .fail:         return "Sotto failed"
            case .handsFree:    return "Sotto hands-free"
            }
        }()
        guard observer.unresolvedFailures > 0 else { return base }
        let suffix = observer.unresolvedFailures == 1
            ? "1 unresolved failure"
            : "\(observer.unresolvedFailures) unresolved failures"
        return "\(base), \(suffix)"
    }
}
```

> The string "Sotto" here assumes RENAME has landed. If RENAME has NOT landed when MENUBAR ships, replace "Sotto" with "VoiceInk" in the labels and add a `// TODO(RENAME): switch to Sotto post-rename` comment. RENAME pair owns the swap in their PR.

- [ ] **Step 2: Build + smoke test**

Run: `make local`
Manually verify:
1. Idle: mark + lime underscore visible.
2. Trigger recording (hotkey): red corner badge pulses.
3. Stop recording: transcribing bouncing dots → enhancing arc spin → green committed badge → returns to idle.
4. Force a failure (disconnect mic mid-record, or trigger via debug menu): red `!` badge appears, stays until clicked.

- [ ] **Step 3: Run the test suite**

Run: `xcodebuild test -scheme VoiceInk -only-testing:VoiceInkTests/MenubarGlyphTests`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add VoiceInk/Views/Common/MenuBarIconRenderer.swift
git commit -m "feat(menubar): wire MenubarGlyphContainer into MenuBarExtra label"
```

---

## Task 5: Accessibility — VoiceOver announcement on state transition

**Spec anchor:** §1.X — "live announcement via `AccessibilityNotification.announcement(...)` on transition is the ceiling."

**Files:**
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift` (MenuBarIcon struct)
- Test: `VoiceInkTests/MenubarGlyphTests.swift`

- [ ] **Step 1: Write failing test for announcement-string mapping**

Append to `VoiceInkTests/MenubarGlyphTests.swift`:

```swift
extension MenubarGlyphTests {
    func test_announcementString_matchesSpec_4_2_a11y() {
        XCTAssertEqual(MenuBarIcon.announcementString(for: .arming),       "Sotto listening")
        XCTAssertEqual(MenuBarIcon.announcementString(for: .recording),    "Sotto recording")
        XCTAssertEqual(MenuBarIcon.announcementString(for: .transcribing), "Sotto transcribing")
        XCTAssertEqual(MenuBarIcon.announcementString(for: .enhancing),    "Sotto enhancing")
        XCTAssertEqual(MenuBarIcon.announcementString(for: .committed),    "Sotto committed")
        XCTAssertEqual(MenuBarIcon.announcementString(for: .fail),         "Sotto failed")
        XCTAssertNil(MenuBarIcon.announcementString(for: .idle),
                     "idle should not announce — silent return-to-rest")
        XCTAssertNil(MenuBarIcon.announcementString(for: .handsFree),
                     "handsFree announcements owned by HandsFreeSessionService, not menubar")
    }
}
```

- [ ] **Step 2: Run test — verify it fails**

Run: `xcodebuild test -scheme VoiceInk -only-testing:VoiceInkTests/MenubarGlyphTests/test_announcementString_matchesSpec_4_2_a11y`
Expected: FAIL — "Type 'MenuBarIcon' has no member 'announcementString'".

- [ ] **Step 3: Implement announcement-string mapping + onChange wiring**

Edit `VoiceInk/Views/Common/MenuBarIconRenderer.swift` — extend the `MenuBarIcon` struct. Add:

```swift
extension MenuBarIcon {
    /// Returns the VoiceOver announcement string for a state transition.
    /// `.idle` and `.handsFree` return nil — `.idle` is silent (return-to-rest
    /// shouldn't speak); hands-free has its own service-level announcements.
    static func announcementString(for state: MenuBarIconRenderer.IconState) -> String? {
        switch state {
        case .idle, .handsFree: return nil
        case .arming:           return "Sotto listening"
        case .recording:        return "Sotto recording"
        case .transcribing:     return "Sotto transcribing"
        case .enhancing:        return "Sotto enhancing"
        case .committed:        return "Sotto committed"
        case .fail:             return "Sotto failed"
        }
    }

    static func announce(_ state: MenuBarIconRenderer.IconState) {
        guard let text = announcementString(for: state) else { return }
        let attributed = NSAttributedString(
            string: text,
            attributes: [.accessibilitySpeechQueueAnnouncement: true]
        )
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: attributed, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }
}
```

Then update the `MenuBarIcon` body to fire announcements on iconState change. Replace the current body's outer `Group { … }` with:

```swift
    var body: some View {
        Group {
            if Self.usePathBFallback {
                Image(
                    nsImage: MenuBarIconRenderer.image(
                        for: observer.iconState,
                        unresolvedFailures: observer.unresolvedFailures
                    )
                )
            } else {
                ZStack {
                    MenubarGlyphContainer(state: observer.iconState)
                    if observer.unresolvedFailures > 0 && observer.iconState != .fail {
                        CornerBadge(kind: .redStatic)
                    }
                }
                .frame(width: 18, height: 18)
            }
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .onChange(of: observer.iconState) { _, newState in
            Self.announce(newState)
        }
    }
```

- [ ] **Step 4: Run test — verify it passes**

Run: `xcodebuild test -scheme VoiceInk -only-testing:VoiceInkTests/MenubarGlyphTests`
Expected: all tests PASS.

- [ ] **Step 5: Manual VoiceOver smoke test**

Enable VoiceOver (`⌘F5`). Trigger a record cycle. Expect to hear each transition announced: "Sotto listening" → "Sotto recording" → "Sotto transcribing" → "Sotto enhancing" → "Sotto committed". Silence on return to idle.

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Views/Common/MenuBarIconRenderer.swift VoiceInkTests/MenubarGlyphTests.swift
git commit -m "feat(menubar): VoiceOver announcement on state transition (spec §1.X)"
```

---

## Task 6: Dark/light menubar flip — NSAppearance observation

**Spec anchor:** Appendix B.DarkLightFlip — appearance change mid-recording flips menubar tint; non-template states must not flash.

**Files:**
- Modify: `VoiceInk/Views/Common/MenubarGlyph.swift`

`Color.primary` already auto-flips. The risk is that `Canvas` snapshots stale-render across an appearance change — we need to force a refresh.

- [ ] **Step 1: Add NSAppearance observer to MenubarGlyphContainer**

Edit `VoiceInk/Views/Common/MenubarGlyph.swift` — `MenubarGlyphContainer`. Add an `@State` appearance bump that increments on `NSApplication.didChangeOcclusionStateNotification` and on `NSApp.effectiveAppearance` KVO, forcing a Canvas redraw via `.id(appearanceTick)`:

```swift
struct MenubarGlyphContainer: View {
    let state: MenuBarIconRenderer.IconState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appearanceTick: Int = 0

    var body: some View {
        contentForState
            .id(appearanceTick)   // force redraw on appearance flip
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSWindow.didChangeBackingPropertiesNotification
                )
            ) { _ in appearanceTick &+= 1 }
            .onReceive(
                DistributedNotificationCenter.default()
                    .publisher(for: Notification.Name("AppleInterfaceThemeChangedNotification"))
            ) { _ in appearanceTick &+= 1 }
    }

    @ViewBuilder
    private var contentForState: some View {
        switch state {
        case .idle:
            MenubarGlyph()
        case .arming:
            if reduceMotion {
                MenubarGlyph(alpha: 0.75)
            } else {
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let breathe = 0.55 + 0.45 * (sin(t * 2 * .pi / 1.2) + 1) / 2
                    MenubarGlyph(alpha: breathe)
                }
            }
        case .recording:
            ZStack {
                MenubarGlyph(markFilled: true)
                if reduceMotion {
                    CornerBadge(kind: .redStatic)
                } else {
                    CornerBadge(kind: .redPulse)
                }
            }
        case .transcribing:
            BouncingDots()
        case .enhancing:
            ZStack {
                MenubarGlyph(markFilled: false)
                if !reduceMotion {
                    ArcSpinner()
                }
            }
        case .committed:
            ZStack {
                MenubarGlyph()
                CornerBadge(kind: .greenStatic)
            }
        case .fail:
            FailGlyph()
        case .handsFree:
            Image(nsImage: MenuBarIconRenderer.image(for: .handsFree))
        }
    }
}
```

- [ ] **Step 2: Manual dark/light flip test**

Run: `make local`.
1. Set System Settings → Appearance → Dark. Start a recording. While recording, switch to Light mid-record.
2. Verify: menubar glyph mark flips immediately (no flash, no stale tint). Underscore stays lime in both modes. Red corner-dot stays red.
3. Reverse — switch back to Dark mid-record. Same expectations.

- [ ] **Step 3: Commit**

```bash
git add VoiceInk/Views/Common/MenubarGlyph.swift
git commit -m "feat(menubar): force redraw on appearance flip (B.DarkLightFlip)"
```

---

## Task 7: Path B fallback — static-NSImage builders + timer-snapshot loop

**ONLY execute this task if Task 0 Step 5 concluded Path A unviable.** Otherwise, skip to "Final review" below.

Path B sacrifices smooth motion for guaranteed render. Gives state-keyed icons + 8 fps timer-snapshot pulses for recording/arming/committed/fail. Transcribing/enhancing lose smooth motion entirely (becomes a static glyph variant — documented loss).

**Files:**
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift`

- [ ] **Step 1: Extend MenuBarIconRenderer with new builders**

Edit `VoiceInk/Views/Common/MenuBarIconRenderer.swift`. After the existing `private static func tinted(...)` builder, append:

```swift
    // MARK: - Path B builders
    //
    // Static-NSImage variants of the 3 new states. Driven by a Timer.publish
    // loop in MenuBarIcon when usePathBFallback == true. Lime underscore is
    // baked in via `lockFocus` + NSBezierPath fill.

    static func arming(alpha: Double) -> NSImage {
        return brandGlyph(
            markAlpha: alpha,
            cornerBadge: nil,
            failOverlay: false,
            label: "Sotto listening"
        )
    }

    static func recording(pulseAlpha: Double) -> NSImage {
        return brandGlyph(
            markAlpha: 1.0,
            markFilled: true,
            cornerBadge: (NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: pulseAlpha), 4),
            failOverlay: false,
            label: "Sotto recording"
        )
    }

    static func committed() -> NSImage {
        return brandGlyph(
            markAlpha: 1.0,
            cornerBadge: (NSColor(red: 0.188, green: 0.820, blue: 0.345, alpha: 1.0), 4),
            failOverlay: false,
            label: "Sotto committed"
        )
    }

    static func failGlyph() -> NSImage {
        return brandGlyph(
            markAlpha: 1.0,
            cornerBadge: (NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0), 4),
            failOverlay: true,
            label: "Sotto failed"
        )
    }

    /// Brand-glyph base — two-stroke mark + lime underscore. Spec §5.2 ratios.
    private static func brandGlyph(
        markAlpha: Double,
        markFilled: Bool = false,
        cornerBadge: (NSColor, CGFloat)? = nil,
        failOverlay: Bool,
        label: String
    ) -> NSImage {
        let s = pointSize
        let canvas = NSImage(size: NSSize(width: s, height: s))
        canvas.lockFocus()
        defer { canvas.unlockFocus() }

        // NSImage coordinates are bottom-origin — flip y so the layout matches
        // SwiftUI's top-origin Canvas in MenubarGlyph.
        let totalH = (0.55 + 0.08 + 0.14) * s
        let topInset = (s - totalH) / 2.0
        let markW = 0.18 * s
        let markH = 0.55 * s
        let markRect = NSRect(
            x: (s - markW) / 2.0,
            y: s - topInset - markH,   // bottom-origin flip
            width: markW,
            height: markH
        )
        let mark = NSBezierPath(roundedRect: markRect, xRadius: markW * 0.15, yRadius: markW * 0.15)
        let primary = NSColor.labelColor.withAlphaComponent(markAlpha)
        if markFilled {
            primary.setFill(); mark.fill()
        } else {
            primary.setStroke(); mark.lineWidth = 1.2; mark.stroke()
        }

        let usH = 0.14 * s
        let usY = s - topInset - markH - 0.08 * s - usH
        let usRect = NSRect(x: 0, y: usY, width: s, height: usH)
        let us = NSBezierPath(roundedRect: usRect, xRadius: usH * 0.3, yRadius: usH * 0.3)
        NSColor(red: 0.831, green: 1.0, blue: 0.227, alpha: markAlpha).setFill()
        us.fill()

        if let (color, diameter) = cornerBadge {
            let dot = NSRect(
                x: s - diameter - 1.0,
                y: s - diameter - 1.0,
                width: diameter,
                height: diameter
            )
            color.setFill()
            NSBezierPath(ovalIn: dot).fill()
        }

        if failOverlay {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .heavy),
                .foregroundColor: NSColor(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)
            ]
            let bang = NSAttributedString(string: "!", attributes: attrs)
            let bangSize = bang.size()
            bang.draw(at: NSPoint(
                x: (s - bangSize.width) / 2.0,
                y: (s - bangSize.height) / 2.0
            ))
        }

        canvas.isTemplate = false
        canvas.accessibilityDescription = label
        return canvas
    }
```

- [ ] **Step 2: Extend `image(for:)` to route new IconState cases**

Edit `VoiceInk/Views/Common/MenuBarIconRenderer.swift` — `image(for state:)` (the existing function). Add the new cases:

```swift
    static func image(for state: IconState) -> NSImage {
        switch state {
        case .idle:
            return brandGlyph(markAlpha: 1.0, cornerBadge: nil, failOverlay: false, label: "Sotto idle")
        case .arming:
            return arming(alpha: 1.0)   // pulse alpha driven by timer in Path B caller
        case .recording:
            return recording(pulseAlpha: 1.0)
        case .transcribing:
            // Path B: no smooth bouncing dots. Static three-dot SF Symbol.
            return template("ellipsis", weight: .regular, label: "Sotto transcribing")
        case .enhancing:
            // Path B: no smooth arc. Static hollow mark + sparkles.
            return template("sparkles", weight: .regular, label: "Sotto enhancing")
        case .committed:
            return committed()
        case .fail:
            return failGlyph()
        case .handsFree:
            return tinted(
                "ear.fill",
                weight: .semibold,
                color: NSColor(red: 0.831, green: 1.0, blue: 0.227, alpha: 1.0),
                label: "Sotto hands-free"
            )
        }
    }
```

> The legacy `.recording` branch previously used `Palette.accent` (tangerine). After RENAME, the lime accent is the brand color; Path B hardcodes the RGB here to avoid coupling to HUD's `Palette.brandAcid` rename ordering.

- [ ] **Step 3: Add timer-snapshot loop to MenuBarIcon under Path B**

Edit `MenuBarIcon` in the same file. Add a `TimelineView`-based pulse driver for the Path-B branch:

```swift
struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver

    var body: some View {
        Group {
            if Self.usePathBFallback {
                TimelineView(.periodic(from: .now, by: 0.125)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let pulse = 0.5 + 0.5 * sin(t * 2 * .pi)   // 1.0s pulse
                    let breathe = 0.55 + 0.45 * (sin(t * 2 * .pi / 1.2) + 1) / 2
                    Image(nsImage: pathBImage(pulse: pulse, breathe: breathe))
                }
            } else {
                ZStack {
                    MenubarGlyphContainer(state: observer.iconState)
                    if observer.unresolvedFailures > 0 && observer.iconState != .fail {
                        CornerBadge(kind: .redStatic)
                    }
                }
                .frame(width: 18, height: 18)
            }
        }
        .accessibilityLabel(Text(accessibilityLabel))
        .onChange(of: observer.iconState) { _, newState in
            Self.announce(newState)
        }
    }

    private func pathBImage(pulse: Double, breathe: Double) -> NSImage {
        switch observer.iconState {
        case .recording: return MenuBarIconRenderer.recording(pulseAlpha: pulse)
        case .arming:    return MenuBarIconRenderer.arming(alpha: breathe)
        default:
            return MenuBarIconRenderer.image(
                for: observer.iconState,
                unresolvedFailures: observer.unresolvedFailures
            )
        }
    }

    static let usePathBFallback: Bool = true   // <-- flipped only in Task 7

    // accessibilityLabel + announcementString unchanged from Task 5
}
```

- [ ] **Step 4: Document the loss in the spike handoff**

Append to `docs/superpowers/handoffs/HANDOFF_menubar_spike_2026-05-11.md`:

```markdown
### Path B losses vs Path A

- Transcribing: 3 bouncing dots → static SF Symbol "ellipsis". No motion.
- Enhancing: 270° arc spin → static SF Symbol "sparkles". No motion.
- Recording / arming: still pulse / breathe via 8fps NSImage snapshot — coarser than TimelineView but adequate.
- Underscore lime preserved in all states (drawn via NSBezierPath in brandGlyph).
- Color-blind disambiguation (committed ✓ / fail ✗) — Path B uses corner dot + center `!` only, no checkmark glyph. Acceptable per spec §1.X (fail `✗` glyph requirement applies to HUD capsule, not menubar).
```

- [ ] **Step 5: Build + smoke test**

Run: `make local`. Verify all 7 states render. Confirm pulse/breathe motion is visible (jankier than Path A — acceptable).

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Views/Common/MenuBarIconRenderer.swift docs/superpowers/handoffs/HANDOFF_menubar_spike_2026-05-11.md
git commit -m "feat(menubar): Path B fallback — static-NSImage builders + timer snapshot"
```

---

## Final review

- [ ] **Run all menubar-related tests:**

```bash
xcodebuild test -scheme VoiceInk -only-testing:VoiceInkTests/MenubarGlyphTests
```

Expected: all 8+ tests pass.

- [ ] **Run full app:** `make local`

Walk through the full state cycle (idle → arming → recording → transcribing → enhancing → committed → idle, then trigger a fail). Verify menubar icon updates within 50ms of HUD state change (spec §4 acceptance).

- [ ] **Spec acceptance checklist (§5.4 + §1.X):**

- [ ] App renamed to Sotto — verified by RENAME pair, not MENUBAR.
- [ ] Menubar icon: `MenubarGlyph` SwiftUI view in `MenuBarExtra` label closure. One view, one binding, animates via `TimelineView`. ✓ Task 4 (or Path B per Task 7).
- [ ] Per §4.2 state table — 7 states render correctly with correct color, motion (or Reduce Motion fallback), and corner badges. ✓ Tasks 3, 6.
- [ ] §1.X menubar accessibility — `accessibilityLabel` per state + `AccessibilityNotification.announcement(...)` on transition. ✓ Task 5.
- [ ] §1.X Reduce Motion fallback — opacity-only fades, motion suppressed. ✓ Task 3 Step 5 / Task 6 Step 1.
- [ ] §5.3 size+tint contract — non-template at all menubar sizes; mark `.primary` auto-flips; underscore stays `brandAcid`. ✓ Task 1.
- [ ] §5.2 proportions — mark 0.18S × 0.55S, underscore 1.00S × 0.14S, gap 0.08S. ✓ Task 1 Step 3 (with test).
- [ ] B.MenubarSpike resolved + documented. ✓ Task 0.
- [ ] B.DarkLightFlip resolved — appearance change mid-recording does not flash. ✓ Task 6.
- [ ] Updates within 50ms of HaloPhase change. ✓ Task 2 (Combine pipeline on main queue, removeDuplicates).

- [ ] **Open PR**

Use `gh pr create` per CLAUDE.md PR guidelines. Body must reference this plan and the spec.

---

## Out of scope (do not touch)

- `VoiceInk/Views/MenuBarView.swift` — dropdown contents. SETTINGS / HUD adjacent, not MENUBAR.
- `VoiceInk/Assets.xcassets/menuBarIcon.imageset/` — ICON pair owns asset regeneration (only needed for Path B if it ships; ICON tracks the dependency).
- `VoiceInk/Views/Recorder/NotchRecorderPanel.swift` and `HaloMaterial.swift` — HUD pair territory. MENUBAR only reads `HaloPhase`; does not extend `HaloPhase` cases.
- Bundle ID, Sparkle feed, CloudKit, Keychain access group, OSLog subsystems — RENAME pair.
- `Palette` rename (`accent` → `brandAcid`) — HUD pair. MENUBAR uses `Palette.brandAcid` (or local fallback constant if HUD has not yet landed; see Task 1 Step 3 note).
