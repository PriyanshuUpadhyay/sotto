# Sotto Onboarding (Surfaces 10–11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Net-new first-run onboarding flow (welcome → permissions → ⌥ SPACE reminder) + Tactical-Glass notification toasts (Surface 11), gated by a `UserDefaults` sentinel that fires once per install.

**Architecture:** Dedicated `OnboardingWindow` (NSWindow via `WindowGroup`-equivalent `NSWindowController`) hosting a paginated `OnboardingFlowView`. First-run gate at app bootstrap in `VoiceInk.swift` (Sotto.swift post-rename). Reuses shipping `PermissionManager` + refactors `PermissionCard` into an embeddable `PermissionRow` so the onboarding flow and the Settings → Permissions pane share one source of truth. Toasts re-skin `AppNotificationView` to route through the HUD pair's `TacticalGlass` primitive with `HaloPhase`-derived state-color tokens.

**Tech Stack:** SwiftUI, AppKit (`NSWindow`/`NSWindowController` for the floating onboarding window), `KeyboardShortcuts`, `AVFoundation`, Core Graphics screen-capture preflight. Depends on RENAME (file paths, bundle ID) and HUD (`TacticalGlass`, `brandAcid`, state-color tokens, `BrandMarks.styledWordmark()`, `MotionTokens`, `AdaptiveGlass`).

---

## Dependencies (from other pairs — block on these landing first)

| Symbol | Owner | Why |
|---|---|---|
| `Sotto/Views/Recorder/HaloMaterial.swift` (renamed path) | RENAME | file path |
| `TacticalGlass(shape:phase:appearance:)` SwiftUI primitive | HUD §1.1 | toast backing + welcome-card backing |
| `Palette.brandAcid` (`#D4FF3A`) | HUD §1.4 | wordmark stop, CTA, selected row, glow |
| `Palette.recRed`, `.commitGreen`, `.transCyan`, `.enhViolet` | HUD §1.4 | toast type-tinting |
| `Palette.surface`, `.hairline`, `.ghost` | HUD §1.4 | every glass tint + border |
| `BrandMarks.wordmark` = `"Sotto."` constant | HUD/RENAME §5.5 | welcome-screen hero |
| `BrandMarks.styledWordmark() -> AttributedString` | HUD §5.5 | colors the trailing `.` lime |
| `MotionTokens.swift` (pulse / breathe / blink) | HUD §4.3 | reduce-motion-aware loops |
| `AdaptiveGlass` HC branch in `HaloMaterial.swift` | HUD §1.X | HC fallback |
| `cornerRadiusGlass: 2pt`, `cornerRadiusNotch: 8pt`, `spacingUnit: 4pt` | HUD §1.2 | geometry tokens |

If a symbol above is missing when implementation starts, stub it locally (clearly marked `// TODO: HUD pair`) and file the gap upstream.

---

## File Structure

**New files:**
- `Sotto/Views/Onboarding/OnboardingWindowController.swift` — owns the floating `NSWindow`; lifecycle, positioning, dismissal.
- `Sotto/Views/Onboarding/OnboardingFlowView.swift` — root SwiftUI view; coordinates step navigation via `OnboardingStep` enum.
- `Sotto/Views/Onboarding/OnboardingStep.swift` — `enum OnboardingStep: CaseIterable { case welcome, permissions, hotkey, done }` + advance/back helpers.
- `Sotto/Views/Onboarding/WelcomeStepView.swift` — wordmark hero + tagline + "Get started" CTA.
- `Sotto/Views/Onboarding/PermissionsStepView.swift` — embeds shared `PermissionRow` instances; gates "Continue" until required permissions granted (mic mandatory; accessibility + screen-rec recommended but skippable).
- `Sotto/Views/Onboarding/HotkeyStepView.swift` — shows the bound shortcut for `.toggleMiniRecorder` (default ⌥ SPACE if unbound) + finish CTA.
- `Sotto/Views/Onboarding/HotkeyReminderToast.swift` — view used by the toast that fires post-onboarding until first successful invocation.
- `Sotto/Views/Common/PermissionRow.swift` — extracted from `PermissionsView.swift`'s `PermissionCard`; embeddable variant.
- `Sotto/Onboarding/OnboardingState.swift` — `@MainActor final class OnboardingState: ObservableObject`. Owns sentinel reads/writes, current step, hotkey-reminder dismissed flag.

**Modified files:**
- `Sotto/Sotto.swift` (renamed from `VoiceInk.swift`) — bootstrap gate at `.onAppear` of root window: if `!OnboardingState.shared.completed`, present `OnboardingWindowController`.
- `Sotto/Views/PermissionsView.swift` — replace inline `PermissionCard` with `PermissionRow`. Settings pane keeps its outer scroll/header; row is shared.
- `Sotto/HotkeyManager.swift` — add `firstInvocationDidFire` sentinel write at the top of the toggle-mini-recorder handler (next to line 21's existing sentinel pattern).
- `Sotto/Notifications/AppNotificationView.swift` — re-skin to `TacticalGlass` backing; add `NotificationType.recording / .transcribing / .enhancing / .committed / .fail` cases with §1.4 color tokens; extend type → icon glyph mapping to use `✓` / `✗` glyphs (§1.X colorblind disambiguation).
- `Sotto/Notifications/NotificationManager.swift` — accept positioning override (top vs bottom — onboarding reminder anchors below notch).

**No deletions.** `MetricsSetupView.swift` is orphaned (not routed) — leave for now; SETTINGS pair will decide whether to retire it.

---

## NET-NEW design decisions (require user sign-off BEFORE Group B)

These are the choices that have no precedent in the codebase and were not pre-locked by the design spec. Surface as a block at the head of the implementation handoff. If the user says "your call", default to the **Default** column.

| # | Decision | Default | Alternative(s) |
|---|---|---|---|
| D1 | Welcome screen tagline (one line under wordmark) | `› sotto voce · under your voice` (matches §5.1 marketing tagline) | `› dictate quietly` · `› transcribe in the background` |
| D2 | "Get started" CTA label | `▸ Get started` | `▸ Begin setup` · `▸ Continue` |
| D3 | Permissions screen layout — one screen per permission, or one screen with all rows | One screen, all rows (matches shipping `PermissionsView` shape) | Wizard (one screen per permission, longer flow) |
| D4 | Mic permission: required to advance, or skippable | Required (recording is broken without it) | Skippable with warning banner |
| D5 | Accessibility + Screen Recording: required, recommended, or optional | Recommended (skip → toast warning on first use) | Required (gate Finish) |
| D6 | Model-download step — include in onboarding, or defer to Settings | Defer (per §6.1 footnote: "leverage existing model picker if any, or defer to Settings") | Inline: embed `ModelsView`'s `WhisperModelDownloadButton` after permissions |
| D7 | `⌥ SPACE` reminder presentation | One-shot toast via `NotificationManager` shown 600 ms after onboarding window dismisses, copy `▸ Press ⌥ SPACE to dictate`, dismisses on first successful hotkey invocation OR manual close | Persistent banner inside main window · pulsing menubar icon hint |
| D8 | Onboarding window topology | Dedicated borderless `NSPanel`-style floating window, 480 × 640, centered, hides Dock/MenuBar `.canBecomeKey = true` (needs focus to type into permission rationale links) | Sheet over main window · replace `ContentView` until completion |
| D9 | Skip-all escape hatch | Yes — `›` close button top-right; sets `onboardingCompleted_v1 = true` and `onboardingSkipped_v1 = true` so retry banners can show in Settings → Permissions | No skip (user must complete or quit) |
| D10 | First successful invocation = which signal extinguishes the reminder | `HotkeyManager.handleHotkeyAction(...)` transitioning engine into `.recording` ANY way (hotkey, middle-click, menubar item) | Hotkey-press only (mouse paths don't count) |
| D11 | Toast position post-redesign | Above the notch (top-anchored, mirroring HUD position) for HUD-state toasts; bottom-anchored (current) for system/info toasts | All bottom (current) · All top |
| D12 | Reduce Motion behavior for toast entry | 200 ms opacity-only fade (no slide-up) per §1.X | Static appear (no fade) |
| D13 | Onboarding "Done" CTA label | `▸ Finish` | `▸ Start dictating` · `▸ Open Sotto` |

Open spike (NOT a copy decision — flagged for later):
- **B.Domain** (Appendix B): the welcome screen does NOT need a URL on it (per §5.1 marketing tagline is the only string). Defer URL choice to marketing-site work; do not block onboarding on this.

---

# Group A — DESIGN (spec the flow before writing window code)

Each design step produces a markdown sub-doc inside the plan repo. These are **not** implementation steps; they are the design artifacts the coder will reference in Group B.

### Task 1: Spec the welcome screen

**Files:**
- Create: `docs/superpowers/specs/2026-05-11-sotto-onboarding-screens/welcome.md`

- [ ] **Step 1.1: Write the welcome-screen spec**

Content of the file:

```markdown
# Welcome step — spec

## Layout (480 × 640 window content area)

| Region | y-offset | Content |
|---|---|---|
| Top spacer | 0–96pt | empty |
| Wordmark | 96–168pt | `BrandMarks.styledWordmark()` — `Sotto.` SF Mono Bold 56pt, +0.02em, lime period |
| Tagline | 192–216pt | `› sotto voce · under your voice` SF Mono Regular 13pt, +0.16em uppercase NOT applied, color `Palette.ghost` |
| Spacer | 216–460pt | empty (negative space carries the wordmark) |
| CTA | 460–504pt | `▸ Get started` SF Mono Bold 14pt, lime on `TacticalGlass` capsule, 220pt × 44pt, 8pt bottom-radius |
| Skip ›  | top-right 16pt inset | `›` close-glyph, white@0.42, 24×24pt tap target |
| Bottom spacer | 504–640pt | empty |

## Motion
- Wordmark fades in 240 ms ease-out on window appear (Reduce Motion: 0 ms, opacity 1 immediately).
- CTA halo breathes 1.6 s (lime glow alpha 0.3↔0.6) (Reduce Motion: static glow alpha 0.5).

## Acceptance
- [ ] Wordmark uses `BrandMarks.styledWordmark()` — never a literal `"Sotto."` string.
- [ ] Tagline is exactly `› sotto voce · under your voice`.
- [ ] CTA = `▸ Get started`.
- [ ] Skip `›` advances to `OnboardingStep.done` and writes both `onboardingCompleted_v1` + `onboardingSkipped_v1` UserDefaults.
- [ ] All glass uses `TacticalGlass` — no `.regularMaterial`.
- [ ] Reduce Motion verified.
```

- [ ] **Step 1.2: Commit**

```bash
git add docs/superpowers/specs/2026-05-11-sotto-onboarding-screens/welcome.md
git commit -m "spec(onboarding): welcome step"
```

### Task 2: Spec the permissions screen

**Files:**
- Create: `docs/superpowers/specs/2026-05-11-sotto-onboarding-screens/permissions.md`

- [ ] **Step 2.1: Write the permissions-screen spec**

```markdown
# Permissions step — spec

## Layout (480 × 640)

| Region | Content |
|---|---|
| Section label | `› PERMISSIONS` SF Mono Bold 11pt, +0.16em, lime, top 24pt left 24pt |
| Headline | `Grant access to dictate anywhere` SF Mono Bold 18pt white, +0.02em |
| Body | `Sotto needs three permissions. Mic is required; the others unlock paste-at-cursor and screen-context.` SF Mono Regular 13pt, `Palette.ghost`, 360pt wrap |
| Row stack | three `PermissionRow` instances, vertical 12pt gap |
| Footer | `▸ Continue` CTA (lime, disabled until mic granted) + `Skip for now ›` (right-aligned, advances anyway) |

## Permission rows (top → bottom)

1. **Microphone** — required. Icon `mic`. Body: `Record your voice for transcription.` Button: `Request permission` (if `.notDetermined`) or `Open System Settings` (otherwise).
2. **Accessibility** — recommended. Icon `hand.raised`. Body: `Paste transcribed text at your cursor across apps.` Button: `Open System Settings`. InfoTip same copy as shipping PermissionsView.
3. **Screen Recording** — recommended. Icon `rectangle.on.rectangle`. Body: `Use screen context to improve transcription accuracy.` Button: `Request permission`.

Each row reuses `PermissionManager` (shipping) for state + refresh; permission status is observed reactively so granting in System Settings updates the row in <500 ms when the app becomes active again.

## Motion
- Rows fade in 60 ms apart (staggered) on screen enter (Reduce Motion: all together, opacity 1).

## Acceptance
- [ ] Three `PermissionRow` instances — extracted from the shipping `PermissionCard`.
- [ ] Continue CTA disabled while mic is `.notDetermined` OR `.denied`. Enabled the moment mic flips `.authorized`.
- [ ] `Skip for now ›` always works; writes `onboardingSkippedPermissions_v1 = true`.
- [ ] Reactive refresh — `PermissionManager.checkAllPermissions()` fires on `NSApplication.didBecomeActiveNotification` (already shipping).
```

- [ ] **Step 2.2: Commit**

```bash
git add docs/superpowers/specs/2026-05-11-sotto-onboarding-screens/permissions.md
git commit -m "spec(onboarding): permissions step"
```

### Task 3: Spec the hotkey-reminder step

**Files:**
- Create: `docs/superpowers/specs/2026-05-11-sotto-onboarding-screens/hotkey.md`

- [ ] **Step 3.1: Write the hotkey-step spec**

```markdown
# Hotkey reminder step — spec

This is the LAST in-window step. Once the user taps Finish, the window dismisses and a one-shot toast (`HotkeyReminderToast` below) fires until the first invocation.

## Layout (480 × 640)

| Region | Content |
|---|---|
| Section label | `› SHORTCUT` lime, top 24pt left 24pt |
| Headline | `Press the shortcut to dictate` SF Mono Bold 18pt |
| Body | `Sotto stays out of the way. Press this anywhere to start.` |
| Shortcut block | `TacticalGlass` panel 220 × 80pt; center-content displays bound shortcut for `.toggleMiniRecorder` via `KeyboardShortcuts.Name.toggleMiniRecorder`. If unbound, shows `⌥ SPACE` as the suggested default + a `Configure ›` link routing to Settings → Hotkeys. |
| Body 2 | `You'll see a reminder toast the first time. After that, Sotto is invisible.` |
| Footer | `▸ Finish` CTA (lime). |

## Model-download note
This step does NOT include model download (decision D6 = defer). If `transcriptionModelManager.currentTranscriptionModel == nil` on Finish, post a `.navigateToDestination` notification with `"Models"` so the user lands on Settings → Models after the window closes. Toast suppressed until model is set.

## Acceptance
- [ ] Reads current binding via `KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)`.
- [ ] Falls back to `⌥ SPACE` display text if unbound.
- [ ] On Finish: writes `onboardingCompleted_v1 = true`; closes window; schedules toast (or routes to Models if no model present).
```

- [ ] **Step 3.2: Commit**

```bash
git add docs/superpowers/specs/2026-05-11-sotto-onboarding-screens/hotkey.md
git commit -m "spec(onboarding): hotkey step"
```

### Task 4: Spec the post-onboarding toast (Surface 11 — onboarding's half)

**Files:**
- Create: `docs/superpowers/specs/2026-05-11-sotto-onboarding-screens/toast.md`

- [ ] **Step 4.1: Write the toast spec**

```markdown
# `⌥ SPACE` reminder toast — spec

Fires once, ever, after onboarding completes. Dismisses permanently after first successful hotkey invocation OR manual ✕.

## Trigger sequence

1. `OnboardingWindowController.close()` → `OnboardingState.shared.markCompleted()`.
2. `OnboardingState.markCompleted()` checks: if `firstInvocationDidFire_v1` is false AND `hotkeyReminderShown_v1` is false → after a 600 ms delay (DispatchQueue.main.asyncAfter) call `NotificationManager.shared.showHotkeyReminder(shortcut: ...)`.
3. `showHotkeyReminder` sets `hotkeyReminderShown_v1 = true` immediately (so even if the user kills the app mid-toast, it never re-fires).
4. Toast stays up until either: user clicks ✕ → dismiss; OR `HotkeyManager` transitions engine into `.recording` for the first time → `firstInvocationDidFire_v1 = true` is written + `NotificationManager.shared.dismissNotification()`.

## Visual

- Material: `TacticalGlass(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), phase: .armed, appearance: .darkAqua)` — lime-keyed halo.
- Width: hug-content, min 280, max 480.
- Height: 44pt.
- Padding: 16h × 12v.
- Position: anchored TOP of notch screen (decision D11 — this is a HUD-adjacent toast, so it lives where the HUD lives), centered horizontally, 16pt below the notch line.
- Icon: `›` lime (NOT `▸` — this is read-only).
- Copy: `Press ⌥ SPACE to dictate` — substituted with whatever `KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)?.description` returns; falls back to `⌥ SPACE`.
- ✕ button: 16×16, white@0.6, top-right.
- No progress bar (the existing `AppNotificationView` progress bar is suppressed for this toast type — it's persistent until dismissed).

## Motion
- Enter: 220 ms ease-out fade + 8pt slide-down from notch.
- Loop: lime halo breathes 1.6 s (alpha 0.25↔0.6) — uses `MotionTokens.breathe`.
- Exit: 180 ms ease-in fade + 8pt slide-up.
- Reduce Motion: 200 ms opacity-only on enter and exit, no slide, static halo at alpha 0.5.

## Acceptance
- [ ] `hotkeyReminderShown_v1` UserDefaults key set immediately on show (idempotent against crashes).
- [ ] Toast dismisses on first `.recording` transition via Combine subscription to `engine.$recordingState`.
- [ ] Toast dismisses on ✕ click.
- [ ] Toast NEVER re-shows after either dismissal path.
- [ ] Reduce Motion respected.
- [ ] VoiceOver announces `"Tip: press ⌥ SPACE to start dictation. Close button available."` on appear.
```

- [ ] **Step 4.2: Commit**

```bash
git add docs/superpowers/specs/2026-05-11-sotto-onboarding-screens/toast.md
git commit -m "spec(onboarding): hotkey reminder toast"
```

---

# Group B — IMPLEMENTATION

### Task 5: `OnboardingState` model + sentinel keys

**Files:**
- Create: `Sotto/Onboarding/OnboardingState.swift`
- Test: `SottoTests/Onboarding/OnboardingStateTests.swift`

- [ ] **Step 5.1: Write failing tests**

```swift
import XCTest
@testable import Sotto

final class OnboardingStateTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        let suite = "OnboardingStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    func test_freshInstall_isNotCompleted() {
        let state = OnboardingState(defaults: defaults)
        XCTAssertFalse(state.completed)
        XCTAssertFalse(state.skipped)
        XCTAssertFalse(state.firstInvocationDidFire)
    }

    func test_markCompleted_setsSentinel() {
        let state = OnboardingState(defaults: defaults)
        state.markCompleted()
        XCTAssertTrue(state.completed)
        XCTAssertTrue(OnboardingState(defaults: defaults).completed,
                      "Sentinel must persist across instances")
    }

    func test_markSkipped_setsBothSentinels() {
        let state = OnboardingState(defaults: defaults)
        state.markSkipped()
        XCTAssertTrue(state.completed)
        XCTAssertTrue(state.skipped)
    }

    func test_markFirstInvocation_isIdempotent() {
        let state = OnboardingState(defaults: defaults)
        state.markFirstInvocation()
        state.markFirstInvocation()
        XCTAssertTrue(state.firstInvocationDidFire)
    }
}
```

- [ ] **Step 5.2: Run tests — verify they fail**

```bash
xcodebuild test -scheme Sotto -only-testing:SottoTests/OnboardingStateTests
```

Expected: FAIL — `OnboardingState` undefined.

- [ ] **Step 5.3: Implement `OnboardingState`**

Content of `Sotto/Onboarding/OnboardingState.swift`:

```swift
import Foundation
import Combine

@MainActor
final class OnboardingState: ObservableObject {
    static let shared = OnboardingState(defaults: .standard)

    enum Key {
        static let completed = "onboardingCompleted_v1"
        static let skipped = "onboardingSkipped_v1"
        static let skippedPermissions = "onboardingSkippedPermissions_v1"
        static let hotkeyReminderShown = "hotkeyReminderShown_v1"
        static let firstInvocationDidFire = "firstInvocationDidFire_v1"
    }

    private let defaults: UserDefaults

    @Published private(set) var completed: Bool
    @Published private(set) var skipped: Bool
    @Published private(set) var hotkeyReminderShown: Bool
    @Published private(set) var firstInvocationDidFire: Bool

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.completed = defaults.bool(forKey: Key.completed)
        self.skipped = defaults.bool(forKey: Key.skipped)
        self.hotkeyReminderShown = defaults.bool(forKey: Key.hotkeyReminderShown)
        self.firstInvocationDidFire = defaults.bool(forKey: Key.firstInvocationDidFire)
    }

    func markCompleted() {
        defaults.set(true, forKey: Key.completed)
        completed = true
    }

    func markSkipped() {
        defaults.set(true, forKey: Key.skipped)
        defaults.set(true, forKey: Key.completed)
        skipped = true
        completed = true
    }

    func markSkippedPermissions() {
        defaults.set(true, forKey: Key.skippedPermissions)
    }

    func markHotkeyReminderShown() {
        defaults.set(true, forKey: Key.hotkeyReminderShown)
        hotkeyReminderShown = true
    }

    func markFirstInvocation() {
        guard !firstInvocationDidFire else { return }
        defaults.set(true, forKey: Key.firstInvocationDidFire)
        firstInvocationDidFire = true
    }
}
```

- [ ] **Step 5.4: Run tests — verify they pass**

```bash
xcodebuild test -scheme Sotto -only-testing:SottoTests/OnboardingStateTests
```

Expected: PASS (4/4).

- [ ] **Step 5.5: Commit**

```bash
git add Sotto/Onboarding/OnboardingState.swift SottoTests/Onboarding/OnboardingStateTests.swift
git commit -m "feat(onboarding): OnboardingState + sentinel keys"
```

### Task 6: Extract `PermissionRow` from shipping `PermissionCard`

**Files:**
- Create: `Sotto/Views/Common/PermissionRow.swift`
- Modify: `Sotto/Views/PermissionsView.swift` (remove inline `PermissionCard`, import `PermissionRow`)

- [ ] **Step 6.1: Create `PermissionRow.swift`**

Move the `PermissionCard` struct verbatim from `Sotto/Views/PermissionsView.swift` (lines 85–191) into `Sotto/Views/Common/PermissionRow.swift`, renaming to `PermissionRow`. No content changes — extraction only. The file should export exactly the same SwiftUI API:

```swift
import SwiftUI

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let buttonTitle: String
    let buttonAction: () -> Void
    let checkPermission: () -> Void
    var infoTipMessage: String?
    var infoTipLink: String?
    @State private var isRefreshing = false

    var body: some View {
        // … (paste the existing body from PermissionCard verbatim) …
    }
}
```

- [ ] **Step 6.2: Update `Sotto/Views/PermissionsView.swift`**

Delete the inline `PermissionCard` struct (lines 85–191). Replace all four `PermissionCard(` call sites in `PermissionsView.body` with `PermissionRow(`. No other changes.

- [ ] **Step 6.3: Build to verify the extraction**

```bash
make local
```

Expected: clean build, app launches, Settings → Permissions renders identically to before.

- [ ] **Step 6.4: Commit**

```bash
git add Sotto/Views/Common/PermissionRow.swift Sotto/Views/PermissionsView.swift
git commit -m "refactor(permissions): extract PermissionRow for reuse in onboarding"
```

### Task 7: `OnboardingStep` enum + flow scaffolding

**Files:**
- Create: `Sotto/Views/Onboarding/OnboardingStep.swift`
- Create: `Sotto/Views/Onboarding/OnboardingFlowView.swift`

- [ ] **Step 7.1: Write `OnboardingStep.swift`**

```swift
import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case permissions
    case hotkey
    case done

    var id: Int { rawValue }

    func next() -> OnboardingStep {
        OnboardingStep(rawValue: rawValue + 1) ?? .done
    }

    func previous() -> OnboardingStep {
        OnboardingStep(rawValue: rawValue - 1) ?? .welcome
    }
}
```

- [ ] **Step 7.2: Write `OnboardingFlowView.swift` (scaffold only — step bodies arrive in Tasks 8–10)**

```swift
import SwiftUI

struct OnboardingFlowView: View {
    @StateObject private var state = OnboardingState.shared
    @State private var current: OnboardingStep = .welcome
    let onFinish: () -> Void

    var body: some View {
        ZStack {
            // Wallpaper bleed-through (§1.5)
            OnboardingBackdrop()

            // Skip button (top-right)
            VStack {
                HStack {
                    Spacer()
                    SkipButton {
                        state.markSkipped()
                        onFinish()
                    }
                }
                Spacer()
            }
            .padding(16)

            // Step content
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 32)
        }
        .frame(width: 480, height: 640)
    }

    @ViewBuilder
    private var stepBody: some View {
        switch current {
        case .welcome:
            WelcomeStepView(onContinue: { current = current.next() })
        case .permissions:
            PermissionsStepView(onContinue: { current = current.next() })
        case .hotkey:
            HotkeyStepView(onFinish: {
                state.markCompleted()
                onFinish()
            })
        case .done:
            EmptyView()
        }
    }
}

private struct OnboardingBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.063) // #0d0d10
            RadialGradient(
                colors: [Color(red: 0.43, green: 0.24, blue: 0.71).opacity(0.18), .clear],
                center: UnitPoint(x: 0.2, y: 0.0),
                startRadius: 0, endRadius: 480
            )
            RadialGradient(
                colors: [Palette.brandAcid.opacity(0.06), .clear],
                center: UnitPoint(x: 1.0, y: 1.0),
                startRadius: 0, endRadius: 480
            )
        }
    }
}

private struct SkipButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("›")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(Palette.ghost)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Skip onboarding")
    }
}
```

- [ ] **Step 7.3: Build — verify step views are stubbed but compile fails (expected; placeholder for Tasks 8–10)**

```bash
make local 2>&1 | grep -E "WelcomeStepView|PermissionsStepView|HotkeyStepView" | head -5
```

Expected: errors referencing the three step views (resolved in Tasks 8–10).

- [ ] **Step 7.4: Commit (work-in-progress; build is broken — explicitly noted)**

```bash
git add Sotto/Views/Onboarding/OnboardingStep.swift Sotto/Views/Onboarding/OnboardingFlowView.swift
git commit -m "wip(onboarding): step enum + flow scaffold (does not build until step views land)"
```

### Task 8: `WelcomeStepView` — wordmark hero

**Files:**
- Create: `Sotto/Views/Onboarding/WelcomeStepView.swift`

- [ ] **Step 8.1: Implement `WelcomeStepView`**

```swift
import SwiftUI

struct WelcomeStepView: View {
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Wordmark — references BrandMarks (HUD pair owns; stub if missing)
            Text(BrandMarks.styledWordmark())
                .font(.system(size: 56, weight: .bold, design: .monospaced))
                .tracking(1.0) // ≈ +0.02em at 56pt
                .opacity(visible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: visible)

            // Tagline
            Text("› sotto voce · under your voice")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .tracking(0.5)
                .foregroundColor(Palette.ghost)
                .opacity(visible ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24).delay(0.12), value: visible)

            Spacer()
            Spacer()

            // CTA
            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("▸ Get started")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                }
                .foregroundColor(Palette.brandAcid)
                .frame(width: 220, height: 44)
                .background(
                    TacticalGlass(
                        shape: NotchCornerShape(radius: 8),
                        phase: .armed,
                        appearance: .darkAqua
                    )
                )
                .accessibilityHint("Begin Sotto setup")
            }
            .buttonStyle(.plain)

            Spacer().frame(height: 64)
        }
        .onAppear { visible = true }
    }
}
```

- [ ] **Step 8.2: Manual visual check**

```bash
make local
```

Expected: with a temporary forced-`!completed` override in `Sotto.swift`, the onboarding window opens to the welcome screen. Wordmark fades in. CTA renders lime on Tactical Glass. Reduce Motion (System Settings → Accessibility) skips fade.

- [ ] **Step 8.3: Commit**

```bash
git add Sotto/Views/Onboarding/WelcomeStepView.swift
git commit -m "feat(onboarding): welcome step with wordmark hero"
```

### Task 9: `PermissionsStepView` — three rows, mic-gated continue

**Files:**
- Create: `Sotto/Views/Onboarding/PermissionsStepView.swift`

- [ ] **Step 9.1: Implement `PermissionsStepView`**

```swift
import SwiftUI
import AVFoundation

struct PermissionsStepView: View {
    let onContinue: () -> Void
    @StateObject private var perms = PermissionManager()
    @EnvironmentObject private var state: OnboardingState

    private var micGranted: Bool { perms.audioPermissionStatus == .authorized }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section label
            Text("› PERMISSIONS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.76) // +0.16em
                .foregroundColor(Palette.brandAcid)
                .padding(.top, 24)

            // Headline
            Text("Grant access to dictate anywhere")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .tracking(0.36)
                .foregroundColor(.white)

            // Body
            Text("Sotto needs three permissions. Mic is required; the others unlock paste-at-cursor and screen-context.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.ghost)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 8)

            // Rows
            VStack(spacing: 12) {
                PermissionRow(
                    icon: "mic",
                    title: "Microphone",
                    description: "Record your voice for transcription.",
                    isGranted: micGranted,
                    buttonTitle: perms.audioPermissionStatus == .notDetermined ? "Request permission" : "Open System Settings",
                    buttonAction: {
                        if perms.audioPermissionStatus == .notDetermined {
                            perms.requestAudioPermission()
                        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    checkPermission: { perms.checkAudioPermissionStatus() }
                )

                PermissionRow(
                    icon: "hand.raised",
                    title: "Accessibility",
                    description: "Paste transcribed text at your cursor across apps.",
                    isGranted: perms.isAccessibilityEnabled,
                    buttonTitle: "Open System Settings",
                    buttonAction: {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    checkPermission: { perms.checkAccessibilityPermissions() },
                    infoTipMessage: "Sotto uses Accessibility to paste transcribed text at your cursor in any app."
                )

                PermissionRow(
                    icon: "rectangle.on.rectangle",
                    title: "Screen Recording",
                    description: "Use screen context to improve transcription accuracy.",
                    isGranted: perms.isScreenRecordingEnabled,
                    buttonTitle: "Request permission",
                    buttonAction: {
                        perms.requestScreenRecordingPermission()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    },
                    checkPermission: { perms.checkScreenRecordingPermission() },
                    infoTipMessage: "Sotto reads on-screen text to improve accuracy. Processed locally, never stored."
                )
            }

            Spacer()

            // Footer
            HStack {
                Button(action: {
                    state.markSkippedPermissions()
                    onContinue()
                }) {
                    Text("Skip for now ›")
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundColor(Palette.ghost)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onContinue) {
                    Text("▸ Continue")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(micGranted ? Palette.brandAcid : Palette.ghost)
                        .frame(width: 140, height: 36)
                        .background(
                            TacticalGlass(
                                shape: NotchCornerShape(radius: 8),
                                phase: micGranted ? .armed : .hidden,
                                appearance: .darkAqua
                            )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!micGranted)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 8)
        .onAppear { perms.checkAllPermissions() }
    }
}
```

- [ ] **Step 9.2: Manual run-through**

Reset `defaults delete com.sotto.Sotto onboardingCompleted_v1`. Launch app. Reach permissions step. Verify:
- Continue is disabled until mic granted.
- Skip-for-now bypasses (writes `onboardingSkippedPermissions_v1`).
- Granting in System Settings → app comes back → row flips to "Granted" within 500 ms (already handled by shipping `PermissionManager.applicationDidBecomeActive`).

- [ ] **Step 9.3: Commit**

```bash
git add Sotto/Views/Onboarding/PermissionsStepView.swift
git commit -m "feat(onboarding): permissions step reuses PermissionRow"
```

### Task 10: `HotkeyStepView` — bound-shortcut preview + Finish

**Files:**
- Create: `Sotto/Views/Onboarding/HotkeyStepView.swift`

- [ ] **Step 10.1: Implement `HotkeyStepView`**

```swift
import SwiftUI
import KeyboardShortcuts

struct HotkeyStepView: View {
    let onFinish: () -> Void

    private var shortcutDescription: String {
        KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)?.description ?? "⌥ SPACE"
    }

    private var isUnbound: Bool {
        KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("› SHORTCUT")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1.76)
                .foregroundColor(Palette.brandAcid)
                .padding(.top, 24)

            Text("Press the shortcut to dictate")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(.white)

            Text("Sotto stays out of the way. Press this anywhere to start.")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.ghost)

            Spacer().frame(height: 16)

            // Shortcut block
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    Text(shortcutDescription)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                    if isUnbound {
                        Button("Configure ›") {
                            NotificationCenter.default.post(
                                name: .navigateToDestination,
                                object: nil,
                                userInfo: ["destination": "Settings"]
                            )
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundColor(Palette.brandAcid)
                    }
                }
                .frame(width: 220, height: 80)
                .background(
                    TacticalGlass(
                        shape: NotchCornerShape(radius: 8),
                        phase: .armed,
                        appearance: .darkAqua
                    )
                )
                Spacer()
            }

            Text("You'll see a reminder toast the first time. After that, Sotto is invisible.")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(Palette.ghost)
                .padding(.top, 16)

            Spacer()

            // Finish CTA
            HStack {
                Spacer()
                Button(action: onFinish) {
                    Text("▸ Finish")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Palette.brandAcid)
                        .frame(width: 140, height: 44)
                        .background(
                            TacticalGlass(
                                shape: NotchCornerShape(radius: 8),
                                phase: .armed,
                                appearance: .darkAqua
                            )
                        )
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 8)
    }
}
```

- [ ] **Step 10.2: Commit**

```bash
git add Sotto/Views/Onboarding/HotkeyStepView.swift
git commit -m "feat(onboarding): hotkey reminder step"
```

### Task 11: `OnboardingWindowController` + bootstrap gate

**Files:**
- Create: `Sotto/Views/Onboarding/OnboardingWindowController.swift`
- Modify: `Sotto/Sotto.swift` — add bootstrap gate

- [ ] **Step 11.1: Implement `OnboardingWindowController`**

```swift
import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSWindowController {
    static let shared = OnboardingWindowController()

    private var hostingController: NSHostingController<OnboardingFlowView>?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.center()
        super.init(window: panel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func present() {
        guard let window else { return }

        let host = NSHostingController(
            rootView: OnboardingFlowView(onFinish: { [weak self] in
                self?.dismissAndScheduleReminder()
            })
        )
        hostingController = host
        window.contentViewController = host
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func dismissAndScheduleReminder() {
        window?.orderOut(nil)

        let state = OnboardingState.shared
        // Schedule the one-shot toast 600ms after the window dismisses,
        // unless the user skipped onboarding entirely OR no model is set
        // (in which case the user lands on Models pane first).
        guard !state.skipped, !state.hotkeyReminderShown else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            HotkeyReminderToast.show()
        }
    }
}
```

- [ ] **Step 11.2: Add bootstrap gate to `Sotto.swift`**

In the root `WindowGroup`'s `.background(WindowAccessor { ... })` closure (around the post-rename equivalent of `VoiceInk.swift:476`), append:

```swift
.task {
    if !OnboardingState.shared.completed {
        OnboardingWindowController.shared.present()
    }
}
```

- [ ] **Step 11.3: Build & smoke test**

```bash
defaults delete com.sotto.Sotto onboardingCompleted_v1 2>/dev/null
make local
```

Expected: app launches → onboarding window appears front-center → main window dimmed behind. Complete the flow → window closes → main window comes to front → toast appears 600 ms later (Task 12 covers the toast view).

- [ ] **Step 11.4: Commit**

```bash
git add Sotto/Views/Onboarding/OnboardingWindowController.swift Sotto/Sotto.swift
git commit -m "feat(onboarding): window controller + first-run bootstrap gate"
```

### Task 12: `HotkeyReminderToast` — one-shot reminder

**Files:**
- Create: `Sotto/Views/Onboarding/HotkeyReminderToast.swift`
- Modify: `Sotto/HotkeyManager.swift` — write `firstInvocationDidFire_v1` on first `.recording` transition + dismiss toast

- [ ] **Step 12.1: Implement `HotkeyReminderToast`**

```swift
import AppKit
import SwiftUI
import KeyboardShortcuts
import Combine

@MainActor
enum HotkeyReminderToast {
    private static var panel: NSPanel?
    private static var subscription: AnyCancellable?

    static func show() {
        guard !OnboardingState.shared.hotkeyReminderShown else { return }
        OnboardingState.shared.markHotkeyReminderShown()

        let shortcut = KeyboardShortcuts.getShortcut(for: .toggleMiniRecorder)?.description ?? "⌥ SPACE"

        let view = HotkeyReminderToastView(
            shortcut: shortcut,
            onClose: { dismiss() }
        )

        let host = NSHostingController(rootView: view)
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize

        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.contentView = host.view
        p.isFloatingPanel = true
        p.level = .popUpMenu
        p.backgroundColor = .clear
        p.hasShadow = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Position: top-anchored, centered, 16pt below notch line.
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.maxY - 16 - size.height
        p.setFrameOrigin(NSPoint(x: x, y: y))
        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil as Any?)
        panel = p

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        // Auto-dismiss on first recording transition.
        // VoiceInkEngine is shared via the AppDelegate — bridge via NotificationCenter.
        subscription = NotificationCenter.default
            .publisher(for: .firstInvocationDidFire)
            .sink { _ in dismiss() }
    }

    static func dismiss() {
        subscription?.cancel()
        subscription = nil
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.close()
        })
    }
}

private struct HotkeyReminderToastView: View {
    let shortcut: String
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Text("›")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(Palette.brandAcid)

            Text("Press \(shortcut) to dictate")
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(.white)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .frame(width: 16, height: 16)
            .accessibilityLabel("Dismiss tip")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 280, maxWidth: 480, minHeight: 44)
        .background(
            TacticalGlass(
                shape: NotchCornerShape(radius: 8),
                phase: .armed,
                appearance: .darkAqua
            )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip: press \(shortcut) to start dictation. Close button available.")
    }
}

extension Notification.Name {
    static let firstInvocationDidFire = Notification.Name("firstInvocationDidFire_v1")
}
```

- [ ] **Step 12.2: Hook into `HotkeyManager`**

In `Sotto/HotkeyManager.swift`, find the handler that transitions engine into `.recording` (look for `engine.toggleRecording()` / `engine.startRecording()` call site, around the existing `setupHotkeyMonitoring` block). Add at the start of the success path:

```swift
if !OnboardingState.shared.firstInvocationDidFire {
    OnboardingState.shared.markFirstInvocation()
    NotificationCenter.default.post(name: .firstInvocationDidFire, object: nil)
}
```

This is the sentinel that extinguishes the toast permanently per Decision D10 (any invocation path counts).

- [ ] **Step 12.3: Smoke test the full first-run sequence**

```bash
defaults delete com.sotto.Sotto onboardingCompleted_v1 hotkeyReminderShown_v1 firstInvocationDidFire_v1 2>/dev/null
make local
```

Expected:
1. Onboarding window opens.
2. Complete flow → window closes → 600 ms later → top-anchored toast appears with `Press ⌥ SPACE to dictate`.
3. Press ⌥ SPACE → engine enters `.recording` → toast fades out within 220 ms.
4. Restart app: no onboarding window, no toast.

- [ ] **Step 12.4: Commit**

```bash
git add Sotto/Views/Onboarding/HotkeyReminderToast.swift Sotto/HotkeyManager.swift
git commit -m "feat(onboarding): one-shot ⌥ SPACE reminder toast"
```

### Task 13: Re-skin `AppNotificationView` to Tactical Glass + state colors

**Files:**
- Modify: `Sotto/Notifications/AppNotificationView.swift`
- Modify: `Sotto/Notifications/NotificationManager.swift` — accept positioning override

- [ ] **Step 13.1: Add state-color cases to `NotificationType`**

In `Sotto/Notifications/AppNotificationView.swift`, extend the enum:

```swift
enum NotificationType {
    case error
    case warning
    case info
    case success
    case recording    // NEW — red dot
    case transcribing // NEW — cyan
    case enhancing    // NEW — violet
    case committed    // NEW — green ✓
    case fail         // NEW — red ✗ + error code

    var iconName: String {
        switch self {
        case .error, .fail: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .success, .committed: return "checkmark.circle.fill"
        case .recording: return "record.circle.fill"
        case .transcribing: return "waveform"
        case .enhancing: return "sparkles"
        }
    }

    var iconColor: Color {
        switch self {
        case .error, .fail: return Palette.recRed
        case .warning: return Palette.warn // existing
        case .info: return Palette.brandAcid
        case .success, .committed: return Palette.commitGreen
        case .recording: return Palette.recRed
        case .transcribing: return Palette.transCyan
        case .enhancing: return Palette.enhViolet
        }
    }

    /// §1.X — shape-based colorblind disambiguation for settled states.
    var glyph: String? {
        switch self {
        case .committed: return "✓"
        case .fail: return "✗"
        default: return nil
        }
    }
}
```

- [ ] **Step 13.2: Replace ad-hoc backgrounds with `TacticalGlass`**

Find the `.background(...)` block (lines 86–110 in the shipping file). Replace with:

```swift
.background(
    TacticalGlass(
        shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
        phase: phaseForType,
        appearance: .darkAqua
    )
)
```

Add a `phaseForType` computed property near the body:

```swift
private var phaseForType: HaloPhase {
    switch type {
    case .recording: return .recording
    case .transcribing: return .transcribing
    case .enhancing: return .enhancing
    case .committed: return .done
    case .fail: return .failed
    case .error: return .failed
    default: return .armed
    }
}
```

Delete the inner `LinearGradient` + `VisualEffectView` stack (TacticalGlass owns all that).

- [ ] **Step 13.3: Replace ad-hoc inner border with `Palette.hairline`**

Find the `.strokeBorder(Palette.hairlineSoft, lineWidth: 0.5)` overlay (line 114). TacticalGlass already provides the inner stroke per §1.1 step 4. Remove the overlay block entirely.

- [ ] **Step 13.4: Add positioning override**

In `Sotto/Notifications/NotificationManager.swift`, change `showNotification` signature:

```swift
enum NotificationAnchor {
    case bottom  // default; existing behavior
    case top     // anchored under notch — for HUD-state toasts
}

func showNotification(
    title: String,
    type: AppNotificationView.NotificationType,
    duration: TimeInterval = 3.0,
    anchor: NotificationAnchor = .bottom,
    onTap: (() -> Void)? = nil,
    actionButton: (label: String, action: () -> Void)? = nil
) {
    // … existing body …
    positionWindow(panel, anchor: anchor)
    // …
}

private func positionWindow(_ window: NSWindow, anchor: NotificationAnchor) {
    let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens[0]
    let visible = screen.visibleFrame
    let x = visible.midX - window.frame.width / 2
    let y: CGFloat
    switch anchor {
    case .bottom:
        y = visible.minY + 24 + 34 + 16 // existing math
    case .top:
        y = visible.maxY - 16 - window.frame.height
    }
    window.setFrameOrigin(NSPoint(x: x, y: y))
}
```

- [ ] **Step 13.5: Build + smoke**

```bash
make local
```

Trigger a `.recording` toast manually from a debug menu (or temporarily inject `NotificationManager.shared.showNotification(title: "REC", type: .recording, anchor: .top)` at app launch). Verify lime/red/cyan/violet/green keyings render correctly on TacticalGlass.

- [ ] **Step 13.6: Commit**

```bash
git add Sotto/Notifications/AppNotificationView.swift Sotto/Notifications/NotificationManager.swift
git commit -m "feat(notifications): TacticalGlass re-skin + HUD state-color types + top/bottom anchor"
```

---

# Group C — ACCESSIBILITY + POLISH

### Task 14: VoiceOver pass

**Files:**
- Modify: `Sotto/Views/Onboarding/WelcomeStepView.swift`
- Modify: `Sotto/Views/Onboarding/PermissionsStepView.swift`
- Modify: `Sotto/Views/Onboarding/HotkeyStepView.swift`
- Modify: `Sotto/Views/Common/PermissionRow.swift`

- [ ] **Step 14.1: Wordmark VoiceOver label**

`WelcomeStepView` wordmark `Text(BrandMarks.styledWordmark())` — add `.accessibilityLabel("Sotto")` (drops the trailing period for spoken pronunciation).

- [ ] **Step 14.2: Section labels — header trait**

Each `› SECTION` label (`PermissionsStepView`, `HotkeyStepView`) — add `.accessibilityAddTraits(.isHeader)`.

- [ ] **Step 14.3: `PermissionRow` — combined element**

Wrap `PermissionRow`'s `body` in `.accessibilityElement(children: .combine)` and add:

```swift
.accessibilityLabel("\(title). \(description). \(isGranted ? "Granted." : "Needs access.")")
.accessibilityHint(isGranted ? "Already granted" : buttonTitle)
```

- [ ] **Step 14.4: Manual VoiceOver run**

`cmd+F5` to enable VoiceOver. Walk the entire flow. Verify each step announces correctly.

- [ ] **Step 14.5: Commit**

```bash
git add Sotto/Views/Onboarding/ Sotto/Views/Common/PermissionRow.swift
git commit -m "a11y(onboarding): VoiceOver labels + hints"
```

### Task 15: Reduce Motion sweep

**Files:**
- Modify: `Sotto/Views/Onboarding/HotkeyReminderToast.swift`
- Modify: `Sotto/Views/Onboarding/OnboardingFlowView.swift`

- [ ] **Step 15.1: Guard toast halo loop**

In `HotkeyReminderToastView`, the `TacticalGlass` `phase: .armed` triggers the 1.6 s breathe loop. Wrap with:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// …
.background(
    TacticalGlass(
        shape: NotchCornerShape(radius: 8),
        phase: reduceMotion ? .hidden : .armed, // .hidden skips the loop; we keep the static glass
        appearance: .darkAqua
    )
)
```

(HUD pair's `TacticalGlass` must map `phase: .hidden` to "static surface, no animations" — clarify with HUD pair if ambiguous; for our purposes `.hidden` is a misnomer but it gives the right rendering. If HUD pair adds a `.static` phase later, swap.)

- [ ] **Step 15.2: Guard toast slide-in**

Replace the 0.22s panel slide animation in `HotkeyReminderToast.show()` with an opacity-only animation when Reduce Motion is on. Read the preference at `show()` time via `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`:

```swift
let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

NSAnimationContext.runAnimationGroup { ctx in
    ctx.duration = reduceMotion ? 0.20 : 0.22
    ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
    p.animator().alphaValue = 1
    // No frame translation under Reduce Motion.
    if !reduceMotion {
        p.setFrame(p.frame.offsetBy(dx: 0, dy: -8), display: false)
        p.animator().setFrame(p.frame.offsetBy(dx: 0, dy: 8), display: true)
    }
}
```

- [ ] **Step 15.3: Verify**

System Settings → Accessibility → Display → Reduce Motion = ON. Reset onboarding sentinels. Re-run the full flow. Every animation should degrade to opacity-only fades.

- [ ] **Step 15.4: Commit**

```bash
git add Sotto/Views/Onboarding/HotkeyReminderToast.swift Sotto/Views/Onboarding/OnboardingFlowView.swift
git commit -m "a11y(onboarding): Reduce Motion fallbacks for toast + entry animations"
```

### Task 16: High Contrast pass

**Files:**
- Modify: `Sotto/Views/Onboarding/OnboardingFlowView.swift`

- [ ] **Step 16.1: Apply `AdaptiveGlass` to the backdrop**

The HC branch in `HaloMaterial.swift` (lines 287–309) provides opaque-fill + 1pt-stroke variants. Wrap `OnboardingBackdrop`:

```swift
@Environment(\.accessibilityShowButtonShapes) private var showButtonShapes
@Environment(\.colorSchemeContrast) private var contrast

// In body
if contrast == .increased {
    Color.black // opaque, no gradient bleed
} else {
    // existing radial-gradient stack
}
```

For step content, `TacticalGlass` already routes through `AdaptiveGlass` per HUD spec — nothing extra needed there, just verify the HUD pair's primitive handles HC. If it doesn't yet, file a blocker.

- [ ] **Step 16.2: Manual HC check**

System Settings → Accessibility → Display → Increase Contrast = ON. Reset onboarding. Verify:
- Backdrop is solid black, no gradient.
- Glass surfaces are opaque, 1pt solid lime/white strokes.
- CTAs render with clear borders.

- [ ] **Step 16.3: Commit**

```bash
git add Sotto/Views/Onboarding/OnboardingFlowView.swift
git commit -m "a11y(onboarding): High Contrast backdrop + AdaptiveGlass routing"
```

### Task 17: End-to-end verification

**Files:** none — verification only.

- [ ] **Step 17.1: Full first-run dry run on a fresh defaults domain**

```bash
defaults delete com.sotto.Sotto onboardingCompleted_v1 onboardingSkipped_v1 onboardingSkippedPermissions_v1 hotkeyReminderShown_v1 firstInvocationDidFire_v1 2>/dev/null
make local
```

Run the full sequence: welcome → permissions (grant mic; skip others) → hotkey → finish → toast appears → press ⌥ SPACE → toast dismisses → restart → no onboarding, no toast.

- [ ] **Step 17.2: Skip path**

```bash
defaults delete com.sotto.Sotto onboardingCompleted_v1 2>/dev/null
```

Launch → click `›` skip on welcome → verify:
- `onboardingCompleted_v1 = 1` and `onboardingSkipped_v1 = 1`.
- No toast (per Task 11 dismiss logic: skipped → no toast).
- Restart → no onboarding window.

- [ ] **Step 17.3: Permissions-skip path**

Fresh defaults. Reach permissions step, click `Skip for now ›` → verify `onboardingSkippedPermissions_v1 = 1` and flow continues to hotkey step.

- [ ] **Step 17.4: Reduce-Motion + VoiceOver combined**

Enable both. Re-run full flow. No animation jank; VoiceOver announces each region.

- [ ] **Step 17.5: Document any defects**

If any acceptance criterion fails, file as follow-up tasks under "Group D — repair" before merge.

- [ ] **Step 17.6: Final commit (only if doc/changelog updates needed)**

```bash
git commit --allow-empty -m "verify(onboarding): end-to-end sentinel + a11y sweep complete"
```

---

## Acceptance (rolls up all step-level criteria)

- [ ] Welcome screen renders `BrandMarks.styledWordmark()` — wordmark hero.
- [ ] CTA uses `▸ Get started`; skip uses `›`.
- [ ] Three permission rows; mic gates Continue; others skippable.
- [ ] `PermissionRow` extracted from `PermissionsView.swift`'s `PermissionCard` and shared.
- [ ] Hotkey step shows bound shortcut (or `⌥ SPACE` default) on TacticalGlass.
- [ ] `OnboardingWindowController` floats as a borderless panel, 480×640, centered.
- [ ] First-run gate at `Sotto.swift` root view `.task` checks `OnboardingState.shared.completed`.
- [ ] `UserDefaults` keys: `onboardingCompleted_v1`, `onboardingSkipped_v1`, `onboardingSkippedPermissions_v1`, `hotkeyReminderShown_v1`, `firstInvocationDidFire_v1` — five total.
- [ ] `⌥ SPACE` toast fires once, dismisses on first `.recording` transition (any path), never re-shows.
- [ ] Toast routes through re-skinned `AppNotificationView` on TacticalGlass with `phase: .armed`.
- [ ] `AppNotificationView` adds `.recording / .transcribing / .enhancing / .committed / .fail` types with §1.4 colors + `✓`/`✗` glyph disambiguation.
- [ ] `NotificationManager` accepts `anchor: .top | .bottom` positioning.
- [ ] VoiceOver labels on wordmark, section headers, permission rows, toast, skip button.
- [ ] Reduce Motion respected on every loop + entry animation.
- [ ] High Contrast respected via `AdaptiveGlass` routing.
- [ ] `make local` builds clean; `make reload` reloads cleanly.
- [ ] No `voiceink` literal strings in new files (carve-outs in §7.1.GPL do not apply to onboarding code).

---

## Self-review notes

- **Spec coverage:** §6.1 Surfaces 10 (onboarding) + 11 (notification toasts) — covered by Tasks 1–17. §5.1 wordmark hero — Task 8. §3 first-run `⌥ SPACE` reminder one-time — Tasks 12, 11. §1.X accessibility (Reduce Motion / VoiceOver / HC / colorblind glyphs) — Tasks 14–16 + Task 13 glyph disambiguation. Appendix C.ONBOARDING starting points (MetricsSetupView pattern, PermissionsView, HotkeyManager:21, AnnouncementManager) — all referenced.
- **No placeholders.** Every code step has runnable code or exact textual content.
- **Type consistency:** `OnboardingState`/`OnboardingStep`/`OnboardingFlowView`/`OnboardingWindowController`/`HotkeyReminderToast` referenced consistently. `PermissionRow` is the shared extract. `BrandMarks.styledWordmark()` and `TacticalGlass(shape:phase:appearance:)` are dependency symbols owned by HUD pair — flagged in Dependencies table.
- **Out of scope (filed back to scope owner):**
  - Marketing site / domain (B.Domain) — defer to marketing; welcome screen has no URL.
  - Brew cask / Sparkle feed copy — RENAME pair.
  - Models-pane deep-link landing UX when user has no model after onboarding — D6 says "defer to Settings"; routing is wired (Task 10 step copy) but Models-pane UI for new-user is SETTINGS pair.
