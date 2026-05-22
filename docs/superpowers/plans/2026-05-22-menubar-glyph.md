# Menu Bar Static Brand Glyph — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the generic SF-Symbol menu bar icons with the static Sotto brand glyph (vertical mark + lime underscore), drawn per state as a non-template `NSImage`.

**Architecture:** `MenuBarIcon` stays a plain `Image(nsImage:)` keyed on `iconState` — that static-image structure is what avoids the `MenuBarExtra` rasterisation hang and does not change. Only the image *content* changes: `MenuBarIconRenderer` is rewritten to draw the brand glyph via `NSBezierPath`/`lockFocus` instead of SF Symbols. The unmountable SwiftUI animation file `MenubarGlyph.swift` is deleted.

**Tech Stack:** Swift, AppKit (`NSImage.lockFocus`, `NSBezierPath`, `NSAppearance`), SwiftUI (`MenuBarExtra` label). Project: `Sotto.xcodeproj`, scheme `Sotto`. Test target `SottoTests` (XCTest).

**Spec:** `docs/superpowers/specs/2026-05-22-menubar-glyph-design.md`
**Branch:** `feat/menubar-glyph` (already created, off `main`).

---

## Conventions

**Build gate** (run from repo root; success = exit 0 and no `error:` lines — `xcodebuild` with `-quiet` does NOT print `** BUILD SUCCEEDED **`):

```bash
xcodebuild build -scheme Sotto -project Sotto.xcodeproj -configuration Debug \
  -derivedDataPath .local-build -skipMacroValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet
```

**Test-target compile check** (the repo's `xcodebuild test` launcher is documented-broken — "Test crashed with signal trap before establishing connection". Confirm the test target *compiles* by swapping `build` → `build-for-testing`. If the launcher does run, all `MenuBarIconTests` must be green; if it crashes on launch, report that — do not silently skip):

```bash
xcodebuild build-for-testing -scheme Sotto -project Sotto.xcodeproj -configuration Debug \
  -derivedDataPath .local-build -skipMacroValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet
```

**Daily-driver build + install** (`/Applications/Sotto.app`): `make local` — this one is not `-quiet` and does print `** BUILD SUCCEEDED **`.

`Sotto.xcodeproj` uses synced file groups, so files added/removed under `VoiceInk/` and `VoiceInkTests/` are picked up automatically; the build gate confirms it. If a build fails referencing a deleted file, a stale project reference exists — remove it from `Sotto.xcodeproj`.

---

## File Structure

**Modify:**
- `VoiceInk/Views/Common/MenuBarIconRenderer.swift` — gains `accessibilityLabel(for:)`; `image(for:)` rewritten to draw the brand glyph; new `brandGlyph(...)` builder; `MenuBarIcon` updated.

**Delete:**
- `VoiceInk/Views/Common/MenubarGlyph.swift` — the entire SwiftUI animation system (`MenubarGlyph`, `BouncingDots`, `ArcSpinner`, `CornerBadge`, `FailGlyph`, `MenubarGlyphContainer`). Every view in it is `TimelineView`-driven and unmountable.

**Rename:**
- `VoiceInkTests/MenubarGlyphTests.swift` → `VoiceInkTests/MenuBarIconTests.swift` — `MenubarGlyph` no longer exists; the file tests `MenuBarIconRenderer`.

---

## Task 1: Move `accessibilityLabel`, delete `MenubarGlyph.swift`, rename tests

A pure refactor — no behavior change. The menu bar still shows SF Symbols after this task; it only relocates `accessibilityLabel(for:)` off the deleted file and removes the dead SwiftUI code. Done first so the build never references a half-deleted symbol.

**Files:**
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift`
- Delete: `VoiceInk/Views/Common/MenubarGlyph.swift`
- Rename: `VoiceInkTests/MenubarGlyphTests.swift` → `VoiceInkTests/MenuBarIconTests.swift`

- [ ] **Step 1: Verify nothing external references the soon-to-be-deleted types**

Run:

```bash
grep -rn "MenubarGlyph\|MenubarGlyphContainer\|BouncingDots\|ArcSpinner\|\bCornerBadge\b\|FailGlyph" \
  VoiceInk/ VoiceInkTests/ --include=*.swift | grep -v "Views/Common/MenubarGlyph.swift"
```

Expected — ONLY these references (all to `MenubarGlyph.accessibilityLabel`):
- `VoiceInk/Views/Common/MenuBarIconRenderer.swift` — 2 lines
- `VoiceInkTests/MenubarGlyphTests.swift` — 8 lines

If any *other* file or any reference to `MenubarGlyphContainer` / `BouncingDots` / `ArcSpinner` / `CornerBadge` / `FailGlyph` appears, STOP — the deletion is not safe; report it.

- [ ] **Step 2: Add `accessibilityLabel(for:)` to `MenuBarIconRenderer`**

In `VoiceInk/Views/Common/MenuBarIconRenderer.swift`, insert this function immediately after the closing `}` of the `IconState` enum and before `static func image(for state: IconState) -> NSImage`:

```swift
    /// VoiceOver label per state. Pure logic, exhaustive over `IconState` —
    /// adding a case is a compile error here. `MenuBarIcon` composes this with
    /// the unresolved-failure suffix at the view layer.
    static func accessibilityLabel(for state: IconState) -> String {
        switch state {
        case .idle:         return "Sotto idle"
        case .arming:       return "Sotto listening"
        case .recording:    return "Sotto recording"
        case .transcribing: return "Sotto transcribing"
        case .enhancing:    return "Sotto enhancing"
        case .committed:    return "Sotto committed"
        case .fail:         return "Sotto failed"
        case .handsFree:    return "Sotto hands-free"
        }
    }
```

- [ ] **Step 3: Update the two internal references in `MenuBarIconRenderer.swift`**

In `failedAccessibilityLabel(for:count:)`, replace:

```swift
        return "\(MenubarGlyph.accessibilityLabel(for: state)), \(suffix)"
```

with:

```swift
        return "\(accessibilityLabel(for: state)), \(suffix)"
```

In the `MenuBarIcon` struct's `accessibilityLabel` computed property, replace:

```swift
        let base = MenubarGlyph.accessibilityLabel(for: observer.iconState)
```

with:

```swift
        let base = MenuBarIconRenderer.accessibilityLabel(for: observer.iconState)
```

- [ ] **Step 4: Delete `MenubarGlyph.swift`**

```bash
git rm VoiceInk/Views/Common/MenubarGlyph.swift
```

- [ ] **Step 5: Rename the test file and update its references**

```bash
git mv VoiceInkTests/MenubarGlyphTests.swift VoiceInkTests/MenuBarIconTests.swift
```

Then in `VoiceInkTests/MenuBarIconTests.swift`:
- Rename the class: `final class MenubarGlyphTests: XCTestCase` → `final class MenuBarIconTests: XCTestCase`.
- Replace every occurrence (8) of `MenubarGlyph.accessibilityLabel(for:` with `MenuBarIconRenderer.accessibilityLabel(for:`.

No other change — the 11 `IconState`-mapping / combined-init tests are untouched.

- [ ] **Step 6: Build gate + test-target compile**

Run the **build gate** — expected: exit 0, no `error:` lines.
Run the **test-target compile check** (`build-for-testing`) — expected: exit 0, no `error:` lines. If the test launcher is attempted and crashes on launch, that is the documented-broken launcher — note it and continue.

- [ ] **Step 7: Commit**

```bash
git add VoiceInk/Views/Common/MenuBarIconRenderer.swift VoiceInk/Views/Common/MenubarGlyph.swift VoiceInkTests/MenubarGlyphTests.swift VoiceInkTests/MenuBarIconTests.swift
git commit -m "refactor(menubar): move accessibilityLabel to renderer, drop dead SwiftUI glyph

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: Rewrite `MenuBarIconRenderer` to draw the brand glyph

Replace the SF-Symbol builders with a pixel-snapped `NSBezierPath` brand-glyph builder, route every state through it, resolve the label-colored mark against the menu bar's effective appearance so it stays legible in light, dark, and high-contrast.

**Files:**
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift`
- Modify: `VoiceInkTests/MenuBarIconTests.swift`

- [ ] **Step 1: Refresh the stale file-header comment**

In `VoiceInk/Views/Common/MenuBarIconRenderer.swift`, replace the header comment block (the `// MARK: - MenuBarIconRenderer` block down to just before `enum MenuBarIconRenderer {`) with:

```swift
// MARK: - MenuBarIconRenderer
//
// Programmatic NSImage builders for the menu bar status icon. Every state
// renders the Sotto brand glyph (vertical mark + full-width lime underscore)
// at 18×18pt as a static, non-template NSImage — static because a SwiftUI /
// TimelineView label re-rasterises every frame inside MenuBarExtra and pins
// the main thread (see commit history). State is carried by mark color and a
// 4pt corner dot; see `image(for:unresolvedFailures:)`.
```

- [ ] **Step 2: Replace the icon-building region**

In `MenuBarIconRenderer.swift`, replace everything from the line `static func image(for state: IconState) -> NSImage {` down to and including the closing `}` of `tinted(...)` — i.e. the whole region between `accessibilityLabel(for:)` (added in Task 1) and the enum's final `}` — with this complete block:

```swift
    // MARK: - Public icon

    /// The menu bar icon for `state`. The brand glyph is non-template, so macOS
    /// will not auto-tint the label-colored mark — its color is resolved here
    /// against `NSApp.effectiveAppearance` (covers light / dark / high-contrast).
    /// `unresolvedFailures > 0` stamps a red corner dot on top.
    static func image(for state: IconState, unresolvedFailures: Int) -> NSImage {
        var markColor = NSColor.labelColor
        NSApp.effectiveAppearance.performAsCurrentDrawingAppearance {
            markColor = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
        }
        let base = glyphImage(for: state, markColor: markColor)
        guard unresolvedFailures > 0 else { return base }
        return stampingFailureDot(
            on: base,
            label: failedAccessibilityLabel(for: state, count: unresolvedFailures)
        )
    }

    /// Per-state brand glyph, no failure overlay. `markColor` is the already-
    /// resolved color for the label-colored states.
    private static func glyphImage(for state: IconState, markColor: NSColor) -> NSImage {
        let label = accessibilityLabel(for: state)
        switch state {
        case .idle:
            return brandGlyph(center: .mark(markColor), cornerDot: nil, label: label)
        case .arming, .transcribing, .enhancing:
            return brandGlyph(center: .mark(markColor),
                              cornerDot: NSColor(Palette.brandAcid), label: label)
        case .recording:
            return brandGlyph(center: .mark(NSColor(Palette.recRed)),
                              cornerDot: nil, label: label)
        case .committed:
            return brandGlyph(center: .mark(markColor),
                              cornerDot: NSColor(Palette.commitGreen), label: label)
        case .fail:
            return brandGlyph(center: .failBang, cornerDot: nil, label: label)
        case .handsFree:
            return tinted("ear.fill", weight: .semibold,
                          color: NSColor(Palette.brandAcid), label: label)
        }
    }

    private static func failedAccessibilityLabel(for state: IconState, count: Int) -> String {
        let suffix = count == 1 ? "1 unresolved failure" : "\(count) unresolved failures"
        return "\(accessibilityLabel(for: state)), \(suffix)"
    }

    // MARK: - Brand-glyph builder

    /// What occupies the center band of the glyph.
    private enum GlyphCenter {
        case mark(NSColor)   // vertical brand bar in the given color
        case failBang        // red "!" drawn in place of the mark
    }

    /// Draws the Sotto brand glyph — vertical mark + full-width lime underscore
    /// — as an 18×18pt non-template NSImage. Non-template because the lime
    /// underscore is a brand color macOS must not tint away. Spec §5.2
    /// proportions, rounded to whole points so every edge is pixel-aligned.
    private static func brandGlyph(center: GlyphCenter, cornerDot: NSColor?, label: String) -> NSImage {
        let s = pointSize

        // Spec §5.2 proportions, rounded to whole points at the 18pt render
        // size so every edge is pixel-aligned (crisp at 1x and 2x).
        let markW = (0.18 * s).rounded()
        let markH = (0.55 * s).rounded()
        let underscoreH = (0.14 * s).rounded()
        let gap = (0.08 * s).rounded()
        let totalH = markH + gap + underscoreH
        let bottomInset = ((s - totalH) / 2.0).rounded()

        let canvas = NSImage(size: NSSize(width: s, height: s))
        canvas.lockFocus()

        // NSImage is bottom-origin: y is measured up from the bottom edge.
        // Underscore — full width, base of the stack.
        let underscoreRect = NSRect(x: 0, y: bottomInset, width: s, height: underscoreH)
        NSColor(Palette.brandAcid).setFill()
        NSBezierPath(roundedRect: underscoreRect,
                     xRadius: underscoreH * 0.3, yRadius: underscoreH * 0.3).fill()

        // Center band — mark or fail "!".
        let bandBottom = bottomInset + underscoreH + gap
        switch center {
        case .mark(let color):
            let markRect = NSRect(x: ((s - markW) / 2.0).rounded(), y: bandBottom,
                                  width: markW, height: markH)
            color.setFill()
            NSBezierPath(roundedRect: markRect,
                         xRadius: markW * 0.15, yRadius: markW * 0.15).fill()
        case .failBang:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .heavy),
                .foregroundColor: NSColor(Palette.recRed),
            ]
            let bang = NSAttributedString(string: "!", attributes: attrs)
            let bangSize = bang.size()
            bang.draw(at: NSPoint(x: (s - bangSize.width) / 2.0,
                                  y: bandBottom + (markH - bangSize.height) / 2.0))
        }

        // Corner dot — upper-right, 1pt inset.
        if let cornerDot {
            let d: CGFloat = 4.0, inset: CGFloat = 1.0
            cornerDot.setFill()
            NSBezierPath(ovalIn: NSRect(x: s - d - inset, y: s - d - inset,
                                        width: d, height: d)).fill()
        }

        canvas.unlockFocus()
        canvas.isTemplate = false
        canvas.accessibilityDescription = label
        return canvas
    }

    /// Re-renders `base` with a red corner dot stamped upper-right — the
    /// unresolved-failure overlay. Works for any 18pt icon and visually
    /// replaces any state dot already at that corner.
    private static func stampingFailureDot(on base: NSImage, label: String) -> NSImage {
        let s = pointSize
        let canvas = NSImage(size: NSSize(width: s, height: s))
        canvas.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: s, height: s))
        let d: CGFloat = 4.0, inset: CGFloat = 1.0
        NSColor(Palette.recRed).setFill()
        NSBezierPath(ovalIn: NSRect(x: s - d - inset, y: s - d - inset,
                                    width: d, height: d)).fill()
        canvas.unlockFocus()
        canvas.isTemplate = false
        canvas.accessibilityDescription = label
        return canvas
    }

    // MARK: - SF Symbol builder (hands-free only)

    private static func tinted(_ symbol: String, weight: NSFont.Weight, color: NSColor, label: String) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let glyph = (NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(cfg)) ?? NSImage()
        let canvas = NSImage(size: NSSize(width: pointSize, height: pointSize))
        canvas.lockFocus()
        let glyphSize = glyph.size
        let originX = (pointSize - glyphSize.width) / 2.0
        let originY = (pointSize - glyphSize.height) / 2.0
        glyph.draw(in: NSRect(x: originX, y: originY, width: glyphSize.width, height: glyphSize.height))
        canvas.unlockFocus()
        canvas.isTemplate = false
        canvas.accessibilityDescription = label
        return canvas
    }
```

This deletes the old SF-Symbol `image(for:)`, the old `image(for:unresolvedFailures:)`, the `failed(...)` builder, and the `template(...)` builder; `tinted(...)` is kept verbatim for the hands-free ear.

- [ ] **Step 3: Replace the `MenuBarIcon` struct**

In `MenuBarIconRenderer.swift`, replace the entire `struct MenuBarIcon: View { ... }` with:

```swift
struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        // Static per-state NSImage. A SwiftUI/TimelineView label re-rasterises
        // every frame inside MenuBarExtra and pins the main thread (see commit
        // history) — so the icon is a discrete image, re-rendered only when
        // iconState/unresolvedFailures change. `.id(colorScheme)` rebuilds it
        // on a light/dark flip; the brand glyph is non-template and image(for:)
        // re-resolves the mark against NSApp.effectiveAppearance each rebuild.
        Image(nsImage: MenuBarIconRenderer.image(
            for: observer.iconState,
            unresolvedFailures: observer.unresolvedFailures
        ))
        .frame(width: 18, height: 18)
        .id(colorScheme)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        let base = MenuBarIconRenderer.accessibilityLabel(for: observer.iconState)
        guard observer.unresolvedFailures > 0 else { return base }
        let suffix = observer.unresolvedFailures == 1
            ? "1 unresolved failure"
            : "\(observer.unresolvedFailures) unresolved failures"
        return "\(base), \(suffix)"
    }
}
```

- [ ] **Step 4: Replace the preview harness**

In `MenuBarIconRenderer.swift`, replace the entire `#if DEBUG ... #endif` preview block at the end of the file with:

```swift
#if DEBUG
private struct MenuBarIconPreviewHarness: View {
    @State private var state: MenuBarIconRenderer.IconState = .idle
    @State private var unresolved: Int = 0

    private let allStates: [(String, MenuBarIconRenderer.IconState)] = [
        ("Idle", .idle), ("Arming", .arming), ("Recording", .recording),
        ("Transcribing", .transcribing), ("Enhancing", .enhancing),
        ("Committed", .committed), ("Fail", .fail), ("Hands-free", .handsFree),
    ]

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: MenuBarIconRenderer.image(
                for: state, unresolvedFailures: unresolved))
                .frame(width: 64, height: 64)

            Picker("State", selection: $state) {
                ForEach(allStates, id: \.1) { Text($0.0).tag($0.1) }
            }
            .pickerStyle(.menu)

            Stepper("Unresolved: \(unresolved)", value: $unresolved, in: 0...5)
        }
        .padding(32)
        .frame(width: 360)
    }
}

#Preview("Menu bar icon — Onyx") {
    MenuBarIconPreviewHarness()
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Menu bar icon — Light") {
    MenuBarIconPreviewHarness()
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
```

- [ ] **Step 5: Add `NSImage`-contract smoke tests**

In `VoiceInkTests/MenuBarIconTests.swift`, add `import AppKit` directly below the existing `import SwiftUI` line, then append this extension at the end of the file (after the closing `}` of `final class MenuBarIconTests`):

```swift
// MARK: - Brand-glyph image contract

extension MenuBarIconTests {
    func test_image_isNonTemplate_andSized_forAllStates() {
        let states: [MenuBarIconRenderer.IconState] = [
            .idle, .arming, .recording, .transcribing,
            .enhancing, .committed, .fail, .handsFree,
        ]
        for state in states {
            let img = MenuBarIconRenderer.image(for: state, unresolvedFailures: 0)
            XCTAssertFalse(img.isTemplate, "\(state): brand glyph must be non-template")
            XCTAssertEqual(img.size, NSSize(width: 18, height: 18), "\(state): icon must be 18×18pt")
            XCTAssertNotNil(img.accessibilityDescription, "\(state): icon needs an a11y description")
        }
    }

    func test_image_withUnresolvedFailures_isNonTemplate_andSized() {
        let img = MenuBarIconRenderer.image(for: .idle, unresolvedFailures: 2)
        XCTAssertFalse(img.isTemplate)
        XCTAssertEqual(img.size, NSSize(width: 18, height: 18))
    }
}
```

- [ ] **Step 6: Verify no stale references remain**

Run:

```bash
grep -rn "static func template\|static func failed\|MenubarGlyph" VoiceInk/ --include=*.swift
grep -rn "MenuBarIconRenderer.image" VoiceInk/ --include=*.swift
```

Expected: the first command returns **nothing** (both old builders deleted, `MenubarGlyph` fully gone). The second returns exactly two call sites — `MenuBarIcon.body` and the preview harness — both using the `image(for:unresolvedFailures:)` signature.

- [ ] **Step 7: Build gate**

Run the **build gate** — expected: exit 0, no `error:` lines. Then the **test-target compile check** (`build-for-testing`) — expected: exit 0, no `error:` lines (confirms the new smoke tests compile). A common failure is a leftover caller of an old `image(for:)` signature — Step 6's grep must be clean first.

- [ ] **Step 8: Commit**

```bash
git add VoiceInk/Views/Common/MenuBarIconRenderer.swift VoiceInkTests/MenuBarIconTests.swift
git commit -m "feat(menubar): draw the brand glyph as a static per-state NSImage

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: Verify success criteria

Build the daily-driver app and confirm the spec's success criteria. No code unless a criterion fails.

**Files:**
- Possibly modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift` (only if a visual check fails)

- [ ] **Step 1: Build and install**

```bash
make local
```

Expected: `** BUILD SUCCEEDED **`, `/Applications/Sotto.app` updated.

- [ ] **Step 2: Verify the idle glyph**

Quit any running Sotto, then `open -a Sotto`. The menu bar icon must be the **brand glyph** — a short vertical mark above a full-width lime underscore — NOT an SF-Symbol waveform. The vertical mark must look crisp (not blurred) at the menu bar size.

- [ ] **Step 3: Verify the state cycle + no hang**

Trigger a dictation (the recording hotkey), speak briefly, stop. Watch the menu bar icon through the cycle:
- recording → **red mark**
- transcribing / enhancing → mark + **lime corner dot**
- committed → mark + **green corner dot** (~1.5s)
- back to **idle** (plain mark + underscore)

The app must stay responsive throughout — no beachball, no CPU spike. (Optional: Activity Monitor → CPU, filter `Sotto`, confirm it does not pin a core during the busy states.)

- [ ] **Step 4: Verify light/dark legibility**

System Settings → Appearance: toggle Light ↔ Dark. The idle glyph's **mark must flip** with the appearance and stay clearly visible in both. The lime underscore stays lime in both. If the mark goes stale/invisible after a flip and only corrects on the next recording, `.id(colorScheme)` is not invalidating the `MenuBarExtra` label — report it as a found issue (the next state-change redraw still self-corrects, since `image(for:)` re-resolves against `NSApp.effectiveAppearance` every call).

- [ ] **Step 5: Verify the remaining states via the Xcode preview**

Open `MenuBarIconRenderer.swift` in Xcode, run the `Menu bar icon — Onyx` and `— Light` previews. Step the picker through all 8 states and the `Unresolved` stepper:
- `fail` → red `!` in place of the mark.
- `handsFree` → the lime `ear.fill`.
- `Unresolved ≥ 1` on any state → a red corner dot is stamped on.
All 8 states must be legible at the 18pt size.

- [ ] **Step 6: Commit any fix**

If a visual check failed and you adjusted `MenuBarIconRenderer.swift` (e.g. dot size, mark proportions, the `.id(colorScheme)` wiring), rebuild (`make local`), re-verify, then:

```bash
git add VoiceInk/Views/Common/MenuBarIconRenderer.swift
git commit -m "fix(menubar): adjust brand glyph from visual verification

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

If every check passed first time, there is nothing to commit — skip.

---

## Self-review notes

- **Spec coverage:** §1 architecture (static `Image(nsImage:)`, only `image(for:)` changes) → Task 2 Steps 2–3. §2 the glyph (proportions, `NSBezierPath`, non-template, pixel-snapped) → Task 2 Step 2 `brandGlyph`. §3 per-state table → Task 2 Step 2 `glyphImage(for:markColor:)`. §4 light/dark (`image(for:)` resolves the mark against `NSApp.effectiveAppearance`; `.id(colorScheme)` rebuilds on flip) → Task 2 Steps 2–3, verified Task 3 Step 4. §5 unresolved-failure overlay → Task 2 Step 2 `stampingFailureDot`. §6 cleanup → Task 1. Testing (build + visual + `NSImage`-contract smoke tests) → Task 2 Steps 5/7, Task 3. Success criteria → Task 3.
- **Type consistency:** `IconState` (8 cases, untouched), `accessibilityLabel(for:)`, `image(for:unresolvedFailures:)`, `glyphImage(for:markColor:)`, `GlyphCenter` (`.mark`/`.failBang`), `brandGlyph(center:cornerDot:label:)`, `stampingFailureDot(on:label:)`, `failedAccessibilityLabel(for:count:)`, `tinted(_:weight:color:label:)` — referenced consistently across Tasks 1–2.
- **Deletions are caller-checked:** Task 1 Step 1 greps for external users of the deleted SwiftUI types; Task 2 Step 6 greps for callers of the deleted `template`/`failed`/old `image(for:)` signatures. Both gate their tasks.
- **Build never breaks mid-plan:** after Task 1 the app builds and shows SF Symbols (safe refactor); after Task 2 it shows the brand glyph. Each task is independently green.

## Unresolved questions

None — the design spec is approved. One verified-in-plan risk: the light/dark redraw relies on `.id(colorScheme)` invalidating the `MenuBarExtra` label closure; Task 3 Step 4 explicitly checks this. Even in the worst case it is self-healing — `image(for:)` re-resolves the mark against `NSApp.effectiveAppearance` on every call, so the next state-change redraw corrects a stale icon.
