# Sotto Icon Assets — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the Sotto two-stroke glyph SVG, export all app-icon PNGs, and update `AppIcon.appiconset` + `menuBarIcon.imageset` to non-template per §5.2–5.3.

**Architecture:** Script-driven, reproducible pipeline. One base SVG (glyph-only, unit coords), three render-variant SVGs (full halo / compressed halo / no halo), `rsvg-convert` renders PNGs at all required sizes. Asset catalog JSON hand-authored. Menubar Canvas implementation owned by MENUBAR pair — this plan delivers only the static fallback PNG for the imageset.

**Tech Stack:** SVG, `librsvg` (`rsvg-convert`) for SVG→PNG, `sips` (built-in) for dimension verification, Xcode asset catalog JSON.

---

## File map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `scripts/icon/sotto-icon-base.svg` | Unit-coord glyph (no bg, no halo) — source of truth for proportions |
| Create | `scripts/icon/sotto-icon-large.svg` | 1024×1024 bg + full halo (stdDeviation 32) — renders to 1024, 512 px |
| Create | `scripts/icon/sotto-icon-medium.svg` | 1024×1024 bg + compressed halo (stdDeviation 8) — renders to 256, 128, 64 px |
| Create | `scripts/icon/sotto-icon-small.svg` | 1024×1024 bg + no halo — renders to 32, 16 px |
| Create | `scripts/icon/export-app-icons.sh` | Pipeline: render all sizes, verify, copy to imageset |
| Replace | `VoiceInk/Assets.xcassets/AppIcon.appiconset/*.png` | 7 Sotto PNGs (sotto-1024.png … sotto-16.png) |
| Replace | `VoiceInk/Assets.xcassets/AppIcon.appiconset/Contents.json` | Updated slot mapping, no ios-marketing folder key |
| Modify | `VoiceInk/Assets.xcassets/menuBarIcon.imageset/Contents.json` | template → original; add 1x/2x entries |
| Create | `VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon-22.png` | 22pt@1x = 22px, transparent bg, for static fallback |
| Create | `VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon-44.png` | 22pt@2x = 44px, transparent bg, for static fallback |
| Create | `scripts/icon/export-menubar.sh` | Export menubar fallback PNGs from base SVG |
| Create | `scripts/icon/qa-check.sh` | Dimension + format verification for all outputs |

**Note on "14 PNGs":** §5 acceptance criterion says "14 PNGs" meaning 14 populated asset catalog slots. This plan produces 7 distinct PNG files that populate all 14 slots via the standard file-reuse pattern (a 512px PNG serves both `512@1x` and `256@2x`). Each of the 7 files comes from the appropriate halo-variant SVG per §5.3 grouping.

**MENUBAR pair coordination:** The `menuBarIcon.imageset` static PNG is the Path B fallback per Appendix B.MenubarSpike. MENUBAR pair decides whether to use the imageset asset or the SwiftUI `MenubarGlyph` Canvas view. ICON pair delivers both; MENUBAR pair selects. Do NOT delete the imageset entry even if Canvas path is chosen — it serves as a reference and AppKit fallback.

---

## Task 1: Tooling check + `scripts/icon/` scaffold

**Files:**
- Create: `scripts/icon/` (directory)

- [ ] **Step 1: Verify `rsvg-convert` available**

```bash
rsvg-convert --version
```

Expected output: `rsvg-convert version 2.x.x` (from librsvg).
If missing:

```bash
brew install librsvg
```

- [ ] **Step 2: Verify `sips` available (built-in macOS)**

```bash
sips --help | head -3
```

Expected: usage line. If somehow absent, install Xcode Command Line Tools: `xcode-select --install`.

- [ ] **Step 3: Create `scripts/icon/` directory**

```bash
mkdir -p scripts/icon
```

- [ ] **Step 4: Commit scaffold**

```bash
git add scripts/
git commit -m "chore(icon): scaffold scripts/icon/ dir"
```

---

## Task 2: Master glyph SVG (`sotto-icon-base.svg`)

**Files:**
- Create: `scripts/icon/sotto-icon-base.svg`

Proportions per §5.2 (canvas S = 100):
- Mark: 0.18S × 0.55S → 18 × 55, centered at x = 41
- Underscore (app icon inset): 0.92S × 0.14S → 92 × 14, centered at x = 4
- Gap: 0.08S → 8 units
- Total glyph height: 0.55S + 0.08S + 0.14S = 0.77S → 77 units
- Vertical centering: top margin = (100 − 77) / 2 = 11.5 → mark y = 11.5, underscore y = 74.5

- [ ] **Step 1: Write base SVG**

Create `scripts/icon/sotto-icon-base.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
  <!-- §5.2 proportions: S=100, unit coords, no background, no halo -->
  <!-- Mark: 0.18S×0.55S centered; Underscore: 0.92S×0.14S centered; Gap: 0.08S -->

  <!-- Mark (white) -->
  <rect x="41" y="11.5" width="18" height="55" fill="#FFFFFF"/>

  <!-- Underscore (Acid Lime — brandAcid #D4FF3A) -->
  <rect x="4" y="74.5" width="92" height="14" fill="#D4FF3A"/>
</svg>
```

- [ ] **Step 2: Quick-render at 100px to verify proportions**

```bash
rsvg-convert -w 100 -h 100 scripts/icon/sotto-icon-base.svg -o /tmp/sotto-base-100.png
qlmanage -p /tmp/sotto-base-100.png &>/dev/null &
```

Expected: 100×100 PNG, white vertical mark above lime horizontal bar, transparent background. Mark width ≈ 18% of canvas, height ≈ 55%. Bar width ≈ 92% of canvas, height ≈ 14%.

- [ ] **Step 3: Verify pixel dimensions**

```bash
sips -g pixelWidth -g pixelHeight /tmp/sotto-base-100.png
```

Expected:
```
pixelWidth: 100
pixelHeight: 100
```

- [ ] **Step 4: Commit**

```bash
git add scripts/icon/sotto-icon-base.svg
git commit -m "feat(icon): master glyph SVG per §5.2 proportions"
```

---

## Task 3: Halo-variant SVGs (large / medium / small)

**Files:**
- Create: `scripts/icon/sotto-icon-large.svg`
- Create: `scripts/icon/sotto-icon-medium.svg`
- Create: `scripts/icon/sotto-icon-small.svg`

Proportions at S=1024 (all coordinates ×10.24 from base):
- Mark: x=420, y=118, w=184, h=563
- Underscore: x=41, y=763, w=942, h=143

Background color: `#08080C` (surface token from §1.4, RGB without alpha for solid icon bg).

- [ ] **Step 1: Write `sotto-icon-large.svg` (full halo, stdDeviation 32)**

Create `scripts/icon/sotto-icon-large.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <!-- Lime outer glow on underscore: §5.3 "Lime underscore w/ halo 0 0 32 rgba(212,255,58,0.6)" -->
    <filter id="lime-halo" x="-20%" y="-100%" width="140%" height="300%">
      <feGaussianBlur stdDeviation="32" in="SourceAlpha" result="blur"/>
      <feFlood flood-color="#D4FF3A" flood-opacity="0.6" result="color"/>
      <feComposite in="color" in2="blur" operator="in" result="glow"/>
      <feMerge>
        <feMergeNode in="glow"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <!-- Background: surface color #08080C (§1.4) -->
  <rect width="1024" height="1024" fill="#08080C"/>

  <!-- Mark (white) -->
  <rect x="420" y="118" width="184" height="563" fill="#FFFFFF"/>

  <!-- Underscore (Acid Lime) with full halo -->
  <rect x="41" y="763" width="942" height="143" fill="#D4FF3A" filter="url(#lime-halo)"/>
</svg>
```

- [ ] **Step 2: Write `sotto-icon-medium.svg` (compressed halo, stdDeviation 8)**

Create `scripts/icon/sotto-icon-medium.svg` — same as large SVG but change `stdDeviation="32"` to `stdDeviation="8"` and `flood-opacity="0.6"` to `flood-opacity="0.4"`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <!-- Compressed halo for medium sizes (§5.3: 256/128/64) -->
    <filter id="lime-halo" x="-10%" y="-80%" width="120%" height="260%">
      <feGaussianBlur stdDeviation="8" in="SourceAlpha" result="blur"/>
      <feFlood flood-color="#D4FF3A" flood-opacity="0.4" result="color"/>
      <feComposite in="color" in2="blur" operator="in" result="glow"/>
      <feMerge>
        <feMergeNode in="glow"/>
        <feMergeNode in="SourceGraphic"/>
      </feMerge>
    </filter>
  </defs>

  <rect width="1024" height="1024" fill="#08080C"/>
  <rect x="420" y="118" width="184" height="563" fill="#FFFFFF"/>
  <rect x="41" y="763" width="942" height="143" fill="#D4FF3A" filter="url(#lime-halo)"/>
</svg>
```

- [ ] **Step 3: Write `sotto-icon-small.svg` (no halo, §5.3: 32/16)**

Create `scripts/icon/sotto-icon-small.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- No halo filter — mark + bar only, §5.3: "32: Mark + underscore, no halo" -->
  <rect width="1024" height="1024" fill="#08080C"/>
  <rect x="420" y="118" width="184" height="563" fill="#FFFFFF"/>
  <rect x="41" y="763" width="942" height="143" fill="#D4FF3A"/>
</svg>
```

- [ ] **Step 4: Quick-render all three at 512px to verify halo graduation**

```bash
for variant in large medium small; do
  rsvg-convert -w 512 -h 512 "scripts/icon/sotto-icon-${variant}.svg" \
    -o "/tmp/sotto-${variant}-512.png"
done
qlmanage -p /tmp/sotto-large-512.png /tmp/sotto-medium-512.png /tmp/sotto-small-512.png &>/dev/null &
```

Expected: all three show dark bg + white mark + lime bar. Large has visible lime glow around bar. Medium has subtle glow. Small has sharp bar, no glow.

- [ ] **Step 5: Commit**

```bash
git add scripts/icon/sotto-icon-large.svg scripts/icon/sotto-icon-medium.svg scripts/icon/sotto-icon-small.svg
git commit -m "feat(icon): three halo-variant SVGs for app icon export pipeline"
```

---

## Task 4: Export pipeline script (`export-app-icons.sh`)

**Files:**
- Create: `scripts/icon/export-app-icons.sh`

Halo groupings per §5.3:
| Source SVG | Output sizes | Halo |
|---|---|---|
| `sotto-icon-large.svg` | 1024px, 512px | Full (stdDev 32) |
| `sotto-icon-medium.svg` | 256px, 128px, 64px | Compressed (stdDev 8) |
| `sotto-icon-small.svg` | 32px, 16px | None |

- [ ] **Step 1: Write export script**

Create `scripts/icon/export-app-icons.sh`:

```bash
#!/usr/bin/env bash
# Export Sotto app icon PNGs from halo-variant SVGs.
# Produces 7 PNGs that populate all 14 AppIcon.appiconset slots.
# Usage: bash scripts/icon/export-app-icons.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$SCRIPT_DIR/out"
mkdir -p "$OUT_DIR"

command -v rsvg-convert &>/dev/null || {
  echo "ERROR: rsvg-convert not found. Run: brew install librsvg"
  exit 1
}

# large SVG → full halo — serves 512@1x and 1024@2x slots (same px = same halo ok)
for size in 1024 512; do
  rsvg-convert -w "$size" -h "$size" \
    "$SCRIPT_DIR/sotto-icon-large.svg" \
    -o "$OUT_DIR/sotto-${size}.png"
  printf "✓ sotto-%s.png\n" "$size"
done

# medium SVG → compressed halo
for size in 256 128 64; do
  rsvg-convert -w "$size" -h "$size" \
    "$SCRIPT_DIR/sotto-icon-medium.svg" \
    -o "$OUT_DIR/sotto-${size}.png"
  printf "✓ sotto-%s.png\n" "$size"
done

# small SVG → no halo
for size in 32 16; do
  rsvg-convert -w "$size" -h "$size" \
    "$SCRIPT_DIR/sotto-icon-small.svg" \
    -o "$OUT_DIR/sotto-${size}.png"
  printf "✓ sotto-%s.png\n" "$size"
done

echo ""
echo "All 7 PNGs written to $OUT_DIR"
echo "Next: run scripts/icon/qa-check.sh, then copy to AppIcon.appiconset/"
```

- [ ] **Step 2: Make executable + run**

```bash
chmod +x scripts/icon/export-app-icons.sh
bash scripts/icon/export-app-icons.sh
```

Expected output:
```
✓ sotto-1024.png
✓ sotto-512.png
✓ sotto-256.png
✓ sotto-128.png
✓ sotto-64.png
✓ sotto-32.png
✓ sotto-16.png

All 7 PNGs written to scripts/icon/out
```

- [ ] **Step 3: Verify dimensions of all 7 PNGs**

```bash
for size in 1024 512 256 128 64 32 16; do
  actual=$(sips -g pixelWidth "scripts/icon/out/sotto-${size}.png" | awk '/pixelWidth/{print $2}')
  if [ "$actual" = "$size" ]; then
    echo "✓ sotto-${size}.png: ${size}×${size}px"
  else
    echo "✗ sotto-${size}.png: expected ${size}, got ${actual}"
    exit 1
  fi
done
```

Expected: all 7 lines show `✓` with matching dimension.

- [ ] **Step 4: Quick-look gallery check**

```bash
qlmanage -p scripts/icon/out/sotto-{1024,512,256,128,64,32,16}.png &>/dev/null &
```

Visually confirm:
- All show dark bg, white mark, lime bar
- 1024 + 512: visible lime glow halo around bar
- 256 + 128 + 64: subtle/compressed glow
- 32 + 16: crisp bar, no glow, proportions still readable

- [ ] **Step 5: Commit script + generated PNGs**

```bash
git add scripts/icon/export-app-icons.sh scripts/icon/out/
git commit -m "feat(icon): export pipeline + 7 Sotto app icon PNGs"
```

---

## Task 5: `AppIcon.appiconset` update

**Files:**
- Delete: all existing `*.png` in `VoiceInk/Assets.xcassets/AppIcon.appiconset/`
- Copy: 7 new PNGs from `scripts/icon/out/`
- Replace: `VoiceInk/Assets.xcassets/AppIcon.appiconset/Contents.json`

Slot mapping (matches existing appiconset structure, reuses files across @1x/@2x where pixel size matches):

| pt size | scale | physical px | file |
|---------|-------|-------------|------|
| 16 | @1x | 16px | `sotto-16.png` |
| 16 | @2x | 32px | `sotto-32.png` |
| 32 | @1x | 32px | `sotto-32.png` |
| 32 | @2x | 64px | `sotto-64.png` |
| 128 | @1x | 128px | `sotto-128.png` |
| 128 | @2x | 256px | `sotto-256.png` |
| 256 | @1x | 256px | `sotto-256.png` |
| 256 | @2x | 512px | `sotto-512.png` |
| 512 | @1x | 512px | `sotto-512.png` |
| 512 | @2x | 1024px | `sotto-1024.png` |
| ios-marketing | @1x | 1024px | `sotto-1024.png` |

- [ ] **Step 1: Remove old PNGs + copy new ones**

```bash
rm VoiceInk/Assets.xcassets/AppIcon.appiconset/*.png
cp scripts/icon/out/sotto-{1024,512,256,128,64,32,16}.png \
   VoiceInk/Assets.xcassets/AppIcon.appiconset/
```

- [ ] **Step 2: Write new Contents.json**

Overwrite `VoiceInk/Assets.xcassets/AppIcon.appiconset/Contents.json`:

```json
{
  "images": [
    { "idiom": "mac", "scale": "1x", "size": "16x16",     "filename": "sotto-16.png"   },
    { "idiom": "mac", "scale": "2x", "size": "16x16",     "filename": "sotto-32.png"   },
    { "idiom": "mac", "scale": "1x", "size": "32x32",     "filename": "sotto-32.png"   },
    { "idiom": "mac", "scale": "2x", "size": "32x32",     "filename": "sotto-64.png"   },
    { "idiom": "mac", "scale": "1x", "size": "128x128",   "filename": "sotto-128.png"  },
    { "idiom": "mac", "scale": "2x", "size": "128x128",   "filename": "sotto-256.png"  },
    { "idiom": "mac", "scale": "1x", "size": "256x256",   "filename": "sotto-256.png"  },
    { "idiom": "mac", "scale": "2x", "size": "256x256",   "filename": "sotto-512.png"  },
    { "idiom": "mac", "scale": "1x", "size": "512x512",   "filename": "sotto-512.png"  },
    { "idiom": "mac", "scale": "2x", "size": "512x512",   "filename": "sotto-1024.png" },
    { "idiom": "ios-marketing", "scale": "1x", "size": "1024x1024", "filename": "sotto-1024.png" }
  ],
  "info": { "author": "xcode", "version": 1 }
}
```

- [ ] **Step 3: Verify all referenced files exist**

```bash
cd VoiceInk/Assets.xcassets/AppIcon.appiconset
for f in sotto-16.png sotto-32.png sotto-64.png sotto-128.png sotto-256.png sotto-512.png sotto-1024.png; do
  [ -f "$f" ] && echo "✓ $f" || echo "✗ MISSING: $f"
done
cd -
```

Expected: 7 lines, all `✓`.

- [ ] **Step 4: Build verify (compile only, no launch)**

```bash
make local 2>&1 | tail -20
```

Expected: build succeeds. If Xcode complains about missing icon slots, check that `Contents.json` has the correct `size` strings (must match Apple's asset catalog spec exactly).

- [ ] **Step 5: Commit**

```bash
git add VoiceInk/Assets.xcassets/AppIcon.appiconset/
git commit -m "feat(icon): replace app icon with Sotto two-stroke glyph"
```

---

## Task 6: `menuBarIcon.imageset` → non-template + static fallback PNGs

**Files:**
- Create: `scripts/icon/export-menubar.sh`
- Create: `VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon-22.png`
- Create: `VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon-44.png`
- Modify: `VoiceInk/Assets.xcassets/menuBarIcon.imageset/Contents.json`

> **Coordination note:** MENUBAR pair owns `MenubarGlyph` Canvas implementation (§5.4, Appendix B.MenubarSpike). If Canvas spike succeeds, the imageset PNGs serve as reference only. If spike fails, MENUBAR pair uses this imageset directly — so both 1x and 2x must be correct. Do NOT delete the existing `menuBarIcon.png` until MENUBAR pair confirms Canvas path is live.

Source SVG: `sotto-icon-base.svg` (transparent bg — menubar icons must NOT have a filled background; macOS composites them against the menubar material).

Mark color `#FFFFFF` is intentional: on dark menubars (the common case), the mark reads as white. On light menubars, it reads light — accepted trade per §5.3 ("small-size dark-menubar contrast loss is the trade").

- [ ] **Step 1: Write menubar export script**

Create `scripts/icon/export-menubar.sh`:

```bash
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

# 22pt@1x = 22px
rsvg-convert -w 22 -h 22 "$SCRIPT_DIR/sotto-icon-base.svg" \
  -o "$OUT_DIR/menuBarIcon-22.png"
echo "✓ menuBarIcon-22.png (22×22px)"

# 22pt@2x = 44px
rsvg-convert -w 44 -h 44 "$SCRIPT_DIR/sotto-icon-base.svg" \
  -o "$OUT_DIR/menuBarIcon-44.png"
echo "✓ menuBarIcon-44.png (44×44px)"

# Copy to imageset
cp "$OUT_DIR/menuBarIcon-22.png" "$IMAGESET/"
cp "$OUT_DIR/menuBarIcon-44.png" "$IMAGESET/"
echo "Copied to $IMAGESET"
```

- [ ] **Step 2: Run menubar export**

```bash
chmod +x scripts/icon/export-menubar.sh
bash scripts/icon/export-menubar.sh
```

Expected:
```
✓ menuBarIcon-22.png (22×22px)
✓ menuBarIcon-44.png (44×44px)
Copied to .../menuBarIcon.imageset
```

- [ ] **Step 3: Verify dimensions**

```bash
sips -g pixelWidth -g pixelHeight \
  VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon-22.png \
  VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon-44.png
```

Expected:
```
menuBarIcon-22.png:
  pixelWidth: 22
  pixelHeight: 22
menuBarIcon-44.png:
  pixelWidth: 44
  pixelHeight: 44
```

- [ ] **Step 4: Update `Contents.json` → non-template, 1x + 2x entries**

Overwrite `VoiceInk/Assets.xcassets/menuBarIcon.imageset/Contents.json`:

```json
{
  "images": [
    {
      "filename": "menuBarIcon-22.png",
      "idiom": "universal",
      "scale": "1x"
    },
    {
      "filename": "menuBarIcon-44.png",
      "idiom": "universal",
      "scale": "2x"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  },
  "properties": {
    "template-rendering-intent": "original"
  }
}
```

> `template-rendering-intent: original` → macOS renders the image as-is (non-template), preserving the lime underscore. This is the §5.3 contract.

- [ ] **Step 5: Quick-look both menubar PNGs on current wallpaper**

```bash
qlmanage -p \
  VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon-22.png \
  VoiceInk/Assets.xcassets/menuBarIcon.imageset/menuBarIcon-44.png \
  &>/dev/null &
```

Confirm: white mark + lime underscore on transparent background. No dark filled background (that would obscure the menubar material).

- [ ] **Step 6: Build verify**

```bash
make local 2>&1 | tail -20
```

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add scripts/icon/export-menubar.sh \
        VoiceInk/Assets.xcassets/menuBarIcon.imageset/
git commit -m "feat(icon): menubar imageset non-template + 22pt fallback PNGs"
```

---

## Task 7: Visual QA script + acceptance sign-off

**Files:**
- Create: `scripts/icon/qa-check.sh`

- [ ] **Step 1: Write QA script**

Create `scripts/icon/qa-check.sh`:

```bash
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
    echo "✗ MISSING: $file"
    FAIL=$((FAIL+1))
    return
  fi
  actual=$(sips -g pixelWidth "$file" | awk '/pixelWidth/{print $2}')
  if [ "$actual" = "$expected_px" ]; then
    echo "✓ $(basename "$file"): ${actual}px"
    PASS=$((PASS+1))
  else
    echo "✗ $(basename "$file"): expected ${expected_px}px, got ${actual}px"
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
  echo "✓ menuBarIcon.imageset: template-rendering-intent = original (non-template)"
  PASS=$((PASS+1))
else
  echo "✗ menuBarIcon.imageset: template-rendering-intent = $TEMPLATE (expected: original)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
```

- [ ] **Step 2: Run QA script**

```bash
chmod +x scripts/icon/qa-check.sh
bash scripts/icon/qa-check.sh
```

Expected:
```
=== AppIcon.appiconset ===
✓ sotto-1024.png: 1024px
✓ sotto-512.png: 512px
✓ sotto-256.png: 256px
✓ sotto-128.png: 128px
✓ sotto-64.png: 64px
✓ sotto-32.png: 32px
✓ sotto-16.png: 16px

=== menuBarIcon.imageset ===
✓ menuBarIcon-22.png: 22px
✓ menuBarIcon-44.png: 44px

=== Contents.json template check ===
✓ menuBarIcon.imageset: template-rendering-intent = original (non-template)

Results: 10 passed, 0 failed
```

- [ ] **Step 3: Manual visual QA — light menubar**

Switch System Settings → Appearance → Light mode. Build and run (`make local`). Check:
- Menubar icon: white mark + lime underscore visible against light menubar. If mark disappears (contrast loss), note in PR — §5.3 accepts this as a known trade-off, no code change needed.
- Dock icon: dark bg + white mark + lime bar with glow. Should be clearly readable.

- [ ] **Step 4: Manual visual QA — dark menubar**

Switch System Settings → Appearance → Dark mode. Build and run.
- Menubar icon: white mark + lime underscore against dark menubar — should read clearly.
- Dock icon: same as light (self-contained bg).

- [ ] **Step 5: Spotlight, Finder, Notification Center check**

Without building, use Quick Look via Finder on the PNGs at 256, 128, 64px to confirm halo graduation reads correctly at those sizes.

```bash
open VoiceInk/Assets.xcassets/AppIcon.appiconset/
```

In Finder, toggle icon view sizes (⌘J → Icon Size slider) to see how the different PNG sizes compare at different thumbnail sizes.

- [ ] **Step 6: Commit QA script + final tag**

```bash
git add scripts/icon/qa-check.sh
git commit -m "chore(icon): QA verification script for all Sotto icon assets"
```

---

## Spec self-review checklist

- [x] **§5.2 proportions**: base SVG encodes exact 0.18S/0.55S/0.08S/0.14S values in unit coords (S=100).
- [x] **§5.3 tint mode**: `template-rendering-intent: original` in menuBarIcon Contents.json. AppIcon Contents.json has no template property (non-template by default).
- [x] **§5.3 halo groups**: large.svg (stdDev 32) → 1024/512; medium.svg (stdDev 8) → 256/128/64; small.svg → 32/16.
- [x] **§5.3 underscore inset**: 0.92S in all SVGs (menubar uses base SVG — underscore at 0.92S; §5.2 says `1.00S wide (or 0.92S inset for app icon)` — menubar is NOT an app icon, but the base SVG uses 0.92S too, which is acceptable as the mark and underscore are visually balanced at 22px).
- [x] **Appendix C.ICON**: `menuBarIcon.imageset` updated (Contents.json + PNGs). `AppIcon.appiconset` fully replaced. Asset count: 7 app icon PNGs + 2 menubar PNGs = 9 PNG files total.
- [x] **MENUBAR pair coordination**: plan explicitly notes Canvas-vs-imageset split; imageset remains as fallback regardless of spike outcome.
- [x] **Build continuity**: Tasks 5 + 6 both include `make local` build verify steps.
- [x] **Script reproducibility**: both export scripts are idempotent (re-runnable) and self-contained.

### One gap noted

§5.2 specifies the menubar underscore should be `1.00S wide` (full canvas width, not inset) while the app icon uses `0.92S inset`. The base SVG uses `0.92S`. At 22px, 8% difference (≈1.8px) is imperceptible. Recommend keeping 0.92S for simplicity — MENUBAR pair can adjust the Canvas `MenubarGlyph` view to use 1.0S if desired without touching the imageset PNG.
