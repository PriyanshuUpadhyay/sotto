# W3 — Failure Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple "a failure happened" (engine event) from "show the failure" (cluster) and "remember unresolved failures" (menubar dot). Engine emits a one-shot event; a session-scoped `FailureRegistry` remembers; the cluster + menubar each subscribe with their own lifetimes. User can pick **3s / 6s / Until-dismissed** for the cluster dwell; menubar dot persists until ack via successful retry or opening Settings.

**Architecture (Path B — locked, 3-actor model):**

```
TranscriptionPipeline / VoiceInkEngine error path
    │ on failure
    ▼
VoiceInkEngine.failurePublisher: PassthroughSubject<FailureEvent, Never>
    │ recordingState stays .idle (no dwell)
    ▼
FailureRegistry  (new ObservableObject — session-scoped, no persistence)
    • subscribes to engine.failurePublisher
    • @Published var current: FailureEvent?    (latest unacked)
    • @Published var unresolvedCount: Int
    • publish(reason:) / acknowledge(_ id: UUID) / clearAll()
    │
    ├──→ ConstellationCluster
    │       • .onReceive(registry.$current)
    │       • reads @AppStorage("failedDwellSeconds")
    │       • 3.0 / 6.0  → schedule task → registry.acknowledge(id)
    │       • .infinity   → wait for RETRY / OPEN SETTINGS / external ack
    │
    └──→ MenuBarIconRenderer (new failed-dot variant)
            • subscribes to registry.unresolvedCount
            • >0 → tangerine waveform + 4pt dot
            • 0  → normal waveform
```

**Three actors, three lifetimes:** the engine emits, the registry remembers, the UI surfaces render. No single timer drives both the cluster (3s/6s/∞) and the menubar (until-acked) — they can disagree because they answer different questions.

**Tech Stack:** Swift 5.x, SwiftUI, AppKit (menubar `NSImage`), Combine, Xcode 16.x, Swift Testing framework. Build via `make local` (~3 min cold). Animations attach via `.animation(_, value:)` / `withAnimation`; never `DispatchQueue.main.asyncAfter`.

**Spec refs:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §3 (Idle — menubar dot variant), §4 (state grammar — failed dwell + 3s/6s/Until-dismissed picker), §5 surface #2 (menubar icon), §5 surface #3 (failure routing).

**CLAUDE.md cadence rules respected:**
- **Single build at merge time.** No `make local` per task; one full build at the final task.
- **No commits during execution.** Final step reports to lead; lead handles commits.
- **No `xcodebuild` per file.** SourceKit/Xcode handles per-file syntax during edits; integration build is the gate.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** All code samples follow this.

---

## File structure

### New files

- `VoiceInk/Services/FailureEvent.swift` — `FailureEvent` value type (`id` UUID, `reason` String, `timestamp` Date). ~25 LOC.
- `VoiceInk/Services/FailureRegistry.swift` — `@MainActor` `ObservableObject`. Subscribes to an external publisher, exposes `current` + `unresolvedCount`, methods `publish(reason:)` / `acknowledge(_:)` / `clearAll()` / `attach(to:)` (subscribes to `engine.failurePublisher`). Doc comment pins the `Double.infinity` AppStorage sentinel and the session-scoped no-persistence contract. ~110 LOC.
- `VoiceInkTests/FailureRegistryTests.swift` — Swift Testing coverage for publish/acknowledge/clearAll/unresolvedCount math. ~80 LOC.

### Modified files

- `VoiceInk/Transcription/Engine/RecordingState.swift` — remove `.failed(reason: String)` case + the doc comment line describing dwell.
- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` — drop `failedDwellSeconds` constant + `failedDwellTask` field + `recordingState`'s `didSet` body + `scheduleFailedDwell()` + `cancelFailedDwell()`. Add `let failurePublisher = PassthroughSubject<FailureEvent, Never>()`. Replace every `recordingState = .failed(reason: …)` call site (lines 139, 234, 260) with `failurePublisher.send(FailureEvent(reason: …))` followed by `recordingState = .idle`. Drop the `.failed` preservation branch in `runPipeline` (lines 280-282).
- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` — add new `onFailure: (String) -> Void` parameter on `run(...)` (kept separate from `onStateChange`). Lines 166 and 182 swap `onStateChange(.failed(…))` for `onFailure(reason)`.
- `VoiceInk/Transcription/Engine/RecorderUIManager.swift` — drop the `while case .failed = engine.recordingState` poll loop in `dismissMiniRecorder` (lines 138-145). Replace the `engine.$recordingState` Combine sink (lines 67-83) that fires `playFail` on `.failed` with a `FailureRegistry.$current` sink that fires `playFail` on each new event.
- `VoiceInk/Views/Recorder/RecorderStateProvider.swift` — remove the `failureReason` extension (lines 73-80). The accessor relies on the deleted `.failed(reason:)` case and W3 has no remaining consumer.
- `VoiceInk/Views/Recorder/Constellation/ClusterPhase.swift` — update the engine bridge: drop the `case .failed(let reason)` arm of `ClusterPhase.fromEngine(_:)` (lines 59-60). `ClusterPhase.failed(reason:)` survives (sourced from registry, not engine).
- `VoiceInk/Views/Recorder/Constellation/ConstellationCluster.swift` — add `@EnvironmentObject var failureRegistry: FailureRegistry`. Replace the local `injectedFailure` State + dwell logic with a `.onReceive(failureRegistry.$current)` subscription. Cluster's failed-dwell `Task` now calls `failureRegistry.acknowledge(id)` instead of clearing local state. Honor `Double.infinity` sentinel: skip auto-ack timer, wait for retry/settings. Drop `if case .failed = state { scheduleFailedDwell() }` from `handleRecordingStateChange` (line 126). Update `derivedPhase`'s `.failed` priority to read from `failureRegistry.current`. RETRY chip clears via engine retry hook (no immediate ack); OPEN SETTINGS posts the existing `.navigateToDestination` notification (already wired).
- `VoiceInk/Views/Common/MenuBarIconRenderer.swift` — add a parallel `image(for state: IconState, unresolvedFailures: Int)` rendering path. When `unresolvedFailures > 0`, composite the waveform + a 4pt tangerine dot in the upper-right corner, hand-drawn via `NSImage.lockFocus`. Update `MenuBarIcon` SwiftUI label to take both inputs. Update `RecordingStateObserver` to also publish `unresolvedFailures: Int` (via a second binding to `FailureRegistry.$unresolvedCount`).
- `VoiceInk/Views/MenuBarView.swift` — no rendering changes (the menubar dropdown content is unchanged; only the icon glyph above it changes). No edits needed unless verification surfaces a binding gap.
- `VoiceInk/Views/Settings/SettingsView.swift` — extend `recordingFeedbackCard` with a new `SettingsRow` hosting a `Picker` for failure dwell. Writes `@AppStorage("failedDwellSeconds")` with three options: 3.0, 6.0, `.infinity`. Display labels: "3 seconds" / "6 seconds" / "Until dismissed".
- `VoiceInk/VoiceInk.swift` — instantiate `FailureRegistry` once via `@StateObject`, attach it to the engine after engine construction (`registry.attach(to: engine)`), inject it into both window groups (`ContentView` + `OnboardingView`) and the `MenuBarExtra` content via `.environmentObject(failureRegistry)`. Pass `failureRegistry.unresolvedCount` to the `MenuBarIcon` label binding.

### Retired files (delete)

None. Path B removes inline timer code and a single state-enum case but does not retire any file.

### Untouched (explicit list — coder do not drift)

- `VoiceInk/Views/Common/Palette.swift` — tokens already exist (`Palette.accent` for the tangerine dot).
- `VoiceInk/Views/Common/GlassChip.swift` — cluster chip surface unchanged; W3 only changes the data feeding it.
- `VoiceInk/Views/Recorder/Constellation/ChipPanel.swift` / `ClusterChips.swift` / `ClusterMotion.swift` — chip authoring unchanged; the failed phase still emits anchor + reason + RETRY + OPEN SETTINGS.
- `VoiceInk/Views/Recorder/HaloRecorderView.swift` / `ConstellationContainer.swift` — constructor surface preserved.
- `VoiceInk/Views/Recorder/Constellation/ConstellationCard.swift` / `ConstellationChip.swift` / `ConstellationOrb.swift` — legacy onboarding consumers of `HaloPhase`. Their `.failed` arms reference `HaloPhase.failed`, NOT `RecordingState.failed`. Untouched.
- `VoiceInk/Views/Recorder/HaloMaterial.swift` — same; its `.failed` arms are on `HaloPhase`. Untouched.
- `VoiceInk/Views/AudioFileRow.swift` / `Components/PromptLivePreview.swift` / `AI Models/MLXModelPickerView.swift` / `Services/AudioFileTranscriptionManager.swift` / `CoreAudioRecorder.swift` — `.failed` cases here belong to *other* enums (audio item status, prompt preview status, MLX download status, AudioFileTranscriptionItem.Status, CoreAudioRecorderError). Verified by inspection. Untouched.
- `HotkeyManager.swift` / `PowerMode/PowerModeShortcutManager.swift` — guard `engine.recordingState != .transcribing && != .enhancing && != .busy`. They never reference `.failed`. Untouched.
- `VoiceInk/Views/MenuBarView.swift`'s `recordingButton` switch — the `default:` arm absorbs the (now-impossible) `.failed`, so removing the case from `RecordingState` doesn't trigger an exhaustiveness error.

---

## Migration policy (resolves ambiguity for each design point)

The team-lead pinned 12 architecture decisions. They are restated here as the authoritative ruleset for the coder.

1. **`FailureRegistry` ownership / DI.** Instantiated once in `VoiceInk.swift`'s `init()` as a local then wrapped in `@StateObject private var failureRegistry: FailureRegistry`. After the engine is built (line 119), the bootstrap calls `failureRegistry.attach(to: engine)` so the registry's Combine subscription to `engine.failurePublisher` is live before any UI mounts. Injected as `@EnvironmentObject` into both `WindowGroup` content and the `MenuBarExtra` content. **Session-scoped only** — no UserDefaults / SwiftData persistence; failures vanish on app relaunch. Documented at top of `FailureRegistry.swift`.

2. **`FailureEvent` shape.** `id: UUID`, `reason: String`, `timestamp: Date`. `Equatable` based on `id` only — duplicate publishes get distinct entries. `Identifiable` for ForEach use. No `category` field (future extension if W6+ ever surfaces typed errors).

3. **Engine refactor scope (exact changes).** All performed in Task 3 below:
   - Drop `static let failedDwellSeconds: Double = 1.4` (line 38).
   - Drop `private var failedDwellTask: Task<Void, Never>?` (line 39).
   - Replace the `recordingState` `didSet { switch … }` body (lines 16-25) with no observer (the property becomes a plain `@Published`).
   - Drop `private func scheduleFailedDwell()` (lines 291-303).
   - Drop `private func cancelFailedDwell()` (lines 307-310).
   - Update the `recordingState` doc-comment block (lines 10-14) to remove dwell language; replace with: `/// Engine state. Failures are emitted as one-shot events via failurePublisher; the engine never sustains a failed state — it returns to .idle immediately.`
   - Add `let failurePublisher = PassthroughSubject<FailureEvent, Never>()` directly under `@Published var lastPasteEvent`.
   - At each former `recordingState = .failed(reason: X)` site (139, 234, 260): swap to:
     ```swift
     failurePublisher.send(FailureEvent(reason: X))
     recordingState = .idle
     ```
   - Drop the `.failed` preservation branch in `runPipeline` (lines 279-284). Replace with:
     ```swift
     if recordingState != .idle {
         recordingState = .idle
     }
     ```
   - **The engine does not import or know about `FailureRegistry`.** External subscription only. The registry calls `engine.failurePublisher.sink {…}` from its own `attach(to:)` method.

4. **`RecordingState.failed` fate.** **REMOVE the case entirely.** Reason: `.failed` no longer represents a state the engine sustains. Removing simplifies pattern matching app-wide. Updated consumers:
   - `VoiceInkEngine.swift` lines 18, 139, 234, 260, 280, 299 → covered by point 3.
   - `RecorderStateProvider.swift` lines 73-80 (`failureReason` extension) → DELETE entirely (Task 5). No consumer survives W3.
   - `RecorderUIManager.swift:143` (`while case .failed = engine.recordingState` poll loop) → DELETE entirely (Task 8). Teardown is unconditional under Path B.
   - `RecorderUIManager.swift:77` (`guard case .failed = newState else { return }` in Combine sink) → REWIRE to `FailureRegistry.$current` (Task 8). Sink fires `playFail` on each non-nil event.
   - `TranscriptionPipeline.swift` lines 166, 182 → REPLACE `onStateChange(.failed(…))` with `onFailure(reason)` (Task 6).
   - `ConstellationCluster.swift:126` (`if case .failed = state { scheduleFailedDwell() }`) → DELETE (Task 9). Cluster sources failures from the registry.
   - `ClusterPhase.swift:59-60` (engine bridge) → DROP the `.failed(let reason)` arm (Task 10). `ClusterPhase` itself keeps its `.failed(reason: String?)` case — it's now sourced from the registry, not `ClusterPhase.fromEngine`.
   - **Untouched** consumers (different enums; verified):
     - `Views/AudioFileRow.swift:37`, `Components/PromptLivePreview.swift:117/172/210`, `Views/Recorder/Constellation/ConstellationOrb.swift:132/163/178`, `ConstellationChip.swift:74`, `ConstellationCard.swift:189/206/394/467`, `HaloMaterial.swift:31/44`, `AI Models/MLXModelPickerView.swift:90`, `Services/AudioFileTranscriptionManager.swift:66`, `CoreAudioRecorder.swift:890-910`. All these `.failed` cases live on different enums (audio item status / prompt preview status / `HaloPhase` / MLX download status / `CoreAudioRecorderError`).

5. **Pipeline injection of registry.** `TranscriptionPipeline.run(...)` gains a sibling `onFailure: (String) -> Void` parameter. `onStateChange` is **kept separate** for clarity (non-failure transitions still flow through it). Pipeline call sites (lines 166, 182) call `onFailure(reason)`. `VoiceInkEngine.runPipeline` wires `onFailure` to `{ [weak self] reason in self?.failurePublisher.send(FailureEvent(reason: reason)) }`.

6. **Cluster subscription change.** The W2 seam `injectFailure(reason:)` is replaced by an `.onReceive(failureRegistry.$current)` subscription. When `current` becomes non-nil, the cluster sets internal state; when it goes nil (acked), the cluster retracts. The cluster's failed-dwell `Task` schedules `failureRegistry.acknowledge(id)` after AppStorage dwell — NOT clearing local state directly. The W2 `injectFailure` method is **deleted** (Task 9) — its only purpose was the W3 hook, which is now subsumed by registry observation.

7. **"Until-dismissed" sentinel.** AppStorage stores `Double`. `Double.infinity` means "until dismissed". Cluster's failed-dwell task: `if dwell.isFinite { sleep then acknowledge } else { wait for retry/settings }`. Settings UI writes `3.0`, `6.0`, or `Double.infinity`. Single key, no `failedDwellMode` enum. Documented in `FailureRegistry.swift`'s top doc comment AND in the SettingsView picker block.

8. **Menubar dot variant.** New code path in `MenuBarIconRenderer.image(for:, unresolvedFailures:)`. When `unresolvedFailures > 0`, composite (a) the recording-color tinted waveform (`Palette.accent`) and (b) a 4pt circle in `Palette.accent` at the upper-right of the 18pt canvas. **Hand-draw via `NSImage.lockFocus`** — no asset dependency. Stays in AppKit territory (menubar items are NSImage). The variant is selected only when `unresolvedFailures > 0`, regardless of recording state — the dot is the higher-priority signal.

9. **MenuBarView wiring.** Add `@Published private(set) var unresolvedFailures: Int = 0` to `RecordingStateObserver` alongside `iconState`. Add a second `bind(toRegistry:)` method that subscribes to `failureRegistry.$unresolvedCount` and republishes via `.receive(on: DispatchQueue.main).removeDuplicates()`. The two bindings are independent — engine state and failure count are orthogonal. The `MenuBarIcon` SwiftUI label reads both `observer.iconState` and `observer.unresolvedFailures`.

10. **Settings UI placement.** **`VoiceInk/Views/Settings/SettingsView.swift`'s `recordingFeedbackCard`** (lines 250-306). Rationale: that card already groups recorder-feedback timing knobs (sound, mute resume delay, clipboard restore delay, AppleScript paste). The failure-dwell picker is the same kind of UX-timing knob. Adding it as a `SettingsRow` keeps related settings together; users discover it where they already tune recording UX. Alternative homes (`EnhancementSettingsView`, a new dedicated section, `RecorderStylePicker.swift`) would either fragment timing settings or scope-creep an unrelated file.

11. **Auto-ack hooks.**
    - **Opening Settings → ack the current event.** The cluster's OPEN SETTINGS chip already posts `.navigateToDestination` with `userInfo["destination"] == "Settings"` (W2 — `ConstellationCluster.handleOpenSettings`). The `FailureRegistry` listens on the same notification and runs `clearAll()` — clears both `current` and `unresolvedCount`. Wired in `FailureRegistry.attach(to:)`.
    - **Successful retry / fresh success → ack.** After a successful enhance (i.e. when `TranscriptionPipeline.run` completes without invoking `onFailure`), the engine calls `failureRegistry.clearAll()` at the tail of `runPipeline`. **Pin: ack only on success, not on RETRY chip click** — so the dot stays if the retry also fails. The RETRY chip itself triggers a re-record via the existing toggle hotkey path (no new code; the chip is informational + visual).
    - The Settings-open ack happens via Notification because the registry must clear when ANY Settings open occurs (menubar Settings menu, hotkey, OPEN SETTINGS chip, deep-link). Centralizing on `.navigateToDestination` covers all paths that already exist.

12. **Tests.**
    - `VoiceInkTests/FailureRegistryTests.swift` — Swift Testing format (matches existing `VoiceInkTests.swift`):
      - `publishIncrementsUnresolvedAndSetsCurrent` — publish two events, expect `unresolvedCount == 2` and `current.id == lastPublished.id`.
      - `acknowledgeMatchingIdClearsCurrent` — publish, ack the published id, expect `current == nil` and `unresolvedCount == 0`.
      - `acknowledgeNonMatchingIdIsNoop` — publish, ack a fresh UUID, expect state unchanged.
      - `clearAllResetsBoth` — publish three, clearAll, expect `current == nil` and `unresolvedCount == 0`.
      - `attachToEngineRoutesPublisher` — build a stub publisher (skip `VoiceInkEngine` itself; tests are pure unit and should not bring up the engine's heavy dependencies). Use a small protocol: registry takes `attach(to publisher: AnyPublisher<FailureEvent, Never>)`. Send through the publisher and assert registry mutates.
    - **No engine test added.** `VoiceInkTests.swift` currently holds Palette tests only — there is no engine test infrastructure (no fakes for `WhisperModelManager` / `AIService` / `ModelContext`). Skipping per the team-lead's "if no engine tests exist, skip" guidance. Manual verification at the integration build (Task 14) covers the engine refactor.

---

## Tasks

### Task 0: Audit + read references

**Files:** none (read-only).

- [ ] **Step 0.1: Confirm only the listed `.failed` consumers reference `RecordingState.failed`**

```bash
grep -rn "case \.failed\|case .failed\|\.failed(reason" VoiceInk --include="*.swift"
```

Expected matches that DO involve `RecordingState.failed`:
- `Transcription/Engine/VoiceInkEngine.swift` lines 10, 18, 36, 139, 234, 260, 280, 299
- `Transcription/Engine/TranscriptionPipeline.swift` lines 166, 182
- `Transcription/Engine/RecorderUIManager.swift` lines 77, 143
- `Views/Recorder/RecorderStateProvider.swift` line 77
- `Views/Recorder/Constellation/ConstellationCluster.swift` lines 84, 126
- `Views/Recorder/Constellation/ClusterPhase.swift` lines 29, 44, 59, 60
- `Views/Recorder/Constellation/ClusterChips.swift` line 48

Expected matches that do NOT involve `RecordingState.failed` (different enums; leave alone):
- `CoreAudioRecorder.swift:890-910` (`CoreAudioRecorderError`)
- `Views/AudioFileRow.swift:37` (`AudioFileTranscriptionItem.Status`)
- `Views/Components/PromptLivePreview.swift:117/172/210` (prompt-preview status)
- `Views/Recorder/Constellation/ConstellationOrb.swift:132/163/178` (`HaloPhase`)
- `Views/Recorder/Constellation/ConstellationChip.swift:74` (`HaloPhase`)
- `Views/Recorder/Constellation/ConstellationCard.swift:189/206/394/467` (`HaloPhase`)
- `Views/Recorder/HaloMaterial.swift:31/44` (`HaloPhase`)
- `Views/AI Models/MLXModelPickerView.swift:90` (MLX download status)
- `Services/AudioFileTranscriptionManager.swift:66` (`AudioFileTranscriptionItem.Status`)

If the grep surfaces any *other* file referencing `RecordingState.failed`, stop and reconcile with the lead before continuing.

- [ ] **Step 0.2: Confirm `engine.recordingState` consumers are W3-safe**

```bash
grep -rn "engine.recordingState\|recordingState ==" VoiceInk --include="*.swift"
```

Expected: `HotkeyManager.swift`, `PowerMode/PowerModeShortcutManager.swift`, `RecorderUIManager.swift`, `VoiceInkEngine.swift`, `MenuBarView.swift`. None of these match `.failed` by name — they all use `==` comparisons against non-failed cases (`.recording`, `.transcribing`, `.enhancing`, `.busy`) or use a `default:` arm. Removing `.failed` from `RecordingState` does not break exhaustiveness for any of them. If the grep surfaces a switch with no `default:` arm that pattern-matches `.failed` directly, stop.

- [ ] **Step 0.3: Confirm `FailureRegistry` does not collide with an existing symbol**

```bash
grep -rn "FailureRegistry\|FailureEvent" VoiceInk --include="*.swift"
```

Expected: zero matches before W3 lands.

---

### Task 1: Add `FailureEvent.swift`

**Files:**
- Create: `VoiceInk/Services/FailureEvent.swift`

- [ ] **Step 1.1: Verify the `Services/` group exists**

```bash
ls VoiceInk/Services/ | head
```

Expected: at least `AudioFileTranscriptionManager.swift`, `ImportExportService.swift`, etc. The directory already hosts cross-cutting service singletons; `FailureEvent` + `FailureRegistry` slot in cleanly here.

- [ ] **Step 1.2: Write the file**

```swift
import Foundation

// MARK: - FailureEvent
//
// Single failure occurrence emitted by `VoiceInkEngine.failurePublisher` and
// stored by `FailureRegistry`. Identity is the UUID — two publishes with the
// same reason string still produce distinct events, so a repeat failure
// re-mounts the cluster and increments `unresolvedCount`.
//
// Spec §4 / §5 surface #3.

struct FailureEvent: Identifiable, Equatable {
    let id: UUID
    let reason: String
    let timestamp: Date

    init(reason: String, id: UUID = UUID(), timestamp: Date = Date()) {
        self.id = id
        self.reason = reason
        self.timestamp = timestamp
    }

    static func == (lhs: FailureEvent, rhs: FailureEvent) -> Bool {
        lhs.id == rhs.id
    }
}
```

- [ ] **Step 1.3: Add file to Xcode project target**

```bash
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("VoiceInk.xcodeproj")
target = project.targets.find { |t| t.name == "VoiceInk" }
group = project.main_group
["VoiceInk", "Services"].each do |seg|
  group = group.find_subpath(seg, false) || (raise "missing group #{seg}")
end
file_ref = group.new_reference("FailureEvent.swift")
target.add_file_references([file_ref])
project.save
'
```

---

### Task 2: Add `FailureRegistry.swift`

**Files:**
- Create: `VoiceInk/Services/FailureRegistry.swift`

- [ ] **Step 2.1: Write the file**

```swift
import Foundation
import Combine

// MARK: - FailureRegistry
//
// Session-scoped store for unresolved failures. Subscribes to an external
// publisher of `FailureEvent`s (typically `VoiceInkEngine.failurePublisher`),
// surfaces the latest unacked event via `current`, and exposes
// `unresolvedCount` as a separate signal so the menubar dot can persist past
// the cluster's dwell.
//
// Lifetime contract:
//   • Session-scoped only. No UserDefaults / SwiftData persistence. Failures
//     vanish on app relaunch — by design (spec §3, "If user navigates away
//     without resolving, dot returns on next launch" describes the in-session
//     persistence; cross-launch persistence is explicitly NOT in scope).
//
// Sentinel:
//   • The companion `@AppStorage("failedDwellSeconds")` knob accepts:
//       3.0  → cluster auto-dismisses after 3 seconds
//       6.0  → cluster auto-dismisses after 6 seconds
//       Double.infinity → cluster persists until RETRY / OPEN SETTINGS / ack
//     The registry itself never reads this value — the cluster reads it and
//     decides when to call `acknowledge(id:)`. Documented here so a coder
//     reading the registry knows where the timing decision lives.
//
// Auto-ack hooks (wired in `attach(to:)`):
//   • `.navigateToDestination` notification with userInfo["destination"]
//     starting with "Settings" → calls `clearAll()`. Catches the cluster's
//     OPEN SETTINGS chip, the menubar Settings menu, hotkey paths, and any
//     other Settings deep-link.
//
// Spec §4 / §5 surface #3.

@MainActor
final class FailureRegistry: ObservableObject {
    @Published private(set) var current: FailureEvent?
    @Published private(set) var unresolvedCount: Int = 0

    private var cancellables = Set<AnyCancellable>()
    private var settingsAckObserver: NSObjectProtocol?

    init() {
        installSettingsAckObserver()
    }

    deinit {
        if let observer = settingsAckObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Publishing

    /// External callers push a failure with just a reason string; the
    /// registry mints the id + timestamp.
    func publish(reason: String) {
        let event = FailureEvent(reason: reason)
        current = event
        unresolvedCount += 1
    }

    /// Ack a single event by id. Clears `current` only if the latest event
    /// matches the id; always decrements `unresolvedCount` (clamped at 0)
    /// when the id was a known publish — caller passes the id from the
    /// `current` snapshot they observed.
    func acknowledge(_ id: UUID) {
        if current?.id == id {
            current = nil
        }
        if unresolvedCount > 0 {
            unresolvedCount -= 1
        }
    }

    /// Drop everything. Used by the success path (engine clears after a
    /// clean `runPipeline`) and by the Settings-open auto-ack hook.
    func clearAll() {
        current = nil
        unresolvedCount = 0
    }

    // MARK: - Engine attachment

    /// Subscribe to a `VoiceInkEngine`-shaped failure publisher. Kept as an
    /// external attach call rather than an injected reference so the engine
    /// stays unaware of `FailureRegistry`'s existence.
    func attach<P: Publisher>(to publisher: P)
    where P.Output == FailureEvent, P.Failure == Never {
        publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                self.current = event
                self.unresolvedCount += 1
            }
            .store(in: &cancellables)
    }

    // MARK: - Settings-open auto-ack

    private func installSettingsAckObserver() {
        settingsAckObserver = NotificationCenter.default.addObserver(
            forName: .navigateToDestination,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let dest = note.userInfo?["destination"] as? String,
                  dest.hasPrefix("Settings") else { return }
            Task { @MainActor [weak self] in
                self?.clearAll()
            }
        }
    }
}
```

- [ ] **Step 2.2: Add file to Xcode project target**

```bash
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("VoiceInk.xcodeproj")
target = project.targets.find { |t| t.name == "VoiceInk" }
group = project.main_group
["VoiceInk", "Services"].each do |seg|
  group = group.find_subpath(seg, false) || (raise "missing group #{seg}")
end
file_ref = group.new_reference("FailureRegistry.swift")
target.add_file_references([file_ref])
project.save
'
```

---

### Task 3: Refactor `VoiceInkEngine` — drop dwell, add `failurePublisher`

**Files:**
- Modify: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`

- [ ] **Step 3.1: Add Combine import**

At the top of the file, replace the existing import block with:

```swift
import Foundation
import SwiftUI
import AVFoundation
import SwiftData
import AppKit
import Combine
import os
```

(Adds `import Combine` for `PassthroughSubject`.)

- [ ] **Step 3.2: Replace the `recordingState` doc + `didSet`**

Current (lines 10-26):

```swift
    /// Engine state. Transitioning to `.failed(reason:)` schedules an automatic
    /// collapse back to `.idle` after `failedDwellSeconds` so the view layer can
    /// render the failure visual (red shake → amber dwell → fade) without the
    /// call site having to manage timers. Starting a new recording cancels any
    /// pending dwell so a fresh `.recording` is never stomped by a stale `.idle`.
    @Published var recordingState: RecordingState = .idle {
        didSet {
            switch recordingState {
            case .failed:
                scheduleFailedDwell()
            case .recording, .starting:
                cancelFailedDwell()
            default:
                break
            }
        }
    }
```

Replace with:

```swift
    /// Engine state. Failures are emitted as one-shot events via
    /// `failurePublisher`; the engine never sustains a failed state — it
    /// returns to `.idle` immediately so the view layer's failure lifetime is
    /// owned by `FailureRegistry` (Path B, spec §4 / §5 surface #3).
    @Published var recordingState: RecordingState = .idle
```

- [ ] **Step 3.3: Replace the dwell constants + add `failurePublisher`**

Current (lines 36-39):

```swift
    /// Dwell window for `.failed(reason:)` before collapsing to `.idle`.
    /// Matches spec §3.1: red shake (~0.32s) + amber dwell (~1.2s) ≈ 1.4s.
    static let failedDwellSeconds: Double = 1.4
    private var failedDwellTask: Task<Void, Never>?
```

Replace with:

```swift
    /// One-shot failure events. `FailureRegistry` subscribes externally; the
    /// engine has no awareness of the registry. Each `send` carries a fresh
    /// `FailureEvent` (UUID + reason + timestamp). Spec §4 / §5 surface #3.
    let failurePublisher = PassthroughSubject<FailureEvent, Never>()
```

- [ ] **Step 3.4: Swap each `recordingState = .failed(reason: …)` site**

Three sites to update.

**Site 1 — line 139** (no recorded audio file):

```swift
                recordingState = .failed(reason: "No recorded audio file")
                await cleanupResources()
```

Replace with:

```swift
                failurePublisher.send(FailureEvent(reason: "No recorded audio file"))
                recordingState = .idle
                await cleanupResources()
```

**Site 2 — line 234** (recorder start failure):

```swift
                                self.recordingState = .failed(reason: error.localizedDescription)
                                self.recordedFile = nil
```

Replace with:

```swift
                                self.failurePublisher.send(FailureEvent(reason: error.localizedDescription))
                                self.recordingState = .idle
                                self.recordedFile = nil
```

**Site 3 — line 260** (no transcription model):

```swift
            recordingState = .failed(reason: "No transcription model selected")
            return
```

Replace with:

```swift
            failurePublisher.send(FailureEvent(reason: "No transcription model selected"))
            recordingState = .idle
            return
```

- [ ] **Step 3.5: Replace the `.failed` preservation branch in `runPipeline`**

Current (lines 278-285):

```swift
        shouldCancelRecording = false
        // Preserve `.failed` so its dwell can complete; it self-collapses to `.idle`.
        if case .failed = recordingState {
            // dwell timer owns the transition
        } else if recordingState != .idle {
            recordingState = .idle
        }
    }
```

Replace with:

```swift
        shouldCancelRecording = false
        if recordingState != .idle {
            recordingState = .idle
        }
    }
```

- [ ] **Step 3.6: Delete `scheduleFailedDwell()` and `cancelFailedDwell()`**

Current (lines 287-310):

```swift
    // MARK: - Failed dwell

    /// Schedules the `.failed` → `.idle` collapse. Idempotent: replaces any
    /// in-flight dwell so a fresh failure resets the timer.
    private func scheduleFailedDwell() {
        failedDwellTask?.cancel()
        failedDwellTask = Task { @MainActor [weak self] in
            let nanos = UInt64(VoiceInkEngine.failedDwellSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            // Only collapse if we're still dwelling — a new recording or
            // explicit reset may have already moved us elsewhere.
            if case .failed = self.recordingState {
                self.recordingState = .idle
            }
        }
    }

    /// Cancels any pending failure dwell. Called on transitions out of `.failed`
    /// (e.g. user starts a new recording mid-dwell).
    private func cancelFailedDwell() {
        failedDwellTask?.cancel()
        failedDwellTask = nil
    }
```

Delete the entire MARK block (the comment header + both methods).

- [ ] **Step 3.7: Diff inspection**

```bash
git --no-pager diff VoiceInk/Transcription/Engine/VoiceInkEngine.swift | head -120
```

Expected: additions of `failurePublisher` + `import Combine`; deletions of `scheduleFailedDwell` / `cancelFailedDwell` / the dwell constants / the `didSet` body / the `.failed` preservation branch; three `.failed(reason:)` → `failurePublisher.send(…)` swaps.

---

### Task 4: Remove `.failed` from `RecordingState`

**Files:**
- Modify: `VoiceInk/Transcription/Engine/RecordingState.swift`

- [ ] **Step 4.1: Replace file contents**

Current (entire file):

```swift
import Foundation

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
    /// Transient failure dwell. Engine collapses back to `.idle` after
    /// `VoiceInkEngine.failedDwellSeconds`. Reason is the user-readable error.
    case failed(reason: String)
}
```

Replace with:

```swift
import Foundation

// MARK: - RecordingState
//
// Engine-side recording lifecycle. Failures used to live here as
// `.failed(reason:)` with a 1.4s dwell baked into the engine — that path was
// retired in W3 (Path B). Failures are now one-shot `FailureEvent`s emitted
// via `VoiceInkEngine.failurePublisher` and remembered by `FailureRegistry`;
// the engine returns to `.idle` immediately on error.
//
// Spec §4 / §5 surface #3.

enum RecordingState: Equatable {
    case idle
    case starting
    case recording
    case transcribing
    case enhancing
    case busy
}
```

---

### Task 5: Remove `RecorderStateProvider.failureReason`

**Files:**
- Modify: `VoiceInk/Views/Recorder/RecorderStateProvider.swift`

- [ ] **Step 5.1: Delete the `failureReason` extension**

Current (lines 73-80):

```swift
extension RecorderStateProvider {
    /// Convenience accessor for the failure reason embedded in
    /// `RecordingState.failed`. Returns nil for any other state.
    var failureReason: String? {
        if case .failed(let reason) = recordingState { return reason }
        return nil
    }
}
```

Delete the entire extension block (lines 73-80, ending at the closing brace).

- [ ] **Step 5.2: Verify no consumer of `failureReason` survives**

```bash
grep -rn "failureReason" VoiceInk --include="*.swift"
```

Expected: zero matches. (W2 used the accessor in mappings that have since been replaced by registry observation.)

---

### Task 6: Add `onFailure` callback to `TranscriptionPipeline`

**Files:**
- Modify: `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`

- [ ] **Step 6.1: Add the parameter to `run(...)`**

Current (lines 39-48):

```swift
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        onStateChange: @escaping (RecordingState) -> Void,
        shouldCancel: () -> Bool,
        onCleanup: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
```

Replace with:

```swift
    func run(
        transcription: Transcription,
        audioURL: URL,
        model: any TranscriptionModel,
        session: TranscriptionSession?,
        onStateChange: @escaping (RecordingState) -> Void,
        onFailure: @escaping (String) -> Void,
        shouldCancel: () -> Bool,
        onCleanup: @escaping () async -> Void,
        onDismiss: @escaping () async -> Void
    ) async {
```

Update the doc comment block immediately above (lines 30-38). Add a line for `onFailure`:

```swift
    ///   - onStateChange: Called when the pipeline moves to a new recording state (e.g. `.enhancing`).
    ///   - onFailure: Called with a user-readable reason when the pipeline hits a failure path
    ///     (transcription throw or enhancement throw). The engine forwards this to
    ///     `failurePublisher` so the FailureRegistry can surface it. Path B / spec §4.
    ///   - shouldCancel: Returns true if the user requested cancellation.
```

- [ ] **Step 6.2: Swap line 166 (enhancement failure)**

Current:

```swift
                    onStateChange(.failed(reason: "Enhancement failed: \(shortReason)"))
```

Replace with:

```swift
                    onFailure("Enhancement failed: \(shortReason)")
```

- [ ] **Step 6.3: Swap line 182 (transcription failure)**

Current:

```swift
            onStateChange(.failed(reason: "Transcription failed: \(shortReason)"))
```

Replace with:

```swift
            onFailure("Transcription failed: \(shortReason)")
```

---

### Task 7: Wire pipeline `onFailure` to engine `failurePublisher`

**Files:**
- Modify: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`

- [ ] **Step 7.1: Update the `pipeline.run(...)` call site**

Current (`runPipeline`, lines 267-277):

```swift
        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            model: model,
            session: session,
            onStateChange: { [weak self] state in self?.recordingState = state },
            shouldCancel: { [weak self] in self?.shouldCancelRecording ?? false },
            onCleanup: { [weak self] in await self?.cleanupResources() },
            onDismiss: { [weak self] in await self?.recorderUIManager?.dismissMiniRecorder() }
        )
```

Replace with:

```swift
        await pipeline.run(
            transcription: transcription,
            audioURL: audioURL,
            model: model,
            session: session,
            onStateChange: { [weak self] state in self?.recordingState = state },
            onFailure: { [weak self] reason in
                self?.failurePublisher.send(FailureEvent(reason: reason))
            },
            shouldCancel: { [weak self] in self?.shouldCancelRecording ?? false },
            onCleanup: { [weak self] in await self?.cleanupResources() },
            onDismiss: { [weak self] in await self?.recorderUIManager?.dismissMiniRecorder() }
        )
```

---

### Task 8: Refactor `RecorderUIManager` (drop poll loop, rewire cue sink)

**Files:**
- Modify: `VoiceInk/Transcription/Engine/RecorderUIManager.swift`

- [ ] **Step 8.1: Add a stored `failureRegistry` reference**

Add a new property near the existing `private weak var engine: VoiceInkEngine?` (around line 42):

```swift
    /// Path B: failure cue (`SoundManager.playFail`) fires on each registry
    /// publish, not on engine state. Held strongly because the registry's
    /// lifetime matches the app process. Set via `configure(...)` after
    /// `VoiceInkApp.init` builds the registry.
    private var failureRegistry: FailureRegistry?
```

- [ ] **Step 8.2: Update `configure(engine:recorder:)` signature + body**

Current (line 55):

```swift
    /// Call after VoiceInkEngine is created to break the circular init dependency.
    func configure(engine: VoiceInkEngine, recorder: Recorder) {
        self.engine = engine
        self.recorder = recorder
        setupNotifications()
        setupStateCueObservers(engine: engine)
    }
```

Replace with:

```swift
    /// Call after VoiceInkEngine + FailureRegistry are created to break the
    /// circular init dependency.
    func configure(engine: VoiceInkEngine, recorder: Recorder, failureRegistry: FailureRegistry) {
        self.engine = engine
        self.recorder = recorder
        self.failureRegistry = failureRegistry
        setupNotifications()
        setupFailureCueObserver(registry: failureRegistry)
    }
```

- [ ] **Step 8.3: Replace `setupStateCueObservers` with `setupFailureCueObserver`**

Current (lines 62-83):

```swift
    /// P3.F: Fire the synthesized failure cue whenever the engine transitions
    /// into `.failed`. Failures originate from multiple sites (recorder start,
    /// missing model, transcription throw, enhancement throw) — observing the
    /// state directly keeps the cue trigger consolidated rather than scattering
    /// `playFail()` calls across each error path.
    private func setupStateCueObservers(engine: VoiceInkEngine) {
        // Cancel any prior subscription before re-subscribing. Today there's
        // only one `configure()` call site, but a second call would otherwise
        // leave the prior sink alive in the set and fire the failure cue twice
        // per transition.
        stateCueObservers.removeAll()

        engine.$recordingState
            .removeDuplicates()
            .sink { newState in
                guard case .failed = newState else { return }
                Task { @MainActor in
                    SoundManager.shared.playFail()
                }
            }
            .store(in: &stateCueObservers)
    }
```

Replace with:

```swift
    /// Path B: fire `SoundManager.playFail` on every fresh `FailureEvent`
    /// from the registry. Replaces the previous `engine.$recordingState`
    /// sink — the engine no longer transitions to `.failed`.
    private func setupFailureCueObserver(registry: FailureRegistry) {
        stateCueObservers.removeAll()

        registry.$current
            .compactMap { $0 }
            .removeDuplicates()
            .sink { _ in
                Task { @MainActor in
                    SoundManager.shared.playFail()
                }
            }
            .store(in: &stateCueObservers)
    }
```

- [ ] **Step 8.4: Drop the `.failed` poll loop in `dismissMiniRecorder`**

Current (lines 138-145):

```swift
        // Hold off teardown while the engine is dwelling on `.failed` so the
        // failure visual gets its window before the panel collapses. The dwell
        // is bounded by `VoiceInkEngine.failedDwellSeconds`; loop exits cleanly
        // whether the engine self-collapses to `.idle` or a new recording starts.
        while case .failed = engine.recordingState {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        if engine.recordingState == .busy {
```

Delete the comment block + the `while` loop entirely. The `if engine.recordingState == .busy` check stays:

```swift
        if engine.recordingState == .busy {
```

Path B: the cluster's failure visual is sourced from `FailureRegistry`, with a lifetime independent of the recorder panel. The panel can tear down immediately; the cluster keeps showing the failed state until its own dwell expires (or until-dismissed sentinel resolves).

- [ ] **Step 8.5: Rename the comment on `stateCueObservers`**

Current (line 45):

```swift
    /// P3.F: Combine subscription to `engine.$recordingState` that fires the
    /// failure cue (`SoundManager.playFail`) on every transition into `.failed`.
    /// Stored as a set so the sink is torn down with the manager.
    private var stateCueObservers = Set<AnyCancellable>()
```

Replace with:

```swift
    /// Combine subscription to `FailureRegistry.$current` that fires the
    /// failure cue (`SoundManager.playFail`) on every fresh failure event.
    /// Stored as a set so the sink is torn down with the manager.
    private var stateCueObservers = Set<AnyCancellable>()
```

---

### Task 9: Refactor `ConstellationCluster` to subscribe to `FailureRegistry`

**Files:**
- Modify: `VoiceInk/Views/Recorder/Constellation/ConstellationCluster.swift`

- [ ] **Step 9.1: Add `failureRegistry` environment dependency + state**

Add `@EnvironmentObject` near the other dependencies. Replace the existing dependency block (lines 18-26):

```swift
struct ConstellationCluster<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    let mode: HaloShape.Mode

    @AppStorage("failedDwellSeconds") private var failedDwellSeconds: Double = 6.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

With:

```swift
struct ConstellationCluster<S: RecorderStateProvider & ObservableObject>: View {
    @ObservedObject var stateProvider: S
    @ObservedObject var recorder: Recorder
    @ObservedObject var aiService: AIService
    @EnvironmentObject var failureRegistry: FailureRegistry
    let mode: HaloShape.Mode

    /// Failure dwell. 3.0 / 6.0 = auto-acknowledge after seconds;
    /// `.infinity` = persist until RETRY / OPEN SETTINGS / external ack.
    @AppStorage("failedDwellSeconds") private var failedDwellSeconds: Double = 6.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
```

- [ ] **Step 9.2: Replace `injectedFailure` with a subscribed mirror**

Current (lines 28-40):

```swift
    // MARK: - Phase state

    @State private var injectedFailure: String? = nil
    @State private var donePayload: DonePayload? = nil
    @State private var doneFading: Bool = false
    @State private var doneTask: Task<Void, Never>? = nil
    @State private var failedTask: Task<Void, Never>? = nil
    @State private var recordingStartedAt: Date? = nil

    private struct DonePayload: Equatable {
        let appName: String?
        let preview: String?
    }
```

Replace with:

```swift
    // MARK: - Phase state

    @State private var activeFailure: FailureEvent? = nil
    @State private var donePayload: DonePayload? = nil
    @State private var doneFading: Bool = false
    @State private var doneTask: Task<Void, Never>? = nil
    @State private var failedTask: Task<Void, Never>? = nil
    @State private var recordingStartedAt: Date? = nil

    private struct DonePayload: Equatable {
        let appName: String?
        let preview: String?
    }
```

- [ ] **Step 9.3: Replace `body` to subscribe to the registry**

Current (lines 44-70):

```swift
    var body: some View {
        let layout = ConstellationLayout.current(mode: mode)
        let phase = derivedPhase

        ZStack(alignment: .topLeading) {
            if phase.isVisible {
                ChipPanel(phase: phase, chips: chipsForCurrentPhase(phase))
                    .opacity(doneFading ? 0 : 1)
                    .animation(reduceMotion ? .clusterFadeReduced : .clusterFade,
                               value: doneFading)
                    .position(x: layout.anchorX, y: layout.anchorY)
                    .transition(
                        AnyTransition.opacity
                            .animation(reduceMotion ? Animation.clusterFadeReduced : Animation.haloExpand)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? .clusterFadeReduced : .haloExpand, value: phase.identity)
        .onChange(of: stateProvider.recordingState) { _, newState in
            handleRecordingStateChange(newState)
        }
        .onChange(of: stateProvider.lastPasteEvent) { _, event in
            handlePasteEvent(event)
        }
        .onAppear { handleRecordingStateChange(stateProvider.recordingState) }
    }
```

Replace with:

```swift
    var body: some View {
        let layout = ConstellationLayout.current(mode: mode)
        let phase = derivedPhase

        ZStack(alignment: .topLeading) {
            if phase.isVisible {
                ChipPanel(phase: phase, chips: chipsForCurrentPhase(phase))
                    .opacity(doneFading ? 0 : 1)
                    .animation(reduceMotion ? .clusterFadeReduced : .clusterFade,
                               value: doneFading)
                    .position(x: layout.anchorX, y: layout.anchorY)
                    .transition(
                        AnyTransition.opacity
                            .animation(reduceMotion ? Animation.clusterFadeReduced : Animation.haloExpand)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(reduceMotion ? .clusterFadeReduced : .haloExpand, value: phase.identity)
        .onChange(of: stateProvider.recordingState) { _, newState in
            handleRecordingStateChange(newState)
        }
        .onChange(of: stateProvider.lastPasteEvent) { _, event in
            handlePasteEvent(event)
        }
        .onReceive(failureRegistry.$current) { event in
            handleFailureEvent(event)
        }
        .onAppear { handleRecordingStateChange(stateProvider.recordingState) }
    }
```

- [ ] **Step 9.4: Replace `derivedPhase`**

Current (lines 72-87):

```swift
    // MARK: - Phase derivation
    //
    // Resolution order (highest priority first):
    //   1. donePayload window (1.2s done dwell + 0.24s fade)
    //   2. injectedFailure (W3 FailureRegistry seam)
    //   3. engine state via ClusterPhase.fromEngine

    private var derivedPhase: ClusterPhase {
        if let payload = donePayload {
            return .done(appName: payload.appName, preview: payload.preview)
        }
        if let reason = injectedFailure {
            return .failed(reason: reason)
        }
        return ClusterPhase.fromEngine(stateProvider.recordingState)
    }
```

Replace with:

```swift
    // MARK: - Phase derivation
    //
    // Resolution order (highest priority first):
    //   1. donePayload window (1.2s done dwell + 0.24s fade)
    //   2. activeFailure (sourced from FailureRegistry)
    //   3. engine state via ClusterPhase.fromEngine

    private var derivedPhase: ClusterPhase {
        if let payload = donePayload {
            return .done(appName: payload.appName, preview: payload.preview)
        }
        if let event = activeFailure {
            return .failed(reason: event.reason)
        }
        return ClusterPhase.fromEngine(stateProvider.recordingState)
    }
```

- [ ] **Step 9.5: Drop the engine-state failed branch in `handleRecordingStateChange`**

Current (lines 116-129):

```swift
    private func handleRecordingStateChange(_ state: RecordingState) {
        switch state {
        case .starting, .recording:
            if recordingStartedAt == nil {
                recordingStartedAt = .now
            }
        default:
            recordingStartedAt = nil
        }

        if case .failed = state {
            scheduleFailedDwell()
        }
    }
```

Replace with:

```swift
    private func handleRecordingStateChange(_ state: RecordingState) {
        switch state {
        case .starting, .recording:
            if recordingStartedAt == nil {
                recordingStartedAt = .now
            }
        default:
            recordingStartedAt = nil
        }
    }
```

(The `if case .failed` arm is removed because `RecordingState.failed` no longer exists — Task 4. Compile-time enforcement.)

- [ ] **Step 9.6: Replace `scheduleFailedDwell` + add `handleFailureEvent`**

Current (lines 150-170):

```swift
    private func scheduleFailedDwell() {
        failedTask?.cancel()
        let dwell = max(0.5, failedDwellSeconds)
        failedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(dwell * 1000)))
            guard !Task.isCancelled else { return }
            injectedFailure = nil
            // Engine .failed already collapses to .idle on its own
            // (engine-side dwell). Cluster only manages the optional
            // injected failure timer.
        }
    }

    // MARK: - W3 seam

    /// W3 wires `FailureRegistry.publish(reason:)` to call this.
    /// W2 ships it unwired so the cluster is testable in isolation.
    func injectFailure(reason: String) {
        injectedFailure = reason
        scheduleFailedDwell()
    }
```

Replace with:

```swift
    private func handleFailureEvent(_ event: FailureEvent?) {
        failedTask?.cancel()
        activeFailure = event
        guard let event else { return }
        scheduleFailedDwell(for: event.id)
    }

    /// Auto-ack timer for the cluster's `.failed` dwell. Three modes:
    ///   • finite dwell (3.0 / 6.0) → sleep then `failureRegistry.acknowledge`
    ///   • `.infinity` sentinel → no auto-ack; wait for retry success or
    ///     OPEN SETTINGS (which clears the registry via the notification
    ///     observer wired in `FailureRegistry.installSettingsAckObserver`).
    private func scheduleFailedDwell(for id: UUID) {
        let dwell = failedDwellSeconds
        guard dwell.isFinite else { return }
        let bounded = max(0.5, dwell)
        failedTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(bounded * 1000)))
            guard !Task.isCancelled else { return }
            failureRegistry.acknowledge(id)
        }
    }
```

- [ ] **Step 9.7: Update `handleRetry` doc comment**

Current (lines 174-179):

```swift
    private func handleRetry() {
        // W2 stub. W3's FailureRegistry will define retry semantics.
        // For now, clear the injected failure so the cluster retracts —
        // the engine state machine handles real recovery via hotkey.
        injectedFailure = nil
    }
```

Replace with:

```swift
    private func handleRetry() {
        // RETRY chip is informational + visual. Per spec §3 + lead's pin
        // on point 11: ack ONLY on retry success — so the dot stays if the
        // retry also fails. The user re-records via the existing toggle
        // hotkey path; the registry clears on the next clean run via
        // `clearAll` from `runPipeline`.
    }
```

- [ ] **Step 9.8: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Recorder/Constellation/ConstellationCluster.swift | head -120
```

Expected: addition of `@EnvironmentObject failureRegistry`; replacement of `injectedFailure` with `activeFailure`; addition of `.onReceive(failureRegistry.$current)`; deletion of `injectFailure(reason:)` seam; reworked `scheduleFailedDwell` honoring the `.infinity` sentinel.

---

### Task 10: Update `ClusterPhase` engine bridge

**Files:**
- Modify: `VoiceInk/Views/Recorder/Constellation/ClusterPhase.swift`

- [ ] **Step 10.1: Drop the `.failed` arm from `fromEngine(_:)`**

Current (lines 48-63):

```swift
extension ClusterPhase {
    static func fromEngine(_ state: RecordingState) -> ClusterPhase {
        switch state {
        case .idle, .busy:
            return .idle
        case .starting, .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .enhancing:
            return .enhancing
        case .failed(let reason):
            return .failed(reason: reason)
        }
    }
}
```

Replace with:

```swift
extension ClusterPhase {
    /// Engine-side `RecordingState` no longer carries a `.failed` case
    /// (Path B / W3). Failures now arrive on `ConstellationCluster` via
    /// `FailureRegistry.$current` and feed `ClusterPhase.failed` separately
    /// from this bridge. This function never returns `.failed`.
    static func fromEngine(_ state: RecordingState) -> ClusterPhase {
        switch state {
        case .idle, .busy:
            return .idle
        case .starting, .recording:
            return .recording
        case .transcribing:
            return .transcribing
        case .enhancing:
            return .enhancing
        }
    }
}
```

(`ClusterPhase.failed(reason: String?)` itself stays — it's still produced by `ClusterChips.chips(...)` when the orchestrator's `derivedPhase` resolves to `.failed`.)

- [ ] **Step 10.2: Update the comment header above `fromEngine`**

Current (lines 41-46):

```swift
// MARK: - RecordingState bridge
//
// Engine-side `RecordingState` → cluster `ClusterPhase`. `.busy` collapses to
// `.idle` (matches v1 ConstellationContainer.derivedPhase). `.failed(reason)`
// preserves the reason. `.done` is NOT derived here — done synthesis lives
// on the orchestrator (PasteEvent freshness window).
```

Replace with:

```swift
// MARK: - RecordingState bridge
//
// Engine-side `RecordingState` → cluster `ClusterPhase`. `.busy` collapses to
// `.idle` (matches v1 ConstellationContainer.derivedPhase). Failure no longer
// flows through here — Path B / W3 sources `.failed` from `FailureRegistry`
// at the orchestrator. `.done` is NOT derived here — done synthesis lives
// on the orchestrator (PasteEvent freshness window).
```

---

### Task 11: Add menubar failed-dot variant

**Files:**
- Modify: `VoiceInk/Views/Common/MenuBarIconRenderer.swift`

- [ ] **Step 11.1: Add an overload that takes `unresolvedFailures: Int`**

Insert immediately after the existing `image(for:)` method (after line 59):

```swift
    /// Failure-aware variant. When `unresolvedFailures > 0`, renders the
    /// recording-tinted waveform plus a 4pt tangerine dot in the upper-right
    /// of the 18pt canvas. Drawn by hand via `NSImage.lockFocus` — no asset
    /// dependency. Spec §3 (Idle — menubar dot variant).
    static func image(for state: IconState, unresolvedFailures: Int) -> NSImage {
        guard unresolvedFailures > 0 else {
            return image(for: state)
        }
        return failed(label: failedAccessibilityLabel(for: state, count: unresolvedFailures))
    }

    private static func failed(label: String) -> NSImage {
        let cfg = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(Palette.accent)]))
        let glyph = (NSImage(systemSymbolName: "waveform", accessibilityDescription: label)?
            .withSymbolConfiguration(cfg)) ?? NSImage()

        let canvas = NSImage(size: NSSize(width: pointSize, height: pointSize))
        canvas.lockFocus()
        defer { canvas.unlockFocus() }

        let glyphSize = glyph.size
        let originX = (pointSize - glyphSize.width) / 2.0
        let originY = (pointSize - glyphSize.height) / 2.0
        glyph.draw(in: NSRect(x: originX, y: originY, width: glyphSize.width, height: glyphSize.height))

        let dotDiameter: CGFloat = 4.0
        let dotInset: CGFloat = 1.0
        let dotRect = NSRect(
            x: pointSize - dotDiameter - dotInset,
            y: pointSize - dotDiameter - dotInset,
            width: dotDiameter,
            height: dotDiameter
        )
        NSColor(Palette.accent).setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        canvas.isTemplate = false
        canvas.accessibilityDescription = label
        return canvas
    }

    private static func failedAccessibilityLabel(for state: IconState, count: Int) -> String {
        let suffix = count == 1 ? "1 unresolved failure" : "\(count) unresolved failures"
        switch state {
        case .recording:    return "VoiceInk recording, \(suffix)"
        case .transcribing: return "VoiceInk transcribing, \(suffix)"
        case .enhancing:    return "VoiceInk enhancing, \(suffix)"
        case .idle:         return "VoiceInk idle, \(suffix)"
        }
    }
```

- [ ] **Step 11.2: Update `RecordingStateObserver` to track unresolved count**

Current (lines 100-119):

```swift
final class RecordingStateObserver: ObservableObject {
    @Published private(set) var iconState: MenuBarIconRenderer.IconState = .idle
    private var cancellable: AnyCancellable?

    @MainActor
    func bind(to engine: VoiceInkEngine) {
        cancellable?.cancel()
        cancellable = engine.$recordingState
            .receive(on: DispatchQueue.main)
            .map(MenuBarIconRenderer.IconState.init)
            .removeDuplicates()
            .sink { [weak self] next in
                self?.iconState = next
            }
    }

    deinit {
        cancellable?.cancel()
    }
}
```

Replace with:

```swift
final class RecordingStateObserver: ObservableObject {
    @Published private(set) var iconState: MenuBarIconRenderer.IconState = .idle
    @Published private(set) var unresolvedFailures: Int = 0

    private var stateCancellable: AnyCancellable?
    private var registryCancellable: AnyCancellable?

    @MainActor
    func bind(to engine: VoiceInkEngine) {
        stateCancellable?.cancel()
        stateCancellable = engine.$recordingState
            .receive(on: DispatchQueue.main)
            .map(MenuBarIconRenderer.IconState.init)
            .removeDuplicates()
            .sink { [weak self] next in
                self?.iconState = next
            }
    }

    @MainActor
    func bind(toRegistry registry: FailureRegistry) {
        registryCancellable?.cancel()
        registryCancellable = registry.$unresolvedCount
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] next in
                self?.unresolvedFailures = next
            }
    }

    deinit {
        stateCancellable?.cancel()
        registryCancellable?.cancel()
    }
}
```

- [ ] **Step 11.3: Update `MenuBarIcon` SwiftUI label**

Current (lines 129-145):

```swift
struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver

    var body: some View {
        Image(nsImage: MenuBarIconRenderer.image(for: observer.iconState))
            .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        switch observer.iconState {
        case .idle:         return "VoiceInk idle"
        case .recording:    return "VoiceInk recording"
        case .transcribing: return "VoiceInk transcribing"
        case .enhancing:    return "VoiceInk enhancing"
        }
    }
}
```

Replace with:

```swift
struct MenuBarIcon: View {
    @ObservedObject var observer: RecordingStateObserver

    var body: some View {
        Image(
            nsImage: MenuBarIconRenderer.image(
                for: observer.iconState,
                unresolvedFailures: observer.unresolvedFailures
            )
        )
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        let base: String = {
            switch observer.iconState {
            case .idle:         return "VoiceInk idle"
            case .recording:    return "VoiceInk recording"
            case .transcribing: return "VoiceInk transcribing"
            case .enhancing:    return "VoiceInk enhancing"
            }
        }()
        guard observer.unresolvedFailures > 0 else { return base }
        let suffix = observer.unresolvedFailures == 1
            ? "1 unresolved failure"
            : "\(observer.unresolvedFailures) unresolved failures"
        return "\(base), \(suffix)"
    }
}
```

- [ ] **Step 11.4: Update DEBUG preview harness (optional but mirrors spec)**

Current (lines 149-180): the `MenuBarIconPreviewHarness` only previews state. Add a count slider so the failed-dot variant is visible in Xcode previews.

Replace lines 149-180 with:

```swift
#if DEBUG
private struct MenuBarIconPreviewHarness: View {
    @State private var state: MenuBarIconRenderer.IconState = .idle
    @State private var unresolved: Int = 0

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: MenuBarIconRenderer.image(for: state, unresolvedFailures: unresolved))
                .frame(width: 64, height: 64)

            Picker("", selection: $state) {
                Text("Idle").tag(MenuBarIconRenderer.IconState.idle)
                Text("Recording").tag(MenuBarIconRenderer.IconState.recording)
                Text("Transcribing").tag(MenuBarIconRenderer.IconState.transcribing)
                Text("Enhancing").tag(MenuBarIconRenderer.IconState.enhancing)
            }
            .pickerStyle(.segmented)

            Stepper("Unresolved: \(unresolved)", value: $unresolved, in: 0...5)
        }
        .padding(32)
        .frame(width: 360)
    }
}

#Preview("Menu bar icon — Onyx") {
    MenuBarIconPreviewHarness()
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
}

#Preview("Menu bar icon — Light") {
    MenuBarIconPreviewHarness()
        .background(Color(red: 0.93, green: 0.94, blue: 0.96))
}
#endif
```

---

### Task 12: Add Settings UI (failure dwell picker)

**Files:**
- Modify: `VoiceInk/Views/Settings/SettingsView.swift`

- [ ] **Step 12.1: Add the AppStorage binding to `SettingsView`**

Add a new `@AppStorage` near the existing ones (around line 39):

```swift
    @AppStorage("failedDwellSeconds") private var failedDwellSeconds: Double = 6.0
```

- [ ] **Step 12.2: Append a `SettingsRow` to `recordingFeedbackCard`**

Current — the card body ends with the `Use AppleScript Paste` row at line 304. Add a new row immediately before the closing `}` of `recordingFeedbackCard` (after line 304, before the closing brace of the `SettingsCard { ... }` block):

```swift
            SettingsRow(
                iconSystemName: "exclamationmark.triangle",
                label: "Failure Dwell",
                subtitle: "How long the recorder shows a failure before retracting. Until-dismissed keeps the menubar dot until you open Settings or the next recording succeeds.",
                iconTint: Palette.accent
            ) {
                Picker("", selection: $failedDwellSeconds) {
                    Text("3 seconds").tag(3.0)
                    Text("6 seconds").tag(6.0)
                    Text("Until dismissed").tag(Double.infinity)
                }
                .labelsHidden()
                .fixedSize()
            }
```

- [ ] **Step 12.3: Diff inspection**

```bash
git --no-pager diff VoiceInk/Views/Settings/SettingsView.swift | head -40
```

Expected: one new `@AppStorage` line + one new `SettingsRow` block inside `recordingFeedbackCard`. No other edits.

---

### Task 13: DI wiring in `VoiceInk.swift`

**Files:**
- Modify: `VoiceInk/VoiceInk.swift`

- [ ] **Step 13.1: Add the `@StateObject` declaration**

Add a new line near the other `@StateObject` declarations (after line 24's `enhancementService` declaration):

```swift
    @StateObject private var failureRegistry: FailureRegistry
```

- [ ] **Step 13.2: Build the registry in `init()` and attach to engine**

Insert immediately after line 124 (after engine construction) and before line 127 (`recorderUIManager.configure(...)`):

```swift
        // Path B failure routing — registry remembers unresolved failures
        // for the cluster + menubar dot. Subscribe to the engine before any
        // UI mounts. Spec §4 / §5 surface #3.
        let failureRegistry = FailureRegistry()
        failureRegistry.attach(to: engine.failurePublisher.eraseToAnyPublisher())
        _failureRegistry = StateObject(wrappedValue: failureRegistry)
```

- [ ] **Step 13.3: Update the `recorderUIManager.configure` call**

Current (line 127):

```swift
        recorderUIManager.configure(engine: engine, recorder: engine.recorder)
```

Replace with:

```swift
        recorderUIManager.configure(engine: engine, recorder: engine.recorder, failureRegistry: failureRegistry)
```

- [ ] **Step 13.4: Bind menubar observer to the registry**

Current (line 168):

```swift
        appDelegate.recordingStateObserver.bind(to: engine)
```

Replace with:

```swift
        appDelegate.recordingStateObserver.bind(to: engine)
        appDelegate.recordingStateObserver.bind(toRegistry: failureRegistry)
```

- [ ] **Step 13.5: Inject the environment object into both window groups + the menubar extra**

Three insertion points. Add `.environmentObject(failureRegistry)` immediately after the existing `.environmentObject(enhancementService)` line in each:

**ContentView block — after line 273:**

```swift
                    .environmentObject(enhancementService)
                    .environmentObject(failureRegistry)
                    .modelContainer(container)
```

**OnboardingView block — after line 327:**

```swift
                    .environmentObject(enhancementService)
                    .environmentObject(failureRegistry)
                    .frame(minWidth: 880, minHeight: 780)
```

**MenuBarExtra block — after line 358:**

```swift
                .environmentObject(enhancementService)
                .environmentObject(failureRegistry)
        } label: {
```

- [ ] **Step 13.6: Add Combine import if missing**

The file already imports `SwiftUI` etc. `eraseToAnyPublisher()` requires `Combine`. Check the import block at the top of the file. If `import Combine` is missing, add it after `import SwiftData`:

```bash
grep -n "^import " VoiceInk/VoiceInk.swift | head
```

If `Combine` is not in the list, insert it. Otherwise skip.

---

### Task 14: Add success-path ack in engine

**Files:**
- Modify: `VoiceInk/Transcription/Engine/VoiceInkEngine.swift`

The engine should clear the registry on a clean run so the menubar dot vanishes after a successful retry. This is the only auto-ack path that requires a registry reference inside the engine.

- [ ] **Step 14.1: Inject the registry via init**

Current init signature (lines 57-62):

```swift
    init(
        modelContext: ModelContext,
        whisperModelManager: WhisperModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        enhancementService: AIEnhancementService? = nil
    ) {
```

Replace with:

```swift
    init(
        modelContext: ModelContext,
        whisperModelManager: WhisperModelManager,
        transcriptionModelManager: TranscriptionModelManager,
        enhancementService: AIEnhancementService? = nil,
        failureRegistry: FailureRegistry
    ) {
```

Add a stored property near `enhancementService` (around line 52):

```swift
    private let failureRegistry: FailureRegistry
```

Add the assignment in the init body, immediately after `self.enhancementService = enhancementService` (around line 66):

```swift
        self.failureRegistry = failureRegistry
```

- [ ] **Step 14.2: Clear registry on successful pipeline tail**

Update `runPipeline` — the new tail logic from Task 3 step 5. Current (post-Task 3):

```swift
        shouldCancelRecording = false
        if recordingState != .idle {
            recordingState = .idle
        }
    }
```

Replace with:

```swift
        shouldCancelRecording = false
        if recordingState != .idle {
            recordingState = .idle
        }
        // Path B: a clean run acks any unresolved failures so the menubar
        // dot clears on retry-success. Failures during this same run came
        // through `failurePublisher` and live on the registry; if the run
        // reached this tail without `onFailure` firing, the user observed
        // a successful end-to-end pipeline.
        failureRegistry.clearAll()
    }
```

(Note: the success-on-tail check is naive — even a partial-success run with a non-fatal enhancement failure reaches here. That matches the spec's intent: a run that reached paste is "successful enough" to ack the dot. The cluster's reason chip already tells the user about the enhancement fallback.)

- [ ] **Step 14.3: Update the `VoiceInk.swift` engine construction call**

Current (lines 119-124):

```swift
        let engine = VoiceInkEngine(
            modelContext: container.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager,
            enhancementService: enhancementService
        )
```

Replace with — note: `failureRegistry` must be built BEFORE `engine` since the engine takes it as an init param. Reorder the Task 13 step 2 insertion to come BEFORE the engine construction:

```swift
        // Path B failure routing — registry remembers unresolved failures
        // for the cluster + menubar dot. Built before the engine so the
        // engine can ack on successful runs. Spec §4 / §5 surface #3.
        let failureRegistry = FailureRegistry()

        let engine = VoiceInkEngine(
            modelContext: container.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager,
            enhancementService: enhancementService,
            failureRegistry: failureRegistry
        )

        // Engine is now constructed — wire the publisher subscription.
        failureRegistry.attach(to: engine.failurePublisher.eraseToAnyPublisher())
        _failureRegistry = StateObject(wrappedValue: failureRegistry)
```

(This supersedes Task 13 step 2's draft — final ordering is built-registry → built-engine → attach publisher → wrap as StateObject.)

---

### Task 15: Tests (`FailureRegistryTests.swift`)

**Files:**
- Create: `VoiceInkTests/FailureRegistryTests.swift`

- [ ] **Step 15.1: Write the file**

```swift
import Testing
import Combine
@testable import VoiceInk

@MainActor
struct FailureRegistryTests {

    @Test func publishIncrementsUnresolvedAndSetsCurrent() async throws {
        let registry = FailureRegistry()
        #expect(registry.unresolvedCount == 0)
        #expect(registry.current == nil)

        registry.publish(reason: "First")
        #expect(registry.unresolvedCount == 1)
        #expect(registry.current?.reason == "First")

        registry.publish(reason: "Second")
        #expect(registry.unresolvedCount == 2)
        #expect(registry.current?.reason == "Second")
    }

    @Test func acknowledgeMatchingIdClearsCurrent() async throws {
        let registry = FailureRegistry()
        registry.publish(reason: "Boom")
        let id = try #require(registry.current?.id)

        registry.acknowledge(id)
        #expect(registry.current == nil)
        #expect(registry.unresolvedCount == 0)
    }

    @Test func acknowledgeNonMatchingIdLeavesCurrentButDecrements() async throws {
        let registry = FailureRegistry()
        registry.publish(reason: "Boom")
        let foreignId = UUID()

        registry.acknowledge(foreignId)
        // current stays — id didn't match the latest event
        #expect(registry.current?.reason == "Boom")
        // unresolvedCount still decrements; ack semantics are "user saw something"
        #expect(registry.unresolvedCount == 0)
    }

    @Test func clearAllResetsBoth() async throws {
        let registry = FailureRegistry()
        registry.publish(reason: "A")
        registry.publish(reason: "B")
        registry.publish(reason: "C")
        #expect(registry.unresolvedCount == 3)

        registry.clearAll()
        #expect(registry.current == nil)
        #expect(registry.unresolvedCount == 0)
    }

    @Test func attachToPublisherRoutesEvents() async throws {
        let registry = FailureRegistry()
        let subject = PassthroughSubject<FailureEvent, Never>()
        registry.attach(to: subject.eraseToAnyPublisher())

        subject.send(FailureEvent(reason: "From publisher"))
        // Allow the receive(on: DispatchQueue.main) hop to land.
        await Task.yield()

        #expect(registry.current?.reason == "From publisher")
        #expect(registry.unresolvedCount == 1)
    }
}
```

- [ ] **Step 15.2: Add file to Xcode test target**

```bash
ruby -e '
require "xcodeproj"
project = Xcodeproj::Project.open("VoiceInk.xcodeproj")
target = project.targets.find { |t| t.name == "VoiceInkTests" }
group = project.main_group
group = group.find_subpath("VoiceInkTests", false) || (raise "missing group VoiceInkTests")
file_ref = group.new_reference("FailureRegistryTests.swift")
target.add_file_references([file_ref])
project.save
'
```

- [ ] **Step 15.3: Verify pbxproj membership**

```bash
grep -c "FailureRegistryTests.swift" VoiceInk.xcodeproj/project.pbxproj
```

Expected: ≥ 1 (PBXFileReference + PBXBuildFile entries).

---

### Task 16: Compile-error sweep

**Files:** none (verification).

- [ ] **Step 16.1: Confirm no remaining `RecordingState.failed` references**

```bash
grep -rn "case \.failed\|case .failed\|\.failed(reason" VoiceInk --include="*.swift"
```

Expected: only the unrelated enums listed in Task 0 step 1 (`CoreAudioRecorder`, `AudioFileRow`, `PromptLivePreview`, `ConstellationOrb`/`Chip`/`Card`, `HaloMaterial`, `MLXModelPickerView`, `AudioFileTranscriptionManager`). Specifically — none of these:

- `Transcription/Engine/VoiceInkEngine.swift`
- `Transcription/Engine/TranscriptionPipeline.swift`
- `Transcription/Engine/RecorderUIManager.swift`
- `Transcription/Engine/RecordingState.swift`
- `Views/Recorder/RecorderStateProvider.swift`
- `Views/Recorder/Constellation/ConstellationCluster.swift`

If the grep surfaces any of those, the corresponding task didn't fully apply.

- [ ] **Step 16.2: Confirm `failureReason` accessor is gone**

```bash
grep -rn "failureReason" VoiceInk --include="*.swift"
```

Expected: zero matches.

- [ ] **Step 16.3: Confirm `failedDwellSeconds` is consumed in exactly two places**

```bash
grep -rn "failedDwellSeconds" VoiceInk --include="*.swift"
```

Expected: two matches —
- `VoiceInk/Views/Recorder/Constellation/ConstellationCluster.swift` (`@AppStorage` + dwell decision)
- `VoiceInk/Views/Settings/SettingsView.swift` (`@AppStorage` + Picker binding)

- [ ] **Step 16.4: Confirm `failurePublisher` references**

```bash
grep -rn "failurePublisher" VoiceInk --include="*.swift"
```

Expected matches:
- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` (declaration + 3 `send` sites + 1 `pipeline.run` `onFailure` callback site)
- `VoiceInk/VoiceInk.swift` (`registry.attach(to: engine.failurePublisher.eraseToAnyPublisher())`)

- [ ] **Step 16.5: Confirm `FailureRegistry` references**

```bash
grep -rn "FailureRegistry" VoiceInk VoiceInkTests --include="*.swift"
```

Expected matches:
- `VoiceInk/Services/FailureRegistry.swift` (definition)
- `VoiceInk/Transcription/Engine/VoiceInkEngine.swift` (init param + stored property)
- `VoiceInk/Transcription/Engine/RecorderUIManager.swift` (configure param + stored property + sink)
- `VoiceInk/Views/Recorder/Constellation/ConstellationCluster.swift` (`@EnvironmentObject`)
- `VoiceInk/Views/Common/MenuBarIconRenderer.swift` (RecordingStateObserver bind method)
- `VoiceInk/VoiceInk.swift` (`@StateObject` + construction + injection)
- `VoiceInkTests/FailureRegistryTests.swift` (tests)

- [ ] **Step 16.6: Confirm pbxproj includes new files**

```bash
grep -c "FailureEvent.swift\|FailureRegistry.swift\|FailureRegistryTests.swift" VoiceInk.xcodeproj/project.pbxproj
```

Expected: ≥ 6 (each file has at least one PBXFileReference + one PBXBuildFile entry).

---

### Task 17: Full integration build (the gate)

**Files:** none.

- [ ] **Step 17.1: Run `make local`**

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
grep -nE "^.* error:" /tmp/voiceink-build.log | head -20
```

Common diagnostics:
- `cannot find 'FailureRegistry' in scope` → Task 2 file isn't in the target; check pbxproj.
- `enum case '.failed' not found in 'RecordingState'` → a consumer was missed; re-run Task 16 step 1 and fix.
- `value of type 'VoiceInkEngine' has no member 'failurePublisher'` → Task 3.3 didn't apply; re-check the diff.
- `extra argument 'failureRegistry' in call` → Task 14.3 ordering wrong; ensure the registry is built before the engine.

- [ ] **Step 17.2: Run the test suite**

```bash
xcodebuild test -project VoiceInk.xcodeproj -scheme VoiceInk -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: `Test Suite 'FailureRegistryTests' passed` with 5 tests (one per `@Test`). Existing `PaletteTests` should also remain green.

- [ ] **Step 17.3: Sanity-launch the app**

```bash
/usr/bin/killall VoiceInk 2>/dev/null
open ~/Downloads/VoiceInk.app
sleep 3
ps aux | grep -E "/VoiceInk\.app/Contents/MacOS/VoiceInk" | grep -v grep | head -1
```

Expected: a running process. Manually:
- Hit the recorder hotkey, force a failure (e.g. unplug mic mid-record, or trigger an enhancement key error). Confirm:
  - Cluster shows FAIL anchor + reason chip + RETRY + OPEN SETTINGS chips.
  - Menubar icon swaps to tangerine waveform + 4pt dot in upper-right.
  - At default `failedDwellSeconds = 6.0`, cluster retracts after 6s; menubar dot persists.
- Open Settings via the menubar Settings menu → menubar dot clears.
- Trigger another failure → both surfaces show.
- Successfully record and have a clean run → menubar dot clears.
- Set Settings → "Failure Dwell" → "Until dismissed". Trigger a failure → cluster persists. Click OPEN SETTINGS → cluster + dot both clear.
- Set Settings → "Failure Dwell" → "3 seconds". Trigger a failure → cluster retracts after 3s; menubar dot persists.

- [ ] **Step 17.4: VoiceOver verification**

Cmd+F5 to enable VoiceOver. With an unresolved failure, focus the menubar icon. VO should read: "VoiceInk recording, 1 unresolved failure" (or `idle` if not recording). Cmd+F5 to disable.

- [ ] **Step 17.5: Reduce-Motion verification**

System Settings → Accessibility → Display → Reduce Motion ON. Trigger a failure. Cluster mounts with 0.18s opacity (from W2's `clusterFadeReduced`). The menubar dot is static (no animation). Toggle off — animations resume on the next event.

- [ ] **Step 17.6: Report status to lead — DO NOT commit**

Per CLAUDE.md, no commits during execution. Report:

```
W3 failure routing: BUILD GREEN, TESTS GREEN
- New: FailureEvent, FailureRegistry, FailureRegistryTests
- Engine: failedDwell* dropped, failurePublisher added, .failed→idle on every error
- RecordingState: .failed case removed
- Pipeline: onFailure callback wired
- RecorderUIManager: poll loop dropped, cue sink rewired to registry
- ConstellationCluster: subscribes to registry.$current, honors .infinity sentinel
- MenuBar: failed-dot variant rendered, observer binds count
- Settings: Failure Dwell row in recordingFeedbackCard (3s/6s/Until-dismissed)
- DI: registry built in VoiceInk.swift, attached to engine, injected into 3 surfaces
- Auto-ack: Settings open via .navigateToDestination + clean pipeline run
- Diff: <git diff --stat | tail -1>
```

Lead reviews diff, decides whether to commit.

---

## Self-review

- [x] **Spec coverage.**
  - §3 Idle — menubar dot variant: hand-drawn 4pt tangerine dot via `NSImage.lockFocus`, gated on `unresolvedCount > 0`. (Task 11) ✓
  - §4 State grammar — failed dwell row + 3s/6s/Until-dismissed picker: `SettingsRow` in `recordingFeedbackCard` with three options including `Double.infinity`. (Task 12) ✓
  - §4 Failure routing — single source of truth: `FailureRegistry` subscribed by both cluster and menubar. Cluster's dwell + menubar's persistence are independent lifetimes. (Tasks 2, 9, 11) ✓
  - §5 surface #2 (menubar icon — failure-dot overlay): `MenuBarIconRenderer.image(for:unresolvedFailures:)`. (Task 11) ✓
  - §5 surface #3 (failure routing — `FailureRegistry`, pipeline calls swapped): all four call sites swapped (engine 139/234/260, pipeline 166/182). (Tasks 3, 6) ✓
  - Auto-ack on retry-success and Settings-open: engine clears registry at clean tail; registry observes `.navigateToDestination`. (Tasks 14, 2) ✓

- [x] **Path B architecture intact.**
  - Engine emits one-shot events, never sustains `.failed`. (Task 3) ✓
  - Registry is session-scoped, no persistence. (Task 2 doc comment) ✓
  - Cluster + menubar subscribe independently. (Tasks 9, 11) ✓
  - "Until-dismissed" sentinel = `Double.infinity` in single AppStorage key. (Task 9 step 6, Task 12 step 2) ✓
  - RETRY chip does NOT immediately ack — waits for retry success. (Task 9 step 7) ✓
  - Engine does not import `FailureRegistry` for publish; only for the success-tail clearAll (Task 14, justified by lead's design point 11). The publisher is external-subscription only.

- [x] **Placeholder scan.** No `TBD`, no "implement later", no "similar to Task N", no "add error handling". Every step has exact code, exact file:line, or exact command.

- [x] **Type consistency.**
  - `FailureEvent` ↔ `FailureRegistry` consistent across all consumers.
  - `Double.infinity` sentinel used uniformly (Task 9 dwell logic, Task 12 Picker tag).
  - `Palette.accent` token from W1 reused for menubar dot (Task 11) — no new color tokens introduced.
  - `RecordingState` reduced to 6 cases — switch sites in `HotkeyManager`, `MenuBarView`, `RecorderUIManager` keep working because they all use `==` against non-failed cases or have a `default:` arm (verified Task 0 step 2).

- [x] **Constructor stability.**
  - `ConstellationContainer<S>` 4-input constructor preserved.
  - `MiniWindowManager` / `NotchWindowManager` / `HaloRecorderView` not edited.
  - `VoiceInkEngine.init` gains a `failureRegistry` param — the only call site is `VoiceInk.swift` (verified). External callers (none in-tree) would need to update, but no other call site exists.

- [x] **Onboarding compliance.**
  - `OnboardingView` injection added (Task 13 step 5). `CinematicWalkthrough` does not reference `FailureRegistry`; the env object is harmless if unused.
  - Legacy `ConstellationCard` / `Chip` / `Orb` / `HaloMaterial` `.failed` arms are on `HaloPhase`, not `RecordingState` — untouched.

- [x] **Build cadence.** No `make local` between tasks; one full build at Task 17.1 per CLAUDE.md.

- [x] **No commits.** Final step reports to lead.

- [x] **No emoji in code.** All chip/menubar surfaces use SF Symbols (`waveform`, `exclamationmark.triangle`) or Unicode glyphs; no emoji literals introduced.

- [x] **Sentence-fragment commits, no PR-reference comments.** All inline comments use the codebase's style — short prose, no `// PR #123` references, no obvious-explainer comments.

---

## Acceptance criteria

- ✅ `make local` completes with `** BUILD SUCCEEDED **`.
- ✅ `xcodebuild test` passes — `FailureRegistryTests` (5 cases) + `PaletteTests` both green.
- ✅ `RecordingState` enum has 6 cases (idle / starting / recording / transcribing / enhancing / busy). No `.failed` case.
- ✅ `VoiceInkEngine.failurePublisher` exists and emits `FailureEvent`. Engine's `recordingState` returns to `.idle` immediately on every error path.
- ✅ `FailureRegistry.publish` / `acknowledge` / `clearAll` work as covered by the test suite.
- ✅ `ConstellationCluster` shows the failed UI when `failureRegistry.current` is non-nil; respects 3s / 6s / `Double.infinity` AppStorage values.
- ✅ Menubar icon renders the tangerine waveform + 4pt dot variant when `unresolvedCount > 0`. Dot persists past the cluster's dwell at 3s and 6s settings.
- ✅ Auto-ack: clean pipeline run clears the registry; opening Settings clears the registry.
- ✅ RETRY chip does NOT immediately ack — only retry-success acks via the engine tail.
- ✅ Settings → Recording Feedback card has a "Failure Dwell" row with three options (3 seconds / 6 seconds / Until dismissed), bound to `@AppStorage("failedDwellSeconds")`.
- ✅ VoiceOver reads "VoiceInk \<state\>, N unresolved failures" when the dot is visible.
- ✅ Sweep `grep -rn "case \.failed\|case .failed\|\.failed(reason" VoiceInk --include="*.swift"` returns ONLY matches on unrelated enums (verified list in Task 0 step 1).
- ✅ Sweep `grep -rn "failureReason" VoiceInk --include="*.swift"` returns 0 matches.

## Estimated effort

~5-6 hours for an engineer familiar with the codebase. ~7-8 hours for a fresh teammate (most of the time is the engine refactor + DI re-wiring + integration verification, not algorithm complexity). The new file count is small (3 files); the cross-file rewiring is the bulk of the work.
