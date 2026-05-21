#!/usr/bin/env bash
# Verify all Sotto icon assets meet §5.3 acceptance criteria.
# Run after export-app-icons.sh and export-menubar.sh.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"
APPICONSET="$REPO_ROOT/VoiceInk/Assets.xcassets/AppIcon.appiconset"
MENUBAR="$REPO_ROOT/VoiceInk/Assets.xcassets/menuBarIcon.imageset"

PASS=0
FAIL=0

check() {
  local file="$1" expected_px="$2"
  if [ ! -f "$file" ]; then
    echo "MISSING: $file"
    FAIL=$((FAIL+1))
    return
  fi
  actual=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  if [ "$actual" = "$expected_px" ]; then
    echo "OK $(basename "$file"): ${actual}px"
    PASS=$((PASS+1))
  else
    echo "FAIL $(basename "$file"): expected ${expected_px}px, got ${actual}px"
    FAIL=$((FAIL+1))
  fi
}

echo "=== AppIcon.appiconset ==="
check "$APPICONSET/sotto-1024.png" 1024
check "$APPICONSET/sotto-512.png"  512
check "$APPICONSET/sotto-256.png"  256
check "$APPICONSET/sotto-128.png"  128
check "$APPICONSET/sotto-64.png"   64
check "$APPICONSET/sotto-32.png"   32
check "$APPICONSET/sotto-16.png"   16

echo ""
echo "=== menuBarIcon.imageset ==="
check "$MENUBAR/menuBarIcon-22.png" 22
check "$MENUBAR/menuBarIcon-44.png" 44

echo ""
echo "=== Contents.json template check ==="
TEMPLATE=$(python3 -c "
import json
with open('$MENUBAR/Contents.json') as f:
    d = json.load(f)
print(d.get('properties', {}).get('template-rendering-intent', 'MISSING'))
")
if [ "$TEMPLATE" = "original" ]; then
  echo "OK menuBarIcon.imageset: template-rendering-intent = original"
  PASS=$((PASS+1))
else
  echo "FAIL menuBarIcon.imageset: template-rendering-intent = $TEMPLATE (expected: original)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
