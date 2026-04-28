# W7 — Type + Sound Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.

**Goal:** Cohesion pass closing out the aesthetic redesign. Three threads:
1. **`.rounded` retirement on body chrome** — drop `design: .rounded` on 7 chrome surfaces (settings headers, section titles, recorder live-transcript, history rows, picker preview, sheet header, power-mode header). Hero numerals on the metrics + onboarding surfaces explicitly KEEP `.rounded` per the brief.
2. **SF Mono on state labels** — sweep every chip / state-pill label in the codebase against the W1+W2+W6 chip vocabulary (`.font(.system(size: N, weight: .semibold, design: .monospaced))` + `.tracking(0.06 * N)` + uppercase). Fix mono-but-no-tracking, uppercase-but-no-mono, and off-spec tracking values (`0.4` / `0.5` / `0.6` raw → `0.06 * size`).
3. **Sound cue volume re-tune** — drop `CueSynthesizer.masterGain` from 0.45 to 0.32 and `SoundManager.loadAndPreparePlayer`'s custom-override volume from 0.4 to 0.28 to match the lighter aesthetic. No asset replacement; volume only.

**Architecture (type migration map):**

```
Surface category                         W7 decision
─────────────────────────────────        ─────────────────────────────────
Hero numerals on metrics dashboards  →   KEEP `.rounded` (display type)
   (MetricsContent hero, MetricCard,        → MetricsContent.swift:157
    PerformanceAnalysisView,                → MetricCard.swift:31
    PerformanceAnalysisPanelView,           → PerformanceAnalysisPanelView.swift:82,170,243
    MetricsSetupView welcome)               → PerformanceAnalysisView.swift:265,346,409
                                            → MetricsSetupView.swift:21

Body chrome / section titles         →   REPLACE — drop `, design: .rounded`
   (SettingsSectionHeader title,            → SettingsSectionHeader.swift:47
    DictionarySettingsView section,         → DictionarySettingsView.swift:147
    HelpAndResourcesSection title,          → HelpAndResourcesSection.swift:7
    PowerModeConfigView header,             → PowerModeConfigView.swift:164
    RecorderStylePicker preview title,      → RecorderStylePicker.swift:90
    HaloRecorderView live transcript,       → HaloRecorderView.swift:69
    TranscriptionListItem timestamp,        → TranscriptionListItem.swift:37
    TranscriptionDetailView header time)    → TranscriptionDetailView.swift:92

State pills / chip labels            →   SF MONO uppercase 0.06em tracking
   (SettingsSectionHeader statusText)       → SettingsSectionHeader.swift:61

Orphan surfaces                      →   IGNORE (not retired in W7)
   (KeyboardShortcutView line 155)          → handoff says separate cleanup ticket
```

**Architecture (SF Mono normalization map):**

```
Site                                       Current                                            W7 fix
─────────────────────────────────────      ─────────────────────────────────────              ─────────────────────────
SettingsSectionHeader.swift:61             10pt semibold rounded + tracking(0.5)              → mono + tracking(0.06*10) + textCase(.uppercase)
PowerMode/PowerModeActivePill.swift:39      9pt semibold mono — NO tracking                   → add tracking(0.06*9)
PowerMode/PowerModeStripView.swift:120      8pt semibold mono — NO tracking ("DEFAULT")        → add tracking(0.06*8)
PowerMode/PowerModePopover.swift:143       10pt semibold mono — NO tracking ("SWITCH")        → add tracking(0.06*10)
PowerMode/PowerModePopover.swift:263        9pt semibold mono — NO tracking ("DEFAULT")        → add tracking(0.06*9)
Views/Components/PromptLivePreview.swift:178 10pt semibold default + tracking(0.6)             → switch design to .monospaced, keep size + tracking
Views/History/TranscriptionDetailView.swift:153 10pt semibold mono + tracking(0.4)             → normalize to tracking(0.06*10)
Views/History/TranscriptionDetailView.swift:181  9pt semibold mono + tracking(0.6)             → normalize to tracking(0.06*9)
Views/History/TranscriptionListItem.swift:43  10pt semibold mono + tracking(0.4)               → normalize to tracking(0.06*10)
Views/Common/GlassSwitch.swift:82,89        11pt semibold mono — NO tracking (#Preview only)  → add tracking(0.06*11)
```

**Architecture (sound cue volume re-tune):**

```
Knob                                          Current   W7 value   Δ (perceived)
─────────────────────────────────────────     ───────   ────────   ──────────────────
CueSynthesizer.masterGain (Float)             0.45      0.32       ~3 dB quieter, ~30% perceived drop
SoundManager.loadAndPreparePlayer volume      0.40      0.28       matched relative drop for custom overrides
SoundManager.playStartSound override volume   0.40      0.28       same — start cue with custom override
```

The `masterGain` knob is the **single normalization point** for synthesized cues; the `CueSynthesizer` doc-comment already declares "loudest cue (start pluck — single voice peaking near 1.0) sits comfortably below clipping while quieter cues remain audible." Lowering `masterGain` keeps the relative balance between cues intact (start vs transcribe vs enhance vs cancel vs fail) and only pulls the whole 5-cue palette down a notch. Per-cue amplitudes (the `amp` constants in `parameters(for:)`) are NOT changed — that would shift the relative balance the synth was tuned for.

**Tech Stack:** Swift 5.x, SwiftUI, AVFoundation (for `AVAudioPlayer.volume`), Xcode 16.x. Build via `make local` (~3 min cold). No new dependencies.

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material/Tokens — "SF Mono uppercase tracking 0.06em for state labels and chip keys. System (`-apple-system`) for prose, body, and main-window content. Retire `.rounded` design tokens for state surfaces."), §5 row W7 ("Type + sound polish: Find/replace `.rounded` → system in body type; verify SF Mono on state labels; sound cue volume re-tune to match new 'lighter' aesthetic. No `.rounded` outside designated places; chip labels uniformly SF Mono."). §5#8 (`GlassCard` hover-lift removal) was already shipped in W5 — not redone here.

**CLAUDE.md cadence rules respected:**
- **Single integration build at merge time.** No `make local` per task; one full build at the final task.
- **No commits during execution.** Final step reports to lead; lead handles commits.
- **No `xcodebuild` per file.** SourceKit handles per-file syntax during edits; integration build is the gate.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code samples.** All inline doc-comment edits cite the spec section + this plan path; none reference PR numbers.
- **Pre-existing spec-ref comments preserved.** `Palette.swift` §1 ref, `GlassChip.swift` §1 ref, `SettingsCard.swift` §3.3 ref, `SoundManager.swift` §3.10 ref, `CueSynthesizer.swift` §3.10/§6.3 ref are not removed; new comments added only where the WHY is non-obvious (e.g. the masterGain re-tune line cites §5 row W7).

---

## File structure

### New files

None. W7 is entirely a token-vocabulary polish + audio-volume re-tune packet. No new types, no new primitives.

### Modified files

- `VoiceInk/Views/Common/SettingsSectionHeader.swift` — drop `, design: .rounded` on the title (line 47); migrate the statusText pill (lines 60-72) to SF Mono uppercase 0.06em tracking, keep the existing capsule + stroke geometry, drop the rounded design + `tracking(0.5)`. Add a `.textCase(.uppercase)` so callers (`"On"`, `"Off"`, `"1 active"`, `"\(count)"`, `"2 active"`, etc.) render uppercase without each call site uppercasing manually. ~+4 LOC, -3 LOC.
- `VoiceInk/Views/Dictionary/DictionarySettingsView.swift` — drop `, design: .rounded` on the section title at line 147. ~+0 LOC, -0 LOC (single replacement on one line).
- `VoiceInk/Views/Settings/RecorderStylePicker.swift` — drop `, design: .rounded` on the preview-card title at line 90. ~+0 LOC, -0 LOC.
- `VoiceInk/PowerMode/PowerModeConfigView.swift` — drop `, design: .rounded` on the sheet header `mode.title` at line 164. ~+0 LOC, -0 LOC.
- `VoiceInk/Views/Metrics/HelpAndResourcesSection.swift` — drop `, design: .rounded` on the "Help & Resources" section title at line 7. ~+0 LOC, -0 LOC.
- `VoiceInk/Views/History/TranscriptionListItem.swift` — drop `, design: .rounded` on the row timestamp at line 37; normalize the durationPill tracking from `0.4` to `0.06 * 10` at line 43. ~+0 LOC, -0 LOC.
- `VoiceInk/Views/History/TranscriptionDetailView.swift` — drop `, design: .rounded` on the header timestamp at line 92; normalize the durationPill tracking from `0.4` to `0.06 * 10` at line 153; normalize the textPane `sectionLabel` tracking from `0.6` to `0.06 * 9` at line 183. ~+0 LOC, -0 LOC.
- `VoiceInk/Views/Recorder/HaloRecorderView.swift` — drop `, design: .rounded` on the live-transcript text at line 69. ~+0 LOC, -0 LOC.
- `VoiceInk/PowerMode/PowerModeActivePill.swift` — add `.tracking(0.06 * 9)` after the SF Mono font at line 39 so the 9pt uppercase pill matches the W1 chip vocab. ~+1 LOC.
- `VoiceInk/PowerMode/PowerModeStripView.swift` — add `.tracking(0.06 * 8)` after the SF Mono font on the "DEFAULT" pill at line 120. ~+1 LOC.
- `VoiceInk/PowerMode/PowerModePopover.swift` — add `.tracking(0.06 * 10)` after the SF Mono font on the "SWITCH" header at line 143; add `.tracking(0.06 * 9)` after the SF Mono font on the "DEFAULT" pill at line 263. ~+2 LOC.
- `VoiceInk/Views/Components/PromptLivePreview.swift` — switch the `sectionLabel` font from default system to monospaced at line 178; tracking already correct (`0.6` ≈ `0.06 * 10`). ~+0 LOC, -0 LOC (parameter change on existing line).
- `VoiceInk/Views/Common/GlassSwitch.swift` — add `.tracking(0.06 * 11)` after the SF Mono font on the two preview labels (lines 82, 89). Preview-only surface but kept consistent. ~+2 LOC.
- `VoiceInk/Audio/CueSynthesizer.swift` — change `masterGain` constant from `0.45` to `0.32` at line 37; update the doc-comment above the constant (lines 34-37) to cite §5 row W7 as the volume-tune rationale. ~+2 LOC, -2 LOC.
- `VoiceInk/SoundManager.swift` — change the two `player?.volume = 0.4` / `player.volume = 0.4` literals (lines 63, 93) to `0.28`. Inline comment cites §5 row W7. ~+2 LOC, -2 LOC.

### Retired files (delete)

None. `KeyboardShortcutView.swift`'s `.rounded` at line 155 is left untouched per the W5 planner's note (orphan retirement is a separate cleanup ticket; W7 does not delete the file or edit it).

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Views/Common/Palette.swift` — token vocabulary (W1). Out of bounds.
- `VoiceInk/Views/Common/GlassChip.swift` / `GlassPanel*` (if exists) / `GlassCard.swift` — primitives (W1 + W5#8). Out of bounds. The W5 planner removed the GlassCard hover-lift; do not re-touch the file.
- `VoiceInk/Views/Common/GlassAppearance.swift` / `GlassAppearanceDetector.swift` — appearance detector (W1). Out of bounds.
- `VoiceInk/Views/Common/SettingsCard.swift` / `SettingsRow.swift` — settings card primitives (W1 / W5). Out of bounds. (`SettingsSectionHeader.swift` IS in scope — it's the only primitive with state-pill + title rendering for W7.)
- `VoiceInk/Views/Common/ProviderChipStyle.swift` / `ProviderChip.swift` — provider chip helpers (W6). Out of bounds.
- `VoiceInk/Views/Recorder/Constellation/{ConstellationCluster,ChipPanel,ClusterChips,ClusterMotion,ClusterPhase}.swift` — W2/W3 territory. Already SF Mono + 0.06em tracking. Confirmed via grep (lines 291, 315, 319, 336, 376, 413 all use `0.06 * size` tracking).
- `VoiceInk/Views/AI Models/MLXModelPickerView.swift` / `ProviderCard.swift` / `APIKeyManagementView.swift` — W6 surfaces. Already W1+W6 chip-vocab compliant.
- `VoiceInk/Views/PromptEditorView.swift` — W6 surface; chrome already migrated.
- `VoiceInk/Services/FailureRegistry.swift` / `FailureEvent.swift` — W3 territory.
- `VoiceInk/Views/Metrics/MetricCard.swift` (line 31, 24pt black `.rounded`) — hero numeral, KEEP per brief.
- `VoiceInk/Views/Metrics/MetricsContent.swift` (line 157, 36pt black `.rounded`) — hero numeral on the formatted-time-saved render, KEEP per brief.
- `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift` (lines 82, 170, 243) — hero numerals (summary pill, speed-factor, enhancement-time), KEEP per brief.
- `VoiceInk/Views/Metrics/PerformanceAnalysisView.swift` (lines 265, 346, 409) — hero numerals (MetricDisplay, speed-factor, enhancement-time), KEEP per brief.
- `VoiceInk/Views/Metrics/MetricsSetupView.swift` (line 21, 28pt bold `.rounded`) — onboarding hero "Welcome to VoiceInk", KEEP per brief (display-type marquee).
- `VoiceInk/Views/KeyboardShortcutView.swift` (line 155, 25pt semibold `.rounded`) — orphan flagged in W5. Out of W7 scope.
- `VoiceInk/Views/Settings/EnhancementShortcutsView.swift` (`KeyChip` SF Mono at line 55) — keyboard-key cap glyph (Cmd, Shift, etc.), not a state label. SF Mono is appropriate; tracking would over-space key glyphs. UNTOUCHED.
- `VoiceInk/Views/Common/KeyCapView.swift` (lines 39, 113 — SF Mono with no tracking) — same reasoning: keyboard-key cap. UNTOUCHED.
- `VoiceInk/Views/Common/ProviderChip.swift` (line 43, SF Mono regular for model name) — model-id text body, not a state label. UNTOUCHED.
- `VoiceInk/Views/Common/TranscriptionInfoPanel.swift` (lines 100, 113 — SF Mono regular for prompt text) — code/prompt body content, not chip labels. UNTOUCHED.
- `VoiceInk/Views/Components/EnhancementSettingsPanel.swift` (line 187, SF Mono 11pt for prompt body) — prompt content body, not chip label. UNTOUCHED.
- `VoiceInk/Views/Settings/CustomSoundSettingsView.swift` (line 74, SF Mono 10pt) — caption / data text, not a chip label. UNTOUCHED.
- `VoiceInk/Views/Settings/AudioInputSettingsView.swift` (lines 76, 337, 397 — already SF Mono 10.5pt + tracking 0.06*10.5 from W5). Already chip-vocab compliant. UNTOUCHED.
- `VoiceInk/Views/AI Models/APIKeyManagementView.swift` (lines 77, 81 — already chip-vocab compliant). UNTOUCHED.
- `VoiceInk/Transcription/Whisper/WhisperModelManager.swift` (line 453, SF Mono % progress label) — numeric data text, not chip label. UNTOUCHED.
- `VoiceInk/Views/AudioPlayerView.swift` (lines 204, 408, 483 `.monospacedDigit()`) — digit-only timestamps, not chip labels. UNTOUCHED.
- `VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift` (lines 184, 198 SF Mono for stat labels) — descriptive stat labels with tracking already absent; consistent with the metrics dashboard's hero-numeral style. UNTOUCHED to avoid scope creep into a metrics-page redesign.
- `VoiceInk/Views/Metrics/PerformanceAnalysisView.swift` (line 470 SF Mono `.body, weight: .semibold`) — system info row label, body data not a chip. UNTOUCHED.
- `VoiceInk/Views/Common/PromptChipPicker.swift` (line 156 SF Mono 11pt with NO tracking) — IS a chip-style label, missing tracking. **NOTE:** Out of scope decision below — see Migration policy point 5.
- `VoiceInk/PowerMode/PowerModeConfigView.swift` (lines 377, 408 SF Mono for code/text fields) — text-field content rendering, not a chip label. UNTOUCHED.
- `VoiceInk/Views/Common/Animation+Halo.swift` (line 219 `.caption.monospaced()`) — debug overlay only. UNTOUCHED.
- `VoiceInk/Views/Common/SettingsRow.swift` (line 87 SF Mono 12pt) — single-row data text, not chip label. UNTOUCHED.
- `VoiceInk/Audio/CueSynthesizer.swift` per-cue amplitudes (`amp = 0.85` for start, `baseAmp = 0.65` for transcribe, `0.50` + `0.50 * 0.70` for enhance, `0.60` for cancel, `0.65` for fail) — relative balance UNCHANGED. Only the `masterGain` knob moves. The synth's per-cue tuning encodes the cue identity; touching individual amps risks shifting the cue character beyond a "lighter" volume re-tune.
- `VoiceInk/SoundManager.swift` AppStorage key `isSoundFeedbackEnabled` — UNTOUCHED. Spec did not call for a volume slider; a future packet might add one.
- All `Capsule(...)` and `RoundedRectangle(...)` chip geometry around the SF Mono labels W7 touches — UNTOUCHED. W7 is type-vocabulary-only; chip chrome was migrated by W1 / W5 / W6 already.
- `VoiceInk/CustomSoundManager.swift` — user-supplied audio asset registry. UNTOUCHED — assets stay (per brief: volume tuning only, no asset swap).
- All test files (`VoiceInkTests/*.swift`) — W7 ships no new tests. Existing `PaletteTests` (2) + `FailureRegistryTests` (5) + `VoiceInkUITests` (4) must still pass at the integration build (Task 15).

---

## Migration policy (resolves ambiguity for each design point)

1. **`.rounded` retirement scope is "body chrome", not "everything".** Per spec §5 row W7 acceptance: "No `.rounded` outside designated places; chip labels uniformly SF Mono." The "designated places" are display-type hero numerals on the metrics + onboarding surfaces — the brief explicitly preserves those. Body chrome (settings headers, list rows, picker preview titles, sheet headers) loses `.rounded`. The 19 `.rounded` survivor sites split as: 12 KEEP, 6 REPLACE, 1 SF-MONO migrate (`SettingsSectionHeader` statusText), and 0 IGNORE-for-now (`KeyboardShortcutView` orphan covered by W5 planner's separate cleanup ticket).

2. **`SettingsSectionHeader.swift` is in W7 scope despite being a W1 primitive.** The W5 plan explicitly treated it as untouched, but it has TWO `.rounded` design tokens (lines 47 + 61). The spec §1 line "Retire `.rounded` design tokens for state surfaces" puts the statusText pill in scope. The title (line 47) is body chrome — also in scope. Both ride into W7 in a single primitive edit; blast radius is every `SettingsSectionHeader` host across the app (Settings hub, Enhancement panel, AI Models page) and is intentional — they're meant to read as a single vocabulary.

3. **SF Mono tracking normalization rule.** The W1 chip vocab says `tracking(0.06 * size)`. Sites currently using `tracking(0.5)`, `tracking(0.6)`, `tracking(0.4)` get normalized to the formula. The values are tiny visually (`0.06 * 10 = 0.6` vs `0.4` — a 0.2pt delta) but the spec is the spec; the chip vocab is "uniformly SF Mono with 0.06em tracking" per W7 acceptance. Mechanical replacement.

4. **`.textCase(.uppercase)` on `SettingsSectionHeader.statusText`.** Callers pass mixed case (`"On"`, `"Off"`, `"1 active"`, `"2 active"`, `"\(count)"`). Adding `.textCase(.uppercase)` at the helper avoids per-call-site `.uppercased()` rewrites and matches the ClusterChips / W6 chip vocab where chip labels render uppercase via the call-site or helper. The numeric `"\(count)"` case (lines 127 of `EnhancementSettingsView`) renders unchanged — `.textCase(.uppercase)` is a no-op on digits. This is a behavior change but the rendered output (`"ON"` instead of `"On"`) matches the chip-vocab everyone else has been migrated to.

5. **`PromptChipPicker.swift` line 156 chip label — DEFER.** Reads from grep as a chip-style label (size 11pt, semibold, mono, no tracking) but the file is the prompt-chip picker grid in the Recorder cluster phase, not a settings/state label. Given the W2 cluster has full tracking already (`ClusterChips.swift`), this is likely a minor inconsistency, but adding `tracking(0.06 * 11)` here is a one-line edit. The plan defers it to keep scope tight: the brief says "verify SF Mono on state labels" — this is a prompt label rendering inside an action button, not a state pill. Out of scope; flag in self-review.

6. **`PowerMode` surfaces in W7 scope.** PowerMode pills use SF Mono uppercase but ALL of them lack the W1 chip-vocab tracking. Three call sites (PowerModeActivePill, PowerModeStripView "DEFAULT", PowerModePopover "DEFAULT" + "SWITCH") gain a `.tracking(0.06 * size)` line each. Mechanical. The PowerMode dashboard chrome (sheet header at PowerModeConfigView line 164) takes the `.rounded` retirement pass alongside.

7. **Sound cue volume target — subjective; one knob, one ratio.** The brief says "match the new 'lighter' aesthetic" — quieter cues. Two interpretations:
   - **Drop master gain only.** Single change to `CueSynthesizer.masterGain`. Affects all 5 synthesized cues uniformly. Custom-override player volume stays at 0.4. **Risk:** users with custom audio assets hear them louder than the synthesized cues, breaking parity.
   - **Drop master gain AND custom-override volume.** Both knobs move. Custom asset replays and synth cues stay balanced. **W7 picks this** — preserves the cue-volume parity the original `0.4` was calibrated against.
   The specific values (0.45 → 0.32 for master gain; 0.40 → 0.28 for custom override) are chosen to (a) drop perceived loudness ~30% — meaningful "lighter" but not whisper-quiet; (b) preserve relative balance between knobs (each drops ~30%; ratio 0.45:0.40 ≈ 0.32:0.28); (c) stay well above the floor where the start cue's single 880Hz pluck would become inaudible against ambient noise. Volume tuning is inherently subjective — the user should sanity-check on real hardware (Task 14.6) and the plan's Risks section flags this as the #1 punted item.

8. **No per-cue amplitude tweaks.** The synth's `parameters(for:)` table encodes cue identity (start = single pluck + overtone; transcribe = 4-voice maj7 arpeggio; enhance = stacked 8-voice; cancel = 2-note descent; fail = 2-note minor descent). Per-cue amps were tuned for relative loudness parity at masterGain=0.45. Touching them risks shifting the cue character (e.g. making fail "feel" different relative to cancel). Volume tune knob is masterGain only.

9. **No new AppStorage key for user-tunable volume.** Spec §5 row W7 calls for a "re-tune" — i.e. a new default. NOT a new user-facing slider. The existing `isSoundFeedbackEnabled` AppStorage stays; W7 only changes the hard-coded volume defaults. **Migration risk:** there's no per-user state to migrate (no existing AppStorage volume key), so all installs land on the new defaults at next launch. Documented in Risks/unknowns #1.

10. **No emoji in code.** The `🦾` emoji prefixes in `MLXProvider.swift` log lines are pre-existing instrumentation markers (W6 documented exception). W7 introduces no new log lines and no new emojis.

11. **Pre-existing spec-ref comments preserved.** `SoundManager.swift:13-18` references "spec §3.10 / plan P3.F + P3.G". `CueSynthesizer.swift:5-20` references "P3.F / spec §3.10, §6.3". W7 adds a one-line cite ("§5 row W7 — lighter-aesthetic re-tune") next to the changed numeric values; doesn't replace the existing references.

---

## Tasks

### Task 0: Audit + sweep references

**Files:** none (read-only).

- [ ] **Step 0.1: Confirm the `.rounded` survivor inventory**

```bash
grep -rn "design: \.rounded\|, design: \.rounded)\|design: \.rounded," VoiceInk --include="*.swift"
```

Expected matches (19 sites total, must match plan's classification):

```
VoiceInk/PowerMode/PowerModeConfigView.swift:164                 — REPLACE
VoiceInk/Views/KeyboardShortcutView.swift:155                    — IGNORE (orphan)
VoiceInk/Views/Metrics/MetricsContent.swift:157                  — KEEP
VoiceInk/Views/Metrics/HelpAndResourcesSection.swift:7           — REPLACE
VoiceInk/Views/Metrics/MetricsSetupView.swift:21                 — KEEP
VoiceInk/Views/Settings/RecorderStylePicker.swift:90             — REPLACE
VoiceInk/Views/Metrics/MetricCard.swift:31                       — KEEP
VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:82     — KEEP
VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:170    — KEEP
VoiceInk/Views/Metrics/PerformanceAnalysisPanelView.swift:243    — KEEP
VoiceInk/Views/Metrics/PerformanceAnalysisView.swift:265         — KEEP
VoiceInk/Views/Metrics/PerformanceAnalysisView.swift:346         — KEEP
VoiceInk/Views/Metrics/PerformanceAnalysisView.swift:409         — KEEP
VoiceInk/Views/Dictionary/DictionarySettingsView.swift:147       — REPLACE
VoiceInk/Views/Common/SettingsSectionHeader.swift:47             — REPLACE
VoiceInk/Views/Common/SettingsSectionHeader.swift:61             — SF-MONO
VoiceInk/Views/History/TranscriptionDetailView.swift:92          — REPLACE
VoiceInk/Views/Recorder/HaloRecorderView.swift:69                — REPLACE
VoiceInk/Views/History/TranscriptionListItem.swift:37            — REPLACE
```

If a NEW `.rounded` site appears (a file landed since plan-time), reconcile with the lead before proceeding — don't drift the plan classification. The `KeyboardShortcutView.swift:155` site stays untouched per W5 planner's note (orphan retirement is a separate ticket).

- [ ] **Step 0.2: Confirm the SF Mono chip-label inventory**

```bash
grep -rn "design: \.monospaced" VoiceInk --include="*.swift" | grep -v "//"
```

Expected matches: 35-40 sites. Compare against the plan's "SF Mono normalization map" — every chip-style label that needs `.tracking(0.06 * size)` is enumerated in the architecture map at the top. If a NEW SF Mono chip-style label appears outside the map, reconcile with the lead before proceeding.

- [ ] **Step 0.3: Confirm `SoundManager` + `CueSynthesizer` are the right volume knobs**

```bash
grep -rn "masterGain\|player\\.volume\|player?\\.volume\|\\.volume = " VoiceInk --include="*.swift"
```

Expected matches:
- `VoiceInk/Audio/CueSynthesizer.swift:37` — `static let masterGain: Float = 0.45`
- `VoiceInk/Audio/CueSynthesizer.swift:241` — `for i in 0..<totalFrames { raw[i] *= masterGain }` (waveform render — still scales by gain)
- `VoiceInk/Audio/CueSynthesizer.swift:334` — `for i in 0..<totalFrames { channel[i] *= CueSynthesizer.masterGain }` (live render)
- `VoiceInk/SoundManager.swift:63` — `player?.volume = 0.4` (custom override loader)
- `VoiceInk/SoundManager.swift:93` — `player.volume = 0.4` (start-sound custom override at play time)

If a third volume knob exists (e.g. an `@AppStorage("cueVolume")` key was added between plan-time and execution), reconcile with the lead — the migration story changes.

- [ ] **Step 0.4: Confirm `SettingsSectionHeader` callers**

```bash
grep -rn "statusText:" VoiceInk --include="*.swift"
```

Expected matches at: `EnhancementSettingsView.swift:72,127`, `Settings/SettingsView.swift:81,636`, `Common/SettingsCard.swift:43,72`, `AI Models/APIKeyManagementView.swift:142`. All callers pass mixed-case strings ("On", "Off", "1 active", "2 active", "\(count)", `providerStatusText`). After Task 1 lands `.textCase(.uppercase)` on the helper, every existing caller renders uppercase without changes — confirm this matches the chip vocab the W2/W6 cluster surfaces already use.

- [ ] **Step 0.5: Confirm `KeyboardShortcutView` orphan claim still holds**

```bash
grep -rn "KeyboardShortcutView(" VoiceInk --include="*.swift"
```

Expected: only matches inside `VoiceInk/Views/KeyboardShortcutView.swift` itself (the `#Preview` block at lines 244-245). If any production call site surfaces, escalate to lead — the file may not be safe to leave alone.

---

### Task 1: Migrate `SettingsSectionHeader` — drop `.rounded` on title + chip-vocab on statusText

**Files:**
- Modify: `VoiceInk/Views/Common/SettingsSectionHeader.swift`

- [ ] **Step 1.1: Replace the title font (line 47)**

Current:

```swift
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
```

Replace with:

```swift
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
```

Single change: drop `, design: .rounded`. Default system design is implied. Body chrome — no longer state surface, per spec §1 retirement rule.

- [ ] **Step 1.2: Replace the statusText pill font + tracking + textCase (lines 60-72)**

Current:

```swift
            if let statusText {
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.5)
                    .foregroundColor(statusTone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(statusTone.color.opacity(0.14))
                    )
                    .overlay(
                        Capsule().stroke(statusTone.color.opacity(0.32), lineWidth: 0.5)
                    )
            }
```

Replace with:

```swift
            if let statusText {
                Text(statusText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 10)
                    .textCase(.uppercase)
                    .foregroundColor(statusTone.color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(statusTone.color.opacity(0.14))
                    )
                    .overlay(
                        Capsule().stroke(statusTone.color.opacity(0.32), lineWidth: 0.5)
                    )
            }
```

Three diffs: (a) `design: .rounded` → `design: .monospaced` (W1 chip vocab); (b) `tracking(0.5)` → `tracking(0.06 * 10)` (chip vocab spec); (c) added `.textCase(.uppercase)` so callers pass mixed case (`"On"`, `"Off"`, `"1 active"`, etc.) but render uppercase without per-call-site rewrites. The capsule chrome (fill + stroke) stays untouched.

- [ ] **Step 1.3: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Common/SettingsSectionHeader.swift | head -40
```

Expected: title font drops `.rounded`; statusText font switches to monospaced; tracking switches to formula; `.textCase(.uppercase)` added. The `.padding(.bottom, 4)` and outer `.textCase(nil)` (line 76 — opting OUT of Form's automatic uppercase on section headers) stay — that's a different scope (Form-wide vs the inline statusText label).

---

### Task 2: Drop `.rounded` on `DictionarySettingsView` section title

**Files:**
- Modify: `VoiceInk/Views/Dictionary/DictionarySettingsView.swift`

- [ ] **Step 2.1: Replace line 147**

Current:

```swift
                    Text(section.rawValue)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
```

Replace with:

```swift
                    Text(section.rawValue)
                        .font(.system(size: 15, weight: .semibold))
```

Single change: drop `, design: .rounded`. Body chrome — section title inside the dictionary settings card row.

---

### Task 3: Drop `.rounded` on `RecorderStylePicker` preview-card title

**Files:**
- Modify: `VoiceInk/Views/Settings/RecorderStylePicker.swift`

- [ ] **Step 3.1: Replace line 90**

Current:

```swift
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
```

Replace with:

```swift
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
```

Single change: drop `, design: .rounded`. The picker preview title under each recorder-style card is body chrome.

The 5pt monospaced labels at lines 197 + 215 (preview hover-glyph rendering) stay untouched — they're inside the preview card itself, intentionally micro-rendered as design ornament; not chip labels.

---

### Task 4: Drop `.rounded` on `PowerModeConfigView` sheet header

**Files:**
- Modify: `VoiceInk/PowerMode/PowerModeConfigView.swift`

- [ ] **Step 4.1: Replace line 164**

Current:

```swift
            Text(mode.title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
```

Replace with:

```swift
            Text(mode.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.primary)
```

Single change: drop `, design: .rounded`. Body chrome — sheet header title for the power-mode config sheet.

The `.roundedBorder` text-field-style at lines 250 + 376 are SwiftUI textfield style enum values, not `.rounded` design tokens — leave alone.

---

### Task 5: Drop `.rounded` on `HelpAndResourcesSection` title

**Files:**
- Modify: `VoiceInk/Views/Metrics/HelpAndResourcesSection.swift`

- [ ] **Step 5.1: Replace line 7**

Current:

```swift
            Text("Help & Resources")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary.opacity(0.8))
```

Replace with:

```swift
            Text("Help & Resources")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.primary.opacity(0.8))
```

Single change: drop `, design: .rounded`. Body chrome — section header on the metrics dashboard's help section. Distinguished from the metrics dashboard's HERO numerals (kept) by being prose body, not a number.

---

### Task 6: Drop `.rounded` on `TranscriptionListItem` timestamp + normalize duration-pill tracking

**Files:**
- Modify: `VoiceInk/Views/History/TranscriptionListItem.swift`

- [ ] **Step 6.1: Replace line 37 (timestamp)**

Current:

```swift
                    Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
```

Replace with:

```swift
                    Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
```

Single change: drop `, design: .rounded`. Body chrome — list-row timestamp in transcription history.

- [ ] **Step 6.2: Normalize duration-pill tracking (line 43)**

Current:

```swift
                        Text(transcription.duration.formatTiming())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.4)
```

Replace with:

```swift
                        Text(transcription.duration.formatTiming())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(0.06 * 10)
```

Single change: `tracking(0.4)` → `tracking(0.06 * 10)` (= 0.6). Brings duration pill to W1 chip-vocab spec. The capsule chrome + `Palette.neutral` color stay untouched.

---

### Task 7: Drop `.rounded` on `TranscriptionDetailView` header timestamp + normalize tracking on durationPill + sectionLabel

**Files:**
- Modify: `VoiceInk/Views/History/TranscriptionDetailView.swift`

- [ ] **Step 7.1: Replace line 92 (header timestamp)**

Current:

```swift
                Text(transcription.timestamp,
                     format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
```

Replace with:

```swift
                Text(transcription.timestamp,
                     format: .dateTime.year().month(.abbreviated).day().hour().minute())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
```

Single change: drop `, design: .rounded`. Body chrome — detail view header timestamp.

- [ ] **Step 7.2: Normalize durationPill tracking (line 153)**

Current:

```swift
        Text(transcription.duration.formatTiming())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.4)
```

Replace with:

```swift
        Text(transcription.duration.formatTiming())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.06 * 10)
```

Single change: `tracking(0.4)` → `tracking(0.06 * 10)` (= 0.6). Same change Task 6 made on the list-item duration pill. Both surfaces now match.

- [ ] **Step 7.3: Normalize textPane sectionLabel tracking (line 183)**

Current:

```swift
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(0.6)
```

Replace with:

```swift
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(0.06 * 9)
```

Single change: `tracking(0.6)` → `tracking(0.06 * 9)` (= 0.54). Brings the pane section label to W1 chip-vocab spec. Visually a 0.06pt tightening — barely perceptible on the rendered glyph but spec-compliant.

---

### Task 8: Drop `.rounded` on `HaloRecorderView` live transcript

**Files:**
- Modify: `VoiceInk/Views/Recorder/HaloRecorderView.swift`

- [ ] **Step 8.1: Replace line 69 (displayText)**

Current:

```swift
                    Text(displayText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(maxWidth: maxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
```

Replace with:

```swift
                    Text(displayText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.95))
                        .frame(maxWidth: maxWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
```

Single change: drop `, design: .rounded`. Body prose — the live partial-transcript text in the recorder host pill. The transcript is content body (variable-length user prose), not display chrome.

The `BlinkingCaret` view + the ScrollView geometry stay untouched.

---

### Task 9: Add chip-vocab tracking to `PowerModeActivePill`

**Files:**
- Modify: `VoiceInk/PowerMode/PowerModeActivePill.swift`

- [ ] **Step 9.1: Add tracking after the SF Mono font (line 39)**

Current:

```swift
                Text(name.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
```

Replace with:

```swift
                Text(name.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 9)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 120, alignment: .leading)
```

Single addition: `.tracking(0.06 * 9)` after the font modifier. Brings the active-pill mode-name to W1 chip-vocab spec (uppercase, mono, 0.06em tracking). The `.uppercased()` call site is preserved — already uppercase per existing code.

---

### Task 10: Add chip-vocab tracking to PowerMode "DEFAULT" + "SWITCH" pills

**Files:**
- Modify: `VoiceInk/PowerMode/PowerModeStripView.swift`
- Modify: `VoiceInk/PowerMode/PowerModePopover.swift`

- [ ] **Step 10.1: Add tracking on "DEFAULT" pill in `PowerModeStripView` (line 120)**

Current:

```swift
                        Text("DEFAULT")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(Palette.warn)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Palette.warn.opacity(0.16))
                            )
```

Replace with:

```swift
                        Text("DEFAULT")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(0.06 * 8)
                            .foregroundColor(Palette.warn)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Palette.warn.opacity(0.16))
                            )
```

Single addition: `.tracking(0.06 * 8)` after the font modifier.

- [ ] **Step 10.2: Add tracking on "SWITCH" header in `PowerModePopover` (line 143)**

Current:

```swift
            Text("SWITCH")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
```

Replace with:

```swift
            Text("SWITCH")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(0.06 * 10)
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
```

Single addition: `.tracking(0.06 * 10)` after the font modifier.

- [ ] **Step 10.3: Add tracking on "DEFAULT" pill in `PowerModePopover` (line 263)**

Current:

```swift
                if config.isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(Palette.warn)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Palette.warn.opacity(0.16))
                        )
                }
```

Replace with:

```swift
                if config.isDefault {
                    Text("DEFAULT")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.06 * 9)
                        .foregroundColor(Palette.warn)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Palette.warn.opacity(0.16))
                        )
                }
```

Single addition: `.tracking(0.06 * 9)` after the font modifier.

The `autoDetectedCaption` SF Mono caption at line 81 is data text (caption / descriptor), NOT a chip label — leave UNTOUCHED.

---

### Task 11: Migrate `PromptLivePreview.sectionLabel` to SF Mono

**Files:**
- Modify: `VoiceInk/Views/Components/PromptLivePreview.swift`

- [ ] **Step 11.1: Switch the section label font to monospaced (line 178)**

Current:

```swift
    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
```

Replace with:

```swift
    private func sectionLabel(_ s: String) -> some View {
        Text(s.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.06 * 10)
            .foregroundStyle(.secondary)
    }
```

Two diffs: (a) add `, design: .monospaced` to the font; (b) `tracking(0.6)` → `tracking(0.06 * 10)` (numerically identical at `0.6`, but spelled in the W1 formula form for grep-consistency with the rest of the chip vocab).

The `.uppercased()` text transform stays inline. The `.foregroundStyle(.secondary)` and the call sites (whatever they are inside `PromptLivePreview`) stay untouched.

---

### Task 12: Add chip-vocab tracking to `GlassSwitch` preview labels

**Files:**
- Modify: `VoiceInk/Views/Common/GlassSwitch.swift`

- [ ] **Step 12.1: Add tracking on "AI ENHANCEMENT" label (line 82)**

Current:

```swift
                Text("AI ENHANCEMENT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(backgroundIsLight ? .black.opacity(0.6) : .white.opacity(0.6))
```

Replace with:

```swift
                Text("AI ENHANCEMENT")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 11)
                    .foregroundColor(backgroundIsLight ? .black.opacity(0.6) : .white.opacity(0.6))
```

- [ ] **Step 12.2: Add tracking on "PAUSE MEDIA" label (line 89)**

Current:

```swift
                Text("PAUSE MEDIA")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(backgroundIsLight ? .black.opacity(0.6) : .white.opacity(0.6))
```

Replace with:

```swift
                Text("PAUSE MEDIA")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.06 * 11)
                    .foregroundColor(backgroundIsLight ? .black.opacity(0.6) : .white.opacity(0.6))
```

Both additions are inside the `#if DEBUG` preview helper. Production code does not render these labels at runtime, but the chip vocab is meant to read consistently in previews + production — coder treats this as one mechanical edit, no separate scope debate.

---

### Task 13: Re-tune sound cue volumes — `CueSynthesizer.masterGain` + `SoundManager` custom-override

**Files:**
- Modify: `VoiceInk/Audio/CueSynthesizer.swift`
- Modify: `VoiceInk/SoundManager.swift`

- [ ] **Step 13.1: Lower `masterGain` from 0.45 to 0.32 in `CueSynthesizer` (lines 34-37)**

Current:

```swift
    /// Master gain applied to every generated buffer. Tuned so the loudest cue
    /// (start pluck — single voice peaking near 1.0) sits comfortably below
    /// clipping while quieter cues remain audible.
    nonisolated static let masterGain: Float = 0.45
```

Replace with:

```swift
    /// Master gain applied to every generated buffer. Tuned so the loudest cue
    /// (start pluck — single voice peaking near 1.0) sits comfortably below
    /// clipping while quieter cues remain audible. Re-tuned per spec §5 row W7
    /// to match the lighter aesthetic — ~30% perceived drop relative to the
    /// pre-W7 0.45 default.
    nonisolated static let masterGain: Float = 0.32
```

Two diffs: (a) doc-comment gains a sentence citing §5 row W7; (b) numeric value `0.45` → `0.32`. The constant is referenced at lines 241 (waveform render) and 334 (live render) — both call sites consume the new value automatically. No additional edits needed.

- [ ] **Step 13.2: Lower custom-override volume from 0.4 to 0.28 in `loadAndPreparePlayer` (line 63)**

Current:

```swift
    private func loadAndPreparePlayer(from url: URL?) -> AVAudioPlayer? {
        guard let url = url else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.volume = 0.4
        player?.prepareToPlay()
        return player
    }
```

Replace with:

```swift
    private func loadAndPreparePlayer(from url: URL?) -> AVAudioPlayer? {
        guard let url = url else { return nil }
        let player = try? AVAudioPlayer(contentsOf: url)
        // Custom-override loudness — re-tuned per spec §5 row W7 to match
        // the synthesized-cue masterGain drop (parity, ~30% perceived drop
        // vs the pre-W7 0.4 default).
        player?.volume = 0.28
        player?.prepareToPlay()
        return player
    }
```

Two diffs: (a) inline 3-line comment cites §5 row W7 + the parity rationale; (b) numeric value `0.4` → `0.28`.

- [ ] **Step 13.3: Lower start-sound override volume from 0.4 to 0.28 in `playStartSound` (line 93)**

Current:

```swift
        if let player = customPlayers[.start] {
            player.volume = 0.4
            if let onFinished {
```

Replace with:

```swift
        if let player = customPlayers[.start] {
            player.volume = 0.28
            if let onFinished {
```

Single change: numeric value `0.4` → `0.28`. This is the second volume-set call site (the start cue re-arms the volume on every play in case the user changed it elsewhere — currently nothing does, but the redundancy stays for safety). No comment added (the rationale is documented in `loadAndPreparePlayer` Step 13.2; this is a duplicate set call).

- [ ] **Step 13.4: Diff inspection**

```bash
git --no-pager diff VoiceInk/Audio/CueSynthesizer.swift VoiceInk/SoundManager.swift | head -50
```

Expected: `masterGain` constant drops + doc-comment gains a §5 row W7 sentence; `loadAndPreparePlayer` drops the volume + gains a 3-line comment; `playStartSound` drops the volume. Five line edits total.

The per-cue amplitudes inside `parameters(for:)` (lines 130-176) are UNTOUCHED. The `arpeggio` helper baseAmp values are UNTOUCHED. The asset-loading pipeline (`reloadCustomSoundsAsync`) is UNTOUCHED — only the volume defaults at load time + start-cue play time change.

---

### Task 14: Verification sweeps (read-only)

**Files:** none (verification).

- [ ] **Step 14.1: Confirm `.rounded` survivor count matches the plan's KEEP list**

```bash
grep -rn "design: \.rounded" VoiceInk --include="*.swift"
```

Expected: 12 matches (the KEEP set + the orphan IGNORE set):
- `MetricsContent.swift:157`
- `KeyboardShortcutView.swift:155` (orphan IGNORE)
- `Metrics/HelpAndResourcesSection.swift` should be GONE
- `MetricsSetupView.swift:21`
- `MetricCard.swift:31`
- `PerformanceAnalysisPanelView.swift:82,170,243`
- `PerformanceAnalysisView.swift:265,346,409`

Total = 12 (11 KEEP + 1 orphan IGNORE). REPLACE sites + SF-MONO migrate site = ZERO `.rounded` matches.

If the count differs, walk back through Tasks 1-8 to find the missed migration. Do NOT fix forward — diagnose first.

- [ ] **Step 14.2: Confirm SF Mono chip-label sites all have tracking**

Sweep for SF Mono chip-style labels lacking tracking. The chip-vocab rule: every uppercase / state-pill SF Mono call site has `.tracking(0.06 * size)`.

```bash
# Find every SF Mono call site with explicit size
grep -rn "design: \.monospaced" VoiceInk --include="*.swift" | grep -E "size: [0-9]+"
```

Expected: every match either:
- Already in the W7 SF Mono normalization map (with `.tracking(0.06 * N)` added by Tasks 9-12).
- Documented in the "Untouched" list as data text / key-cap glyph / prompt body / dashboard caption (where tracking is intentionally absent).

If a NEW match without tracking surfaces (didn't exist at plan-time), reconcile with the lead — likely a recent landing not covered by the audit.

- [ ] **Step 14.3: Confirm `tracking(0.06 *` is now the dominant idiom**

```bash
grep -rn "\.tracking(0.06 \*" VoiceInk --include="*.swift" | wc -l
grep -rn "\.tracking(0\.[3-7])" VoiceInk --include="*.swift"
```

Expected:
- Count of `tracking(0.06 *` matches ≥ 25 (W1 + W2 + W6 + W7 sites).
- Off-spec tracking values surfaced by the second grep should be limited to: nothing W7 didn't intentionally leave (e.g. `RecorderStylePicker.swift:198,216` micro-glyphs at size 5 — design ornament, NOT chip labels; `PerformanceAnalysisView.swift:467` 0.5 raw — metrics dashboard caption; `Metrics/PerformanceAnalysisPanelView.swift:262` 0.5 raw — same surface).

If a state-pill / chip-label match shows up in the second grep (off-spec tracking), the migration was incomplete — fix before proceeding.

- [ ] **Step 14.4: Confirm sound cue volume re-tune landed**

```bash
grep -n "masterGain" VoiceInk/Audio/CueSynthesizer.swift
grep -n "player\\.volume\|player?\\.volume" VoiceInk/SoundManager.swift
```

Expected:
- `CueSynthesizer.swift:37` (or near it): `nonisolated static let masterGain: Float = 0.32`
- `CueSynthesizer.swift:241,334`: `*= masterGain` / `*= CueSynthesizer.masterGain` (unchanged from Task 0.3 audit)
- `SoundManager.swift`: two `0.28` literals (lines 63 + 93 give-or-take a few, depending on the exact landing offset)

If any volume literal is still `0.4` or `0.45`, the migration was incomplete.

- [ ] **Step 14.5: Confirm no W1/W2/W3/W4/W5/W6 surfaces were edited**

```bash
git --no-pager diff --stat \
  VoiceInk/Views/Common/Palette.swift \
  VoiceInk/Views/Common/GlassChip.swift \
  VoiceInk/Views/Common/GlassCard.swift \
  VoiceInk/Views/Common/GlassAppearance.swift \
  VoiceInk/Views/Common/GlassAppearanceDetector.swift \
  VoiceInk/Views/Common/SettingsCard.swift \
  VoiceInk/Views/Common/SettingsRow.swift \
  VoiceInk/Views/AI\ Models/MLXModelPickerView.swift \
  VoiceInk/Views/AI\ Models/ProviderCard.swift \
  VoiceInk/Views/AI\ Models/APIKeyManagementView.swift \
  VoiceInk/Views/PromptEditorView.swift \
  VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift \
  VoiceInk/Services/AIEnhancement/MLXProvider.swift \
  VoiceInk/Services/FailureRegistry.swift \
  VoiceInk/Views/Recorder/Constellation/ConstellationCluster.swift \
  VoiceInk/Views/Recorder/Constellation/ChipPanel.swift \
  VoiceInk/Views/Recorder/Constellation/ClusterChips.swift \
  VoiceInk/Views/Recorder/Constellation/ClusterMotion.swift \
  VoiceInk/Views/Recorder/Constellation/ClusterPhase.swift \
  VoiceInk/Views/ContentView.swift
```

Expected: zero output for all listed files. W7 deliberately stays out of W1-W6 territory.

Note: `SettingsSectionHeader.swift` IS edited in Task 1 — that's intentional (the W1 primitive holding state-pill rendering rides into W7's chip-vocab compliance pass).

- [ ] **Step 14.6: Sound cue re-tune sanity check (manual, env-permitting)**

The coder can't render sound from their environment per the W6 handoff "What Didn't Work" §4 — no audio-output device wired. Reserve as a **user-machine** verification gap.

After the integration build (Task 15), the user runs through:
1. Toggle Settings → Sound Feedback ON.
2. Hit the dictation hotkey to start recording → start cue plays.
3. End dictation → transcribe-complete cue plays (or enhance-complete if AI is on).
4. Esc to cancel mid-recording → cancel cue plays.
5. Force a transcription failure (disconnect mic, etc.) → fail cue plays.

Sanity criteria:
- All cues audibly quieter than pre-W7 (subjective ~30% drop).
- No cue is now inaudible against ambient noise — if start cue (the loudest) feels too quiet in moderate ambient noise, lead reverts `masterGain` to a higher target (e.g. 0.36 or 0.40) and re-runs verification.
- Custom-override + synthesized cues feel parity (try uploading a custom asset for one cue → both should read at similar perceived loudness post-W7).

This step is a **user verification reservation** — the plan flags subjective volume choices as a punted research item per the brief ("any subjective volume-tuning decisions that the user should sanity-check").

- [ ] **Step 14.7: Confirm no emoji literals were introduced into W7's modified set**

```bash
grep -rnE "[\x{1F300}-\x{1FAFF}]" \
  VoiceInk/Views/Common/SettingsSectionHeader.swift \
  VoiceInk/Views/Dictionary/DictionarySettingsView.swift \
  VoiceInk/Views/Settings/RecorderStylePicker.swift \
  VoiceInk/PowerMode/PowerModeConfigView.swift \
  VoiceInk/Views/Metrics/HelpAndResourcesSection.swift \
  VoiceInk/Views/History/TranscriptionListItem.swift \
  VoiceInk/Views/History/TranscriptionDetailView.swift \
  VoiceInk/Views/Recorder/HaloRecorderView.swift \
  VoiceInk/PowerMode/PowerModeActivePill.swift \
  VoiceInk/PowerMode/PowerModeStripView.swift \
  VoiceInk/PowerMode/PowerModePopover.swift \
  VoiceInk/Views/Components/PromptLivePreview.swift \
  VoiceInk/Views/Common/GlassSwitch.swift \
  VoiceInk/Audio/CueSynthesizer.swift \
  VoiceInk/SoundManager.swift \
  2>/dev/null
```

Expected: zero matches. The pre-existing `🦾` markers in `MLXProvider.swift` (W6 territory, not in W7's modified set) are NOT touched and stay where they are.

- [ ] **Step 14.8: Confirm `KeyboardShortcutView` orphan claim still holds**

```bash
grep -rn "KeyboardShortcutView(" VoiceInk --include="*.swift"
```

Expected: only matches inside `VoiceInk/Views/KeyboardShortcutView.swift` itself. If a production caller appears, the orphan claim broke since plan-time — escalate to user before merge.

---

### Task 15: Full integration build (the gate) + handback

**Files:** none.

- [ ] **Step 15.1: Run `make local`**

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
- `cannot find 'masterGain' in scope` in `CueSynthesizer.swift` → typo on the constant name during Task 13.1.
- `value of type 'AVAudioPlayer?' has no member 'volume'` in `SoundManager.swift` → impossible (`volume` is on `AVAudioPlayer`), means the receiver is wrong type. Check the optional-chain style (`player?.volume = X` for the `loadAndPreparePlayer` site; `player.volume = X` for the unwrapped `playStartSound` site) matches what the surrounding code does.
- `extra argument 'design' in call` on a font — a `.rounded` retirement removal accidentally left the comma in (`.font(.system(size: 14, weight: .semibold, ))`). Re-check Tasks 1-8 for the trailing-comma pattern.
- `value of type 'Text' has no member 'tracking'` — impossible (every Text supports `.tracking`); means the modifier order is wrong. `.tracking` should attach after `.font(...)` per the chip-vocab pattern.
- `value of type 'Text' has no member 'textCase'` — impossible (every Text supports `.textCase`); same modifier-order debug.

- [ ] **Step 15.2: Run the existing test suite (no W7 tests added)**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: all existing tests pass — `PaletteTests` (2), `FailureRegistryTests` (5), `VoiceInkUITests` (4). If the test runner is env-blocked per W6 handoff "What Didn't Work" §4 (Mac Development cert + macros trust), skip this step and document the gap to the lead.

- [ ] **Step 15.3: Sanity-launch (env-permitting)**

```bash
/usr/bin/killall VoiceInk 2>/dev/null
/Users/priyanshu/Downloads/VoiceInk.app/Contents/MacOS/VoiceInk &
sleep 3
ps aux | grep -E "/VoiceInk\.app/Contents/MacOS/VoiceInk" | grep -v grep | head -1
```

Expected: a running process. Per W6 handoff "What Didn't Work" §5: `open ~/Downloads/VoiceInk.app` errors -600; direct binary launch via `Contents/MacOS/VoiceInk` works.

- [ ] **Step 15.4: Report status to lead — DO NOT commit**

Per CLAUDE.md, no commits during execution. Report:

```
W7 Type + sound polish: BUILD GREEN, TESTS GREEN (or test gap noted)

Type pass:
- 6 chrome `.rounded` retirements (SettingsSectionHeader title,
  DictionarySettingsView section, RecorderStylePicker preview,
  PowerModeConfigView header, HelpAndResourcesSection title,
  TranscriptionListItem timestamp, TranscriptionDetailView header,
  HaloRecorderView live transcript).
- 1 chip-vocab migrate (SettingsSectionHeader statusText →
  SF Mono uppercase 0.06em + textCase).
- 12 hero numerals KEEP `.rounded` per brief (Metrics dashboards,
  MetricCard, MetricsSetupView welcome).
- KeyboardShortcutView.swift:155 orphan UNTOUCHED (separate cleanup ticket).

SF Mono polish:
- 5 chip-style label sites gained `.tracking(0.06 * size)`:
  PowerModeActivePill, PowerModeStripView "DEFAULT",
  PowerModePopover "SWITCH" + "DEFAULT", GlassSwitch preview labels (×2).
- 1 sectionLabel migrated to SF Mono (PromptLivePreview).
- 3 off-spec tracking values normalized (TranscriptionListItem duration,
  TranscriptionDetailView duration + sectionLabel).

Sound re-tune:
- CueSynthesizer.masterGain: 0.45 → 0.32 (~30% perceived drop).
- SoundManager custom-override volume: 0.40 → 0.28 (parity).
- Per-cue amplitudes UNTOUCHED (relative balance preserved).
- USER VERIFICATION RESERVED — Task 14.6 (subjective volume choice
  flagged for sanity check on real hardware).

Diff: <git diff --stat | tail -1>
```

Lead reviews diff, decides whether to commit. Reviewer (`superpowers:code-reviewer`) gets the diff next; the reviewer pattern enforces (a) the `.rounded` REPLACE/KEEP/SF-MONO split matches the plan classification, (b) every chip-style label has `.tracking(0.06 * size)`, (c) sound volume re-tune doesn't touch per-cue amps, (d) no W1-W6 surfaces were edited.

---

## Self-review

- [x] **Spec coverage.**
  - §1 Material/Tokens — "Retire `.rounded` design tokens for state surfaces" + "SF Mono uppercase tracking 0.06em for state labels and chip keys": Tasks 1-8 retire 7 chrome `.rounded` sites; Task 1.2 migrates the one state-pill `.rounded` site (SettingsSectionHeader statusText) to SF Mono uppercase 0.06em; Tasks 9-12 add the chip-vocab tracking to 5 SF-Mono-but-no-tracking sites + 1 default-system uppercase label that should have been mono. ✓
  - §5 row W7 — "Find/replace `.rounded` → system in body type; verify SF Mono on state labels; sound cue volume re-tune to match new 'lighter' aesthetic": Tasks 1-8 cover the find/replace; Tasks 9-12 cover the SF Mono verify + fix; Task 13 covers the volume re-tune. Acceptance "No `.rounded` outside designated places; chip labels uniformly SF Mono" verified by Task 14.1 + Task 14.2 sweeps. ✓
  - §5#8 GlassCard hover-lift removal: shipped in W5 (`87a08ca`); explicitly NOT redone in W7 per brief.

- [x] **Out-of-scope guard.**
  - W1-W6 surfaces explicitly listed in "Untouched"; Task 14.5 grep guard verifies zero edits. ✓
  - License / Pro / Polar / Obfuscator / Onboarding / legacy ConstellationCard: all removed via `972896a` / `de41ed7`; not referenced. ✓
  - Strip-out aftermath (orphan onboarding helper, stale ConstellationCard doc refs): `de41ed7` shipped post-W5 — not re-introduced. ✓
  - KeyboardShortcutView.swift orphan retirement — explicitly listed as separate cleanup ticket; W7 leaves the file alone. ✓
  - CardBackground migration on AudioInput device cards + Dictionary SectionCard — separate cross-screen consistency ticket per W5 planner's note; not in W7. ✓
  - ContentView sidebar — W4's surface; not touched. ✓
  - Sound asset replacement — out of scope per brief; W7 only tunes volume, not assets. ✓
  - PromptChipPicker.swift line 156 SF Mono no-tracking — flagged in Migration policy point 5 as a punted item (chip-style label inside an action button rendering, not a state pill); deliberately deferred to keep scope tight.

- [x] **Placeholder scan.** No `TBD`, no "implement later", no "similar to Task N" without code, no "add error handling without showing how". Every step has exact code, exact file:line, or exact command.

- [x] **Type consistency.**
  - `Palette.warn`, `Palette.success`, `Palette.accent`, `Palette.neutral` — all confirmed in `Palette.swift`.
  - SF Mono modifier syntax `font(.system(size: N, weight: .semibold, design: .monospaced))` — matches the W1 + W2 + W6 chip-vocab idiom. Tracking modifier `.tracking(0.06 * N)` — same idiom.
  - `.textCase(.uppercase)` is the correct SwiftUI modifier signature for forcing uppercase render (Text → Text).
  - `CueSynthesizer.masterGain: Float` type preserved — `0.32` literal is a valid `Float`.
  - `AVAudioPlayer.volume: Float` — `0.28` literal is a valid `Float` for the player property.

- [x] **Build cadence.** No `make local` between tasks; one full build at Task 15.1 per CLAUDE.md.

- [x] **No commits.** Final step reports to lead.

- [x] **No PR-reference comments in code samples.** All inline doc-comments cite the spec section + this plan path; none reference PR numbers.

- [x] **Pre-existing spec-ref comments preserved.** `SoundManager.swift:13-18` "spec §3.10 / plan P3.F + P3.G" reference stays; `CueSynthesizer.swift:5-20` "P3.F / spec §3.10, §6.3" reference stays; the only edit is adding a `§5 row W7` cite alongside the value change in the master-gain doc-comment.

- [x] **Coder context isolation.** Tasks reference exact file:line and exact code blocks. The coder need not read the W1-W6 plans to execute W7. The chip-vocab idiom (`font(... design: .monospaced))` + `tracking(0.06 * size)`) is explicitly demonstrated in every applicable task; the coder grep sweeps in Task 0 surface everything they need to verify the migration.

---

## Acceptance criteria

- ✅ `make local` completes with `** BUILD SUCCEEDED **`.
- ✅ `xcodebuild test` passes (or env-block documented) — all existing tests green.
- ✅ Sweep `grep -rn "design: \.rounded" VoiceInk --include="*.swift"` returns exactly 12 matches: the 11 KEEP sites (hero numerals on Metrics + onboarding) + the 1 IGNORE site (`KeyboardShortcutView.swift:155` orphan).
- ✅ Sweep `grep -rn "tracking(0\\.[3-7])" VoiceInk --include="*.swift"` returns no chip-style state-pill or chip-label sites — only ornament / dashboard caption / display-type sites that are intentionally off-spec (RecorderStylePicker preview micro-glyphs at size 5, MetricsDashboard caption labels).
- ✅ Every state-pill / chip-label SF Mono call site uses `.tracking(0.06 * size)` per the W1 chip-vocab. Verified via Task 14.2 + 14.3 sweeps.
- ✅ `SettingsSectionHeader.swift`: title drops `, design: .rounded`; statusText pill uses SF Mono uppercase 0.06em with `.textCase(.uppercase)` for caller mixed-case input. Capsule chrome geometry preserved.
- ✅ `PowerModeActivePill`, `PowerModeStripView`, `PowerModePopover`, `PromptLivePreview`, `GlassSwitch` preview labels all gain `.tracking(0.06 * size)` after their SF Mono fonts.
- ✅ `TranscriptionListItem` + `TranscriptionDetailView` duration pills + sectionLabel use the W1 tracking formula; TranscriptionDetailView header timestamp + TranscriptionListItem timestamp drop `, design: .rounded`.
- ✅ `HaloRecorderView` live-transcript drops `, design: .rounded`.
- ✅ `RecorderStylePicker`, `PowerModeConfigView`, `HelpAndResourcesSection`, `DictionarySettingsView` chrome titles drop `, design: .rounded`.
- ✅ `CueSynthesizer.masterGain` = 0.32 (was 0.45). `SoundManager` custom-override volume = 0.28 (was 0.40) at both call sites. Per-cue amplitudes inside `parameters(for:)` UNTOUCHED.
- ✅ Sweep for emoji literals (Task 14.7) across the W7 file set returns zero matches.
- ✅ `KeyboardShortcutView` orphan claim verified (Task 14.8); not deleted in W7.
- ✅ User-machine sound sanity check (Task 14.6) reserved as a verification gap; the plan flags subjective volume choice as the #1 punted item for the user to sign off on.
- ✅ No W1-W6 surface edited (Task 14.5 grep guard).

---

## Risks / unknowns

1. **Sound volume is subjective — user verification REQUIRED.** The 0.32 / 0.28 numbers are picked to drop ~30% perceived loudness while staying audible. Ambient-noise tolerance varies — user on a quiet desk might want a smaller drop (e.g. 0.36 / 0.32); user with headphones might want a larger drop (0.28 / 0.24). **Mitigation:** Task 14.6 reserves the sanity check as a user-machine verification gap. If the user reports cues as inaudible, lead bumps the values up (single-line edit in two files) and rebuilds. If the user reports cues as still too loud, lead drops further. There is no "right" answer here; the plan's specific numbers are a first-cut that respects the brief's "lighter" intent.

2. **Existing users with custom audio assets.** Users who have uploaded custom sound assets via `CustomSoundManager` will see the override player volume drop from 0.40 to 0.28 on next launch (no migration; volume is set at load time). If they tuned their custom asset to be loud-enough at 0.40 in the previous build, the new 0.28 makes it ~30% quieter. **Mitigation:** the brief explicitly says "one-shot migration is out of scope (over-engineering for a personal fork)"; the new defaults apply uniformly. Users can re-upload louder source assets if needed (no UI change). Document in the post-W7 handoff so the lead can mention it in the commit message.

3. **`SettingsSectionHeader.swift` is a W1 primitive — blast radius is wide.** Every `SettingsSectionHeader` host across the app (Settings hub, Enhancement panel, AI Models page, the SettingsCard wrapper) inherits Task 1's edits. Title font drops `.rounded` everywhere; statusText pill becomes SF Mono uppercase 0.06em with `.textCase(.uppercase)`. **Risk:** a caller passing `"On"` now reads `"ON"` — visible behavior change. **Mitigation:** the brief is explicit ("chip labels uniformly SF Mono"); the W6 surfaces already render uppercase chip labels; making SettingsSectionHeader match brings the app's chip vocab to a single grammar. Visual smoke pass is required (reserved on user-machine).

4. **`HaloRecorderView.swift` may be retired in a future packet.** The W2 ConstellationContainer comment says it sits on top of the existing panel hosts; if a future packet retires the legacy halo recorder entirely, Task 8's edit becomes moot. **Mitigation:** the edit is mechanical (single line) and harmless if the file is later deleted — costs nothing. If the file IS still rendering live transcript text in production, the W7 type pass needs to apply to it (per spec §1 "system for body content").

5. **Track-formula numeric output is identical for `tracking(0.6)` ↔ `tracking(0.06 * 10)`.** Mechanical-equivalence sweeps may flag the migration as a no-op visually. The plan's grep verification (Task 14.3) reads the FORMULA expression, not the numeric value, so the spec-compliance check holds. If a future grep tool simplifies the constant-folding, the chip-vocab grep needs updating.

6. **`PromptChipPicker.swift:156` SF Mono no-tracking — deliberate punt.** Migration policy point 5 documents the decision. **Risk:** reviewer may flag this as a missed migration. **Mitigation:** the plan's "Untouched" list calls it out explicitly with the rationale (prompt-chip rendering inside action button, not a state pill); reviewer sees the documentation.

7. **Existing tracking values `0.5`, `0.6`, `0.4` may be intentional design choices.** The W7 normalization assumes `tracking(0.06 * size)` is the W1 chip-vocab spec for all chip-style labels. If any of the off-spec values were a deliberate design choice (e.g. tighter tracking for a specific surface to fit a width constraint), W7's mechanical normalization breaks that intent. **Mitigation:** review of git blame on each off-spec tracking site shows none were called out in commit messages as intentional design overrides — they read as inconsistent landings rather than considered choices. Reviewer pass + visual smoke surface any regressions.

8. **`textCase(.uppercase)` on `SettingsSectionHeader.statusText` is a behavior change.** Pre-W7: callers see whatever case they pass. Post-W7: always uppercase. **Risk:** a caller intentionally passing mixed case (e.g. "MyCompany Pro" — none observed but possible) will render uppercase, losing the original casing. **Mitigation:** the four observed callers all pass either short flags ("On"/"Off"/"1 active"/"2 active") or numeric ("\(count)") — uppercase is appropriate for all. Future callers with mixed-case requirements would need a `forceUppercase: Bool` parameter; defer that until a real caller surfaces.

9. **Build green doesn't cover audio playback.** Per the W6 handoff, the test suite is env-blocked and even when accessible doesn't cover audio output. Task 13's volume re-tune compiles green but the AUDIBLE result requires user-machine playback. **Mitigation:** Task 14.6 reserves the sanity check; Task 15.4's report explicitly flags the verification gap to lead.

## Estimated effort

~2 hours for an engineer familiar with the codebase. ~3 hours for a fresh teammate. Most of the work is rote text replacement (Tasks 1-12 = single-line edits per file). Task 13's volume re-tune is two short edits + comment updates. Task 14's verification sweeps are grep-driven and fast. The largest single edit (Task 1's SettingsSectionHeader migration) is ~7 LOC churn across two surfaces in the file. New file count: 0; cross-file rewiring: none. The sound sanity check (Task 14.6) belongs to the user post-merge.
