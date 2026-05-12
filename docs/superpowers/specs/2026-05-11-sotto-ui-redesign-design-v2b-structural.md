# Sotto · UI redesign design spec — v2b (structural rebuild)

**Date:** 2026-05-11
**Source:** iterative-visual-mockups brainstorm `59608-1778494162`
**Status:** Foundations locked. Rebuilt against existing code.
**Scope tier:** Recommended (7 teammate pairs · ~3 weeks parallel)
**Supersedes:** `2026-05-11-sotto-ui-redesign-design.md` (v1 — drafted before reading the codebase).

v1 locked the visual vocabulary correctly but described surfaces that don't match the shipping implementation. v2b keeps every locked foundation choice (Sotto, Tactical Glass, Acid Lime, Bay, Symmetric Glass, Invisible idle, Recommended scope, 7-state morphology) and rewrites §1–§7 against the actual Swift code that already implements 60–80% of what's needed. New **Appendix C** maps every pair to existing-code starting points; expanded **§7.1 Migration** spells out bundle-ID / SwiftData / CloudKit / Sparkle continuity; new **§1.X Accessibility** closes the Reduce-Motion + colorblind gaps both critiques flagged.

Locked foundations (do not re-litigate): Sotto brand, Tactical Glass material, Acid Lime accent, Bay structure, Symmetric Glass chips, Invisible idle, Recommended scope, 7-state morphology.

---

## 0 · Constraints & non-goals

**Hard constraints:**
- macOS 14.4+ (SwiftUI 5).
- Fork of GPL-v3 `github.com/Beingpax/VoiceInk`. Source-header copyrights preserved per §7.1.GPL.
- `NotchRecorderPanel` is the sacred keeper. v2b builds *inside* the existing single-strip-panel topology — does not split or relocate it.
- Bundle ID `com.prakashjoshipax.VoiceInk` collides with upstream → rename mandatory + migration shim required (see §7.1).
- Monetization already stripped from this fork (per project memory) — no PRO/trial/Polar/license surfaces need redesign.

**Non-goals:** new features (CLI, palette, snippets, sound), behavior changes during re-skin, cross-platform parity.

---

## 1 · Material

### Locked: Tactical Glass

Hybrid material — glass refraction (depth) + brutalist geometry/typography (personality).

### 1.1 — Surface recipe (Swift, not CSS)

The v1 spec gave a CSS recipe (`backdrop-filter: blur(28px) saturate(1.5)`). `NSVisualEffectView` exposes `material` as an opaque enum — no `blurRadius` or `saturation` setter. The CSS numbers are aspirational; the shipping contract is the `HaloMaterial.swift` pattern, which composites:

1. `VisualEffectBlur` (`material: .hudWindow`, `blendingMode: .behindWindow`, `appearance: .darkAqua`)
2. Opaque fill — `Color.black.opacity(0.78)` (onyx) or `Color.white.opacity(0.32)` (light)
3. Inner top gloss — 1.5pt linear gradient, white@0.30 → transparent
4. Inner stroke — 0.5pt white@0.16 (onyx) / white@0.55 (light)
5. Bottom inner stroke — 0.5pt white@0.05 (onyx) / white@0.18 (light)
6. State-keyed outer halo — 24pt blur, color from `HaloPhase.glowColor`
7. Drop shadow — 14pt blur, offset (0, 6), black@0.45

> **Divergence flag:** the rendered surface will not match the HTML mockups numerically — Apple bakes blur radius / saturation into the named material. Reviewers compare against `HaloMaterial` previews, not the HTML.

**SwiftUI primitive (new, shared):** `TacticalGlass(shape:phase:appearance:)` — a thin wrapper that calls into `HaloMaterial` with Sotto-tuned defaults. HUD pair owns the file; SETTINGS / MAIN / ONBOARDING import it.

### 1.2 — Geometry tokens

- `cornerRadiusGlass: 2pt` (matte app surfaces)
- `cornerRadiusNotch: 8pt bottom-only` (Bay capsule + chips — match notch bottom-radius, hard top edge)
- `cornerRadiusZero: 0pt` (brackets, dividers, tiles)
- `hairline: 0.5pt white@0.16` (matches `HaloMaterial` inner stroke — not 1pt)
- `spacingUnit: 4pt` (paddings are 8/12/16, not 16/24/32)

### 1.3 — Typography

- Body / sidebar / labels / CTA / transcript: **SF Mono** (fallback `ui-monospace`).
- Tracking: uppercase labels `+0.16em` to `+0.20em`. Body `+0.02em`.
- Weights: 700 for labels / CTAs / titles. 400 for body. No medium/semibold.
- Prompt glyph: `›` (U+203A) leads sidebar items + section labels + CTAs. Lime when selected, white@0.42 otherwise. 4–6pt right margin.

### 1.4 — Color tokens

| Token | Hex | Use |
|---|---|---|
| `brandAcid` | `#D4FF3A` | wordmark · selected row · section labels · prompt glyph · CTA halo · HUD audio bars |
| `recRed` | `#FF3B30` | recording dot · fail state · destructive utility only |
| `commitGreen` | `#30D158` | committed · success utility only |
| `transCyan` | `#5AC8FA` | transcribing sweep + capsule border |
| `enhViolet` | `#BF5AF2` | enhancing halo breath + arc spin |
| `surface` | `rgba(8,8,12,0.78)` | every glass tint (alpha aligned to `HaloMaterial`'s 0.78 fill) |
| `hairline` | `rgba(255,255,255,0.16)` | every border |
| `ghost` | `rgba(255,255,255,0.42)` | secondary text on glass |

> **Migration note:** existing `Palette.accent` is tangerine (`0.357, 0.227`). Renaming to `Palette.brandAcid` + retiring tangerine is a HUD-pair task. `HaloPhase.glowColor` returns must be re-keyed to the new state colors (see §4).

### 1.5 — Wallpaper bleed-through

In-app surfaces (Settings, Main) need a saturated backdrop or glass reads as flat plastic. Subtle gradient:

```
radial-gradient(at 20% 0%, rgba(110,62,182,0.18), transparent 60%),
radial-gradient(at 100% 100%, rgba(212,255,58,0.06), transparent 50%),
#0d0d10
```

Implemented as a `RadialGradient` ZStack under the root window — SETTINGS / MAIN pairs own.

### 1.6 — Glyph collision resolution (`›` vs `▸`)

Two codepoints — different roles:

- `›` (U+203A) — **read-only prompt** in front of sidebar rows, section labels, CTA text. Never tappable on its own.
- `▸` (U+25B8) — **tappable affordance** on Bay chips and explicit buttons. Indicates "this is a hit target."

Acceptance criterion §1 covers both: sidebar rows use `›`; chip text and buttons use `▸`.

### 1.X — Accessibility (new)

Color-keyed grammar (§4) plus motion-keyed states (§4) leak two A11y debts. v2b closes them:

- **Reduce Motion** (`accessibilityReduceMotion`): every state with a 0.8–1.6s loop (arming breathe, recording pulse, transcribe sweep, enhance halo breath, fail blink) degrades to an opacity-only fade. The state's halo color still renders; the motion does not.
- **Color-blind disambiguation:** `committed` shows a `✓` glyph in the capsule; `fail` shows a `✗` glyph + the error code. Settled-state distinction is shape-based, not color-only.
- **VoiceOver:** every Bay subview gets explicit `accessibilityLabel` / `accessibilityValue`. Capsule announces state on transition (`"Recording, 0:12"`, `"Transcribing"`, `"Committed, paste available"`). The menubar icon announces state changes via `MenuBarIcon.accessibilityLabel` — already implemented in `MenuBarIconRenderer.failedAccessibilityLabel` for failures, extend to the other states.
- **High Contrast** (`accessibilityDisplayShouldIncreaseContrast`): reuse the existing `AdaptiveGlass` pattern in `HaloMaterial.swift` — opaque fills, 1pt solid strokes in state color, halo glows suppressed. Already shipping; SETTINGS / MAIN / ONBOARDING pairs adopt the same branch.
- **Menubar icon accessibility label:** must announce on each state change. Static text via `MenuBarIcon.accessibilityLabel` is the floor; live announcement via `AccessibilityNotification.announcement(...)` on transition is the ceiling.

### Reasoning

Pure glass is anonymous. Pure brutalism is cold. Tactical Glass keeps warmth + personality. The shipping `HaloMaterial` already implements the right pattern; v2b standardises the recipe and adds A11y branches.

### Acceptance

- [ ] All glass surfaces route through `TacticalGlass` (wraps `HaloMaterial`); no ad-hoc `.regularMaterial` or `.ultraThinMaterial`.
- [ ] Text styles use SF Mono. User-typed prose (notes textareas) MAY use SF Pro inside the field.
- [ ] Uppercase labels track `+0.16em` or more.
- [ ] Sidebar/list rows use `›` prefix + lime tint; chips/buttons use `▸`.
- [ ] No `cornerRadius > 8pt` anywhere.
- [ ] No inner highlights (only `HaloMaterial`'s prescribed top gloss).
- [ ] All color uses tokens above. Tangerine `Palette.accent` retired or renamed.
- [ ] Reduce Motion fallback present for every multi-second loop.
- [ ] Committed `✓` and fail `✗` glyphs render independently of color.

---

## 2 · Structure

### Locked: Bay (single panel, multi-element layout)

The recording HUD = central capsule + two stalactite chips. v1 said "each is its own NSPanel"; that regresses the shipping topology and breaks Space transitions. v2b: the Bay is a layout *inside* the existing single NSPanel.

### 2.1 — Existing topology (the contract)

`VoiceInk/Views/Recorder/NotchRecorderPanel.swift` is a full-width strip panel:

- `styleMask: [.nonactivatingPanel, .fullSizeContentView]` — never becomes key, never steals focus.
- `level = .popUpMenu` (101) — composites above Metal/Stage-Manager full-screen apps.
- `collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]` — survives 4-finger swipes, Mission Control, app entering full-screen mid-record.
- `ignoresMouseEvents = true` — passthrough hit-test; menu bar clicks fall through even though the panel sits above it.
- Frame = full screen width × 120pt at top.
- `handleActiveSpaceChange` re-anchors + `orderFrontRegardless` on Space change.
- `calculateWindowMetrics()` reads `screen.auxiliaryTopLeftArea?.width` + `.auxiliaryTopRightArea?.width`. Returns `180` fallback on non-notch Macs.

Splitting the Bay into 3 NSPanels would mean three independent `activeSpaceDidChangeNotification` subscriptions, three re-anchor timings, and three `orderFrontRegardless` calls per Space swap — visible component desync. v2b mandates: **one panel, three subviews.**

### 2.2 — Layout inside the panel

| Element | Width | Height | x-offset from screen center | y-offset from top | Corners |
|---|---|---|---|---|---|
| Central capsule | 220pt | 44pt | 0 | 22pt (under notch) | bottom 8pt |
| Left stalactite (MODE) | ~78pt | 28pt | −110pt − 8pt gap (≈ −118pt) | 38pt | bottom 6pt |
| Right stalactite (ACTION) | ~78pt | 28pt | +110pt + 8pt gap (≈ +118pt) | 38pt | bottom 6pt |

> **Multi-monitor caveat:** `NSScreen.main` may or may not be the notch display when external monitors are attached. The Bay is wider than the non-notch `180pt` fallback. HUD pair must spike multi-monitor anchoring (Appendix B).

All three subviews mount into the same `NSHostingView`-rooted SwiftUI tree, share a single `@StateObject RecorderUIState`, and animate on a single driver. The existing `NotchRecorderHostingController` clears its layer background — keep as-is.

### 2.3 — Chip treatment (Q4.5 lock: Symmetric Glass)

Both chips wear identical material (lime SF-Mono on Tactical Glass, 6pt bottom-radius, white hairline). The right chip has a leading `▸` glyph to indicate tappability — the symmetric look hides which chip is hot at a glance, the glyph makes it explicit.

> **User-overridden brainstorm pick:** the mockup `chips.html` pre-selected "Asymmetric Command" and flagged Symmetric's tappability ambiguity as the current weakness. User chose **Symmetric Glass** for the quieter visual posture; the `▸` glyph + tap-target acceptance criterion below is the mitigation.

Content per phase:

| Phase | Left chip | Right chip |
|---|---|---|
| arming | hidden | hidden |
| recording | active prompt: `DEFAULT` / `ASSISTANT` / custom name (truncated 9 chars) | `▸ SAVE` |
| transcribing | collapsed | collapsed |
| enhancing | collapsed | collapsed |
| committed (1.5s) | collapsed | `▸ UNDO` |
| fail | collapsed | collapsed (error code in capsule) |

> **Mode-list correction:** v1 invented `PROSE / EMAIL / CODE / RAW`. The real surface is `PredefinedPrompts.all` returning `Default` + `Assistant`, plus user-defined `CustomPrompt` rows from `AIEnhancementService.customPrompts`. The left chip displays `activePrompt?.title.uppercased()` truncated to 9 chars; if none, the chip is hidden.

Chip fade timing: out 140ms on `recording → transcribing`, in 220ms on `committed → recording` re-entry (not a real transition — but matches design). Synced with capsule via a single `withAnimation` driver.

### 2.4 — Keyboard handling during recording

The NSPanel is `.nonactivatingPanel` and `canBecomeKey = false` — `Return` / `Esc` while dictating are NOT intercepted, they pass through to Mail/Slack/VSCode. The right stalactite is mouse-actionable only when `ignoresMouseEvents` is toggled off for that subview's frame — see Appendix B.HitTest.

### Reasoning

- "Drop" (single capsule) too thin for 6 affordances.
- "Strip" (full-width drop) eats 44pt of vertical real estate permanently.
- "Bay" threads the needle: notch metaphor pure (grows from notch, doesn't replace menubar), exposes mode + primary action, animates as one ecosystem.
- Single-panel topology is the existing contract — re-using it gives Space-transition handling for free.

### Acceptance

- [ ] HUD lives in `Sotto/Views/Recorder/NotchRecorderPanel.swift` (renamed). Single NSPanel, three SwiftUI subviews.
- [ ] Subviews share one `RecorderUIState` observable.
- [ ] Single `withAnimation` driver coordinates capsule + chips.
- [ ] Right stalactite is mouse-actionable (chip frame opted-into hit-test); keyboard input is NOT intercepted from the focused app.
- [ ] Tap targets ≥ 28pt × 60pt (chip visible bounds == hit bounds — no invisible padding).
- [ ] `collectionBehavior`, `level`, `styleMask`, `handleActiveSpaceChange` carry over unchanged.
- [ ] Multi-monitor + non-notch fallback behavior documented + tested (Appendix B).

---

## 3 · Idle

### Locked: Invisible

When the app is not recording, the HUD is fully absent. Menubar icon carries idle presence.

> **User-overridden brainstorm pick:** the mockup `idle.html` pre-selected "Whisper" (faint persistent breath). User chose **Invisible** — the notch is bare hardware, the app is summoned on top of it.

The existing `NotchRecorderPanel.hide(completion:)` is a no-op placeholder. v2b: HUD pair implements idle-hide as `orderOut(nil)` (window closed, but instance retained as a property of `RecorderUIManager`). The hosting tree's SwiftUI views unmount via state binding when `phase == .hidden`. No backdrop-filter views render in idle.

> The v1 acceptance "alphaValue = 0 AND orderOut AND no NSPanel resources persist" contradicted itself. v2b resolves: panel instance lives for the app lifetime (cheap), but `orderOut` removes it from compositing and SwiftUI tree unmounts.

### Acceptance

- [ ] `NotchRecorderPanel.orderOut(_:)` is called on idle. Panel instance retained by manager.
- [ ] `HaloPhase == .hidden` → SwiftUI subview tree returns `EmptyView`; no `VisualEffectBlur` mounted.
- [ ] Menubar icon renders the idle variant (see §5).
- [ ] Cursor approaching the top of the screen does NOT reveal the HUD.
- [ ] First-run permissions flow (ONBOARDING pair) may show a one-time `⌥ SPACE` reminder — must dismiss permanently after first successful invocation. (Not a "shortcut hint pattern" — fires once, never again.)

---

## 4 · State grammar

### Locked: 7 states, dual-surface morphology

Mapped onto existing engine state.

### 4.1 — Existing state machinery

Two enums already cover most of the spec:

**`RecordingState`** (`VoiceInk/Transcription/Engine/RecordingState.swift`) — engine-side:
`idle · starting · recording · transcribing · enhancing · busy`

**`HaloPhase`** (`VoiceInk/Views/Recorder/HaloMaterial.swift`) — view-side:
`hidden · armed · recording · transcribing · enhancing · liveText · failed · done`

Spec states map to existing as follows:

| Spec state | Engine `RecordingState` | View `HaloPhase` | Notes |
|---|---|---|---|
| idle | `.idle` | `.hidden` | clean mapping |
| arming | `.starting` | `.armed` | `HaloPhase.armed` is "reserved at v1, unused" — v2b activates it |
| recording | `.recording` | `.recording` (or `.liveText` w/ partial transcript) | clean |
| transcribing | `.transcribing` | `.transcribing` | clean |
| enhancing | `.enhancing` | `.enhancing` | clean |
| committed | `.idle` (engine returns immediately) | `.done` | view layer holds `.done` for 1.5s |
| fail | `.idle` (engine returns immediately) | `.failed` | view layer holds; engine emits `FailureEvent` via `VoiceInkEngine.failurePublisher` |

**No new state machinery** — HUD pair extends `HaloPhase` mapping rules in `RecorderUIManager` to handle `done` / `failed` view-lifetimes (already partly done — `FailureRegistry` holds unresolved failures). Spec §4 then reads HaloPhase directly.

### 4.2 — State table

| # | State | Color | Notch HUD | Menubar icon | Enter | Loop | Exit |
|---|---|---|---|---|---|---|---|
| 1 | **idle** | — | hidden (`orderOut`) | bare Sotto glyph (template) | — | static | 120ms ease-out |
| 2 | **arming** | `#D4FF3A` | empty capsule fades in; lime border breathes 0.4↔0.9 α; ghost dot pulses; mono "LISTENING"; chips hidden | bare glyph pulses 0.55↔1.0 α | 180ms ease-out | 1.2s breathe | → recording on first audio |
| 3 | **recording** | `#FF3B30` + `#D4FF3A` | red dot pulse 1.0s; 5 lime audio bars (0.8–1.1s staggered); mono `REC mm:ss`; chips visible `[PROMPT] [▸ SAVE]` | glyph fills (white-on-black inverse); red corner-dot badge pulses 1.0s | 220ms (synced) | bars 0.8–1.1s · dot 1.0s | → transcribing on stop |
| 4 | **transcribing** | `#5AC8FA` | cyan sweep L→R 1.4s linear; bars freeze faint cyan; mono "TRANSCRIBING…"; chips collapsed | glyph swaps to 3 bouncing dots | 140ms chip retract | 1.4s sweep | → enhancing OR committed |
| 5 | **enhancing** | `#BF5AF2` | violet halo breathes 1.6s (0.25↔0.6 α); bars stay faint violet; mono "ENHANCING…" | glyph hollows + 270° arc spins 1.6s linear | 200ms cross-fade | 1.6s halo · 1.6s arc | → committed |
| 6 | **committed** | `#30D158` | green `✓` center + green halo; mono `PASTED` or `SAVED`; right chip `▸ UNDO` 1.5s | green corner-dot badge | 120ms snap | hold 1.5s | 400ms fade → idle |
| 7 | **fail** | `#FF3B30` | red border blinks 0.8s; `✗` glyph + error code (e.g. `ERR · NO_DEVICE`) | red `!` corner badge | 120ms snap | 0.8s blink until dismissed | click HUD or icon → idle |

> **"First audio" definition** (spike → HUD pair, Appendix B): VAD-gated first non-silent frame from `AudioRecorder`. Threshold pinned at -50 dBFS; mic init <16ms skips arming. Open until measured.

> **Reduce Motion fallback:** every loop above becomes a static colored surface + a 200ms opacity fade on enter/exit. Color and shape carry state; motion does not.

> **Per critiques:** the menubar icon's animated transcribing/enhancing states cannot be smooth under `isTemplate`. v2b resolves in §5: Canvas/Path views in `MenuBarExtra` label DO animate (verified in shipping `.menuBarExtraStyle(.menu)`). Template auto-tinting is achieved via `.foregroundStyle(.primary)` + `.symbolRenderingMode(.monochrome)`, not `NSImage.isTemplate`. Path B (timer-snapshot via existing `MenuBarIconRenderer`) is the fallback if the Path-view spike fails — at the cost of judder, not smoothness.

### 4.3 — Motion atoms

New file `Sotto/Theme/MotionTokens.swift` — pure value types, no model-layer imports. Each token = `(duration, easing, repeatStyle)`. The v1 phrase "CSS keyframes translate directly to SwiftUI" was a hand-wave — they don't; expect ~2 hours of fiddling per animation. Atoms:

`pulse · bars · sweep · breathe · blink · dotJump · spin`

### Reasoning

- Distinct colors for transcribe vs enhance: motion alone is too subtle at 1s glance; color adds a redundant channel.
- `arming` state preserved: the ~500ms breath gives the surface dignified entry; without it, the HUD pops in mid-recording.
- `committed` 1.5s hold: long enough to register, short enough not to block. `▸ UNDO` is the recoverability affordance.
- Fail must be user-dismissed: errors that vanish unread cause silent data loss.

### Acceptance

- [ ] HUD pair extends existing `HaloPhase` view-lifetime rules in `RecorderUIManager` to hold `.done` 1.5s + `.failed` until-dismissed. No new state-machine class.
- [ ] Motion timing matches table to ±20ms.
- [ ] Color tokens from §1 used; no per-state ad-hoc colors.
- [ ] Menubar icon updates within 50ms of `HaloPhase` change (same Combine subscription via `RecordingStateObserver`).
- [ ] `arming` skippable if mic init <16ms — HUD pair measures + decides v1 vs deferred (Appendix B).
- [ ] Fail shows monospace uppercase code `ERR · {DOMAIN}_{REASON}`.
- [ ] Chip content matches §2.3 phase table.
- [ ] Reduce Motion fallback verified for every loop.

---

## 5 · Brand

### Locked: Sotto

**Name:** `Sotto` — from Italian *sotto voce*, "under one's voice." Title-cased, five letters, common-pronounceable across the target markets the user ships to.

> **LLM-tell fixed:** v1 said "pronounceable in every language Anthropic ships." This is a personal fork — no Anthropic dependency. Replaced with neutral phrasing.

> **User-overridden brainstorm pick:** the mockup `brand.html` pre-selected "spool" and flagged Sotto's title-case + Italian register as disagreeing with the lowercase-mono design system. User chose **Sotto** anyway, accepting the wordmark tension: the wordmark is the one Title surface; everything else lives in lowercase mono.

### 5.1 — Wordmark

```
Sotto.
```

- Typeface: SF Mono Bold (700)
- Case: Title (cap S, lowercase otto)
- Tracking: `+0.02em`
- Trailing stop: heavy lime period (`#D4FF3A`, weight 900, +2pt left-margin)
- Glow (marketing surfaces only): `shadow: 0 0 12 rgba(212,255,58,0.7)`

Wordmark is one token. Never break line. Never replace `.`. Trailing stop = brand-mark.

**Tagline (marketing):** `› sotto voce · under your voice`

**Legal / file-system surfaces (carve-out):** `CFBundleName`, `CFBundleDisplayName`, brew cask name, and filesystem paths use bare `Sotto` (no trailing period — Finder displays `Sotto.app` where `.app` is the extension). The trailing period is for typeset surfaces only; legal copy ("By using Sotto you agree…") drops the period.

### 5.2 — Icon glyph

Two strokes — vertical mark above a heavy horizontal underscore. Reads as the typographic "below" notation. Mark is white/template; underscore is brand lime.

Proportions (canvas square `S`):
- Mark: 0.18S wide × 0.55S tall
- Underscore: 1.00S wide (or 0.92S inset for app icon) × 0.14S tall
- Gap: 0.08S
- Composite vertically centered

### 5.3 — Size + tint contract

| Size | Render | Tint mode |
|---|---|---|
| 1024 / 512 (App / Dock) | Full mark + underscore. Lime underscore w/ halo `0 0 32 rgba(212,255,58,0.6)` | Non-template |
| 256 / 128 / 64 (Spotlight, Finder, Notif Center) | Same proportions; halos compressed | Non-template |
| 32 (Notification) | Mark + underscore, no halo | Non-template |
| 16 / 18 / 22 (Menubar — all states) | **Non-template at all sizes** — see §5.4 | Non-template |

> **Template-vs-color resolution:** v1 said 16pt template (auto-tinted), but template strips the lime underscore. v2b: lime underscore is the brand-mark; preserving it at menubar size means **non-template at all sizes**. Cost: on light menu bars, the white mark loses contrast slightly — accepted. Mitigation: at menubar sizes the mark renders in `.primary` system color (auto-flips light/dark), only the underscore stays lime. Documented loss: small-size renderings on dark menubars under hostile wallpapers may need an opaque 1pt outline on the mark — HUD/ICON pair to spike if QA flags.

### 5.4 — Stateful menubar icon (single-path commitment)

**Chosen path: pure-SwiftUI `Canvas`/`Path` views inside `MenuBarExtra` label closure.**

The shipping app uses `.menuBarExtraStyle(.menu)` (see `VoiceInk.swift` line 502). SwiftUI views inside the label closure of `.menu`-style MenuBarExtra DO render and animate on macOS 14.4. The existing `MenuBarIcon` view (`Views/Common/MenuBarIconRenderer.swift` line 230) uses `Image(nsImage:)` because under the older `.window` style, `NSViewRepresentable` labels rendered 0×0. v2b uses the same `MenuBarExtra` label slot but replaces `Image(nsImage:)` with a `MenubarGlyph` SwiftUI view that draws the two-stroke mark via `Path`.

> **Spike required** (Appendix B.MenubarSpike): verify on macOS 14.4 specifically that (a) animation loops persist across menu bar re-snapshots, (b) battery cost of 1.6s repeat-forever animations in the menu bar is acceptable, (c) the `Canvas`/`Path` view at 16pt with state-keyed motion reads correctly on both dark and light menubars. **If the spike fails:** fall back to Path B — extend the existing `MenuBarIconRenderer` static-NSImage builders to add `arming`/`committed`/`fail` variants, drive them from a `Timer` snapshot loop (gives state but not smooth motion).

Drop the v1 phrasing "SwiftUI view hosted in the button (preferred — enables animation)." `NSStatusBarButton` has no SwiftUI hosting API; that path is impossible. The path is `MenuBarExtra` label, full stop.

**Animated states implementation:**

- `idle` — static `MenubarGlyph(phase: .idle)`. Mark + lime underscore.
- `arming` — `MenubarGlyph` with `.opacity(breathe)` driven by `TimelineView(.animation)`.
- `recording` — `MenubarGlyph` overlaid with red corner-dot Circle, dot pulses on `TimelineView`.
- `transcribing` — `MenubarGlyph` swapped for `BouncingDots()` (3 Circles with phase-offset Y-translation).
- `enhancing` — `MenubarGlyph` overlaid with `ArcSpinner()` — a `Path` arc rotating via `TimelineView`.
- `committed` — `MenubarGlyph` overlaid with green corner-dot, 1.5s hold then revert to idle.
- `fail` — `MenubarGlyph` overlaid with red `!` text + corner-dot.

**Wiring:** existing `RecordingStateObserver` (Combine bridge from `engine.$recordingState` + `HandsFreeSessionService.shared.$state`) is the model. Extend its `IconState` enum to include `.arming`, `.committed`, `.fail` (currently it has `.idle`, `.recording`, `.transcribing`, `.enhancing`, `.handsFree`). `committed` / `fail` are view-lifetime states held by the HUD coordinator; observer reads from there.

### Reasoning

- **Sotto** wins distinctiveness vs the cohort (every other product names the *thing it does*; Sotto names *how* — quietly, underneath).
- **Icon glyph** is the most reduced expression of "under" possible; scales 1024 → 16 without losing read.
- **Non-template** preserves the lime underscore — the brand-mark. Small-size dark-menubar contrast loss is the trade.
- **Pure-SwiftUI in `MenuBarExtra` label** is the only path that gives both stateful glyph and animation; spike validates feasibility.

### Acceptance

- [ ] App renamed: `PRODUCT_NAME`, `CFBundleDisplayName`, `CFBundleName`, `CFBundleIdentifier` (proposed `com.sotto.Sotto` — verify uniqueness via `mdfind`), `SUFeedURL`, brew cask, all marketing URL references.
- [ ] App icon assets: 1024 / 512 / 256 / 128 / 64 / 32 / 16 at 1x + 2x — 14 PNGs.
- [ ] Menubar icon: `MenubarGlyph` SwiftUI view in `MenuBarExtra` label closure. One view, one binding, animates via `TimelineView`. (Fallback to extended `MenuBarIconRenderer` if spike fails.)
- [ ] `BrandMarks.wordmark = "Sotto."` Swift constant + `BrandMarks.styledWordmark()` `AttributedString` view with the stop colored `brandAcid`.
- [ ] `grep -ri 'voiceink' Sotto/` is clean **except** the carve-outs in §7.1.GPL: `LICENSE`, `README`, `ACKNOWLEDGMENTS`, GPL-v3 §5 source-header copyright notices, deliberate upstream references in migration shim code.

---

## 6 · Scope

### Locked: Recommended (7 teammate pairs · ~3 weeks parallel)

### 6.1 — Surfaces in scope (11)

| # | Surface | Pair | Notes |
|---|---|---|---|
| 1 | App rename + bundle ID + Sparkle + brew + URLs | RENAME | + UserDefaults / SwiftData / CloudKit / OSLog migration — see §7.1 |
| 2 | App icon assets | ICON | 14 PNGs |
| 3 | Stateful menubar icon | MENUBAR | `MenubarGlyph` SwiftUI view + state machine binding |
| 4 | Notch HUD | HUD | Bay layout in single panel, Symmetric Glass chips, 7-state morphology, Invisible idle |
| 5 | Settings shell (sidebar, frame, nav) | SETTINGS | mono items + `›` prompts, Tactical Glass header/footer |
| 6 | Models pane | SETTINGS | **already shipped as W14F** (commits `924f9a6` + `b1148d2` on main) — verify visual conformance to §1, do NOT re-implement |
| 7 | General / Recorder / Hotkeys / Permissions panes | SETTINGS | re-skin, no logic changes |
| 8 | AI Models / Audio Input panes | SETTINGS | re-skin |
| 9 | Main window (transcript / history) | MAIN | sidebar + main pane |
| 10 | Onboarding / welcome | ONBOARDING | wordmark, first-run permissions, single `⌥ SPACE` reminder. **Net-new** — no existing onboarding view (only `MetricsSetupView` for metrics). Scope grows: full first-run flow design + impl |
| 11 | Notification toasts | ONBOARDING | Tactical Glass cards with Sotto colors |

### 6.2 — W14F status

Per git log: W14F two-tab Models pane + provider accordion shipped on `main` (commits `924f9a6 feat(settings): W14F — Models pane two-tab + provider accordion` and `b1148d2 feat(mlx): W14F — refresh curated lineup post hunter/challenger research`). The untracked `W14F_ui_redesign_report.md` is the post-ship report.

**Implication:** SETTINGS pair scope for Models pane = re-skin existing shipped code to §1 vocabulary (Tactical Glass focal cards, `›` row prefixes, lime selected row, SF Mono throughout). Pair does NOT re-implement segmented/accordion logic. This is a smaller delta than v1 implied.

### 6.3 — Pair assignments (7 pairs)

| Pair | Surfaces | Dependencies |
|---|---|---|
| RENAME | 1 | None — critical path, runs first |
| ICON | 2 | None |
| MENUBAR | 3 | RENAME (bundle ID for `MenuBarExtra` ownership), ICON (glyph asset) |
| HUD | 4 | RENAME (file paths) |
| SETTINGS | 5–8 | RENAME |
| MAIN | 9 | RENAME |
| ONBOARDING | 10–11 | RENAME, HUD (toast state colors) |

RENAME on critical path. ICON parallel from day 1. Others start once RENAME lands.

### 6.4 — Deferred (post-redesign backlog)

- Sound design (commit click, arming up-spool, fail negatone)
- Marketing site (`sotto.app` landing w/ state-cycle showcase)
- CLI parity (`sotto rec` / `sotto transcribe` / `sotto whisper` / `sotto modes`)
- Quick-paste palette (`⌘⇧V` Tactical Glass dropdown)
- Snippet library UI
- Voice memo timeline / gantt
- Custom enhancement-mode editor

### Acceptance

- [ ] All 11 surfaces touched and conform to §§1–5.
- [ ] No surface ships partially redesigned.
- [ ] Deferred items filed as GitHub issues with `redesign-followup` label before merge.
- [ ] PR description for each pair links back to this spec.
- [ ] SETTINGS pair confirms W14F shipped code conforms to §1 (or files re-skin delta as part of Surface 6).

---

## 7 · Handoff

1. User reviews spec. Team-lead handles review loop.
2. `/writing-plans` invoked with this spec — produces 7 per-pair plans.
3. Plans dispatched via `superpowers:subagent-driven-development` or `dispatching-parallel-agents`.
4. Each pair lands a PR, reviewed by team-lead pair-reviewer, merged to `redesign/sotto` integration branch.
5. Integration QA — highest risk = RENAME seam (verify no `voiceink` strings leak in error messages, logs, UserDefaults).
6. Final merge to main + brew cask update + Sparkle feed cutover.

### 7.1 — Migration (RENAME pair, expanded)

This subsection is owned end-to-end by RENAME. Every item is a known landmine.

#### 7.1.UserDefaults — ~33 unique `@AppStorage` keys + ~198 direct `UserDefaults.standard` accesses

After bundle-ID change, the new app reads an empty UserDefaults domain. Existing users lose every preference silently.

**Migration shim:** on first launch with new bundle ID, read `UserDefaults(suiteName: "com.prakashjoshipax.VoiceInk")`, iterate every key with the documented prefix list, and copy non-default values into `UserDefaults.standard` (which is now the Sotto domain). Then write a `__sotto_userdefaults_migrated_v1` sentinel to prevent re-runs.

Sentinel placement: `UserDefaults.standard`. After migration, the old suite remains on disk but unread.

#### 7.1.SwiftData — store path

`VoiceInk.swift` lines 141 and 287 both hardcode `appSupportDirectory.appendingPathComponent("com.prakashjoshipax.VoiceInk")`. After rename, the new app looks for a directory that doesn't exist; existing transcript history is orphaned.

**Migration shim:** at SwiftData container init, check for the legacy path. If found and the new path does not exist, `FileManager.moveItem(at:to:)` the entire directory. Idempotent — guarded by existence check.

#### 7.1.CloudKit — container ID

`VoiceInk.entitlements` line 9: `iCloud.com.prakashjoshipax.VoiceInk`. CloudKit container IDs are globally unique + tied to the developer account; the new container starts empty. **iCloud-synced Vocabulary/Dictionary data does not migrate automatically.**

**Options** (RENAME pair picks one and documents in PR):
- **A. New container, no migration.** Existing iCloud data is orphaned on the user's iCloud account; new container starts empty. Lowest-effort, highest data loss.
- **B. Keep the old container ID as `legacy`** in entitlements alongside the new container; one-shot copy on first launch. Doubles entitlement footprint.
- **C. Don't change the CloudKit container ID** — only the app bundle ID changes. CloudKit accepts any container the team owns; the container name doesn't have to match the bundle ID. Lowest-risk; recommended.

Recommend C unless there's a brand reason to migrate.

#### 7.1.OSLog — 51 `Logger(subsystem:)` instances, 5 unique subsystems

Subsystems present: `com.prakashjoshipax.voiceink`, `com.prakashjoshipax.VoiceInk`, `com.prakashjoshipax.voiceink.fluidaudio`, `com.VoiceInk`, `VADModelManager`. After rename, log attribution in Console.app / `log stream` will mismatch installed app identity.

**Action:** add `OSLogSubsystems.swift` exposing constants (`OSLogSubsystems.app = "com.sotto.Sotto"`, etc.). Replace all 51 instances. RENAME pair owns the global `grep` + replace.

#### 7.1.Sparkle — feed cutover

Existing `SUFeedURL = https://beingpax.github.io/VoiceInk/appcast.xml`. After bundle ID change, Sparkle treats Sotto as a distinct product — **existing VoiceInk installs will NOT receive an in-app upgrade prompt to Sotto.**

**Policy** (RENAME pair documents in PR):
- This fork's user base ≈ the user themselves + maybe collaborators. **No automated Sparkle handoff to Sotto.** Old VoiceInk continues to receive (if any) upstream updates from `beingpax.github.io`. Sotto starts with a fresh feed at `https://sotto.app/appcast.xml` (or a CDN path — Appendix B.Domain).
- New users install Sotto via brew cask / direct DMG.
- If a Sparkle handoff is wanted later, RENAME pair files a backlog ticket.

#### 7.1.GPL — source-header carve-out

GPL-v3 §5 requires copyright notices be preserved on modified source. The acceptance criterion `grep -ri 'voiceink' Sotto/` returns zero **must carve out** copyright notices in source headers that reference the upstream "VoiceInk" project — those legally cannot be erased.

**Carve-out paths:**
- `LICENSE` (verbatim GPL-v3)
- `README` (must attribute upstream)
- `ACKNOWLEDGMENTS` (new — call out `github.com/Beingpax/VoiceInk` as the parent project)
- Per-file copyright comments where present (preserve verbatim)
- Migration shim code that references the legacy `com.prakashjoshipax.VoiceInk` suite name (legitimate functional use)
- Compiled assets, generated `.strings` files, Sparkle XML history (transient; not actionable until rebuilt)

The grep acceptance criterion becomes: "zero `voiceink` matches in Swift source bodies, ignoring carve-out paths."

#### 7.1.ApplicationSupport — already covered above (§7.1.SwiftData)

The full app-support tree at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/` includes Whisper models (`WhisperModels/`), transcript store, dictionary store, MLX cache. The SwiftData migration shim above moves the whole tree.

#### 7.1.Keychain

`VoiceInk.entitlements` line 36: `$(AppIdentifierPrefix)com.prakashjoshipax.VoiceInk` keychain access group. API keys stored via `KeychainHelper` will be inaccessible after rename.

**Migration shim:** dual-list the keychain access group in entitlements during the transition release (`$(AppIdentifierPrefix)com.prakashjoshipax.VoiceInk` AND `$(AppIdentifierPrefix)com.sotto.Sotto`). On first launch, read existing keys via the old group, re-write to the new group, then drop the old group entitlement in the next release.

---

## Appendix A · Source mockups

Brainstorm session `.superpowers/brainstorm/59608-1778494162/content/`

| Question | File | Lock |
|---|---|---|
| Q1 — Material | `material.html`, `accent-tactical-glass.html` | Tactical Glass + Acid Lime |
| Q2 — Structure | `structure.html` | Bay |
| Q3 — Idle | `idle.html` | Invisible (user-overridden — mockup pre-selected Whisper) |
| Q4 — State cycle | `state-cycle.html` | 7-state morphology, dual-surface |
| Q4.5 — Chip treatment | `chips.html` | Symmetric Glass (user-overridden — mockup pre-selected Asymmetric Command) |
| Q5 — Brand | `brand.html` | Sotto (user-overridden — mockup pre-selected spool) |
| Q6 — Scope | `scope.html` | Recommended |

---

## Appendix B · Tier 3 spikes (open implementation choices)

Surface as plan-level spikes during `/writing-plans`. Not foundation questions — implementation choices the plans should make:

- **B.Domain** — register `sotto.app` vs `sotto.so` vs fallback (`getsotto.com`). ONBOARDING owns when first marketing surface needs the URL. Trademark check (USPTO, EU, restaurants like Sotto Pizza LA) is a pre-marketing gate, not a foundation gate.
- **B.Trademark** — "Sotto" cleared for software class coverage in target markets. RENAME or ONBOARDING owns. Worst case: rename mid-build.
- **B.MultiMonitor** — Bay anchors to `NSScreen.main`; on external-monitor setups `NSScreen.main` may not be the notch display. HUD pair spikes. Decision: anchor to notch display always, or follow keyboard focus.
- **B.ModeList** — reconcile chip prompt-name with `PredefinedPrompts.all` + `AIEnhancementService.customPrompts`. SETTINGS / HUD pairs agree on truncation rule (9 chars uppercase) and the "no prompt selected" fallback (hide left chip).
- **B.FirstAudio** — define VAD-gated first-audio threshold. HUD pair measures real-world mic-init times across hardware classes; threshold pinned at -50 dBFS provisionally.
- **B.ArmingSkip** — `arming → recording` skip when mic init <16ms. HUD pair measures; v1 vs deferred decision.
- **B.SparkleCutover** — see §7.1.Sparkle. RENAME pair documents in PR.
- **B.KeyHandlingDictation** — confirm `Return`/`Esc` pass through to the dictation target during recording. HUD pair tests with Mail / Slack / VSCode.
- **B.HitTest** — opt the right stalactite into hit-testing while keeping the rest of the strip `ignoresMouseEvents = true`. SwiftUI `.allowsHitTesting(true)` per-subview spike.
- **B.FullScreenPolicy** — HUD render policy during Zoom screen-share / Keynote / full-screen apps. Already partially handled by `collectionBehavior: [.fullScreenAuxiliary]`. Confirm screen-sharing visibility is intended (user-confirmable).
- **B.MenubarSpike** — verify `Canvas`/`Path` views in `MenuBarExtra` label closure animate persistently on macOS 14.4 + battery cost acceptable. Fallback: extend `MenuBarIconRenderer` static-NSImage builders.
- **B.W14FConformance** — SETTINGS pair audits shipped W14F surfaces (`ModelsView.swift`, `EnhancementProviderSection.swift`) against §1 vocabulary and files re-skin delta (or marks as conformant).
- **B.DarkLightFlip** — appearance change mid-recording flips menubar tint; non-template states may flash. MENUBAR pair tests.
- **B.UndoCollision** — if hotkey is re-invoked within the 1.5s `committed → idle` window, does it trigger UNDO or start a new recording? HUD pair decides (recommend: new recording wins; UNDO requires explicit chip tap).

---

## Appendix C · Existing-code starting points (per pair)

The most actionable section. For each pair, the files / patterns / line numbers already implementing 60–80% of what they need.

### C.RENAME

- `VoiceInk/VoiceInk.swift` — lines 141, 287 (SwiftData store path with hardcoded `com.prakashjoshipax.VoiceInk`)
- `VoiceInk/VoiceInk.entitlements` — line 9 (CloudKit container), line 31–33 (mach-lookup global names), line 36 (keychain access group)
- `VoiceInk/Info.plist` — line 7–8 (`SUFeedURL`)
- `*.xcodeproj/project.pbxproj` — `PRODUCT_NAME`, `PRODUCT_BUNDLE_IDENTIFIER`
- All `Logger(subsystem:)` call sites — 51 instances, 5 unique subsystems (`grep -rn 'Logger(subsystem:'`)
- Migration shim model: see `StreamingKeysMigration.run()` in `VoiceInk.swift` line 187 — proven pattern for one-shot UserDefaults migration with sentinel.

### C.ICON

- `VoiceInk/Assets.xcassets/menuBarIcon.imageset/` — existing template PNG + `Contents.json` with `template-rendering-intent: template`. Replace with non-template per §5.3.
- `VoiceInk/Assets.xcassets/AppIcon.appiconset/` — existing app icon set, replace all sizes.
- Worst-case asset count: 14 PNGs for app icon (7 sizes × 2 scales). Menubar handled via SwiftUI Canvas — no per-state PNGs.

### C.MENUBAR

- `VoiceInk/Views/Common/MenuBarIconRenderer.swift`:
  - `MenuBarIconRenderer` enum (lines 16–161) — `template()`, `tinted()`, `failed()` builders. Fallback path if Canvas spike fails.
  - `RecordingStateObserver` class (lines 173–220) — **shipping** Combine bridge from `engine.$recordingState` + `HandsFreeSessionService.shared.$state`. Reuse as-is; extend `IconState` to include `.arming`, `.committed`, `.fail`.
  - `MenuBarIcon` view (lines 230–259) — SwiftUI label currently using `Image(nsImage:)`. Replace body with `MenubarGlyph` Canvas view.
- `VoiceInk/VoiceInk.swift` lines 476–502 — `MenuBarExtra` mounting + `.menuBarExtraStyle(.menu)` setup. Comment at line 491 documents the `.window` → `.menu` decision.
- `VoiceInk/Views/MenuBarView.swift` — dropdown contents (untouched by this redesign).

### C.HUD

- `VoiceInk/Views/Recorder/NotchRecorderPanel.swift` (entire file, ~148 lines) — sacred. Single-panel topology, Space-transition handling, `calculateWindowMetrics()`. Renamed but structurally unchanged.
- `VoiceInk/Views/Recorder/HaloMaterial.swift`:
  - `HaloPhase` enum (lines 10–48) — 8 cases, glow color + alpha mapping. Extend to map `.done` 1.5s hold + `.failed` until-dismissed lifetime in `RecorderUIManager`.
  - `VisualEffectBlur` (lines 56–80) — shipping `NSViewRepresentable` wrapper. Reuse.
  - `HaloMaterial<S: Shape>` (lines 107–271) — shipping 8-layer glass compose. Wrap into `TacticalGlass` SwiftUI primitive per §1.1.
  - `AdaptiveGlass` (lines 287–309) — shipping High Contrast token namespace. Reuse for §1.X.A11y HC fallback.
- `VoiceInk/Transcription/Engine/RecordingState.swift` — 6-case enum. Spec states 1–5 + 7 map cleanly; spec state 6 (`committed`) is view-side only.
- `VoiceInk/Views/Common/Palette.swift` — existing tangerine accent. Rename + recolor.

### C.SETTINGS

- `VoiceInk/Views/Settings/SettingsView.swift` — shell to re-skin.
- `VoiceInk/Views/Models/ModelsView.swift` — **W14F shipped** (commit `924f9a6`). Two-tab segmented + focal cards already in place; re-skin to §1 vocabulary only.
- `VoiceInk/Views/AI Models/EnhancementProviderSection.swift` — **W14F shipped**. `ActiveEnhancementProviderCard` + `OtherEnhancementProvidersAccordion`.
- `VoiceInk/Views/Settings/`: `AudioInputSettingsView.swift`, `DiagnosticsSettingsView.swift`, `HandsFreeSettingsView.swift`, `RecorderStylePicker.swift`, `CustomSoundSettingsView.swift`, `EnhancementShortcutsView.swift`, `CommandPaletteSheet.swift`, `AudioCleanupSettingsView.swift` — all need re-skin.
- `VoiceInk/Views/PermissionsView.swift` — first-run-adjacent; coordinates with ONBOARDING.

### C.MAIN

- `VoiceInk/Views/ContentView.swift` — main window root.
- `VoiceInk/Views/MetricsView.swift` + `Views/Metrics/*` — m03 metrics overlay (shipped fdeb92c). Re-skin tiles to §1 vocabulary.
- `VoiceInk/Views/Snippets/` — transcript history surface.
- `VoiceInk/Views/Scratchpad/` — W12.E scratchpad UI.
- `VoiceInk/Views/Dictionary/` — vocabulary + replacements UI.

### C.ONBOARDING

- **Net-new.** No existing onboarding view (monetization stripped). Closest analog is `VoiceInk/Views/Metrics/MetricsSetupView.swift` ("Welcome to VoiceInk" header — repurpose pattern, not content).
- `VoiceInk/Views/PermissionsView.swift` — existing permissions UI, integrate into the new first-run flow.
- `VoiceInk/HotkeyManager.swift` line 21 — `default:` form is first-run-only; existing first-run sentinel pattern for the `⌥ SPACE` reminder dismissal.

> **Scope note:** ONBOARDING pair scope is materially larger than v1 implied because there is no existing onboarding to re-skin. The pair owns design + impl of the welcome flow end-to-end. Notification toast styling (Surface 11) is the smaller half of the pair's work.

