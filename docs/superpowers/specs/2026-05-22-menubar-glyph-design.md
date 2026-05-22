# Sotto Menu Bar — Static Brand Glyph Design

**Date:** 2026-05-22
**Branch:** `feat/menubar-glyph` (off `main`)
**Status:** design — approved, ready for implementation plan
**Supersedes:** `docs/superpowers/plans/2026-05-11-sotto-menubar-plan.md` (stale — specced a SwiftUI-animated "Path A" that is now proven non-viable)

## Problem

The menu bar icon should be the Sotto brand glyph (two-stroke mark + lime underscore) reflecting recorder state. A prior mission (`menubar-s1`) built a full SwiftUI animated glyph — `MenubarGlyph` plus `TimelineView`-driven overlays (`BouncingDots`, `ArcSpinner`, `CornerBadge`, `FailGlyph`, `MenubarGlyphContainer`) — and mounted it as the `MenuBarExtra` label.

It **hung the app at 100% CPU** (commit `3135761`): `MenuBarExtra` rasterises its label into the status-item button image on every SwiftUI update, so a `TimelineView` label re-rasterises every animation frame → infinite `updateButton → setImage → _adjustLength` loop, pinning the main thread once the icon entered any animated state. The fix reverted `MenuBarIcon` to a static SF-Symbol `NSImage`.

So today the menu bar shows generic SF Symbols (`waveform` / `sparkles` / `checkmark` / …), not the brand glyph, and the entire SwiftUI animated glyph system is dead code that can never be mounted.

## Goal

Replace the SF-Symbol menu bar icons with the **static brand glyph**, drawn per state as an `NSImage`. Fully static — no animation of any kind. (User decision: the recorder HUD already carries the live animated feedback; the menu bar is a peripheral status light.) Delete the unmountable SwiftUI animation code.

## Non-goals

- No animation — no timer-driven re-snapshots, no `TimelineView`.
- No change to `IconState`, `RecordingStateObserver`, the Combine pipeline, or the `MenuBarExtra` mount in `VoiceInk.swift`.
- No change to the `MenuBarView` dropdown contents.
- `handsFree` keeps its existing `ear.fill` icon — outside brand-glyph scope.

## Design

### 1. Architecture — minimal blast radius

`MenuBarIcon` stays a plain `Image(nsImage:)` keyed on `observer.iconState` + `observer.unresolvedFailures`. That static-image structure is exactly what avoids the rasterisation hang and must not change. **Only the image content changes**: `MenuBarIconRenderer.image(for:)` is rewritten to draw the brand glyph instead of SF Symbols.

Untouched: `MenuBarIconRenderer.IconState` (all 8 cases), `RecordingStateObserver` and its `bind(to:)` / `bind(toHalo:)` / `bind(toRegistry:)` pipeline, the `VoiceInk.swift` `MenuBarExtra` mount.

### 2. The glyph

Brand mark on an 18×18pt canvas (`MenuBarIconRenderer.pointSize`), spec §5.2 proportions (S = 18pt):

- **Mark** — vertical bar, width 0.18S, height 0.55S, centered horizontally, corner radius ≈ 15% of width.
- **Underscore** — full-width bar (1.00S), height 0.14S, `Palette.brandAcid` (#D4FF3A lime), corner radius ≈ 30% of height.
- Gap 0.08S between mark and underscore; the mark + gap + underscore stack (0.77S total) is vertically centered (≈ 0.115S inset top and bottom).

Drawn via `NSBezierPath` inside `NSImage.lockFocus()`. `isTemplate = false` — the lime underscore is a brand color; a template image would flatten the whole glyph to a single tint mask.

### 3. Per-state rendering

State is carried by **mark color** (loud states) and a **4pt corner dot** in the upper-right (quiet states):

| IconState     | Mark                          | Corner dot              |
|---------------|-------------------------------|-------------------------|
| idle          | label color                   | —                       |
| arming        | label color                   | lime (`brandAcid`)      |
| recording     | red (`recRed`)                | —                       |
| transcribing  | label color                   | lime                    |
| enhancing     | label color                   | lime                    |
| committed     | label color                   | green (`commitGreen`)   |
| fail          | red `!` glyph replaces the mark | —                     |
| handsFree     | unchanged — keeps `ear.fill`, lime-tinted | —           |

Vocabulary: **red mark = recording**, **red `!` = fail**, **lime dot = busy**, **green dot = done**, **plain = idle**.

`arming` / `transcribing` / `enhancing` render identically — a single "busy" glyph (label-color mark + lime dot). At 18pt static they cannot legibly differ, and the HUD carries the fine-grained phase. VoiceOver accessibility labels still distinguish all 8 states.

The fail `!` is drawn as a heavy monospaced "!" centered in place of the mark; the lime underscore remains.

### 4. Light / dark menu bar

Because the images are non-template, macOS will not auto-tint them. The saturated elements — red mark, lime underscore, dots, red `!` — read on both light and dark menu bars and never need to flip.

The **label-colored mark** (idle / arming / transcribing / enhancing / committed) must track the menu bar appearance: the renderer resolves the label color against the menu bar's effective appearance, and a lightweight observer regenerates the image set when the system light/dark appearance changes. Without it, the idle glyph keeps a stale mark color — possibly near-invisible — after a mid-session appearance flip.

### 5. Unresolved-failure overlay

`image(for:unresolvedFailures:)` keeps its current contract: when `unresolvedFailures > 0`, the icon carries a red corner dot (preserved, restyled onto the brand glyph). The existing `failed()` builder currently uses the stale pre-rename tangerine `Palette.accent`; the redesign drops that — failure signaling uses `recRed`.

### 6. Cleanup

`VoiceInk/Views/Common/MenubarGlyph.swift` is **deleted in full** — every view in it is `TimelineView`-driven and unmountable. Its only non-view export, `accessibilityLabel(for:)` (pure logic, exhaustive over `IconState`), moves to `MenuBarIconRenderer`.

## Files changed

| File | Change |
|------|--------|
| `VoiceInk/Views/Common/MenuBarIconRenderer.swift` | Rewrite `image(for:)` to draw the brand glyph; add a private `brandGlyph(...)` `NSBezierPath` builder; add `accessibilityLabel(for:)`; add the appearance observer + image regeneration; drop the stale `Palette.accent` usage |
| `VoiceInk/Views/Common/MenubarGlyph.swift` | **Deleted** |
| `VoiceInkTests/MenubarGlyphTests.swift` | Renamed `MenuBarIconTests.swift`; accessibility-label tests reference `MenuBarIconRenderer.accessibilityLabel`; `IconState` mapping tests unchanged; `NSImage`-contract smoke tests added |

## Testing

- The 11 `IconState`-mapping / combined-init tests — unchanged, stay green.
- The 8 accessibility-label tests — reference updated to `MenuBarIconRenderer.accessibilityLabel`.
- A few `NSImage`-contract smoke tests (`isTemplate == false`, 18×18 size, non-nil accessibility description) are added to `MenuBarIconTests` — they compile-verify the glyph contract and catch the most likely regression (a forgotten `isTemplate = false`).
- The repo's `xcodebuild test` launcher is documented-broken ("Test crashed with signal trap before establishing connection"). Gate on the headless build (`xcodebuild build … -quiet` → exit 0, no `error:` lines) plus a manual menu-bar state-cycle visual check via `make local`. If the test launcher cannot run, fall back to `build-for-testing` to confirm the test target compiles — do not silently skip.

## Success criteria

1. Build gate green; the renamed test target compiles.
2. The menu bar shows the brand glyph (mark + lime underscore) in every state — not SF Symbols.
3. recording = red mark; fail = red `!`; committed = green dot; busy states = lime dot; idle = plain — all legible at 18pt on both light and dark menu bars.
4. No CPU hang in any state (guaranteed by the static-image structure).
5. `MenubarGlyph.swift` is deleted; no dead / unmountable view code remains.

## Open questions

None — design approved.
