# Design: VoiceInk → Sotto rename

**Date:** 2026-05-22
**Status:** approved — ready for implementation plan
**Branch:** `worktree-rename+voiceink-to-sotto`

## Goal

The app's identity is "Sotto" end to end: `make reload` builds `/Applications/Sotto.app`,
and no "VoiceInk" string appears in the IDE, the build output, or anywhere a user sees.
Persistence identifiers stay untouched — a migration service already owns them, and
renaming them would orphan existing user data.

The bundle id (`com.sotto.Sotto`) and display name (`Sotto`) are already correct. This
rename closes the remaining gap: the Xcode target/scheme/project, the built `.app`, the
Swift module, the Makefile, the test targets, and user-facing strings.

## Approach

Direct `project.pbxproj` text edits plus targeted file renames via CLI — the environment
is headless, so no Xcode GUI. The change set is a known, finite list, so no project-
manipulation tooling dependency is introduced. All work on one branch, build-verified.

**Rejected alternatives:**
- Xcode GUI rename — no GUI available in this environment.
- `PRODUCT_MODULE_NAME = VoiceInk` to avoid updating test imports — leaves the target
  named `Sotto` but the module named `VoiceInk`, a permanent inconsistency. Not worth
  dodging 12 one-line import edits.

## Change set

### 1. Xcode project (`VoiceInk.xcodeproj` → `Sotto.xcodeproj`, `project.pbxproj`)

- Rename the `.xcodeproj` bundle directory `VoiceInk.xcodeproj` → `Sotto.xcodeproj`.
- Targets: `VoiceInk` → `Sotto`, `VoiceInkTests` → `SottoTests`,
  `VoiceInkUITests` → `SottoUITests` (`name` + `productName`).
- Product file references: `VoiceInk.app` → `Sotto.app`,
  `VoiceInkTests.xctest` → `SottoTests.xctest`,
  `VoiceInkUITests.xctest` → `SottoUITests.xctest`.
- `TEST_HOST` and `TEST_TARGET_NAME` → `Sotto`.
- Test bundle ids: `com.prakashjoshipax.VoiceInkTests` → `com.sotto.SottoTests`,
  `com.prakashjoshipax.VoiceInkUITests` → `com.sotto.SottoUITests`.
- `CODE_SIGN_ENTITLEMENTS`: `VoiceInk/VoiceInk.entitlements` → `VoiceInk/Sotto.entitlements`.
- PBXProject name strings (cosmetic comments) → `Sotto`.

**Unchanged:** `PRODUCT_NAME = $(TARGET_NAME)` (auto-resolves to `Sotto` once the target
is renamed), `INFOPLIST_FILE = VoiceInk/Info.plist`,
`DEVELOPMENT_ASSET_PATHS = "VoiceInk/Preview Content"`, and the
`fileSystemSynchronizedGroups` directory paths (`VoiceInk`, `VoiceInkTests`,
`VoiceInkUITests`) — see Non-goals.

### 2. Files renamed on disk

- `VoiceInk.xcodeproj/xcshareddata/xcschemes/VoiceInk.xcscheme` → `Sotto.xcscheme`
  (and the `BlueprintName` / `BuildableName` values inside, for all three targets — the
  scheme stays **shared** so `xcodebuild -scheme Sotto` resolves it).
- `VoiceInk/VoiceInk.entitlements` → `VoiceInk/Sotto.entitlements`.

The three source directories — `VoiceInk/`, `VoiceInkTests/`, `VoiceInkUITests/` — are
**kept**. A `PBXFileSystemSynchronizedRootGroup` points at a path; the owning target
need not share that path's name.

### 3. Swift module

Renaming the target renames the module to `Sotto`. Update `@testable import VoiceInk` →
`@testable import Sotto` in the 12 files under `VoiceInkTests/`. (App-target code does
not import its own module, so no app-side import changes are expected — to be confirmed
by grep during implementation.)

### 4. Makefile

- `-scheme VoiceInk` → `-scheme Sotto`; `-project VoiceInk.xcodeproj` →
  `-project Sotto.xcodeproj` if present.
- All `VoiceInk.app` paths → `Sotto.app`; `/Applications/VoiceInk.app` →
  `/Applications/Sotto.app`.
- `killall VoiceInk` → `killall Sotto`; `open -a VoiceInk` → `open -a Sotto`.
- Help text "VoiceInk" → "Sotto".
- **Kept:** `DEPS_DIR := $(HOME)/VoiceInk-Dependencies` — a build-dependency cache
  (whisper.cpp), shared across worktrees and already built; renaming it would require
  moving a real external directory for zero user benefit.

### 5. User-facing strings → "Sotto"

- Window titles: `WindowManager.swift`, `HistoryWindowController.swift`.
- Email subject: `EmailSupport.swift`.
- Error-dialog text: `VoiceInk.swift`.
- A repo-wide grep sweep for any other user-visible "VoiceInk" string (onboarding,
  About panel, notifications) — each judged user-facing or not, and updated if so.

### 6. Info.plist

No change. `CFBundleName` / `CFBundleDisplayName` are already "Sotto"; there is no
hardcoded `CFBundleExecutable` key, so the executable name follows the target rename
via the build-injected `$(EXECUTABLE_NAME)`.

## Non-goals

- **Source/test directory names** (`VoiceInk/`, `VoiceInkTests/`, `VoiceInkUITests/`) —
  invisible to users; renaming moves hundreds of files for no functional gain.
- **`@main struct VoiceInkApp`** — an internal symbol; nothing references it by name.
- **`~/VoiceInk-Dependencies`** — external build cache (see Makefile, above).
- **Persistence identifiers** — Application Support paths, the iCloud container, and
  keychain access groups all use `com.prakashjoshipax.VoiceInk`. `SottoBundleIdentityMigration`
  already owns the transition; renaming these strings here would orphan existing user
  data and double-handle the migration.

## Verification

- `xcodebuild build -scheme Sotto -project Sotto.xcodeproj -configuration Debug
  -derivedDataPath .local-build -skipMacroValidation CODE_SIGN_IDENTITY=-
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet` — succeeds; the built bundle
  is `Sotto.app`.
- `xcodebuild build-for-testing -scheme Sotto …` — `SottoTests` and `SottoUITests`
  compile, confirming `@testable import Sotto` resolves. Compile only — the test
  launcher is documented as fragile, so tests are not run.
- `make reload` — installs and launches `/Applications/Sotto.app`. The Makefile's
  `rm -rf` + `ditto` auto-replaces the stale May-21 `Sotto.app`.
- `grep -ri "voiceink"` across the repo — only the deliberate non-goal references
  remain (directory names, `~/VoiceInk-Dependencies`, `com.prakashjoshipax.VoiceInk`
  persistence ids).

## Risks

- **`project.pbxproj` corruption** — text edits to a structured file. The build catches
  any breakage immediately; the change is on an isolated branch.
- **Scheme discovery** — the renamed scheme must remain in `xcshareddata` (shared) for
  `xcodebuild -scheme Sotto` to find it. Preserved by renaming in place.
