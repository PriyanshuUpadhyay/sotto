# Sotto Floating Recorder — Re-skin to Bay Visual Language

**Date:** 2026-05-22
**Branch:** `feat/constellation-reskin` (off `main`)
**Status:** design — approved, ready for implementation plan

## Problem

The Sotto recorder has two HUD implementations, selected by a user setting (`UserDefaults("RecorderType")`, surfaced in Settings as "Halo (Notch)" vs "Halo (Floating)"):

- **Notch** → `BayHUDView` — the current, on-brand HUD: acid-lime + phase-keyed accents, the 8-layer onyx `HaloMaterial` / `TacticalGlass`, phase-keyed halo glows.
- **Floating** → `ConstellationCluster` — an older HUD: **off-brand** — legacy tangerine accent (`Palette.accent`), the flat shared `GlassChip` material, no halos.

The floating recorder is the **default** (`RecorderType` defaults to `"mini"`), so the recorder most users see is the off-brand one. This re-skins it to Bay's visual language while keeping its distinct compact chip-cluster layout.

## Goal

Re-skin the floating (Constellation) recorder *in place* so it shares Bay's visual language — onyx tactical glass, phase-keyed accents, phase halo glows — without changing its chip-cluster layout or state logic.

## Non-goals

- No layout / geometry change — the chip cluster, anchor position, and `ChipPanel` composition stay.
- No change to `ClusterPhase` derivation, done-dwell / failed-dwell timers, `FailureRegistry` handling, action chips, or the accessibility structure.
- No change to Bay, the notch HUD, the window managers, or the recorder-style setting.
- The shared `GlassChip` / `.glassChip()` primitive is **not** modified — it is consumed app-wide (Settings, History, Metrics, prompt/transcribe views). The re-skin introduces a recorder-specific glass instead.

## Design

### 1. Recorder chip glass

The six Constellation chip views (`AnchorChip`, `KeyValueChip`, `TimeChip`, `DoneAnchorChip`, `ReasonChip`, `ActionChip` in `ClusterChips.swift`) currently end with `.glassChip()` — the shared, locked `GlassChip` primitive (flat `.ultraThinMaterial`, `rgba(20,20,28,0.55)` fill, no halo). Because `GlassChip` is consumed app-wide, it must not change.

Introduce a recorder-specific chip glass — a small view modifier, `recorderChip(phase:)` — that backgrounds content with `TacticalGlass` / `HaloMaterial` (onyx variant) clipped to an all-corners `RoundedRectangle` (the floating chips have no notch hard-edge, unlike Bay's `BottomRoundedRectangle`). It takes a `HaloPhase` to drive the halo. Corner radius and chip padding match the current `GlassChip` chip values (10pt radius; 11pt horizontal / 7pt vertical padding) so the cluster's footprint is unchanged.

The six `.glassChip()` call sites in `ClusterChips.swift` are swapped to `.recorderChip(phase:)`.

### 2. Phase-keyed accents

Add a `ClusterPhase → HaloPhase` mapping:

| ClusterPhase    | HaloPhase       |
|-----------------|-----------------|
| `.idle`         | `.hidden`       |
| `.recording`    | `.recording`    |
| `.transcribing` | `.transcribing` |
| `.enhancing`    | `.enhancing`    |
| `.done`         | `.done`         |
| `.failed`       | `.failed`       |

`HaloPhase` already exposes the phase palette via `glowColor` — red recording/fail, cyan transcribing, violet enhancing, green done. The re-skin replaces the legacy tangerine accents with phase-keyed colors:

- `AnchorChip` `dotColor` — recording → `Palette.recRed`, enhancing → `Palette.enhViolet`, failed → `Palette.recRed` (all currently `Palette.accent`). The transcribing anchor's neutral dot (`Palette.onyxFg`) stays — its cyan reads from the halo.
- `MeterBars` — `Palette.accent` → `Palette.brandAcid` (acid-lime), matching Bay's recording audio bars.
- `DoneAnchorChip` checkmark — `Palette.accent` → `Palette.commitGreen`.
- `RingPulseDot` ring stroke — `Palette.accentGlow` → the dot's own phase color.

### 3. Anchor-only halo

The `recorderChip(phase:)` glass renders the `HaloMaterial` outer halo only when its `phase` is a glowing phase. The **anchor chip** of each cluster passes the live `HaloPhase` → it carries the phase halo glow. **Secondary chips** (TIME, MODEL, PROMPT, reason) and **action chips** (RETRY, OPEN SETTINGS) pass `.hidden` → onyx glass, no glow. This keeps the multi-chip cluster calm — one glow per cluster, on the chip that owns the phase. (`HaloMaterial` with `.hidden` renders the full glass stack but a `.clear` / zero-alpha halo.)

### 4. Motion

- `RingPulseDot` — ring stroke recolored from `Palette.accentGlow` to the dot's phase color. Cadence (`.fast` / `.slow` / `.none`) unchanged.
- `ChipShimmer` (transcribing α-cycle) — kept as-is.
- `ChipBreath` — retired. The enhancing anchor's breathing halo is now carried by the `recorderChip` glass: when its phase is `.enhancing`, `recorderChip` drives `HaloMaterial`'s `breathePulse` with a repeating 0↔1 animation and sets `showInnerSheen: true` — the violet breathing halo + inner sheen, matching Bay's enhancing treatment. This preserves the *motion*, not just the color. The breathe driver respects Reduce Motion (static mid-amplitude when reduced). The `ChipBreath` type and its `.chipBreath()` view extension are removed; the enhancing `AnchorChip` no longer applies it.
- The Reduce-Motion branches in `RingPulseDot` and `ChipShimmer` are preserved. `HaloMaterial` brings High-Contrast handling (opaque fills, halo suppression, 1pt accent stroke) for free — the re-skinned recorder inherits it.

### 5. Files

| File | Change |
|------|--------|
| `VoiceInk/Views/Recorder/Constellation/ClusterChips.swift` | Swap the 6 `.glassChip()` → `.recorderChip(phase:)`; phase-key the `AnchorChip` dot colors, `MeterBars`, `DoneAnchorChip` checkmark; drop `.chipBreath()` from the enhancing anchor |
| `VoiceInk/Views/Recorder/Constellation/ClusterMotion.swift` | Recolor `RingPulseDot`'s ring to the phase color; remove `ChipBreath` and the `.chipBreath()` extension |
| `VoiceInk/Views/Recorder/Constellation/RecorderChipGlass.swift` | **New** — the `recorderChip(phase:)` modifier over `TacticalGlass` / `HaloMaterial`, plus the `ClusterPhase → HaloPhase` mapping |

## Testing

- The recorder has no unit-test surface for visuals, and the repo's `xcodebuild test` launcher is documented-broken. Gate on the headless build (`xcodebuild build … -quiet` → exit 0, no `error:` lines) plus a manual visual check.
- Manual: `make local`, select the Floating recorder style, run a record cycle — confirm onyx glass chips, the anchor-chip phase halo (red recording → cyan transcribing → violet enhancing → green committed → red fail), acid-lime meter bars, and no tangerine anywhere in the cluster. Toggle Reduce Motion and Increase Contrast and confirm graceful degradation.
- The pure `ClusterPhase → HaloPhase` mapping is a small pure function and can carry a lightweight unit test.

## Success criteria

1. Build gate green.
2. The floating recorder renders onyx `HaloMaterial` glass — no flat `GlassChip` material and no tangerine left in the cluster.
3. Accents are phase-keyed (red / cyan / violet / green; acid-lime meter bars), matching Bay.
4. Exactly the anchor chip of each cluster carries a phase halo; secondary and action chips do not glow.
5. The shared `GlassChip` primitive and all its non-recorder consumers are unchanged.
6. Reduce-Motion and Increase-Contrast both degrade gracefully.

## Open questions

None — design approved.
