# W5 — Settings Re-skin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.

**Goal:** Migrate the remaining Settings surfaces to the W1 token vocabulary. Layout stays untouched; only chrome (background materials, stroke colors, corner radii, type weights, status pills, accent fills) changes. Drops the last rainbow leftovers (`.green`, `.orange`, `.blue`, `.red`, `Color.accentColor` references) from `PermissionsView`, `AudioInputSettingsView`, `AudioCleanupSettingsView`, `DiagnosticsSettingsView`, `FillerWordsSettingsView`, `ModelSettingsView`, `EnhancementSettingsView`'s drop-target stroke, `EnhancementSettingsPanel`'s `LastSystemPromptViewer`, `DictionarySettingsPanel`'s close button, and the `RecorderStylePicker` selected fill. Re-skins `PermissionCard`'s entire glass body to the W1 vocabulary. Verifies `.tint(Palette.accent)` propagation across direct `Toggle` and `Picker` call sites. Does not change any picker, toggle, hotkey-recorder, or backup logic.

**Architecture (token migration map):**

```
Rainbow leftover                         W1 replacement
────────────────────────────────────     ────────────────────────────────────
Color.green / .green                  →  Palette.success
Color.orange / .orange                →  Palette.warn
Color.red / .red                      →  Palette.warn (destructive accents)
                                            or Palette.accent (active chips)
Color.blue / .blue                    →  Palette.accent
Color.accentColor / .accentColor      →  Palette.accent
Color.secondary.opacity(0.1) circle   →  glass-chip 8pt RR + ultraThinMaterial
                                            + Palette.hairline stroke
Divider().opacity(0.5)                →  Rectangle.fill(Palette.hairlineSoft)
                                            .frame(height: 1)
RoundedRectangle(cornerRadius: 16)    →  RoundedRectangle(cornerRadius: 14)
  (panel)                                  per spec §1 panel token
RoundedRectangle(cornerRadius: 7-8)   →  unchanged where already 8 (spec §1
  (chip)                                   chip token)
.rounded design on body chrome        →  .system (default) — explicit only
                                            where the file already specifies
                                            (the broader `.rounded` sweep is
                                            W7's surface, not W5)
```

The migration is mechanical — every replacement is one of the six rules above. No new view types are introduced. Existing primitives (`SettingsCard`, `SettingsRow`, `SettingsSectionHeader`, `glassChip()`, `glassPanel()`) are reused; nothing in `VoiceInk/Views/Common/` is touched.

**Architecture (PermissionCard re-skin):**

```
PermissionCard (current)                  PermissionCard (W5)
────────────────────────────              ────────────────────────────
Circle .fill(.green/.orange α0.15)    →   RoundedRectangle 9pt
  with hierarchical icon glyph                .fill(Palette.success / .warn α0.18)
                                              .stroke(α0.36) overlay
                                              + same icon glyph

Image checkmark.seal / xmark.seal     →   StatusPill(text: "Granted" / "Needs Access",
                                                tone: .positive / .warning)
  in green/orange                              — reused from APIKeyManagementView

LinearGradient Color.accentColor      →   Capsule .fill(Palette.accent)
  → Color.accentColor.opacity(0.8)          + Palette.hairline stroke,
  CTA pill                                    foregroundColor white
                                              cornerRadius 10 (chip token)

CardBackground(isSelected: false)     →   GlassCard(cornerRadius: 14, padding: 20)
  + cornerRadius 16 + soft shadow            (no hover-lift gain since this
                                              is a permissions surface; the
                                              W6 hover-lift removal pattern
                                              is per-card and only ProviderCard
                                              has been migrated so far —
                                              W5 leaves GlassCard's lift
                                              alone since SettingsCard hosts
                                              already use GlassCard and have
                                              not been flagged as a problem)
```

**Tech Stack:** Swift 5.x, SwiftUI, AppKit, Xcode 16.x. Build via `make local` (~3 min cold). Animations attach via `.animation(_, value:)` / `withAnimation`; never `DispatchQueue.main.asyncAfter` for chrome.

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens), §5 row W5 ("Settings re-skin: `EnhancementSettingsView.swift`, `EnhancementSettingsPanel.swift`, `HotkeySettings*`, `AudioInputSettings*`, etc. Existing layout preserved; cards/chips/toggles inherit new tokens; visual diff against old screens captured."). Plus W6's already-completed scope on `EnhancementSettingsView` chrome buttons (W5 picks up only the rainbow leftovers W6 didn't touch).

**CLAUDE.md cadence rules respected:**
- **Single integration build at merge time.** No `make local` per task; one full build at the final task.
- **No commits during execution.** Final step reports to lead; lead handles commits.
- **No `xcodebuild` per file.** SourceKit handles per-file syntax during edits; integration build is the gate.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code samples.** All inline doc-comments cite the spec section + this plan path; none reference PR numbers.
- **Pre-existing spec-ref comments preserved.** `Palette.swift` §1 ref, `GlassChip.swift` §1 ref, `SettingsCard.swift` §3.3 ref, `SettingsRow.swift` §3.3 ref, etc. are not modified.

---

## File structure

### New files

None. W5 is entirely a token migration + chrome re-skin packet. No new types, no new primitives.

### Modified files

- `VoiceInk/Views/PermissionsView.swift` — full re-skin of `PermissionCard`. Drop the rainbow `.green` / `.orange` symbol fills + the `Color.accentColor` CTA gradient + the soft-shadow `CardBackground` chrome. Adopt `GlassCard`, `Palette.success` / `Palette.warn` for status, `StatusPill` from `APIKeyManagementView` for the granted/needs-access badge, single-accent `Palette.accent` Capsule for the CTA. ~+50 LOC, -30 LOC.
- `VoiceInk/Views/Settings/AudioInputSettingsView.swift` — replace `.green` (active label, capsule fill), `.blue` (selected radios + chevron + add button), `.red` (priority-remove button) call sites with `Palette.success` / `Palette.accent` / `Palette.warn`. The `CardBackground` host stays for now (Out of scope per scope-creep guard — W4 owns top-level cards). Keep functional behavior intact. ~+18 LOC, -18 LOC.
- `VoiceInk/Views/Settings/DiagnosticsSettingsView.swift` — single `.green` checkmark on export-success goes to `Palette.success`. ~+1 LOC, -1 LOC.
- `VoiceInk/Views/Settings/AudioCleanupSettingsView.swift` — pure-functional surface with no rainbow leftovers; verify `.tint` propagation by adding `.tint(Palette.accent)` at the outer Group so the picker selection rendering is consistent. ~+1 LOC.
- `VoiceInk/Views/Settings/CustomSoundSettingsView.swift` — already W1-correct (uses `Palette.accent` / `Palette.warn` / `Palette.neutral` per `tint(for:)` and the "Custom" badge). Verify only — no edits planned. **Untouched in this packet.**
- `VoiceInk/Views/Settings/EnhancementShortcutsView.swift` — `KeyChip` private struct uses `Color(NSColor.controlBackgroundColor)` + `Color(NSColor.separatorColor)` — those are system-adaptive colors (not rainbow palette), so they stay. Verify only — no edits planned. **Untouched in this packet.**
- `VoiceInk/Views/Settings/RecorderStylePicker.swift` — line 102 `Color.accentColor.opacity(0.06)` selected fill migrates to `Palette.accent.opacity(0.06)`. Card chrome stays (this surface is a picker, not a settings card — its chrome is part of the W2 cluster preview vocabulary). ~+1 LOC, -1 LOC.
- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` — `LastSystemPromptViewer` chrome (lines 192-198): replace `Color(NSColor.textBackgroundColor).opacity(0.6)` + `Color.secondary.opacity(0.2)` 1pt stroke with W1 vocabulary (`.ultraThinMaterial` background + `Palette.hairlineSoft` 1pt stroke, corner radius 6 → 8 to match chip token). Header chrome already W6-touched — leave alone. ~+5 LOC, -3 LOC.
- `VoiceInk/Views/Components/FillerWordsSettingsView.swift` — `FillerWordChip` `.red` hover, `.blue` add button, `Color(.windowBackgroundColor).opacity(0.4)` chip fill, `Color.secondary.opacity(0.2)` stroke all migrate. Use `Palette.warn` for destructive hover, `Palette.accent` for the add button, `.ultraThinMaterial` + `Palette.hairlineSoft` for the chip. Corner radius 6 → 8 (chip token). ~+10 LOC, -10 LOC.
- `VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift` — close button (lines 18-26): replace `Color.secondary.opacity(0.1)` Circle background with the W1 glass-chip vocabulary matching `EnhancementSettingsPanel` Task 10.1 from W6. Bottom hairline (lines 32-34): `Divider().opacity(0.5)` → `Rectangle.fill(Palette.hairlineSoft).frame(height: 1)`. ~+12 LOC, -6 LOC.
- `VoiceInk/Views/EnhancementSettingsView.swift` — single line 234 `Color.accentColor.opacity(0.25)` drop-target stroke inside `ReorderablePromptGrid` migrates to `Palette.accent.opacity(0.25)`. The grid body stays untouched per W6's same-file scope decision. ~+1 LOC, -1 LOC.
- `VoiceInk/Views/Common/GlassCard.swift` — drop the `.offset(y: hovering ? -4 : 0)` + the `.animation(_, value: hovering)` chained modifier per spec §5#8 ("`GlassCard` hover-lift removed (kept hover, dropped 4pt translate-y)"). Keep `@State private var hovering` + `.onHover { hovering = $0 }` per W6's ProviderCard pattern. Update the file header doc-comment. Drop the `AccessibilityMotionMonitor` `@ObservedObject` if it becomes unreferenced post-edit. Blast radius: every `SettingsCard` / `GlassCard` host across the app loses the 4pt lift on hover. ~+5 LOC, -10 LOC.
- `VoiceInk/Views/ModelSettingsView.swift` — pure form with no rainbow leftovers. Verify `.tint(Palette.accent)` propagation by inspecting it through the SettingsView host. **Untouched in this packet.**

### Retired files (delete)

None. **`KeyboardShortcutView.swift` (248 LOC) is an orphan** — its only references are inside the file itself (the legacy private `ShortcutKeyCap` struct + the `#Preview` block). No production call site. Per the brief: flag for the user but do **not** delete in W5 scope (separate cleanup ticket).

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Views/Common/Palette.swift` / `GlassChip.swift` / `GlassSwitch.swift` / `SettingsCard.swift` / `SettingsRow.swift` / `SettingsSectionHeader.swift` / `CardBackground.swift` / `ProviderChipStyle.swift` / `ProviderChip.swift` — W1 primitives. Re-use only. (`GlassCard.swift` is now in scope — see Modified files; the hover-lift removal lives there per spec §5#8.)
- `VoiceInk/Views/EnhancementSettingsView.swift` — the prompt-grid header `+` button (lines 130-152) and gear button (lines 75-94) — **already W6-touched**. Do not redo. The `ReorderablePromptGrid` body (lines 195-271) outside the line-234 stroke fix.
- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` — the header xmark close button (lines 25-39) and the bottom hairline (lines 45-50) — **already W6-touched**. Do not redo. The Form body (lines 53-169) is untouched per W6's same-file scope decision.
- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` / `ProviderCard.swift` / `APIKeyManagementView.swift` — W6 surfaces.
- `VoiceInk/Views/PromptEditorView.swift` — W6 surface.
- `VoiceInk/Views/Settings/SettingsView.swift` — main settings hub, already W1 token-correct. The `SettingsCard` / `SettingsRow` / `SettingsSectionHeader` primitives it composes are W1's deliverable; the GlassCard hover-lift those inherit is a spec §5#8 concern that has been addressed only on `ProviderCard` (W6) so far. **Do not modify SettingsView in W5.** If the user wants the hover-lift removed system-wide, that's a separate ticket touching `GlassCard.swift` directly.
- `VoiceInk/Views/ContentView.swift` — W4 surface. Sidebar already uses `.tint(Palette.accent)`.
- `VoiceInk/Views/Recorder/Constellation/*.swift` / `MorphingRecorderPanel.swift` (if still present) — W2/W3 territory.
- `VoiceInk/Views/Settings/CustomSoundSettingsView.swift` — already W1-correct (uses `Palette.accent` / `Palette.warn` / `Palette.neutral`). Inspect-only.
- `VoiceInk/Views/Settings/EnhancementShortcutsView.swift` — `KeyChip` uses `Color(NSColor.controlBackgroundColor)` + `Color(NSColor.separatorColor)`, both system-adaptive (not rainbow). Inspect-only.
- `VoiceInk/Views/ModelSettingsView.swift` — pure Form, no rainbow leftovers. Inspect-only.
- `VoiceInk/Views/KeyboardShortcutView.swift` — orphan; do not edit in W5 scope. Coder reports as a flag for the user.
- `VoiceInk/Services/**/*.swift` — no service-layer changes in W5.
- All test files (`VoiceInkTests/*.swift`) — W5 ships no new tests. Existing `PaletteTests` (2) + `FailureRegistryTests` (5) + `VoiceInkUITests` (4) must still pass at the integration build (Task 13).
- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`'s pre-W6 stripped surfaces (TrialMessageView etc.) — already gone via `972896a`. Don't re-introduce.

---

## Migration policy (resolves ambiguity for each design decision)

1. **Rainbow → token mapping is mechanical.** Six rules in the architecture map above. No designer judgment per call site — apply the rule, move on.

2. **Destructive accents (`.red`).** Two interpretations exist:
   - **W5 default:** `.red` → `Palette.warn` for destructive cues that are **non-imminent** (e.g. a hover affordance on a delete-chip xmark — user has not committed to the action). Logs as warn-tier, not danger-tier. Matches the W6 `Palette.warn` use for EXPERIMENTAL chip and the spec §3.10 cue palette where `Palette.warn` reads "amber, attention" rather than "red, danger".
   - **W5 escalation:** if the destructive surface fires immediately on tap (e.g. `AudioInputSettingsView` lines 425-428 `Image(systemName: "minus.circle.fill") .foregroundStyle(isPrioritized ? .red : .blue)` — the priority-list remove button), keep `Palette.warn` for the `isPrioritized` branch. Don't introduce a separate "danger" token; the spec doesn't define one and the W1 packet deliberately collapsed the palette.

3. **Active selection (`.blue`, `Color.accentColor`).** Always `Palette.accent`. No exceptions in W5 — the single-accent rule is locked per spec §1.

4. **System-adaptive colors stay.** `Color(NSColor.controlBackgroundColor)`, `Color(NSColor.windowBackgroundColor)`, `Color(NSColor.textBackgroundColor)`, `Color(NSColor.separatorColor)`, `Color(NSColor.shadowColor)`, `Color(NSColor.quaternaryLabelColor)` — these adapt to dark/light system theme via the macOS color palette, not the rainbow palette. They stay. The rule only retires hard-coded color names + `Color.accentColor`.

5. **`.green` for "active" labels stays via `Palette.success`.** `AudioInputSettingsView` uses `.green` for the "Active" device-state label (active mic, active input) — that's a genuine completion / validation success signal, exactly what `Palette.success` exists for. Migrate `.green` → `Palette.success` (not `Palette.accent`), preserving the semantic distinction the spec encodes (spec §1: "`Palette.success` only for true completion / validation success").

6. **`.orange` for permissions warning stays via `Palette.warn`.** `PermissionsView` uses `.orange` for "needs access" state — that's exactly what `Palette.warn` represents. Direct migration.

7. **`StatusPill` reuse from `APIKeyManagementView`.** `PermissionCard` adopts the same `StatusPill(text:tone:)` component the W6 `ProviderCard` already adopts. Same module, no import needed. Saves a re-implementation.

8. **`GlassCard` hover-lift removal is in scope (Task 9).** Spec §5#8 requires `GlassCard hover-lift removed (kept hover, dropped 4pt translate-y)`. W6's `ProviderCard` migrated inline. Lead's call: fold the base-primitive removal into W5 because the blast radius ("every `SettingsCard` host across the app") IS exactly W5's surface inventory — doing it now means the visual smoke pass already in this plan covers the consistent change in one packet rather than scattered across packets. Mechanically a single-line edit to drop the `.offset(y:)` + `.animation(_, value: hovering)` modifier; preserves `@State hovering` + `.onHover` per W6's ProviderCard pattern.

9. **Toggles + Pickers — verify `.tint` propagation, don't replace.** Direct `Toggle(...)` and `Picker(...)` call sites inherit accent from the nearest enclosing `.tint(...)`. ContentView line 109 sets `.tint(Palette.accent)` on the sidebar List. SwiftUI propagates `.tint` down the view hierarchy. **Verify by reading the rendered toggle thumb color in the visual smoke pass** (Task 12). If a particular surface needs an explicit pin (the `EnhancementSettingsPanel` Form, the `AudioCleanupSettingsView` group, the `ModelSettingsView` Form), add `.tint(Palette.accent)` at that surface root — one line per surface. Do NOT migrate `Toggle` to `GlassSwitch` in W5; `GlassSwitch` is a custom replacement that drops `LaunchAtLogin.Toggle` interop and per-OS toggle accessibility traits. Surface-by-surface migration to `GlassSwitch` is a follow-up if the user wants a stricter visual match.

10. **`PermissionCard` body chrome migration choice — `GlassCard` over `CardBackground`.** `CardBackground` (in `VoiceInk/Views/Common/CardBackground.swift`) renders a glassmorphism gradient that pre-dates W1; it's still used by `AudioInputSettingsView`'s device cards, `DictionarySettingsView`'s `SectionCard`, and `PermissionsView`'s `PermissionCard`. Migrating only `PermissionCard` to `GlassCard` (W1 primitive) is acceptable — `PermissionsView` is the single-most rainbow-bearing surface and the W4 handoff explicitly tagged it. The other two `CardBackground` sites are out of scope (audio-input device cards in their existing slot remain visually consistent with each other; W4-territory primitive review can address the broader migration in a future ticket).

11. **No emoji in code.** None of the files in W5's scope have emoji literals. Verify via Task 11.7 grep sweep.

---

## Tasks

### Task 0: Audit + sweep references

**Files:** none (read-only).

- [ ] **Step 0.1: Catalog rainbow color usages in W5's scope**

```bash
grep -rnE "(\.blue|\.green|\.red|\.orange|\.yellow|\.pink|\.purple)\b|Color\.accentColor" \
  VoiceInk/Views/Settings/ \
  VoiceInk/Views/PermissionsView.swift \
  VoiceInk/Views/EnhancementSettingsView.swift \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsView.swift \
  VoiceInk/Views/ModelSettingsView.swift
```

Expected matches as of W5 dispatch (spot-checked by planner):
- `PermissionsView.swift`: lines 103, 108, 155, 160, 179.
- `Settings/AudioInputSettingsView.swift`: lines 77, 82, 291, 322, 333, 338, 388, 393, 412, 418, 428.
- `Settings/DiagnosticsSettingsView.swift`: line 18.
- `Settings/RecorderStylePicker.swift`: line 102.
- `Components/FillerWordsSettingsView.swift`: lines 17, 67.
- `EnhancementSettingsView.swift`: line 234.

Total ~20 matches. If grep finds anything outside this list, reconcile with the lead before proceeding (a new file may have landed since plan-time).

- [ ] **Step 0.2: Catalog Toggle / Picker direct usages without `.tint`**

```bash
grep -rnE "Toggle\(|Picker\(" \
  VoiceInk/Views/Settings/ \
  VoiceInk/Views/PermissionsView.swift \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift \
  VoiceInk/Views/ModelSettingsView.swift \
  | grep -v "TextField\|InfoTip\|tint("
```

Use the result to populate the visual-verify checklist in Task 12 — every surface that hosts a Toggle / Picker needs a tint-propagation read in the smoke pass.

- [ ] **Step 0.3: Confirm the `KeyboardShortcutView` orphan finding**

```bash
grep -rn "KeyboardShortcutView(" VoiceInk --include="*.swift"
```

Expected: only two matches inside `VoiceInk/Views/KeyboardShortcutView.swift` itself (the `#Preview` block). If any other call site is found, the orphan claim is wrong — W5 still doesn't delete the file (that's a separate cleanup ticket), but the coder reports the surprise to the user.

- [ ] **Step 0.4: Confirm `StatusPill` is reachable from `PermissionsView.swift`**

```bash
grep -n "struct StatusPill" VoiceInk --include="*.swift" -r
```

Expected: one match in `VoiceInk/Views/AI Models/APIKeyManagementView.swift` (around line 144). Same Swift module as `PermissionsView` (target `VoiceInk`), so no import needed. If it's gone or moved, the `PermissionCard` re-skin (Task 1) needs a different status badge — fall back to inline SF Mono uppercase Capsule using `Palette.success.opacity(0.16)` fill + `Palette.success.opacity(0.42)` stroke.

- [ ] **Step 0.5: Read `StatusPill`'s exact API**

```bash
sed -n '140,185p' VoiceInk/Views/AI\ Models/APIKeyManagementView.swift
```

Confirm signature `StatusPill(text: String, tone: Tone)` with `.positive` / `.neutral` / `.warning` cases. If the API differs, adapt the call site in Task 1.

---

### Task 1: Re-skin `PermissionCard` — body chrome + status pill + CTA

**Files:**
- Modify: `VoiceInk/Views/PermissionsView.swift`

- [ ] **Step 1.1: Replace the icon-circle (lines 100-110)**

Current:

```swift
                ZStack {
                    Circle()
                        .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: isGranted ? "\(icon).fill" : icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isGranted ? .green : .orange)
                        .symbolRenderingMode(.hierarchical)
                }
```

Replace with:

```swift
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill((isGranted ? Palette.success : Palette.warn).opacity(0.18))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke((isGranted ? Palette.success : Palette.warn).opacity(0.36), lineWidth: 0.5)
                        )

                    Image(systemName: isGranted ? "\(icon).fill" : icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isGranted ? Palette.success : Palette.warn)
                        .symbolRenderingMode(.hierarchical)
                }
```

Two diffs: (a) Circle → 10pt rounded rectangle to match the W1 chip token + the `SettingsRow` icon-tile geometry; (b) `.green` / `.orange` symbol colors → `Palette.success` / `Palette.warn`.

- [ ] **Step 1.2: Replace the seal status indicator (lines 152-162)**

Current:

```swift
                    if isGranted {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                            .symbolRenderingMode(.hierarchical)
                    } else {
                        Image(systemName: "xmark.seal.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.orange)
                            .symbolRenderingMode(.hierarchical)
                    }
```

Replace with:

```swift
                    StatusPill(
                        text: isGranted ? "Granted" : "Needs Access",
                        tone: isGranted ? .positive : .warning
                    )
```

Two diffs: (a) symbol-only seal → SF Mono uppercase status pill (text-bearing, VoiceOver-readable); (b) `.green` / `.orange` retired in favor of `StatusPill`'s `.positive` / `.warning` tones (which already resolve to `Palette.success` / `Palette.warn` per spec).

If the planner's Step 0.4 grep showed `StatusPill` is unreachable for any reason, fall back to the inline form:

```swift
                    Text(isGranted ? "GRANTED" : "NEEDS ACCESS")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .tracking(0.06 * 10.5)
                        .foregroundColor(isGranted ? Palette.success : Palette.warn)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill((isGranted ? Palette.success : Palette.warn).opacity(0.16)))
                        .overlay(Capsule().stroke((isGranted ? Palette.success : Palette.warn).opacity(0.42), lineWidth: 0.5))
```

- [ ] **Step 1.3: Replace the CTA pill (lines 167-186)**

Current:

```swift
            if !isGranted {
                Button(action: buttonAction) {
                    HStack {
                        Text(buttonTitle)
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
```

Replace with:

```swift
            if !isGranted {
                Button(action: buttonAction) {
                    HStack {
                        Text(buttonTitle)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.accent)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
```

Three diffs: (a) `LinearGradient(Color.accentColor, Color.accentColor.opacity(0.8))` → flat `Palette.accent` (single-accent vocabulary, no gradient — gradients on chrome are out per spec §1's flat-fill discipline); (b) `.font(.headline)` → explicit system 14 semibold (matches the rest of the W1 chrome); (c) hairline stroke added so the pill still reads as a defined edge against the glass body.

- [ ] **Step 1.4: Replace the card body chrome (lines 188-192)**

Current:

```swift
        .padding()
        .background(CardBackground(isSelected: false))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.05), radius: 5, y: 2)
    }
```

Replace with:

```swift
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(red: 0.078, green: 0.078, blue: 0.110).opacity(0.28))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Palette.hairline, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
```

Four diffs: (a) `CardBackground(isSelected: false)` (gradient + soft shadow) → flat `.ultraThinMaterial` + hairline stroke (W1 panel vocabulary); (b) corner radius 16 → 14 per spec §1 panel token; (c) drop the soft drop-shadow — the W1 vocabulary uses inner highlight / hairline rather than ambient shadow on settings surfaces; (d) explicit `.clipShape` so the inner content doesn't peek past the rounded corners. Note: not using `.glassPanel()` here because `PermissionCard` already supplies its own layout-padding; nesting would double-stack the inner highlight + shadow.

- [ ] **Step 1.5: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/PermissionsView.swift | head -120
```

Expected: icon-circle replaced with rounded-rect, seal swapped for StatusPill, CTA swapped from gradient to flat accent + hairline, card body switched from CardBackground+shadow to ultraThinMaterial+hairline. The `PermissionsView` outer `ScrollView` body and the four `PermissionCard(...)` call sites stay UNTOUCHED.

---

### Task 2: Migrate rainbow leftovers in `AudioInputSettingsView`

**Files:**
- Modify: `VoiceInk/Views/Settings/AudioInputSettingsView.swift`

- [ ] **Step 2.1: Replace `.green` "Active" labels (lines 77, 82, 333, 338, 388, 393)**

There are three identical "Active" label call sites (in `systemDefaultSection`, `DeviceSelectionCard`, `DevicePriorityCard`). Each uses:

```swift
                Label("Active", systemImage: "wave.3.right")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(.green.opacity(0.1))
                    )
```

Replace each with:

```swift
                Label("Active", systemImage: "wave.3.right")
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundStyle(Palette.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Palette.success.opacity(0.16))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Palette.success.opacity(0.42), lineWidth: 0.5)
                    )
```

Three diffs per site: (a) `.green` → `Palette.success`; (b) `.font(.caption)` → SF Mono uppercase 0.06em tracking (chip vocabulary per spec §1); (c) hairline overlay added so the pill reads as a defined edge.

Use `replace_all` carefully — three identical blocks; visually verify each replacement by re-running `git diff` between sites.

- [ ] **Step 2.2: Replace `.blue` selected radios in `InputModeCard` + `DeviceSelectionCard` (lines 291, 322)**

Current at line 291 (`InputModeCard`):

```swift
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
```

Replace with:

```swift
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Palette.accent : .secondary)
```

Current at line 322 (`DeviceSelectionCard`):

```swift
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .font(.system(size: 18))
```

Replace with:

```swift
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? Palette.accent : .secondary)
                    .font(.system(size: 18))
```

- [ ] **Step 2.3: Replace `.blue` chevrons + `.red`/`.blue` priority button (lines 412-428)**

Current:

```swift
                if isPrioritized {
                    HStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .foregroundStyle(canMoveUp ? .blue : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveUp)
                        
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .foregroundStyle(canMoveDown ? .blue : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveDown)
                    }
                }
                
                // Toggle priority button
                Button(action: onTogglePriority) {
                    Image(systemName: isPrioritized ? "minus.circle.fill" : "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPrioritized ? .red : .blue)
                }
```

Replace with:

```swift
                if isPrioritized {
                    HStack(spacing: 2) {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .foregroundStyle(canMoveUp ? Palette.accent : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveUp)

                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .foregroundStyle(canMoveDown ? Palette.accent : .secondary.opacity(0.5))
                        }
                        .disabled(!canMoveDown)
                    }
                }

                // Toggle priority button
                Button(action: onTogglePriority) {
                    Image(systemName: isPrioritized ? "minus.circle.fill" : "plus.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isPrioritized ? Palette.warn : Palette.accent)
                }
```

Three diffs: (a) `.blue` chevrons → `Palette.accent` (single-accent active-state); (b) `.red` priority-remove → `Palette.warn` (per migration policy point 2 — non-imminent destructive); (c) `.blue` priority-add → `Palette.accent`.

- [ ] **Step 2.4: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Settings/AudioInputSettingsView.swift | head -100
```

Expected: three "Active" pill rebuilds, two `.blue` selected-radio fixes, four chevron + priority-button color migrations. The `prioritizedDevicesSection`, `customDeviceSection`, `availableDevicesContent`, the `DevicePriorityCard` move logic, and the `CardBackground` chrome all stay untouched.

---

### Task 3: Migrate the `DiagnosticsSettingsView` checkmark

**Files:**
- Modify: `VoiceInk/Views/Settings/DiagnosticsSettingsView.swift`

- [ ] **Step 3.1: Replace line 18**

Current:

```swift
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
```

Replace with:

```swift
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Palette.success)
```

Single line. Mechanical.

---

### Task 4: Migrate the `RecorderStylePicker` selected fill

**Files:**
- Modify: `VoiceInk/Views/Settings/RecorderStylePicker.swift`

- [ ] **Step 4.1: Replace line 102**

Current:

```swift
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.06) : Color.clear)
        )
```

Replace with:

```swift
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Palette.accent.opacity(0.06) : Color.clear)
        )
```

Single line. The card preview chrome (the `ZStack` with `LinearGradient` + `HaloShape` + `Capsule` + `RoundedRectangle.stroke(isSelected ? Palette.accent : Color.white.opacity(0.12))`) stays untouched — it's already token-correct on the selected stroke.

---

### Task 5: Re-skin `LastSystemPromptViewer` chrome inside `EnhancementSettingsPanel`

**Files:**
- Modify: `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`

- [ ] **Step 5.1: Replace the prompt-viewer ScrollView chrome (lines 192-198)**

Current:

```swift
                .frame(minHeight: 120, maxHeight: 220)
                .background(Color(NSColor.textBackgroundColor).opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
```

Replace with:

```swift
                .frame(minHeight: 120, maxHeight: 220)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Palette.hairlineSoft, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
```

Three diffs: (a) `Color(NSColor.textBackgroundColor).opacity(0.6)` → `.ultraThinMaterial` (W1 vocabulary; reads against both light + dark wallpapers); (b) corner radius 6 → 8 (chip token per spec §1); (c) `Color.secondary.opacity(0.2)` stroke → `Palette.hairlineSoft` (matches the panel-header divider migrated by W6 already in this file).

The "Copy" button chrome (`.buttonStyle(.bordered)`) stays — it's a system-styled button, not a hand-rolled chrome surface.

---

### Task 6: Re-skin `FillerWordChip` + add-button in `FillerWordsSettingsView`

**Files:**
- Modify: `VoiceInk/Views/Components/FillerWordsSettingsView.swift`

- [ ] **Step 6.1: Replace the `FillerWordChip` body (lines 14-37)**

Current:

```swift
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHovered ? .red : .secondary)
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
```

Replace with:

```swift
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isHovered ? Palette.warn : .secondary)
                    .font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .onHover { hover in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hover
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.hairlineSoft, lineWidth: 1)
        )
    }
```

Three diffs: (a) `.red` hover destructive cue → `Palette.warn` (per migration policy point 2 — non-imminent: hover signals intent, doesn't fire delete); (b) corner radius 6 → 8 (chip token); (c) `Color(.windowBackgroundColor).opacity(0.4)` + `Color.secondary.opacity(0.2)` stroke → `.ultraThinMaterial` + `Palette.hairlineSoft` (W1 chip vocabulary).

- [ ] **Step 6.2: Replace the add-word button (line 67)**

Current:

```swift
                        Button(action: addWord) {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.blue)
                                .font(.system(size: 16, weight: .semibold))
                        }
```

Replace with:

```swift
                        Button(action: addWord) {
                            Image(systemName: "plus.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Palette.accent)
                                .font(.system(size: 16, weight: .semibold))
                        }
```

Single-line color migration.

---

### Task 7: Re-skin `DictionarySettingsPanel` close button + bottom hairline

**Files:**
- Modify: `VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift`

- [ ] **Step 7.1: Replace the close button (lines 18-26)**

Current:

```swift
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close")
```

Replace with:

```swift
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Palette.hairline, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("Close")
```

Identical chrome to W6's `EnhancementSettingsPanel` close button. The two settings sliding-panels now read as a single vocabulary.

- [ ] **Step 7.2: Replace the bottom hairline (lines 32-34)**

Current:

```swift
            .overlay(
                Divider().opacity(0.5), alignment: .bottom
            )
```

Replace with:

```swift
            .overlay(
                Rectangle()
                    .fill(Palette.hairlineSoft)
                    .frame(height: 1),
                alignment: .bottom
            )
```

Same migration W6 already applied to `EnhancementSettingsPanel`. Same vocabulary.

---

### Task 8: Migrate the `EnhancementSettingsView` drop-target stroke

**Files:**
- Modify: `VoiceInk/Views/EnhancementSettingsView.swift`

- [ ] **Step 8.1: Replace line 234**

Current:

```swift
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    draggingItem != nil && draggingItem?.id != prompt.id
                                    ? Color.accentColor.opacity(0.25)
                                    : Color.clear,
                                    lineWidth: 1
                                )
                        )
```

Replace with:

```swift
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(
                                    draggingItem != nil && draggingItem?.id != prompt.id
                                    ? Palette.accent.opacity(0.25)
                                    : Color.clear,
                                    lineWidth: 1
                                )
                        )
```

Single line. The rest of `ReorderablePromptGrid` (drag/drop logic, prompt-icon rendering) stays untouched.

---

### Task 9: Drop `GlassCard` 4pt hover-lift translate-y per spec §5#8

**Files:**
- Modify: `VoiceInk/Views/Common/GlassCard.swift`

- [ ] **Step 9.1: Remove the `.offset(y:)` + chained `.animation(...)` from the body**

Current (lines 32-48 of `GlassCard.swift`):

```swift
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content()
            .padding(padding)
            .background(
                HaloMaterial(
                    shape: shape,
                    phase: .hidden,
                    appearance: resolvedAppearance
                )
            )
            .offset(y: hovering ? -4 : 0)
            .animation(
                motion.reduceMotion ? nil : .easeOut(duration: 0.18),
                value: hovering
            )
            .onHover { hovering = $0 }
    }
```

Replace with:

```swift
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content()
            .padding(padding)
            .background(
                HaloMaterial(
                    shape: shape,
                    phase: .hidden,
                    appearance: resolvedAppearance
                )
            )
            .onHover { hovering = $0 }
    }
```

Two diffs: (a) `.offset(y: hovering ? -4 : 0)` removed (the 4pt translate-y); (b) the chained `.animation(_, value: hovering)` modifier removed (no longer needed without the offset). Keep `@State private var hovering: Bool = false` (line 25) and `.onHover { hovering = $0 }` per W6's `ProviderCard` pattern — the cursor-signal hook stays available for any future caller without re-introducing the offset.

- [ ] **Step 9.2: Update the file header doc-comment**

Current (lines 1-15):

```swift
import SwiftUI

// MARK: - GlassCard
//
// Generic glass surface used across Phase 2/3 surfaces (Menu Bar, Settings,
// License, AI Models, Prompts, History detail). Composes `HaloMaterial`
// at `phase: .hidden` — never duplicates the layered material itself.
//
// Per spec §3.2 + §4 ("Hover-lift on cards"):
//   - 4pt translate-y on cursor enter, 0.18s ease.
//   - Reduce Motion → translation is immediate (no spring).
//
// Appearance defaults to `GlassAppearanceDetector.shared.current` when nil.
// Callers may pin `appearance: .onyx` / `.light` for surfaces that should not
// adapt to wallpaper luminance (e.g. fixed dark recorder satellites).
```

Replace with:

```swift
import SwiftUI

// MARK: - GlassCard
//
// Generic glass surface used across Phase 2/3 surfaces (Menu Bar, Settings,
// AI Models, Prompts, History detail). Composes `HaloMaterial`
// at `phase: .hidden` — never duplicates the layered material itself.
//
// Hover lift removed per spec §5#8 ("GlassCard hover-lift removed (kept
// hover, dropped 4pt translate-y)"). The `@State hovering` + `.onHover`
// hook is retained so future surfaces can opt into a non-translate hover
// signal (e.g. accent-glow swell) without rewiring the boolean. Matches
// W6's `ProviderCard` migration pattern.
//
// Appearance defaults to `GlassAppearanceDetector.shared.current` when nil.
// Callers may pin `appearance: .onyx` / `.light` for surfaces that should not
// adapt to wallpaper luminance (e.g. fixed dark recorder satellites).
```

The "License" surface reference is dropped because the strip-out commit `972896a` removed the License views entirely.

- [ ] **Step 9.3: Drop `AccessibilityMotionMonitor` if unreferenced post-edit**

Run:

```bash
grep -n "AccessibilityMotionMonitor\|motion\." VoiceInk/Views/Common/GlassCard.swift
```

If the only remaining match is the `@ObservedObject private var motion = AccessibilityMotionMonitor.shared` declaration line itself (no other use site), delete that line too — Step 9.1 removed the only consumer of `motion.reduceMotion`. Do NOT remove if `motion` is still used elsewhere in the file (unexpected — current code only references it inside the `.animation` modifier the previous step removed).

Expected post-edit grep result: zero matches.

- [ ] **Step 9.4: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Common/GlassCard.swift | head -60
```

Expected: `.offset(y: hovering ? -4 : 0)` deleted, `.animation(_, value: hovering)` deleted, doc-comment rewritten, `@ObservedObject private var motion` deleted (if Step 9.3 confirmed no other consumer). The `@State private var hovering: Bool = false` and `.onHover { hovering = $0 }` lines stay.

- [ ] **Step 9.5: Sweep for any remaining `offset(y: hovering` survivors across the project**

```bash
grep -rn "offset(y: hovering" VoiceInk --include="*.swift"
```

Expected: zero matches. W6 already removed the `ProviderCard` site; W5 removes the `GlassCard` base primitive site; no other survivors should exist. If any match remains, escalate to lead — there's a third hover-lift consumer the brief didn't anticipate.

---

### Task 10: Add `.tint(Palette.accent)` propagation pins where needed

**Files:**
- Modify: `VoiceInk/Views/Settings/AudioCleanupSettingsView.swift`
- Modify: `VoiceInk/Views/Components/EnhancementSettingsPanel.swift`
- Modify: `VoiceInk/Views/ModelSettingsView.swift`

These three surfaces host direct `Toggle` and `Picker` calls that don't appear inside the `ContentView`'s `.tint(Palette.accent)` propagation path (they're rendered inside slidingPanel hosts and standalone Forms). Pinning the tint at each surface root guarantees the toggle thumb + picker selection render in the W1 accent regardless of where the surface mounts.

- [ ] **Step 10.1: Pin `AudioCleanupSettingsView` body**

Current (line 26):

```swift
        Group {
```

Replace with:

```swift
        Group {
```

(no structural change), and at the end of the outer `Group {...}` block — find the line that closes the outer Group (around line 211 `}` with no trailing modifier), and append `.tint(Palette.accent)`:

```swift
        }
        .tint(Palette.accent)
    }
}
```

Verify with:

```bash
grep -n "tint(Palette.accent)" VoiceInk/Views/Settings/AudioCleanupSettingsView.swift
```

Expected: one match, on the closing `}` of the outer Group inside `body`.

- [ ] **Step 10.2: Pin `EnhancementSettingsPanel` body**

The outer `VStack(spacing: 0)` in the body (line 15) hosts both the header and the Form. Append `.tint(Palette.accent)` to the VStack — find the closing `}` of `body` (around line 173) and the trailing closure on `.scrollContentBackground(.hidden)` (line 171) on the Form. Add the tint on the OUTER VStack closing brace:

Current (around line 172):

```swift
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
    }
}
```

Replace with:

```swift
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .tint(Palette.accent)
    }
}
```

The tint applies to the entire VStack including the header (which is fine — header buttons set their own foreground colors already).

- [ ] **Step 10.3: Pin `ModelSettingsView` Form**

Current (line 110):

```swift
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedLanguage) { oldValue, newValue in
```

Replace with:

```swift
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .tint(Palette.accent)
        .onChange(of: selectedLanguage) { oldValue, newValue in
```

The pin propagates to all toggles + the picker selection inside the Form.

---

### Task 11: Visual + functional self-checks

**Files:** none (verification).

- [ ] **Step 11.1: Confirm zero rainbow color literals remain in W5's modified set**

```bash
grep -rnE "(\.blue|\.green|\.red|\.orange)\b|Color\.accentColor" \
  VoiceInk/Views/PermissionsView.swift \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift \
  VoiceInk/Views/Settings/DiagnosticsSettingsView.swift \
  VoiceInk/Views/Settings/RecorderStylePicker.swift \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift \
  VoiceInk/Views/EnhancementSettingsView.swift
```

Expected: zero matches. If any match remains, it's a missed migration site — fix before proceeding to Task 11.

- [ ] **Step 11.2: Confirm SettingsCard / SettingsRow / SettingsSectionHeader / GlassChip / GlassSwitch / Palette were not modified**

```bash
git --no-pager diff --stat \
  VoiceInk/Views/Common/SettingsCard.swift \
  VoiceInk/Views/Common/SettingsRow.swift \
  VoiceInk/Views/Common/SettingsSectionHeader.swift \
  VoiceInk/Views/Common/GlassChip.swift \
  VoiceInk/Views/Common/GlassSwitch.swift \
  VoiceInk/Views/Common/Palette.swift
```

Expected: zero output (no files changed in the W1-primitive set besides `GlassCard.swift` which IS in W5's scope per Task 9).

Then verify `GlassCard.swift` did change:

```bash
git --no-pager diff --stat VoiceInk/Views/Common/GlassCard.swift
```

Expected: ~5-10 LOC delta (offset + animation removed, doc-comment rewritten, optionally the `@ObservedObject motion` declaration removed).

- [ ] **Step 11.3: Confirm `offset(y: hovering` is gone everywhere**

```bash
grep -rn "offset(y: hovering" VoiceInk --include="*.swift"
```

Expected: zero matches across the entire project. W6 already removed `ProviderCard`'s; Task 9 removes `GlassCard`'s; no other survivors.

- [ ] **Step 11.4: Confirm W6 surfaces were not edited**

```bash
git --no-pager diff --stat \
  VoiceInk/Views/AI\ Models/MLXModelPickerView.swift \
  VoiceInk/Views/AI\ Models/ProviderCard.swift \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift \
  VoiceInk/Views/PromptEditorView.swift \
  VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift \
  VoiceInk/Services/AIEnhancement/MLXProvider.swift
```

Expected: zero output.

- [ ] **Step 11.5: Confirm the W6-touched surfaces in the W5 file set were not re-edited**

```bash
git --no-pager diff VoiceInk/Views/EnhancementSettingsView.swift | grep -E "^\+.*Image\(systemName: \"(plus|gear)\"" | head
```

Expected: zero output (the `+` and gear button chrome should not appear in the diff — only line 234 of `ReorderablePromptGrid`).

```bash
git --no-pager diff VoiceInk/Views/Components/EnhancementSettingsPanel.swift | grep -E "^\+.*xmark" | head
```

Expected: zero output (the close button at line 25 was already W6-touched; W5 only edits `LastSystemPromptViewer` and the body `.tint`).

- [ ] **Step 11.6: Confirm the `KeyboardShortcutView` orphan claim**

```bash
grep -rn "KeyboardShortcutView(" VoiceInk --include="*.swift"
```

Expected: only matches inside `VoiceInk/Views/KeyboardShortcutView.swift` itself. If any other call site is found, escalate to the user before merge — the file may not be safe to retire later.

- [ ] **Step 11.7: Confirm no W5 file introduces an emoji literal**

```bash
grep -rnE "[\x{1F300}-\x{1FAFF}]" \
  VoiceInk/Views/PermissionsView.swift \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift \
  VoiceInk/Views/Settings/DiagnosticsSettingsView.swift \
  VoiceInk/Views/Settings/RecorderStylePicker.swift \
  VoiceInk/Views/Settings/AudioCleanupSettingsView.swift \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift \
  VoiceInk/Views/EnhancementSettingsView.swift \
  VoiceInk/Views/ModelSettingsView.swift \
  2>/dev/null
```

Expected: zero matches.

- [ ] **Step 11.8: Confirm StatusPill is the right symbol in PermissionCard**

```bash
grep -n "StatusPill" VoiceInk/Views/PermissionsView.swift
```

Expected: at least one match (Task 1.2 added the StatusPill call site). If zero matches, the fallback inline form was used — verify it renders the SF Mono uppercase status copy in Task 12 visual smoke.

---

### Task 12: SwiftUI compile-error sweep (read-only)

**Files:** none (verification).

- [ ] **Step 12.1: Confirm no missing imports**

The W5 changes do NOT introduce any new module dependencies. `Palette`, `StatusPill`, `GlassChip`, `GlassPanel` are all in the `VoiceInk` target. If a "cannot find ... in scope" error surfaces in Task 13, the most likely cause is that `StatusPill`'s file membership changed — confirm via Xcode File Inspector. No `import` statements should be added.

- [ ] **Step 12.2: Confirm `.glassChip()` modifier is NOT used inside W5 surfaces**

```bash
grep -rn "\.glassChip()\|\.glassPanel()" \
  VoiceInk/Views/PermissionsView.swift \
  VoiceInk/Views/Settings/ \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift \
  VoiceInk/Views/EnhancementSettingsView.swift
```

Expected: zero matches. W5 deliberately uses the explicit `RoundedRectangle.fill(.ultraThinMaterial) + .stroke(Palette.hairline)` form rather than the `.glassChip()` modifier — same reason as W6 Task 5.1: the W5 chrome surfaces sit inside Form / GlassCard hosts that already provide the inner highlight + drop shadow; nesting a `.glassChip()` would double-stack those layers per `GlassChip.swift:32-58`.

- [ ] **Step 12.3: Confirm `RoundedRectangle` corner radii are consistent**

```bash
grep -rnE "RoundedRectangle\(cornerRadius: (6|7|8|10|14)" \
  VoiceInk/Views/PermissionsView.swift \
  VoiceInk/Views/Settings/AudioInputSettingsView.swift \
  VoiceInk/Views/Components/EnhancementSettingsPanel.swift \
  VoiceInk/Views/Components/FillerWordsSettingsView.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsPanel.swift \
  | grep -v "controlBackgroundColor\|separatorColor"
```

Expected (per spec §1):
- 8 = chip / button chrome
- 10 = icon tile (PermissionsView Task 1.1)
- 14 = panel body (PermissionsView Task 1.4)

If any 6 or 7 corners remain, they were missed migrations — fix before Task 13.

---

### Task 13: Visual smoke pass on the user's machine (BLOCKED — coder cannot render)

**Files:** none (manual visual verification).

The coder cannot render UI in their environment (the `xcodebuild test` + `open ~/Downloads/VoiceInk.app` paths are blocked per W6 handoff "What Didn't Work" §4 + §5). This task is recorded as a **verification gap** the user fills in after merge. The plan reserves it explicitly so the lead can hand it to the user as part of the post-W5 smoke pass.

- [ ] **Step 13.1: Permissions tab — full visual diff**

System Settings (in-app) → Permissions tab. For each of the four `PermissionCard` rows (Keyboard Shortcut, Microphone, Accessibility, Screen Recording):
- Confirm the icon tile renders as a 10pt rounded rectangle (no longer a circle), filled with `Palette.success` (~#30D158 mid-saturation green) when granted or `Palette.warn` (~#FF9F0A amber) when needs-access.
- Confirm the StatusPill renders SF Mono uppercase "GRANTED" / "NEEDS ACCESS" text-bearing pill in the same accent + a hairline edge (replacing the old solid checkmark/xmark seal symbol).
- Confirm the CTA pill (when not granted) is a flat `Palette.accent` fill (no longer a left-to-right gradient) with hairline edge + white text.
- Confirm the card body is a `.ultraThinMaterial` 14pt rounded rectangle with `Palette.hairline` 1pt stroke (no longer the heavier `CardBackground` gradient + soft shadow).

- [ ] **Step 13.2: Audio Input tab — visual diff**

System Settings → Audio Input. For each of the input modes (System Default / Custom / Prioritized):
- Confirm the "Active" device badge renders as SF Mono uppercase + `Palette.success` (was `.green`).
- Confirm the input-mode card icons render `Palette.accent` when selected (was `.blue`).
- Confirm the device-selection radio toggles use `Palette.accent` for the "filled" state (was `.blue`).
- Confirm the priority-list move-up / move-down chevrons render `Palette.accent` when active (was `.blue`).
- Confirm the priority-list remove (minus) button renders `Palette.warn` (was `.red`); the priority-list add (plus) button renders `Palette.accent` (was `.blue`).

- [ ] **Step 13.3: Settings → Diagnostics**

Click "Export Logs". Once it succeeds, confirm the trailing checkmark renders `Palette.success` (was `.green`).

- [ ] **Step 13.4: Settings → Recorder Style picker**

Click each of the three preview cards. Confirm the surrounding hover-tint background uses `Palette.accent.opacity(0.06)` when selected (was `Color.accentColor.opacity(0.06)` — visually similar but explicitly the W1 token now).

- [ ] **Step 13.5: Settings → Filler Words editor**

In ModelSettings → Filler Words section: add a word, hover the trailing `xmark.circle.fill` on the resulting chip. Confirm the symbol tints amber (`Palette.warn`, was `.red`). Confirm the chip body is `.ultraThinMaterial` + `Palette.hairlineSoft` 8pt rounded rectangle (was `windowBackgroundColor.opacity(0.4)` + `Color.secondary.opacity(0.2)` 6pt). Confirm the add-word `+` button tints `Palette.accent` (was `.blue`).

- [ ] **Step 13.6: Dictionary settings sliding panel**

Settings → Dictionary → click the gear (sliding panel opens). Confirm the close `x` button renders the W1 glass-chip vocabulary identical to the EnhancementSettingsPanel close button (8pt rounded, ultraThinMaterial, `Palette.hairline`). Confirm the bottom hairline of the header is the `Palette.hairlineSoft` rect (no longer `Divider().opacity(0.5)`).

- [ ] **Step 13.7: Enhancement settings sliding panel — LastSystemPromptViewer**

Settings → Enhancement → gear (sliding panel) → scroll to "Last Sent System Prompt". Run a dictation cycle so a prompt populates. Confirm the prompt ScrollView container renders `.ultraThinMaterial` 8pt rounded with `Palette.hairlineSoft` 1pt stroke (was `textBackgroundColor.opacity(0.6)` + `Color.secondary.opacity(0.2)` 6pt).

- [ ] **Step 13.8: Toggle / Picker tint propagation**

For each of `Settings → Privacy (auto-cleanup)`, `Settings → Enhancement → gear`, and `Settings → AI Models tab → Transcription` (if the ModelSettingsView is mounted there): toggle a switch and confirm the on-state thumb + track use `Palette.accent` (~tangerine) and not the system-default blue. If any toggle thumb still reads system blue, the surface needs a `.tint(Palette.accent)` pin — file a follow-up.

- [ ] **Step 13.9: Card hover behavior (GlassCard hover-lift removal verification)**

Hover the cursor over any `SettingsCard` / `GlassCard` host. Confirm: (a) the cursor still indicates hover (cursor signal still wired via `.onHover`); (b) the card does NOT translate up by 4pt — the lift is gone per spec §5#8. Spot-check at least one card on each of: Settings (Shortcuts card, Privacy card, Power Mode card), Permissions (any of the four permission cards — they're now `GlassCard`-hosted post-Task 1.4), AI Models (any ProviderCard — already migrated by W6 but should still pass since W5's primitive removal aligns with W6's inline removal), Audio Input (the InputModeCard tiles still use `CardBackground` not `GlassCard`, so they're not affected — confirm). If a card still lifts, the primitive removal was incomplete or a third hover-lift consumer surfaced — escalate to lead.

- [ ] **Step 13.10: Reduce-Motion verification**

System Settings → Accessibility → Display → Reduce Motion ON. Open Permissions. Confirm the PermissionCard chrome renders without animation; the StatusPill swap on toggle of permission state should not trigger spring animation. Confirm the SwiftUI Material graceful degradation kicks in for the glass body (no flicker on toggle).

- [ ] **Step 13.11: VoiceOver verification**

Cmd+F5. Tab through PermissionsView. VO should read each card's title + description + StatusPill text ("Granted" / "Needs Access") + CTA button text. The icon tile is `accessibilityHidden` per the SettingsRow pattern, so VO doesn't double-announce the symbol. Cmd+F5 to disable.

- [ ] **Step 13.12: Capture before/after screenshots**

Per spec §5 row W5 ("visual diff against old screens captured"). Save before/after pairs to `docs/superpowers/handoffs/` for the lead's post-merge handoff doc. Recommended set: PermissionsView (granted state + needs-access state), AudioInputSettingsView (each input mode), Dictionary settings panel, Enhancement settings panel (LastSystemPromptViewer populated). If env-blocked from screenshotting, document the visual deltas in prose at minimum.

---

### Task 14: Full integration build (the gate) + handback

**Files:** none.

- [ ] **Step 14.1: Run `make local`**

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
grep -nE "^.* error:" /tmp/voiceink-build.log 2>/dev/null | head -20
```

Common diagnostics:
- `cannot find 'StatusPill' in scope` in `PermissionsView.swift` → `APIKeyManagementView.swift`'s file-membership in the `VoiceInk` target was lost. Verify in Xcode File Inspector or fall back to the inline status form per Task 1.2 fallback.
- `cannot find 'Palette.hairline' in scope` → typo; the W1 token is `Palette.hairline` per `Palette.swift:56`.
- `cannot find 'Palette.warn' in scope` → typo; the W1 token is `Palette.warn` per `Palette.swift:21`.
- `cannot find type 'CardBackground' in scope` → impossible (it's still used by `AudioInputSettingsView`); means a successful migration accidentally removed the host file.
- `value of type 'View' has no member 'tint'` → Task 9.1/9.2/9.3 added a `.tint` to a non-View value. Walk back the modifier chain.

- [ ] **Step 14.2: Run the existing test suite (no W5 tests added)**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: all existing tests pass — `PaletteTests` (2), `FailureRegistryTests` (5), `VoiceInkUITests` (4). If the test runner is env-blocked per W6 handoff "What Didn't Work" §4, skip this step and document the gap to the lead.

- [ ] **Step 14.3: Sanity-launch (env-permitting)**

```bash
/usr/bin/killall VoiceInk 2>/dev/null
/Users/priyanshu/Downloads/VoiceInk.app/Contents/MacOS/VoiceInk &
sleep 3
ps aux | grep -E "/VoiceInk\.app/Contents/MacOS/VoiceInk" | grep -v grep | head -1
```

Expected: a running process. Note the W6 handoff "What Didn't Work" §5: `open ~/Downloads/VoiceInk.app` errored -600 on local-cert-signed bundles; direct binary launch via `Contents/MacOS/VoiceInk` works. If the launch silently fails, kill the process and report — don't proceed with Task 12 visual checks.

- [ ] **Step 14.4: Report status to lead — DO NOT commit**

Per CLAUDE.md, no commits during execution. Report:

```
W5 Settings re-skin: BUILD GREEN, TESTS GREEN (or test gap noted)
- PermissionCard: full re-skin (icon tile rounded rect, StatusPill swap, flat accent CTA, ultraThinMaterial body)
- AudioInputSettingsView: 11 rainbow leftovers migrated (.green → success, .blue → accent, .red → warn)
- DiagnosticsSettingsView, RecorderStylePicker, EnhancementSettingsView: 1-line color migrations
- LastSystemPromptViewer + FillerWordChip + DictionarySettingsPanel: chrome migrations to glass vocabulary
- GlassCard: 4pt hover-lift removed per spec §5#8 (base-primitive edit; affects every SettingsCard host)
- .tint(Palette.accent) pinned on AudioCleanup, EnhancementSettingsPanel, ModelSettingsView
- KeyboardShortcutView confirmed orphan (no production callers); flagged for separate retirement ticket
- Diff: <git diff --stat | tail -1>
- Visual smoke: Task 13 reserved as user-machine pass (env-blocked from rendering)
```

Lead reviews diff, decides whether to commit. Reviewer (`superpowers:code-reviewer`) gets the diff next; the reviewer pattern enforces (a) exhaustive check that no rainbow color remains in W5's modified set, (b) `StatusPill` reachability sanity, (c) tint-propagation verification on the three pinned surfaces, (d) confirmation that W6-touched surfaces in the same files were not re-edited.

---

## Self-review

- [x] **Spec coverage.**
  - §1 Material/Tokens: every W5 chrome surface uses `Palette.accent` / `Palette.success` / `Palette.warn` / `Palette.hairline` / `.ultraThinMaterial` + 8pt chips / 10pt icon tiles / 14pt panels. ✓
  - §5 row W5 — "Settings re-skin: `EnhancementSettingsView.swift`, `EnhancementSettingsPanel.swift`, `HotkeySettings*`, `AudioInputSettings*`, etc. Existing layout preserved; cards/chips/toggles inherit new tokens; visual diff against old screens captured." All listed surfaces covered (HotkeySettings is the SettingsView shortcuts card, already W1-correct via `SettingsCard` from W1; the W5 packet doesn't re-touch it). Layout preserved everywhere — only chrome migrates. Visual diff capture reserved as Task 13.12 for user. ✓
  - §5#8 — `GlassCard hover-lift removed (kept hover, dropped 4pt translate-y)`. Task 9 removes the `.offset(y:)` + chained `.animation(...)` from the base primitive; preserves `@State hovering` + `.onHover` per W6's ProviderCard pattern. Visual verification reserved as Task 13.9. ✓
  - W4 deferred TODO on PermissionsView rainbow cleanup — Task 1 covers it end-to-end. ✓

- [x] **Out-of-scope guard.**
  - TrialMessageView: removed in `972896a`; not referenced. ✓
  - License / Pro / Polar / Obfuscator: removed in `972896a`; not referenced. ✓
  - Onboarding / CinematicWalkthrough: removed in `972896a`; not referenced. ✓
  - Legacy constellation 4 (ConstellationCard etc.): removed in `972896a`; not referenced. ✓
  - W6's already-touched surfaces (`+` button, gear button, panel close button) — explicitly listed in "Untouched" and protected via Task 11.5 grep verification. ✓
  - W7 polish (`.rounded` → system body type, sound cue volume) — not touched; Task 9 only adds `.tint(...)` (one-line per surface), not a `.rounded` sweep. ✓
  - ContentView sidebar — not touched. ✓
  - AI Models page — explicitly listed in "Untouched"; Task 11.4 grep guard. ✓
  - Recorder cluster — not touched. ✓

- [x] **Placeholder scan.** No `TBD`, no "implement later", no "similar to Task N" without code, no "add error handling without showing how". Every step has exact code, exact file:line, or exact command.

- [x] **Type consistency.**
  - `Palette.success`, `Palette.warn`, `Palette.accent`, `Palette.hairline`, `Palette.hairlineSoft` are the correct symbol names per `Palette.swift`.
  - `StatusPill(text: String, tone: Tone)` signature matches the existing definition (Task 0.5 verifies).
  - `.tint(Palette.accent)` is the correct SwiftUI modifier signature (View → View, returns `some View`).
  - Corner radii: 8 (chips), 10 (icon tile), 14 (panel) — consistent with W6's vocabulary.

- [x] **Build cadence.** No `make local` between tasks; one full build at Task 14.1 per CLAUDE.md.

- [x] **No commits.** Final step reports to lead.

- [x] **No PR-reference comments in code samples.** All inline doc-comments cite the spec section + this plan path; none reference PR numbers.

- [x] **Pre-existing spec-ref comments preserved.** No edits to the W1-primitive files (`Palette.swift`, `GlassChip.swift`, `SettingsCard.swift`, `SettingsRow.swift`, `SettingsSectionHeader.swift`). `GlassCard.swift`'s doc-comment is rewritten in Task 9.2 — the spec ref shifts from §3.2/§4 to §5#8 to reflect the post-removal state, which is a correct update rather than a deletion.

---

## Acceptance criteria

- ✅ `make local` completes with `** BUILD SUCCEEDED **`.
- ✅ `xcodebuild test` passes (or env-block documented) — all existing tests green.
- ✅ Sweep `grep -rnE "(\.blue|\.green|\.red|\.orange)\b|Color\.accentColor" <W5 file set>` returns zero matches.
- ✅ `PermissionsView.swift`: PermissionCard's icon tile is a 10pt rounded rectangle filled with `Palette.success` / `Palette.warn`; status badge is `StatusPill` (or fallback inline mono pill); CTA is flat `Palette.accent` Capsule with hairline edge; card body is `.ultraThinMaterial` + 14pt + `Palette.hairline`.
- ✅ `AudioInputSettingsView.swift`: zero `.green`, `.blue`, `.red` literals; "Active" badges are SF Mono uppercase `Palette.success`; selected radios + chevrons + add buttons use `Palette.accent`; remove (priority) button uses `Palette.warn`.
- ✅ `DiagnosticsSettingsView.swift`: export-success checkmark uses `Palette.success`.
- ✅ `RecorderStylePicker.swift`: selected hover-tint uses `Palette.accent.opacity(0.06)`.
- ✅ `EnhancementSettingsView.swift`: drop-target stroke uses `Palette.accent.opacity(0.25)`. The W6-touched `+` and gear buttons are unchanged.
- ✅ `EnhancementSettingsPanel.swift`: LastSystemPromptViewer ScrollView chrome uses `.ultraThinMaterial` + 8pt + `Palette.hairlineSoft`. The W6-touched header chrome is unchanged.
- ✅ `FillerWordsSettingsView.swift`: FillerWordChip body uses `.ultraThinMaterial` + 8pt + `Palette.hairlineSoft`; xmark hover uses `Palette.warn`; add `+` uses `Palette.accent`.
- ✅ `DictionarySettingsPanel.swift`: close button uses 8pt glass-chip vocabulary; bottom hairline uses `Palette.hairlineSoft` rect.
- ✅ `AudioCleanupSettingsView.swift`, `EnhancementSettingsPanel.swift`, `ModelSettingsView.swift`: each pins `.tint(Palette.accent)` at body root for downstream Toggle / Picker rendering.
- ✅ `GlassCard.swift`: 4pt translate-y hover-lift removed (`.offset(y: hovering ? -4 : 0)` + chained `.animation(_, value: hovering)` deleted). `@State hovering` + `.onHover` retained for cursor-signal hook.
- ✅ Sweep `grep -rn "offset(y: hovering" VoiceInk --include="*.swift"` returns zero matches across the entire project.
- ✅ Sweep for emoji literals across the W5 file set (Task 11.7) returns zero matches.
- ✅ `KeyboardShortcutView` orphan claim verified (Task 11.6); flagged for separate cleanup ticket; not deleted in W5.
- ✅ Visual smoke pass (Task 13) reserved as a user-machine handoff item; before/after screenshots captured per spec §5 W5 acceptance; card-hover behavior verification on Step 13.9 confirms the lift is gone everywhere.

---

## Risks / unknowns

1. **`StatusPill` cross-file reachability.** `PermissionsView.swift` adopts `StatusPill` defined in `APIKeyManagementView.swift` (same Swift module, no import needed). If file-membership ever splits across modules, the call site needs an `import` or the inline fallback in Task 1.2. Current single-target setup makes this risk-free; Task 0.4 verifies before implementation.

2. **`.tint(Palette.accent)` propagation depth.** SwiftUI `.tint` cascades down the view hierarchy, but only as far as the next `.tint` modifier override (or the next NSViewRepresentable boundary). The three pins in Task 10 are surface-roots — they should propagate to all descendants. **Risk:** if a downstream Toggle / Picker has its own `.tint(.blue)` (none observed in current code), the override wins. Visual smoke pass Task 13.8 verifies.

3. **`GlassCard` hover-lift removal — folded into W5 per lead direction.** Removal via single-line edit in `GlassCard.swift` is mechanically trivial (Task 9). Visual smoke gap is real: every `SettingsCard` / `GlassCard` host across the app loses the 4pt lift on hover. The user's first impression after merge will be "the cards no longer rise on hover" — that's the intended W1+spec §5#8 result, but if a future surface depends on the lift, restore it locally rather than re-introducing the base-primitive offset. Visual verification reserved as Task 13.9.

4. **`KeyboardShortcutView` orphan retirement.** The file is 248 LOC of legacy `ShortcutKeyCap` rendering with no production callers. Per the brief: flag, don't delete in W5. **Risk:** if the user lands the W5 packet and forgets the orphan flag, the file persists indefinitely. **Mitigation:** Task 14.4 status report calls it out explicitly; lead's commit message can reference the cleanup follow-up.

5. **Inline `Picker` "Active" Label vs StatusPill consistency.** `AudioInputSettingsView` uses `Label("Active", systemImage:)` — Task 2.1 styles it like a status pill (SF Mono uppercase + capsule + hairline) but does NOT call into `StatusPill`. Reasoning: `StatusPill` doesn't accept a `systemImage:` argument; replacing the icon-bearing `Label` would lose the wave glyph. Keeping the inline form preserves the icon while migrating the color tokens. If the user wants strict consistency, a follow-up could extend `StatusPill` with an optional `systemImage:`.

6. **`CardBackground` continued use in `AudioInputSettingsView` + `DictionarySettingsView` + `PermissionsView`'s sibling sections.** W5 only migrates `PermissionCard`'s body off `CardBackground`. Other consumers stay. **Risk:** visual inconsistency between W5-migrated PermissionCard and the still-on-CardBackground audio-input device cards. **Mitigation:** within `PermissionsView` only one card type exists (PermissionCard); within `AudioInputSettingsView` all cards still use `CardBackground` (consistent with each other). Cross-screen consistency is a broader cleanup ticket — flag, don't act.

7. **`Color(NSColor.windowBackgroundColor)` and similar system-adaptive colors stay.** Per migration policy point 4. **Risk:** the user reads "rainbow cleanup" as "all hardcoded colors gone" and asks why `Color(NSColor.controlBackgroundColor)` remains in EnhancementShortcutsView. **Mitigation:** plan documents this explicitly; coder cites the rule when the user asks.

8. **Failure dwell pickers + similar functional pickers untouched.** `SettingsView` already has `Picker("", selection: $failedDwellSeconds)` for the "3 seconds / 6 seconds / Until dismissed" choice — its chrome inherits the system Picker style + the W1 SettingsRow icon tile. No re-styling needed; pickers should look like macOS-native pickers, not custom chips, because they handle multi-option selection that chips don't model well.

## Estimated effort

~3-4 hours for an engineer familiar with the codebase. ~5-6 hours for a fresh teammate. Most of the work is rote color-token migration (Tasks 2-8). The PermissionCard rebuild (Task 1) is the largest single edit (~80 LOC churn). New file count: 0; cross-file rewiring is none — every change stays inside the file being migrated. The visual smoke pass (Task 12) belongs to the user post-merge.
