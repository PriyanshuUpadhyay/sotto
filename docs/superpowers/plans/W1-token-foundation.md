# W1 — Token Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retire VoiceInk's rainbow Palette tokens (`recording`/`transcribe`/`enhance`) and ship a single-tangerine accent vocabulary plus a new `GlassChip` view modifier — without breaking the build.

**Architecture:** Mechanical token migration across ~85 call sites in ~30 files; expand `Palette.swift` with the new locked tokens (accent, onyx*, hairline*, innerHi); add a `GlassChip` SwiftUI view modifier that mirrors `HaloMaterial` but with the spec'd 28pt blur / hairline / 10pt corner geometry. Done in additive-then-subtractive order so the codebase compiles after every task: add new tokens first, migrate call sites in feature-area batches, remove retired tokens last.

**Tech Stack:** Swift 5.x, SwiftUI, Xcode 16.x, Swift Testing framework (`import Testing`, `@Test` syntax). Build via `make local` (~3 min cold, ~30 s incremental).

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (Material), §5 (Surfaces in scope #1 + #10).

**CLAUDE.md cadence rules respected:**
- **Single build at merge time.** No `make local` per task; one full build at Task 12.
- **No commits during execution.** The plan ends with "report build green to lead" — coder does NOT commit unilaterally.
- **No `xcodebuild` per file.** SourceKit / Xcode-in-IDE handles per-file syntax during edits; the integration build is the gate.

---

## File structure

### New files
- `VoiceInk/Views/Common/GlassChip.swift` — view modifier with locked vocabulary (28pt blur 1.4 saturate, white α0.16 hairline border, inset white α0.22 highlight, black α0.55 14pt shadow, 10pt corner radius). One file, ~80 LOC.
- `VoiceInkTests/PaletteTests.swift` — assertions on token hex values + a smoke test that `Palette.accent` exists. ~30 LOC.

### Modified — token additions/retirement
- `VoiceInk/Views/Common/Palette.swift` — add new tokens; retire `recording`/`transcribe`/`enhance` (Task 1 → present, Task 10 → removed).

### Modified — call-site migration (in batches by feature area)

Group A (recorder/state surfaces):
- `VoiceInk/Views/Recorder/HaloMaterial.swift`
- `VoiceInk/Views/Common/MenuBarIconRenderer.swift`
- `VoiceInk/Views/Common/Animation+Halo.swift`
- `VoiceInk/Views/Components/PromptLivePreview.swift`
- `VoiceInk/Views/Recorder/Constellation/ConstellationCard.swift`

Group B (provider / AI / enhancement surfaces):
- `VoiceInk/Views/Common/ProviderChipStyle.swift`
- `VoiceInk/Views/AI Models/ProviderCard.swift`
- `VoiceInk/Views/AI Models/APIKeyManagementView.swift`
- `VoiceInk/Views/EnhancementSettingsView.swift`

Group C (settings chrome):
- `VoiceInk/Views/Settings/SettingsView.swift`
- `VoiceInk/Views/Common/SettingsCard.swift`
- `VoiceInk/Views/Common/SettingsRow.swift`
- `VoiceInk/Views/Common/GlassSwitch.swift`
- `VoiceInk/Views/Common/PromptChipPicker.swift`
- `VoiceInk/Views/Settings/RecorderStylePicker.swift`
- `VoiceInk/Views/Settings/CustomSoundSettingsView.swift`

Group D (history / detail surfaces):
- `VoiceInk/Views/History/AudioTimelineView.swift`
- `VoiceInk/Views/History/TranscriptionDetailView.swift`
- `VoiceInk/Views/History/TranscriptionListItem.swift`

Group E (dictionary / license / power-mode surfaces):
- `VoiceInk/Views/Dictionary/DictionarySettingsView.swift`
- `VoiceInk/Views/Dictionary/WordReplacementView.swift`
- `VoiceInk/Views/LicenseManagementView.swift`
- `VoiceInk/Views/LicenseView.swift`
- `VoiceInk/PowerMode/PowerModeConfigView.swift`

Group F (onboarding — token swap only, layout untouched per spec deferral):
- `VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift`
- `VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift`

---

## Migration policy (resolves ambiguity for each call site)

The spec says "single tangerine accent across all live states" but several call sites are non-state-color uses. Rule applied **uniformly** below:

1. **Live state colors** (recording/transcribing/enhancing/failed glow, halo, dot, ring, ribbon) → `Palette.accent`.
2. **Decorative `iconTint:`** in Settings/Onboarding/SettingsCard/SettingsRow → `Palette.accent`. Single accent throughout.
3. **Per-provider brand colors in `ProviderChipStyle.providerColor`** (Gemini = blue, OpenRouter = violet, Cerebras = red, etc.) → all `Palette.accent`. Per-provider color identity is dropped this packet; a follow-up can reintroduce brand colors via a new `ProviderBrand.color` enum if desired (NOT this packet).
4. **`Palette.success` (green)** stays. Used for license-validation success and `HaloPhase.done`. Spec doesn't retire it.
5. **`Palette.warn` (amber)** stays. Power-mode signal.
6. **`Palette.neutral` (gray)** stays. Idle baseline.
7. **`Palette.recording` used as error/destructive color** (e.g. `LicenseView.swift:45` validation-failure indicator, `TranscriptionDetailView.swift:308` destructive button) → `Palette.accent`. Tangerine reads as both "live" and "warning" cleanly.

---

## Tasks

### Task 1: Add new Palette tokens (additive)

**Files:**
- Modify: `VoiceInk/Views/Common/Palette.swift`

- [ ] **Step 1.1: Add new locked-vocabulary tokens to `Palette` enum**

Open `VoiceInk/Views/Common/Palette.swift`. Add the following tokens immediately after the existing `onyxBackground` token (around line 33), keeping the existing `recording`/`transcribe`/`enhance` tokens in place for now:

```swift
    /// #FF5B3A — single live-state accent (locked, post-redesign 2026-04). All
    /// "live" surfaces — recording, transcribing, enhancing, failed — use this
    /// one accent; motion (ringPulse / shimmer / breath) distinguishes states,
    /// not color. Source of truth: docs/superpowers/specs/2026-04-28-aesthetic-redesign.md §1.
    static let accent = Color(red: 1.000, green: 0.357, blue: 0.227)

    /// #FF5B3A α 0.42 — for muted accent fills (chip backgrounds, halo bases).
    static let accentMuted = Color(red: 1.000, green: 0.357, blue: 0.227).opacity(0.42)

    /// #FF5B3A α 0.55 — for accent glows (ringPulse end frames, shadow tints).
    static let accentGlow = Color(red: 1.000, green: 0.357, blue: 0.227).opacity(0.55)

    /// #0A0A0D — onyx background. Replaces the previously-hardcoded
    /// `Color(red: 0.06, green: 0.06, blue: 0.07)` in onyx hosts.
    static let onyxBg = Color(red: 0.039, green: 0.039, blue: 0.051)

    /// #EDEDF0 — onyx foreground (primary text on onyx surfaces).
    static let onyxFg = Color(red: 0.929, green: 0.929, blue: 0.941)

    /// #8A8A93 — onyx muted (secondary text). Same hue as `neutral` but
    /// pinned in case `neutral` shifts under a future system-color rebase.
    static let onyxMute = Color(red: 0.541, green: 0.541, blue: 0.576)

    /// White α 0.16 — hairline border on glass surfaces (locked).
    static let hairline = Color.white.opacity(0.16)

    /// White α 0.10 — softer hairline for nested or secondary edges.
    static let hairlineSoft = Color.white.opacity(0.10)

    /// White α 0.22 — inner highlight on glass surfaces (the bright-edge sheen
    /// at the top of a glass chip / panel).
    static let innerHi = Color.white.opacity(0.22)
```

- [ ] **Step 1.2: Build-mode syntax check (no full project build)**

The Swift LSP / SourceKit running in your editor should show no diagnostics on `Palette.swift` after the edit. If the editor isn't open, this step is a visual diff check — confirm:
- All new tokens compile (color literals only, no symbol references).
- No duplicate token names (e.g. you didn't accidentally define `accent` twice).
- Existing `recording`, `transcribe`, `enhance` are untouched.

Skip xcodebuild here — saves ~30s and the integration build at Task 12 catches any error.

- [ ] **Step 1.3: Checkpoint — diff inspection only, no commit**

```bash
git --no-pager diff VoiceInk/Views/Common/Palette.swift
```

Expected diff: only additions, no deletions or modifications to existing tokens. If the diff shows any deletion in this task, stop and re-do — Task 1 is strictly additive.

---

### Task 2: Add `GlassChip` view modifier

**Files:**
- Create: `VoiceInk/Views/Common/GlassChip.swift`

- [ ] **Step 2.1: Write the file**

Create `VoiceInk/Views/Common/GlassChip.swift` with this exact content:

```swift
import SwiftUI

// MARK: - GlassChip
//
// View modifier implementing the locked Adaptive Glass chip vocabulary
// (post-redesign 2026-04). Used across the new constellation cluster (W2),
// reskinned settings cards (W5), AI / prompt chips (W6), and any new chip
// surfaces in W3/W4/W7. Source of truth:
// `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.
//
// Geometry (locked — do not parametrize without spec change):
//   - 28pt backdrop blur, 1.4 saturate
//   - rgba(20,20,28, 0.55) translucent fill
//   - 1px white α0.16 hairline border
//   - inset 0 1.5pt 0 white α0.22 inner highlight (top edge sheen)
//   - 0 14pt 36pt black α0.55 drop shadow
//   - 10pt corner radius (chips), 14pt for panels — caller chooses via init
//
// Reduce-Motion / fallback rendering: SwiftUI `Material` already degrades
// gracefully on older macOS or under Reduce-Transparency. No extra branch
// needed here.

struct GlassChip: ViewModifier {
    var cornerRadius: CGFloat = 10
    var paddingH: CGFloat = 11
    var paddingV: CGFloat = 7

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .padding(.horizontal, paddingH)
            .padding(.vertical, paddingV)
            .background(
                shape
                    .fill(Color(red: 0.078, green: 0.078, blue: 0.110).opacity(0.55))
                    .background(
                        // backdrop refraction layer
                        shape.fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                shape.stroke(Palette.hairline, lineWidth: 1)
            )
            .overlay(
                // top-edge sheen (1.5pt inset highlight on the top)
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [Palette.innerHi, .clear],
                            startPoint: .top,
                            endPoint: UnitPoint(x: 0.5, y: 0.18)
                        ),
                        lineWidth: 1.5
                    )
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 14, x: 0, y: 14)
            .clipShape(shape)
    }
}

extension View {
    /// Wraps the view in a 10pt-radius Adaptive Glass chip per spec §1.
    /// Use for state chips, action chips, status pills.
    func glassChip(cornerRadius: CGFloat = 10) -> some View {
        modifier(GlassChip(cornerRadius: cornerRadius))
    }

    /// Wider radius (14pt) variant for panels / cards. Same vocabulary,
    /// just a softer corner.
    func glassPanel(cornerRadius: CGFloat = 14) -> some View {
        modifier(GlassChip(cornerRadius: cornerRadius, paddingH: 14, paddingV: 12))
    }
}

// MARK: - Previews

#if DEBUG
private struct GlassChipPreviewBody: View {
    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Text("REC")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.onyxFg)
                    .glassChip()
                Text("00:14")
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .tracking(0.06 * 10.5)
                    .foregroundColor(Palette.onyxMute)
                    .glassChip()
            }
            Text("MODEL · Parakeet → Gemma 4")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .tracking(0.06 * 11)
                .foregroundColor(Palette.onyxFg)
                .glassPanel()
        }
        .padding(40)
    }
}

#Preview("GlassChip · onyx wallpaper") {
    GlassChipPreviewBody()
        .background(
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.10, blue: 0.34), Color(red: 0.54, green: 0.23, blue: 0.42)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
}
#endif
```

- [ ] **Step 2.2: Add the new file to the Xcode project target**

The repo uses an Xcode project (`VoiceInk.xcodeproj`), not a Swift Package, so new files must be added to the project's `Sources` build phase. Two paths:

**Path A — IDE:** Open `VoiceInk.xcodeproj`, drag `VoiceInk/Views/Common/GlassChip.swift` into the `Views/Common` group, ensure "Target Membership" includes `VoiceInk`. Save.

**Path B — Headless (sed/ruby):** If you can't open Xcode, run this from the repo root to add the file by hand:

```bash
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("VoiceInk.xcodeproj")
target = project.targets.find { |t| t.name == "VoiceInk" }
group = project.main_group
["VoiceInk", "Views", "Common"].each do |seg|
  group = group.find_subpath(seg, false) || (raise "missing group #{seg}")
end
file_ref = group.new_reference("GlassChip.swift")
target.add_file_references([file_ref])
project.save
'
```

If `xcodeproj` gem isn't installed: `gem install xcodeproj` first. (Path A is simpler.)

- [ ] **Step 2.3: Checkpoint — verify file is target-member**

```bash
grep -c "GlassChip.swift" VoiceInk.xcodeproj/project.pbxproj
```
Expected: ≥ 2 (one PBXBuildFile entry, one PBXFileReference). If 0, the add didn't take — repeat Step 2.2.

---

### Task 3: Add Palette unit test

**Files:**
- Modify: `VoiceInkTests/VoiceInkTests.swift` (replace example with real assertions, OR create new file `VoiceInkTests/PaletteTests.swift` if you prefer a dedicated file)

- [ ] **Step 3.1: Write the assertion in `VoiceInkTests/VoiceInkTests.swift`**

Replace the entire file contents with:

```swift
import Testing
import SwiftUI
@testable import VoiceInk

struct PaletteTests {

    @Test func accentTokenHasExpectedHex() async throws {
        // #FF5B3A == (1.000, 0.357, 0.227). Allow a tiny epsilon for floating-point
        // round-trip through SwiftUI Color components.
        let resolved = Palette.accent.resolveComponents()
        #expect(abs(resolved.r - 1.000) < 0.005, "accent red component drifted: \(resolved.r)")
        #expect(abs(resolved.g - 0.357) < 0.005, "accent green component drifted: \(resolved.g)")
        #expect(abs(resolved.b - 0.227) < 0.005, "accent blue component drifted: \(resolved.b)")
    }

    @Test func successAndWarnAndNeutralTokensRetained() async throws {
        // Sanity: tokens we keep should still resolve to non-clear colors.
        #expect(Palette.success != Color.clear)
        #expect(Palette.warn != Color.clear)
        #expect(Palette.neutral != Color.clear)
    }
}

private extension Color {
    /// Pull the SRGB components out of a SwiftUI Color via NSColor on macOS.
    /// Approximate; epsilon of 0.005 in tests is well above NSColor round-trip noise.
    func resolveComponents() -> (r: Double, g: Double, b: Double) {
        #if canImport(AppKit)
        let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
        return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
        #else
        return (0, 0, 0)
        #endif
    }
}
```

- [ ] **Step 3.2: Run the test in Xcode (single-file scope, fast)**

Open Xcode, ⌘U (or `Product → Test`) — runs the `VoiceInkTests` bundle. Expected:
- `accentTokenHasExpectedHex` passes
- `successAndWarnAndNeutralTokensRetained` passes

If accent test fails with "drifted", you typo'd a hex component in Task 1 — go back and fix `Palette.accent`'s color literal.

---

### Task 4: Migrate Group A — recorder + state surfaces

**Files:**
- Modify: `VoiceInk/Views/Recorder/HaloMaterial.swift`
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift`
- Modify: `VoiceInk/Views/Common/Animation+Halo.swift`
- Modify: `VoiceInk/Views/Components/PromptLivePreview.swift`
- Modify: `VoiceInk/Views/Recorder/Constellation/ConstellationCard.swift`

These are the surfaces that own state-driven coloring today; migrating them first means subsequent migrations don't accidentally reintroduce the old palette.

- [ ] **Step 4.1: HaloMaterial.swift — collapse rainbow to single accent**

Replace `glowColor` switch (around lines 22-34) so all live phases return `Palette.accent`. Keep `.done` on `Palette.success` and idle/armed on `Palette.neutral`:

```swift
extension HaloPhase {
    var glowColor: Color {
        switch self {
        case .hidden, .armed:           return Palette.neutral
        case .recording, .liveText:     return Palette.accent
        case .transcribing:             return Palette.accent
        case .enhancing:                return Palette.accent
        case .failed:                   return Palette.accent
        case .done:                     return Palette.success
        }
    }
    // glowAlpha and other functions: leave untouched.
}
```

- [ ] **Step 4.2: MenuBarIconRenderer.swift — recording icon tint**

Find the `tinted("waveform"...)` call inside `image(for:)` (around line 51). Change `color: NSColor(Palette.recording)` to `color: NSColor(Palette.accent)`. Also update the comment block at line 13 from `Palette.recording` to `Palette.accent`.

- [ ] **Step 4.3: Animation+Halo.swift — preview gradient stops**

Around lines 223-233 the preview uses three colored circles + a 3-stop gradient. Replace all three of `Palette.recording`, `Palette.transcribe`, `Palette.enhance` with `Palette.accent`. Stops should look like this after edit:

```swift
                Circle().fill(Palette.accent).frame(width: 24, height: 24)
                Circle().fill(Palette.accent).frame(width: 24, height: 24)
                Circle().fill(Palette.accent).frame(width: 24, height: 24)
                ...
                        .init(color: Palette.accent.a(0.7),    location: phase),
```

(Yes, three identical circles — the preview was demoing color drift; now it demos motion drift only.)

- [ ] **Step 4.4: PromptLivePreview.swift — phase color**

Around lines 144, 208, 210 — the live-preview phase colors. Replace:
- `Palette.recording` → `Palette.accent`
- `Palette.enhance` (at line 208 for `.enhancing`) → `Palette.accent`
- Update the file's top doc comment (lines 12-14) to drop the per-state color description; mention that state is now distinguished by motion.

- [ ] **Step 4.5: ConstellationCard.swift — about to be retired in W2, but compile-stable**

Around lines 224, 233, 356 the Constellation card uses Palette.transcribe / Palette.enhance for icon + gradient. Migrate to `Palette.accent`. Note: this whole file is scheduled for retirement in W2; this token swap is just to keep the build green between W1 and W2.

- [ ] **Step 4.6: Group A diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Recorder/HaloMaterial.swift VoiceInk/Views/Common/MenuBarIconRenderer.swift VoiceInk/Views/Common/Animation+Halo.swift VoiceInk/Views/Components/PromptLivePreview.swift VoiceInk/Views/Recorder/Constellation/ConstellationCard.swift | grep -cE "^- .*Palette\.(recording|transcribe|enhance)"
```
Expected: number ≥ the count grepped pre-task. (Should be 11 — verify by `grep -c "Palette\.\(recording\|transcribe\|enhance\)" <files>` before/after.) Any retired-token line that survived in the `+ ` half = bug; go fix it.

---

### Task 5: Migrate Group B — provider / AI / enhancement surfaces

**Files:**
- Modify: `VoiceInk/Views/Common/ProviderChipStyle.swift`
- Modify: `VoiceInk/Views/AI Models/ProviderCard.swift`
- Modify: `VoiceInk/Views/AI Models/APIKeyManagementView.swift`
- Modify: `VoiceInk/Views/EnhancementSettingsView.swift`

- [ ] **Step 5.1: ProviderChipStyle.swift — drop per-provider colors**

Around lines 40-51, `providerColor(for:)` returns brand colors per provider. Replace ALL `Palette.recording / .transcribe / .enhance` returns with `Palette.accent`. After the edit, the function should still exist (call sites depend on it) but every case returns `Palette.accent`. Add a one-line note at the top of the function:

```swift
    /// Single-accent post-redesign 2026-04. All providers chip in tangerine;
    /// brand identity moves to the icon glyph, not the color. To restore
    /// per-provider colors, introduce `ProviderBrand.color` enum (out of W1 scope).
```

- [ ] **Step 5.2: ProviderCard.swift — error/dot tints**

Lines 345, 445, 531 use `Palette.recording` for negative/error UI. Replace each with `Palette.accent`.

- [ ] **Step 5.3: APIKeyManagementView.swift — accent + negative**

- Line 72: `accent: Palette.enhance` → `accent: Palette.accent`.
- Line 154: `case .negative: return Palette.recording` → `case .negative: return Palette.accent`.

- [ ] **Step 5.4: EnhancementSettingsView.swift — accent panels**

Lines 71, 84, 122, 134, 138, 142 use `Palette.transcribe` and `Palette.enhance` for chip/panel backgrounds + foregrounds. Replace each with `Palette.accent`. The `.opacity(0.16)` / `.opacity(0.32)` at the call sites stays — those are just alpha modifiers.

- [ ] **Step 5.5: Group B diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Common/ProviderChipStyle.swift VoiceInk/Views/AI\ Models/ProviderCard.swift VoiceInk/Views/AI\ Models/APIKeyManagementView.swift VoiceInk/Views/EnhancementSettingsView.swift | grep -E "^[+-].*Palette\.(recording|transcribe|enhance|accent)" | head -20
```
Expected: every retired token (`recording`/`transcribe`/`enhance`) on a `-` line has a matching `+` line replacing it with `accent`. Eyeball it.

---

### Task 6: Migrate Group C — settings chrome

**Files:**
- Modify: `VoiceInk/Views/Settings/SettingsView.swift`
- Modify: `VoiceInk/Views/Common/SettingsCard.swift`
- Modify: `VoiceInk/Views/Common/SettingsRow.swift`
- Modify: `VoiceInk/Views/Common/GlassSwitch.swift`
- Modify: `VoiceInk/Views/Common/PromptChipPicker.swift`
- Modify: `VoiceInk/Views/Settings/RecorderStylePicker.swift`
- Modify: `VoiceInk/Views/Settings/CustomSoundSettingsView.swift`

- [ ] **Step 6.1: SettingsView.swift — replace all iconTints**

Lines 89, 98, 125, 168, 175, 184, 193, 208, 230, 253, 300, 313 — every `iconTint: Palette.recording / .transcribe / .enhance` → `iconTint: Palette.accent`.

`replace_all` is safe here (the file uses no other `Palette.recording`/etc. references for non-iconTint purposes). Suggested approach in Edit tool:

```swift
old_string: "iconTint: Palette.enhance"
new_string: "iconTint: Palette.accent"
replace_all: true
```

Repeat once more for `iconTint: Palette.recording` and `iconTint: Palette.transcribe` (they're each a single match in this file but use replace_all anyway for safety).

- [ ] **Step 6.2: SettingsCard.swift, SettingsRow.swift — same pattern**

Both files use `iconTint: Palette.enhance / .recording`. Same `replace_all` approach for each token.

- [ ] **Step 6.3: GlassSwitch.swift — default tint**

Line 19 has `var tint: Color = Palette.enhance`. Change default to `Palette.accent`.

- [ ] **Step 6.4: PromptChipPicker.swift — selection ring**

Lines 82, 118: `Palette.enhance` (selection stroke + halo color). Replace each with `Palette.accent`. Update the file's top doc comment (line 7) to reference `Palette.accent`.

- [ ] **Step 6.5: RecorderStylePicker.swift — preview swatches**

Lines 84, 125, 153, 215, 217, 218, 231, 247 all use `Palette.recording` for the recorder preview swatches. `replace_all: true` from `Palette.recording` → `Palette.accent` covers all of them.

- [ ] **Step 6.6: CustomSoundSettingsView.swift — sound type colors**

Lines 145-147 map sound types to per-type colors. Replace each (`Palette.recording`, `Palette.transcribe`, `Palette.enhance`) with `Palette.accent`. Sound types now share the accent — the icon and label distinguish them, not color.

---

### Task 7: Migrate Group D — history / detail surfaces

**Files:**
- Modify: `VoiceInk/Views/History/AudioTimelineView.swift`
- Modify: `VoiceInk/Views/History/TranscriptionDetailView.swift`
- Modify: `VoiceInk/Views/History/TranscriptionListItem.swift`

- [ ] **Step 7.1: AudioTimelineView.swift — playhead + waveform tint**

Lines 55, 59, 93, 139, 140 use `Palette.transcribe` for the timeline accent. `replace_all: true` from `Palette.transcribe` → `Palette.accent`.

- [ ] **Step 7.2: TranscriptionDetailView.swift — multi-token migration**

This file has both `Palette.recording` (error/destructive UI) and `Palette.enhance`/`Palette.transcribe` (panel accents). Run three `replace_all` passes:
- `Palette.recording` → `Palette.accent`
- `Palette.enhance` → `Palette.accent`
- `Palette.transcribe` → `Palette.accent`

Watch out: line 69 has `msg.isError ? Palette.recording : Palette.success`. After migration this becomes `msg.isError ? Palette.accent : Palette.success` — error reads tangerine, success stays green. Correct.

- [ ] **Step 7.3: TranscriptionListItem.swift — selection stroke**

Lines 71, 86 use `Palette.enhance` (selection ring + bg). `replace_all: true` from `Palette.enhance` → `Palette.accent`.

---

### Task 8: Migrate Group E — dictionary / license / power-mode

**Files:**
- Modify: `VoiceInk/Views/Dictionary/DictionarySettingsView.swift`
- Modify: `VoiceInk/Views/Dictionary/WordReplacementView.swift`
- Modify: `VoiceInk/Views/LicenseManagementView.swift`
- Modify: `VoiceInk/Views/LicenseView.swift`
- Modify: `VoiceInk/PowerMode/PowerModeConfigView.swift`

- [ ] **Step 8.1: DictionarySettingsView.swift — section colors**

Lines 128-129 map sections to colors (`Palette.transcribe`, `Palette.enhance`). Replace each with `Palette.accent`.

- [ ] **Step 8.2: WordReplacementView.swift — accent + error icons**

Lines 463, 472. `replace_all` from `Palette.transcribe` → `Palette.accent`, then from `Palette.recording` → `Palette.accent`.

- [ ] **Step 8.3: LicenseManagementView.swift — three tints**

Lines 62, 141, 147, 165 use `Palette.transcribe`, `Palette.enhance`, `Palette.recording`. `replace_all` for each retired token → `Palette.accent`.

- [ ] **Step 8.4: LicenseView.swift — gradient + state colors**

- Line 45: `licenseViewModel.validationSuccess ? Palette.success : Palette.recording` → `... : Palette.accent`. Success path unchanged.
- Line 112: gradient `[Palette.warn, Palette.enhance]`. Decide: this is a `LicenseView` premium-tier gradient. Per migration policy (point 5: warn stays, retired tokens swap), replace `Palette.enhance` with `Palette.accent` → gradient becomes `[Palette.warn, Palette.accent]` (amber→tangerine).
- Line 141: `case .trial: return Palette.transcribe` → `Palette.accent`.

- [ ] **Step 8.5: PowerModeConfigView.swift — multiple tints**

Lines 286, 436, 519, 525, 545. `replace_all` from `Palette.transcribe` → `Palette.accent`, then from `Palette.enhance` → `Palette.accent`. Toggle tints (`SwitchToggleStyle(tint: ...)`) follow the same rule.

---

### Task 9: Migrate Group F — onboarding (token swap only)

**Files:**
- Modify: `VoiceInk/Views/Onboarding/OnboardingModelDownloadView.swift`
- Modify: `VoiceInk/Views/Onboarding/OnboardingPermissionsView.swift`

Per spec, onboarding **layout** is deferred. We only swap tokens here so the file compiles after Task 10 retires the rainbow tokens.

- [ ] **Step 9.1: OnboardingModelDownloadView.swift**

Lines 98, 115, 118, 123, 173, 174, 181 use `Palette.enhance` and `Palette.transcribe`. `replace_all`:
- `Palette.enhance` → `Palette.accent`
- `Palette.transcribe` → `Palette.accent`

The gradient at lines 173-174 was `[Palette.enhance, Palette.enhance.opacity(0.85)]` — after migration becomes `[Palette.accent, Palette.accent.opacity(0.85)]`. Same shape, accent color.

- [ ] **Step 9.2: OnboardingPermissionsView.swift**

Lines 50, 55, 60, 65 — same pattern. `replace_all` for each retired token → `Palette.accent`.

---

### Task 10: Confirm zero remaining call sites, then retire tokens

**Files:**
- Modify: `VoiceInk/Views/Common/Palette.swift`

- [ ] **Step 10.1: Sweep for any leftover references**

```bash
grep -rn "Palette\.\(recording\|transcribe\|enhance\)" VoiceInk/ --include="*.swift" \
  | grep -v "Views/Common/Palette.swift:" \
  | grep -v "\/\/" \
  | head
```

Expected output: **empty**. If any line shows up:
- If it's a code reference: go back to the appropriate Group task and finish the migration.
- If it's in a comment that survived (e.g. `// Palette.recording for reference`): clean up the comment too — drop dead references.

`grep -v "Views/Common/Palette.swift:"` excludes the definition file. `grep -v "\/\/"` excludes single-line comments.

- [ ] **Step 10.2: Retire the rainbow tokens in `Palette.swift`**

Remove lines 12-19 (the `recording`, `transcribe`, `enhance` declarations). Specifically, remove these declarations and their docstrings:

```swift
    /// #FF3B30 — system-red intent...
    static let recording = Color(red: 1.00, green: 0.231, blue: 0.188)

    /// #5AC8FA — Apple cyan...
    static let transcribe = Color(red: 0.353, green: 0.784, blue: 0.980)

    /// #BF5AF2 — "AI" violet...
    static let enhance = Color(red: 0.749, green: 0.353, blue: 0.949)
```

Keep `success`, `warn`, `neutral`, `onyxBackground`, `HaloIntensity`, the `Color.a(_:)` extension, and ALL new tokens added in Task 1.

- [ ] **Step 10.3: Update Palette.swift docstring**

The file's top docstring (lines 3-10) mentions `Palette.recording etc.`. Replace it with a fresh description that points at `Palette.accent`:

```swift
/// Functional accents for VoiceInk UI. Single live-state accent (`accent`)
/// post-redesign 2026-04 — `success` (green), `warn` (amber), `neutral` (gray)
/// retained for non-state semantics. Source of truth:
/// `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.
///
/// Usage:
/// - `Palette.accent` for any live state (recording / transcribing /
///   enhancing / failed). Motion distinguishes states, not color.
/// - `Palette.accentMuted` for chip backgrounds (~0.16-0.42 alpha range).
/// - `Palette.accentGlow` for ringPulse shadow stops.
/// - `Palette.success` only for true completion / validation success.
/// - `Palette.hairline` / `hairlineSoft` for glass borders.
/// - `Palette.innerHi` for the top-edge sheen on glass surfaces.
```

---

### Task 11: Comment-cleanup pass — references to retired tokens in prose

- [ ] **Step 11.1: Find prose mentions of retired tokens**

```bash
grep -rn "Palette\.\(recording\|transcribe\|enhance\)" VoiceInk/ --include="*.swift"
```

After Task 10, this should ideally be 0. If anything remains, it'll be in `///` comments (e.g. `MenuBarIconRenderer.swift:13`). Update each comment to reference `Palette.accent` instead, or remove the per-state-color line entirely if it no longer applies.

Run the same grep again — should now return **empty**.

---

### Task 12: Full integration build (the gate)

**Files:** none (read-only verification)

- [ ] **Step 12.1: Run `make local`**

```bash
/usr/bin/make local 2>&1 | tail -30
```

Expected last lines include:
```
** BUILD SUCCEEDED **
Copying VoiceInk.app to ~/Downloads...
Build complete! App saved to: ~/Downloads/VoiceInk.app
```

If you see `BUILD FAILED`:
- Search the log upward for `error:` lines (`grep -nE "^.* error:" /tmp/voiceink-build.log`).
- If an `error: cannot find 'Palette\.recording' in scope` appears, you missed a call site. Re-run the Task 10.1 sweep, fix, re-build.
- If a different error appears, treat as a regression — bisect by reverting groups one at a time.

- [ ] **Step 12.2: Run unit tests**

In Xcode: ⌘U. Or headless:

```bash
xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk \
  -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `Test Suite 'PaletteTests' passed`. If `accentTokenHasExpectedHex` failed, the hex literal in `Palette.accent` drifted — check Task 1.1.

- [ ] **Step 12.3: Sanity-launch the app**

```bash
/usr/bin/killall VoiceInk 2>/dev/null; sleep 1
open ~/Downloads/VoiceInk.app
sleep 3
ps aux | grep -E "/VoiceInk\.app/Contents/MacOS/VoiceInk" | grep -v grep | head -1
```

Expected: a running process line. Open the menu-bar item, navigate to Settings → AI Models → AI Enhancement → History; the surfaces should render without crashes. Visual regression is expected (icons that were violet are now tangerine) — this is intended.

- [ ] **Step 12.4: Report status to lead — DO NOT commit**

Per CLAUDE.md, no commits during execution. Report:

```
W1 token-foundation: BUILD GREEN
- New tokens added: Palette.accent / accentMuted / accentGlow / onyxBg / onyxFg / onyxMute / hairline / hairlineSoft / innerHi
- New primitive: GlassChip + .glassChip()/.glassPanel() modifiers
- Migrated: <N> call sites across <M> files
- Retired: Palette.recording / Palette.transcribe / Palette.enhance (zero remaining refs)
- Tests: PaletteTests passing
- App: launches, surfaces render
- Diff: <git diff --stat | tail -1>
```

Lead reviews diff, decides whether to commit and dispatch W2.

---

## Self-review

- [x] **Spec coverage.**
  - §1 Material — Tokens (Task 1) ✓ · GlassChip primitive (Task 2) ✓
  - §5 Surface #1 (recorder/cluster prep) — HaloMaterial + ConstellationCard token swap (Task 4) ✓ (full cluster build is W2)
  - §5 Surface #10 (palette retirement) — All retired tokens removed (Task 10) ✓
  - §1 Type pass — explicitly W7, NOT this packet. Out of scope here.
  - §1 Reduce-Motion — GlassChip relies on SwiftUI Material's built-in fallback; no extra state needed (Task 2 docstring documents this).

- [x] **Placeholder scan.** No `TBD`, no "implement later", no "similar to Task N", no "add error handling" — every step has either exact code, exact file:line, or exact command.

- [x] **Type consistency.**
  - `Palette.accent` referenced in Tasks 1, 2, 4–9, 10, 11 — same exact spelling.
  - `GlassChip` modifier struct + `.glassChip()` / `.glassPanel()` view extensions — names consistent across Task 2 file and (eventual) W2/W5/W6 references.
  - `accentMuted` and `accentGlow` are defined in Task 1 but not actually consumed in W1 — they're seeded for W2/W3 to use. Documented as such in their docstrings.

- [x] **Migration completeness.** ~85 call sites grep'd before plan was written; each landed in exactly one group task (4–9). Sweep step 10.1 catches any miss.

- [x] **Build cadence.** No `make local` between tasks; one full build at Task 12.1 per CLAUDE.md.

- [x] **No commits.** Final step is "report to lead", not `git commit`. CLAUDE.md respected.

- [x] **Onboarding-deferral compliance.** Task 9 swaps tokens only; layout untouched. Onboarding redesign explicitly deferred per spec §5.

---

## Acceptance criteria

- ✅ `make local` completes with `** BUILD SUCCEEDED **`.
- ✅ `grep -rn "Palette\.\(recording\|transcribe\|enhance\)" VoiceInk/ --include="*.swift"` returns 0 matches.
- ✅ `PaletteTests` (Swift Testing bundle) passes — accent hex value verified.
- ✅ App launches; menu-bar item, Settings, AI Models, History, License screens render without crash.
- ✅ Visual regression confirmed: anything that was violet/blue/red is now tangerine. Greens (success) and ambers (warn) preserved.

## Estimated effort

~4-5 hours for one engineer familiar with the codebase. ~6-7 hours for a fresh teammate (most of the time is sweep verification + build cycles, not code).
