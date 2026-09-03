# Building Sotto

This guide provides detailed instructions for building Sotto from source.

## Prerequisites

Before you begin, ensure you have:
- macOS 26.0 or later
- Xcode (latest version recommended)
- Swift (latest version recommended)
- Git (for cloning repositories)

For `make dmg` and `make release` only:
- [uv](https://docs.astral.sh/uv/) (`brew install uv`). The packaging script runs
  `dmgbuild` through `uvx` to write the installer window layout; nothing is
  installed into the project.

For `make acceptance` only:
- Babashka (`bb`)
- A JDK on `PATH`. `acceptance/bb.edn` declares a Maven dependency, and
  Babashka shells out to `java` to resolve it. macOS ships a `/usr/bin/java`
  stub that is not a runtime, so a Homebrew JDK needs `PATH` and `JAVA_HOME`
  set, for example
  `export JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH="$JAVA_HOME/bin:$PATH"`.

## Quick Start with Makefile (Recommended)

The easiest way to build Sotto is using the included Makefile, which automates the entire build process including building and linking the whisper framework.

### Simple Build Commands

```bash
# Clone the repository and enter it
git clone https://github.com/PriyanshuUpadhyay/sotto.git
cd sotto

# Build everything (recommended for first-time setup)
make all

# Or for development (build and run)
make dev
```

### Available Makefile Commands

- `make check` or `make healthcheck` - Verify all required tools are installed
- `make whisper` - Clone and build whisper.cpp XCFramework automatically
- `make vad-model` - Fetch and checksum the Silero VAD model
- `make setup` - Prepare the whisper framework and fetch the VAD model
- `make build` - Build the Sotto Xcode project
- `make local` - Build for local use (no Apple Developer certificate needed)
- `make run` - Launch the built Sotto app
- `make reload` - Rebuild, kill the running instance, relaunch (dev loop)
- `make test` - Run the unit test suite headlessly (non-activating)
- `make dmg` - Package the local build into `dist/Sotto.dmg` (see [Distributing a DMG](#distributing-a-dmg))
- `make release` - Build and sign a release DMG plus its Sparkle appcast in `dist/releases`
- `make publish` - Upload what `make release` prepared (`make publish NOTES=path/to/notes.md`)
- `make dev` - Build and run (ideal for development workflow)
- `make all` - Complete build process (default)
- `make clean` - Remove build artifacts and dependencies
- `make help` - Show all available commands

### How the Makefile Helps

The Makefile automatically:
1. **Manages Dependencies**: Creates a dedicated `~/Sotto-Dependencies` directory for all external frameworks
2. **Builds Whisper Framework**: Clones whisper.cpp and builds the XCFramework with the correct configuration
3. **Fetches the VAD Model**: Downloads the Silero VAD weights and verifies the SHA-256 before the build
4. **Handles Framework Linking**: Sets up the whisper.xcframework in the proper location for Xcode to find
5. **Verifies Prerequisites**: Checks that git, xcodebuild, and swift are installed before building
6. **Streamlines Development**: Provides convenient shortcuts for common development tasks

This approach ensures consistent builds across different machines and eliminates manual framework setup errors.

## Silero VAD Model

The voice-activity-detection weights are not in git. `make setup` fetches them:

| | |
|---|---|
| Path | `Sotto/Resources/models/ggml-silero-v5.1.2.bin` |
| Source | `https://huggingface.co/ggml-org/whisper-vad/resolve/main/ggml-silero-v5.1.2.bin` |
| SHA-256 | `29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf` |
| License | MIT (Silero Team) |

The target fails the build if the download fails or the checksum does not match.
This matters because Xcode synchronized folders bundle whatever is on disk: an
absent file produces an app that runs with VAD silently disabled, with no error.

---

## Building for Local Use (No Apple Developer Certificate)

If you don't have an Apple Developer certificate, use `make local`:

```bash
git clone https://github.com/PriyanshuUpadhyay/sotto.git
cd sotto
make local
open -a Sotto
```

This builds Sotto using a separate build configuration (`LocalBuild.xcconfig`) that requires no Apple Developer account, and installs the app to `/Applications/Sotto.app`.

### Stable signing (optional, recommended)

By default `make local` looks for a self-signed code-signing certificate named
`sotto-local` in your login keychain. Signing with a stable certificate keeps the
app's cdhash constant across rebuilds, so macOS Accessibility / Input Monitoring
permissions persist. If the certificate is absent it falls back to ad-hoc signing
(permissions reset on each rebuild).

To create the certificate (one-time, ~30 sec):
- Keychain Access → Certificate Assistant → Create a Certificate…
  - Name: `sotto-local`
  - Identity Type: Self Signed Root
  - Certificate Type: Code Signing

### How It Works

The `make local` command uses:
- `LocalBuild.xcconfig` to override signing and entitlements settings
- `Sotto.local.entitlements` (stripped-down, no CloudKit/keychain groups)
- `LOCAL_BUILD` Swift compilation flag for conditional code paths

Your normal `make all` / `make build` commands are completely unaffected.

## Distributing a DMG

`make dmg` packages the `make local` app into `dist/Sotto.dmg` with the
drag-to-Applications installer window. The window layout (no toolbar or tab
bar, icon positions, background, volume icon) is written straight into the
volume's `.DS_Store` by `dmgbuild` from `scripts/dmg/settings.py`, so the
result does not depend on the Finder settings of the Mac that built it. The
artwork comes from `scripts/dmg/make-background.swift` and is re-rendered
whenever that file is newer than `scripts/dmg/background.png`.

The app is signed with the self-signed local certificate, not an Apple
Developer ID, so macOS blocks the first launch on another Mac. Tell
recipients to:

1. Open the DMG and drag Sotto onto the Applications folder shown.
2. Open Sotto from Applications. When macOS says it cannot verify the app, go to
   System Settings > Privacy & Security, scroll to Security, and click
   **Open Anyway**. Terminal fallback if that button does not appear:
   `xattr -dr com.apple.quarantine /Applications/Sotto.app`
3. Grant Accessibility and Input Monitoring when asked.

Updates after that arrive through the in-app updater and need no repeat of
step 2.

---

## Manual Build Process (Alternative)

If you prefer to build manually or need more control over the build process, follow these steps:

### Building whisper.cpp Framework

1. Clone and build whisper.cpp:
```bash
git clone https://github.com/ggerganov/whisper.cpp.git
cd whisper.cpp
./build-xcframework.sh
```
This will create the XCFramework at `build-apple/whisper.xcframework`.

### Building Sotto

1. Clone the repository and open `Sotto.xcodeproj` in Xcode.

2. Add the whisper.xcframework to your project:
   - Drag and drop `../whisper.cpp/build-apple/whisper.xcframework` into the project navigator, or
   - Add it manually in the "Frameworks, Libraries, and Embedded Content" section of project settings

3. Build and Run
   - Build the project using Cmd+B or Product > Build
   - Run the project using Cmd+R or Product > Run

## Development Setup

1. **Xcode Configuration**
   - Ensure you have the latest Xcode version
   - Install any required Xcode Command Line Tools

2. **Dependencies**
   - The project uses [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for transcription
   - Ensure the whisper.xcframework is properly linked in your Xcode project
   - Test the whisper.cpp installation independently before proceeding

3. **Building for Development**
   - Use the Debug configuration for development
   - Enable relevant debugging options in Xcode

4. **Testing**
   - Run `make test` before making changes
   - Ensure all tests pass after your modifications

## Troubleshooting

If you encounter any build issues:
1. Clean the build folder (Cmd+Shift+K)
2. Clean the build cache (Cmd+Shift+K twice)
3. Check Xcode and macOS versions
4. Verify all dependencies are properly installed
5. Make sure whisper.xcframework is properly built and linked
