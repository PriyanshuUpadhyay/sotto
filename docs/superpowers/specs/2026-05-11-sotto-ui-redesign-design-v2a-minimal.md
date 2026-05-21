# Sotto · UI redesign design spec

**Date:** 2026-05-11 · revised 2026-05-11 (v2a-minimal)
**Source:** iterative-visual-mockups brainstorm session `59608-1778494162`
**Status:** Foundations locked. v2a-minimal revision applied. Ready for /writing-plans handoff.
**Scope tier:** Recommended (7 teammate pairs · ~3 weeks parallel)

This spec is the output of a 6-foundation visual brainstorm for the VoiceInk fork's UI redesign and rebrand. It locks the visual vocabulary, recording-HUD behavior, lifecycle morphology, brand identity, and scope. Each section: locked choice → reasoning → acceptance criteria.

The spec assumes the reader is familiar with the VoiceInk codebase (`VoiceInk/Views/Recorder/NotchRecorderPanel.swift`, `Assets.xcassets/menuBarIcon.imageset`, the Settings panes) and with the prior W14F Models-pane redesign report.

---

## 0 · Constraints & non-goals

**Hard constraints inherited from upstream:**
- macOS 14.4+ only (SwiftUI 5.0, backdrop-filter equivalents via `NSVisualEffectView`).
- Fork of GPL-v3 `github.com/Beingpax/VoiceInk` — GPL obligations propagate.
- The recording-notch (Dynamic-Island-style overlay) is the SACRED keeper. Redesign builds *on* it; does not remove or relocate it.
- Bundle ID + PRODUCT_NAME + CFBundleDisplayName collide with upstream's installed builds → rename is mandatory.

**Non-goals for this spec:**
- New features (CLI, snippet library, command palette, sound design, marketing site) — deferred to Total tier.
- Refactoring component logic during re-skins — only the visual shell changes; behavior is preserved.
- Cross-platform parity (iOS / Windows / Linux) — out of scope.

---

## 1 · Material

### Locked: Tactical Glass

A hybrid material — liquid-glass surfaces wearing brutalist geometry. Glass refraction does the depth work; geometry + typography do the personality work.

**Surface recipe (every glass surface in the app):**

```css
backdrop-filter: blur(28px) saturate(1.5);
-webkit-backdrop-filter: blur(28px) saturate(1.5);
background: rgba(8, 8, 12, 0.62);
border: 1px solid rgba(255, 255, 255, 0.16);
box-shadow: 0 12px 26px rgba(0, 0, 0, 0.55);
/* NO inner highlight. Outer shadow only. */
```

In SwiftUI: `.background(.regularMaterial)` is **not** sufficient — use a custom `NSVisualEffectView` wrapper with `.material = .hudWindow` and a manually composited overlay for the rgba tint, then a 1px stroke overlay for the hairline.

**Geometry tokens:**

- `corner-radius-glass: 2px` (matte surfaces use 2px corners — most app surfaces)
- `corner-radius-notch-anchored: 8px bottom-only` (Bay HUD + stalactites — match the notch's bottom-radius profile, top edges hard against the notch)
- `corner-radius-zero: 0px` (brackets, dividers, internal tiles)
- `hairline: 1px solid rgba(255,255,255,0.16)` — never thicker
- `spacing-unit: 4px` (tight — most paddings are 8/12/16, not 16/24/32)

**Typography:**

- **Body / sidebar / labels / CTA / transcript: SF Mono** (system-installed; fall back to `ui-monospace`). NOT SF Pro.
- **Tracking:** uppercase labels use `letter-spacing: 0.16em–0.20em`. Body text is `0.02em`.
- **Weights:** 700 for labels/CTAs/titles. 400 for body. No medium/semibold.
- **Prompt glyph:** `›` (U+203A) leads every sidebar item and section label. Color: lime when selected, dim white otherwise. 4–6px right-margin.
- **Glyph role rule:** `›` (U+203A) = navigation items / selected rows / section labels. `▸` (U+25B8) = tappable buttons / CTAs / action triggers.

**Color tokens:**

| Token | Hex | Use |
|---|---|---|
| `--brand-acid` | `#D4FF3A` | brand-mark glow · wordmark · sidebar selected row · section labels · prompt glyph · CTA outline + halo · HUD audio bars |
| `--rec-red` | `#FF3B30` | recording dot · fail state · destructive utility ONLY (never decorative) |
| `--commit-green` | `#30D158` | committed state · success utility ONLY |
| `--trans-cyan` | `#5AC8FA` | transcribing state (sweep + capsule border) |
| `--enh-violet` | `#BF5AF2` | enhancing state (halo breath + arc spin) |
| `--surface` | `rgba(8,8,12,0.62)` | every glass tint |
| `--hairline` | `rgba(255,255,255,0.16)` | every border |
| `--ghost` | `rgba(255,255,255,0.42)` | secondary text on glass |

**Wallpaper bleed-through is required.** Glass without a saturated background under it reads as flat plastic. The OS wallpaper does this work for the notch HUD; for in-app surfaces (Settings, Main window), the app frame uses a subtle gradient backdrop:

```
radial-gradient(at 20% 0%, rgba(110,62,182,0.18), transparent 60%),
radial-gradient(at 100% 100%, rgba(212,255,58,0.06), transparent 50%),
#0d0d10;
```

### Reasoning

Pure glass is pretty but anonymous (Apple's own apps have already taken that ground). Pure brutalism is distinctive but cold. Tactical Glass keeps the material warmth of glass and the personality of brutalism — refraction + brackets + monospace + lime. Distinctive in the cohort (Otter, Whisper, MacWhisper, Wispr Flow, SuperWhisper, Aqua Voice, Krisp, Speakerly all lean either polished-SaaS or flat-marketing).

### Acceptance criteria

- [ ] Every glass surface uses the surface recipe above (no `.regularMaterial` shortcuts).
- [ ] Every text style uses SF Mono. Settings panes that show user-typed content (e.g. a notes textarea) MAY use SF Pro only inside that text content; everything else is mono.
- [ ] Every uppercase label uses `letter-spacing: 0.16em` or greater.
- [ ] Every sidebar/list selected row uses `›` prefix + lime tint.
- [ ] No `border-radius` greater than `8px` anywhere in the app (the Bay HUD's bottom corners are the maximum).
- [ ] No inner highlights (`box-shadow: inset 0 1px 0 ...`). Outer shadows only.
- [ ] All color uses the tokens above. No ad-hoc hex.

---

## 1.X · Accessibility

### Design rules

**Reduce Motion.** Every animated state (arming 1.2s breathe, recording 0.8–1.1s bars, transcribing 1.4s sweep, enhancing 1.6s halo, committed 400ms fade) degrades to an opacity-only fade when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is `true`. A 120ms opacity cross-fade between states satisfies this condition. No looping animations play.

**Color-blind disambiguation.** Committed (green) and fail (red) must not rely on hue alone at settled states. Committed capsule shows a `✓` glyph; fail capsule shows a `✗` glyph (or `!`). These glyphs are the primary differentiator; the color token is a redundant second channel.

**VoiceOver on Bay NSPanel subviews.** `NSPanel` subviews are not automatically exposed to VoiceOver. The following elements require explicit annotations:
- Capsule timer/status text: `accessibilityLabel = "Recording, <mm:ss>"` during recording; `"Transcribing"`, `"Enhancing"`, etc. per state. `accessibilityRole = .staticText`, `accessibilityValue` for the mutable timer string.
- Mode chip (left stalactite): `accessibilityLabel = "Mode: <mode>"`, `accessibilityRole = .staticText`.
- Action chip (right stalactite — `▸ SAVE`, `▸ UNDO`): `accessibilityLabel = "Save"` / `"Undo"`, `accessibilityRole = .button`.

**Animated menubar icon.** State changes must announce to VoiceOver via `accessibilityLabel` updates on `NSStatusBarButton` — not through motion alone. Example: on entering recording, set `button.accessibilityLabel = "Sotto — recording"`. Label updates on every state transition.

**High-contrast.** Leverage the existing `AdaptiveGlass` HC fallback in `HaloMaterial.swift`: under High Contrast, replace translucent blur with opaque fill + 1pt solid state-colored stroke. No new pattern required; HUD pair confirms HC path exercises `AdaptiveGlass` unchanged.

### Acceptance criteria

- [ ] All animated states fall back to 120ms opacity-only fade when `accessibilityDisplayShouldReduceMotion` is on.
- [ ] Committed capsule shows `✓` glyph; fail capsule shows `✗` glyph, independent of color, at all sizes where the glyph is legible.
- [ ] All Bay NSPanel interactive/dynamic subviews have `accessibilityLabel` + `accessibilityRole` (and `accessibilityValue` for the timer).
- [ ] `NSStatusBarButton.accessibilityLabel` updates on every state change.
- [ ] HC mode exercises `AdaptiveGlass` opaque-fill path without modification.

---

## 2 · Structure

### Locked: Bay

The recording HUD = central capsule + two stalactite chips, all anchored to the physical notch.

**Geometry:**

| Element | Width | Height | Position | Corners |
|---|---|---|---|---|
| Central capsule | 220px | 44px | top: 22px (under notch), centered | bottom 8px |
| Left stalactite (MODE) | ~78px | 28px | top: 38px, offset −78px from center | bottom 6px |
| Right stalactite (ACTION) | ~78px | 28px | top: 38px, offset +78px from center | bottom 6px |

All three share the same glass material and hairline. All three live in a **single full-width transparent NSPanel** (matching the existing `NotchRecorderPanel` single-panel architecture); per-element x-offsets handle positioning, and a shared `RecorderState` observable handles state management.

**Material:**

- Central capsule: full Tactical Glass recipe with a red halo during recording (`box-shadow: 0 0 28px rgba(255,59,48,0.28)`) — the halo color is state-dependent, see Section 4.
- Stalactites: same recipe, no halo. They are status displays + tap targets.

**Chip treatment (Q4.5 lock): Symmetric Glass.**

Both chips wear identical material — dark glass tint, white hairline, 6px bottom-radius, lime SF-Mono text. They are visually equal-weight; the right chip has a leading `▸` glyph to indicate tappability. Content per phase:

| Phase | Left chip | Right chip |
|---|---|---|
| arming | (hidden — chips only appear during recording) | (hidden) |
| recording | active mode (modes per `AIEnhancementService`; see Appendix B) | `▸ SAVE` |
| transcribing | (collapsed — no user action available) | (collapsed) |
| enhancing | (collapsed) | (collapsed) |
| committed (1.5s) | (collapsed) | `▸ UNDO` |
| fail | (collapsed) | (collapsed — error code lives in capsule) |

Chips fade out for 140ms when transitioning into transcribing; fade in for 220ms when returning to recording. They never animate independently — always sync to the capsule's transitions.

### Reasoning

- "Drop" (single capsule) is too thin: ~6 affordances competing for ~1 chip slot.
- "Strip" (full-width drop) eats 44px of screen height permanently — aggressive on 13" MacBooks.
- "Bay" threads the needle: keeps the notch metaphor pure (HUD grows from the notch, doesn't replace the menubar), exposes two power-user affordances (mode + primary action), and animates as a coordinated ecosystem.

Symmetric Glass chips (not Asymmetric Command) were chosen because the user prefers the clean visual continuity of twin glass objects over the explicit hierarchy of a label/button split. The eye learns the `▸` glyph = tappable convention quickly; symmetric chips give the design a quieter, more confident posture.

> *Note: brainstorm mockup pre-selected "Asymmetric Command" as recommended; user override locked "Symmetric Glass". Pairs implement Symmetric.*

### Acceptance criteria

- [ ] HUD lives in `Sotto/Views/Recorder/NotchRecorderPanel.swift` (renamed from VoiceInk). All three surfaces (capsule + two stalactites) are SwiftUI views within a **single** transparent NSPanel — not separate windows.
- [ ] Central capsule, left stalactite, right stalactite are three separate views with shared `RecorderState` observable.
- [ ] Stalactites enter/exit synchronized with the capsule's state transitions (single animation driver).
- [ ] Right stalactite is keyboard-actionable (`Return` triggers, `Esc` cancels) AND click-actionable.
- [ ] Tap targets are 28×60+ px minimum (Apple HIG min 44pt is relaxed since these are mouse targets, but the visible chip width is the tap target — no extra invisible padding).
- [ ] Stalactites use shared NSPanel hosting — no separate windows per chip; performance budget is the same as today's single-panel HUD.

---

## 3 · Idle

### Locked: Invisible

When the app is not recording, the HUD is fully absent. The notch is the bare hardware notch. No glass, no breathing dot, no shortcut hint, no whisper.

**The menubar icon carries all idle-state presence.** See Section 4 for the menubar icon's idle rendering and Section 5 for the icon glyph.

### Reasoning

The user explicitly rejected ambient whispers and persistent identity. The principle: the app respects the notch as hardware; it summons a feature *on top* of the notch when invoked, and recedes when done. This matches the notch-as-affordance metaphor cleanly — the magic is in the summoning, not the squatting.

The menubar icon is the only persistent surface. It is small, monochrome by default, and macOS users already expect menubar icons to indicate background-app presence. The icon's state-morphology (Section 4) means presence and state are communicated through that single surface without consuming visual real-estate.

> *Note: brainstorm mockup pre-selected "Whisper" as recommended; user override locked "Invisible". Pairs implement Invisible.*

### Acceptance criteria

- [ ] `NotchRecorderPanel` is hidden (`orderOut(_:)` + `alphaValue = 0`) in idle state. The panel remains allocated; `orderOut` removes it from the screen list without releasing the object.
- [ ] No backdrop-filter views render in idle.
- [ ] Menubar icon renders the `idle` variant (see Section 4).
- [ ] Cursor approaching the top of the screen does NOT reveal the HUD (rejected: shortcut-hint pattern).
- [ ] First-run / onboarding may show a one-time `⌥ SPACE` reminder toast, but it must dismiss permanently after first invocation.

---

## 4 · State grammar

### Locked: 7 states, dual-surface morphology

The lifecycle has 7 named states. Each state has a defined color, motion, timing, and parallel expression on both the notch HUD and the menubar icon. Transitions are unidirectional; the only loops are within-state (breathe / pulse / blink).

```
idle → arming → recording → transcribing → enhancing → committed → idle
                          ↘ (skip enhancing if mode = RAW)        ↗
   any state → fail → (user dismisses) → idle
```

### State table

| # | State | Color | Notch HUD | Menubar icon | Enter | Loop | Exit |
|---|---|---|---|---|---|---|---|
| 1 | **idle** | — | hidden | bare glyph (non-template; lime underscore, mark adapts to appearance) | — | static | 120ms ease-out |
| 2 | **arming** | `#D4FF3A` | empty bay capsule fades in; lime border breathes (0.4↔0.9 alpha); ghost lime dot pulses; mono label "LISTENING"; no stalactites | bare glyph pulses (0.55↔1.0 alpha) | 180ms ease-out | 1.2s breathe | → recording on first audio (typically <500ms) |
| 3 | **recording** | `#FF3B30` + `#D4FF3A` | red dot pulses 1.0s; lime audio bars animate (5 bars, 0.8–1.1s staggered); mono `REC mm:ss` timer; stalactites visible: `[MODE] [▸ SAVE]` | glyph fills (inverse — black bg, white bars); red dot badge in top-right corner, pulses 1.0s | 220ms (capsule + stalactites synced) | bars 0.8–1.1s · dot 1.0s | → transcribing on stop |
| 4 | **transcribing** | `#5AC8FA` | cyan sweep across capsule L→R 1.4s linear; bars freeze faint cyan; mono "TRANSCRIBING…"; stalactites collapsed | glyph swaps to 3 bouncing dots (**non-template** — animation requires live rendering) | 140ms (stalactites retract) | 1.4s shimmer sweep | → enhancing OR committed |
| 5 | **enhancing** | `#BF5AF2` | violet halo breathes 1.6s around capsule (0.25↔0.6 alpha); bars stay faint violet; mono "ENHANCING…" | glyph hollows out + 270° arc spins inside, 1.6s linear | 200ms cross-fade from transcribing | 1.6s halo breath · 1.6s arc spin | → committed on completion |
| 6 | **committed** | `#30D158` | green `✓` center + green halo; mono `PASTED` or `SAVED`; right stalactite shows `▸ UNDO` for 1.5s | green dot badge in top-right corner | 120ms snap | hold 1.5s | 400ms fade → idle |
| 7 | **fail** | `#FF3B30` | red `✗` border blinks 0.8s; mono error code (e.g. `ERR · NO_DEVICE`, `ERR · MODEL_LOAD`) | red `!` badge in top-right corner; bare glyph | 120ms snap | 0.8s blink until dismissed | click HUD or icon → idle |

### Motion atoms

All keyframes are defined in `Sotto/Theme/MotionTokens.swift` (new file). The CSS keyframes from the mockups (`pulse`, `bar1–4`, `shimmer`, `sweep`, `breathe`, `blink`, `dotJump`, `spin`) translate directly to SwiftUI `withAnimation(.easeInOut(duration:).repeatForever(autoreverses:))` patterns or `Animation.linear(duration:).repeatForever(autoreverses:false)` for the unidirectional ones (sweep, spin).

### Reasoning

- **Distinct colors for transcribe/enhance vs. lime-everywhere:** cyan + violet were chosen for legibility. The user must distinguish "audio → text" (deterministic, fast) from "text → enhanced text" (LLM, slower, may fail differently). Three motion-only states (recording bars vs. transcribe shimmer vs. enhance breath) is too much for the eye to parse at a 1s glance. Color adds a redundant channel.
- **`arming` state preserved:** the ~500ms breath between hotkey-press and first audio gives the surface room to enter dignified. Without it, the HUD pops in mid-recording, which reads as glitchy.
- **`committed` hold = 1.5s:** long enough to register, short enough not to block. The `▸ UNDO` chip is a hard-tested affordance — without it, accidental commits to the wrong app are unrecoverable.
- **Fail must be dismissed, never auto-times-out:** errors that vanish unread cause silent data loss. User must acknowledge.

### Acceptance criteria

- [ ] All 7 states implemented in `Sotto/Models/RecorderState.swift` enum, with associated values for in-flight data (`recording(duration: TimeInterval, mode: EnhancementMode)`, `fail(code: ErrorCode, message: String)`, etc.).
- [ ] State transitions are explicit — no setter on `RecorderState`; transitions go through `RecorderStateMachine.transition(to:)` which validates legality.
- [ ] Motion timing matches the table above to ±20ms tolerance.
- [ ] Color tokens from Section 1 are used; no per-state ad-hoc colors.
- [ ] Menubar icon updates within 50ms of notch HUD state change (same observable subscription).
- [ ] `arming` state is skippable if mic init takes <16ms (one frame) — direct jump to `recording` to avoid stutter.
- [ ] Fail state shows error code in monospace uppercase (`ERR · {DOMAIN}_{REASON}`).
- [ ] Stalactite content matches the phase table in Section 2.

---

## 5 · Brand

### Locked: Sotto

**Name:** `Sotto` — from Italian *sotto voce*, "under one's voice." References the stage-aside whisper. Title-cased, five letters, pronounceable in major Romance and Germanic languages.

**Wordmark:**

```
Sotto.
```

- Typeface: SF Mono Bold (700)
- Case: Title case (cap S, lowercase otto)
- Tracking: `+0.02em`
- Trailing stop: heavy lime period (`#D4FF3A`, font-weight 900, `margin-left: 2px`)
- Glow on stop: `text-shadow: 0 0 12px rgba(212,255,58,0.7)` (used in marketing/hero only; not in-app)

The wordmark is a single token. Never break across lines. Never replace `.` with `,` or remove it. The trailing stop is the brand-mark.

**Tagline (marketing):** `› sotto voce · under your voice`

**Icon glyph (universal mark):**

Two strokes — a vertical mark above a heavy horizontal underscore. Reads as the typographic "below" notation or a single-tally annotation. The mark is white (or appearance-adapted); the underscore is the brand lime.

Proportions (relative to canvas square `S`):
- Mark: width = 0.18 × S, height = 0.55 × S
- Underscore: width = 1.00 × S (or 0.92 × S inset for app icon), height = 0.14 × S
- Gap between mark and underscore: 0.08 × S
- Mark vertically centered above the underscore-mark composite; composite vertically centered in canvas

**Size variants:**

| Size | Render | Tint mode |
|---|---|---|
| 1024 (App / Dock) | Full mark + full underscore. Lime underscore with halo (`0 0 32px rgba(212,255,58,0.6)`). White mark with subtle halo. | Non-template (rendered as-is) |
| 256 / 128 / 64 (Spotlight, Finder, Notification Center) | Same proportions; halos compressed | Non-template |
| 32 (Notification) | Mark + underscore, no halo | Non-template |
| 16 (Menubar — all states) | Mark + underscore. Lime underscore preserved at all sizes; mark color adapts to `NSAppearance` (white on dark menubar, `#1C1C1E` on light). State-specific badge or animation per §4. | **Non-template** (lime underscore requires color preservation; app handles appearance adaptation manually) |

**Stateful menubar icon:**

The menubar icon morphs across all 7 lifecycle states. See Section 4's table for the per-state rendering. Implementation: an `NSStatusItem` via `MenuBarExtra` label with pure-SwiftUI `Canvas`/`Path` views (preferred — enables animation; needs 1-day spike on macOS 14.4 specifically, see Appendix B) OR `button.image` set from state-keyed assets.

**Icon assets to generate:**

- `Sotto/Assets.xcassets/AppIcon.appiconset/` — 1024, 512, 256, 128, 64, 32, 16 at 1x and 2x (Apple icon spec)
- `Sotto/Assets.xcassets/MenubarIcon-idle.imageset/` — 16×16, 18×18, 22×22 (1x, 2x, 3x) non-template
- `Sotto/Assets.xcassets/MenubarIcon-recording.imageset/` — non-template variants
- (one imageset per state OR a single SwiftUI `MenubarGlyph` view with state binding — recommended approach)

### Reasoning

- **Sotto wins on distinctiveness.** Among the cohort (Otter, Whisper, MacWhisper, Wispr Flow, SuperWhisper, Aqua Voice, Krisp, Speakerly), every other product names the *thing it does* (whispering, hearing, listening). Sotto names *how* — quietly, underneath, in the margin. The word is poetic without being pretentious.
- **Domain availability** assumed for `sotto.app` and `sotto.so`; if registrar checks fail, fallback to `getsotto.com` or `try-sotto.com`. (Verify before shipping marketing — see Appendix B.)
- **The risk noted in the brainstorm — that Sotto's title-case + Italian register disagrees with the lowercase-mono design system — is real but acceptable.** The wordmark is the *brand surface*; the rest of the app uses lowercase mono. The wordmark is the one place the brand permits itself a Title.
- **Icon glyph reasoning:** the two-stroke composition (mark + underscore) is the most reduced expression of "under" possible. It scales from 1024 to 16 without losing its read. The lime underscore at large sizes is the brand-mark; at menubar size, it becomes a unified bar.

> *Note: brainstorm mockup pre-selected "spool" as recommended; user override locked "Sotto". Pairs implement Sotto.*

### Acceptance criteria

- [ ] App rename: `PRODUCT_NAME`, `CFBundleDisplayName`, `CFBundleName`, `CFBundleIdentifier` (suggest `com.sotto.Sotto` — verify no collision via `mdfind`), all marketing URL references (`tryvoiceink.com` → `sotto.app` or placeholder), brew cask name, Sparkle update feed URL.
- [ ] All icon assets generated and added to `Sotto.xcodeproj`.
- [ ] Menubar icon implemented as a SwiftUI `MenubarGlyph` view bound to `RecorderState`; one view, one binding, rendered into the `NSStatusItem`.
- [ ] Wordmark Swift constant: `BrandMarks.wordmark = "Sotto."` with a `BrandMarks.styledWordmark()` view returning an `AttributedString` rendering of the wordmark with the stop colored `--brand-acid`.
- [ ] All on-screen instances of "VoiceInk" or "voiceink" are replaced. `grep -ri 'voiceink' Sotto/` returns zero hits at PR-ready time (except: `LICENSE`, `README`, `ACKNOWLEDGMENTS`, GPL-v3 source copyright headers — see §7.1 for the migration carve-outs).

---

## 6 · Scope

### Locked: Recommended (7 teammate pairs · ~3 weeks parallel)

The redesign covers every surface the user *actually sees* during normal use. New features (CLI, command palette, marketing site, snippet library) are deferred.

### Surfaces in scope (11)

| # | Surface | Pair | Notes |
|---|---|---|---|
| 1 | App rename + bundle ID | RENAME | bundle ID change, Sparkle feed, brew cask, marketing URL references |
| 2 | App icon assets | ICON | all sizes 1024 → 16, non-template menubar variants |
| 3 | Stateful menubar icon | MENUBAR | `MenubarGlyph` SwiftUI view + state machine binding |
| 4 | Notch HUD | HUD | Bay structure, Symmetric Glass chips, 7-state morphology, idle:invisible |
| 5 | Settings shell (sidebar nav, frame) | SETTINGS | new sidebar with mono items + ›-prompts, tactical-glass header/footer |
| 6 | Models pane | SETTINGS | absorb W14F redesign: Enhancement/Transcriber segmented + ACTIVE PROVIDER focal card |
| 7 | General / Recorder / Hotkeys / Permissions panes | SETTINGS | re-skin, no logic changes |
| 8 | AI Models / Audio Input panes | SETTINGS | re-skin |
| 9 | Main window (transcript / history) | MAIN | sidebar with mono items + lime active row, main pane with section labels + transcript body |
| 10 | Onboarding / welcome | ONBOARDING | wordmark, first-run permissions flow, single `⌥ SPACE` reminder |
| 11 | Notification toasts | ONBOARDING | tactical-glass cards with Sotto colors |

### Teammate pair assignments (7 pairs)

| Pair | Responsibilities | Dependencies |
|---|---|---|
| RENAME | Surface 1 (rename + bundle ID + Sparkle + brew + URLs) | None — runs first or in parallel |
| ICON | Surface 2 (icon assets) | None |
| MENUBAR | Surface 3 (stateful menubar icon) | RENAME (for bundle ID), ICON (for template glyph source) |
| HUD | Surface 4 (notch HUD redesign + state machine) | RENAME (for view file paths) |
| SETTINGS | Surfaces 5–8 (Settings shell + all 6 panes) | RENAME |
| MAIN | Surface 9 (main window) | RENAME |
| ONBOARDING | Surfaces 10–11 (onboarding + toasts) | RENAME, HUD (state colors used in toasts) |

RENAME is on the critical path; everyone else can start once it lands. ICON has no dependencies and can run end-to-end in parallel.

### Deferred (7 items — backlog post-redesign)

These are NOT cancelled — they become the next backlog after the redesign ships:

- Sound design (commit click, arming up-spool, fail negatone)
- Marketing site (`sotto.app` landing page with state-cycle showcase)
- CLI parity (`sotto rec` / `sotto transcribe` / `sotto whisper` / `sotto modes`)
- Quick-paste palette (`⌘⇧V`, tactical-glass dropdown over the caret)
- Snippet library UI (saved transcripts, tagged, searchable)
- Voice memo timeline / gantt view (scrubbable history)
- Custom enhancement-mode editor (user-defined prompts)

### Reasoning

- **Minimal (3 pairs)** would ship a coherent notch on top of an incoherent app. Users open Settings and feel the seam every time.
- **Total (11 pairs)** is the right north star but most of its tail is feature work, not redesign work. CLI parity alone is a 2-week project. Marketing site needs copy/photography/hosting.
- **Recommended** is the redesign: make every existing screen the user sees agree with Sotto's vocabulary, and stop at the boundary where new features start.

### Acceptance criteria

- [ ] All 11 surfaces listed are touched and conform to Sections 1–5.
- [ ] No surface ships partially redesigned (e.g. Settings sidebar redesigned but pane content untouched — would create a worse seam than not redesigning at all).
- [ ] Deferred items are filed as GitHub issues with `redesign-followup` label before the redesign branch merges.
- [ ] PR description for each pair links back to this spec doc.

---

## 7 · Handoff

This spec is complete. Next steps (out of scope for the iterative-visual-mockups brainstorm):

1. **User reviews this spec.** Team-lead handles the review loop.
2. **`/writing-plans` is invoked** with this spec as input. Produces an implementation plan per pair (RENAME, ICON, MENUBAR, HUD, SETTINGS, MAIN, ONBOARDING) — 7 plans total.
3. **Plans are dispatched** via `superpowers:subagent-driven-development` or `superpowers:dispatching-parallel-agents` — one teammate pair per plan, working in parallel.
4. **Each pair lands its own PR**, reviewed by the team-lead pair-reviewer, merged to a `redesign/sotto` integration branch.
5. **Integration branch** is QA'd holistically (the seam between RENAME and the other surfaces is the highest risk — verify no `voiceink` strings leak in error messages, log files, or UserDefaults keys).
6. **Final merge to main** + brew cask update + Sparkle feed cutover.

---

## 7.1 · Migration

The bundle-ID rename (§5, §7) creates seven categories of data orphaned in the old namespace. RENAME pair owns this section; every row must be resolved before the integration branch ships.

| Category | Old identifier / path | Policy |
|---|---|---|
| **UserDefaults** (~56 `@AppStorage` keys) | `UserDefaults(suiteName: "com.prakashjoshipax.VoiceInk")` | Migration shim on first launch: read old suite, copy non-default values to new suite. Old-key reads in the shim are explicitly carved out of the `grep` clean criterion. |
| **SwiftData store** | `~/Library/Application Support/com.prakashjoshipax.VoiceInk/` (`VoiceInk.swift` lines 141, 287) | Move-and-symlink old path to new path on first launch, before SwiftData initialises. Existing transcript history is preserved. |
| **CloudKit container** | `iCloud.com.prakashjoshipax.VoiceInk` (`VoiceInk.entitlements`) | Accept data loss for v1: new container starts empty. Add first-run notice: "iCloud sync data was not migrated; please re-sync your custom Vocabulary." |
| **Sparkle update channel** | `beingpax.github.io/VoiceInk/appcast.xml` | Bundle ID change orphans existing VoiceInk installs from Sparkle's channel. Ship a final "Install Sotto" notice on the old feed (or via `tryvoiceink.com` banner) before cutover. No in-app cross-version update path. RENAME pair documents cutover timing. |
| **OSLog subsystem strings** (~30 literals) | `"com.prakashjoshipax.voiceink"` | Rename in-place; covered by `grep` clean criterion. |
| **Application Support directory** | `~/Library/Application Support/com.prakashjoshipax.VoiceInk/` | Rename or move-and-symlink on first launch (handled by SwiftData row above; same path operation). |
| **GPL-v3 copyright headers** | Per-file `// Copyright … VoiceInk` in source files | Per-file audit BEFORE bulk rename. GPL-v3 §5 requires copyright notices stay intact. Source-header references to "VoiceInk" are explicitly carved out of the `grep` clean criterion. |

---

## Appendix A · Source mockups

Brainstorm session: `.superpowers/brainstorm/59608-1778494162/content/`

| Question | File | Lock |
|---|---|---|
| Q1 — Material | `material.html`, `accent-tactical-glass.html` | Tactical Glass + Acid Lime |
| Q2 — Structure | `structure.html` | Bay |
| Q3 — Idle | `idle.html` | Invisible (menubar carries presence) |
| Q4 — State cycle | `state-cycle.html` | 7-state morphology, dual-surface |
| Q4.5 — Chip treatment | `chips.html` | Symmetric Glass |
| Q5 — Brand | `brand.html` | Sotto |
| Q6 — Scope | `scope.html` | Recommended |

## Appendix B · Open questions deferred to plans

These are not foundation questions — they're implementation choices the plans should make:

- **Domain registration** (`sotto.app` vs. `sotto.so` vs. fallbacks) — verify with registrar BEFORE ONBOARDING pair starts. Fallback: `getsotto.com` or `try-sotto.com`.
- **"Sotto" trademark clearance** — USPTO software-class search BEFORE foundation lock is enforced on RENAME. "Sotto" overlaps restaurant brands and Italian SaaS products; verify clearance before any public shipping.
- **Sparkle update feed URL** (under `sotto.app/appcast.xml` or CDN) — RENAME pair decides. Cutover policy: old `beingpax.github.io/VoiceInk/appcast.xml` feed ships a final "Install Sotto" notice; new feed is a clean channel. Existing installed users are NOT auto-migrated via Sparkle (see §7.1).
- **Menubar icon rendering** — `MenuBarExtra` label with `Canvas`/`Path` SwiftUI views (preferred) vs. static imagesets. MENUBAR pair spikes on macOS 14.4 before committing; battery cost must be measured. See §5 acceptance for the resolution direction.
- **`arming → recording` skip** — §4 acceptance marks this REQUIRED in v1 (direct jump to `recording` when mic init <16ms). HUD pair to spike and measure; expected to ship but may be flagged if unmeasurable on hardware. Previous deferral in this appendix is superseded by the §4 acceptance criterion.
- **"First audio" detection** — arming → recording transitions "on first audio (typically <500ms)". Exact definition: VAD-gated? energy threshold? Cumulative energy over N frames? HUD pair to define and document in `RecorderStateMachine`.
- **Mode list reconciliation** — chip treatment (§2) and state machine (§4) reference `EnhancementMode` cases per `AIEnhancementService`. SETTINGS pair to verify exact mode names/enum cases against existing code before SETTINGS PR ships.
- **Right stalactite keyboard handling during dictation** — `Return` triggers SAVE, `Esc` cancels. During recording the user is dictating into another app; if `NotchRecorderPanel` becomes key it steals Return/Esc from the target app. HUD pair to resolve: either panel stays non-key (chip receives no keyboard events) or key-capture is scoped to the chip only. Both choices have UX trade-offs.
- **HUD click-through** — is the central capsule click-blocking or click-through? Stalactite chips are explicit tap targets; the capsule is status-only. HUD pair to confirm `ignoresMouseEvents` behavior per subview region, consistent with existing `NotchRecorderPanel` passthrough policy.
- **Full-screen / screen-share / Zoom** — does the Bay HUD render during full-screen apps, Keynote presentations, Zoom calls, or screen-share? HUD pair to define `NSPanel.collectionBehavior` explicitly (existing panel uses `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` — verify adequate).
- **Multi-monitor / external-display HUD anchoring** — which screen does the HUD anchor to on a non-notch external monitor? Fallback notch width is 180px; Bay capsule is 220px wide. HUD pair to define anchoring policy for non-notch screens.
- **W14F Models-pane integration** — `git status` shows W14F redesign as untracked report files only; no committed implementation on main. SETTINGS pair to verify scope before PR: is this a re-skin of the existing pane or net-new feature work? If net-new, SETTINGS pair flags and scopes separately before starting.
