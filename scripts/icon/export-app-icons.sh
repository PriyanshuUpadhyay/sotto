#!/usr/bin/env bash
# Export Sotto app icon PNGs from halo-variant SVGs.
# Produces 7 PNGs that populate all 11 AppIcon.appiconset slots.
# Usage: bash scripts/icon/export-app-icons.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
mkdir -p "$OUT_DIR"

command -v rsvg-convert &>/dev/null || {
  echo "ERROR: rsvg-convert not found. Run: brew install librsvg"
  exit 1
}

for size in 1024 512; do
  rsvg-convert -w "$size" -h "$size" \
    "$SCRIPT_DIR/sotto-icon-large.svg" \
    -o "$OUT_DIR/sotto-${size}.png"
  printf "OK sotto-%s.png\n" "$size"
done

for size in 256 128 64; do
  rsvg-convert -w "$size" -h "$size" \
    "$SCRIPT_DIR/sotto-icon-medium.svg" \
    -o "$OUT_DIR/sotto-${size}.png"
  printf "OK sotto-%s.png\n" "$size"
done

for size in 32 16; do
  rsvg-convert -w "$size" -h "$size" \
    "$SCRIPT_DIR/sotto-icon-small.svg" \
    -o "$OUT_DIR/sotto-${size}.png"
  printf "OK sotto-%s.png\n" "$size"
done

echo ""
echo "All 7 PNGs written to $OUT_DIR"
