#!/usr/bin/env bash
# Package the locally-built Sotto.app into a shareable, styled .dmg with the
# native drag-to-Applications installer window (Acid Lime brand background +
# the app icon as the disk's volume icon).
#
# Reuses the app produced by `make local` (the only build path known to run
# correctly — a plain Release xcodebuild compiles but crashes at runtime). The
# app is signed with the self-signed `sotto-local` cert, which other
# Macs do NOT trust, so friends must clear the download quarantine once:
#
#   xattr -dr com.apple.quarantine /Applications/Sotto.app
#
# Override the window background with BACKGROUND=/path/to/bg.(tiff|png).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP_PATH:-$ROOT/.local-build/Build/Products/Debug/Sotto.app}"
OUT_DIR="${OUT_DIR:-$ROOT/dist}"
VOL_NAME="${VOL_NAME:-Sotto}"
DMG="$OUT_DIR/Sotto.dmg"
RW_DMG="$OUT_DIR/.Sotto-rw.dmg"
BG_DIR="$ROOT/scripts/dmg"
BACKGROUND="${BACKGROUND:-$BG_DIR/background.tiff}"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found. Run 'make local' first." >&2
  exit 1
fi

# Generate the brand background if it's the default one and missing.
if [ "$BACKGROUND" = "$BG_DIR/background.tiff" ] && [ ! -f "$BACKGROUND" ]; then
  if command -v swift >/dev/null 2>&1; then
    echo "Generating brand DMG background..."
    ( cd "$BG_DIR" && swift make-background.swift >/dev/null \
        && tiffutil -cathidpicheck background.png background@2x.png -out background.tiff >/dev/null )
  else
    echo "  note: swift not found — building DMG without a background image."
    BACKGROUND=""
  fi
fi

echo "Packaging: $APP"
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 \
  && echo "  signature: valid (self-signed; untrusted on other Macs — expected)" \
  || echo "  signature: WARNING — codesign --verify failed; app may show as 'damaged'"

# --- stage app + Applications symlink (sizes the image) -------------------
STAGING="$(mktemp -d)"
cleanup() { rm -rf "$STAGING"; [ -f "$RW_DMG" ] && rm -f "$RW_DMG" || true; }
trap cleanup EXIT
ditto "$APP" "$STAGING/Sotto.app"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$OUT_DIR"
rm -f "$DMG" "$RW_DMG"

# Detach any stale mount of this volume from earlier runs (avoids writing to
# the wrong "/Volumes/Sotto 1" copy).
while [ -d "/Volumes/$VOL_NAME" ]; do
  hdiutil detach "/Volumes/$VOL_NAME" -force >/dev/null 2>&1 || break
done

SIZE_MB=$(( $(du -sm "$STAGING" | cut -f1) + 60 ))
hdiutil create -volname "$VOL_NAME" -srcfolder "$STAGING" \
  -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW_DMG" >/dev/null

# --- mount, capturing the REAL device + mountpoint ------------------------
ATTACH="$(hdiutil attach "$RW_DMG" -nobrowse -noautoopen)"
DEV="$(echo "$ATTACH"  | awk '/^\/dev\// && /Apple_HFS/{print $1; exit}')"
MNT="$(echo "$ATTACH"  | sed -n 's#^/dev/[^[:space:]]*[[:space:]]*Apple_HFS[[:space:]]*##p' | head -1)"
[ -d "$MNT" ] || { echo "error: could not determine mountpoint" >&2; exit 1; }

# Background image into .background/
BG_LINE=""
if [ -n "$BACKGROUND" ] && [ -f "$BACKGROUND" ]; then
  mkdir -p "$MNT/.background"
  BG_BASENAME="bg.${BACKGROUND##*.}"
  cp "$BACKGROUND" "$MNT/.background/$BG_BASENAME"
  BG_LINE="set background picture of theViewOptions to file \".background:$BG_BASENAME\""
fi

# --- style the Finder window ---------------------------------------------
/usr/bin/osascript <<APPLESCRIPT || echo "  note: window styling skipped (Finder scripting unavailable)"
tell application "Finder"
  tell disk "$VOL_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 840, 520}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set text size of theViewOptions to 12
    $BG_LINE
    set position of item "Sotto.app" of container window to {165, 205}
    set position of item "Applications" of container window to {475, 205}
    update without registering applications
    delay 3
    close
  end tell
end tell
APPLESCRIPT

# Volume icon = app icon. Done LAST so Finder's window-styling pass can't clobber
# the custom-icon bit. Needs both the .icns at root AND the volume's 'C' attr.
ICNS="$APP/Contents/Resources/AppIcon.icns"
if [ -f "$ICNS" ] && command -v SetFile >/dev/null 2>&1; then
  cp "$ICNS" "$MNT/.VolumeIcon.icns"
  SetFile -a V "$MNT/.VolumeIcon.icns"          # hidden
  [ -d "$MNT/.background" ] && SetFile -a V "$MNT/.background"
  SetFile -a C "$MNT"
  if [ "$(GetFileInfo -aC "$MNT" 2>/dev/null)" = "1" ]; then
    echo "  volume icon: set ✔"
  else
    echo "  volume icon: WARNING — custom-icon bit not set"
  fi
fi

sync
hdiutil detach "$DEV" >/dev/null

# --- compress to the final read-only DMG ----------------------------------
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW_DMG"

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
echo "  1. Open the DMG, drag Sotto onto the Applications folder shown."
echo "  2. Run once in Terminal (clears Apple's download quarantine):"
echo "       xattr -dr com.apple.quarantine /Applications/Sotto.app"
echo "  3. Open Sotto. Grant Accessibility + Input Monitoring when asked"
echo "     (System Settings > Privacy & Security)."
