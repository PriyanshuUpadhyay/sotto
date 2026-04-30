# W13.F — History Window Glass + Animation Codemod Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax. Reviewer is `superpowers:code-reviewer`.

**Date:** 2026-04-30
**Author:** planner-w13f (team `voiceink-phase23`, task #22)
**Sources:**
- Master plan §4 W13.F: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`
- R4 audit (the WHY for every site below): `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md` rows #5, #16
- Sibling shape (sweep + flag, animation codemod): `docs/superpowers/plans/W13A-token-sweep.md`
- Window flag pattern (mirror target): `VoiceInk/WindowManager.swift:19-48` (`configureWindow`)
- Glass primitives: `Palette.swift` / `GlassChip.swift` / `Animation+Halo.swift` / `AdaptiveGlassBackground.swift` / `HaloMaterial.swift` (under `VoiceInk/Views/Common/` + `VoiceInk/Views/Recorder/`)

**Goal:** flip the standalone History `NSWindow` from opaque chrome to non-opaque glass and codemod its ad-hoc animation literals to the named `Animation.halo*` tokens. Two surfaces, four chrome edits, five animation-literal swaps. No structural rebuilds — we mirror the W8 main-window contract into `HistoryWindowController.createHistoryWindow` and surgically drop the four `Color(NSColor.windowBackgroundColor / .controlBackgroundColor)` calls in `TranscriptionHistoryView` that defeat the wallpaper-glass pipeline.

**Why now:** Q8=a (master plan §0) signed off "Keep History as separate window". So we can't retire `HistoryWindowController`; we have to fix W8's missing flags here. The audit (R4 row #16, "Σ 20") flagged this as the 5th-worst cohesion offender — opaque box pops where every other VoiceInk surface (main window, recorder, mini, notch) reads as glass-on-wallpaper. The audit also calls out the fix as one-line-per-flag-site; this packet executes that.

**Architecture (per-axis sweep / defer / flag table):**

```
Axis                                        Source token                                     Target / disposition
─────────────────────────────────────       ─────────────────────────────────                ─────────────────────────────────
A. NSWindow opaque flags                    window.backgroundColor = .windowBackgroundColor  window.backgroundColor = .clear
   (HistoryWindowController only)           (default isOpaque == true)                       window.isOpaque = false
                                                                                             — mirror WindowManager.configureWindow:36-41

B. Sub-pane opaque NSColor fills            Color(NSColor.windowBackgroundColor)             drop overlay or → adaptiveGlassBackground / HaloMaterial
   (TranscriptionHistoryView)               Color(NSColor.controlBackgroundColor)            (per-site detail in §Replacement table)

C. Raw .thinMaterial chip → glassChip       RoundedRectangle 8pt + .fill(.thinMaterial)      .glassChip(cornerRadius: 8)
   (search field at :184)                                                                     (HStack content; drop the surrounding rect)

D. Ad-hoc animation literals → Halo tokens  withAnimation(.smooth(duration: 0.3))            withAnimation(Animation.haloExpand)
   (5× analysis-panel + selectionToolbar)   .animation(.smooth(duration: 0.3), value: …)     .animation(Animation.haloExpand, value: …)
                                                                                             — generic "smooth" → reveal-class anim
                                                                                               (per W13.A migration table point 4)
```

**Tech Stack:** Swift 5.x, SwiftUI, AppKit (`NSWindow` + `NSColor`), Xcode 16.x. Build via `make local` (~3 min cold) at merge time. No new dependencies. No new tests.

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens), §1.X (W8 wallpaper-glass contract — `NSWindow` must be `isOpaque=false` + `.clear` so the SwiftUI root's `.adaptiveGlassBackground()` can paint behindWindow), §2.4 (motion grammar — four named tokens). Master plan §4 W13.F. Q-decision Q8=a.

**Q-decisions honored (from master plan §0):**
- **Q8=a** — History stays a separate `NSWindow`. We FIX the W8 flag drift in-place, not retire the window. This packet does NOT collapse history into `ContentView`.

**CLAUDE.md cadence rules respected:**
- **Single feat commit at merge** (per dossier). The plan-file lands as a separate `docs(plans):` commit; the codemod lands as a single `feat(aesthetic): W13F — history window glass + animation codemod` commit.
- **Single integration build at merge time** (per `feedback_skip_per_packet_builds.md`). No `make local` per task. One `xcodebuild build` at the end.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** Inline doc-comment that lands at the new `isOpaque=false` line cites W8 spec + this plan path; no PR numbers.
- **Pre-existing spec-ref comments preserved** (`Animation+Halo.swift:14-17` reviewer note, `HaloMaterial.swift` §2.3 / §6.4, `Palette.swift` §1).

**Worktree:** ABSOLUTE path `.worktrees/w13f/`. Do not work on the main repo working tree.

---

## File structure

### New files

None. W13.F is a flag flip + four chrome edits + animation codemod. No new vocabulary primitives.

### Modified files (2 total)

- `VoiceInk/HistoryWindowController.swift` — `createHistoryWindow:32-65` window flag flip (axis A).
- `VoiceInk/Views/History/TranscriptionHistoryView.swift` — four sub-pane chrome edits (axis B + C) + 5× animation literals (axis D).

### Excluded files (DO NOT touch — explicit list, coder do not drift)

**Out of scope per master plan / W13.A deferral list:**

- `VoiceInk/Views/History/InlineHistoryView.swift` — that's the inline history INSIDE main `ContentView` (W13.D's territory for the cardListView Form-host purge; W13.A already swept its non-Form animations).
- `VoiceInk/Views/History/TranscriptionDetailView.swift` — center-pane detail view; W13.A swept its animations; structural is OOS.
- `VoiceInk/Views/History/TranscriptionListItem.swift` — left-sidebar row; W13.A swept its accent + animation.
- `VoiceInk/Views/History/HistoryShortcutTipView.swift` — center-pane empty-state tip card with `Color(NSColor.controlBackgroundColor).opacity(0.5)` at :40 — routed to W13.G polish per W13.A axis-G defer table.
- `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift` — PAPV is rendered AS the analysis-panel overlay content. It paints its own `Color(NSColor.windowBackgroundColor)` at :20 and `Color(NSColor.controlBackgroundColor)` at :109. Those are W13.B residual debt; **flagged in §Follow-ups** but NOT swept here (would expand the diff into Metrics territory).

**Glass primitive files (UNTOUCHED — vocabulary source-of-truth):**

- `VoiceInk/Views/Common/GlassChip.swift`
- `VoiceInk/Views/Common/GlassCard.swift`
- `VoiceInk/Views/Common/Palette.swift`
- `VoiceInk/Views/Common/Animation+Halo.swift` (preserve reviewer note at :14-17)
- `VoiceInk/Views/Common/AdaptiveGlassBackground.swift`
- `VoiceInk/Views/Recorder/HaloMaterial.swift`

**Window manager (REFERENCE only — do not edit):**

- `VoiceInk/WindowManager.swift` — we copy the flag pattern from `configureWindow:36-41`; do NOT edit.

**Tests:**

- `VoiceInkTests/*.swift` and `VoiceInkUITests/*.swift` — out of W13.F scope. No new tests.

---

## Migration policy (resolves ambiguity for each design point)

1. **Window flag flip mirrors `WindowManager.configureWindow` literally — no extra additions.** The reference at `WindowManager.swift:36-41` sets:
   ```
   window.backgroundColor = .clear
   window.isReleasedWhenClosed = false
   window.title = "VoiceInk"
   window.collectionBehavior = [.fullScreenPrimary]
   window.level = .normal
   window.isOpaque = false
   ```
   `HistoryWindowController.createHistoryWindow` already sets `isReleasedWhenClosed`, `title`, `collectionBehavior`. The two MISSING bits are `backgroundColor = .clear` (currently `= .windowBackgroundColor`) and `isOpaque = false` (currently default `true`). We flip exactly those two fields. We do NOT add `level = .normal` — `NSWindow` defaults to `.normal`, and adding it explicitly creates a documentation lie if the default ever changes upstream. We do NOT touch `titleVisibility` — `HistoryWindowController.createHistoryWindow:53` keeps it `.visible` (history window has a real `"VoiceInk — Transcription History"` title that users want to see, unlike the main window's `.hidden` titlebar).

2. **`backgroundColor` change is one-token, not "use Palette".** `NSColor` ≠ `Color`. The window's `backgroundColor` property is `NSColor`-typed; `.clear` is `NSColor.clear`. We do NOT introduce a `Palette.glassBg` token — none exists, and the spec is explicit that the wallpaper bleeds through via `NSVisualEffectView .behindWindow` painted by `.adaptiveGlassBackground()` on the SwiftUI root. The window itself is a *transparent host*; the SwiftUI content paints the visible material.

3. **`.adaptiveGlassBackground()` is NOT added at the hosting-controller level.** The `TranscriptionHistoryView.body` already paints its own backdrops on each pane: `leftSidebarView` uses `HaloMaterial(shape: Rectangle(), phase: .hidden, appearance: glassAppearance.current)` at :248-252; the empty-state `centerPaneView` uses the same at :296-300. So the glass IS painted; only the four sub-pane opaque overlays defeat it. We surgically drop those overlays. We do NOT add a new pane-level `.adaptiveGlassBackground()` modifier — that would double-glass with `HaloMaterial` and risk visible chrome shifts.

4. **Sub-pane opaque overlays — drop or replace per site context.** Decision rules per site:
   - If the inner content already paints its own backdrop (PAPV at :133), the outer `.background(Color(NSColor.windowBackgroundColor))` is a redundant double-paint. **Drop entirely.** Wallpaper visibility is handled by the panel's own backdrop; we just stop overpainting it with system-window-background blue/grey.
   - If the empty state has no own backdrop (right-sidebar at :321), drop `.background(Color(NSColor.controlBackgroundColor))` and apply `.background(HaloMaterial(shape: Rectangle(), phase: .hidden, appearance: glassAppearance.current))` — matches the established `leftSidebarView` + `centerPaneView` pattern in the same file.
   - If the surface is a floating chrome strip with shadow (selectionToolbar at :391-394), the existing `Color(NSColor.windowBackgroundColor).shadow(...)` was a bottom-floating bar with up-shadow. Replace fill with `HaloMaterial`; preserve the up-shadow as a separate `.shadow(...)` modifier on the toolbar HStack (so the glass strip still casts a hint-shadow over the rows below it).

5. **Search-field `.thinMaterial` swap is THE one axis-C site in this packet.** Per W13.A's axis-C defer entry (`TranscriptionHistoryView.swift:184` → defer to W13.F), the `RoundedRectangle 8pt + fill(.thinMaterial)` background is a hand-rolled chip vocabulary. Replace with `.glassChip(cornerRadius: 8)` modifier on the HStack. The current `.padding(10)` outside the rect becomes redundant — `glassChip` adds its own paddingH=11 / paddingV=7 (close to 10/10). Net visual change: ~1pt horizontal expansion, ~3pt vertical compression. Acceptable; matches the chip vocabulary across the rest of the app.

6. **Animation codemod table** (codifies axis D — exact mapping per W13.A §Migration policy point 4):

   | Source literal                       | Halo token             | Rationale                                |
   |--------------------------------------|------------------------|------------------------------------------|
   | `.smooth(duration: 0.3)`             | `Animation.haloExpand` | Generic "smooth" → reveal-class anim     |

   All 5 W13.F sites use the same source literal. All 5 take `Animation.haloExpand`. No flag, no defer.

7. **`withAnimation` AND `.animation(_:value:)` BOTH in scope.** Per W13.A migration policy point 5, both forms get the codemod. Sites:114, :125, :353 use `withAnimation(.smooth(duration: 0.3)) { ... }` blocks. Sites :118, :144 use `.animation(.smooth(duration: 0.3), value: …)` modifiers. All take `Animation.haloExpand`.

8. **`.toolbar { ... withAnimation { ... } }` at :90 and :96 — UNTOUCHED.** Those `withAnimation { ... }` calls have no explicit `Animation` argument (default SwiftUI animation). They're not in the codemod scope (axis D is *ad-hoc literal* swaps; defaults aren't ad-hoc). Coder may verify by re-reading the toolbar block — we leave defaults alone.

9. **`Color.black.opacity(isAnalysisPanelPresented ? 0.1 : 0)` overlay at :110 — UNTOUCHED.** That's a dimmer scrim, not glass chrome. Spec-correct as is.

10. **`Color(NSColor.separatorColor)` at :136 — UNTOUCHED.** Hairline separator between analysis panel and main pane. `NSColor.separatorColor` is the system-correct semantic token for a divider; it tracks light/dark mode. Replacing with `Palette.hairline` would force `white α 0.16` in light mode where the divider should darken — wrong. Leave alone.

11. **No primitive drift.** `Palette.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift`, `WindowManager.swift` are byte-identical pre/post.

12. **No recorder-cluster drift.** Out of scope for this packet by definition; nothing in `Recorder/` is touched.

13. **`window.titleVisibility` stays `.visible`.** The history window benefits from the macOS title showing the active context (`"VoiceInk — Transcription History"`). The main window hides title because its content fills full-bleed and the `.hiddenTitleBar` style + `WindowManager.configureWindow` enforce a flush surface. History uses standard `.titled` style and shows the title — that's the expected contract for a secondary window.

---

## Replacement table

Every line below is a grep-validated hit. **Sweep** = land in W13.F. **Defer** = leave for the named packet. **Flag** = ambiguous; coder evaluates context.

### Axis A — `NSWindow` flag flip (HistoryWindowController only)

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/HistoryWindowController.swift:54` | `window.backgroundColor = NSColor.windowBackgroundColor` | `window.backgroundColor = .clear` | **Sweep** | Mirror `WindowManager.configureWindow:36`. Wallpaper-glass contract (W8). |
| `VoiceInk/HistoryWindowController.swift` (after :54, new line) | (no `isOpaque` — defaults to `true`) | `window.isOpaque = false` | **Sweep** | Mirror `WindowManager.configureWindow:41`. Required for `NSVisualEffectView .behindWindow` to render through. |

**Pattern to land** (replace single line at :54 with two-line block, with one short comment block citing the W8 contract per CLAUDE.md "no obvious-explainer comments" — the comment IS the spec-ref justification, not redundant explanation):

```swift
// W13.F — adaptive glass app-wide. Non-opaque + clear bg so the SwiftUI
// root's HaloMaterial backdrops (sidebar, center pane) render through the
// NSWindow. Mirrors WindowManager.configureWindow flag pattern. Spec §1 /
// §6.1 / docs/superpowers/plans/W13F-history-window-glass.md.
window.backgroundColor = .clear
window.isOpaque = false
```

(Replaces the old single line `window.backgroundColor = NSColor.windowBackgroundColor`.)

### Axis B — Sub-pane opaque NSColor fills → drop overlay / adaptiveGlass / HaloMaterial

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:133` | `.background(Color(NSColor.windowBackgroundColor))` | DROP — remove the `.background(...)` modifier line entirely | **Sweep** | PAPV (the inner view) paints its own `.background(Color(NSColor.windowBackgroundColor))` at PerformanceAnalysisPanelView.swift:20. Outer `.background` here is a redundant double-paint that adds nothing visually but defeats wallpaper-glass at the analysis-panel boundary. PAPV's own opaque chrome is W13.B's residual debt — flagged in §Follow-ups, not swept here. |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:321` | `.background(Color(NSColor.controlBackgroundColor))` | `.background(HaloMaterial(shape: Rectangle(), phase: .hidden, appearance: glassAppearance.current))` | **Sweep** | Right-sidebar empty state ("No Metadata"). Match the established sibling pattern in the same file (`leftSidebarView` :248-252 and empty `centerPaneView` :296-300 already do this for their empty states). One-pattern symmetry across all three pane empty states. |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:391-394` | `.background(Color(NSColor.windowBackgroundColor).shadow(color: Color.black.opacity(0.15), radius: 3, y: -2))` | `.background(HaloMaterial(shape: Rectangle(), phase: .hidden, appearance: glassAppearance.current))` + `.shadow(color: Color.black.opacity(0.15), radius: 3, y: -2)` modifier on the HStack | **Sweep** | Floating selection toolbar at the bottom of the left sidebar. Glass-strip vocabulary; preserve the up-shadow as a sibling modifier (not a chained `.shadow` on the `Color`, which is the current less-clean form). |

### Axis C — Raw `.thinMaterial` chip stack → `glassChip()`

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:171-186` | `HStack { magnifyingglass + TextField } .padding(10) .background(RoundedRectangle 8pt fill .thinMaterial) .padding(12)` | `HStack { … } .glassChip(cornerRadius: 8) .padding(12)` | **Sweep** | Search field. Drop the rect+fill stack and the inner `.padding(10)` (glassChip provides its own paddingH=11 / paddingV=7); keep the outer `.padding(12)` as the wrapper rhythm to the divider. |

**Pattern to land** (replaces lines 173-186 — the search-field block — leaving the outer ZStack at :190 and downstream code untouched):

```swift
HStack {
    Image(systemName: "magnifyingglass")
        .foregroundColor(.secondary)
        .font(.system(size: 13))
    TextField("Search transcriptions", text: $searchText)
        .textFieldStyle(PlainTextFieldStyle())
        .font(.system(size: 13))
}
.glassChip(cornerRadius: 8)
.padding(12)
```

### Axis D — `.smooth(duration: 0.3)` → `Animation.haloExpand` (5 sites)

| File:line | Current | Replacement | Disposition | Rationale |
|---|---|---|---|---|
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:114` | `withAnimation(.smooth(duration: 0.3)) { isAnalysisPanelPresented = false }` | `withAnimation(.haloExpand) { isAnalysisPanelPresented = false }` | **Sweep** | Backdrop-tap dismiss. W13.A migration table: generic smooth → haloExpand. |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:118` | `.animation(.smooth(duration: 0.3), value: isAnalysisPanelPresented)` | `.animation(.haloExpand, value: isAnalysisPanelPresented)` | **Sweep** | Backdrop scrim opacity binding. |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:125` | `withAnimation(.smooth(duration: 0.3)) { isAnalysisPanelPresented = false }` | `withAnimation(.haloExpand) { isAnalysisPanelPresented = false }` | **Sweep** | Analysis-panel close-button tap. |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:144` | `.animation(.smooth(duration: 0.3), value: isAnalysisPanelPresented)` | `.animation(.haloExpand, value: isAnalysisPanelPresented)` | **Sweep** | Analysis-panel slide-in transition binding. |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:353` | `withAnimation(.smooth(duration: 0.3)) { isAnalysisPanelPresented = true }` | `withAnimation(.haloExpand) { isAnalysisPanelPresented = true }` | **Sweep** | Selection-toolbar Analyze button tap. |

**Untouched animation hits in scope-adjacent files (per W13.A):**

- `VoiceInk/Views/History/InlineHistoryView.swift` — already swept by W13.A (10 hits) outside the cardListView Form; cardListView Form animations are W13.D.
- `VoiceInk/Views/History/TranscriptionDetailView.swift` — already swept by W13.A.
- `VoiceInk/Views/History/TranscriptionListItem.swift` — already swept by W13.A.

**No new `withAnimation` defaults swept.** Sites at :90 and :96 use `withAnimation { ... }` (no literal); these are SwiftUI defaults, not ad-hoc literals. Out of scope.

### Axis E — `.rounded` font usage

`grep -n 'design:\s*\.rounded' VoiceInk/Views/History/TranscriptionHistoryView.swift VoiceInk/HistoryWindowController.swift` → **zero hits**. No-op axis for W13.F.

### Axis F — `Color.accentColor` / `Color(.controlAccentColor)` usage

`grep -n 'accentColor\|controlAccentColor' VoiceInk/Views/History/TranscriptionHistoryView.swift VoiceInk/HistoryWindowController.swift` → **zero hits** in W13.F-scope files. (`TranscriptionListItem.swift:101` was swept by W13.A.) No-op axis.

### Axis G — Window-bg opaque tokens (the W8 contract surface)

| File:line | Current | Disposition | Routes to |
|---|---|---|---|
| `VoiceInk/HistoryWindowController.swift:54` | `window.backgroundColor = NSColor.windowBackgroundColor` | **Sweep** (axis A above) | THIS PACKET |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:133` | `.background(Color(NSColor.windowBackgroundColor))` | **Sweep** (axis B above) | THIS PACKET |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:321` | `.background(Color(NSColor.controlBackgroundColor))` | **Sweep** (axis B above) | THIS PACKET |
| `VoiceInk/Views/History/TranscriptionHistoryView.swift:392` | `Color(NSColor.windowBackgroundColor).shadow(...)` | **Sweep** (axis B above) | THIS PACKET |
| `VoiceInk/Views/History/HistoryShortcutTipView.swift:40` | `Color(NSColor.controlBackgroundColor).opacity(0.5)` | **Defer** | **W13.G** polish (per W13.A axis-G defer table). |
| `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:20, 109` | `Color(NSColor.windowBackgroundColor / .controlBackgroundColor)` | **Defer / Flag** | **W13.B** residual debt. Flagged in §Follow-ups. |

---

## Tasks

### Task 0: Audit + grep validation (read-only)

**Files:** none.

- [ ] **Step 0.1: Re-run W13.F-scope axis greps and confirm hit counts match this plan**

```bash
# Axis A — HistoryWindowController flag
rg -n 'backgroundColor\s*=\s*NSColor\.windowBackgroundColor|backgroundColor\s*=\s*\.windowBackgroundColor' VoiceInk/HistoryWindowController.swift

# Axis B — TranscriptionHistoryView opaque NSColor backgrounds
rg -n 'NSColor\.windowBackgroundColor|NSColor\.controlBackgroundColor' VoiceInk/Views/History/TranscriptionHistoryView.swift

# Axis C — search field .thinMaterial
rg -n '\.thinMaterial' VoiceInk/Views/History/TranscriptionHistoryView.swift

# Axis D — animation literals
rg -n '\.smooth\(duration:|\.spring\(response:|\.easeInOut\(duration:' VoiceInk/Views/History/TranscriptionHistoryView.swift

# Axis E + F — rounded + accent (expect zero)
rg -n 'design:\s*\.rounded' VoiceInk/Views/History/TranscriptionHistoryView.swift VoiceInk/HistoryWindowController.swift
rg -n 'accentColor|controlAccentColor' VoiceInk/Views/History/TranscriptionHistoryView.swift VoiceInk/HistoryWindowController.swift
```

Expected hit counts:
- Axis A: 1 hit (`HistoryWindowController.swift:54`)
- Axis B: 3 hits (`TranscriptionHistoryView.swift:133, 321, 392`)
- Axis C: 1 hit (`TranscriptionHistoryView.swift:184`)
- Axis D: 5 hits (`TranscriptionHistoryView.swift:114, 118, 125, 144, 353`)
- Axis E: 0 hits
- Axis F: 0 hits

If counts differ, escalate to lead. Do not drift.

- [ ] **Step 0.2: Verify excluded files are NOT in the working diff**

```bash
git status -s VoiceInk/Views/History/InlineHistoryView.swift VoiceInk/Views/History/TranscriptionDetailView.swift VoiceInk/Views/History/TranscriptionListItem.swift VoiceInk/Views/History/HistoryShortcutTipView.swift VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift VoiceInk/WindowManager.swift VoiceInk/Views/Common/Animation+Halo.swift VoiceInk/Views/Common/GlassChip.swift VoiceInk/Views/Common/Palette.swift VoiceInk/Views/Common/AdaptiveGlassBackground.swift VoiceInk/Views/Recorder/HaloMaterial.swift
```

All paths above MUST show clean (empty status). If any show modifications, the coder has drifted; revert before continuing.

### Task 1: Axis A — `NSWindow` flag flip in `HistoryWindowController.createHistoryWindow`

**Files:** `VoiceInk/HistoryWindowController.swift`.

- [ ] **Step 1.1: Replace the single `window.backgroundColor = NSColor.windowBackgroundColor` line at :54 with the two-flag block + W13.F doc-comment** (per §Migration policy point 1 + axis A pattern). Do NOT add `level = .normal` or any other field.
- [ ] **Step 1.2: Verify** the edit lands AFTER `window.titleVisibility = .visible` (currently :53) and BEFORE `window.isReleasedWhenClosed = false` (currently :55). The block reads cleanly inside the existing top-of-method config sequence.
- [ ] **Step 1.3: Self-grep**: `rg -n 'NSColor\.windowBackgroundColor|isOpaque' VoiceInk/HistoryWindowController.swift` should now show one `isOpaque = false` line and zero `NSColor.windowBackgroundColor` lines.

### Task 2: Axis B — TranscriptionHistoryView opaque sub-pane fills

**Files:** `VoiceInk/Views/History/TranscriptionHistoryView.swift`.

- [ ] **Step 2.1: Drop `.background(Color(NSColor.windowBackgroundColor))` at :133** entirely. The PAPV inside the overlay paints its own backdrop; the outer `.background` was a redundant double-paint. After the edit, the overlay block at :120-142 should have `.frame(width: 400)` followed directly by `.frame(maxHeight: .infinity)` followed by `.overlay(alignment: .leading) { Rectangle()...separatorColor... }` — the `.background(Color(NSColor.windowBackgroundColor))` line is removed.
- [ ] **Step 2.2: Replace `.background(Color(NSColor.controlBackgroundColor))` at :321** with `.background(HaloMaterial(shape: Rectangle(), phase: .hidden, appearance: glassAppearance.current))`. Match the style of :248-252 / :296-300 in the same file.
- [ ] **Step 2.3: Restructure the `selectionToolbar` background at :391-394** — split the inlined `Color(NSColor.windowBackgroundColor).shadow(...)` into:
  - `.background(HaloMaterial(shape: Rectangle(), phase: .hidden, appearance: glassAppearance.current))`
  - `.shadow(color: Color.black.opacity(0.15), radius: 3, y: -2)`
  applied as separate sibling modifiers on the `HStack`. Preserves the up-shadow without baking it into the fill.
- [ ] **Step 2.4: Self-grep**: `rg -n 'NSColor\.windowBackgroundColor|NSColor\.controlBackgroundColor' VoiceInk/Views/History/TranscriptionHistoryView.swift` should now return **zero hits**.

### Task 3: Axis C — Search field `.thinMaterial` → `glassChip(cornerRadius: 8)`

**Files:** `VoiceInk/Views/History/TranscriptionHistoryView.swift`.

- [ ] **Step 3.1: Replace the search-field block at :173-186** with the `.glassChip(cornerRadius: 8)` form per the §Replacement table axis-C pattern. Specifically: drop the `.padding(10)` line (:181), drop the `RoundedRectangle 8pt + .fill(.thinMaterial)` background block (:182-185), and replace with `.glassChip(cornerRadius: 8)` after the closing `}` of the `HStack`. Keep the outer `.padding(12)` (:186) as the rhythm to the divider below.
- [ ] **Step 3.2: Self-grep**: `rg -n '\.thinMaterial' VoiceInk/Views/History/TranscriptionHistoryView.swift` should now return **zero hits**.

### Task 4: Axis D — Animation codemod (5× `.smooth(0.3)` → `Animation.haloExpand`)

**Files:** `VoiceInk/Views/History/TranscriptionHistoryView.swift`.

- [ ] **Step 4.1: Edit each of the 5 sites** per the axis-D §Replacement table:
  - Line 114: `withAnimation(.smooth(duration: 0.3))` → `withAnimation(.haloExpand)`
  - Line 118: `.animation(.smooth(duration: 0.3), value: …)` → `.animation(.haloExpand, value: …)`
  - Line 125: `withAnimation(.smooth(duration: 0.3))` → `withAnimation(.haloExpand)`
  - Line 144: `.animation(.smooth(duration: 0.3), value: …)` → `.animation(.haloExpand, value: …)`
  - Line 353: `withAnimation(.smooth(duration: 0.3))` → `withAnimation(.haloExpand)`
- [ ] **Step 4.2: Self-grep**: `rg -n '\.smooth\(duration:' VoiceInk/Views/History/TranscriptionHistoryView.swift` should now return **zero hits**.

### Task 5: Self-review + grep follow-up

**Files:** none (read-only).

- [ ] Re-run the six W13.F-scope axis greps from Task 0.1. All should be clean (matching the §Replacement table dispositions):
  - Axis A: 0 hits (post-flip, zero `NSColor.windowBackgroundColor` in `HistoryWindowController`).
  - Axis B: 0 hits in `TranscriptionHistoryView.swift`.
  - Axis C: 0 hits in `TranscriptionHistoryView.swift`.
  - Axis D: 0 `.smooth(duration:` hits in `TranscriptionHistoryView.swift`.
- [ ] Confirm excluded-files list still has zero edits (re-run Task 0.2).
- [ ] Confirm `Animation+Halo.swift` reviewer note at lines 14-17 is preserved.
- [ ] Confirm `WindowManager.swift` is byte-identical pre/post (`git diff VoiceInk/WindowManager.swift` empty).
- [ ] Confirm no new `import` statements added — `HistoryWindowController.swift` already imports `AppKit` + `SwiftUI` + `SwiftData`; `TranscriptionHistoryView.swift` already imports `SwiftUI` + `SwiftData`. No new modules.

### Task 6: Integration build

**Files:** none.

- [ ] Run `make local` (single integration build, per `feedback_skip_per_packet_builds.md`). Expect ~3 min cold; ~30s warm.
- [ ] Confirm zero new warnings related to W13.F edits. The codemod is type-stable (`.smooth(duration: 0.3)` and `.haloExpand` are both `Animation`-typed; `NSColor.clear` and `NSColor.windowBackgroundColor` are both `NSColor`-typed; `HaloMaterial` initializer signature is unchanged from sibling sites in the same file). Any warning surfaces as a deviation from the plan and warrants a stop-and-escalate.

### Task 7: Visual smoke pass

**Files:** none (manual check).

- [ ] Open the app. Trigger Show History (menu bar item or `⌥+⌘+H` if bound). Eyeball each of these surfaces under (a) system Light, (b) system Dark, (c) bright wallpaper, (d) dark wallpaper:
  - History window opens — wallpaper bleeds through behind the sidebar / center-pane glass (was a flat opaque box pre-W13.F).
  - Left-sidebar search field reads as a glass chip (was a flat `.thinMaterial` rect).
  - Selection-toolbar at the bottom of the sidebar (visible after one or more rows are checked) reads as a glass strip with up-shadow (was an opaque `windowBackgroundColor` strip).
  - Right-sidebar empty state ("No Metadata" — visible when no transcription is selected and the right sidebar is open) reads as glass (was opaque `controlBackgroundColor`).
  - Click "Analyze" with one or more transcriptions selected — analysis panel slides in from the trailing edge, animation feels cohesive with the rest of the app's `haloExpand` reveals (was the slightly snappier ad-hoc `.smooth(0.3)`).
  - Click backdrop or close button — analysis panel slides out at the same `haloExpand` cadence.
  - PAPV's own opaque chrome inside the analysis panel is still visible (W13.B residual debt — flagged in §Follow-ups, NOT W13.F's job to fix). Visual cue: the analysis panel itself is opaque against the glass main pane behind it. That's expected and correct for this packet.
- [ ] Confirm no surface flickers; no regressed contrast under Reduce-Transparency or Increase-Contrast (System Settings → Accessibility → Display).
- [ ] Confirm the title bar still reads `"VoiceInk — Transcription History"` (we did NOT change `titleVisibility`).
- [ ] Confirm the Toggle Sidebar / Toggle Inspector toolbar buttons still work (we did NOT touch the `.toolbar { ... }` block).

### Task 8: Commit + report to lead

- [ ] Lead handles commits per CLAUDE.md cadence:
  ```
  docs(plans): W13F — history window glass + animation codemod
  feat(aesthetic): W13F — history window glass + animation codemod
  ```
- [ ] Report to lead: task ID, edited file list (2 files), total LOC delta, smoke-pass observations, any flagged hits left untouched (with reason — should be: PAPV opaque chrome at PerformanceAnalysisPanelView.swift:20+109 → W13.B; HistoryShortcutTipView.swift:40 → W13.G).

---

## Verification

1. **Build green.** `xcodebuild build` (or `make local`) at Task 6. Zero warnings, zero errors related to W13.F surfaces.
2. **Grep follow-up clean.** All Axis A/B/C/D hits in W13.F scope are gone; remaining hits in adjacent files match this plan's "Defer" classifications.
3. **Visual smoke green.** Task 7 — every targeted surface reads glass-on-wallpaper under all four wallpaper/system-mode permutations.
4. **No primitive drift.** `Palette.swift`, `GlassChip.swift`, `GlassCard.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift`, `WindowManager.swift` are byte-identical pre/post.
5. **No recorder-cluster drift.** Nothing in `VoiceInk/Views/Recorder/` is touched.
6. **No history-adjacent drift.** `InlineHistoryView.swift`, `TranscriptionDetailView.swift`, `TranscriptionListItem.swift`, `HistoryShortcutTipView.swift` are byte-identical pre/post.
7. **No metrics drift.** `PerformanceAnalysisPanelView.swift` is byte-identical pre/post (its residual debt is W13.B's, not W13.F's).
8. **Window-flag mirror exact.** `HistoryWindowController.createHistoryWindow` uses the same `backgroundColor = .clear` + `isOpaque = false` flag pair as `WindowManager.configureWindow`. Diff verifiable via side-by-side read.

---

## Rollback plan

Single-commit packet (`feat(aesthetic): W13F — history window glass + animation codemod`). If a regression surfaces:

```bash
git revert <sha>
```

Reverts cleanly because every edit is a one-line / one-block token swap with no companion edits, no schema migrations, no dependency changes. The `docs(plans): W13F — history window glass + animation codemod` commit can stay (the plan document itself is reusable across re-attempts).

If a *partial* regression surfaces (e.g. the search-field axis-C swap reads wrong, but the window flag flip is fine), rollback the offending file's edit:

```bash
git checkout HEAD~1 -- VoiceInk/Views/History/TranscriptionHistoryView.swift
git commit --amend
```

…preserves the rest of the sweep. Or rebuild the swap with a different cornerRadius / padding via a follow-up commit.

If the window-flag flip itself causes a regression (e.g. NSWindow content shows partial transparency where glass should be solid because some pane backdrop is missing), the most likely cause is that one of the three sub-pane backdrops in `TranscriptionHistoryView` is misconfigured. Re-read :248-252, :296-300, :321 to verify all three use `HaloMaterial(...)`. If still buggy, fall back to a single-line revert of the `isOpaque = false` flag and add `.adaptiveGlassBackground(intensity: .pane)` at the `body`'s `HStack` level as a backstop — escalate to lead before doing this.

---

## Risks

1. **Wallpaper-bleed exposure on missing pane backdrops** (medium). The flag flip makes the window non-opaque. If ANY pane in `TranscriptionHistoryView` lacks a backdrop, that pane's content would render against raw wallpaper — visible as an ugly transparent strip. **Mitigation:** the three pane backdrops are all in place (verified at :248-252 sidebar, :296-300 center empty, post-edit :321 right empty). The center-pane "selected" branch renders `TranscriptionDetailView`, which paints its own backdrop. The analysis panel overlay renders PAPV which paints its own opaque backdrop. The only paneless surfaces are the `Divider()`s at :74, :81 — those are 1pt vertical strokes that ARE meant to render against the wallpaper. Visual smoke at Task 7 catches anything else.

2. **PAPV opaque chrome still visible after W13.F** (acknowledged trade-off, not a regression). PerformanceAnalysisPanelView.swift:20 + :109 still paint `Color(NSColor.windowBackgroundColor / .controlBackgroundColor)`. Inside the slide-in analysis panel, the inner content reads as opaque against the now-glass main pane. **Mitigation:** explicit out-of-scope per master plan §4 W13.F — the analysis panel is W13.B's residual. Flagged in §Follow-ups. The cohesion gain from flipping the window itself is worth the partial-state mid-W13.

3. **Timing drift on `haloExpand` vs `.smooth(0.3)`** (low). `Animation.haloExpand` is `spring(response: 0.38, dampingFraction: 0.78)`; the source `.smooth(duration: 0.3)` is a pre-iOS-17 SwiftUI smooth interpolator that differs in physics. Post-codemod, the analysis-panel slide-in reads ~25ms slower with a slight overshoot/settle character. **Mitigation:** that's the *point* of the cohesion sweep — recorder grammar wins over per-call-site idiosyncrasy. Visual smoke at Task 7 catches anything off.

4. **Search-field `.glassChip(cornerRadius: 8)` padding shift** (low). Current is `.padding(10)` outside a `RoundedRectangle 8pt`; new is `glassChip` modifier with paddingH=11 / paddingV=7. Net: ~1pt horizontal expansion, ~3pt vertical compression. **Mitigation:** matches chip vocabulary across the rest of the app (used identically in MenuBarView, PromptChipPicker, ConstellationContainer). If visually off, escalate to spec amendment for a `paddingV: 10` overload — but unlikely.

5. **`titleVisibility = .visible` + `backgroundColor = .clear` interaction on macOS** (low). `NSWindow` with `.titled` + transparent background renders the title bar against the SwiftUI content. The title text and traffic-light buttons should still render with their system chrome. Verified pattern: main `WindowManager.configureWindow` does the same flip with `titleVisibility = .hidden`. The only difference is whether the title text shows. **Mitigation:** if the title text reads incorrectly (e.g. unreadable against bright wallpaper), spec extension to add `titlebarAppearsTransparent = true` is already set at :52. macOS handles the contrast via vibrancy. Visual smoke under bright wallpapers catches anything off.

6. **`HaloMaterial(phase: .hidden)` propagation cost** (none — already proven). The pattern is already in the same file at :248 + :296. Adding two more invocations (at :321 + :391) extends a working pattern. No new performance characteristic.

7. **Build-time surprises** (low). The `Animation.haloExpand` token is defined in `Views/Common/Animation+Halo.swift` which is already in scope for `TranscriptionHistoryView.swift` (transitively imported via SwiftUI module). No new imports needed. Same for `HaloMaterial` (already used in the file at :248).

8. **Test-fixture drift** (none for W13.F). `VoiceInkTests/PaletteTests` (2) + `FailureRegistryTests` (5) + `VoiceInkUITests` (4) don't reference any of the surface tokens this packet sweeps. **Mitigation:** integration build (Task 6) catches anything.

---

## Follow-ups for B–G packets (W13.F-adjacent residuals)

### W13.B residual debt (PerformanceAnalysisPanelView)

PAPV at lines :20 (`.background(Color(NSColor.windowBackgroundColor))` outer wrapper) and :109 (`Color(NSColor.controlBackgroundColor)` inner card row) was supposed to be swept by W13.B but the W13.B impl didn't fully reach this surface. Visual evidence: post-W13.F, opening the analysis panel still shows opaque chrome inside the panel, sitting against the now-glass center pane.

**Recommended W13.B follow-up edit (out of W13.F scope):**

- `PerformanceAnalysisPanelView.swift:20` — drop `.background(Color(NSColor.windowBackgroundColor))` or replace with `.adaptiveGlassBackground(intensity: .panel)`.
- `PerformanceAnalysisPanelView.swift:109` — replace `RoundedRectangle 12pt + fill(Color(NSColor.controlBackgroundColor))` with `glassChip(cornerRadius: 12)` or `GlassCard(cornerRadius: 12)`.

If lead wants to bundle this with W13.F instead of cutting a W13.B follow-up packet, the diff is +2-edit-sites, all in PerformanceAnalysisPanelView.swift. Coder may opt into that scope expansion at lead's call. Default per dossier: stay in W13.F scope; flag for a separate packet.

### W13.G polish residual (HistoryShortcutTipView)

`VoiceInk/Views/History/HistoryShortcutTipView.swift:40` — `Color(NSColor.controlBackgroundColor).opacity(0.5)`. Per W13.A axis-G defer table → W13.G polish. The shortcut-tip card sits inside the center-pane "No Selection" empty state; cohesion gain post-W13.G will be noticeable but not critical for the W13.F glass flip.

**Recommended W13.G edit:** replace with `glassChip(cornerRadius: 10)` or `glassPanel()` per the audit row guidance.

### Final spec extension (per master plan §4 W13.G)

After all W13 packets land, amend `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.X (or write `2026-04-29-aesthetic-redesign-W13-deltas.md`) with:

- Codified animation token mapping table (the §Migration policy point 6 table, consistent with W13.A's table).
- Confirmation that secondary `NSWindow`s (history, future-scratchpad-W12.E) use the same `backgroundColor = .clear` + `isOpaque = false` flag pair as the main window — extends the W8 contract from "main window only" to "every app-owned `NSWindow`".
- Q8=a sign-off: history stays separate window, glass-flag drift fixed in W13.F.

---

## Open questions

None. All Q-decisions resolved at master plan §0 sign-off (Q8=a). Risks 1-8 above are acknowledged trade-offs, not unresolved questions. The PAPV residual is a known W13.B miss documented in §Follow-ups, not a W13.F blocker.
