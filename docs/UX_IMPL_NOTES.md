# Halo Implementation Notes

Companion to `UX_PROPOSAL.md`. Records build-time decisions, deviations from the proposal, and what's left to validate by hand.

## Pre-flight Decisions

### 1. Mini variant anchoring → **top**
Aligns with proposal lean. Single mental model ("VoiceInk lives at the top"). Eye lives near the menu bar; bottom anchoring competed with Dock. `MiniRecorderPanel.calculateWindowMetrics()` flips `yPosition` from `visibleFrame.minY + padding` to `visibleFrame.maxY - height - padding`.

Migration cost: zero (existing users won't notice — bottom-anchored Mini was barely a feature; Notch users unaffected). No per-user opt-out at this revision.

### 2. Idle visibility → **hidden by default**
Proposal lean. Less visual noise. The pill appears only when armed → recording. Idle-armed (low-opacity pill) deferred to stretch (`Idle Ambient Mode` in the proposal); design supports it but keeps it gated.

### 3. NSVisualEffectView blur under `.statusBar+3` panel → **implement defensively**
Path chosen: build `HaloMaterial` with `NSVisualEffectView` at `.hudWindow / .behindWindow / .dark`. The hosting controller already sets `view.layer.backgroundColor = clear`, panel is `isOpaque = false`, `backgroundColor = .clear`. These are the standard preconditions for behind-window blur to composite. `.statusBar + 3` is a window level — affects z-order, not blending.

**Fallback baked in:** the material stack layers translucent obsidian + inner gloss + stroke on top of the blur view. If blur fails to composite (wallpaper-tinting absent), the layered translucent black still reads as "liquid obsidian"; only the depth-of-field cue is lost. Will validate visually post-build; if blur fails entirely, swap blending mode to `.withinWindow` (rare) or remove the NSVisualEffectView and lean entirely on the translucent stack.

### 4. Functional palette → **6 fixed accents (per proposal §4.6)**
Locked in `Palette.swift` as static tokens. Rationale:

| Token | Hex | Use | Why |
|---|---|---|---|
| recording | #FF3B30 | red halo, record dot, settings:Recording icon | system-red, but a custom value (avoid `Color.red` system-shifting in Beta themes) |
| transcribe | #5AC8FA | cyan halo + shimmer | Apple-system cyan, distinct from recording without competing |
| enhance | #BF5AF2 | violet halo + breathe | "AI" violet — distinguishes machine-shaping from machine-listening |
| success | #30D158 | green flash, settings:Privacy icon | mid-saturation green; reads positive without lab green |
| warn | #FF9F0A | amber, settings:PowerMode icon | avoids ambient glow being mistaken for a fault state |
| neutral | #8E8E93 | idle/unselected | system gray, used as "no signal" baseline |

All values opaque — alpha applied at use-site (halo: 0.20–0.32; chip background: 0.16; dot: 1.0).

### 5. Bespoke sound design → **out of scope** (stretch)
Per brief.

## State Machine Mapping (engine → halo)

| Engine `RecordingState` | Halo display | Halo color | Notes |
|---|---|---|---|
| `idle` | hidden (panel orderOut'd by manager) | — | unchanged |
| `starting` | `recording` UI (assume mic warming up) | recording red | brief — engine flips to `recording` quickly |
| `recording` (no partial) | recording | red, audio-reactive | pulsing red dot |
| `recording` (with partial) | liveText | red | live transcript appended below |
| `transcribing` | transcribing | cyan | shimmer pass on stroke |
| `enhancing` | enhancing | violet | breathe + model-identity at right |
| `busy` | last visible state, frozen | last | engine transient |

`success`, `failed`, `cancelled` from the proposal: **deferred to a follow-up pass**. The engine doesn't surface a `failed` flag at the view layer today — adding that signal would require touching `VoiceInkEngine`, which the brief flags as out-of-scope. We get clean idle/recording/transcribing/enhancing morphing in v1; failure flash is a v2 polish.

## Implementation deviations from proposal §5

- Did **not** create separate `HaloShape.swift`. Reusing `NotchShape` + a plain `RoundedRectangle` for the off-notch case (top-anchored Mini) — the notch shape's flat top with quad-curved corners is specific to physical-notch geometry; for free-floating Mini we want an all-around rounded pill. Two shapes, picked at render time.
- `RecorderComponents.swift` left mostly untouched. Added a new `HaloStatusDisplay` (richer than `RecorderStatusDisplay`) for transcribing shimmer + enhancing model-identity. Old display kept for any external callers but no longer referenced by recorder.
- Settings polish (Day 2 of proposal) — implemented `Palette.swift`, `RecorderStylePicker.swift` (visual cards), `ProviderChip.swift`, `SettingsSectionHeader.swift`. Adopted in `SettingsView` for the most-visible sections; not exhaustive.

## Files touched / created

See final summary in handoff message.

## Validate by hand

- [ ] Notched Mac: trigger Notch recorder, verify pill morphs idle → recording → transcribing → enhancing → idle.
- [ ] Non-notched Mac (or external display): trigger Mini, same morphing, anchored top-center, **not** competing with the menu bar.
- [ ] Halo glow visible on a bright wallpaper. (Behind-window blur cue.)
- [ ] All 5 ASR engines transcribe (Whisper variants, Parakeet) — selectable from existing settings.
- [ ] All 5 enhancement providers complete (OpenAI, Ollama, LocalCLI, FoundationModels, MLX) — model identity renders inline during enhancing for each.
- [ ] Settings → Interface → Recorder Style picker shows two visual cards, selection persists.
- [ ] Provider chips render in EnhancementSettingsView and MenuBarView.

## Known limitations (v1)

- No `success` / `failed` / `cancelled` halo flashes (deferred — needs engine-side error flag).
- No `Idle Ambient Mode` (stretch from proposal §6.4).
- No animated menu bar icon (stretch from proposal §6.8).
- Power Mode horizontal-strip in Settings (proposal §4.4) — deferred; existing expandable row kept.
- Sound design (proposal §6.1) — deferred.
