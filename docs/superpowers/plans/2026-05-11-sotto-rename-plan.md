# Sotto · RENAME pair implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename app + bundle ID from `VoiceInk` / `com.prakashjoshipax.VoiceInk` → `Sotto` / `com.sotto.Sotto`, with zero data-loss for existing users (UserDefaults, SwiftData store, Keychain, CloudKit, OSLog attribution, Sparkle continuity). Preserves GPL §5 attribution.

**Architecture:** Three migration shims (UserDefaults / SwiftData store-move / Keychain dual-read) land **before** any pbxproj/entitlements/Info.plist change, so the new binary's first launch on legacy installs finds everything it needs. CloudKit container ID is intentionally **not** renamed (Option C — §7.1.CloudKit). OSLog subsystems centralised through a constants module and swept across 51 call sites. Marketing/Sparkle/brew/README references swept last.

**Tech Stack:** Swift 5.9 + SwiftUI 5, SwiftData, Sparkle 2, Keychain Services, OSLog, Xcode 15 (macOS 14.4+ target). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-05-11-sotto-ui-redesign-design.md` — §0, §5.1, §6.1, §6.3, §7.1, Appendix B (B.Trademark / B.Domain / B.SparkleCutover), Appendix C.RENAME.

**Critical path:** RENAME runs FIRST. Blocks HUD (file-path renames), MENUBAR (bundle ID for MenuBarExtra), SETTINGS / MAIN / ONBOARDING (file paths). Do NOT widen scope beyond Surface #1 in §6.1.

---

## Cross-pair dependencies

| Downstream pair | What they need from RENAME | Surface in their plan |
|---|---|---|
| HUD | `Sotto/Views/Recorder/*` paths post-rename; `TacticalGlass` import path | §2 acceptance row 1 |
| MENUBAR | `com.sotto.Sotto` bundle ID for `MenuBarExtra` ownership; new `OSLogSubsystems.app` constant | §5 acceptance row 3 |
| SETTINGS / MAIN | new module name, new bundle ID for `@AppStorage` reads | §6.1 |
| ONBOARDING | new bundle ID (first-run sentinel `__sotto_userdefaults_migrated_v1` collides if naming changes) | §6.1 |

---

## Phase 0 · Pre-flight spikes (BLOCKS KICKOFF)

These resolve before Step 1. Any failure → rename pauses and team-lead arbitrates.

### Spike S1: Trademark — `Sotto` cleared for software (Appendix B.Trademark)

- [ ] **S1.1 — USPTO search**

Run via web: `https://tmsearch.uspto.gov/` — search `Sotto` filtered by **International Class 9** (downloadable software) AND **Class 42** (SaaS / hosted software). Record hits.

- [ ] **S1.2 — EU search**

`https://euipo.europa.eu/eSearch/` — same classes.

- [ ] **S1.3 — Common-law check**

Google `"Sotto" macOS app`, `"Sotto" transcription`, `"Sotto" dictation`. Sotto Pizza LA / Sotto restaurants do NOT block software class — only same-class collisions matter.

- [ ] **S1.4 — Document outcome**

Append findings to `docs/superpowers/specs/2026-05-11-sotto-rename-trademark-check.md` (create file). Decision: GO / NO-GO / NEED-LEGAL.

Acceptance: clear in Class 9 + 42 in US/EU OR explicit user sign-off accepting risk.

### Spike S2: Domain — register marketing URL (Appendix B.Domain)

- [ ] **S2.1 — Check availability**

Run:
```bash
whois sotto.app
whois sotto.so
whois getsotto.com
```

- [ ] **S2.2 — Pick + register**

Preference order: `sotto.app` > `sotto.so` > `getsotto.com`. Register with user's preferred registrar (Porkbun, Cloudflare). User completes purchase out-of-band.

- [ ] **S2.3 — Record choice**

Append to `docs/superpowers/specs/2026-05-11-sotto-rename-trademark-check.md` as `## Domain` section. The chosen domain feeds Step 8 (`SUFeedURL`) and ONBOARDING marketing URLs.

Acceptance: domain registered OR explicit decision to use CDN-only / GitHub Pages stopgap (`https://<user>.github.io/sotto/appcast.xml`).

### Spike S3: Sparkle cutover ADR (Appendix B.SparkleCutover / §7.1.Sparkle)

- [ ] **S3.1 — Write ADR**

Create `docs/superpowers/specs/2026-05-11-sotto-rename-sparkle-adr.md`. Document: **No automated Sparkle handoff.** Existing VoiceInk installs do NOT receive a Sparkle update to Sotto (bundle ID change makes them distinct products to Sparkle). Reasoning: fork user base ≈ self + collaborators, and per §7.1.Sparkle, manual reinstall (brew / DMG) is acceptable.

Template body:

```markdown
# Sotto rename — Sparkle cutover decision

**Date:** 2026-05-11
**Status:** Accepted

## Decision
No automated Sparkle handoff from VoiceInk → Sotto. Existing installs continue receiving upstream `beingpax.github.io` feed updates (if any). Sotto starts with fresh feed at `https://<domain>/appcast.xml`.

## Reasoning
- Fork user base is small (developer + collaborators).
- Bundle ID change makes Sotto a distinct Sparkle product; same-feed re-association is not supported.
- Manual reinstall (brew cask / DMG) is acceptable for known user set.

## Consequences
- Old VoiceInk install remains on disk + may receive (unrelated) upstream updates.
- Sotto users must `brew uninstall voiceink && brew install sotto` (or DMG drop-in).
- New `SUPublicEDKey` may need regeneration for `appcast.xml` signing — track as backlog if signing infra is staged.
```

Acceptance: ADR file committed; PR description for Step 7 links it.

---

## Phase 1 · Foundations (migrations, OSLog, entitlements)

All Phase 1 steps land BEFORE Phase 2 (the rename itself). Phase 1 is no-op on existing VoiceInk install — it adds infrastructure but doesn't yet change identity. Phase 1 sub-steps within a step are mostly sequential; Step 1 and Step 2 are independent and may be parallelised.

---

### Step 1: `OSLogSubsystems` constants module + sweep 51 call sites

**Files:**
- Create: `VoiceInk/Services/OSLogSubsystems.swift`
- Modify: all 51 files containing `Logger(subsystem:` — full list:
  - `VoiceInk/VoiceInk.swift:57`
  - `VoiceInk/Recorder.swift:9`
  - `VoiceInk/WindowManager.swift:11`
  - `VoiceInk/HotkeyManager.swift:70`
  - `VoiceInk/MenuBarManager.swift:7`
  - `VoiceInk/CoreAudioRecorder.swift:12`
  - `VoiceInk/CursorPaster.swift:7` (currently `com.VoiceInk` — collapses to `app`)
  - `VoiceInk/Transcription/Processing/TranscriptionOutputFilter.swift:5`
  - `VoiceInk/Transcription/Native/NativeAppleTranscriptionService.swift:12`
  - `VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift:13` (currently `…fluidaudio`)
  - `VoiceInk/Transcription/Streaming/StreamingTranscriptionService.swift:44`
  - `VoiceInk/Transcription/Streaming/FluidAudioStreamingProvider.swift:8`
  - `VoiceInk/Transcription/Engine/TranscriptionModelManager.swift:13`
  - `VoiceInk/Transcription/Engine/AudioFileProcessor.swift:6`
  - `VoiceInk/Transcription/Engine/TranscriptionSession.swift:55`
  - `VoiceInk/Transcription/Engine/RecorderUIManager.swift:61`
  - `VoiceInk/Transcription/FluidAudio/FluidAudioModelManager.swift:14`
  - `VoiceInk/Transcription/Engine/TranscriptionServiceRegistry.swift:11`
  - `VoiceInk/Transcription/Cloud/CustomCloudModelManager.swift:7`
  - `VoiceInk/Transcription/Whisper/WhisperTranscriptionService.swift:8`
  - `VoiceInk/Transcription/Whisper/WhisperModelManager.swift:76`
  - `VoiceInk/Transcription/Whisper/VADModelManager.swift:6` (currently `VADModelManager` — bare string, collapses to `app`)
  - `VoiceInk/Transcription/Engine/VoiceInkEngine.swift:51`
  - `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift:14`
  - `VoiceInk/Transcription/Whisper/LibWhisper.swift:17`
  - `VoiceInk/Views/ContentView.swift:62`
  - `VoiceInk/HandsFree/HandsFreeSessionService.swift:35`
  - `VoiceInk/Audio/CueSynthesizer.swift:32`
  - `VoiceInk/Views/Metrics/MetricsContent.swift:6` (currently `com.prakashjoshipax.VoiceInk` — note Capital I)
  - `VoiceInk/Views/Dictionary/WordReplacementView.swift:6`
  - `VoiceInk/Views/AI Models/MLXModelPickerView.swift:4`
  - `VoiceInk/Services/AutoLearnVocabularyService.swift:12`
  - `VoiceInk/Services/SessionMetricRecorder.swift:6`
  - `VoiceInk/Services/ScratchpadStore.swift:20`
  - `VoiceInk/Services/AudioFileTranscriptionManager.swift:22`
  - `VoiceInk/Services/SessionMetricMigrationService.swift:9`
  - `VoiceInk/Services/AudioDeviceManager.swift:19`
  - `VoiceInk/Services/KeychainService.swift:11`
  - `VoiceInk/Services/APIKeyManager.swift:8`
  - `VoiceInk/Services/AudioDeviceConfiguration.swift:8`
  - `VoiceInk/Services/LogExporter.swift:7`
  - `VoiceInk/Services/CommandModeService.swift:50`
  - `VoiceInk/Services/TranscriptionAutoCleanupService.swift:8`
  - `VoiceInk/Services/AudioFileTranscriptionService.swift:15`
  - `VoiceInk/Services/AIEnhancement/MLXProvider.swift:669`
  - `VoiceInk/Services/AIEnhancement/MLXModelRegistry.swift:8`
  - `VoiceInk/Services/ModelPrewarmService.swift:16`
  - `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:14`
  - `VoiceInk/Services/AIEnhancement/AIService.swift:221`
  - `VoiceInk/Services/AIEnhancement/AIService.swift:598`
  - `VoiceInk/Services/AIEnhancement/AFMProvider.swift:54`
- Test: `VoiceInkTests/OSLogSubsystemsTests.swift`

Unique subsystem strings inventoried (5):
1. `com.prakashjoshipax.voiceink` (most)
2. `com.prakashjoshipax.VoiceInk` (MetricsContent — capital `I`)
3. `com.prakashjoshipax.voiceink.fluidaudio` (FluidAudioTranscriptionService)
4. `com.VoiceInk` (CursorPaster — short)
5. `VADModelManager` (VADModelManager — bare, no reverse-DNS)

All collapse to `OSLogSubsystems.app = "com.sotto.Sotto"` except FluidAudio which gets its own constant (preserves Console.app categorisation).

- [ ] **Step 1.1: Write failing test for constants module**

`VoiceInkTests/OSLogSubsystemsTests.swift`:

```swift
import XCTest
@testable import VoiceInk

final class OSLogSubsystemsTests: XCTestCase {
    func test_app_subsystem_uses_sotto_bundle_id() {
        XCTAssertEqual(OSLogSubsystems.app, "com.sotto.Sotto")
    }

    func test_fluidaudio_subsystem_namespaced_under_app() {
        XCTAssertTrue(OSLogSubsystems.fluidAudio.hasPrefix(OSLogSubsystems.app))
        XCTAssertEqual(OSLogSubsystems.fluidAudio, "com.sotto.Sotto.fluidaudio")
    }
}
```

- [ ] **Step 1.2: Run test to verify it fails**

Run: `xcodebuild test -workspace VoiceInk.xcworkspace -scheme VoiceInk -only-testing:VoiceInkTests/OSLogSubsystemsTests 2>&1 | tail -20`
Expected: FAIL — `Cannot find 'OSLogSubsystems' in scope`.

- [ ] **Step 1.3: Create the constants module**

`VoiceInk/Services/OSLogSubsystems.swift`:

```swift
import Foundation

/// Centralised OSLog subsystem identifiers.
///
/// Subsystem strings drive Console.app filtering + `log stream --predicate`
/// queries. They MUST match the app's bundle identifier so log attribution
/// in Console.app aligns with the installed app identity. Pre-rename, 51
/// call sites used 5 inconsistent strings; consolidated here at rename time.
enum OSLogSubsystems {
    /// Primary subsystem — matches `CFBundleIdentifier`.
    static let app = "com.sotto.Sotto"

    /// FluidAudio streaming + model-manager subsystem. Distinct from `app`
    /// so power-user Console filters can isolate FluidAudio noise.
    static let fluidAudio = "com.sotto.Sotto.fluidaudio"
}
```

- [ ] **Step 1.4: Run test to verify it passes**

Run: `xcodebuild test -workspace VoiceInk.xcworkspace -scheme VoiceInk -only-testing:VoiceInkTests/OSLogSubsystemsTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 1.5: Sweep 50 of 51 call sites (skip FluidAudioTranscriptionService — handled in 1.6)**

For each file listed above except `FluidAudioTranscriptionService.swift`, replace the literal subsystem string with `OSLogSubsystems.app`. Example transform:

```swift
// before
private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Recorder")
// after
private let logger = Logger(subsystem: OSLogSubsystems.app, category: "Recorder")
```

Note: 4 special cases —
- `MetricsContent.swift:6`: `com.prakashjoshipax.VoiceInk` → `OSLogSubsystems.app`
- `CursorPaster.swift:7`: `com.VoiceInk` → `OSLogSubsystems.app`
- `VADModelManager.swift:6`: `VADModelManager` (bare) → `OSLogSubsystems.app` (category stays `"ModelManagement"`)
- `VoiceInk.swift:57` (inside `init`): `Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Initialization")` → `Logger(subsystem: OSLogSubsystems.app, category: "Initialization")`

- [ ] **Step 1.6: Sweep FluidAudioTranscriptionService to use `fluidAudio` constant**

`VoiceInk/Transcription/FluidAudio/FluidAudioTranscriptionService.swift:13`:

```swift
// before
private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink.fluidaudio", category: "FluidAudioTranscriptionService")
// after
private let logger = Logger(subsystem: OSLogSubsystems.fluidAudio, category: "FluidAudioTranscriptionService")
```

- [ ] **Step 1.7: grep-verify no literals remain**

Run:
```bash
grep -rn 'Logger(subsystem: *"' --include='*.swift' VoiceInk/
```
Expected: zero matches.

Run:
```bash
grep -rn 'com\.prakashjoshipax\.voiceink\|com\.prakashjoshipax\.VoiceInk\|"com\.VoiceInk"\|"VADModelManager"' --include='*.swift' VoiceInk/ | grep -v 'BundleIdentityMigration\|KeychainService' | grep -v '//'
```
Expected: zero matches (the surviving allow-list is the migration shim itself + KeychainService legacy literal, addressed Step 4).

- [ ] **Step 1.8: Build + commit**

```bash
make local
```
Expected: clean build.

```bash
git add VoiceInk/Services/OSLogSubsystems.swift VoiceInkTests/OSLogSubsystemsTests.swift VoiceInk/
git commit -m "infra(rename-s1): centralise OSLog subsystems through OSLogSubsystems constants

Sweep 51 Logger(subsystem:) call sites to read OSLogSubsystems.app /
.fluidAudio. Subsystem string now tracks app bundle ID so Console.app
attribution stays correct post-rename. Spec §7.1.OSLog.
"
```

---

### Step 2: `SottoBundleIdentityMigration` shim — UserDefaults + SwiftData + Keychain orchestrator

This is the heart of the rename. Idempotent + sentinel-guarded, modelled on `VoiceInk/Services/StreamingKeysMigration.swift`. Runs ONCE per install; copies UserDefaults from the legacy bundle suite, moves the app-support directory, and rewrites Keychain items into the new access group.

**Files:**
- Create: `VoiceInk/Services/SottoBundleIdentityMigration.swift`
- Test: `VoiceInkTests/SottoBundleIdentityMigrationTests.swift`

#### Step 2A: UserDefaults sub-shim (§7.1.UserDefaults)

- [ ] **Step 2A.1: Write failing test — UserDefaults copy is idempotent and sentinel-gated**

`VoiceInkTests/SottoBundleIdentityMigrationTests.swift`:

```swift
import XCTest
@testable import VoiceInk

final class SottoBundleIdentityMigrationTests: XCTestCase {
    private let legacySuiteName = "com.prakashjoshipax.VoiceInk"
    private let sentinelKey = "__sotto_identity_migrated_v1"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: sentinelKey)
        UserDefaults.standard.removeObject(forKey: "TestKey_A")
        UserDefaults(suiteName: legacySuiteName)?.removeObject(forKey: "TestKey_A")
    }

    func test_userDefaults_copy_copies_legacy_to_standard_then_sets_sentinel() {
        let legacy = UserDefaults(suiteName: legacySuiteName)!
        legacy.set("legacy_value", forKey: "TestKey_A")

        SottoBundleIdentityMigration.runUserDefaultsCopy()

        XCTAssertEqual(UserDefaults.standard.string(forKey: "TestKey_A"), "legacy_value")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: sentinelKey))
    }

    func test_userDefaults_copy_is_no_op_when_sentinel_set() {
        UserDefaults.standard.set(true, forKey: sentinelKey)
        let legacy = UserDefaults(suiteName: legacySuiteName)!
        legacy.set("legacy_value", forKey: "TestKey_B")

        SottoBundleIdentityMigration.runUserDefaultsCopy()

        XCTAssertNil(UserDefaults.standard.object(forKey: "TestKey_B"))
    }
}
```

- [ ] **Step 2A.2: Run test to verify it fails**

Run: `xcodebuild test ... -only-testing:VoiceInkTests/SottoBundleIdentityMigrationTests 2>&1 | tail -20`
Expected: FAIL — `Cannot find 'SottoBundleIdentityMigration' in scope`.

- [ ] **Step 2A.3: Implement UserDefaults sub-shim**

`VoiceInk/Services/SottoBundleIdentityMigration.swift`:

```swift
import Foundation
import OSLog

/// One-shot migration that lifts user data from the legacy
/// `com.prakashjoshipax.VoiceInk` bundle namespace into the renamed
/// `com.sotto.Sotto` namespace. Sentinel-guarded; idempotent across
/// crash/relaunch. Spec §7.1.UserDefaults / §7.1.SwiftData / §7.1.Keychain.
///
/// Modelled on `StreamingKeysMigration.run()` (sentinel pattern + UserDefaults
/// scope) — kept separate so it can be deleted in a future release once the
/// transition window has elapsed.
enum SottoBundleIdentityMigration {
    static let legacyBundleID = "com.prakashjoshipax.VoiceInk"
    static let legacyAppSupportDirName = "com.prakashjoshipax.VoiceInk"
    static let newAppSupportDirName = "com.sotto.Sotto"
    static let userDefaultsSentinel = "__sotto_identity_migrated_v1"

    private static let logger = Logger(subsystem: OSLogSubsystems.app, category: "BundleIdentityMigration")

    /// Top-level entry point — runs all three sub-migrations sequentially.
    /// Safe to call on every launch (each sub-step is sentinel-gated).
    static func run() {
        runUserDefaultsCopy()
        runAppSupportDirectoryMove()
        runKeychainGroupCopy()
    }

    // MARK: - UserDefaults (§7.1.UserDefaults)

    static func runUserDefaultsCopy() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: userDefaultsSentinel) else { return }
        guard let legacy = UserDefaults(suiteName: legacyBundleID) else {
            logger.warning("Legacy UserDefaults suite unavailable; marking migrated.")
            defaults.set(true, forKey: userDefaultsSentinel)
            return
        }

        let snapshot = legacy.dictionaryRepresentation()
        var copied = 0
        for (key, value) in snapshot {
            // Don't clobber values that the new namespace has already set
            // via AppDefaults.registerDefaults() — only copy if standard
            // has no user-provided value yet.
            guard defaults.object(forKey: key) == nil else { continue }
            defaults.set(value, forKey: key)
            copied += 1
        }
        logger.info("UserDefaults copy: \(copied, privacy: .public) keys lifted from legacy suite.")
        defaults.set(true, forKey: userDefaultsSentinel)
    }

    // MARK: - SwiftData app-support directory (§7.1.SwiftData)
    // Implementation lands in Step 2B.

    static func runAppSupportDirectoryMove() {
        // Stub — implemented in Step 2B.
    }

    // MARK: - Keychain group (§7.1.Keychain)
    // Implementation lands in Step 2C.

    static func runKeychainGroupCopy() {
        // Stub — implemented in Step 2C.
    }
}
```

- [ ] **Step 2A.4: Run test to verify it passes**

Run: `xcodebuild test ... -only-testing:VoiceInkTests/SottoBundleIdentityMigrationTests/test_userDefaults_copy_copies_legacy_to_standard_then_sets_sentinel`
Expected: PASS.

Run: `xcodebuild test ... -only-testing:VoiceInkTests/SottoBundleIdentityMigrationTests/test_userDefaults_copy_is_no_op_when_sentinel_set`
Expected: PASS.

- [ ] **Step 2A.5: Commit**

```bash
git add VoiceInk/Services/SottoBundleIdentityMigration.swift VoiceInkTests/SottoBundleIdentityMigrationTests.swift
git commit -m "infra(rename-s2a): SottoBundleIdentityMigration — UserDefaults copy shim

Lift @AppStorage + UserDefaults.standard reads from legacy
com.prakashjoshipax.VoiceInk suite into renamed com.sotto.Sotto domain.
Sentinel __sotto_identity_migrated_v1 prevents re-run. Spec §7.1.UserDefaults.
"
```

#### Step 2B: SwiftData store path move (§7.1.SwiftData)

- [ ] **Step 2B.1: Write failing test**

Append to `SottoBundleIdentityMigrationTests.swift`:

```swift
func test_appSupport_move_relocates_legacy_directory() throws {
    let fm = FileManager.default
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let legacyURL = appSupport.appendingPathComponent(SottoBundleIdentityMigration.legacyAppSupportDirName)
    let newURL = appSupport.appendingPathComponent(SottoBundleIdentityMigration.newAppSupportDirName)

    // Setup: legacy exists, new doesn't
    try? fm.removeItem(at: legacyURL)
    try? fm.removeItem(at: newURL)
    try fm.createDirectory(at: legacyURL, withIntermediateDirectories: true)
    try "marker".write(to: legacyURL.appendingPathComponent("smoke.txt"), atomically: true, encoding: .utf8)

    SottoBundleIdentityMigration.runAppSupportDirectoryMove()

    XCTAssertFalse(fm.fileExists(atPath: legacyURL.path))
    XCTAssertTrue(fm.fileExists(atPath: newURL.appendingPathComponent("smoke.txt").path))

    // Cleanup
    try? fm.removeItem(at: newURL)
}

func test_appSupport_move_skips_when_new_already_exists() throws {
    let fm = FileManager.default
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let legacyURL = appSupport.appendingPathComponent(SottoBundleIdentityMigration.legacyAppSupportDirName)
    let newURL = appSupport.appendingPathComponent(SottoBundleIdentityMigration.newAppSupportDirName)

    try? fm.removeItem(at: legacyURL)
    try? fm.removeItem(at: newURL)
    try fm.createDirectory(at: legacyURL, withIntermediateDirectories: true)
    try fm.createDirectory(at: newURL, withIntermediateDirectories: true)

    SottoBundleIdentityMigration.runAppSupportDirectoryMove()

    XCTAssertTrue(fm.fileExists(atPath: legacyURL.path))  // legacy preserved — operator decides
    XCTAssertTrue(fm.fileExists(atPath: newURL.path))

    try? fm.removeItem(at: legacyURL)
    try? fm.removeItem(at: newURL)
}
```

- [ ] **Step 2B.2: Run tests to verify they fail**

Run: `xcodebuild test ... -only-testing:VoiceInkTests/SottoBundleIdentityMigrationTests/test_appSupport_move_relocates_legacy_directory`
Expected: FAIL — directory not moved.

- [ ] **Step 2B.3: Implement directory move**

Replace the stub in `SottoBundleIdentityMigration.swift`:

```swift
static func runAppSupportDirectoryMove() {
    let fm = FileManager.default
    let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let legacyURL = appSupport.appendingPathComponent(legacyAppSupportDirName, isDirectory: true)
    let newURL = appSupport.appendingPathComponent(newAppSupportDirName, isDirectory: true)

    // Idempotency guards (in priority order):
    // 1. New dir already exists → do not clobber, leave legacy on disk for
    //    operator to inspect/remove. Logged so QA can audit.
    // 2. Legacy dir doesn't exist → nothing to move (fresh install or
    //    already migrated).
    guard !fm.fileExists(atPath: newURL.path) else {
        logger.notice("AppSupport move skipped: \(newURL.path, privacy: .public) already exists.")
        return
    }
    guard fm.fileExists(atPath: legacyURL.path) else {
        logger.debug("AppSupport move skipped: no legacy directory at \(legacyURL.path, privacy: .public).")
        return
    }

    do {
        try fm.moveItem(at: legacyURL, to: newURL)
        logger.info("AppSupport move: \(legacyURL.lastPathComponent, privacy: .public) → \(newURL.lastPathComponent, privacy: .public)")
    } catch {
        logger.error("AppSupport move FAILED: \(error.localizedDescription, privacy: .public)")
    }
}
```

- [ ] **Step 2B.4: Run tests to verify they pass**

Run: both `test_appSupport_move_*` tests.
Expected: PASS.

- [ ] **Step 2B.5: Update hardcoded SwiftData paths in `VoiceInk.swift`**

`VoiceInk/VoiceInk.swift:141`:

```swift
// before
let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("com.prakashjoshipax.VoiceInk")
// after
let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent(SottoBundleIdentityMigration.newAppSupportDirName)
```

`VoiceInk/VoiceInk.swift:287` (inside `createPersistentContainer`):

```swift
// before
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
// after
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent(SottoBundleIdentityMigration.newAppSupportDirName, isDirectory: true)
```

`VoiceInk/VoiceInk.swift:374` (inside `createPersistentStatsContainer`):

```swift
// before
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
// after
let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent(SottoBundleIdentityMigration.newAppSupportDirName, isDirectory: true)
```

(The team-lead briefing listed line 141 + 287 only — line 374 is the third hit found via grep; identical pattern.)

- [ ] **Step 2B.6: Commit**

```bash
git add VoiceInk/Services/SottoBundleIdentityMigration.swift VoiceInkTests/SottoBundleIdentityMigrationTests.swift VoiceInk/VoiceInk.swift
git commit -m "infra(rename-s2b): app-support dir move + retarget SwiftData paths

moveItem legacy com.prakashjoshipax.VoiceInk dir → com.sotto.Sotto on
first launch (idempotent; skips if new dir exists). Retarget three
hardcoded paths in VoiceInk.swift (lines 141, 287, 374). Spec §7.1.SwiftData.
"
```

#### Step 2C: Keychain dual-read shim (§7.1.Keychain)

KeychainService currently uses `service = "com.prakashjoshipax.VoiceInk"` (line 12) — items remain accessible via that legacy service string until rewritten. Strategy: leave the legacy service literal in code for ONE release for read-fallback; copy items into the new service on first launch.

- [ ] **Step 2C.1: Write failing test**

Append to `SottoBundleIdentityMigrationTests.swift`:

```swift
func test_keychain_copy_sets_sentinel_after_run() {
    let sentinel = "__sotto_keychain_migrated_v1"
    UserDefaults.standard.removeObject(forKey: sentinel)

    SottoBundleIdentityMigration.runKeychainGroupCopy()

    XCTAssertTrue(UserDefaults.standard.bool(forKey: sentinel))
}
```

Note: full keychain item migration is hard to unit-test without entitlements signing — this test only validates the sentinel mechanism. End-to-end Keychain copy is validated by Step 13 smoke test (manual: install legacy build, save API key, install new build, verify key is readable).

- [ ] **Step 2C.2: Run test to verify it fails**

Expected: FAIL — sentinel not set.

- [ ] **Step 2C.3: Implement keychain copy**

Replace stub in `SottoBundleIdentityMigration.swift`:

```swift
static let keychainSentinel = "__sotto_keychain_migrated_v1"
static let legacyKeychainService = "com.prakashjoshipax.VoiceInk"
static let newKeychainService = "com.sotto.Sotto"

static func runKeychainGroupCopy() {
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: keychainSentinel) else { return }

    // Enumerate all generic-password items under the legacy service,
    // copy each to the new service. Keychain entitlements (Step 5) must
    // already include both access groups OR the new bundle ID must own
    // the legacy group via dual-list — see Phase 1 entitlements step.
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: legacyKeychainService,
        kSecMatchLimit as String: kSecMatchLimitAll,
        kSecReturnAttributes as String: true,
        kSecReturnData as String: true,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let items = result as? [[String: Any]] else {
        logger.info("Keychain copy: no legacy items found (status=\(status, privacy: .public)).")
        defaults.set(true, forKey: keychainSentinel)
        return
    }

    var copied = 0
    for item in items {
        guard let account = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data else { continue }
        let synchronizable = (item[kSecAttrSynchronizable as String] as? Bool) ?? false

        var addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: newKeychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if synchronizable { addQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue }

        // Delete any pre-existing entry under the new service first to
        // avoid duplicate errors.
        SecItemDelete(addQuery as CFDictionary)
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus == errSecSuccess { copied += 1 }
    }
    logger.info("Keychain copy: \(copied, privacy: .public) items copied to \(newKeychainService, privacy: .public).")
    defaults.set(true, forKey: keychainSentinel)
}
```

- [ ] **Step 2C.4: Update `KeychainService.service` literal + add legacy read-fallback**

`VoiceInk/Services/KeychainService.swift:12`:

```swift
// before
private let service = "com.prakashjoshipax.VoiceInk"
// after
private let service = "com.sotto.Sotto"
private let legacyService = "com.prakashjoshipax.VoiceInk"
```

Then extend `getData(forKey:syncable:)` to fall back to the legacy service on miss (covers the corner case where `SottoBundleIdentityMigration.runKeychainGroupCopy()` hasn't yet run — e.g. during the same launch's init sequence):

```swift
func getData(forKey key: String, syncable: Bool = true) -> Data? {
    #if LOCAL_BUILD
    return defaults.data(forKey: localPrefix + key)
    #else
    var query = baseQuery(forKey: key, syncable: syncable)
    query[kSecReturnData as String] = kCFBooleanTrue
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: AnyObject?
    var status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecItemNotFound {
        // Legacy fallback — read-only path covering the pre-migration
        // window. Migration shim removes need for this within 1 launch.
        var legacyQuery = query
        legacyQuery[kSecAttrService as String] = legacyService
        status = SecItemCopyMatching(legacyQuery as CFDictionary, &result)
    }

    if status == errSecSuccess {
        return result as? Data
    } else if status != errSecItemNotFound {
        logger.error("Failed to retrieve keychain item for key: \(key, privacy: .public), status: \(status, privacy: .public)")
    }
    return nil
    #endif
}
```

- [ ] **Step 2C.5: Run test to verify it passes**

Run: `test_keychain_copy_sets_sentinel_after_run`
Expected: PASS.

- [ ] **Step 2C.6: Commit**

```bash
git add VoiceInk/Services/SottoBundleIdentityMigration.swift VoiceInk/Services/KeychainService.swift VoiceInkTests/SottoBundleIdentityMigrationTests.swift
git commit -m "infra(rename-s2c): keychain dual-read + one-shot service copy

KeychainService.service → com.sotto.Sotto; getData falls back to legacy
service on miss for pre-migration window. SottoBundleIdentityMigration
.runKeychainGroupCopy copies all generic-password items
{legacy → new} on first launch. Spec §7.1.Keychain.
"
```

---

### Step 3: CloudKit container decision — Option C (keep legacy container ID)

Per spec §7.1.CloudKit, Option C (recommended): only the app bundle ID changes; the CloudKit container ID stays `iCloud.com.prakashjoshipax.VoiceInk`. No entitlement change; the rename has zero CloudKit blast radius.

- [ ] **Step 3.1: Add ADR comment in entitlements (annotation only, no functional change)**

Edit `VoiceInk/VoiceInk.entitlements` — entitlements files don't support XML comments inside `<dict>` cleanly across all toolchains, so the ADR lives in a sidecar markdown.

Create `VoiceInk/VoiceInk.entitlements.README.md`:

```markdown
# Sotto entitlements — CloudKit container ID rationale

## Why does `iCloud.com.prakashjoshipax.VoiceInk` remain post-rename?

Spec §7.1.CloudKit Option C: CloudKit accepts any container the developer
team owns; the container ID does NOT have to match the bundle ID. Keeping
the legacy container ID:

- Avoids the empty-new-container data-loss scenario in Option A.
- Avoids the dual-entitlement footprint cost of Option B.
- Preserves all existing iCloud-synced Vocabulary / WordReplacement / Snippet
  data without a copy step.

The literal `iCloud.com.prakashjoshipax.VoiceInk` is therefore retained in
`VoiceInk.entitlements` line 9 AND in `VoiceInk.swift` line 318 (the
`#if !LOCAL_BUILD` branch of `createPersistentContainer`).

This is the ONLY string anywhere in the Sotto codebase containing
`prakashjoshipax` that is NOT a legacy-migration shim — it is a deliberate,
load-bearing reference. Treat as a carve-out for the §7.1.GPL grep audit
in Step 9.
```

- [ ] **Step 3.2: Commit**

```bash
git add VoiceInk/VoiceInk.entitlements.README.md
git commit -m "docs(rename-s3): ADR for CloudKit container ID preservation

Option C (keep iCloud.com.prakashjoshipax.VoiceInk) avoids data-loss +
entitlement-bloat. Carve-out documented for grep audit in Step 9.
Spec §7.1.CloudKit.
"
```

---

### Step 4: Entitlements dual-list (Keychain access group)

Add the new bundle ID's keychain access group alongside the legacy. This MUST land before the pbxproj rename so the signed binary is allowed to read both groups during the migration window.

**Files:**
- Modify: `VoiceInk/VoiceInk.entitlements:34-37`

- [ ] **Step 4.1: Add new keychain group alongside legacy**

`VoiceInk/VoiceInk.entitlements` — replace the `<key>keychain-access-groups</key>` block:

```xml
<!-- before -->
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.prakashjoshipax.VoiceInk</string>
</array>

<!-- after -->
<key>keychain-access-groups</key>
<array>
    <string>$(AppIdentifierPrefix)com.sotto.Sotto</string>
    <string>$(AppIdentifierPrefix)com.prakashjoshipax.VoiceInk</string>
</array>
```

The legacy group stays for ONE release (transition window). Once telemetry confirms all installs migrated, file backlog ticket `rename-cleanup-keychain-legacy-group` and drop the second entry.

Note: the mach-lookup global names (`$(PRODUCT_BUNDLE_IDENTIFIER)-spks` / `-spki`) at lines 31-33 are already variable-substituted — they re-target automatically when `PRODUCT_BUNDLE_IDENTIFIER` flips. No edit needed.

- [ ] **Step 4.2: Verify Xcode reads the new entitlements**

Run: `xcodebuild -showBuildSettings -scheme VoiceInk 2>&1 | grep CODE_SIGN_ENTITLEMENTS`
Expected: prints `VoiceInk/VoiceInk.entitlements` (the path stays the same).

- [ ] **Step 4.3: Build**

```bash
make local
```
Expected: signing succeeds — dual entitlement is valid pre-rename (current bundle ID is still `com.prakashjoshipax.VoiceInk`; first group is unused for now).

- [ ] **Step 4.4: Commit**

```bash
git add VoiceInk/VoiceInk.entitlements
git commit -m "infra(rename-s4): entitlements dual-list keychain access groups

Add \$(AppIdentifierPrefix)com.sotto.Sotto alongside legacy
…com.prakashjoshipax.VoiceInk so post-rename binary can read both groups
during one-launch migration. Backlog: drop legacy group next release.
Spec §7.1.Keychain.
"
```

---

## Phase 2 · The rename itself

Phase 2 flips identity. After these steps, the next launch on a legacy install runs the migrations from Phase 1.

---

### Step 5: Xcode project rename — `PRODUCT_BUNDLE_IDENTIFIER` + `PRODUCT_NAME` + `CFBundleDisplayName`

**Files:**
- Modify: `VoiceInk.xcodeproj/project.pbxproj` (lines 509, 518, 519, 543, 552, 553)
- Modify: `VoiceInk/Info.plist` (display name — see Step 6)

Per `grep` in pre-flight: 6 lines in pbxproj reference the main app target's identity. Test/UITest targets remain `com.prakashjoshipax.VoiceInkTests` / `…UITests` to avoid churn — these don't ship.

- [ ] **Step 5.1: Patch the two `PRODUCT_BUNDLE_IDENTIFIER` lines for main target**

`VoiceInk.xcodeproj/project.pbxproj:518`:

```diff
- PRODUCT_BUNDLE_IDENTIFIER = com.prakashjoshipax.VoiceInk;
+ PRODUCT_BUNDLE_IDENTIFIER = com.sotto.Sotto;
```

`VoiceInk.xcodeproj/project.pbxproj:552`:

```diff
- PRODUCT_BUNDLE_IDENTIFIER = com.prakashjoshipax.VoiceInk;
+ PRODUCT_BUNDLE_IDENTIFIER = com.sotto.Sotto;
```

DO NOT touch lines 570, 588, 604, 620 (test target bundle IDs — out of scope).

- [ ] **Step 5.2: Patch the two `CFBundleDisplayName` lines**

`VoiceInk.xcodeproj/project.pbxproj:509`:

```diff
- INFOPLIST_KEY_CFBundleDisplayName = VoiceInk;
+ INFOPLIST_KEY_CFBundleDisplayName = Sotto;
```

`VoiceInk.xcodeproj/project.pbxproj:543`:

```diff
- INFOPLIST_KEY_CFBundleDisplayName = VoiceInk;
+ INFOPLIST_KEY_CFBundleDisplayName = Sotto;
```

Note: `CFBundleName` defaults to `$(PRODUCT_NAME)` unless explicitly set. `PRODUCT_NAME = "$(TARGET_NAME)"` and the target name is `VoiceInk` — Finder will show `VoiceInk.app` unless we override. v2b acceptance §5 says `CFBundleName` must be `Sotto`. Add the explicit override.

- [ ] **Step 5.3: Pin `INFOPLIST_KEY_CFBundleName` explicitly**

Insert after each `INFOPLIST_KEY_CFBundleDisplayName = Sotto;` line in pbxproj (lines 509 and 543, post-edit):

```diff
  INFOPLIST_KEY_CFBundleDisplayName = Sotto;
+ INFOPLIST_KEY_CFBundleName = Sotto;
```

- [ ] **Step 5.4: Build + verify bundle ID flipped**

```bash
make local
```

Then:

```bash
defaults read /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/.local-build/Build/Products/Debug/VoiceInk.app/Contents/Info.plist CFBundleIdentifier
```

Expected: `com.sotto.Sotto`.

```bash
defaults read /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/.local-build/Build/Products/Debug/VoiceInk.app/Contents/Info.plist CFBundleDisplayName
defaults read /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/.local-build/Build/Products/Debug/VoiceInk.app/Contents/Info.plist CFBundleName
```

Expected: both `Sotto`.

Note: the on-disk `.app` filename remains `VoiceInk.app` until `TARGET_NAME` flips — DON'T flip `TARGET_NAME` in this plan. Renaming the target rewrites scheme/build/source-group paths and is high-risk for a critical-path PR. Operator (user) manually renames the target via Xcode's UI in a follow-up commit; alternatively, keep `VoiceInk.app` filename and only the user-visible display name is "Sotto". `CFBundleDisplayName` is what Finder/Dock/Notification Center renders. This is acceptable per §5 acceptance ("`PRODUCT_NAME, CFBundleDisplayName, CFBundleName, CFBundleIdentifier`").

> **Open question for team-lead:** does the user want the filesystem `.app` renamed too? If yes, file as a Step 5b follow-up — requires Xcode UI rename, not a textual pbxproj patch.

- [ ] **Step 5.5: Commit**

```bash
git add VoiceInk.xcodeproj/project.pbxproj
git commit -m "feat(rename-s5): flip bundle ID to com.sotto.Sotto + display name to Sotto

PRODUCT_BUNDLE_IDENTIFIER (Debug+Release) → com.sotto.Sotto.
INFOPLIST_KEY_CFBundleDisplayName + CFBundleName → Sotto.
Test/UITest targets unchanged (don't ship). Spec §5 acceptance.
"
```

---

### Step 6: `Info.plist` — Sparkle feed URL + permission-prompt strings

**Files:**
- Modify: `VoiceInk/Info.plist:7-8, 15-20`

- [ ] **Step 6.1: Update `SUFeedURL`**

`VoiceInk/Info.plist:8`:

```diff
- <string>https://beingpax.github.io/VoiceInk/appcast.xml</string>
+ <string>https://<DOMAIN_FROM_SPIKE_S2>/appcast.xml</string>
```

`<DOMAIN_FROM_SPIKE_S2>` resolves to the registered domain (`sotto.app` / `sotto.so` / fallback). If Spike S2 produced GitHub Pages stopgap, use `<user>.github.io/sotto`.

- [ ] **Step 6.2: Update permission-prompt strings**

`VoiceInk/Info.plist:16`:

```diff
- <string>VoiceInk needs access to your microphone to record audio for transcription.</string>
+ <string>Sotto needs access to your microphone to record audio for transcription.</string>
```

`VoiceInk/Info.plist:18`:

```diff
- <string>VoiceInk needs to interact with your browser to detect the current website for applying website-specific configurations.</string>
+ <string>Sotto needs to interact with your browser to detect the current website for applying website-specific configurations.</string>
```

`VoiceInk/Info.plist:20`:

```diff
- <string>VoiceInk needs screen recording access to understand context from your screen for improved transcription accuracy.</string>
+ <string>Sotto needs screen recording access to understand context from your screen for improved transcription accuracy.</string>
```

- [ ] **Step 6.3: Build + verify**

```bash
make local
```

Then:

```bash
defaults read /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/.local-build/Build/Products/Debug/VoiceInk.app/Contents/Info.plist SUFeedURL
```

Expected: `https://<domain>/appcast.xml`.

- [ ] **Step 6.4: Commit**

```bash
git add VoiceInk/Info.plist
git commit -m "feat(rename-s6): Sparkle feed → Sotto domain + permission strings

SUFeedURL cuts over to Sotto's own appcast.xml; mic/AppleEvents/Screen
recording prompts reference Sotto. No automated handoff from VoiceInk
feed — see Sparkle ADR (Spike S3). Spec §7.1.Sparkle.
"
```

---

### Step 7: Marketing + brew + announcements URL sweep

**Files:**
- Modify: `VoiceInk/Services/AnnouncementsService.swift:13`
- Modify: `README.md` (lines 2, 3, 8, 9, 10, 12, 13, 16, 17, 23, 25, 45, 48, 51, 55, 64, 69, 72, 96)
- Modify: `BUILDING.md` (lines 1, 3, 15, 21, 22, 36, 38, 47, 62, 63, 65)

#### Step 7A: AnnouncementsService

- [ ] **Step 7A.1: Update announcements URL**

`VoiceInk/Services/AnnouncementsService.swift:13`:

```diff
- private let announcementsURL = URL(string: "https://beingpax.github.io/VoiceInk/announcements.json")!
+ private let announcementsURL = URL(string: "https://<DOMAIN_FROM_SPIKE_S2>/announcements.json")!
```

If no Sotto announcements feed exists yet, point at a 404 path — `AnnouncementsService` handles failed fetches silently (verify with Read pass).

- [ ] **Step 7A.2: Build + commit**

```bash
make local
```

```bash
git add VoiceInk/Services/AnnouncementsService.swift
git commit -m "feat(rename-s7a): repoint AnnouncementsService at Sotto domain

announcements.json now served from Sotto's own host. Spec §7.1 (marketing
URL sweep).
"
```

#### Step 7B: README + BUILDING

- [ ] **Step 7B.1: Rewrite README header + body**

Replace `VoiceInk` → `Sotto`, `tryvoiceink.com` → `<DOMAIN_FROM_SPIKE_S2>`, `brew install --cask voiceink` → `brew install --cask sotto` (assumes future cask under same name; if a different name is registered, sub-in). PRESERVE the GitHub link to `Beingpax/VoiceInk` in the upstream attribution section per §7.1.GPL — see Step 9.

Concrete edits per line — apply via `Edit` tool:

| Line | Before | After |
|---|---|---|
| 2 | `<img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" ...` | `<img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" ...` (path stays — repo dir not renamed in this plan) |
| 3 | `<h1>VoiceInk</h1>` | `<h1>Sotto.</h1>` |
| 8 | `…release/Beingpax/VoiceInk` | UNCHANGED — upstream attribution per §7.1.GPL |
| 9 | `…downloads/Beingpax/VoiceInk/total` | UNCHANGED |
| 10 | `…stars/Beingpax/VoiceInk?style=social` | UNCHANGED |
| 12 | `<a href="https://tryvoiceink.com">Website</a>` | `<a href="https://<DOMAIN>">Website</a>` |
| 13 | `<a href="https://www.youtube.com/@tryvoiceink">YouTube</a>` | DROP the YouTube row (no Sotto YouTube channel) |
| 16-17 | `<a href="https://tryvoiceink.com">…Download VoiceInk…</a>` | `<a href="https://<DOMAIN>">…Download Sotto…</a>` |
| 23 | `VoiceInk is a native macOS application…from [here](https://tryvoiceink.com)` | `Sotto is a fork of VoiceInk, a native macOS application…from [here](https://<DOMAIN>)` |
| 25 | `![VoiceInk Mac App](…)` | `![Sotto Mac App](…)` |
| 45 | `…free trial from [tryvoiceink.com]…` + monetization sentence | Remove entire paragraph — monetization stripped per project memory |
| 48 | `Alternatively, you can install VoiceInk via brew:` | `Install Sotto via brew:` |
| 51 | `brew install --cask voiceink` | `brew install --cask sotto` |
| 55 | `…build VoiceInk yourself…compiled version includes additional benefits…` | `…build Sotto yourself by following [BUILDING.md](BUILDING.md).` (drop the monetization-adjacent sentence) |
| 64 | `…contribute to VoiceInk` | `…contribute to Sotto` |
| 69 | `You're welcome to fork and modify VoiceInk` | `Sotto is a personal fork of VoiceInk; you're welcome to fork and modify it further.` |
| 72 | `https://github.com/Beingpax/VoiceInk/issues` | UNCHANGED if user wants reports forwarded upstream, OR replace with Sotto's own repo issues URL (user decides — file as open question at end). |
| 96 | `Keeping VoiceInk up to date` | `Keeping Sotto up to date` |

- [ ] **Step 7B.2: Rewrite BUILDING.md**

Apply mechanical `VoiceInk` → `Sotto` substitution for instructional copy, BUT preserve `git clone https://github.com/Beingpax/VoiceInk.git` lines (line 21, 62) — they are the canonical fork-from URL. If user has a Sotto repo with a different URL, capture as open question.

Replace `cd VoiceInk` (lines 22, 63) → `cd voiceink-fork` (matches the actual repo dir name) OR `cd sotto` if user renamed the directory locally — defer to user.

`~/VoiceInk-Dependencies` (line 47) — leave UNCHANGED. This is a Makefile-pinned external dir; renaming would break the Makefile + every developer's local cache. File backlog `rename-followup-dependencies-dir` instead.

- [ ] **Step 7B.3: Commit**

```bash
git add README.md BUILDING.md
git commit -m "docs(rename-s7b): README+BUILDING refer to Sotto; upstream attribution kept

Mechanical VoiceInk→Sotto on body copy. Upstream Beingpax/VoiceInk
references preserved per GPL §5 (badges, fork-from URL). YouTube row +
monetization paragraphs dropped. \`brew install --cask sotto\`.
\`~/VoiceInk-Dependencies\` dir name unchanged (Makefile-pinned).
"
```

#### Step 7C: brew cask reference

- [ ] **Step 7C.1: File homebrew cask follow-up**

No homebrew cask file exists in this repo (verified — `find … -name 'Casks*'` returns empty). The cask lives in a separate `homebrew-cask` tap or `homebrew/homebrew-cask` upstream repo. Out-of-scope for this PR.

Create `docs/superpowers/handoffs/HANDOFF_sotto_brew_cask.md`:

```markdown
# Sotto brew cask — handoff

## Status
Cask creation deferred. README references `brew install --cask sotto` aspirationally.

## Pre-req
- `<DOMAIN>` DMG hosted at `https://<DOMAIN>/Sotto-<version>.dmg` (or GitHub release asset).
- Cask SHA256 + URL inside the formula.

## Action
File issue on user's `homebrew-tap` repo (or upstream `homebrew-cask` if quality bar is met) with cask formula:

\`\`\`ruby
cask "sotto" do
  version "<VERSION>"
  sha256 "<SHA>"
  url "https://<DOMAIN>/Sotto-#{version}.dmg"
  name "Sotto"
  desc "macOS dictation app — quietly under your voice"
  homepage "https://<DOMAIN>"
  app "Sotto.app"
end
\`\`\`

## Blocked by
- Spike S2 (domain registered)
- First Sotto release built + signed
```

- [ ] **Step 7C.2: Commit**

```bash
git add docs/superpowers/handoffs/HANDOFF_sotto_brew_cask.md
git commit -m "docs(rename-s7c): handoff for sotto brew cask creation

Deferred — depends on Sotto release + domain. Spec §6.4 (deferred backlog).
"
```

---

## Phase 3 · Wiring + audit

---

### Step 8: Wire `SottoBundleIdentityMigration.run()` into app init

The migration runs ON EVERY LAUNCH but is sentinel-gated → effectively first-launch-only.

**Files:**
- Modify: `VoiceInk/VoiceInk.swift:187` (insertion point — before `StreamingKeysMigration.run()`)

- [ ] **Step 8.1: Insert migration call**

`VoiceInk/VoiceInk.swift` — locate line 187:

```swift
// before
// 6. Initialize model state
// Migration and refreshAllAvailableModels must run before loadCurrentTranscriptionModel so renamed keys are remapped and imported models are present when restoring the saved selection.
StreamingKeysMigration.run()
```

Replace with:

```swift
// 6. Initialize model state
// Migration and refreshAllAvailableModels must run before loadCurrentTranscriptionModel so renamed keys are remapped and imported models are present when restoring the saved selection.
//
// SottoBundleIdentityMigration MUST precede StreamingKeysMigration: the
// streaming migration reads UserDefaults.standard, which is empty on the
// post-rename first launch until the identity migration lifts the legacy
// suite. Spec §7.1.UserDefaults.
SottoBundleIdentityMigration.run()
StreamingKeysMigration.run()
```

- [ ] **Step 8.2: Build + smoke (no legacy install on disk — verify no-op + sentinels set)**

```bash
make reload
```

After launch:

```bash
defaults read com.sotto.Sotto __sotto_identity_migrated_v1
defaults read com.sotto.Sotto __sotto_keychain_migrated_v1
```

Expected: both `1`.

- [ ] **Step 8.3: Commit**

```bash
git add VoiceInk/VoiceInk.swift
git commit -m "feat(rename-s8): wire SottoBundleIdentityMigration in VoiceInkApp.init

Runs before StreamingKeysMigration so the streaming shim reads the
post-migration UserDefaults. Sentinel-gated; no-op on fresh installs.
Spec §7.1.
"
```

---

### Step 9: GPL §5 audit + ACKNOWLEDGMENTS + grep-clean criterion

§7.1.GPL — `grep -ri 'voiceink' Sotto/` must return zero **except** carve-outs.

**Files:**
- Create: `ACKNOWLEDGMENTS.md`
- Audit: every Swift source body (excluding migration shims + KeychainService.legacyService + entitlements README + LICENSE/README/upstream-attribution)

- [ ] **Step 9.1: Create `ACKNOWLEDGMENTS.md`**

```markdown
# Acknowledgments

## Upstream

Sotto is a fork of [VoiceInk](https://github.com/Beingpax/VoiceInk) by
[Pax Joshi (@Beingpax)](https://github.com/Beingpax). Sotto is licensed
under GPL-v3, the same license as VoiceInk. Per GPL-v3 §5, copyright
notices in source headers are preserved verbatim where present.

## Specific upstream credits

- Audio capture loop, transcription pipeline orchestrator, and SwiftData
  schema design originate in VoiceInk and are retained largely as-is.
- The notch recorder panel (`NotchRecorderPanel.swift`) is the project's
  foundational invention.
- Sparkle integration, model-manager scaffolding, and the AI-enhancement
  service share architecture with upstream.

## Open-source dependencies

See `BUILDING.md` for the full dependency list (Sparkle, AXSwift, FluidAudio,
whisper.cpp, MLX, et al.). All retain their original licenses + attributions.
```

- [ ] **Step 9.2: Run the grep-clean audit**

```bash
grep -rin 'voiceink' \
    --include='*.swift' \
    --exclude-dir='.local-build' \
    --exclude-dir='.git' \
    VoiceInk/ \
    | grep -v 'SottoBundleIdentityMigration\.swift' \
    | grep -v 'KeychainService\.swift:.*legacyService' \
    | grep -v 'StreamingKeysMigration\.swift' \
    | grep -v '// '
```

Expected: zero unmatched results.

Carve-out paths (these may keep `voiceink` literals):
- `LICENSE` — verbatim GPL-v3
- `README.md` line 8-10, 25, 72 — upstream badges + fork-from URL
- `BUILDING.md` line 21, 62 — `git clone …Beingpax/VoiceInk.git`
- `ACKNOWLEDGMENTS.md` — entire file (intentional attribution)
- `VoiceInk/VoiceInk.entitlements:9` — `iCloud.com.prakashjoshipax.VoiceInk` CloudKit container (Option C; ADR in Step 3)
- `VoiceInk/VoiceInk.entitlements:36` — legacy keychain access group (dual-list per Step 4)
- `VoiceInk/VoiceInk.entitlements.README.md` — ADR
- `VoiceInk/VoiceInk.swift:318` — CloudKit container literal in `#if !LOCAL_BUILD`
- `VoiceInk/Services/SottoBundleIdentityMigration.swift` — legacy bundle ID, suite name, service string, dir name (all functional)
- `VoiceInk/Services/KeychainService.swift:13` — `legacyService` literal (read-fallback)
- `VoiceInk/Services/StreamingKeysMigration.swift` — pre-existing one-shot, untouched
- `appcast.xml` — historical Sparkle XML (transient until rebuilt)
- All files under `.local-build/`, `.git/`, `docs/superpowers/specs/`, `docs/superpowers/plans/`, `docs/superpowers/handoffs/` — spec/plan/handoff content
- All files under `docs/superpowers/research/` — historical research notes
- `VoiceInk/Assets.xcassets/AppIcon.appiconset/*.png` — binary assets (renamed in ICON pair, not RENAME)
- The Xcode project directory `VoiceInk.xcodeproj/` — pbxproj test target IDs preserved (`PRODUCT_BUNDLE_IDENTIFIER = com.prakashjoshipax.VoiceInkTests` etc.)

- [ ] **Step 9.3: If any non-carve-out hits remain, patch + re-run audit**

For each unexpected match, decide:
1. Replace `voiceink` → `Sotto` if it's user-facing copy.
2. Add to carve-out list above + document why in inline `// MARK: -` comment.
3. Delete if dead code.

- [ ] **Step 9.4: Commit**

```bash
git add ACKNOWLEDGMENTS.md
git commit -m "docs(rename-s9): ACKNOWLEDGMENTS + GPL §5 grep-clean audit pass

Source-header voiceink references audited; carve-out list documented
in plan (CloudKit container, legacy keychain group, migration shims,
upstream attribution). Spec §7.1.GPL.
"
```

---

### Step 10: Integration smoke test

Manual + scripted verification across the rename surfaces.

**Files:**
- None (verification only)

- [ ] **Step 10.1: Fresh-install smoke**

```bash
# Clear any prior Sotto domain state
defaults delete com.sotto.Sotto 2>/dev/null
rm -rf ~/Library/Application\ Support/com.sotto.Sotto

# Build + launch
make reload
```

Verify:
- App launches without crash.
- Menu bar icon appears.
- Bundle ID via `osascript -e 'tell application "System Events" to get bundle identifier of every process whose name is "VoiceInk"'` reports `com.sotto.Sotto`.
- Logger output: `log stream --predicate 'subsystem == "com.sotto.Sotto"' --info` shows initialization logs.

- [ ] **Step 10.2: Legacy-install migration smoke**

Pre-req: a `com.prakashjoshipax.VoiceInk` install with at least one transcript + one API key set. If unavailable, simulate:

```bash
# Seed legacy UserDefaults
defaults write com.prakashjoshipax.VoiceInk testSeedKey "seed_value"

# Seed legacy app-support directory
mkdir -p ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/WhisperModels
echo "smoke" > ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/smoke.txt
```

Then `make reload` and verify:

```bash
defaults read com.sotto.Sotto testSeedKey
# Expected: seed_value

ls ~/Library/Application\ Support/com.sotto.Sotto/smoke.txt
# Expected: file present

ls ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/ 2>&1
# Expected: No such file or directory (moved)

defaults read com.sotto.Sotto __sotto_identity_migrated_v1
# Expected: 1

defaults read com.sotto.Sotto __sotto_keychain_migrated_v1
# Expected: 1
```

- [ ] **Step 10.3: Sparkle feed reachability**

```bash
curl -sI "$(defaults read /Users/priyanshu/Desktop/Projects/pu/voiceink-fork/.local-build/Build/Products/Debug/VoiceInk.app/Contents/Info.plist SUFeedURL)"
```

Expected: 200 OK (if domain has feed) OR 404 (if stopgap — acceptable per Sparkle ADR).

- [ ] **Step 10.4: Console attribution check**

```bash
log stream --predicate 'subsystem BEGINSWITH "com.sotto"' --info --color none | head -5
```

Expected: lines with `subsystem: com.sotto.Sotto` (and `…Sotto.fluidaudio` once a transcription runs).

- [ ] **Step 10.5: Final commit (no code change; tag for downstream pairs)**

```bash
git commit --allow-empty -m "chore(rename-s10): integration smoke green; RENAME complete

Fresh-install + legacy-migration smokes pass. OSLog attribution under
com.sotto.Sotto. Keychain dual-read verified. SwiftData store
relocated. Sparkle pointed at Sotto domain (no automated handoff per
ADR). Downstream pairs (HUD, MENUBAR, SETTINGS, MAIN, ONBOARDING)
unblocked.
"
```

---

## Self-review (run before reporting back)

### Spec coverage

| Spec section | Tasked? |
|---|---|
| §0 bundle-ID rename | Step 5 |
| §5.1 wordmark `BrandMarks.wordmark` | OUT OF SCOPE — owned by HUD/MAIN (UI surfaces); RENAME owns only the identity change |
| §5 Acceptance (PRODUCT_NAME, CFBundleDisplayName, CFBundleName, CFBundleIdentifier, SUFeedURL, brew cask, marketing URL refs, grep clean) | Steps 5, 6, 7, 9 |
| §6.1 Surface 1 (app rename + migrations) | Phases 1-3 |
| §6.3 RENAME pair = critical path | Plan ordered RENAME first; downstream deps section |
| §7.1.UserDefaults | Step 2A |
| §7.1.SwiftData | Step 2B |
| §7.1.CloudKit Option C | Step 3 |
| §7.1.OSLog 51 instances | Step 1 |
| §7.1.Sparkle | Step 6 + Spike S3 |
| §7.1.GPL §5 carve-out | Step 9 |
| §7.1.Keychain dual-list | Steps 2C + 4 |
| Appendix B.Trademark | Spike S1 |
| Appendix B.Domain | Spike S2 |
| Appendix B.SparkleCutover | Spike S3 |
| Appendix C.RENAME | All steps cite file:line |

### Type consistency

- `OSLogSubsystems.app` (Step 1) referenced throughout (Step 2's shim, KeychainService rewrite).
- `SottoBundleIdentityMigration.newAppSupportDirName` used in Step 2B AND in `VoiceInk.swift` retargeting — single constant, no drift.
- `userDefaultsSentinel = "__sotto_identity_migrated_v1"` — only this sentinel referenced; Step 8 verifies the same key.
- `keychainSentinel = "__sotto_keychain_migrated_v1"` — same pattern, distinct sentinel for keychain sub-step (so partial failures can re-run only the failed sub-step).

### Placeholder scan

- `<DOMAIN_FROM_SPIKE_S2>` appears in Steps 6.1, 7A.1, 7B.1 — resolves at S2 completion. Not a placeholder in the prohibited sense (TBD/TODO); it's a parameter the spike feeds.
- `<VERSION>` / `<SHA>` in Step 7C's deferred cask handoff — explicitly deferred, not within RENAME's PR.

---

## Open questions for team-lead

1. **`.app` filename rename** — keep `VoiceInk.app` on disk (current) or rename target so it becomes `Sotto.app`? Latter requires Xcode UI work; trades textual-patch simplicity for filesystem cleanliness. Recommend defer to follow-up PR.
2. **README issues URL** — keep upstream `Beingpax/VoiceInk/issues` (current) or point at the user's fork repo's own issue tracker? Need user's fork URL.
3. **Sotto-specific GitHub repo** — does one exist? README + BUILDING currently reference `Beingpax/VoiceInk` for `git clone`. If the user has `<username>/sotto`, swap those lines.
4. **Spike S2 outcome** — confirm registered domain before Step 6 runs, or use stopgap (`<user>.github.io/sotto`) and file follow-up for cutover.
5. **Spike S1 outcome** — if USPTO collision found in Class 9/42, the entire plan needs renaming again. Worst case: ~2h of regex sweeps if `Sotto` → `<NewName>` (Steps 5-9 all touched).
