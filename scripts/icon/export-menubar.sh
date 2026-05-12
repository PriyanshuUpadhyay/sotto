#!/usr/bin/env bash
# Export Sotto menubar icon fallback PNGs.
# Source: sotto-icon-base.svg (transparent bg, glyph-only).
# Output: 22pt@1x (22px) and 22pt@2x (44px) for menuBarIcon.imageset.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
IMAGESET="$(git rev-parse --show-toplevel)/VoiceInk/Assets.xcassets/menuBarIcon.imageset"

command -v rsvg-convert &>/dev/null || {
  echo "ERROR: rsvg-convert not found. Run: brew install librsvg"
  exit 1
}

mkdir -p "$OUT_DIR"

rsvg-convert -w 22 -h 22 "$SCRIPT_DIR/sotto-icon-base.svg" \
  -o "$OUT_DIR/menuBarIcon-22.png"
echo "OK menuBarIcon-22.png (22x22px)"

rsvg-convert -w 44 -h 44 "$SCRIPT_DIR/sotto-icon-base.svg" \
  -o "$OUT_DIR/menuBarIcon-44.png"
echo "OK menuBarIcon-44.png (44x44px)"

cp "$OUT_DIR/menuBarIcon-22.png" "$IMAGESET/"
cp "$OUT_DIR/menuBarIcon-44.png" "$IMAGESET/"
echo "Copied to $IMAGESET"
