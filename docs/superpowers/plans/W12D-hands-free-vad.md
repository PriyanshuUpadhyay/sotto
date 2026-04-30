# W12.D — Hands-free + VAD + voice "press enter" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.
>
> **Phase 2 packet — fourth.** W12.D adds a hotkey-toggleable continuous-listening mode with VAD-based utterance segmentation, voice-command "press enter" / "submit" / "send it" stripping with autoSend wiring, and a 20-min session cap (Wispr-parity). Accessibility-critical (Parkinson's users specifically cited Wispr for this) + long-form dictation use case (notes, journaling, code dictation).

**Date:** 2026-04-30
**Scope:** Add a new opt-in hands-free session mode behind a dedicated hotkey (`KeyboardShortcuts.Name.handsFreeToggle`). When the toggle fires, the recorder enters a continuous-listen state machine that segments utterances by RMS-derived silence threshold, runs each utterance through the existing transcribe→enhance→paste pipeline, and immediately re-arms for the next utterance. A post-enhance trigger-phrase filter scans for "press enter" / "submit" / "send it" / "send message" (configurable list); on match, the trigger is stripped from the pasted text and `CursorPaster.performAutoSend(.enter)` fires. A 20-min hard cap auto-stops the session and notifies the user. Menubar icon gains a `.handsFree` state variant (different glyph). Settings page gains a "Hands-free Mode" section with VAD threshold picker, silence-duration picker, trigger-phrase editor, session-cap display.

**Sources of truth:**
- R3 audit (the WHY for hands-free + voice "press enter"): `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` §1 P0-4 ("Hands-free / continuous mode" + "voice press enter" stripping), §2 row "Hands-free / continuous", §3 ("Voice press enter" — better than auto-send-on-stop), §6 ("new `Services/HandsFreeSessionService.swift` with VAD on `CoreAudioRecorder` tail").
- Master plan §3 W12.D: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`.
- W12.A shape reference: `docs/superpowers/plans/W12A-auto-cleanup-levels.md` (preamble + packet shape + tasks + rollback + risks + open Qs + post-merge protocol).
- Existing recorder + audio + hotkey surface (verified by grep + read at plan-time):
  - `VoiceInk/Recorder.swift` — public `Recorder` actor; exposes `audioMeter`, `startRecording`, `stopRecording`, `onAudioChunk`. Audio-meter timer at `:191` polls every 17ms.
  - `VoiceInk/CoreAudioRecorder.swift` — AUHAL-based `CoreAudioRecorder`; exposes `averagePower` / `peakPower` (thread-safe locks).
  - `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` — `toggleRecord(powerModeId:)` is the existing one-shot recording path; `runPipeline(...)` dispatches to `TranscriptionPipeline.run`.
  - `VoiceInk/Transcription/Engine/RecorderUIManager.swift` — `toggleMiniRecorder(...)` is the user-initiated entry point; `dismissMiniRecorder()` is the cleanup tail.
  - `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` — pipeline run; paste happens at `:191-214`; `CursorPaster.performAutoSend` fires at `:209-211` when `activeConfig.autoSendKey.isEnabled`.
  - `VoiceInk/HotkeyManager.swift` — global modifier-key + custom-shortcut hotkey monitor; `KeyboardShortcuts.Name` extension at `:7-15`.
  - `VoiceInk/MiniRecorderShortcutManager.swift` — registers `KeyboardShortcuts.onKeyDown` / `onKeyUp` for paste + history hotkeys.
  - `VoiceInk/CursorPaster.swift` — `pasteAtCursor(_:)` + `performAutoSend(_:)`. AutoSend supports `.enter` / `.shiftEnter` / `.commandEnter`.
  - `VoiceInk/PowerMode/PowerModeConfig.swift` — `AutoSendKey` enum at `:4-16`; PowerMode-level `autoSendKey` field.
  - `VoiceInk/Views/Common/MenuBarIconRenderer.swift` — `IconState` enum at `:28-42`; `MenuBarIcon` SwiftUI view at `:197-225`. Reuse this surface for the hands-free indicator.
  - `VoiceInk/Views/EnhancementSettingsView.swift` — global Settings host. Add "Hands-free Mode" section here OR new `HandsFreeSettingsView` reachable from main settings nav. Decision in T8.
  - `VoiceInk/Transcription/Whisper/VADModelManager.swift` — bundled silero-v5.1.2 VAD model exists, but is consumed only by the inner whisper.cpp pass (`LibWhisper.swift`) for in-pass voice-activity gating. **NOT reused for hands-free utterance segmentation in v1** — the bundled VAD is invoked synchronously inside the whisper transcription call, not on a live audio meter stream. Hands-free uses RMS gating off the existing `Recorder.audioMeter` instead. Out of scope to refactor `VADModelManager` for live streaming in this packet.
- Aesthetic spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` (Settings card vocabulary, `Palette.accent` glow, `GlassCard` chrome).

**Goal:** users assign one global hotkey for hands-free, hit it once to enter continuous-listen mode, dictate one or more utterances back-to-back without pressing anything else, and use voice commands ("press enter" / "submit") to fire enter without removing hands from rest. The session auto-ends at 20 min or when the hotkey fires again. VAD threshold + trigger phrase list + silence duration are configurable. **Recorder behavior outside hands-free is byte-for-byte unchanged.**

---

## Prelude — packet shape + commit etiquette

W12.D is **one logical packet** but its diff straddles a new service + recorder hooks + pipeline hooks + menubar renderer + new settings UI + the plan doc itself. Per CLAUDE.md `feedback_skip_per_packet_builds.md` the lead does ONE integration `make local` at merge time and ONE squashed `feat:` commit.

- `docs(plans): W12D — hands-free + VAD + voice press enter plan` — this file. Lands FIRST, before any code, after lead sign-off.
- `feat(hands-free): W12D — continuous mode + VAD + voice press-enter trigger` — code edits across the new service + recorder + pipeline + menubar + settings UI. **Single squashed commit** at merge time.

Coder leaves edits uncommitted; lead handles both commits. No per-task build is run during the packet; the integration `make local` runs once at the end (Task 11).

---

## Pre-merge ground-truth gate (USER-SIDE — light)

Hands-free is a UX-shape change with two failure modes that aren't visible in code review:

1. **VAD threshold mis-tuning.** RMS gating is microphone-dependent. The default −40 dBFS / 1500ms silence may cut the user off mid-thought OR stretch into long pauses. The post-merge tuning loop hinges on the user feeling the threshold against their mic + cadence.
2. **Trigger phrase false positives.** "Send me the report" includes "send" — but doesn't end with "send it". The suffix-match heuristic must fire on intent, not just keyword presence.

### Gate condition (light)

Before the coder touches code, the user runs **2 sample dictations** on the current `main` build with whatever recording style is normally used. For each, capture rough timings:

1. **Cadence dictation:** speak 4 short sentences with natural ~1-2s pauses between. Note: do the pauses feel like end-of-utterance, or just thinking pauses? The user's mental model for "what counts as silence" feeds the silence-duration default (Task 1).
2. **Trigger-phrase dictation:** speak 3 sentences ending in "send it." or "press enter." vs 3 sentences containing "send" mid-sentence (e.g. "send me the file", "press the button"). Note any phrasings the user wants to confirm fire-or-not.

Optionally save into `docs/superpowers/research/2026-04-30-w12d-handsfree-reference.md` (free-form notes — no required schema). The coder MAY proceed without it; it's a soft input, not a blocker. The lead may also skip the gate and tune post-merge.

---

## Architecture (W12.D change list — T1 through T9)

```
Task   Where                                                          Risk
─────  ─────────────────────────────────────────────────────────────  ─────
T1     Define HandsFreeMode config + state model                      LOW
       VoiceInk/HandsFree/HandsFreeMode.swift (NEW)
       VoiceInk/HandsFree/HandsFreeSessionState.swift (NEW)
       VoiceInk/AppDefaults.swift                                     — register defaults

T2     Register handsFreeToggle KeyboardShortcuts.Name + hotkey wire  LOW
       VoiceInk/HotkeyManager.swift                                   — additive .Name + onKeyUp handler

T3     HandsFreeSessionService — state machine + 20-min cap           HIGH
       VoiceInk/HandsFree/HandsFreeSessionService.swift (NEW)         — load-bearing wall of W12.D.
                                                                        Coordinates recorder cycling
                                                                        + utterance commit + cap timer.

T4     Silence detection — RMS gating off Recorder.audioMeter         MED
       VoiceInk/HandsFree/SilenceDetector.swift (NEW)                 — pure detector; no UI.

T5     Utterance-commit flow — pipeline cycle                         MED
       VoiceInk/Transcription/Engine/VoiceInkEngine.swift             — new commitUtterance() entry
                                                                        point; reuses runPipeline.

T6     Voice-trigger filter — strip "press enter" + autoSend          LOW
       VoiceInk/HandsFree/VoiceTriggerFilter.swift (NEW)              — pure string + AutoSendKey.
       VoiceInk/Transcription/Engine/TranscriptionPipeline.swift      — inject before paste, gated
                                                                        on hands-free active.

T7     Menubar indicator — .handsFree icon variant                    LOW
       VoiceInk/Views/Common/MenuBarIconRenderer.swift                — IconState gains .handsFree;
                                                                        glyph "ear.fill" tinted accent.

T8     Settings UI — Hands-free Mode section                          LOW
       VoiceInk/Views/Settings/HandsFreeSettingsView.swift (NEW)      — VAD threshold slider, silence
                                                                        duration picker, trigger
                                                                        phrase list editor, session
                                                                        cap display, hotkey binding.
       VoiceInk/Views/Settings/SettingsView.swift                     — nav entry.

T9     Cancellation + cleanup hardening                               MED
       VoiceInk/HandsFree/HandsFreeSessionService.swift               — endSession() must cancel
                                                                        in-flight commit, stop the
                                                                        cap timer, reset menubar
                                                                        icon, clear notification.
```

**Combined target:** users hit one hotkey, dictate continuously with VAD-segmented utterances, use voice triggers to autoSend, and exit at 20 min or by hitting the hotkey again. **Single integration build at Task 11.** No new SPM deps. No deployment-target bump (already at 26.0 from W11.B). No new test files (Q10 deferred).

---

## Tech Stack

Swift 5.x, SwiftUI, AppKit, Combine. **No SPM additions.** macOS 26.0 deployment target (post-W11.B). The `KeyboardShortcuts` SPM dep is already in-tree and is the registered shortcut surface for T2.

VAD = audio-level RMS gating off the existing `Recorder.audioMeter` (smoothed average + peak, normalized to [0, 1] per `Recorder.updateAudioMeter:212-227`). The bundled silero-v5.1.2 model in `VADModelManager` is **NOT reused** for live segmentation in v1 — it's a per-pass whisper.cpp dependency, not a streaming detector. A follow-up packet could swap RMS for silero streaming if the simple gate proves insufficient (see Risks #2).

Build via `make local` (~3 min cold). One integration build at Task 11.

---

## Spec refs

- Research: `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` §1 (P0 list — "Hands-free / continuous mode + auto-stop + voice press enter"), §2 row "Hands-free / continuous (toggle + VAD)", §3 ("Voice press enter that strips itself from the output. Better than the auto-send-on-stop model VoiceInk has — keeps keyboard hands-off without burning the user when they didn't actually want to submit. Just a token-tail check before paste."), §6 (implementation pointers — "new `Services/HandsFreeSessionService.swift` with VAD on `CoreAudioRecorder` tail; tail-token stripping in pre-paste step").
- Master plan: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` §3 W12.D scope (toggle + VAD + voice "press enter" + 20-min cap).
- Aesthetic spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §3.7 (SettingsCard vocabulary), §4 (color tokens — `Palette.accent` for the menubar tint).
- W12.A precedent for plan shape + commit etiquette + risk shape.

---

## CLAUDE.md cadence rules respected

- **Single integration build at merge time.** No `make local` per task; one full build at Task 11. Per `feedback_skip_per_packet_builds.md`.
- **One squashed commit at merge time.** No per-task commits during execution.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** New `🦾` log markers may extend the existing convention (e.g. `🦾 hands-free: state=listening`) for observability.
- **No new test files.** Per master plan §0 Q10=defer, validation is build-only.
- **No SPM additions, no deployment-target bump.**
- **No pbxproj edits.** Files added under `VoiceInk/HandsFree/` and `VoiceInk/Views/Settings/` auto-included by Xcode 16 PBXFileSystemSynchronizedRootGroup.

---

## File structure

### New files

- `VoiceInk/HandsFree/HandsFreeMode.swift` (~80 LOC) — config struct: VAD threshold (Float dBFS, default −40), silence duration (TimeInterval, default 1.5s), session cap (TimeInterval, hard-coded 20 * 60 = 1200s), trigger-phrase list (`[String]`, default `["press enter", "submit", "send it", "send message"]`). Codable for JSON-encoded `@AppStorage` round-trip. `static let `default` for first-run.

- `VoiceInk/HandsFree/HandsFreeSessionState.swift` (~40 LOC) — enum: `.inactive / .listening / .committing / .endingSession`. Equatable. `displayName` for menubar accessibility.

- `VoiceInk/HandsFree/HandsFreeSessionService.swift` (~280 LOC) — the load-bearing wall. `@MainActor` `ObservableObject`. Holds `@Published var state: HandsFreeSessionState`. Public API: `func toggle()` (start or stop), `func endSession(reason: EndReason)` (graceful stop). Internal: `func handleSilenceDetected()` (advances `.listening → .committing`), `func handleUtteranceCommitted()` (back to `.listening`), `func handleSessionCapFired()` (graceful stop with notification). 20-min cap is a `Task` started at session begin, cancelled on `endSession`. `EndReason` enum: `.userToggle / .sessionCap / .pipelineFailure / .otherHotkey`. Owns the `SilenceDetector` instance + the cap-timer task. Subscribes to `Recorder.$audioMeter` via Combine to feed the silence detector.

- `VoiceInk/HandsFree/SilenceDetector.swift` (~110 LOC) — pure detector; no UI; no Combine. Stateful `class` (or `actor`?) with `func update(meter: AudioMeter, now: Date) -> SilenceEvent?`. Internal state: `lastVoiceTimestamp: Date?` (timestamp of last sample with `averagePower >= threshold`), `hasSpokenInUtterance: Bool` (gate against starting a "silence" event before any voice has been heard — prevents firing on session start). Emits `.silenceDetected` exactly once per utterance boundary (debounced internally). `reset()` to start a fresh utterance. **MAIN-ACTOR-SAFE:** all access through `HandsFreeSessionService` which is `@MainActor`; no concurrency primitives needed inside the detector itself.

- `VoiceInk/HandsFree/VoiceTriggerFilter.swift` (~80 LOC) — pure string utility. `static func detectTrigger(in: String, against: [String]) -> TriggerHit?` returning `.some((cleanedText: String, autoSend: AutoSendKey))` or `.none`. Suffix-match policy: lowercase the last `maxTriggerWords` words of the input (cap at 5 words, ~36 chars), strip trailing punctuation, exact-suffix-match against each trigger phrase normalized the same way. On hit, return the input text with the trigger suffix stripped + the matching `AutoSendKey` (default `.enter` for all triggers in v1; later packets could vary per trigger). NOT a regex — keep it boring.

- `VoiceInk/Views/Settings/HandsFreeSettingsView.swift` (~220 LOC) — settings page. Sections:
  - **Activation** — `KeyboardShortcuts.Recorder` for `handsFreeToggle`. Inline help: "Press once to start; press again to stop. Sessions cap at 20 min."
  - **Voice activity (VAD) threshold** — segmented picker with 3 named cells (Low / Medium / High = -50 / -40 / -30 dBFS) + advanced disclosure with raw slider (-60 to -20 dBFS). Default Medium.
  - **Silence duration** — segmented picker with 3 cells (Quick / Standard / Patient = 1.0 / 1.5 / 2.5 seconds). Default Standard.
  - **Voice triggers** — list of trigger phrases with add/edit/remove. Each row: TextField + delete button. Footer hint: "When detected at the END of an utterance, the trigger is removed and Enter is pressed for you. Mid-utterance occurrences are ignored."
  - **Session cap** — read-only display: "Sessions auto-stop at 20 minutes. (Configurable in a future release.)"

### Modified files

- `VoiceInk/HotkeyManager.swift` — T2. Add `static let handsFreeToggle = Self("handsFreeToggle")` to the `KeyboardShortcuts.Name` extension at `:7-15`. In `init(...)` (around `:166`, after the existing custom-shortcut registrations), add a single `KeyboardShortcuts.onKeyUp(for: .handsFreeToggle) { … }` handler that calls `HandsFreeSessionService.shared.toggle()`. **No default shortcut is auto-bound** — per Open Question #1, the default is unset; the user assigns it via the settings page (T8). ~+10 LOC.

- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` — T5. Add `func commitUtterance() async` — adapter over the existing `toggleRecord(powerModeId:)` flow. The existing `toggleRecord` toggles between recording start / recording stop + pipeline run; for hands-free we want to STOP + RUN PIPELINE + START AGAIN as one atomic step. Implementation: if `recordingState == .recording`, run the existing stop→pipeline path inline, then immediately call `toggleRecord(powerModeId: …)` again to re-arm. Each utterance is its own `Transcription` row (no schema change — matches existing model). ~+25 LOC, -0 LOC.

- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` — T6. Inject voice-trigger filter into the paste step. Around `:191-214`, before `CursorPaster.pasteAtCursor(textToPaste + …)`:
  ```swift
  let isHandsFreeActive = HandsFreeSessionService.shared.state != .inactive
  let triggerHit: VoiceTriggerFilter.TriggerHit? = isHandsFreeActive
      ? VoiceTriggerFilter.detectTrigger(
          in: textToPaste,
          against: HandsFreeSessionService.shared.mode.triggerPhrases
        )
      : nil
  let pasteText = triggerHit?.cleanedText ?? textToPaste
  // ... existing paste call uses pasteText ...
  ```
  Then after the paste keystroke fires (in the existing `asyncAfter` block), if `triggerHit != nil`, fire `CursorPaster.performAutoSend(triggerHit!.autoSend)` after the existing autoSend delay. Suppress the existing PowerMode `activeConfig.autoSendKey` autoSend when a voice trigger fires (otherwise we'd send Enter twice on a "press enter" utterance under a PowerMode that ALSO has autoSend enabled). ~+20 LOC.

- `VoiceInk/Views/Common/MenuBarIconRenderer.swift` — T7. Extend `IconState` enum at `:28-42` with `.handsFree`. Add the case to the `init(_ state: RecordingState)` initializer — but this initializer takes `RecordingState`, not hands-free state. **Decision:** add a SECOND `IconState` source via a new initializer `init(handsFree: HandsFreeSessionState, recordingState: RecordingState)` that returns `.handsFree` when hands-free is active (regardless of inner recording state) else falls through to the existing `init(_ state:)` mapping. Update `RecordingStateObserver` (`:153-187`) to subscribe to `HandsFreeSessionService.shared.$state` AND `engine.$recordingState`, combining both via `Publishers.CombineLatest` to drive `iconState`. New `image(for: .handsFree)` returns a tinted "ear.fill" SF Symbol at the existing canvas size. ~+45 LOC.

- `VoiceInk/Views/Settings/SettingsView.swift` — T8. Nav entry. Add a row pointing to `HandsFreeSettingsView()` in the existing settings nav structure. Ordering: under "Enhancement" or "Recorder" depending on the existing IA; coder picks a sensible slot. ~+5 LOC.

- `VoiceInk/AppDefaults.swift` — T1. Register hands-free defaults:
  ```swift
  // Hands-free
  "HandsFreeVADThresholdDb": -40.0,
  "HandsFreeSilenceDurationMs": 1500,
  "HandsFreeTriggerPhrasesJSON": #"["press enter","submit","send it","send message"]"#,
  ```
  ~+3 LOC.

### Untouched (explicit list — coder do NOT drift)

- `VoiceInk/Recorder.swift` — public API stays. T3 subscribes to the existing `@Published var audioMeter` via Combine; no method on `Recorder` changes.
- `VoiceInk/CoreAudioRecorder.swift` — UNTOUCHED. The hands-free service uses stop+start cycling between utterances (Migration policy #5). File rotation (avoiding the AUHAL stop/start cost) is a follow-up if user reports gaps.
- `VoiceInk/Transcription/Whisper/VADModelManager.swift` — UNTOUCHED. silero is a per-whisper-pass dependency; not used for live segmentation in v1.
- `VoiceInk/Transcription/Engine/RecorderUIManager.swift` — UNTOUCHED. Hands-free uses `engine.toggleRecord(...)` and `engine.commitUtterance()` directly; the mini-recorder UI lifecycle is owned by `RecorderUIManager.toggleMiniRecorder` and stays unchanged. **Implication:** during a hands-free session, the recorder panel IS visible (showing `.recording` state with the audio meter), and dismisses cleanly on session end via the existing `dismissMiniRecorder()` path called from `HandsFreeSessionService.endSession()`.
- `VoiceInk/PowerMode/PowerModeConfig.swift` — UNTOUCHED. The PowerMode `autoSendKey` field is read-only consumed by T6's filter (suppressed when a voice trigger fires).
- `VoiceInk/CursorPaster.swift` — UNTOUCHED. T6 reuses `pasteAtCursor` + `performAutoSend(.enter)` as-is.
- `VoiceInk/MiniRecorderShortcutManager.swift`, `VoiceInk/PowerMode/PowerModeShortcutManager.swift` — UNTOUCHED. `handsFreeToggle` is registered alongside paste/history/dictionary in `HotkeyManager.init` (T2).
- `VoiceInk/Models/Transcription.swift` — UNTOUCHED. Each hands-free utterance becomes a separate `Transcription` row; no schema change. (Migration policy #4.)
- `VoiceInk/Services/AIEnhancement/*` — UNTOUCHED. Hands-free uses the same enhance pipeline; W12.A's `enhanceLevel` flows through unchanged.
- All test files (`VoiceInkTests/*.swift`) — W12.D ships no new tests. Per master plan §0 Q10.
- `VoiceInk/Services/ImportExportService.swift` — UNTOUCHED. The hands-free config is `@AppStorage`-backed only; not part of PowerMode or transcription export.

---

## Migration policy (resolves ambiguity for each design point)

The lead pinned the following architecture decisions for this packet. Restated as the authoritative ruleset for the coder.

1. **Default state: opt-in, off, no shortcut bound.** New installs get the registered defaults (Task 1) but no `handsFreeToggle` shortcut. The user explicitly sets the shortcut in `HandsFreeSettingsView` (T8) before the feature is reachable. Rationale: the master plan §3 W12.D doesn't mandate a default; user previously expressed (Q5 for W12.B) preference for predictable + configurable hotkeys over presumed defaults. Caps+H (Hyper+H) is a reasonable RECOMMENDATION shown as the placeholder text in the settings UI but is not auto-bound. **Open Question #1 flags this — user may flip to auto-bind if they prefer.**

2. **Existing recorder behavior is byte-for-byte unchanged when hands-free is inactive.** All new code paths gate on `HandsFreeSessionService.shared.state != .inactive`. The non-hands-free hotkey flow (`HotkeyManager.processKeyPress` → `RecorderUIManager.toggleMiniRecorder` → `VoiceInkEngine.toggleRecord`) is untouched. The pipeline's voice-trigger filter (T6) returns `nil` when hands-free is inactive, short-circuiting before any string work.

3. **Hands-free is a single-instance global session.** `HandsFreeSessionService` is a `static let shared` singleton on the main actor. Only one hands-free session exists at a time; toggling while active ends it; toggling while a regular recorder is active ends the regular one first. Rationale: avoids the "is this hotkey for this recorder or that one" UX trap. **Hotkey collision policy:** if the user presses a normal toggle hotkey (`toggleMiniRecorder` / `toggleMiniRecorder2` / modifier hotkeys) while hands-free is active, the hands-free session ends first (graceful pipeline drain, then re-arm). The user's normal hotkey behavior takes effect AFTER. Implemented in `HotkeyManager.canProcessHotkeyAction` extending guard.

4. **Each utterance = its own `Transcription` row.** No schema change; the existing `VoiceInkEngine.runPipeline` pattern creates one `Transcription` per recording. Hands-free reuses this exactly. The History view will show one row per utterance. PowerMode + level + prompt all flow through unchanged. **Implication:** a 5-minute hands-free session could create 30+ Transcription rows. This matches Wispr's UX (each utterance is a discrete dictation event in their history). **Out of scope:** "hands-free session grouping" in History — a future packet could wrap consecutive Transcriptions from the same session under a parent `HandsFreeSession` model.

5. **Stop+start audio between utterances for v1.** When silence fires, `HandsFreeSessionService` calls `engine.commitUtterance()` which (a) stops the current `Recorder`, (b) runs the existing pipeline, (c) starts a NEW `Recorder` instance. Trade-off: ~150-300ms gap between utterances during which voice is dropped. **Rationale:** zero risk — the existing `toggleRecord` flow is already validated end-to-end. **Follow-up if user reports gaps:** add `Recorder.rotateOutputFile(toURL:)` that closes the current `audioFile` and opens a new one in the audio thread, keeping the AUHAL running. Risk #4 documents this.

6. **VAD = simple RMS gating, NOT silero streaming.** The bundled silero model is consumed by the inner whisper pass (`LibWhisper.swift:73-75`); refactoring it for live streaming is a separate, larger packet. v1 uses `Recorder.$audioMeter`'s smoothed `averagePower` (already EMA-smoothed at 17ms cadence) compared against a threshold. **Threshold default:** −40 dBFS. **Silence duration default:** 1500 ms. Both `@AppStorage`-backed so the user can tune without a rebuild.

7. **Voice trigger detection runs POST-enhance, on the final paste-bound text.** Reasoning: enhance applies punctuation + capitalization; the trigger filter must see "Press enter." (with caps + period from enhance), not "press enter" raw. Suffix-match strips the trigger from the final text BEFORE paste, then fires `CursorPaster.performAutoSend(.enter)` after the existing paste delay. **Mid-utterance occurrences are ignored** — the trigger must be at the literal end of the utterance (after lowercasing + trailing-punct strip + last-N-words).

8. **Voice trigger overrides PowerMode autoSend.** If the active PowerMode has `autoSendKey != .none` AND a voice trigger fires, ONLY the voice-trigger autoSend fires (not both). Otherwise the user gets Enter twice on a "press enter" utterance under a PowerMode that auto-sends. Implementation: T6's voice-trigger branch sets a local flag that suppresses the existing PowerMode autoSend at `TranscriptionPipeline.swift:208-211`.

9. **20-min session cap is hard-coded in v1.** Master plan §3 W12.D specifies "20-min cap matches Wispr." Configurable cap is out of scope; flagged Open Question #6. The cap is implemented as `Task.sleep(nanoseconds: 20 * 60 * 1_000_000_000)` started at session begin, cancelled on session end. On fire, `HandsFreeSessionService.endSession(reason: .sessionCap)` runs the graceful drain and shows a `NotificationManager.showNotification(title: "Hands-free session ended (20-min cap)", type: .info)`.

10. **Menubar icon reflects ALL of `(hands-free state, recording state)`.** When hands-free is active, the icon shows the `.handsFree` glyph (tinted ear.fill) regardless of the inner recording state — the user wants to see "I'm in hands-free" at all times, not "I'm transcribing right now". When hands-free is inactive, the icon falls back to the existing `IconState(_ recordingState:)` mapping. Combine merge in `RecordingStateObserver` (T7).

11. **Settings UI lives in its own new view, NOT folded into `EnhancementSettingsView`.** Reasoning: hands-free is conceptually parallel to enhance (it changes recorder lifecycle, not enhance output); putting it under "Enhancement" misframes it. New `HandsFreeSettingsView.swift` reachable from the main Settings nav. T8.

12. **AppStorage-only persistence; no SwiftData.** All hands-free config (`HandsFreeMode`) is registered defaults + `@AppStorage`-encoded. No SwiftData migration. ImportExportService UNTOUCHED.

13. **No emoji in new code.** Existing `🦾` markers stay (W6 instrumentation). New `🦾 hands-free: …` markers may extend the convention; no other emoji.

14. **No deployment-target bump.** Already at 26.0 from W11.B. RMS gating + KeyboardShortcuts + Combine + SwiftData all comfortably supported.

15. **No SPM additions.** RMS gating uses existing `Recorder.audioMeter`. silero is bundled but not reused. `KeyboardShortcuts` is already a dep.

16. **Out of scope: wake-word activation ("Hey VoiceInk").** v1 is hotkey-toggle only. Wake-word would require always-on audio capture + a wake-word model + a privacy review; deferred to a future P1+ packet.

17. **Out of scope: per-app hands-free overrides via PowerMode.** A future packet could let a PowerMode declare "auto-enter hands-free when this app is frontmost". Out of scope for v1.

18. **Out of scope: live-transcription overlay during hands-free.** No real-time-text-before-commit visualization. The recorder panel still shows the audio meter; the partial-transcript stream is already piped into the existing recorder UI via `engine.partialTranscript` and remains as-is during hands-free.

19. **Out of scope: custom session-cap value.** 20-min hard-coded. Open Question #6 if user has concerns.

---

## Tasks

### Task 0 — Audit + read references

**Files:** none (read-only).

- [ ] **Step 0.1 — Confirm `Recorder.audioMeter` is published**

```bash
grep -n "audioMeter\|@Published" VoiceInk/Recorder.swift | head -10
```

Expected: `@Published var audioMeter = AudioMeter(averagePower: 0, peakPower: 0)` at `:15`. The smoothed values feed it via the audio-meter timer at `:191-241`. T4's `SilenceDetector` consumes this via Combine.

- [ ] **Step 0.2 — Confirm `KeyboardShortcuts.Name` extension shape**

```bash
grep -n "extension KeyboardShortcuts.Name\|static let " VoiceInk/HotkeyManager.swift | head -10
```

Expected: extension at `:7-15` with `.toggleMiniRecorder` / `.toggleMiniRecorder2` / `.pasteLastTranscription` / `.pasteLastEnhancement` / `.retryLastTranscription` / `.openHistoryWindow` / `.quickAddToDictionary`. T2 adds `.handsFreeToggle` to this list.

- [ ] **Step 0.3 — Confirm `CursorPaster.performAutoSend` signature**

```bash
grep -n "performAutoSend\|case \.enter" VoiceInk/CursorPaster.swift VoiceInk/PowerMode/PowerModeConfig.swift | head -10
```

Expected: `static func performAutoSend(_ key: AutoSendKey)` at `CursorPaster.swift:196`; `AutoSendKey` enum with `.enter` / `.shiftEnter` / `.commandEnter` cases at `PowerModeConfig.swift:4-16`. T6 reuses both.

- [ ] **Step 0.4 — Confirm `MenuBarIconRenderer.IconState` shape**

```bash
grep -n "enum IconState\|case .idle\|case .recording" VoiceInk/Views/Common/MenuBarIconRenderer.swift | head -10
```

Expected: `enum IconState { case idle, recording, transcribing, enhancing }` at `:28-42`. T7 adds `.handsFree`.

- [ ] **Step 0.5 — Confirm `TranscriptionPipeline.run` paste path**

```bash
grep -n "pasteAtCursor\|performAutoSend\|autoSendKey" VoiceInk/Transcription/Engine/TranscriptionPipeline.swift | head -10
```

Expected: paste at `:204-205`; PowerMode autoSend at `:207-211`. T6 inserts the voice-trigger filter ABOVE the paste call and fires its own autoSend AFTER the paste, suppressing the PowerMode autoSend on hit.

- [ ] **Step 0.6 — Confirm `RecorderUIManager.toggleMiniRecorder` is the existing user-initiated entry**

```bash
grep -n "func toggleMiniRecorder\|func toggleRecord" VoiceInk/Transcription/Engine/RecorderUIManager.swift VoiceInk/Transcription/Engine/VoiceInkEngine.swift | head -10
```

Expected: `RecorderUIManager.toggleMiniRecorder(powerModeId:)` at the manager (`:120`); `VoiceInkEngine.toggleRecord(powerModeId:)` at the engine (`:105`). T5's `commitUtterance()` is a sibling of the latter — sequential STOP+RUN+START rather than the existing toggle.

- [ ] **Step 0.7 — Confirm pre-merge gate file existence is optional**

```bash
ls -la docs/superpowers/research/2026-04-30-w12d-handsfree-reference.md 2>&1 || echo "absent — soft gate, may proceed"
```

Either outcome is acceptable.

---

### Task 1 — Define `HandsFreeMode` + `HandsFreeSessionState`

**Files:**
- Create: `VoiceInk/HandsFree/HandsFreeMode.swift`
- Create: `VoiceInk/HandsFree/HandsFreeSessionState.swift`
- Modify: `VoiceInk/AppDefaults.swift`

- [ ] **Step 1.1 — Write `HandsFreeMode`**

```swift
import Foundation

/// W12.D hands-free configuration. Persisted via `@AppStorage` (3 separate
/// keys; see `AppDefaults`). Constructed on demand from defaults; the
/// canonical source is the per-key UserDefaults values.
struct HandsFreeMode: Equatable {
    /// dBFS gate for "voice present". Samples with average power < threshold
    /// count as silence. Default −40 dBFS.
    var vadThresholdDb: Float

    /// Continuous-silence duration before an utterance commits. Default 1.5s.
    var silenceDuration: TimeInterval

    /// Hard session cap. Master plan §3 W12.D: "20-min cap matches Wispr."
    /// Hard-coded in v1; flagged Open Question #6.
    var sessionCap: TimeInterval { 20.0 * 60.0 }

    /// Trigger phrases that, when matched at the END of an utterance, strip
    /// themselves and fire AutoSend(.enter). Defaults from
    /// `AppDefaults.registerDefaults()`.
    var triggerPhrases: [String]

    /// Read the current state from UserDefaults.
    static func current() -> HandsFreeMode {
        let thresholdDb = UserDefaults.standard.float(forKey: "HandsFreeVADThresholdDb")
        let silenceMs = UserDefaults.standard.integer(forKey: "HandsFreeSilenceDurationMs")
        let phrasesJSON = UserDefaults.standard.string(forKey: "HandsFreeTriggerPhrasesJSON") ?? "[]"
        let phrases = (try? JSONDecoder().decode([String].self, from: Data(phrasesJSON.utf8))) ?? []
        return HandsFreeMode(
            vadThresholdDb: thresholdDb,
            silenceDuration: TimeInterval(silenceMs) / 1000.0,
            triggerPhrases: phrases
        )
    }

    /// Write the trigger phrase list back to UserDefaults as JSON.
    static func saveTriggerPhrases(_ phrases: [String]) {
        let json = (try? JSONEncoder().encode(phrases))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "[]"
        UserDefaults.standard.set(json, forKey: "HandsFreeTriggerPhrasesJSON")
    }
}
```

- [ ] **Step 1.2 — Write `HandsFreeSessionState`**

```swift
import Foundation

/// W12.D session lifecycle. Owned by `HandsFreeSessionService`; published to
/// SwiftUI + the menubar observer.
enum HandsFreeSessionState: Equatable {
    /// Default. Recorder behaves exactly as pre-W12.D.
    case inactive

    /// Recorder is running, listening for voice. Transitions to `.committing`
    /// when `SilenceDetector` reports an utterance boundary.
    case listening

    /// An utterance just ended. `VoiceInkEngine.commitUtterance()` is running
    /// (stop → pipeline → restart). Transitions back to `.listening` when
    /// the new recorder is started, or to `.inactive` on session end.
    case committing

    /// Graceful drain in progress (user toggle, session cap, or pipeline
    /// failure). Transitions to `.inactive` when cleanup is done.
    case endingSession

    var displayName: String {
        switch self {
        case .inactive:      return "Inactive"
        case .listening:     return "Listening"
        case .committing:    return "Committing"
        case .endingSession: return "Ending"
        }
    }
}
```

- [ ] **Step 1.3 — Register AppDefaults**

In `VoiceInk/AppDefaults.swift`, after the existing `// Model` block:

```swift
// Hands-free
"HandsFreeVADThresholdDb": Float(-40.0),
"HandsFreeSilenceDurationMs": 1500,
"HandsFreeTriggerPhrasesJSON": #"["press enter","submit","send it","send message"]"#,
```

- [ ] **Step 1.4 — Verify**

```bash
grep -rn "HandsFreeMode\|HandsFreeSessionState" VoiceInk --include="*.swift"
```

Expected: only the new files. T3-T8 add call sites.

**Risk:** LOW — pure additive types + registered defaults.

**Verification:** type-check passes.

---

### Task 2 — Register `handsFreeToggle` hotkey

**Files:**
- Modify: `VoiceInk/HotkeyManager.swift`

- [ ] **Step 2.1 — Add `.handsFreeToggle` to the `KeyboardShortcuts.Name` extension**

```swift
extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    static let toggleMiniRecorder2 = Self("toggleMiniRecorder2")
    static let pasteLastTranscription = Self("pasteLastTranscription")
    static let pasteLastEnhancement = Self("pasteLastEnhancement")
    static let retryLastTranscription = Self("retryLastTranscription")
    static let openHistoryWindow = Self("openHistoryWindow")
    static let quickAddToDictionary = Self("quickAddToDictionary")
    static let handsFreeToggle = Self("handsFreeToggle")  // W12.D
}
```

- [ ] **Step 2.2 — Register the onKeyUp handler in `init(...)`**

In `HotkeyManager.init(engine:recorderUIManager:)` around `:166-207` (the existing `KeyboardShortcuts.onKeyUp` block), add:

```swift
KeyboardShortcuts.onKeyUp(for: .handsFreeToggle) { [weak self] in
    guard let self = self else { return }
    Task { @MainActor in
        await HandsFreeSessionService.shared.toggle(engine: self.engine,
                                                    recorderUIManager: self.recorderUIManager)
    }
}
```

The service receives `engine` + `recorderUIManager` so it can drive the recorder cycling; alternative is `static let shared` with a `configure(engine:recorderUIManager:)` step at app start. Coder picks whichever fits the existing service-locator pattern (the codebase uses `PowerModeManager.shared` and `SoundManager.shared` already — match that style).

- [ ] **Step 2.3 — Hotkey collision policy: normal hotkey ends hands-free first**

In `HotkeyManager.processKeyPress(...)` around `:389-444` AND `handleCustomShortcutKeyDown(...)` around `:446-480`, before any `await recorderUIManager.toggleMiniRecorder()` call where the user is requesting a NORMAL recording action, add:

```swift
if HandsFreeSessionService.shared.state != .inactive {
    await HandsFreeSessionService.shared.endSession(reason: .otherHotkey)
    return  // user's normal-hotkey intent re-fires after they release + re-press
}
```

Implementation note: a single press DOES end hands-free, but does NOT also start a normal recorder in the same press. Rationale: starting a recorder on the same press is a usability footgun (the user just said "exit hands-free" — they didn't necessarily say "start a one-shot recording right now"). User presses again to start the normal recorder.

- [ ] **Step 2.4 — Verify**

```bash
grep -rn "handsFreeToggle\|HandsFreeSessionService" VoiceInk --include="*.swift"
```

Expected: definitions in `HotkeyManager.swift` (KeyboardShortcuts.Name extension + onKeyUp handler + collision policy) + service references. T3 adds the service definition.

**Risk:** LOW — additive hotkey + a guard before existing hotkey actions.

**Verification:** type-check passes.

---

### Task 3 — Implement `HandsFreeSessionService`

**Files:**
- Create: `VoiceInk/HandsFree/HandsFreeSessionService.swift`

- [ ] **Step 3.1 — Define the service skeleton**

```swift
import Foundation
import Combine
import os

/// W12.D hands-free session orchestrator. Single global instance; coordinates
/// recorder cycling, silence detection, the 20-min cap, and graceful drain.
/// All state mutation is `@MainActor`-confined.
@MainActor
final class HandsFreeSessionService: ObservableObject {
    static let shared = HandsFreeSessionService()

    @Published private(set) var state: HandsFreeSessionState = .inactive
    private(set) var mode: HandsFreeMode = .current()

    private weak var engine: VoiceInkEngine?
    private weak var recorderUIManager: RecorderUIManager?

    private let silenceDetector = SilenceDetector()
    private var meterCancellable: AnyCancellable?
    private var capTimerTask: Task<Void, Never>?
    private var commitTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink",
                                category: "HandsFreeSessionService")

    enum EndReason: String {
        case userToggle = "user-toggle"
        case sessionCap = "session-cap"
        case pipelineFailure = "pipeline-failure"
        case otherHotkey = "other-hotkey"
    }

    private init() {}

    func toggle(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) async {
        if state == .inactive {
            await startSession(engine: engine, recorderUIManager: recorderUIManager)
        } else {
            await endSession(reason: .userToggle)
        }
    }
    // ... rest defined below
}
```

- [ ] **Step 3.2 — `startSession`**

```swift
private func startSession(engine: VoiceInkEngine, recorderUIManager: RecorderUIManager) async {
    self.engine = engine
    self.recorderUIManager = recorderUIManager
    self.mode = .current()
    self.silenceDetector.configure(thresholdDb: mode.vadThresholdDb,
                                   silenceDuration: mode.silenceDuration)
    self.silenceDetector.reset()

    state = .listening
    logger.notice("🦾 hands-free: state=listening (start)")

    // Start recorder via the existing user-initiated path (shows the panel).
    await recorderUIManager.toggleMiniRecorder()

    // Subscribe to audio meter for silence detection.
    meterCancellable = engine.recorder.$audioMeter
        .receive(on: DispatchQueue.main)
        .sink { [weak self] meter in
            guard let self = self else { return }
            self.handleMeterSample(meter)
        }

    // 20-min cap.
    capTimerTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(20.0 * 60.0 * 1_000_000_000))
        guard !Task.isCancelled, let self = self else { return }
        await MainActor.run {
            Task { await self.endSession(reason: .sessionCap) }
        }
    }
}
```

- [ ] **Step 3.3 — `handleMeterSample` + commit transition**

```swift
private func handleMeterSample(_ meter: AudioMeter) {
    guard state == .listening else { return }
    if let event = silenceDetector.update(meter: meter, now: Date()),
       event == .silenceDetected {
        Task { await commitCurrentUtterance() }
    }
}

private func commitCurrentUtterance() async {
    guard state == .listening, let engine = engine else { return }
    state = .committing
    logger.notice("🦾 hands-free: state=committing")

    commitTask = Task { [weak self] in
        guard let self = self, let engine = self.engine else { return }
        await engine.commitUtterance()
        // commitUtterance returns AFTER the new recorder is armed.
        guard !Task.isCancelled, self.state == .committing else { return }
        self.silenceDetector.reset()
        self.state = .listening
        self.logger.notice("🦾 hands-free: state=listening (post-commit)")
    }
    await commitTask?.value
}
```

- [ ] **Step 3.4 — `endSession`**

```swift
func endSession(reason: EndReason) async {
    guard state != .inactive else { return }
    state = .endingSession
    logger.notice("🦾 hands-free: state=endingSession reason=\(reason.rawValue, privacy: .public)")

    capTimerTask?.cancel(); capTimerTask = nil
    commitTask?.cancel(); commitTask = nil
    meterCancellable?.cancel(); meterCancellable = nil

    // Drain in-flight: if recorder is currently recording, fire one final
    // commit so the user's last utterance isn't dropped. If pipeline is
    // already running, let it finish (no extra commit).
    if let engine = engine, engine.recordingState == .recording {
        await engine.commitUtterance(restartAfter: false)
    }

    // Dismiss the recorder panel via the existing tail.
    await recorderUIManager?.dismissMiniRecorder()

    state = .inactive
    silenceDetector.reset()
    logger.notice("🦾 hands-free: state=inactive")

    if reason == .sessionCap {
        await MainActor.run {
            NotificationManager.shared.showNotification(
                title: "Hands-free session ended (20-min cap)",
                type: .info
            )
        }
    }
}
```

- [ ] **Step 3.5 — Verify**

```bash
grep -rn "HandsFreeSessionService\.shared\|HandsFreeSessionService(" VoiceInk --include="*.swift"
```

Expected: definition in this new file; call sites in `HotkeyManager.swift` (T2) and `TranscriptionPipeline.swift` (T6) and `MenuBarIconRenderer.swift` (T7) once those tasks land.

**Risk:** HIGH — load-bearing wall of W12.D. Coordinates async lifecycle (recorder cycling, Combine subscription, cap timer, commit task) without leaking. Cancellation semantics in `endSession` MUST cleanly tear down all four state holders even if `endSession` is re-entered (e.g. user mashes the toggle).

**Verification:** type-check passes. Manual trace: toggle on, dictate one utterance, toggle off — confirm the recorder panel dismisses, no orphan tasks, menubar icon returns to idle.

---

### Task 4 — Implement `SilenceDetector`

**Files:**
- Create: `VoiceInk/HandsFree/SilenceDetector.swift`

- [ ] **Step 4.1 — Write the detector**

```swift
import Foundation

/// W12.D silence-detection helper. Pure state machine; no Combine, no
/// concurrency primitives. Owned by `HandsFreeSessionService`; called from
/// the main actor exclusively. See plan
/// `docs/superpowers/plans/W12D-hands-free-vad.md` §Migration policy #6.
final class SilenceDetector {
    enum SilenceEvent: Equatable {
        case silenceDetected
    }

    private var thresholdDb: Float = -40.0
    private var silenceDuration: TimeInterval = 1.5

    private var lastVoiceTimestamp: Date?
    private var hasSpokenInUtterance: Bool = false
    private var didEmitSilence: Bool = false

    func configure(thresholdDb: Float, silenceDuration: TimeInterval) {
        self.thresholdDb = thresholdDb
        self.silenceDuration = silenceDuration
    }

    func reset() {
        lastVoiceTimestamp = nil
        hasSpokenInUtterance = false
        didEmitSilence = false
    }

    /// Called once per audio meter sample (~17ms cadence from `Recorder`).
    /// Returns `.silenceDetected` exactly once per utterance boundary; returns
    /// `nil` for all subsequent samples until `reset()` is called.
    func update(meter: AudioMeter, now: Date) -> SilenceEvent? {
        guard !didEmitSilence else { return nil }

        // `Recorder` exposes audioMeter values in [0, 1] (normalized from dB).
        // Convert back to dBFS for threshold comparison.
        let avgPower = Float(meter.averagePower)  // [0, 1]
        let dB: Float = avgPower > 0
            ? 20.0 * log10f(avgPower)
            : -160.0

        if dB >= thresholdDb {
            // Voice present.
            lastVoiceTimestamp = now
            hasSpokenInUtterance = true
            return nil
        }

        // Silence sample — only meaningful if we've heard voice already.
        guard hasSpokenInUtterance, let last = lastVoiceTimestamp else { return nil }
        let silenceElapsed = now.timeIntervalSince(last)
        if silenceElapsed >= silenceDuration {
            didEmitSilence = true
            return .silenceDetected
        }
        return nil
    }
}
```

**Note on threshold semantics:** `Recorder.audioMeter.averagePower` is normalized to `[0, 1]` via `(power - minVisibleDb) / (maxVisibleDb - minVisibleDb)` where `minVisibleDb = -60` and `maxVisibleDb = 0`. The detector inverts that to dBFS. Coder confirms the math against `Recorder.swift:208-219` before committing — if the normalization changes there, this detector breaks silently.

- [ ] **Step 4.2 — Verify**

```bash
grep -rn "SilenceDetector" VoiceInk --include="*.swift"
```

Expected: definition + the `HandsFreeSessionService.silenceDetector` property.

**Risk:** MED — math against an internally-normalized value. The dB inversion must match `Recorder`'s normalization formula; a mismatch makes the threshold meaningless without a build error.

**Verification:** type-check passes. Manual sanity (no test file): instantiate, feed 10 samples at avgPower=0.0 (silence) + 10 at avgPower=0.5 (~−6 dB) + 10 more at 0.0 with timestamps 100ms apart — confirm `silenceDetected` fires only after the silence-duration elapses post-voice.

---

### Task 5 — Implement utterance-commit flow

**Files:**
- Modify: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`

- [ ] **Step 5.1 — Add `commitUtterance(restartAfter:)`**

After the existing `toggleRecord(powerModeId:)` method (around `:251`), add:

```swift
/// W12.D hands-free commit: stop the current recording, run the pipeline
/// for the captured utterance, then optionally start a new recording so
/// the next utterance can begin immediately. Each utterance is its own
/// `Transcription` row (matches existing schema).
///
/// - Parameter restartAfter: true (hands-free in progress) → re-arm the
///   recorder for the next utterance. false (session ending or one-shot
///   drain) → leave the recorder stopped.
func commitUtterance(restartAfter: Bool = true) async {
    guard recordingState == .recording else { return }
    logger.notice("🦾 hands-free: commitUtterance restartAfter=\(restartAfter, privacy: .public)")

    // Reuse the existing stop+pipeline path from toggleRecord by calling
    // it directly. After it returns (state is back to .idle), restart.
    await toggleRecord()

    if restartAfter {
        // Wait for recordingState to settle to .idle before restarting,
        // otherwise the recorder UI may still be tearing down. The pipeline
        // sets state to .idle at runPipeline tail (`:292-294`).
        var spins = 0
        while recordingState != .idle, spins < 100 {
            try? await Task.sleep(nanoseconds: 20_000_000)  // 20ms
            spins += 1
        }
        guard recordingState == .idle else {
            logger.error("🦾 hands-free: commitUtterance abort — recordingState=\(String(describing: self.recordingState), privacy: .public) after pipeline")
            return
        }
        // Re-arm. Reuse the same powerModeId implicitly (the existing
        // `toggleRecord` reads PowerMode state at recording start).
        await toggleRecord()
    }
}
```

**Important — recorder UI lifecycle:** `toggleRecord` sets `recordingState = .recording` on start and `.idle` on pipeline tail. The `RecorderUIManager.toggleMiniRecorder` showing the panel is owned by the calling site (in T3, `HandsFreeSessionService.startSession` calls `recorderUIManager.toggleMiniRecorder()` once at session start; the panel stays visible across utterance commits because `commitUtterance` calls `toggleRecord` directly, NOT `recorderUIManager.toggleMiniRecorder`). On `restartAfter=true`, the second `toggleRecord` call enters the start-recording branch since state is `.idle`, which re-attaches the recorder + audio capture but does NOT toggle the panel visibility (the panel was already shown). Coder confirms this assumption holds against `RecorderUIManager.toggleMiniRecorder:120-139` — the panel is only hidden via `dismissMiniRecorder` (called from `HandsFreeSessionService.endSession` in T3.4, NOT from this commit path).

- [ ] **Step 5.2 — Verify**

```bash
grep -rn "commitUtterance" VoiceInk --include="*.swift"
```

Expected: definition here + call sites in `HandsFreeSessionService.swift` (T3.3 + T3.4).

**Risk:** MED — the engine state-machine assumption (recordingState transitions through `.recording → .transcribing → .enhancing → .idle` via the existing pipeline) must hold. If a future packet adds intermediate states or makes the transition non-deterministic, the spin-wait at `:5.1` becomes a hazard.

**Verification:** type-check passes. Manual: invoke from a test harness or via the hands-free hotkey (post-T2/T3) — confirm the recorder panel stays visible across commits, audio meter resumes within ~300ms after each commit, and each utterance creates its own History row.

---

### Task 6 — Voice-trigger filter + paste integration

**Files:**
- Create: `VoiceInk/HandsFree/VoiceTriggerFilter.swift`
- Modify: `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`

- [ ] **Step 6.1 — Write the filter**

```swift
import Foundation

/// W12.D voice-trigger detection. Suffix-match policy: lowercase the last
/// `maxTriggerWords` words (cap 5), strip trailing punctuation, exact-suffix
/// against the configured trigger list. On match: return cleaned text + the
/// AutoSendKey to fire after paste. See plan
/// `docs/superpowers/plans/W12D-hands-free-vad.md` §Migration policy #7.
enum VoiceTriggerFilter {
    struct TriggerHit: Equatable {
        let cleanedText: String
        let autoSend: AutoSendKey
        let matchedPhrase: String
    }

    static let maxTriggerWords = 5

    static func detectTrigger(in text: String, against phrases: [String]) -> TriggerHit? {
        guard !phrases.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Strip trailing punctuation (.,!?;:) for comparison.
        let trailingPunct = CharacterSet(charactersIn: ".,!?;:\"'`)]}")
        let stripped = trimmed.trimmingTrailingCharactersInSet(trailingPunct)
        let strippedLower = stripped.lowercased()

        for phrase in phrases.map({ $0.lowercased() }) {
            guard !phrase.isEmpty else { continue }
            // Suffix-match: the phrase must end the text AND be preceded by
            // a word boundary (start of string OR whitespace) to prevent
            // "transcend it" matching "send it".
            if strippedLower.hasSuffix(phrase) {
                let cutoff = strippedLower.count - phrase.count
                let isAtStart = cutoff == 0
                let beforeIndex = strippedLower.index(strippedLower.startIndex,
                                                      offsetBy: cutoff)
                let priorChar = isAtStart ? Character(" ") : strippedLower[strippedLower.index(before: beforeIndex)]
                guard isAtStart || priorChar.isWhitespace else { continue }

                // Strip the trigger from the original (case-preserving) text.
                // Use the trimmed length, not the lowercased length, because
                // `strippedLower.count` matches `stripped.count` (lowercase
                // doesn't change ASCII length, and we operate on the latin-1
                // subset for the default phrases).
                let strippedCutoff = stripped.index(stripped.startIndex, offsetBy: cutoff)
                var cleaned = String(stripped[..<strippedCutoff])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                // Restore a single trailing period if the original ended with
                // sentence-ending punctuation — the trigger may have absorbed
                // the period.
                if let lastChar = trimmed.last, ".!?".contains(lastChar) {
                    if !cleaned.isEmpty, ".!?".contains(cleaned.last!) == false {
                        cleaned += "."
                    }
                }
                return TriggerHit(cleanedText: cleaned,
                                  autoSend: .enter,
                                  matchedPhrase: phrase)
            }
        }
        return nil
    }
}

private extension String {
    func trimmingTrailingCharactersInSet(_ set: CharacterSet) -> String {
        var s = self
        while let last = s.unicodeScalars.last, set.contains(last) {
            s.removeLast()
        }
        return s
    }
}
```

- [ ] **Step 6.2 — Inject into the paste step**

In `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` around `:191-214`, replace the existing paste block:

```swift
if let textToPaste = finalPastedText,
   transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {

    // W12.D: hands-free voice-trigger detection. Runs only when a hands-free
    // session is active; returns nil otherwise (no-op for normal recordings).
    let isHandsFreeActive = HandsFreeSessionService.shared.state != .inactive
    let triggerHit: VoiceTriggerFilter.TriggerHit? = isHandsFreeActive
        ? VoiceTriggerFilter.detectTrigger(
            in: textToPaste,
            against: HandsFreeSessionService.shared.mode.triggerPhrases
          )
        : nil
    let pasteText = triggerHit?.cleanedText ?? textToPaste

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
        if didEnhance {
            SoundManager.shared.playEnhanceComplete()
        } else if !didFireTranscribeCue {
            SoundManager.shared.playTranscribeComplete()
        }
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        CursorPaster.pasteAtCursor(pasteText + (appendSpace ? " " : ""))

        let powerMode = PowerModeManager.shared
        // W12.D: voice trigger overrides PowerMode autoSend (Migration policy #8).
        if let hit = triggerHit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                CursorPaster.performAutoSend(hit.autoSend)
            }
        } else if let activeConfig = powerMode.currentActiveConfiguration,
                  activeConfig.autoSendKey.isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                CursorPaster.performAutoSend(activeConfig.autoSendKey)
            }
        }
    }
}
```

- [ ] **Step 6.3 — Verify**

```bash
grep -rn "VoiceTriggerFilter\|detectTrigger" VoiceInk --include="*.swift"
```

Expected: definition + the call site in `TranscriptionPipeline.swift`.

**Risk:** LOW — string utility + a guarded paste branch. The risk is misinterpreting the user's intent (e.g. "transcend it" matching "send it") — Migration policy #7 + Step 6.1's word-boundary check mitigate.

**Verification:** type-check passes. Manual:
- Hands-free OFF: dictate "press enter" → confirm filter does NOT fire (text is pasted as-is, no autoSend).
- Hands-free ON: dictate "tell him press enter" → text "Tell him." pasted, Enter fires after 500ms.
- Hands-free ON: dictate "transcend it" → text "Transcend it." pasted, NO Enter (word-boundary check rejects).
- Hands-free ON: dictate "press enter" with PowerMode that has `autoSendKey = .enter` → confirm Enter fires only ONCE (the trigger path; PowerMode autoSend is suppressed).

---

### Task 7 — Menubar `.handsFree` indicator

**Files:**
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift`

- [ ] **Step 7.1 — Extend `IconState` with `.handsFree`**

```swift
enum IconState: Equatable {
    case idle
    case recording
    case transcribing
    case enhancing
    case handsFree  // W12.D

    init(_ state: RecordingState) {
        switch state {
        case .recording:    self = .recording
        case .transcribing: self = .transcribing
        case .enhancing:    self = .enhancing
        default:            self = .idle
        }
    }

    /// W12.D: hands-free overrides the inner recording state — when active,
    /// the user wants to see "I'm in hands-free" regardless of whether the
    /// recorder is currently capturing or committing.
    init(handsFree: HandsFreeSessionState, recordingState: RecordingState) {
        if handsFree != .inactive {
            self = .handsFree
        } else {
            self.init(recordingState)
        }
    }
}
```

- [ ] **Step 7.2 — Add `.handsFree` glyph in `image(for:)`**

```swift
static func image(for state: IconState) -> NSImage {
    switch state {
    case .idle:
        return template("waveform", weight: .light, label: "VoiceInk idle")
    case .recording:
        return tinted("waveform", weight: .semibold,
                      color: NSColor(Palette.accent), label: "VoiceInk recording")
    case .transcribing:
        return template("waveform", weight: .regular, label: "VoiceInk transcribing")
    case .enhancing:
        return template("sparkles", weight: .regular, label: "VoiceInk enhancing")
    case .handsFree:  // W12.D
        return tinted("ear.fill", weight: .semibold,
                      color: NSColor(Palette.accent), label: "VoiceInk hands-free")
    }
}
```

Update `failedAccessibilityLabel(for:count:)` similarly with a `.handsFree` case ("VoiceInk hands-free, \(suffix)").

- [ ] **Step 7.3 — Update `RecordingStateObserver` to subscribe to hands-free state**

```swift
final class RecordingStateObserver: ObservableObject {
    @Published private(set) var iconState: MenuBarIconRenderer.IconState = .idle
    @Published private(set) var unresolvedFailures: Int = 0

    private var stateCancellable: AnyCancellable?
    private var handsFreeCancellable: AnyCancellable?
    private var registryCancellable: AnyCancellable?

    @MainActor
    func bind(to engine: VoiceInkEngine) {
        stateCancellable?.cancel()
        handsFreeCancellable?.cancel()

        let combined = Publishers.CombineLatest(
            engine.$recordingState,
            HandsFreeSessionService.shared.$state
        )
        .receive(on: DispatchQueue.main)
        .map { recordingState, handsFreeState in
            MenuBarIconRenderer.IconState(handsFree: handsFreeState,
                                          recordingState: recordingState)
        }
        .removeDuplicates()

        stateCancellable = combined.sink { [weak self] next in
            self?.iconState = next
        }
    }
    // ... bind(toRegistry:) unchanged ...
}
```

- [ ] **Step 7.4 — Update preview harness with the new case**

```swift
Picker("", selection: $state) {
    Text("Idle").tag(MenuBarIconRenderer.IconState.idle)
    Text("Recording").tag(MenuBarIconRenderer.IconState.recording)
    Text("Transcribing").tag(MenuBarIconRenderer.IconState.transcribing)
    Text("Enhancing").tag(MenuBarIconRenderer.IconState.enhancing)
    Text("Hands-free").tag(MenuBarIconRenderer.IconState.handsFree)  // W12.D
}
```

- [ ] **Step 7.5 — Verify**

```bash
grep -n "case handsFree\|case .handsFree\|HandsFreeSessionService" VoiceInk/Views/Common/MenuBarIconRenderer.swift
```

Expected: 5+ matches across IconState, image(for:), accessibility label, RecordingStateObserver, preview harness.

**Risk:** LOW — additive enum case + a Combine merge. The Publishers.CombineLatest emits on every change to either side, which is exactly what we want.

**Verification:** type-check passes. Manual: toggle hands-free via the hotkey → confirm menubar glyph swaps to ear.fill tinted accent within one frame; toggle off → confirm fall-back to existing waveform.

---

### Task 8 — Hands-free Settings UI

**Files:**
- Create: `VoiceInk/Views/Settings/HandsFreeSettingsView.swift`
- Modify: `VoiceInk/Views/Settings/SettingsView.swift`

- [ ] **Step 8.1 — Write `HandsFreeSettingsView`**

Match the W12.A `EnhancementSettingsView` shape (Form / Section / GlassCard / SettingsCard depending on what the existing settings nav uses post-W13.D — coder picks the matching idiom). Sections:

1. **Activation** — `KeyboardShortcuts.Recorder(for: .handsFreeToggle)` + inline help text "Press once to start. Press again to stop. Sessions auto-end at 20 minutes."

2. **VAD threshold** — segmented Picker bound to a `@State threshold: Float`:
   - Low (-50 dBFS) — "Picks up quiet speech; may segment on long pauses."
   - Medium (-40 dBFS) — "Balanced. Default."
   - High (-30 dBFS) — "Only loud speech; avoids background hum but cuts soft talk."
   Below the picker, a disclosure "Advanced" with a `Slider` from -60 to -20 dBFS for power users who want a precise value. `onChange` writes `UserDefaults.standard.set(value, forKey: "HandsFreeVADThresholdDb")`.

3. **Silence duration** — segmented Picker bound to `@State silenceMs: Int`:
   - Quick (1000 ms) — "Snappy; segments on 1-second pauses."
   - Standard (1500 ms) — "Balanced. Default."
   - Patient (2500 ms) — "Tolerates longer thinking pauses."
   `onChange` writes to `"HandsFreeSilenceDurationMs"`.

4. **Voice triggers** — list of trigger phrases:
   ```swift
   ForEach(triggerPhrases.indices, id: \.self) { i in
       HStack {
           TextField("Trigger phrase", text: $triggerPhrases[i])
           Button(role: .destructive) { triggerPhrases.remove(at: i) } label: {
               Image(systemName: "trash")
           }
       }
   }
   Button("Add trigger") { triggerPhrases.append("") }
   ```
   On any change to the array, persist via `HandsFreeMode.saveTriggerPhrases(triggerPhrases)`. Footer: "Detected at the END of an utterance; mid-utterance occurrences are ignored. Each match strips the phrase from your text and presses Enter."

5. **Session cap** — read-only label: "Sessions auto-stop at 20 minutes." with a small caption: "20 minutes matches Wispr's hands-free cap. Configurable in a future release."

- [ ] **Step 8.2 — Add nav entry in `SettingsView`**

In `VoiceInk/Views/Settings/SettingsView.swift`, add a row pointing to `HandsFreeSettingsView()`. Match the existing nav idiom (sidebar item, NavigationLink, or list row depending on the existing pattern). Place it under "Recorder" or "Enhancement" (coder picks).

- [ ] **Step 8.3 — Verify**

```bash
grep -rn "HandsFreeSettingsView" VoiceInk --include="*.swift"
```

Expected: definition + nav entry in `SettingsView.swift`.

**Risk:** LOW — straightforward settings UI. Visual fidelity to the W13 aesthetic is post-W13.D — for now match whatever idiom the surrounding settings views use (Form / Section if pre-W13.D-purge, SettingsCard if post). DO NOT pre-purge — that's W13.D's territory.

**Verification:** type-check passes. Manual: open the new settings page, change each control, confirm UserDefaults persist (quit + relaunch + observe).

---

### Task 9 — Cancellation + cleanup hardening

**Files:**
- Modify: `VoiceInk/HandsFree/HandsFreeSessionService.swift`

- [ ] **Step 9.1 — Tighten `endSession` re-entrancy**

Wrap `endSession` body in a guard that early-returns if `state == .endingSession` already:

```swift
func endSession(reason: EndReason) async {
    guard state != .inactive, state != .endingSession else { return }
    state = .endingSession
    // ... body unchanged from T3.4
}
```

- [ ] **Step 9.2 — Confirm cap-timer task cancels cleanly**

The cap-timer task in `startSession` is `@Sendable` and stored on `capTimerTask`. `endSession` calls `capTimerTask?.cancel()`. **Confirm:** the inner `try? await Task.sleep` honors cancellation — yes, `Task.sleep` is documented to throw `CancellationError` on cancellation. The `try?` swallows the error, and the `guard !Task.isCancelled` post-sleep prevents firing the `.sessionCap` end after a manual end. Trace verified in plan; coder confirms by reading the implementation.

- [ ] **Step 9.3 — Confirm meter subscription cancels cleanly**

`meterCancellable?.cancel()` in `endSession` tears down the Combine sink. After cancel, no more `handleMeterSample` calls fire. `silenceDetector.reset()` is called as belt-and-suspenders so a subsequent session starts fresh.

- [ ] **Step 9.4 — Confirm engine state is consistent on session end**

If the session ends while `state == .committing` (a commit is in flight), `commitTask?.cancel()` interrupts the spin-wait in `VoiceInkEngine.commitUtterance` — but `toggleRecord` may already have started the pipeline. The pipeline does NOT honor task cancellation mid-run (it has its own `shouldCancel` closure that tracks `engine.shouldCancelRecording`). **Decision:** let the in-flight pipeline complete — paste fires for the last utterance even after the user toggled off. This is correct UX (the user said something; they want it pasted). Then `dismissMiniRecorder` runs in `endSession`'s tail.

If the session ends while `state == .listening` (no commit in flight, recorder is idle-listening), `endSession`'s drain branch (`engine.recordingState == .recording`) fires one final commit with `restartAfter: false` — flushes the user's last utterance. `dismissMiniRecorder` then runs.

- [ ] **Step 9.5 — Confirm app quit / sleep behavior**

If the user quits the app or the system sleeps mid-hands-free, the OS tears down the recorder process. `HandsFreeSessionService.shared` doesn't need explicit handlers — singletons die with the process. But if the system wakes from sleep mid-session, the recorder may be in a stale state. **Decision:** add a `NSWorkspace.willSleepNotification` observer in `HandsFreeSessionService.startSession` that calls `endSession(reason: .pipelineFailure)`. Mirrors the existing `NSWorkspace.didWakeNotification` prewarm hook from W11.A1.

```swift
NotificationCenter.default.addObserver(
    forName: NSWorkspace.willSleepNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    Task { @MainActor in
        await self?.endSession(reason: .pipelineFailure)
    }
}
```

Tear down the observer in `endSession`.

- [ ] **Step 9.6 — Verify**

```bash
grep -n "endSession\|willSleepNotification" VoiceInk/HandsFree/HandsFreeSessionService.swift
```

Expected: re-entrancy guard + sleep observer + observer teardown.

**Risk:** MED — async cleanup is the load-bearing wall. A stuck session (icon stuck on hands-free, hotkey unresponsive) is the worst-case failure mode.

**Verification:** type-check passes. Manual:
- Toggle on → toggle off rapidly 3 times → confirm icon stops at idle, no orphan tasks (check Console log for absence of `🦾 hands-free` after the third toggle).
- Toggle on → close laptop lid → re-open → confirm icon is back at idle (not stuck on hands-free).
- Toggle on → quit app via menubar → re-launch → confirm icon starts at idle.

---

### Task 10 — Static checks (coder-runnable, no build)

**Files:** none (read-only verification).

- [ ] **Step 10.1 — All touched files compile in isolation via SourceKit**

The coder's environment runs SourceKit live. Verify:
- No undefined-symbol errors after each task.
- New `VoiceInk/HandsFree/*.swift` files import `Foundation` (and `Combine` where used).
- No circular imports — `HandsFreeSessionService` references `VoiceInkEngine` weakly; `MenuBarIconRenderer` references `HandsFreeSessionService` directly (no cycle).

- [ ] **Step 10.2 — No orphan references to old constants**

```bash
grep -rn "isHandsFreeMode\|isShortcutHandsFreeMode" VoiceInk --include="*.swift"
```

Expected: matches in `HotkeyManager.swift` only — these are PRE-EXISTING flags in the modifier-key state machine (`processKeyPress`) tracking a single key-up after a toggle hotkey. They are NAMING-COINCIDENT with W12.D's hands-free but represent different concepts (the existing flag is "did the user toggle by tapping and releasing without holding"). **The W12.D implementation does NOT touch these flags.** Coder confirms the existing flags still compile + work.

- [ ] **Step 10.3 — Confirm `HandsFreeSessionService` is referenced everywhere it should be**

```bash
grep -rn "HandsFreeSessionService" VoiceInk --include="*.swift"
```

Expected: matches in
- `VoiceInk/HandsFree/HandsFreeSessionService.swift` (definition)
- `VoiceInk/HotkeyManager.swift` (T2 — onKeyUp + collision policy)
- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` (T6 — voice-trigger gate)
- `VoiceInk/Views/Common/MenuBarIconRenderer.swift` (T7 — Combine subscription)
- `VoiceInk/Views/Settings/HandsFreeSettingsView.swift` (T8 — settings page reads + writes via `HandsFreeMode.current()` / `.saveTriggerPhrases`)

≥5 distinct files.

- [ ] **Step 10.4 — Confirm `commitUtterance` is wired**

```bash
grep -rn "commitUtterance" VoiceInk --include="*.swift"
```

Expected: matches in `VoiceInkEngine.swift` (definition) AND `HandsFreeSessionService.swift` (call sites in T3.3 + T3.4).

- [ ] **Step 10.5 — Confirm no recorder behavior regression outside hands-free**

```bash
grep -rn "HandsFreeSessionService.shared.state" VoiceInk --include="*.swift"
```

Expected: every read is gated by `!= .inactive` or `== .inactive` — i.e. the new code paths short-circuit when hands-free is OFF. A read that doesn't have such a gate is a regression risk (it means existing behavior depends on hands-free state, which violates Migration policy #2).

- [ ] **Step 10.6 — Confirm KeyboardShortcuts.Name registration**

```bash
grep -n "handsFreeToggle" VoiceInk --include="*.swift" -r
```

Expected: matches in `HotkeyManager.swift` (KeyboardShortcuts.Name extension + onKeyUp handler), `HandsFreeSettingsView.swift` (KeyboardShortcuts.Recorder binding).

---

### Task 11 — Integration build + post-merge verification

**Files:** none (verification + report).

- [ ] **Step 11.1 — Single integration build**

```bash
make local
```

Expected: clean build. If it fails:
- Most likely: `Publishers.CombineLatest` map signature mismatch in `RecordingStateObserver.bind(to:)` — confirm the closure param order matches `(RecordingState, HandsFreeSessionState)`.
- Second-most-likely: `IconState`'s new initializer collides with the existing `init(_ state: RecordingState)` due to argument label ambiguity — confirm Swift can disambiguate `init(_:)` vs `init(handsFree:recordingState:)` (it should).
- Third-most-likely: `HandsFreeSessionService.shared` is `@MainActor`-isolated and called from a non-isolated context (the audio thread). Confirm all access goes through `Task { @MainActor in ... }` or an explicit `await` from a main-actor caller.
- Fourth-most-likely: `KeyboardShortcuts.Recorder` doesn't exist in the in-tree version of the lib. Confirm the API name against existing usage in `EnhancementShortcutsView.swift` or wherever `KeyboardShortcuts.Name` is bound to UI today.

Per CLAUDE.md cadence, this is the only build run during the packet.

- [ ] **Step 11.2 — Coder smoke pass (manual)**

Coder bind `handsFreeToggle` to a free shortcut (e.g. ⌥⌘H) in the new settings page. Smoke checklist:

1. Hit the hotkey → recorder panel appears, audio meter active, menubar icon swaps to ear.fill tinted accent.
2. Speak "this is the first sentence" → pause 2 seconds → confirm utterance commits, paste fires, recorder re-arms within ~300ms.
3. Speak "this is the second sentence press enter" → pause 2 seconds → confirm: text "This is the second sentence." pastes, then Enter fires after 500ms (visible by a newline in the target field if it's a multi-line editor, OR a Send action if focused on a chat input). Console shows `🦾 hands-free: state=committing` then `state=listening (post-commit)`.
4. Hit the hotkey again → menubar returns to idle, recorder panel dismisses.
5. Hit the hotkey, immediately speak a 30-second utterance with multiple internal pauses (~700ms each) → confirm only ONE utterance commits at the END (pauses < silence-duration don't trigger).
6. Hit the hotkey, speak nothing for 25 minutes (or temporarily lower the cap to 30s for the smoke; revert before commit) → confirm session auto-stops with notification "Hands-free session ended (20-min cap)".
7. Hit the hotkey, then immediately hit the normal toggleMiniRecorder hotkey → confirm hands-free ends + the normal recorder does NOT start (per Migration policy #3).

- [ ] **Step 11.3 — User-side post-merge verification protocol**

After the code commit lands, the user runs the qualitative verification (8-step protocol below in §Post-merge verification protocol).

- [ ] **Step 11.4 — Coder report to lead**

Send the lead:
- Confirmation of all 9 tasks completed (or which deferred per §Risks).
- Build status.
- Smoke-checklist Console log (showing `🦾 hands-free: state=…` transitions across an end-to-end session with one commit + voice trigger + auto-end).
- `HandsFreeSettingsView` screenshot (optional).
- Any architectural surprises (especially around recorder lifecycle, audio gap timing, or trigger-filter false positives).

The lead handles the two commits + push + final handoff doc.

---

## Test plan

Per master plan §0 Q10 (test-infra deferred): no `xcodebuild test` runs. Validation is build-only via `make local` (Task 11.1) plus smoke session (Task 11.2) plus user-side post-merge verification (Task 11.3).

**What `xcodebuild build` runs:**
- Single `make local` invocation at Task 11.1. ~3 min cold; warm rebuilds are seconds.

**What the user/coder does for smoke:**
- Coder smoke (Task 11.2): the 7-point checklist above.
- User verification (Task 11.3): the 8-step qualitative protocol below.

If any of those expected behaviors don't materialize, the failing task is the candidate for a focused follow-up packet — see §Rollback plan.

---

## Rollback plan

**Single-commit packet → `git revert <code commit sha>` restores the entire pre-W12.D behavior.** Plan doc commit stays (not reverted) so the historical record is preserved.

**Why squashed-not-split:**
- T2 + T3 + T5 are tightly coupled (hotkey → service → engine commit path).
- T6 + T7 share the `HandsFreeSessionService.shared.state` read.
- T8 + T1 share the `HandsFreeMode` AppStorage shape.
- A per-task commit matrix would create a brittle revert (e.g., reverting T3 alone would leave T2's hotkey handler crashing on a missing service).

**Per-feature surgical revert** (if a single feature turns out worse):
- **VAD over/under-triggers:** force `SilenceDetector.update` to always return `nil`. Effectively makes hands-free a never-committing single-recorder session. Toggle still works; only commits don't auto-fire. Workaround: user manually toggles off to commit their utterance.
- **Voice-trigger false positives:** comment out the `triggerHit` block in `TranscriptionPipeline` (T6). Voice triggers stop working; PowerMode autoSend resumes its existing role.
- **Menubar indicator regress:** revert the `IconState.handsFree` case + the Combine merge in `RecordingStateObserver`. Menubar reverts to the existing 4-state mapping; hands-free runs invisibly.
- **20-min cap unwanted:** in `startSession`, comment out the `capTimerTask` setup. Sessions run indefinitely until the user toggles off.

**Detection signals** (which production data tells us a revert is needed):
- User reports utterances commit too early / too late → tune VAD threshold + silence duration. NOT a revert; tune via settings.
- User reports voice trigger fires when they didn't intend → tune trigger phrase list (remove "submit" if it false-positives, e.g.). NOT a revert.
- User reports menubar icon stuck on hands-free after session end → check `endSession`'s teardown order; revert T7's Combine merge and use a simpler `engine.$recordingState`-only path while debugging.
- Session-end races leave a stuck recorder panel → revert T9's re-entrancy guard tightening; investigate `dismissMiniRecorder` timing.
- App crashes on hands-free toggle → revert the entire packet, file a bug, re-plan.

**Blast radius of a full revert:** zero data loss. All edits are in-memory state + AppStorage keys. The `HandsFree*` keys would persist after revert but read code paths are gone — harmless dead state. Each captured utterance during a hands-free session was already saved to a `Transcription` row via the existing pipeline (no schema change), so user dictations from pre-revert sessions remain in History.

---

## Risks / unknowns

1. **VAD threshold tuning is mic-dependent.** The default −40 dBFS / 1500ms may cut off speakers with quiet voices or stretch through long pauses for fast speakers. **Mitigation:** ship with the segmented Low/Medium/High picker (T8) so the user can iterate without typing dB values. Open Question #2 documents the alternative (silero streaming) for a follow-up.

2. **RMS gating doesn't distinguish voice from noise.** A noisy environment (HVAC, keyboard, music) sustains audio above threshold and prevents silence detection. v1 punts — the user is responsible for a quiet-enough environment. **Mitigation:** if user reports "session never commits in cafés", swap RMS for silero streaming in a follow-up packet (~150 LOC + a refactor of `VADModelManager` to stream rather than batch).

3. **Stop+start audio between utterances drops 150-300ms of voice.** If the user starts the next sentence within ~300ms of the previous one ending (no real silence — just a hard transition), the first words may be missed. **Mitigation:** silence-duration default 1.5s gives the audio hardware time to spin up. If user reports gaps, follow-up adds `Recorder.rotateOutputFile(toURL:)` keeping AUHAL alive. Migration policy #5 acknowledges this.

4. **Voice trigger false positives.** "Send me the file" doesn't end with "send it" so it's safe; but "let's send it tomorrow" DOES end with "send it" — and would fire Enter unintentionally. **Mitigation:** the user can edit the trigger list (T8). Default phrases were chosen to be unlikely sentence-end content ("submit" is the riskiest; "press enter" is nearly always intentional). If false positives are common, follow-up could require an explicit trigger word like "command:" or punctuation cue.

5. **Voice trigger false negatives.** Whisper / AFM may transcribe "press enter" as "Press Enter" (literally with capital E). The lowercasing in `VoiceTriggerFilter` handles caps; but if the model hallucinates a comma between "press" and "enter" ("press, enter"), the suffix doesn't match. **Mitigation:** acceptable v1; the trigger phrase list is editable so users can add variants.

6. **Hotkey unbound by default.** New users won't know the feature exists until they go into settings. **Mitigation:** Open Question #1 — auto-bind to Caps+H (Hyper+H) for users with the Hyper layer? Or prompt on first run? Lead picks.

7. **Concurrency hazards with rapid toggling.** User mashes the hotkey → multiple `Task`s spawn → potential races in `state` transitions. **Mitigation:** Migration policy #3 (single-instance, main-actor-confined) + Task 9's re-entrancy guard. The remaining race is "user toggles off DURING a commit" — handled by letting the in-flight commit complete (Task 9.4).

8. **`Recorder.audioMeter` normalization is internal contract.** `SilenceDetector` inverts the [0,1] back to dBFS using hard-coded `-60` / `0` constants. If `Recorder.minVisibleDb` / `maxVisibleDb` change, the threshold becomes meaningless silently. **Mitigation:** comment in `SilenceDetector` cites `Recorder.swift:208-219`; any change in `Recorder` triggers a grep that hits the detector. Long-term: expose `dBFS` directly on `AudioMeter` rather than only normalized [0,1].

9. **Pipeline failures during hands-free are silent.** If transcription fails on utterance N, the existing pipeline path posts a failure to `FailureRegistry` but does NOT abort the session — utterance N+1 should still be captured. **Mitigation:** acceptable v1; the user sees a warning notification per failure. If failures cascade (e.g. enhance-API-down for 5 minutes), the user can toggle off manually.

10. **20-min cap may be too short OR too long.** Master plan §3 W12.D matches Wispr at 20 min. **Mitigation:** Open Question #6. Hard-coded in v1; a future packet could expose a Settings field.

11. **Menubar icon ear.fill availability.** `ear.fill` is an SF Symbol introduced in SF Symbols 2 (macOS 11+). **Confirm:** at deployment target 26.0, comfortably supported. No fallback needed.

12. **No tests.** Per Q10. The `SilenceDetector` and `VoiceTriggerFilter` are pure utilities ideal for unit tests, but test infra is blocked. **Mitigation:** smoke (Task 11.2) + manual tuning (Task 11.3). The detector + filter are small enough that a future test-infra-unblock packet adds tests retroactively without refactor.

13. **Settings UI doesn't follow W13 aesthetic yet.** T8 ships the page on whatever idiom the surrounding settings views use today (Form / Section if pre-W13.D, SettingsCard if post). **Mitigation:** acceptable interim; the W13.D form-host purge will sweep this view alongside `EnhancementSettingsView`.

14. **Hands-free + Command Mode (W12.B) interaction undefined.** If W12.B ships first AND the user has Command Mode active when they toggle hands-free, what happens? **Mitigation:** v1 doesn't probe for an active Command Mode. If both are active simultaneously, the result is undefined — likely Command Mode wins (it owns the recorder). Open Question #5 flags this for the lead.

15. **`engine.commitUtterance` spin-wait.** The 2s ceiling on the spin-wait (100 spins × 20ms) handles the worst-case pipeline tail. If the pipeline takes longer (slow MLX cold load), the re-arm is skipped and the next utterance is missed. **Mitigation:** acceptable v1; the W11.A1 prewarm + W11.B AFM should keep pipeline tails <500ms typical. If user reports drops, raise the ceiling or refactor commitUtterance to use a state-change publisher rather than spin.

---

## Out of scope (explicit) for follow-ups

- **Wake-word activation ("Hey VoiceInk").** Per Migration policy #16. Future P1+ packet; requires always-on capture + wake-word model + privacy review.
- **Per-app hands-free overrides via PowerMode.** Per Migration policy #17. Future packet — `PowerModeConfig` gains `autoEnterHandsFree: Bool`.
- **Live-transcription overlay during hands-free.** Per Migration policy #18. The recorder panel still shows the partial transcript via `engine.partialTranscript`; the missing piece is a multi-utterance preview as the session accumulates. Future polish.
- **Custom session-cap value.** Per Migration policy #19 + Open Question #6. 20-min hard-coded v1.
- **silero streaming VAD.** Per Risk #2. Refactor `VADModelManager` into a streaming detector; swap RMS gating for silero output. Larger packet.
- **`Recorder.rotateOutputFile(toURL:)` for gap-free utterance segmentation.** Per Migration policy #5 + Risk #3. Avoids AUHAL stop+start cost.
- **Hands-free session grouping in History.** Per Migration policy #4. New `HandsFreeSession` parent model wrapping consecutive `Transcription` rows.
- **Per-trigger AutoSendKey mapping.** Currently all triggers fire `.enter`. Future: `["press shift enter": .shiftEnter, ...]`.
- **Mid-utterance voice triggers.** Currently triggers must be at the END of an utterance. Future: detect mid-utterance, split the utterance into "before-trigger" + paste + Enter + "after-trigger".
- **First-run onboarding for hands-free.** Currently the feature is unbound + unannounced. Future: a tooltip in the recorder panel "Try hands-free → ⌘ Settings".
- **Voice-controlled session end** ("stop dictating"). v1 ends only via hotkey or cap. Future: a "session-end" trigger phrase that calls `endSession` instead of paste+autoSend.
- **Hands-free + Scratchpad (W12.E) integration.** When hands-free + Scratchpad is the focused target, what's the UX? Future packet.
- **Test infrastructure unblock.** Per master plan §0 Q10. Separate session.

---

## Open questions for lead

1. **Default hotkey: leave unbound, or auto-bind to Caps+H (Hyper+H)?** Migration policy #1 ships unbound + recommends Hyper+H in the settings page placeholder. **Choice:** (a) leave unbound — predictable, no surprise; (b) auto-bind on first run — discoverable, but may collide with the user's existing Caps+H mapping. Recommend (a) — match the existing VoiceInk pattern (other shortcuts also unbound by default).

2. **VAD strategy: RMS gating (v1) vs silero streaming (refactor).** Risk #2 + Out-of-scope flag silero as a follow-up. **Choice:** confirm RMS for v1 OR demand silero streaming up-front. Recommend RMS — ships fast, lets us validate hotkey + commit + trigger UX before investing in the audio refactor.

3. **Stop+start audio gap (Migration policy #5) acceptable for v1?** ~150-300ms drop between utterances. **Choice:** accept v1 OR demand `Recorder.rotateOutputFile` up-front. Recommend accept — we can add the rotation if user reports gaps.

4. **Voice-trigger suffix-match policy.** Current rule: lowercase last 5 words, strip trailing punctuation, suffix-match against the configured phrase list with word-boundary check. **Choice:** confirm OR tighten (e.g. require an explicit "command:" prefix). Recommend confirm — natural-language triggers are the whole UX point.

5. **Hands-free + Command Mode (W12.B) interaction.** If both are active simultaneously, undefined. **Choice:** (a) hands-free wins, Command Mode disabled while hands-free active; (b) Command Mode wins, can't enter hands-free while Command Mode active; (c) defer to whichever ships first. Recommend (c) — the second-shipping packet decides; flag in that packet's plan.

6. **Session cap: 20-min hard-coded vs configurable.** Master plan §3 W12.D matches Wispr at 20 min. **Choice:** confirm hard-coded for v1 OR demand configurable up-front. Recommend hard-coded — Wispr's 20-min default is well-validated; configurable is a small follow-up.

7. **Trigger phrase defaults.** Currently `["press enter", "submit", "send it", "send message"]`. **Choice:** confirm or trim/expand. Recommend confirm — these match Wispr's documented triggers.

8. **Menubar glyph for hands-free state.** Currently `ear.fill` tinted `Palette.accent`. **Alternatives:** `waveform.badge.mic`, `ear.and.waveform`, `mic.and.signal.meter.fill`. Recommend confirm `ear.fill` — clean + recognizable + doesn't clash with the existing waveform glyph.

9. **Should hands-free force a specific cleanup level?** E.g. force `.light` (W12.A) for hands-free utterances regardless of global setting, since long-form dictation may benefit from minimal cleanup. **Choice:** confirm "use whatever level the user has globally set" OR "force .light during hands-free". Recommend confirm — respect user's existing level; if they want `.light` for hands-free, they can pair hands-free with a PowerMode set to `.light` (post-W12.A).

10. **Pre-merge gate — capture or skip?** The 2-dictation reference set is a soft gate (Pre-merge ground-truth gate above). **Confirm:** does the user run the cadence + trigger-phrase reference capture before code lands, or does the lead defer it to post-merge?

---

## Post-merge verification protocol (USER-SIDE)

1. Open Settings → Hands-free Mode. Bind `handsFreeToggle` to a free shortcut (suggestion: Hyper+H = Caps+H if Karabiner is configured; else ⌥⌘H or similar). Confirm the binding shows a recorded shortcut in the picker.
2. Hit the hotkey. Confirm:
   - Recorder panel appears (mini or notch per the user's existing `RecorderType` setting).
   - Audio meter responds to voice.
   - Menubar glyph swaps to `ear.fill` tinted accent.
3. Speak a 1-sentence utterance with a clear ending pause (~2 seconds of silence). Confirm:
   - Within ~2.5 seconds of finishing, the utterance commits + pastes + the recorder re-arms.
   - Console log shows `🦾 hands-free: state=committing` then `state=listening (post-commit)`.
   - History gains one new Transcription row.
4. Speak a 2nd utterance ending in "press enter" (e.g. "send him a quick hello press enter"). Confirm:
   - Pasted text reads "Send him a quick hello." (trigger stripped).
   - Enter fires ~500ms after paste (visible in a multi-line editor as a newline; in a chat input as a Send action).
5. Speak a 3rd utterance with an internal pause shorter than the silence duration (e.g. 700ms mid-sentence). Confirm:
   - The internal pause does NOT commit.
   - The utterance commits only at the FINAL end-pause.
6. Hit the hotkey again. Confirm:
   - Recorder panel dismisses.
   - Menubar returns to idle waveform.
   - History shows the captured utterances.
7. Toggle hands-free + immediately hit the normal recorder hotkey. Confirm:
   - Hands-free ends.
   - The normal recorder does NOT auto-start (per Migration policy #3).
   - Press the normal hotkey AGAIN → the normal recorder starts as expected.
8. Toggle hands-free + leave the session running for >20 min (or temporarily change `HandsFreeSilenceDurationMs` to a small value + sleep through the cap; revert before next test). Confirm:
   - Session auto-ends with a notification "Hands-free session ended (20-min cap)".
   - Menubar returns to idle.
9. Open `HandsFreeSettingsView` again. Edit the trigger phrase list (add a new phrase like "submit form"). Toggle hands-free + speak an utterance ending in "submit form". Confirm Enter fires.
10. Quit + relaunch the app. Confirm hands-free hotkey + threshold + silence duration + trigger phrases all persist.

If any step fails, log the failure mode + which task is implicated, and SendMessage the lead. Tasks 1-9 are independently revertible per §Rollback plan.

---

## Notes for the lead

- **Recorder UI lifecycle is owned by `RecorderUIManager`, not `HandsFreeSessionService`.** The service calls `recorderUIManager.toggleMiniRecorder()` once at session start (shows the panel) and `recorderUIManager.dismissMiniRecorder()` once at session end (hides). Between commits, the panel stays visible because `commitUtterance` calls `engine.toggleRecord` directly — bypassing the UI manager. Coder confirms this behavior holds against `RecorderUIManager.toggleMiniRecorder:120-139`.
- **Each utterance is a separate `Transcription` row.** No schema change. A 5-minute hands-free session can create 30+ rows. History grouping ("session view") is an out-of-scope follow-up.
- **VAD = RMS gating, NOT silero streaming.** The bundled silero is per-pass-only; a streaming refactor is a separate packet.
- **Voice trigger overrides PowerMode autoSend.** A voice-trigger "press enter" suppresses the existing PowerMode autoSend so Enter fires only once.
- **Two commits, not one.** Plan doc lands first (`docs(plans): W12D — hands-free + VAD + voice press enter plan`). Code lands after lead sign-off (`feat(hands-free): W12D — continuous mode + VAD + voice press-enter trigger`).
- **No new tests.** Build is the gate. Per Q10 deferral.
- **One integration build.** Per `feedback_skip_per_packet_builds.md`. Coder does NOT run `make local` during execution.
- **Forward-compat with W12.B/E.** `HandsFreeSessionService.shared.state` is the single read-point for "is hands-free active"; W12.B (Command Mode) and W12.E (Scratchpad) can read it for their own gating decisions. The collision policy with W12.B is flagged as Open Question #5.
