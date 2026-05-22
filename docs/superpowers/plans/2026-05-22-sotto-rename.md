# VoiceInk → Sotto Rename Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the app's build identity and user-facing strings from "VoiceInk" to "Sotto" so `make reload` produces `/Applications/Sotto.app` and no "VoiceInk" appears in the IDE, build output, or anything a user sees.

**Architecture:** Direct `project.pbxproj` text edits + targeted `git mv` file renames, headless (no Xcode GUI). Persistence identifiers (`com.prakashjoshipax.VoiceInk` App-Support/iCloud/keychain) are deliberately untouched — a migration service owns them. Verified by `xcodebuild` build + `build-for-testing` + `make local`.

**Tech Stack:** Xcode project (`.pbxproj`, `.xcscheme`), Swift, Make.

**Spec:** `docs/superpowers/specs/2026-05-22-sotto-rename-design.md`

---

## File Structure

| File | Change |
|------|--------|
| `VoiceInk.xcodeproj/` → `Sotto.xcodeproj/` | Directory renamed (`git mv`) |
| `Sotto.xcodeproj/project.pbxproj` | Target/product/scheme settings + comments |
| `…/xcschemes/VoiceInk.xcscheme` → `Sotto.xcscheme` | Renamed + contents rewritten |
| `VoiceInk/VoiceInk.entitlements` → `VoiceInk/Sotto.entitlements` | Renamed (contents unchanged) |
| `VoiceInk/VoiceInk.local.entitlements` → `VoiceInk/Sotto.local.entitlements` | Renamed (contents unchanged) |
| `VoiceInkTests/*.swift` (12 files) | `@testable import VoiceInk` → `import Sotto` |
| `Makefile` | Scheme/project/app-path/process-name references |
| `VoiceInk/WindowManager.swift`, `HistoryWindowController.swift`, `EmailSupport.swift`, `VoiceInk.swift`, +grep sweep | User-facing strings |

**Directories `VoiceInk/`, `VoiceInkTests/`, `VoiceInkUITests/` are NOT renamed** — synchronized groups reference them by path; invisible to users.

---

## Task 1: Rename Xcode project, scheme, and entitlements

**Files:**
- Rename: `VoiceInk.xcodeproj/` → `Sotto.xcodeproj/`
- Rename: `Sotto.xcodeproj/xcshareddata/xcschemes/VoiceInk.xcscheme` → `Sotto.xcscheme`
- Rename: `VoiceInk/VoiceInk.entitlements` → `VoiceInk/Sotto.entitlements`
- Rename: `VoiceInk/VoiceInk.local.entitlements` → `VoiceInk/Sotto.local.entitlements`
- Modify: `Sotto.xcodeproj/project.pbxproj`
- Modify: `Sotto.xcodeproj/xcshareddata/xcschemes/Sotto.xcscheme`

- [ ] **Step 1: Rename the four paths with `git mv`**

```bash
git mv VoiceInk.xcodeproj Sotto.xcodeproj
git mv Sotto.xcodeproj/xcshareddata/xcschemes/VoiceInk.xcscheme Sotto.xcodeproj/xcshareddata/xcschemes/Sotto.xcscheme
git mv VoiceInk/VoiceInk.entitlements VoiceInk/Sotto.entitlements
git mv VoiceInk/VoiceInk.local.entitlements VoiceInk/Sotto.local.entitlements
```

The entitlements file *contents* are NOT edited — they keep `com.prakashjoshipax.VoiceInk` (iCloud container + keychain group); renaming those orphans user data.

- [ ] **Step 2: Edit `Sotto.xcodeproj/project.pbxproj` — functional settings**

Apply these exact string replacements (each `old` string is unique or appears with the noted count; use replace-all where count > 1). Do NOT use a blind global replace — several `VoiceInk` tokens must survive (see Step 4 note).

| # | old | new | count |
|---|-----|-----|-------|
| A | `path = VoiceInk.app;` | `path = Sotto.app;` | 1 |
| B | `path = VoiceInkTests.xctest;` | `path = SottoTests.xctest;` | 1 |
| C | `path = VoiceInkUITests.xctest;` | `path = SottoUITests.xctest;` | 1 |
| D | `name = VoiceInk;` | `name = Sotto;` | 1 |
| E | `name = VoiceInkTests;` | `name = SottoTests;` | 1 |
| F | `name = VoiceInkUITests;` | `name = SottoUITests;` | 1 |
| G | `productName = VoiceInk;` | `productName = Sotto;` | 1 |
| H | `productName = VoiceInkTests;` | `productName = SottoTests;` | 1 |
| I | `productName = VoiceInkUITests;` | `productName = SottoUITests;` | 1 |
| J | `remoteInfo = VoiceInk;` | `remoteInfo = Sotto;` | 2 |
| K | `CODE_SIGN_ENTITLEMENTS = VoiceInk/VoiceInk.entitlements;` | `CODE_SIGN_ENTITLEMENTS = VoiceInk/Sotto.entitlements;` | 2 |
| L | `PRODUCT_BUNDLE_IDENTIFIER = com.prakashjoshipax.VoiceInkTests;` | `PRODUCT_BUNDLE_IDENTIFIER = com.sotto.SottoTests;` | 2 |
| M | `PRODUCT_BUNDLE_IDENTIFIER = com.prakashjoshipax.VoiceInkUITests;` | `PRODUCT_BUNDLE_IDENTIFIER = com.sotto.SottoUITests;` | 2 |
| N | `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/VoiceInk.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/VoiceInk";` | `TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Sotto.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Sotto";` | 2 |
| O | `TEST_TARGET_NAME = VoiceInk;` | `TEST_TARGET_NAME = Sotto;` | 2 |

(Edit D's `name = VoiceInk;` ends in `;`, so it does not match `name = VoiceInkTests;`.)

- [ ] **Step 3: Edit `Sotto.xcodeproj/project.pbxproj` — comments (cosmetic)**

Xcode auto-regenerates `/* … */` comments, so these do not affect the build — but update them so the file is not half-renamed. Apply as replace-all:

| # | old | new |
|---|-----|-----|
| P | `Build configuration list for PBXProject "VoiceInk"` | `Build configuration list for PBXProject "Sotto"` |
| Q | `PBXNativeTarget "VoiceInk" */` | `PBXNativeTarget "Sotto" */` |
| R | `PBXNativeTarget "VoiceInkTests"` | `PBXNativeTarget "SottoTests"` |
| S | `PBXNativeTarget "VoiceInkUITests"` | `PBXNativeTarget "SottoUITests"` |
| T | `/* VoiceInk.app */` | `/* Sotto.app */` |
| U | `/* VoiceInkTests.xctest */` | `/* SottoTests.xctest */` |
| V | `/* VoiceInkUITests.xctest */` | `/* SottoUITests.xctest */` |
| W | `E11473AF2CBE0F0A00318EE4 /* VoiceInk */` | `E11473AF2CBE0F0A00318EE4 /* Sotto */` |
| X | `E11473C22CBE0F0B00318EE4 /* VoiceInkTests */` | `E11473C22CBE0F0B00318EE4 /* SottoTests */` |
| Y | `E11473CC2CBE0F0B00318EE4 /* VoiceInkUITests */` | `E11473CC2CBE0F0B00318EE4 /* SottoUITests */` |

W/X/Y carry the **target** UUIDs. The bare comments `/* VoiceInk */`, `/* VoiceInkTests */`, `/* VoiceInkUITests */` that carry the **group** UUIDs `E11473B22…`, `E11473C62…`, `E11473D02…` must be LEFT — they label the kept source directories.

- [ ] **Step 4: Rewrite `Sotto.xcodeproj/xcshareddata/xcschemes/Sotto.xcscheme`**

Replace the file's entire contents with (every `VoiceInk` in the scheme becomes a Sotto name; `BlueprintIdentifier` UUIDs are unchanged):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2620"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "E11473AF2CBE0F0A00318EE4"
               BuildableName = "Sotto.app"
               BlueprintName = "Sotto"
               ReferencedContainer = "container:Sotto.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES"
      shouldAutocreateTestPlan = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "E11473C22CBE0F0B00318EE4"
               BuildableName = "SottoTests.xctest"
               BlueprintName = "SottoTests"
               ReferencedContainer = "container:Sotto.xcodeproj">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "E11473CC2CBE0F0B00318EE4"
               BuildableName = "SottoUITests.xctest"
               BlueprintName = "SottoUITests"
               ReferencedContainer = "container:Sotto.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "E11473AF2CBE0F0A00318EE4"
            BuildableName = "Sotto.app"
            BlueprintName = "Sotto"
            ReferencedContainer = "container:Sotto.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "E11473AF2CBE0F0A00318EE4"
            BuildableName = "Sotto.app"
            BlueprintName = "Sotto"
            ReferencedContainer = "container:Sotto.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 5: Build the app target**

Run:
```bash
xcodebuild build -scheme Sotto -project Sotto.xcodeproj -configuration Debug \
  -derivedDataPath .local-build -skipMacroValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet
```
Expected: `** BUILD SUCCEEDED **`, exit 0, no `error:` lines. Then confirm the product name:
```bash
ls -d .local-build/Build/Products/Debug/Sotto.app
```
Expected: the path exists (proves the rename produced `Sotto.app`).

Then confirm the project structure and the built bundle's identity:
```bash
xcodebuild -list -project Sotto.xcodeproj
plutil -p .local-build/Build/Products/Debug/Sotto.app/Contents/Info.plist | grep -E 'CFBundleName|CFBundleDisplayName|CFBundleExecutable'
```
Expected: `xcodebuild -list` lists targets `Sotto`, `SottoTests`, `SottoUITests` and scheme `Sotto` (no `VoiceInk`); the plist shows `CFBundleName` = `Sotto`, `CFBundleDisplayName` = `Sotto`, `CFBundleExecutable` = `Sotto`.

The scheme's `BuildAction` lists only the app target, so this build does not touch the test targets — stale test imports (fixed in Task 2) will not fail it.

- [ ] **Step 6: Commit**

This commit is intentionally a partial state — the app target builds, but the test
targets will not compile until Task 2 updates their imports. That is expected.

```bash
git add -A
git commit -m "build: rename Xcode project/target/scheme VoiceInk→Sotto"
```

---

## Task 2: Update Swift module imports in tests

Renaming the target renamed the Swift module to `Sotto`. The test targets still `@testable import VoiceInk` and will not compile until updated.

**Files:**
- Modify: every `*.swift` under `VoiceInkTests/` containing `import VoiceInk` (~12 files)

- [ ] **Step 1: Enumerate the import sites**

Run:
```bash
grep -rln "import VoiceInk" VoiceInkTests VoiceInkUITests
grep -rln "import VoiceInk" VoiceInk   # expect NO output — a target never imports itself
```
Record the file list from the first command. If the second prints anything, stop and report — it is unexpected and must be assessed before proceeding.

- [ ] **Step 2: Replace the import in each file**

In every file from Step 1, replace:
- `@testable import VoiceInk` → `@testable import Sotto`
- plain `import VoiceInk` (if any) → `import Sotto`

Match the whole-line token `VoiceInk` only in the `import` statement — do not touch other occurrences.

- [ ] **Step 3: Build the test targets**

Run:
```bash
xcodebuild build-for-testing -scheme Sotto -project Sotto.xcodeproj -configuration Debug \
  -derivedDataPath .local-build -skipMacroValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet
```
Expected: `** TEST BUILD SUCCEEDED **` (or `** BUILD SUCCEEDED **`), exit 0, no `error:` lines — confirms `SottoTests`/`SottoUITests` compile and `import Sotto` resolves. Tests are not run (the launcher is documented as fragile; compilation is the gate).

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "test: update @testable import VoiceInk→Sotto"
```

---

## Task 3: Update the Makefile

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Apply replacements**

Apply as replace-all in `Makefile`:

| old | new |
|-----|-----|
| `VoiceInk.xcodeproj` | `Sotto.xcodeproj` |
| `-scheme VoiceInk ` (trailing space) | `-scheme Sotto ` |
| `VoiceInk.app` | `Sotto.app` |
| `VoiceInk.local.entitlements` | `Sotto.local.entitlements` |
| `killall VoiceInk` | `killall Sotto` |
| `open -a VoiceInk` | `open -a Sotto` |

Then these single echo/help-text edits:

| old | new |
|-----|-----|
| `"Building VoiceInk for local use..."` | `"Building Sotto for local use..."` |
| `Copy whisper XCFramework to VoiceInk project` | `Copy whisper XCFramework to Sotto project` |
| `Build the VoiceInk Xcode project` | `Build the Sotto Xcode project` |
| `Launch the built VoiceInk app` | `Launch the built Sotto app` |
| `Killing running VoiceInk instance (if any)...` | `Killing running Sotto instance (if any)...` |

**Do NOT change** (these must remain "VoiceInk"): `DEPS_DIR := $(HOME)/VoiceInk-Dependencies`, the `voiceink-fork-local` signing-cert name (×2), and the `VoiceInk/` directory prefix in `$(CURDIR)/VoiceInk/Sotto.local.entitlements`.

- [ ] **Step 2: Verify with a local build**

Run:
```bash
make local
```
Expected: `** BUILD SUCCEEDED **`, then `Build complete! App saved to: /Applications/Sotto.app`, and:
```bash
ls -d /Applications/Sotto.app
```
exists. (The Makefile's `rm -rf` + `ditto` replaces the stale May-21 `Sotto.app`.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "build: point Makefile at the Sotto scheme and app"
```

---

## Task 4: Update user-facing strings

**Files:**
- Modify: `VoiceInk/WindowManager.swift`, `VoiceInk/HistoryWindowController.swift`, `VoiceInk/EmailSupport.swift`, `VoiceInk/VoiceInk.swift`, plus any other file surfaced by the sweep.

- [ ] **Step 1: Enumerate user-facing "VoiceInk" strings**

Run:
```bash
grep -rn '"[^"]*VoiceInk' VoiceInk --include='*.swift'
```
Review each hit. A string is **user-facing** if it appears in a window title, alert/dialog text, notification, email subject, menu item, onboarding/About copy, or similar. It is **NOT user-facing** (leave it) if it is a `DispatchQueue` label, a `UserDefaults`/identifier key, a window autosave name, a log subsystem, or a persistence path containing `com.prakashjoshipax.VoiceInk`.

- [ ] **Step 2: Update the known user-facing strings**

- `VoiceInk/WindowManager.swift` — `window.title = "VoiceInk"` → `window.title = "Sotto"`
- `VoiceInk/HistoryWindowController.swift` — `"VoiceInk — Transcription History"` → `"Sotto — Transcription History"`
- `VoiceInk/EmailSupport.swift` — `"VoiceInk Support Request"` → `"Sotto Support Request"`
- `VoiceInk/VoiceInk.swift` — error-dialog text `"VoiceInk couldn't access its storage location…"` → `"Sotto couldn't access its storage location…"` (both occurrences)

- [ ] **Step 3: Update any other user-facing strings from Step 1**

For each remaining user-facing hit from Step 1 (e.g. onboarding/About copy, notification titles), replace "VoiceInk" with "Sotto". Leave every non-user-facing hit untouched.

- [ ] **Step 4: Build and run the final grep sweep**

Run:
```bash
xcodebuild build -scheme Sotto -project Sotto.xcodeproj -configuration Debug \
  -derivedDataPath .local-build -skipMacroValidation \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet
```
Expected: `** BUILD SUCCEEDED **`, exit 0.

Then:
```bash
grep -rin voiceink VoiceInk Sotto Makefile Sotto.xcodeproj/project.pbxproj
```
Every remaining hit MUST fall into an approved non-goal category:
- directory names `VoiceInk/`, `VoiceInkTests/`, `VoiceInkUITests/` (and paths under them);
- `~/VoiceInk-Dependencies`, the `voiceink-fork-local` cert name;
- persistence identifiers `com.prakashjoshipax.VoiceInk` (entitlements file contents, App-Support/iCloud/keychain code);
- internal `DispatchQueue`/identifier strings `com.prakashjoshipax.voiceink.*`;
- the `@main struct VoiceInkApp` symbol and its references;
- pbxproj synchronized-group comments/paths (`/* VoiceInk */` group labels, `path = VoiceInk*`, `INFOPLIST_FILE`, `DEVELOPMENT_ASSET_PATHS`).

If a hit does not fit one of these, fix it (or report it if its classification is unclear). Do not grep `docs/` — historical specs/handoffs keep their original wording.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: rename user-facing VoiceInk strings to Sotto"
```

---

## Verification Summary

| Task | Gate |
|------|------|
| 1 | `xcodebuild build -scheme Sotto` → `** BUILD SUCCEEDED **`; `Sotto.app` produced |
| 2 | `xcodebuild build-for-testing -scheme Sotto` → test targets compile |
| 3 | `make local` → `/Applications/Sotto.app` installed |
| 4 | `xcodebuild build` green; grep sweep shows only approved non-goal remainders |

After all tasks: `make reload` launches `/Applications/Sotto.app`; the running process and Dock/menu-bar identity read "Sotto".

## Non-Goals (do not touch)

Source/test directory names; the `@main struct VoiceInkApp` symbol; `~/VoiceInk-Dependencies`; the `voiceink-fork-local` signing cert; `com.prakashjoshipax.VoiceInk` App-Support/iCloud/keychain identifiers (a migration service owns these — renaming orphans user data); `docs/` historical wording.
