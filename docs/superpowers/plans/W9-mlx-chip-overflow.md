# W9 — MLX Picker Chip Overflow → FlowLayout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.

**Goal:** Fix the MLX model picker chip-strip overflow flagged in `HANDOFF_post_redesign_open_asks_2026-04-29.md` Ask 2. The chip-strip second HStack inside `MLXModelPickerView.modelRow(_:)` (Speed N/10 + Quality N/10 + latency-range + size GB) currently lives in a single horizontal `HStack(spacing: 6)` and the Quality chip clips on narrow `ProviderCard` widths. Wrap the chip strip in the existing `FlowLayout` primitive so chips wrap to a second row when horizontal space runs out. User picked option (a) FlowLayout over option (b) combined Speed/Quality chip — preserves the "/10" denominator and the W6 chip vocabulary.

**Architecture (chip-strip layout migration map):**

```
Surface                                    Current (W6)                                  Target (W9)
─────────────────────────────────────      ─────────────────────────────────────         ─────────────────────────
modelRow row-1 (title + ACTIVE/EXPER       HStack(alignment: .center, spacing: 8)        UNCHANGED
 + Spacer + Use/Download)                  with Spacer() pushing controls right
                                           — line 41-50

modelRow row-2 (chip strip)                HStack(spacing: 6) {                          FlowLayout(spacing: 6) {
                                             ratingChip("Speed", ...)                       ratingChip("Speed", ...)
                                             ratingChip("Quality", ...)                     ratingChip("Quality", ...)
                                             latencyChip(...)                               latencyChip(...)
                                             Spacer()                                       sizeChip(...)
                                             Text("\(GB)")...                            }  // no Spacer; size flows
                                           }                                              // and wraps with the rest
                                           — line 52-61
```

**Layout primitive:** `VoiceInk/Views/Components/FlowLayout.swift` (exists, verified). 44-line `Layout` protocol conformance with `spacing: CGFloat = 6` default, greedy left-to-right placement that wraps when `x + size.width > maxWidth, x > 0`. No row-spacing parameter — the same `spacing` constant doubles as inter-row gap (`y += rowHeight + spacing` on line 33). For W9 the default `spacing: 6` matches the W6 chip-strip spacing exactly; no parameter override needed.

**Spec refs:**
- `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §5 row W6 — the chip vocabulary that the strip already follows; W9 preserves chip styling (font, tracking, capsule chrome) and only changes the layout container.
- `docs/superpowers/handoffs/HANDOFF_post_redesign_open_asks_2026-04-29.md` Ask 2 — user statement + lead's recommendation (option a, FlowLayout).
- `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` line 564 — establishes `HStack(spacing: 6)` for the chip strip; W9 inherits the spacing token unchanged via FlowLayout's default.

**Tech stack:** Swift 5.x, SwiftUI `Layout` protocol (macOS 13+ already required by the codebase), Xcode 16.x. Build via `make local`. No new dependencies, no new primitives.

**CLAUDE.md cadence rules respected:**
- **Single integration build at merge time.** No `make local` per task; one build at the final task.
- **No commits during execution.** Final step reports to lead; lead handles commits.
- **No emoji in code samples; no PR-reference comments; sentence-fragment commit message.** Inline comment on the new layout cites §5 row W6 + this plan path.
- **Pre-existing spec-ref comments preserved.** `MLXModelPickerView.swift:5-9` "spec §5 row W6 + W6 plan" header comment stays untouched; W9 adds a single inline comment next to the FlowLayout wrap citing this plan.

---

## File structure

### New files

None. W9 is a single-row layout swap inside one existing function.

### Modified files

- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` — wrap the chip strip (lines 52-61) in `FlowLayout(spacing: 6)`; drop the `Spacer()` (FlowLayout doesn't honor Spacer the way HStack does — Spacer's `sizeThatFits(.unspecified)` returns minimum size and the layout would treat it as a zero-width flow item, breaking the right-alignment intent). The size GB element migrates from a trailing right-aligned `Text` to the LAST flow item — sits adjacent to latency on a single line when width allows, wraps to a second/third row on narrow widths. ~+3 LOC, -2 LOC. Header doc-comment gains one line citing W9.

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Views/Components/FlowLayout.swift` — primitive stays as-is. The `spacing: CGFloat = 6` default already matches the chip strip's `HStack(spacing: 6)`; no parameter additions, no row-spacing override needed.
- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` row-1 (title + ACTIVE / EXPERIMENTAL + Spacer + Use button + statusControl, lines 41-50) — UNTOUCHED. The chip-overflow report cites the second-row chip strip; ACTIVE / EXPERIMENTAL on row 1 share space with `displayName` (which already truncates) and the trailing controls (which size to `controlSize(.small)`). Row 1 reads fine on the widths under test.
- `ratingChip(_:value:)`, `latencyChip(min:max:)`, `activeChip`, `experimentalChip` helpers (lines 84-135) — chip rendering UNCHANGED. W9 is a container swap; chip chrome (font, tracking, capsule fill, stroke, padding) stays at the W6 spec.
- `downloadProgressChip(fraction:)` helper (lines 187-213) — separate sub-feature; not part of the chip strip.
- `VoiceInk/Views/AI Models/ProviderCard.swift` — outer host card untouched. The card's `.frame(...)` constraints remain whatever the AI Models page sets; W9 fixes the inner row to wrap gracefully under whatever width the card propagates.
- All other W1-W8 surfaces — out of bounds. W9 is a single-file fix.

---

## Migration policy (resolves ambiguity)

1. **`Spacer()` is dropped, not preserved.** SwiftUI `Spacer` reports `sizeThatFits(.unspecified)` as `(0, 0)` minimum (Spacer is greedy in its parent's layout proposal but FlowLayout passes `.unspecified` when measuring children — see `FlowLayout.swift:30`). A Spacer inside FlowLayout would degenerate into a zero-width flow item and provide no right-push. Migrating means the size GB element flows naturally with the chip strip rather than being right-aligned. **Trade-off:** loses the right-edge size annotation pattern. **Why acceptable:** when the chip strip wraps (the failure mode W9 fixes), the right-edge alignment is meaningless anyway because the second row wouldn't right-align with the first row's chips. Keeping size as the last flow item is consistent across both single-row and multi-row states.

2. **Size GB stays as plain `Text`, not a Capsule chip.** The W6 design rendered size GB as bare uppercase mono text — visually distinct from the encapsulated chips (Speed, Quality, latency). W9 preserves that distinction; only the container changes. Size text continues to use `Palette.onyxMute` foreground (line 60) to read as a quiet annotation rather than a primary chip.

3. **No row-spacing parameter override.** FlowLayout's single `spacing` constant doubles as inter-row gap (`y += rowHeight + spacing`). At `spacing: 6`, the second row sits 6pt below the first — matches the W6 plan's row-internal vertical rhythm (`VStack(alignment: .leading, spacing: 8)` from line 40 surrounds the row-1 / chip-strip / notes block at 8pt gaps; the in-flow 6pt gap reads tighter than the inter-element 8pt outside, which is the right hierarchy).

4. **`alignment` is implicit `.leading` (FlowLayout left-aligns rows).** FlowLayout's `placeSubviews` always places at `bounds.minX + position.x` with `position.x` reset to 0 on row break. There is no `.center` / `.trailing` row alignment option in this primitive. The chip strip already lives in `VStack(alignment: .leading, spacing: 8)` (line 40), so leading rows match the parent VStack's alignment. No drift.

5. **No new tests.** The fix is a layout container swap on a single render path. Unit-testing FlowLayout's wrap behavior is not in scope (the primitive predates W9 and isn't covered by tests today). Visual smoke at narrow widths is the validation gate (Task 2.3). If a future packet adds Layout protocol tests, a wrap-at-N-pixels case for FlowLayout would be the right vehicle, not a W9-specific test.

6. **Card-height growth is acceptable.** On narrow widths the row grows by ~21pt (one extra chip-strip line; chips are 10.5pt font + 3pt vertical padding ×2 ≈ 16.5pt; plus 6pt FlowLayout row-gap). Per the handoff: "Card height grows ~20pt per row but all info preserved." Lead signed off; user picked option (a). No card-clamp adjustment needed inside `ProviderCard` — the card's `VStack` heights flex to the row's intrinsic content.

7. **Don't pre-emptively wrap row-1 in FlowLayout.** Row 1 (title + ACTIVE / EXPERIMENTAL + Spacer + Use + statusControl) reads fine in the test widths; user's reported defect is specifically the Quality chip clipping on row 2. Scope discipline: fix the reported defect, leave row 1 alone. If row-1 overflow surfaces later, it gets a separate packet — the chip strip there mixes Text + Spacer + Buttons (which FlowLayout handles poorly because `Button(.bordered)` doesn't measure cleanly under unspecified proposals).

---

## Tasks

### Task 0: Audit — confirm primitive + current chip-strip shape

**Files:** none (read-only).

- [ ] **Step 0.1: Confirm FlowLayout exists at the expected path**

```bash
ls -la VoiceInk/Views/Components/FlowLayout.swift
grep -n "struct FlowLayout\|: Layout\|spacing:" VoiceInk/Views/Components/FlowLayout.swift
```

Expected:
- File exists at `VoiceInk/Views/Components/FlowLayout.swift` (44 lines).
- `struct FlowLayout: Layout` (line 3).
- `var spacing: CGFloat = 6` (line 4).

If the file is missing, escalate — the W9 migration assumes this primitive exists. The handoff's "verify the primitive exists at the listed path" caveat is settled here: it does exist.

- [ ] **Step 0.2: Confirm the chip-strip HStack is at lines 52-61 in MLXModelPickerView**

```bash
grep -n "HStack(spacing: 6)\|ratingChip\|latencyChip\|approximateSizeGB" "VoiceInk/Views/AI Models/MLXModelPickerView.swift"
```

Expected matches:
- Line 52: `HStack(spacing: 6) {`
- Line 53: `ratingChip(label: "Speed", value: model.speedRating)`
- Line 54: `ratingChip(label: "Quality", value: model.qualityRating)`
- Line 55: `latencyChip(min: latency.lowerBound, max: latency.upperBound)`
- Line 56: `Spacer()`
- Line 57: `Text("\(String(format: "%.1f", model.approximateSizeGB)) GB")`

If the line numbers have drifted (a recent landing reshuffled the file), re-anchor on the `HStack(spacing: 6)` + `ratingChip(label: "Speed"` pair — that's the only chip strip in the file.

- [ ] **Step 0.3: Confirm the title row (row 1) is the OTHER HStack and stays untouched**

```bash
grep -n "HStack(alignment: .center, spacing: 8)" "VoiceInk/Views/AI Models/MLXModelPickerView.swift"
```

Expected: line 41 — the title row. W9 leaves that line and its body alone.

- [ ] **Step 0.4: Confirm no other FlowLayout call sites already exist (so the W9 wrap is the first usage)**

```bash
grep -rn "FlowLayout" VoiceInk --include="*.swift" | grep -v "Components/FlowLayout.swift"
```

Expected: zero matches. FlowLayout is currently a primitive with no production call sites — W9 is its first deployment. If a hit surfaces, read it for prior conventions (parameter overrides, alignment expectations) and reconcile with the lead before drifting from the existing pattern.

---

### Task 1: Wrap the chip strip in `FlowLayout`

**Files:**
- Modify: `VoiceInk/Views/AI Models/MLXModelPickerView.swift`

- [ ] **Step 1.1: Replace the chip-strip `HStack(spacing: 6)` with `FlowLayout(spacing: 6)` and drop the `Spacer()` (lines 52-61)**

Current:

```swift
            HStack(spacing: 6) {
                ratingChip(label: "Speed", value: model.speedRating)
                ratingChip(label: "Quality", value: model.qualityRating)
                latencyChip(min: latency.lowerBound, max: latency.upperBound)
                Spacer()
                Text("\(String(format: "%.1f", model.approximateSizeGB)) GB")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.onyxMute)
            }
```

Replace with:

```swift
            // W9: chip strip wraps to a second row on narrow ProviderCard widths
            // (Quality chip was clipping at default width). FlowLayout's default
            // spacing(6) matches the prior HStack inter-chip gap and doubles as
            // the inter-row gap. Spacer() is dropped — FlowLayout treats Spacer
            // as a zero-width flow item, so the size annotation flows as the
            // trailing item instead. Spec §5 row W6; plan
            // docs/superpowers/plans/W9-mlx-chip-overflow.md.
            FlowLayout(spacing: 6) {
                ratingChip(label: "Speed", value: model.speedRating)
                ratingChip(label: "Quality", value: model.qualityRating)
                latencyChip(min: latency.lowerBound, max: latency.upperBound)
                Text("\(String(format: "%.1f", model.approximateSizeGB)) GB")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.onyxMute)
            }
```

Three diffs:
1. `HStack(spacing: 6) {` → `FlowLayout(spacing: 6) {`.
2. Drop the `Spacer()` line.
3. Add a six-line inline comment above the `FlowLayout` opener citing the spec section + this plan path + the rationale for dropping Spacer.

Chip rendering inside the closure (`ratingChip`, `latencyChip`, the size `Text`) is byte-for-byte identical to the W6 implementation. Font, tracking, foreground, capsule chrome all preserved.

- [ ] **Step 1.2: Update the file header doc-comment to mention the W9 layout fix**

Current (lines 5-9):

```swift
// On-device model picker rendered inside `ProviderCard`'s `.mlx` expanded
// arm. W6 re-skin: rows show speed + quality ratings + expected latency
// chips inheriting the glass vocabulary; experimental tier surfaces a
// caution chip. Spec §5 row W6 + W6 plan
// `docs/superpowers/plans/W6-mlx-quality-and-segregation.md`.
```

Replace with:

```swift
// On-device model picker rendered inside `ProviderCard`'s `.mlx` expanded
// arm. W6 re-skin: rows show speed + quality ratings + expected latency
// chips inheriting the glass vocabulary; experimental tier surfaces a
// caution chip. W9: chip strip wraps via FlowLayout on narrow card widths
// to recover the Quality chip clipping reported in the post-W8 handoff.
// Spec §5 row W6 + W6 plan
// `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` + W9 plan
// `docs/superpowers/plans/W9-mlx-chip-overflow.md`.
```

Two diffs: (a) add a sentence noting the W9 wrap; (b) add the W9 plan path alongside the W6 plan path. The "spec §5 row W6" citation stays — W9 inherits the same spec section (chip vocabulary); no new spec section is created for a layout container swap.

- [ ] **Step 1.3: Diff inspection**

```bash
git --no-pager diff "VoiceInk/Views/AI Models/MLXModelPickerView.swift" | head -40
```

Expected: header doc-comment gains the W9 sentence + plan path; chip-strip HStack swaps to FlowLayout; Spacer() line drops; six-line inline comment lands above the FlowLayout call. No other changes in the file.

---

### Task 2: Verification sweeps + visual smoke (manual, env-permitting)

**Files:** none (verification).

- [ ] **Step 2.1: Confirm exactly one `FlowLayout(` call site landed**

```bash
grep -rn "FlowLayout(" VoiceInk --include="*.swift" | grep -v "Components/FlowLayout.swift"
```

Expected: one match — `VoiceInk/Views/AI Models/MLXModelPickerView.swift` at the chip-strip line. If zero, the wrap didn't land. If more than one, scope drifted.

- [ ] **Step 2.2: Confirm the row-1 HStack at line 41 stays untouched**

```bash
grep -n "HStack(alignment: .center, spacing: 8)" "VoiceInk/Views/AI Models/MLXModelPickerView.swift"
```

Expected: still on line 41 (or whatever line the title row landed on — drift is allowed since Task 1 added an inline comment block above the chip strip, which shifts later line numbers). The assertion is the LINE EXISTS, not its number.

- [ ] **Step 2.3: Visual smoke — narrow-width chip wrap**

Reserved for the user-machine pass after the integration build. The coder cannot render the AI Models page from their environment per the W6 handoff "What Didn't Work" §4. User runs through:

1. Launch the app (`/Users/priyanshu/Downloads/VoiceInk.app/Contents/MacOS/VoiceInk`).
2. Open Settings → AI Models. Expand the MLX provider card.
3. Resize the settings window:
   - **Wide** (≥800pt): chip strip on a single row — Speed, Quality, latency, size GB all visible. Same as pre-W9.
   - **Default** (~600pt): chip strip likely still single-row but tighter; if Quality was clipping pre-W9, it's now visible.
   - **Narrow** (~400pt): chip strip wraps to two rows. Speed + Quality on row A; latency + size on row B (or some other split FlowLayout chooses based on intrinsic widths). All four pieces visible.
   - **Very narrow** (~320pt): may wrap to three rows. All info preserved.
4. Confirm: ACTIVE / EXPERIMENTAL chips on row 1 (the title row, not the chip strip) still read correctly across all widths — they were untouched.
5. Confirm: each MLX row's notes paragraph (line 63 `Text(model.notes)`) sits below the chip strip with the existing `VStack(spacing: 8)` gap — the FlowLayout's intrinsic height feeds back into the parent VStack so the notes paragraph repositions correctly when the chip strip grows from 1 → 2 → 3 rows.

**Sanity criteria:**
- No chip clipped at any tested width.
- Row growth is graceful — no flicker on resize, no clipping during the transition.
- Card height adjusts smoothly; sibling rows don't overlap.
- All chips retain their W6 styling (capsule chrome, mono font, tracking, color tokens).

If a chip clips at any width, escalate — likely indicates the chip's intrinsic size is wider than expected (e.g. a very long latency range). Mitigation: shorten the chip text (reformat latency display) rather than re-engineering the layout. Lead decides.

This step is a **user-machine verification reservation** — visual layout choices are inherently subjective and the coder cannot render UI from CI.

- [ ] **Step 2.4: Confirm no W1-W8 surfaces edited**

```bash
git --no-pager diff --stat \
  VoiceInk/Views/Components/FlowLayout.swift \
  VoiceInk/Views/AI\ Models/ProviderCard.swift \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift \
  VoiceInk/Views/Common/Palette.swift \
  VoiceInk/Views/Common/GlassChip.swift \
  VoiceInk/Views/Common/SettingsCard.swift
```

Expected: zero output. W9 is one-file scope; only `MLXModelPickerView.swift` is touched.

- [ ] **Step 2.5: Confirm no emoji literals introduced**

```bash
grep -nE "[\x{1F300}-\x{1FAFF}]" "VoiceInk/Views/AI Models/MLXModelPickerView.swift" 2>/dev/null
```

Expected: zero matches. Pre-existing `🦾` markers live in `MLXProvider.swift` (out of W9 scope) — not touched.

---

### Task 3: Full integration build (the gate) + handback

**Files:** none.

- [ ] **Step 3.1: Run `make local`**

```bash
/usr/bin/make local 2>&1 | tail -40
```

Expected last lines:

```
** BUILD SUCCEEDED **
Copying VoiceInk.app to ~/Downloads...
Build complete! App saved to: ~/Downloads/VoiceInk.app
```

If `BUILD FAILED`:

```bash
grep -nE "^.* error:" /tmp/voiceink-build.log 2>/dev/null | head -20
```

Common diagnostics:
- `cannot find 'FlowLayout' in scope` — the file `VoiceInk/Views/Components/FlowLayout.swift` is in the project but not in the Xcode target membership. Open the project file (`VoiceInk.xcodeproj/project.pbxproj`) and confirm `FlowLayout.swift` is in the `VoiceInk` target's sources build phase. If missing, add it via Xcode's File Inspector → Target Membership. (Should not happen — file existed pre-W9 and any prior Xcode add would have set membership — but flag if it does.)
- `argument 'spacing' is unrelated to type 'FlowLayout'` — typo on the parameter name (`FlowLayout(spacing: 6)` is the only public init; double-check the spelling).
- `closure body cannot be a multiple-statement closure with type 'TupleView<...>'` — happened pre-W9 with some Layout-protocol uses where the Swift compiler can't infer the tuple. Mitigation: wrap each chip in `Group { ... }` or split the closure content into a `@ViewBuilder` helper. Should NOT happen for this 4-element flow but document in case.

- [ ] **Step 3.2: Run the existing test suite**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: existing `PaletteTests` + `FailureRegistryTests` + `VoiceInkUITests` all green. W9 adds no new tests. If the test runner is env-blocked per W6 handoff "What Didn't Work" §4, skip and document the gap.

- [ ] **Step 3.3: Sanity-launch (env-permitting)**

```bash
/usr/bin/killall VoiceInk 2>/dev/null
/Users/priyanshu/Downloads/VoiceInk.app/Contents/MacOS/VoiceInk &
sleep 3
ps aux | grep -E "/VoiceInk\.app/Contents/MacOS/VoiceInk" | grep -v grep | head -1
```

Expected: a running process. Per W6 handoff: `open ~/Downloads/VoiceInk.app` errors -600; direct binary launch via `Contents/MacOS/VoiceInk` works.

- [ ] **Step 3.4: Report status to lead — DO NOT commit**

Per CLAUDE.md, no commits during execution. Report:

```
W9 MLX picker chip overflow: BUILD GREEN, TESTS GREEN (or test gap noted)

Layout swap:
- MLXModelPickerView modelRow chip strip wrapped in FlowLayout(spacing: 6).
- Spacer() dropped; size GB flows as last item (wraps with the rest on
  narrow widths).
- Chip rendering (font, tracking, capsule chrome, foreground tokens)
  byte-for-byte identical to W6.
- Header doc-comment updated to cite W9 plan path alongside W6.
- USER VERIFICATION RESERVED — Task 2.3 (visual smoke at wide / default
  / narrow / very-narrow widths).

Diff: <git diff --stat | tail -1>
```

Lead reviews diff, decides whether to commit. Reviewer (`superpowers:code-reviewer`) checks: (a) FlowLayout call site is the only call site (one place, one swap); (b) chip rendering helpers untouched; (c) row 1 / title HStack untouched; (d) no W1-W8 surfaces edited; (e) header comment updated.

---

## Self-review

- [x] **Spec coverage.**
  - §5 row W6 chip vocabulary preserved (font, tracking, capsule chrome unchanged).
  - Handoff Ask 2 option (a) implemented per user's pick.
  - W6 plan's `HStack(spacing: 6)` token preserved as `FlowLayout(spacing: 6)` — same numeric gap.

- [x] **Out-of-scope guard.**
  - FlowLayout primitive (`Components/FlowLayout.swift`) UNTOUCHED. ✓
  - ProviderCard / APIKeyManagementView / Palette / GlassChip / SettingsCard UNTOUCHED. ✓
  - `MLXModelPickerView` row 1 (title + ACTIVE / EXPERIMENTAL + Use / Download) UNTOUCHED. ✓
  - Chip helpers (`ratingChip`, `latencyChip`, `activeChip`, `experimentalChip`) UNTOUCHED. ✓
  - Download progress chip UNTOUCHED. ✓
  - No new tests, no new primitives, no new dependencies. ✓
  - W7's type / sound / chip-tracking polish UNTOUCHED — W9 doesn't drift into typography. ✓

- [x] **Placeholder scan.** Every step has exact file:line, exact code, or exact command. No "TBD" / "implement later".

- [x] **Type consistency.**
  - `FlowLayout` is a `struct` conforming to `Layout` protocol (verified at `Components/FlowLayout.swift:3`).
  - `FlowLayout(spacing:)` signature: `var spacing: CGFloat = 6` — `Int` literal `6` auto-converts. ✓
  - Children inside the FlowLayout closure are SwiftUI Views (Text + ratingChip / latencyChip return `some View`); FlowLayout's `Subviews` is `LayoutSubviews` which accepts any View. ✓

- [x] **Build cadence.** No `make local` between tasks; one full build at Task 3.1 per CLAUDE.md.

- [x] **No commits.** Final step reports to lead.

- [x] **No PR-reference comments in code samples.** Inline comment cites spec section + plan path; no PR numbers.

- [x] **Pre-existing spec-ref comments preserved.** Header doc-comment's "Spec §5 row W6 + W6 plan ..." line stays; W9 cite is added alongside, not replacing.

- [x] **Coder context isolation.** Tasks reference exact file:line and exact code blocks. Coder need not read W1-W8 plans to execute W9. The single layout-container swap is fully demonstrated in Task 1.1; the comment-update in Task 1.2 is also fully spelled out.

---

## Acceptance criteria

- ✅ `make local` completes with `** BUILD SUCCEEDED **`.
- ✅ `xcodebuild test` passes (or env-block documented) — all existing tests green.
- ✅ `grep -rn "FlowLayout(" VoiceInk --include="*.swift"` returns exactly one production call site (in `MLXModelPickerView.swift`) plus the primitive declaration in `Components/FlowLayout.swift`.
- ✅ The chip strip's prior `HStack(spacing: 6)` is gone; the same four chips (Speed / Quality / latency / size) live inside `FlowLayout(spacing: 6)`.
- ✅ `Spacer()` between latency and size is gone (FlowLayout's wrap behavior replaces the right-push).
- ✅ Chip rendering (font, tracking, foreground, capsule chrome) is byte-for-byte identical to W6 — only the container changes.
- ✅ Row 1 / title HStack at line 41 is untouched.
- ✅ Header doc-comment cites W9 plan path alongside W6.
- ✅ No W1-W8 surface edited (Task 2.4 grep guard).
- ✅ User-machine visual smoke (Task 2.3) reserved as a verification gap; lead surfaces the chip-overflow recovery in the commit message + post-W9 handoff.

---

## Risks / unknowns

1. **Spacer() removal alters single-row visual.** Pre-W9: Speed + Quality + latency on the left, size GB right-aligned via Spacer. Post-W9 single-row: Speed + Quality + latency + size all packed left, with empty space trailing on the right. **Visual change.** Card readability is preserved (all four pieces visible) but the right-edge size annotation pattern is gone. **Mitigation:** the chip-overflow defect specifically affects the wrapped state; preserving right-alignment in single-row mode while wrapping in multi-row mode would require a measure-then-pick-layout helper (e.g. `ViewThatFits`) — overkill for this packet. If user dislikes the new single-row alignment, follow-up packet picks ONE of: (a) pad-trailing the FlowLayout to maintain a right-edge gutter; (b) restore HStack on wide widths via `ViewThatFits` between an HStack and a FlowLayout; (c) move size into the title row (row 1) as a chip and keep only Speed/Quality/latency in the FlowLayout. None ship in W9.

2. **`FlowLayout` is unused before W9 — first production deployment.** The primitive is 44 lines, has no test coverage, and was added in an earlier cleanup landing without a call site. The greedy left-to-right placement reads correct on inspection (`x + size.width > maxWidth` wrap on the line, reset `x` to 0, advance `y`). **Risk:** edge cases not covered by inspection — e.g. the very-narrow case where a single chip's intrinsic width exceeds the proposed maxWidth. The current code (`x > 0` guard at line 31) prevents the infinite-loop case but means a too-wide chip overflows its own row rather than wrapping inside itself (no chip text wrapping). **Mitigation:** the chips are short (Speed N/10, Quality N/10, latency Xs-Ys, X.X GB) — none should exceed even a 200pt-wide ProviderCard. If a chip text grows in a future packet (e.g. localization to a longer language), the wrap-then-overflow case becomes possible — at that point the chip itself needs `lineLimit(1)` + `truncationMode(.tail)` like the title.

3. **Card height grows on narrow widths.** Per the handoff: "~20pt per row." The MLX picker is rendered inside a `ScrollView` (the AI Models page is scroll-friendly) so card growth doesn't break layout, but it does push subsequent MLX rows further down. Acceptable per user's preferred option (a). **Mitigation:** none needed; lead pre-approved.

4. **Reduce Motion / Accessibility.** FlowLayout is a static layout primitive with no animation. SwiftUI's parent VStack will animate the height transition implicitly (default spring) when the row count changes due to a width resize. **Risk:** users with Reduce Motion enabled don't get a "frame" reduce — the height transition is part of the standard SwiftUI implicit animation. **Mitigation:** none needed; the implicit animation is mild (no springy bouncing), and the W3 reduce-motion tokens (`Animation.clusterFadeReduced`) are scoped to cluster motion, not generic resize.

5. **Header doc-comment churn.** The W6 doc-comment was tight; W9 adds three lines mentioning the layout fix + plan path. **Risk:** future packets may grow the comment further until it dwarfs the actual code. **Mitigation:** keep cites short; future packets adding cite-only lines should consider a single "see plans/" pointer rather than enumerating each plan path. Out of W9 scope to refactor.

6. **`ViewThatFits` alternative not pursued.** A future-proof variant would wrap both an `HStack` (single-row, right-aligned size) and the new `FlowLayout` (wrap-friendly) inside `ViewThatFits` so the system picks the HStack on wide widths and falls back to FlowLayout on narrow. **Risk:** W9 commits to the FlowLayout-always pattern. **Mitigation:** the user / lead can sign off on the always-flow-left visual; if they reject it after Task 2.3, follow-up packet adds `ViewThatFits` as a single-line wrapper change. ~5 minutes of work to upgrade later.

## Estimated effort

~30 minutes for an engineer familiar with the codebase. ~1 hour for a fresh teammate. The bulk of the change is one HStack → FlowLayout swap + one Spacer() removal + a six-line inline comment + a three-line header doc-comment update. Verification sweeps are grep-driven and fast. The visual smoke pass (Task 2.3) belongs to the user post-merge and is reserved as a verification gap.
