#!/usr/bin/env bash
# Package the locally-built Sotto.app into a shareable, styled .dmg with the
# native drag-to-Applications installer window (Acid Lime brand background +
# the app icon as the disk's volume icon).
#
# The Finder window layout is written straight into the volume's .DS_Store by
# dmgbuild (settings in scripts/dmg/settings.py), not recorded through Finder
# scripting: on macOS 26 Finder persists the build Mac's tab bar and shifts
# every icon when a hidden item lands above the window, so a recorded layout
# depended on whichever Finder settings the build Mac happened to have.
#
# Reuses the app produced by `make local` (the only build path known to run
# correctly — a plain Release xcodebuild compiles but crashes at runtime). The
# app is signed with the self-signed `sotto-local` cert, which other Macs do
# NOT trust, so a recipient allows it once (instructions printed at the end).
#
# Override the window background with BACKGROUND=/path/to/bg.png; a
# <name>@2x<ext> sibling next to it is picked up automatically.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP_PATH:-$ROOT/.local-build/Build/Products/Debug/Sotto.app}"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
VOL_NAME="${VOL_NAME:-Sotto}"
DMG="$OUT_DIR/Sotto.dmg"
BG_DIR="$ROOT/scripts/dmg"
BACKGROUND="${BACKGROUND:-$BG_DIR/background.png}"
ICNS="$APP/Contents/Resources/AppIcon.icns"
# Pinned: the settings file relies on this version's option names and on it
# placing the art at <volume>/.background.tiff.
DMGBUILD_SPEC="dmgbuild==1.6.7"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run 'make local' first." >&2
  exit 1
fi
[ -f "$ICNS" ] || { echo "error: app icon not found: $ICNS" >&2; exit 1; }
command -v uv >/dev/null 2>&1 \
  || { echo "error: uv is required for make dmg (brew install uv)" >&2; exit 1; }

# Render the brand background when it is the default one and missing or older
# than its generator.
if [ "$BACKGROUND" = "$BG_DIR/background.png" ] \
   && { [ ! -f "$BACKGROUND" ] || [ "$BG_DIR/make-background.swift" -nt "$BACKGROUND" ]; }; then
  command -v swift >/dev/null 2>&1 \
    || { echo "error: swift is required to render $BACKGROUND" >&2; exit 1; }
  echo "Generating brand DMG background..."
  ( cd "$BG_DIR" && swift make-background.swift >/dev/null )
fi
[ -f "$BACKGROUND" ] || { echo "error: background not found: $BACKGROUND" >&2; exit 1; }

echo "Packaging: $APP"
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 \
  && echo "  signature: valid (self-signed; untrusted on other Macs — expected)" \
  || echo "  signature: WARNING — codesign --verify failed; app may show as 'damaged'"

mkdir -p "$OUT_DIR"
rm -f "$DMG"

# Detach any stale mount of this volume from earlier runs so dmgbuild's own
# mount does not land on "/Volumes/$VOL_NAME 1".
while [ -d "/Volumes/$VOL_NAME" ]; do
  hdiutil detach "/Volumes/$VOL_NAME" -force >/dev/null 2>&1 || break
done

echo "Writing $DMG..."
uvx --from "$DMGBUILD_SPEC" dmgbuild \
  -s "$BG_DIR/settings.py" \
  -D "app=$APP" -D "background=$BACKGROUND" -D "icon=$ICNS" \
  "$VOL_NAME" "$DMG"

# Offscreen preview of how a clean recipient sees the installer window.
if command -v swift >/dev/null 2>&1 && [ -f "$BG_DIR/make-preview.swift" ]; then
  swift "$BG_DIR/make-preview.swift" "$APP" "$OUT_DIR/installer-preview.png" >/dev/null 2>&1 \
    && echo "Preview: $OUT_DIR/installer-preview.png (clean-Mac render)"
fi

echo ""
echo "Created: $DMG"
echo "Size:    $(du -h "$DMG" | cut -f1)"
echo ""
echo "Send this DMG to friends. Tell them to:"
echo "  1. Open the DMG and drag Sotto onto the Applications folder shown."
echo "  2. Open Sotto from Applications. macOS blocks the first launch because"
echo "     the app is not notarized: go to System Settings > Privacy & Security,"
echo "     scroll to Security, and click \"Open Anyway\"."
echo "     Terminal fallback:  xattr -dr com.apple.quarantine /Applications/Sotto.app"
echo "  3. Grant Accessibility + Input Monitoring when asked"
echo "     (System Settings > Privacy & Security)."
