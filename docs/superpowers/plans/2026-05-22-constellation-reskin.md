# Floating Recorder Re-skin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the floating (Constellation) recorder's chip cluster to Bay's visual language — onyx tactical glass, phase-keyed accents, an anchor-only phase halo — without touching its layout or state logic.

**Architecture:** A new recorder-specific `recorderChip(phase:)` modifier wraps each cluster chip in `TacticalGlass`/`HaloMaterial` (the app-wide onyx glass Bay uses) instead of the shared flat `GlassChip` primitive. The chip factories pass a `ClusterPhase`-derived `HaloPhase`: the anchor chip gets the live phase (it glows), secondary/action chips get `.hidden`. Legacy tangerine accents become phase-keyed; the manual `ChipBreath` modifier is retired in favor of `HaloMaterial`'s `breathePulse`.

**Tech Stack:** Swift, SwiftUI, AppKit. Project: `Sotto.xcodeproj`, scheme `Sotto`. Test target `SottoTests` (XCTest).

**Spec:** `docs/superpowers/specs/2026-05-22-constellation-reskin-design.md`
**Branch:** `feat/constellation-reskin` (already created, off `main`).

---

## Conventions

**Build gate** (run from repo root; success = exit 0 and no `error:` lines — `-quiet` does NOT print `** BUILD SUCCEEDED **`):

```bash
xcodebuild build -scheme Sotto -project Sotto.xcodeproj -configuration Debug \
  -derivedDataPath .local-build -skipMacroValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet
```

**Test-target compile check** — the repo's `xcodebuild test` launcher is documented-broken ("Test crashed with signal trap before establishing connection"). Confirm the test target *compiles* by swapping `build` → `build-for-testing`. If the launcher does run, the `RecorderChipGlassTests` must be green; if it crashes on launch, report that — do not silently skip.

**Daily-driver build + install** (`/Applications/Sotto.app`): `make local`.

`Sotto.xcodeproj` uses synced file groups — files added under `VoiceInk/` and `VoiceInkTests/` are picked up automatically; the build gate confirms it.

---

## File Structure

**Create:**
- `VoiceInk/Views/Recorder/Constellation/RecorderChipGlass.swift` — the `ClusterPhase → HaloPhase` mapping + the `recorderChip(phase:)` glass modifier.
- `VoiceInkTests/RecorderChipGlassTests.swift` — unit tests for the pure mapping.

**Modify:**
- `VoiceInk/Views/Recorder/Constellation/ClusterChips.swift` — swap the 6 chip views from `.glassChip()` to `.recorderChip(phase:)`; phase-key the accents; thread `haloPhase`; drop `.chipBreath()`.
- `VoiceInk/Views/Recorder/Constellation/ClusterMotion.swift` — recolor `RingPulseDot`'s ring; remove the `ChipBreath` modifier.

**Untouched:** `GlassChip.swift` (shared primitive), `ChipPanel.swift`, `ConstellationCluster.swift`, `ConstellationContainer.swift`, `ClusterPhase.swift`, all of `Bay/`, the window managers.

---

## Task 1: `ClusterPhase → HaloPhase` mapping + `recorderChip` glass modifier

Create the new recorder chip glass. The `HaloPhase(clusterPhase:)` mapping is a pure function (TDD); the `recorderChip` modifier is visual (build-verified).

**Files:**
- Create: `VoiceInk/Views/Recorder/Constellation/RecorderChipGlass.swift`
- Test: `VoiceInkTests/RecorderChipGlassTests.swift`

- [ ] **Step 1: Write the failing test**

Create `VoiceInkTests/RecorderChipGlassTests.swift`:

```swift
import XCTest
@testable import Sotto

final class RecorderChipGlassTests: XCTestCase {
    // ClusterPhase → HaloPhase mapping (drives recorderChip glass + halo color).

    func test_haloPhase_idle_isHidden() {
        XCTAssertEqual(HaloPhase(clusterPhase: .idle), .hidden)
    }

    func test_haloPhase_recording() {
        XCTAssertEqual(HaloPhase(clusterPhase: .recording), .recording)
    }

    func test_haloPhase_transcribing() {
        XCTAssertEqual(HaloPhase(clusterPhase: .transcribing), .transcribing)
    }

    func test_haloPhase_enhancing() {
        XCTAssertEqual(HaloPhase(clusterPhase: .enhancing), .enhancing)
    }

    func test_haloPhase_done_ignoresPayload() {
        XCTAssertEqual(HaloPhase(clusterPhase: .done(appName: "Notes", preview: "hi")), .done)
    }

    func test_haloPhase_failed_ignoresReason() {
        XCTAssertEqual(HaloPhase(clusterPhase: .failed(reason: "No speech detected")), .failed)
    }
}
```

- [ ] **Step 2: Run the test — verify it fails**

Run the test-target compile check (`build-for-testing`). Expected: FAIL — `extra argument 'clusterPhase'` / no `HaloPhase` initializer taking `clusterPhase`.

- [ ] **Step 3: Create `RecorderChipGlass.swift`**

Create `VoiceInk/Views/Recorder/Constellation/RecorderChipGlass.swift`:

```swift
import SwiftUI

// MARK: - ClusterPhase → HaloPhase

extension HaloPhase {
    /// Maps the cluster-side `ClusterPhase` to the view-side `HaloPhase` that
    /// drives `recorderChip` glass + halo color. The chip cluster never enters
    /// `.armed` or `.liveText`, so those `HaloPhase` cases are unreachable here.
    init(clusterPhase: ClusterPhase) {
        switch clusterPhase {
        case .idle:         self = .hidden
        case .recording:    self = .recording
        case .transcribing: self = .transcribing
        case .enhancing:    self = .enhancing
        case .done:         self = .done
        case .failed:       self = .failed
        }
    }
}

// MARK: - RecorderChipGlass
//
// Onyx tactical-glass background for the floating-recorder cluster chips —
// the Constellation equivalent of Bay's capsule material. Built on
// `TacticalGlass` / `HaloMaterial` (the app-wide onyx glass), NOT the shared
// flat `GlassChip` primitive — so the recorder carries phase-keyed halos
// without restyling the Settings / History / Metrics chips that also use
// `GlassChip`.
//
// `phase` drives the outer halo: pass the cluster's live `HaloPhase` for the
// anchor chip (it glows), `.hidden` for secondary / action chips (onyx glass,
// no glow). On `.enhancing` the modifier drives `HaloMaterial`'s breathePulse
// so the anchor's violet halo breathes — replacing the retired `ChipBreath`.

struct RecorderChipGlass: ViewModifier {
    let phase: HaloPhase

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breatheUp = false

    private static let cornerRadius: CGFloat = 10
    private static let paddingH: CGFloat = 11
    private static let paddingV: CGFloat = 7

    func body(content: Content) -> some View {
        let isEnhancing = (phase == .enhancing)
        let pulse: Double = {
            guard isEnhancing else { return 0 }
            if reduceMotion { return 0.5 }      // static mid-amplitude
            return breatheUp ? 1.0 : 0.0
        }()

        content
            .padding(.horizontal, Self.paddingH)
            .padding(.vertical, Self.paddingV)
            .background(
                TacticalGlass<RoundedRectangle>(
                    shape: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous),
                    phase: phase,
                    breathePulse: pulse,
                    showInnerSheen: isEnhancing
                )
            )
            .onAppear { startBreathe() }
            .onChange(of: reduceMotion) { _, _ in startBreathe() }
    }

    /// Drives the repeating breathe for the enhancing anchor. Resets to rest
    /// for every other phase and under Reduce Motion.
    private func startBreathe() {
        guard phase == .enhancing, !reduceMotion else {
            breatheUp = false
            return
        }
        breatheUp = false
        withAnimation(.chipBreath) { breatheUp = true }
    }
}

extension View {
    /// Wraps a floating-recorder cluster chip in onyx tactical glass.
    /// Pass the cluster's live `HaloPhase` for the anchor chip; `.hidden`
    /// for secondary / action chips.
    func recorderChip(phase: HaloPhase) -> some View {
        modifier(RecorderChipGlass(phase: phase))
    }
}
```

- [ ] **Step 4: Run the test — verify it passes**

Run the build gate, then the test-target compile check. Expected: both exit 0, no `error:` lines. If the test launcher runs, all 6 `RecorderChipGlassTests` are green.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Views/Recorder/Constellation/RecorderChipGlass.swift VoiceInkTests/RecorderChipGlassTests.swift
git commit -m "feat(recorder): add recorderChip onyx glass + ClusterPhase->HaloPhase map

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: Re-skin the cluster chips — `ClusterChips.swift`

Swap the 6 chip views to `recorderChip`, thread the `HaloPhase` to the anchor chips, phase-key the accent colors, and drop the `.chipBreath()` call.

**Files:**
- Modify: `VoiceInk/Views/Recorder/Constellation/ClusterChips.swift`

- [ ] **Step 1: Thread `haloPhase` through the `chips(phase:)` entry point**

In the `chips(...)` function, the `switch phase` dispatches to the per-state factories. Add a `haloPhase` derived once and pass it to each factory. Replace the `switch phase { ... }` body with:

```swift
        let haloPhase = HaloPhase(clusterPhase: phase)
        switch phase {
        case .idle:
            return []
        case .recording:
            return recordingChips(
                startedAt: recordingStartedAt,
                audioLevel: audioLevel,
                promptIcon: promptIcon,
                promptName: promptName,
                haloPhase: haloPhase
            )
        case .transcribing:
            return transcribingChips(modelLabel: transcriptionModelLabel, haloPhase: haloPhase)
        case .enhancing:
            return enhancingChips(
                promptIcon: promptIcon,
                promptName: promptName,
                providerLabel: enhancementProviderLabel,
                haloPhase: haloPhase
            )
        case .done(let appName, _):
            return doneChips(appName: appName)
        case .failed(let reason):
            return failedChips(
                reason: reason,
                onRetry: onRetry,
                onOpenSettings: onOpenSettings,
                haloPhase: haloPhase
            )
        }
```

- [ ] **Step 2: `recordingChips` — signature + red dot + halo**

Change the `recordingChips` signature line from:

```swift
    private static func recordingChips(
        startedAt: Date?,
        audioLevel: Float,
        promptIcon: String?,
        promptName: String?
    ) -> [ChipDescriptor] {
```

to (add `haloPhase`):

```swift
    private static func recordingChips(
        startedAt: Date?,
        audioLevel: Float,
        promptIcon: String?,
        promptName: String?,
        haloPhase: HaloPhase
    ) -> [ChipDescriptor] {
```

Then replace the `AnchorChip(...)` call in `recordingChips`:

```swift
                AnchorChip(
                    label: "REC",
                    dotColor: Palette.accent,
                    rate: .fast,
                    trailing: AnyView(MeterBars(level: audioLevel))
                )
```

with:

```swift
                AnchorChip(
                    label: "REC",
                    dotColor: haloPhase.glowColor,
                    rate: .fast,
                    haloPhase: haloPhase,
                    trailing: AnyView(MeterBars(level: audioLevel))
                )
```

- [ ] **Step 3: `transcribingChips` — signature + halo**

Change the `transcribingChips` signature from:

```swift
    private static func transcribingChips(modelLabel: String?) -> [ChipDescriptor] {
```

to:

```swift
    private static func transcribingChips(modelLabel: String?, haloPhase: HaloPhase) -> [ChipDescriptor] {
```

Then replace its `AnchorChip(...)` call:

```swift
                AnchorChip(
                    label: "TRANSCRIBING",
                    dotColor: Palette.onyxFg.opacity(0.85),
                    rate: .none
                )
                .chipShimmer(active: true)
```

with (the neutral dot stays — cyan reads from the halo):

```swift
                AnchorChip(
                    label: "TRANSCRIBING",
                    dotColor: Palette.onyxFg.opacity(0.85),
                    rate: .none,
                    haloPhase: haloPhase
                )
                .chipShimmer(active: true)
```

- [ ] **Step 4: `enhancingChips` — signature + violet dot + halo, drop `.chipBreath()`**

Change the `enhancingChips` signature from:

```swift
    private static func enhancingChips(
        promptIcon: String?,
        promptName: String?,
        providerLabel: String?
    ) -> [ChipDescriptor] {
```

to:

```swift
    private static func enhancingChips(
        promptIcon: String?,
        promptName: String?,
        providerLabel: String?,
        haloPhase: HaloPhase
    ) -> [ChipDescriptor] {
```

Then replace its `AnchorChip(...)` call:

```swift
                AnchorChip(
                    label: "ENHANCING",
                    dotColor: Palette.accent,
                    rate: .slow
                )
                .chipBreath(active: true)
```

with (violet dot, halo, and the manual `.chipBreath()` removed — the breathe is now carried by `recorderChip`):

```swift
                AnchorChip(
                    label: "ENHANCING",
                    dotColor: haloPhase.glowColor,
                    rate: .slow,
                    haloPhase: haloPhase
                )
```

- [ ] **Step 5: `failedChips` — signature + red dot + halo**

Change the `failedChips` signature from:

```swift
    private static func failedChips(
        reason: String?,
        onRetry: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> [ChipDescriptor] {
```

to:

```swift
    private static func failedChips(
        reason: String?,
        onRetry: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        haloPhase: HaloPhase
    ) -> [ChipDescriptor] {
```

Then replace its `AnchorChip(...)` call:

```swift
                AnchorChip(
                    label: "FAIL",
                    dotColor: Palette.accent,
                    rate: .fast
                )
```

with:

```swift
                AnchorChip(
                    label: "FAIL",
                    dotColor: haloPhase.glowColor,
                    rate: .fast,
                    haloPhase: haloPhase
                )
```

- [ ] **Step 6: `AnchorChip` — add `haloPhase`, swap to `recorderChip`**

Replace the entire `AnchorChip` struct with:

```swift
private struct AnchorChip: View {
    let label: String
    let dotColor: Color
    let rate: RingPulseRate
    let haloPhase: HaloPhase
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 6) {
            RingPulseDot(color: dotColor, rate: rate)
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
            if let trailing {
                trailing
            }
        }
        .recorderChip(phase: haloPhase)
    }
}
```

- [ ] **Step 7: `DoneAnchorChip` — green checkmark + `recorderChip(.done)`**

Replace the entire `DoneAnchorChip` struct with:

```swift
private struct DoneAnchorChip: View {
    let appName: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HaloPhase.done.glowColor)
            Text("PASTED")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .tracking(0.06 * 10.5)
                .foregroundStyle(Palette.onyxFg)
            Text("\u{2192}")
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(Palette.onyxMute)
            Text(appName)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Palette.onyxFg)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .recorderChip(phase: .done)
    }
}
```

- [ ] **Step 8: `MeterBars` — acid-lime bars**

Replace the entire `MeterBars` struct with:

```swift
private struct MeterBars: View {
    let level: Float

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<4, id: \.self) { i in
                let threshold = Float(i + 1) / 4.0
                Capsule()
                    .fill(level >= threshold ? Palette.brandAcid : Palette.brandAcid.opacity(0.30))
                    .frame(width: 1.5, height: CGFloat(3 + i))
            }
        }
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 9: Secondary / action chips — swap to `recorderChip(phase: .hidden)`**

Three single-line swaps (the secondary and action chip views never glow). In `KeyValueChip.body`, `TimeChip.body`, `ReasonChip.body`, and `ActionChip.body`, replace each `.glassChip()` with `.recorderChip(phase: .hidden)`. There are exactly four occurrences left after Steps 6–7 — confirm with:

```bash
grep -n "glassChip" VoiceInk/Views/Recorder/Constellation/ClusterChips.swift
```

Expected before this step: 4 lines (`KeyValueChip`, `TimeChip`, `ReasonChip`, `ActionChip`). Replace all four `.glassChip()` → `.recorderChip(phase: .hidden)`. Expected after: the grep returns nothing.

- [ ] **Step 10: Build gate**

Run the build gate. Expected: exit 0, no `error:` lines. `ChipBreath` is now unreferenced — an unused-code warning is expected and is removed in Task 3. Common failure: a missed `.glassChip()` — Step 9's grep must be clean.

- [ ] **Step 11: Commit**

```bash
git add VoiceInk/Views/Recorder/Constellation/ClusterChips.swift
git commit -m "feat(recorder): re-skin cluster chips to onyx glass + phase-keyed accents

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Recolor `RingPulseDot`, retire `ChipBreath` — `ClusterMotion.swift`

**Files:**
- Modify: `VoiceInk/Views/Recorder/Constellation/ClusterMotion.swift`

- [ ] **Step 1: Recolor the `RingPulseDot` ring to the phase color**

In `RingPulseDot.body`, replace:

```swift
            Circle()
                .stroke(Palette.accentGlow, lineWidth: 1)
                .frame(width: ringDiameter, height: ringDiameter)
```

with (the ring matches the dot's own phase color instead of the legacy tangerine glow):

```swift
            Circle()
                .stroke(color.opacity(0.55), lineWidth: 1)
                .frame(width: ringDiameter, height: ringDiameter)
```

- [ ] **Step 2: Remove the `ChipBreath` modifier**

Delete the entire `// MARK: - ChipBreath` block — the comment block and the `struct ChipBreath: ViewModifier { ... }` (everything from the `// MARK: - ChipBreath` line through the closing `}` of `struct ChipBreath`).

Then in the `extension View` at the bottom of the file, delete the `chipBreath` function so the extension reads exactly:

```swift
extension View {
    func chipShimmer(active: Bool) -> some View {
        modifier(ChipShimmer(active: active))
    }
}
```

Leave `Animation.chipBreath` (the `static let chipBreath` in the `extension Animation`) — `RecorderChipGlass` uses it to drive the enhancing breathe.

- [ ] **Step 3: Verify no stale references**

Run:

```bash
grep -rn "ChipBreath\|chipBreath(" VoiceInk --include='*.swift'
```

Expected: only `Animation.chipBreath` references — its definition in `ClusterMotion.swift` and its use in `RecorderChipGlass.swift`. No `struct ChipBreath`, no `.chipBreath(active:)` call sites.

- [ ] **Step 4: Build gate**

Run the build gate. Expected: exit 0, no `error:` lines, and the unused-`ChipBreath` warning from Task 2 is gone.

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Views/Recorder/Constellation/ClusterMotion.swift
git commit -m "feat(recorder): phase-color the ring pulse, retire ChipBreath

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: Verify success criteria

Build the daily-driver app and confirm the spec's success criteria. No code unless a check fails.

**Files:**
- Possibly modify: `VoiceInk/Views/Recorder/Constellation/*` (only if a visual check fails)

- [ ] **Step 1: Build and install**

```bash
make local
```

Expected: `** BUILD SUCCEEDED **`, `/Applications/Sotto.app` updated.

- [ ] **Step 2: Select the floating recorder**

Quit any running Sotto, `open -a Sotto`. In Settings, set the recorder style to **"Halo (Floating)"** (this is the default, so it may already be selected).

- [ ] **Step 3: Verify the re-skin across the full phase cycle**

Trigger a dictation, speak briefly, stop, and let it run through to paste — watch the cluster transition **recording → transcribing → enhancing → committed**. Then force a failure (stop with no speech, or a provider error) for the **failed** phase. Confirm per phase:

| Phase | Anchor halo | Anchor accent | Watch for |
|---|---|---|---|
| recording | red | red REC dot + **acid-lime** meter bars | — |
| transcribing | cyan | neutral dot | shimmer intact |
| enhancing | violet, **breathing** | violet dot | breathe is smooth — **no reset / jitter** on the transcribing→enhancing entry or the enhancing→committed exit |
| committed | green | green checkmark | — |
| failed | red | red FAIL dot | — |

Across all phases also confirm: chips render onyx tactical glass (near-black, hairline border, top gloss) — not the old flat translucent-gray; secondary chips (TIME, MODEL, PROMPT, reason) and action chips (RETRY, OPEN SETTINGS) show the glass but carry **no glow**; no tangerine anywhere in the cluster.

Then set the recorder style to **Notch** in Settings and run one Bay cycle — the floating recorder's glass and phase colors should read as the same visual language as Bay (side-by-side parity check).

- [ ] **Step 4: Verify accessibility fallbacks**

- System Settings → Accessibility → Display → **Reduce Motion** on: re-run a cycle — the ring pulse and the enhancing breathe go static; the recorder still renders correctly.
- **Increase Contrast** on: the chip glass becomes opaque and the halo is replaced by a solid accent stroke (inherited from `HaloMaterial`). Confirm the cluster stays legible.

- [ ] **Step 5: Commit any fix**

If a check failed and you adjusted a `Constellation/*` file, rebuild (`make local`), re-verify, then:

```bash
git add VoiceInk/Views/Recorder/Constellation/
git commit -m "fix(recorder): adjust re-skin from visual verification

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

If every check passed first time, there is nothing to commit — skip.

---

## Self-review notes

- **Spec coverage:** §1 recorder chip glass → Task 1 (`recorderChip` modifier) + Task 2 (6 call-site swaps). §2 phase-keyed accents → Task 1 (`HaloPhase(clusterPhase:)`) + Task 2 (anchor dot colors + `DoneAnchorChip` checkmark derive from `HaloPhase.glowColor` — single source of truth, no scattered hardcodes; `MeterBars` → brand lime) + Task 3 (`RingPulseDot` ring → the dot's own color). §3 anchor-only halo → Task 2 (anchors pass the live `haloPhase`; secondary/action chips pass `.hidden`). §4 motion → Task 3 (`RingPulseDot` recolor, `ChipBreath` removed) + Task 1 (`recorderChip` drives `breathePulse` for enhancing). §5 files → Tasks 1–3 match the spec's file table. Success criteria → Task 4.
- **Type consistency:** `HaloPhase(clusterPhase:)`, `recorderChip(phase:)`, `RecorderChipGlass`, `AnchorChip(label:dotColor:rate:haloPhase:trailing:)`, the four factory signatures gaining `haloPhase: HaloPhase`, `RingPulseDot(color:rate:)` (signature unchanged — only its ring color expression changes) — referenced consistently across Tasks 1–3.
- **Build never breaks mid-plan:** after Task 1 the new file compiles unused; after Task 2 `ClusterChips` uses `recorderChip` and no longer calls `.chipBreath()` (`ChipBreath` still exists → unused-warning only); after Task 3 `ChipBreath` is removed with zero references. Each task is independently green.
- **`ChipDescriptor.Motion.breath`** stays on the `enh-anchor` descriptor — it is inert metadata (`ChipPanel` does not act on `motion`), and `ChipPanel.swift` is out of scope per the spec.

## Unresolved questions

None — the design spec is approved.
