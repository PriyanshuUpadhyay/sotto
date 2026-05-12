# Sotto · SETTINGS pair implementation plan (Phase D)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin Settings shell + 7 panes (Models W14F-shipped audit-only; General/Recorder/Hotkeys/Permissions/AI Models/Audio Input) to Sotto §1 vocabulary — Tactical Glass + Acid Lime + SF Mono + `›` prompts — with zero behavior change.

**Architecture:** Single SwiftUI surface tree, unchanged. Re-skin = color token swap (`Palette.accent` tangerine → `Palette.brandAcid` lime), corner-radius collapse (≥14pt → 2pt matte / 8pt notch), `.ultraThinMaterial` → `TacticalGlass` primitive (HUD pair owns), and SF Mono enforcement on every label.

**Tech Stack:** SwiftUI 5 · macOS 14.4+ · existing `GlassCard` / `SettingsCard` / `SettingsRow` / `SettingsSectionHeader` / `AdaptiveGlassBackground` primitives.

**Dependencies:**
- **RENAME pair** — must land first (file paths flip `VoiceInk/` → `Sotto/`; entitlements + bundle ID).
- **HUD pair** — owns `TacticalGlass(shape:phase:appearance:)` SwiftUI primitive + `Palette.brandAcid` token rename. SETTINGS imports both. Stage Group C work behind these landings.

**W14F audit verdict (early):** **delta required.** Two-tab + ACTIVE PROVIDER focal card + accordion structure is conformant; visual tokens are NOT — `Palette.accent` is tangerine `#FF5B3A`, spec §1.4 wants lime `#D4FF3A`; cards use `cornerRadius: 14`, spec §1.2 caps at 8pt; `.ultraThinMaterial` ad-hoc in 4 sites, spec §1 acceptance forbids it. Re-skin delta is one PR (Group B).

---

## File touch map

| File | Action | Group |
|---|---|---|
| `Sotto/Views/ContentView.swift` | Re-skin sidebar List rows (`SidebarItemView`) | A |
| `Sotto/Views/Common/Palette.swift` | Add `brandAcid` token (coordinate w/ HUD); retire tangerine `accent` after Group E migration | A |
| `Sotto/Views/Common/SettingsSectionHeader.swift` | SF Mono on title + subtitle; tracking +0.16em on uppercase status pill (already mono — verify) | A |
| `Sotto/Views/Common/SettingsCard.swift` | cornerRadius 16 → 8; route bg through `TacticalGlass` (HUD primitive) | A |
| `Sotto/Views/Common/SettingsRow.swift` | SF Mono label; iconTile cornerRadius 6 → 2 | A |
| `Sotto/Views/Common/GlassCard.swift` | cornerRadius default 16 → 8; underlying `HaloMaterial` stays | A |
| `Sotto/Views/Common/AdaptiveGlassBackground.swift` | Add §1.5 RadialGradient wallpaper-bleed layer behind blur | A |
| `Sotto/Views/Common/CompactHeroSection.swift` | SF Mono title (22pt bold); description SF Mono 14pt | A |
| `Sotto/Views/Models/ModelsView.swift` | **Audit-only (W14F shipped).** Token swap + cornerRadius collapse + segmented control SF Mono | B |
| `Sotto/Views/AI Models/EnhancementProviderSection.swift` | **Audit-only (W14F shipped).** Token swap on `ActiveEnhancementProviderCard` + `OtherEnhancementProvidersAccordion` | B |
| `Sotto/Views/AI Models/APIKeyManagementView.swift` | Token swap on `ProviderCard` chrome (read for diff only — primary tokens flow through Palette) | B |
| `Sotto/Views/Settings/SettingsView.swift` | No structural change — token swap flows through SettingsCard. Verify no per-call-site tangerine literal | C |
| `Sotto/Views/Settings/HandsFreeSettingsView.swift` | Token swap + verify SF Mono | C |
| `Sotto/Views/Settings/AudioInputSettingsView.swift` | Token swap; `InputModeCard` / `DeviceSelectionCard` / `DevicePriorityCard` cornerRadius 16 → 8; SF Mono on labels | C |
| `Sotto/Views/Settings/RecorderStylePicker.swift` | cornerRadius 10/12 → 8/8; SF Mono titles | C |
| `Sotto/Views/Settings/CustomSoundSettingsView.swift` | cornerRadius 14 → 8 on cue cards; SF Mono | C |
| `Sotto/Views/Settings/AudioCleanupSettingsView.swift` | Token-only (no chrome of its own) | C |
| `Sotto/Views/Settings/EnhancementShortcutsView.swift` | `KeyChip` cornerRadius 6 → 2; tokens | C |
| `Sotto/Views/Settings/CommandPaletteSheet.swift` | `CommandPaletteRow` selected-row tint → `brandAcid`; row cornerRadius 8 → 2 | C |
| `Sotto/Views/Settings/DiagnosticsSettingsView.swift` | Token-only | C |
| `Sotto/Views/PermissionsView.swift` | `PermissionCard` cornerRadius 10/14 → 8; CTA button bg → `brandAcid`; SF Mono | C |
| `Sotto/Views/Common/AccessibilityHelpers.swift` (new) | VoiceOver helpers + Reduce-Motion guard wrapper | D |
| `docs/superpowers/reports/2026-05-11-W14F-conformance.md` (new) | W14F audit report → team-lead | E |

**Critical files NOT touched:** `Sotto/Views/ContentView.swift` `NavigationSplitView` structure, all SwiftData `@Query` shapes, every `@AppStorage` key, `KeyboardShortcuts.Name`s, `PermissionManager` logic, `AudioCleanupManager` logic.

---

## Pre-flight (blocking checks before Group A)

- [ ] **Step 0.1: Confirm RENAME landed.**

Run: `git log --oneline main | grep -i "rename\|sotto" | head -5`
Expected: at least one commit referencing the RENAME pair's bundle-ID flip. If empty: stop, ping team-lead, do NOT start.

- [ ] **Step 0.2: Confirm HUD pair shipped `TacticalGlass` + `brandAcid`.**

Run: `grep -rn "struct TacticalGlass\|static let brandAcid" Sotto/ 2>/dev/null`
Expected: 2+ matches (struct declaration + token declaration).
If missing: Group A can start (uses `GlassCard` as proxy) but Group A.Step 4 onward stalls until HUD lands. Stage as a draft PR.

- [ ] **Step 0.3: Pin SettingsView line ranges for verification (since file is 784 lines).**

Run: `wc -l Sotto/Views/Settings/SettingsView.swift Sotto/Views/Models/ModelsView.swift`
Expected: 784 + 804 (or close). Used as the regression baseline in Group E.

---

## Group A — Settings shell + shared primitives

Re-skin every primitive that every pane composes — single edit pass flips the whole surface.

### Task A1: brandAcid token

**Files:**
- Modify: `Sotto/Views/Common/Palette.swift`

- [ ] **Step 1: Add `brandAcid` token alongside existing `accent`.**

Edit `Palette.swift` — insert after the existing `accent` declaration (currently `~line 36`):

```swift
/// #D4FF3A — Sotto Acid Lime. Locked accent per §1.4 of the Sotto UI redesign.
/// Selected rows, prompt glyph `›`, section labels, CTA, HUD audio bars.
/// Replaces tangerine `accent` post-redesign — old token retained transitionally;
/// every consumer migrates to `brandAcid` in this PR, tangerine is removed in Group E.
static let brandAcid = Color(red: 0.831, green: 1.000, blue: 0.227)

/// #D4FF3A α 0.16 — chip backgrounds + section-label underlines on glass.
static let brandAcidMuted = Color(red: 0.831, green: 1.000, blue: 0.227).opacity(0.16)

/// #D4FF3A α 0.42 — secondary text on glass per §1.4 `ghost` token.
static let ghost = Color.white.opacity(0.42)
```

- [ ] **Step 2: Verify no consumer broke.**

Run: `swift build 2>&1 | grep -E "error:|warning:" | head -20` (or `make local` per project memory)
Expected: zero new errors. `brandAcid` is additive — no migration in this step.

- [ ] **Step 3: Commit.**

```bash
git add Sotto/Views/Common/Palette.swift
git commit -m "settings(A1): add Palette.brandAcid + ghost tokens"
```

### Task A2: SettingsSectionHeader — SF Mono + lime status

**Files:**
- Modify: `Sotto/Views/Common/SettingsSectionHeader.swift`

- [ ] **Step 1: Mono'fy title; lime accent on status pill when caller passes `Palette.brandAcid`.**

Edit lines 46–48 — replace:
```swift
Text(title)
    .font(.system(size: 14, weight: .semibold))
    .foregroundColor(.primary)
```
with:
```swift
Text(title)
    .font(.system(size: 14, weight: .semibold, design: .monospaced))
    .tracking(0.02 * 14)
    .foregroundColor(.primary)
```

Edit lines 50–53 — replace:
```swift
Text(subtitle)
    .font(.system(size: 11, weight: .regular))
    .foregroundColor(.secondary)
    .lineLimit(1)
```
with:
```swift
Text(subtitle)
    .font(.system(size: 11, weight: .regular, design: .monospaced))
    .tracking(0.02 * 11)
    .foregroundColor(.secondary)
    .lineLimit(1)
```

Edit line 32: change `RoundedRectangle(cornerRadius: 7, ...)` → `RoundedRectangle(cornerRadius: 2, ...)` (icon tile, matches §1.2 matte).

- [ ] **Step 2: Visual check via SwiftUI preview.**

Open `SettingsSectionHeader.swift` in Xcode → Canvas → Resume. Verify mono'd "Recording" / "Privacy" titles + +0.02em tracking visible.

- [ ] **Step 3: Commit.**

```bash
git add Sotto/Views/Common/SettingsSectionHeader.swift
git commit -m "settings(A2): SettingsSectionHeader SF Mono + 2pt icon tile"
```

### Task A3: SettingsRow — SF Mono + 2pt tile

**Files:**
- Modify: `Sotto/Views/Common/SettingsRow.swift`

- [ ] **Step 1: Mono label + subtitle.**

Edit `body` block (lines 34–42) — replace label/subtitle Text styles:
```swift
Text(label)
    .font(.system(size: 13, weight: .medium, design: .monospaced))
    .tracking(0.02 * 13)
    .foregroundColor(.primary)
if let subtitle, !subtitle.isEmpty {
    Text(subtitle)
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .tracking(0.02 * 11)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
}
```

Edit lines 55–59 — change `iconTile`'s `cornerRadius: 6` → `cornerRadius: 2` (both `.fill` and `.stroke`).

- [ ] **Step 2: Commit.**

```bash
git add Sotto/Views/Common/SettingsRow.swift
git commit -m "settings(A3): SettingsRow SF Mono + 2pt icon tile"
```

### Task A4: GlassCard + SettingsCard — cornerRadius collapse

**Files:**
- Modify: `Sotto/Views/Common/GlassCard.swift`
- Modify: `Sotto/Views/Common/SettingsCard.swift`

- [ ] **Step 1: GlassCard default.**

Edit `GlassCard.swift` line 20: `var cornerRadius: CGFloat = 16` → `var cornerRadius: CGFloat = 8`.

- [ ] **Step 2: SettingsCard.**

Edit `SettingsCard.swift` line 36: `GlassCard(cornerRadius: 16, ...)` → `GlassCard(cornerRadius: 8, ...)`.

- [ ] **Step 3: Commit.**

```bash
git add Sotto/Views/Common/GlassCard.swift Sotto/Views/Common/SettingsCard.swift
git commit -m "settings(A4): GlassCard + SettingsCard cornerRadius 16 → 8"
```

### Task A5: AdaptiveGlassBackground — §1.5 wallpaper bleed

**Files:**
- Modify: `Sotto/Views/Common/AdaptiveGlassBackground.swift`

- [ ] **Step 1: Add RadialGradient layer behind blur.**

Edit `backdrop` view (lines 58–76) — wrap the existing ZStack with a 3-layer gradient backdrop matching spec §1.5:

```swift
@ViewBuilder
private var backdrop: some View {
    let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast

    if reduceTransparency {
        Color(NSColor.controlBackgroundColor)
    } else if highContrast {
        Color(NSColor.windowBackgroundColor)
    } else {
        ZStack {
            // §1.5 wallpaper bleed-through — saturated radial backdrop so
            // Tactical Glass reads as glass, not flat plastic.
            Color(red: 0.051, green: 0.051, blue: 0.063)
            RadialGradient(
                colors: [Color(red: 0.431, green: 0.243, blue: 0.714).opacity(0.18), .clear],
                center: UnitPoint(x: 0.2, y: 0.0),
                startRadius: 0,
                endRadius: 600
            )
            RadialGradient(
                colors: [Palette.brandAcid.opacity(0.06), .clear],
                center: UnitPoint(x: 1.0, y: 1.0),
                startRadius: 0,
                endRadius: 500
            )
            VisualEffectBlur(
                material: .fullScreenUI,
                blendingMode: .behindWindow,
                appearanceName: detector.current == .light ? .aqua : .darkAqua
            )
            tint
        }
    }
}
```

- [ ] **Step 2: Verify previews render gradient + glass.**

Open `AdaptiveGlassBackground.swift` in Xcode → resume the two `#Preview` blocks (Onyx pane / Onyx panel). Verify violet glow top-left, lime glow bottom-right, glass on top.

- [ ] **Step 3: Commit.**

```bash
git add Sotto/Views/Common/AdaptiveGlassBackground.swift
git commit -m "settings(A5): AdaptiveGlassBackground §1.5 RadialGradient bleed"
```

### Task A6: ContentView sidebar — `›` prompt + lime selection

**Files:**
- Modify: `Sotto/Views/ContentView.swift:269-300` (`SidebarItemView`)
- Modify: `Sotto/Views/ContentView.swift:131` (List `.tint`)

- [ ] **Step 1: Add `›` glyph + SF Mono + lime selected color.**

Edit `SidebarItemView.body` (lines 277–299) — replace the HStack with:

```swift
var body: some View {
    HStack(spacing: 8) {
        Text("›")
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundColor(Palette.brandAcid)
            .frame(width: 10)

        Image(systemName: viewType.icon)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 20, height: 20)

        Text(viewType.rawValue)
            .font(.system(size: 13, weight: .bold, design: .monospaced))
            .tracking(0.02 * 13)

        Spacer()

        if isConfigured {
            Circle()
                .fill(Palette.brandAcid.opacity(0.85))
                .frame(width: 6, height: 6)
                .accessibilityLabel("Configured")
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .padding(.vertical, 6)
    .padding(.horizontal, 2)
}
```

> **Note:** §1.6 says `›` is read-only prefix in front of sidebar rows. The whole row remains tappable via SwiftUI's `NavigationLink` (line 119) — the glyph itself doesn't gain its own gesture. Acceptance §1: "Sidebar rows use `›` prefix + lime tint."

- [ ] **Step 2: Lime selection tint.**

Edit line 131: `.tint(Palette.accent)` → `.tint(Palette.brandAcid)`.

Also edit line 109: `Text("VoiceInk")` → `Text("Sotto.")` and bump styling:

```swift
HStack(spacing: 2) {
    Text("Sotto")
        .font(.system(size: 16, weight: .bold, design: .monospaced))
        .tracking(0.02 * 16)
    Text(".")
        .font(.system(size: 16, weight: .black, design: .monospaced))
        .foregroundColor(Palette.brandAcid)
}
```

> Cross-check §5.1: "Wordmark is one token. Never break line. Never replace `.`. Trailing stop = brand-mark." Lime period heavy weight.

- [ ] **Step 3: Verify.**

Run: `make local` then open Settings — sidebar shows `› Dashboard` / `› Models` / etc. in SF Mono with lime `›`. Selected row's background tints lime.

- [ ] **Step 4: Commit.**

```bash
git add Sotto/Views/ContentView.swift
git commit -m "settings(A6): sidebar › prompt + lime tint + Sotto. wordmark"
```

### Task A7: CompactHeroSection — SF Mono hero

**Files:**
- Modify: `Sotto/Views/Common/CompactHeroSection.swift`

- [ ] **Step 1: Mono'fy.**

Replace body's Text styles (lines 18–22):
```swift
Text(title)
    .font(.system(size: 22, weight: .bold, design: .monospaced))
    .tracking(0.02 * 22)
Text(description)
    .font(.system(size: 13, weight: .regular, design: .monospaced))
    .tracking(0.02 * 13)
    .foregroundStyle(.secondary)
    .multilineTextAlignment(.center)
    .frame(maxWidth: maxDescriptionWidth)
```

Edit line 13: `.foregroundStyle(Palette.accent)` → `.foregroundStyle(Palette.brandAcid)`.

- [ ] **Step 2: Commit.**

```bash
git add Sotto/Views/Common/CompactHeroSection.swift
git commit -m "settings(A7): CompactHeroSection SF Mono + lime icon"
```

### Task A8: Group A integration check + PR

- [ ] **Step 1: Build clean.**

Run: `make local`
Expected: zero compile errors, app launches.

- [ ] **Step 2: Visual smoke.**

Open Sotto → click each sidebar entry (Dashboard, Models, Hands-free, Permissions, Audio Input, Dictionary, Snippets, Settings). Verify:
- All sidebar rows show `›` + SF Mono name.
- All section headers in each pane show SF Mono title + 2pt icon tiles.
- Card corners visibly tighter (8pt vs 16pt).
- No lingering tangerine in the chrome (cards inside Models/AI Models still tangerine until Group B).

- [ ] **Step 3: Open Group A PR.**

```bash
gh pr create --title "sotto-settings/A: shell + shared primitives re-skin" --base main \
  --body "$(cat <<'EOF'
## Summary
- Add `Palette.brandAcid` (lime `#D4FF3A`) + `ghost` tokens.
- Re-skin shared primitives: `SettingsCard`, `SettingsRow`, `SettingsSectionHeader`, `GlassCard`, `CompactHeroSection` — SF Mono + 2/8pt cornerRadius.
- `AdaptiveGlassBackground` adds §1.5 RadialGradient wallpaper-bleed layer.
- `ContentView` sidebar: `›` prompt glyph, `Sotto.` wordmark w/ lime period, lime selection tint.

W14F Models pane (Group B) and per-pane re-skins (Group C) remain on tangerine until those PRs land — by design, single-PR token swap would balloon the diff.

## Test plan
- [ ] `make local` builds clean
- [ ] Each sidebar entry renders w/ `›` + SF Mono
- [ ] Settings pane cards have visibly tighter corners
- [ ] Wallpaper-bleed gradient visible in pane backdrop

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Group B — Models pane (W14F audit + re-skin)

**Audit conclusion (early):** structure shipped W14F is conformant — two-tab segmented + `ActiveEnhancementProviderCard` focal card + `OtherEnhancementProvidersAccordion` matches §6.2. Visual token delta required: tangerine → lime + cornerRadius 14 → 8 + `.ultraThinMaterial` → `TacticalGlass`.

### Task B1: ModelsView token swap

**Files:**
- Modify: `Sotto/Views/Models/ModelsView.swift`

- [ ] **Step 1: Tangerine → lime on the Models surface.**

The file references `Palette.accent` in ~14 sites. Replace each with `Palette.brandAcid`. Use Edit's `replace_all` once — verify no false-positives.

Run: `grep -n "Palette.accent" Sotto/Views/Models/ModelsView.swift`
Expected: 14 hits. Each one is a visual token (chip border, focal-card glow, tab indicator, gear button) — all should flip to lime.

Edit each occurrence: `Palette.accent` → `Palette.brandAcid`.

- [ ] **Step 2: cornerRadius collapse in `defaultModelCard`.**

Edit lines 322–324 + 362–367: `cornerRadius: 9` → `cornerRadius: 2` (icon tile); `cornerRadius: 14` → `cornerRadius: 8` (card surface).

- [ ] **Step 3: `.ultraThinMaterial` → TacticalGlass.**

Lines 363–364 + 608–612 + 660–662 — replace:
```swift
RoundedRectangle(cornerRadius: 14, style: .continuous)
    .fill(.ultraThinMaterial)
```
with (assuming HUD pair shipped `TacticalGlass`):
```swift
TacticalGlass(
    shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
    phase: .hidden,
    appearance: nil
)
```

If HUD `TacticalGlass` not yet landed: fall back to `GlassCard`-style `HaloMaterial` direct (mirrors `GlassCard.swift` lines 33–42 pattern). Document the fallback in the PR description with a `// TODO(HUD-TacticalGlass)` marker for swap when ready.

- [ ] **Step 4: Segmented control SF Mono.**

Edit `tabHeader` (lines 164–178) — `Picker(.segmented)` doesn't expose font customization on macOS; add a `.fontDesign(.monospaced)` modifier on the `Picker` and bump font:

```swift
Picker("View", selection: $selectedTab) {
    ForEach(ModelTab.allCases) { tab in
        Text(tab.rawValue)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .tag(tab)
    }
}
.pickerStyle(.segmented)
.labelsHidden()
.frame(maxWidth: 320)
```

- [ ] **Step 5: ACTIVE chip → lime.**

Lines 338–348 — verify the ACTIVE chip's background + stroke route through `Palette.brandAcid` (post-swap from Step 1). Sanity-check: chip text remains `Palette.brandAcid` (was `Palette.accent`).

- [ ] **Step 6: Commit.**

```bash
git add Sotto/Views/Models/ModelsView.swift
git commit -m "settings(B1): ModelsView token swap → brandAcid + 8pt corners + SF Mono segmented"
```

### Task B2: EnhancementProviderSection token swap

**Files:**
- Modify: `Sotto/Views/AI Models/EnhancementProviderSection.swift`

- [ ] **Step 1: Tangerine → lime.**

Run: `grep -n "Palette.accent\|Palette.hairline\|cornerRadius" Sotto/Views/AI\ Models/EnhancementProviderSection.swift`
Expected hits: `accent` on lines 66 (section label color); cornerRadius 14 on line 105 + 9 on lines 146–148.

Edit:
- Line 66: `Palette.accent` → `Palette.brandAcid`.
- Line 105: `cornerRadius: 14` → `cornerRadius: 8`.
- Lines 146–148: `cornerRadius: 9` → `cornerRadius: 2` (pictogram tile).

- [ ] **Step 2: `.ultraThinMaterial` swap.**

Lines 133–135 — replace `shape.fill(.ultraThinMaterial)` with TacticalGlass-equivalent (see Task B1.Step 3 pattern; same TODO marker if not yet landed).

- [ ] **Step 3: Header "OTHER PROVIDERS" / "X HIDDEN" already SF Mono — verify tracking matches §1.3 (+0.16em uppercase).**

Lines 167–170: existing `tracking(0.06 * 9.5)` = ~0.06em, NOT +0.16em. Increase: `tracking(0.16 * 9.5)`.

- [ ] **Step 4: Commit.**

```bash
git add "Sotto/Views/AI Models/EnhancementProviderSection.swift"
git commit -m "settings(B2): EnhancementProviderSection tokens + +0.16em uppercase tracking"
```

### Task B3: APIKeyManagementView ProviderCard chrome

**Files:**
- Read first: `Sotto/Views/AI Models/APIKeyManagementView.swift` (entire — `ProviderCard` lives here)
- Modify: same file

- [ ] **Step 1: Read entire file.**

Run: `wc -l Sotto/Views/AI\ Models/APIKeyManagementView.swift`
Expected: 249. Read the full file first; `ProviderCard` is the per-provider expandable card hosted by `ActiveEnhancementProviderCard` and `OtherEnhancementProvidersAccordion`. If it pins `Palette.accent` or `cornerRadius: 14`, swap inline. If `ProviderCard` lives elsewhere (likely a separate file), find it: `grep -rn "struct ProviderCard" Sotto/`.

- [ ] **Step 2: Apply token swap.**

Same as Task B1.Step 1 + Step 2 — swap `Palette.accent` → `Palette.brandAcid`, cornerRadius ≥14 → 8, ad-hoc `.ultraThinMaterial` → TacticalGlass (or TODO fallback). Don't touch logic — only visual tokens.

- [ ] **Step 3: Commit.**

```bash
git add "Sotto/Views/AI Models/APIKeyManagementView.swift"
git commit -m "settings(B3): ProviderCard chrome token swap"
```

### Task B4: B.ModeList verification (spec Appendix B)

**Acceptance §6.1.surface-6:** SETTINGS pair confirms W14F shipped code conforms to §1. Includes B.ModeList — chip prompt names align with `PredefinedPrompts.all` + `AIEnhancementService.customPrompts`.

**Files:**
- Read: `Sotto/Models/PredefinedPrompts.swift`
- Read: `Sotto/Services/AIEnhancement/AIEnhancementService.swift:54-60` (`@Published var customPrompts`)
- Read: `Sotto/Views/Recorder/RecorderComponents.swift:160-170` (chip rendering — verify rule)

- [ ] **Step 1: Confirm prompt sources.**

Run: `grep -n "PredefinedPrompts\.all\|allPrompts\|customPrompts" Sotto/Services/AIEnhancement/AIEnhancementService.swift | head -10`
Expected: `allPrompts` in `AIEnhancementService` is the union `PredefinedPrompts.all + customPrompts`. `customPrompts` is user-added on top of the 2 predefined (`Default`, `Assistant`).

- [ ] **Step 2: Confirm chip truncation rule.**

Open `RecorderComponents.swift:160-170`. The chip currently shows `enhancementService.activePrompt?.icon` — but the **spec §2.3 says left chip displays `activePrompt?.title.uppercased()` truncated to 9 chars; hide chip if `nil`.**

This is a HUD-pair surface (not SETTINGS-pair). Do NOT modify here. File a one-line dossier entry in the audit report (Group E): "B.ModeList — HUD pair must implement title-uppercased-truncated-9 rule; current uses `icon`."

- [ ] **Step 3: Confirm no SETTINGS-side leakage.**

Run: `grep -rn "truncatingTail\|prefix(9)\|9 chars" Sotto/Views/Models/ Sotto/Views/Settings/ Sotto/Views/AI\ Models/`
Expected: zero hits. SETTINGS surfaces show full prompt titles (in `ReorderablePromptGrid` icon labels + prompt editor); the 9-char rule applies only to the HUD chip.

- [ ] **Step 4: Commit (no-op file change — verification only).**

Nothing to commit here. Verification result feeds the Group E audit report.

### Task B5: Group B integration + PR

- [ ] **Step 1: Visual diff Models pane.**

`make local` → open Settings → Models. Compare to spec §1 acceptance list:
- [ ] All cards 8pt corners (no 14pt left).
- [ ] All accent surfaces lime (no tangerine).
- [ ] Segmented control SF Mono.
- [ ] "ACTIVE PROVIDER" + "ACTIVE MODEL" + "X HIDDEN" SF Mono with +0.16em.

- [ ] **Step 2: PR.**

```bash
gh pr create --title "sotto-settings/B: Models pane W14F audit + re-skin" --base main \
  --body "$(cat <<'EOF'
## Summary
- W14F shipped (commits 924f9a6 + b1148d2) structurally conforms to §6.2; visual tokens needed update.
- Tangerine → lime across ModelsView + EnhancementProviderSection + APIKeyManagementView.
- cornerRadius 14/9 → 8/2.
- `.ultraThinMaterial` ad-hoc → TacticalGlass (HUD primitive) where landed; `// TODO(HUD-TacticalGlass)` markers where not.
- Uppercase SF Mono labels bumped from +0.06em → +0.16em per §1.3.
- B.ModeList verified — chip 9-char truncation rule is HUD-pair surface, not SETTINGS; no changes here.

W14F structural pattern preserved end-to-end — zero logic changes.

## Test plan
- [ ] Models tab "Enhancement" renders w/ lime focal card + accordion
- [ ] Models tab "Transcriber" renders w/ lime ACTIVE MODEL card + pill switcher
- [ ] Switching provider via accordion still re-renders focal card (W14F regression check)
- [ ] All AppStorage keys + KeychainHelper writes unchanged

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Group C — non-Models panes re-skin

One PR per logical pane cluster. Six panes; bundle by ownership of @AppStorage keys to keep diffs reviewable.

### Task C1: SettingsView body (root pane) audit

**Files:**
- Read: `Sotto/Views/Settings/SettingsView.swift` (entire — 784 lines)
- Modify: same file

- [ ] **Step 1: Count tangerine references.**

Run: `grep -cn "Palette.accent" Sotto/Views/Settings/SettingsView.swift`
Expected: ~25 occurrences (`iconTint: Palette.accent` per `SettingsCard` + `SettingsRow`).

- [ ] **Step 2: Bulk swap iconTint accents to brandAcid.**

Use Edit's `replace_all` on `Palette.accent` → `Palette.brandAcid`. Manually re-inspect: rows tagged with `Palette.neutral` (gray) or `Palette.warn` (amber) or `Palette.success` (green) must stay — only `accent` flips.

- [ ] **Step 3: Verify build + visual smoke.**

`make local` → Settings pane → confirm every section header icon + every row icon tile is lime.

- [ ] **Step 4: Commit.**

```bash
git add Sotto/Views/Settings/SettingsView.swift
git commit -m "settings(C1): SettingsView accent tokens → brandAcid"
```

### Task C2: HandsFreeSettingsView re-skin

**Files:**
- Modify: `Sotto/Views/Settings/HandsFreeSettingsView.swift`

- [ ] **Step 1: Token swap.**

Run: `grep -n "Palette.accent" Sotto/Views/Settings/HandsFreeSettingsView.swift` (expect ~5 hits) → all flip to `brandAcid`.

- [ ] **Step 2: Segmented Pickers SF Mono.**

Lines 110–117 + 176–183 — add `.fontDesign(.monospaced)` to the `Picker` tag text or wrap Text styles inside the ForEach. Same pattern as Task B1.Step 4.

- [ ] **Step 3: Commit.**

```bash
git add Sotto/Views/Settings/HandsFreeSettingsView.swift
git commit -m "settings(C2): HandsFreeSettingsView tokens + SF Mono segmented"
```

### Task C3: AudioInputSettingsView re-skin

**Files:**
- Modify: `Sotto/Views/Settings/AudioInputSettingsView.swift`

- [ ] **Step 1: Token swap (≥6 hits).**

`grep -n "Palette.accent" Sotto/Views/Settings/AudioInputSettingsView.swift` → flip all to `brandAcid`.

- [ ] **Step 2: cornerRadius collapse on InputModeCard / DeviceSelectionCard / DevicePriorityCard.**

Find `cornerRadius: 16` across InputModeCard (line 310, 313) / DeviceSelectionCard (line 357, 360) / DevicePriorityCard (line 461) → all flip to `8`.

- [ ] **Step 3: SF Mono Text.**

Lines 44–47 (`Input Mode` title) + 62–65 (`Current Device` title) + 99–101 (`Available Devices`) + 140–145 (`Prioritized Devices` + description) + 162–164 — mono'fy each Text with the same `.font(.system(size: N, weight: .bold, design: .monospaced)).tracking(0.02*N)` pattern.

- [ ] **Step 4: Commit.**

```bash
git add Sotto/Views/Settings/AudioInputSettingsView.swift
git commit -m "settings(C3): AudioInputSettingsView tokens + 8pt cards + SF Mono"
```

### Task C4: RecorderStylePicker re-skin

**Files:**
- Modify: `Sotto/Views/Settings/RecorderStylePicker.swift`

- [ ] **Step 1: cornerRadius collapse.**

Lines 68–73 + 88–90 — `cornerRadius: 10` (preview) → `8`; `cornerRadius: 12` (card) → `8`.

- [ ] **Step 2: Tokens + SF Mono.**

Lines 71 + 89: `Palette.accent` → `Palette.brandAcid`.
Lines 77–82: title (size 12 bold) + subtitle (size 10) — add `design: .monospaced` + `.tracking(0.02 * size)`.

- [ ] **Step 3: Commit.**

```bash
git add Sotto/Views/Settings/RecorderStylePicker.swift
git commit -m "settings(C4): RecorderStylePicker 8pt + tokens + SF Mono"
```

### Task C5: CustomSoundSettingsView re-skin

**Files:**
- Modify: `Sotto/Views/Settings/CustomSoundSettingsView.swift`

- [ ] **Step 1: Token swap + cornerRadius.**

Run: `grep -n "Palette.accent\|cornerRadius:" Sotto/Views/Settings/CustomSoundSettingsView.swift`
Expected hits: `Palette.accent` line 144–146 (tint), `cornerRadius: 14` line 50 (`GlassCard`).

- Line 50: `GlassCard(cornerRadius: 14, padding: 14)` → `GlassCard(cornerRadius: 8, padding: 14)`.
- Lines 144–146: `Palette.accent` → `Palette.brandAcid`.

- [ ] **Step 2: Title text mono.**

Line 56–58: cue title — `Text(type.displayName).font(.system(size: 13, weight: .semibold))` → add `design: .monospaced` + `.tracking(0.02*13)`.

- [ ] **Step 3: Commit.**

```bash
git add Sotto/Views/Settings/CustomSoundSettingsView.swift
git commit -m "settings(C5): CustomSoundSettingsView 8pt + tokens"
```

### Task C6: EnhancementShortcutsView + CommandPaletteSheet + AudioCleanup + Diagnostics

**Files:**
- Modify: `Sotto/Views/Settings/EnhancementShortcutsView.swift`
- Modify: `Sotto/Views/Settings/CommandPaletteSheet.swift`
- Modify: `Sotto/Views/Settings/AudioCleanupSettingsView.swift`
- Modify: `Sotto/Views/Settings/DiagnosticsSettingsView.swift`

- [ ] **Step 1: EnhancementShortcutsView.swift.**

Line 60: `KeyChip` `cornerRadius: 6` → `cornerRadius: 2` (both `.fill` and overlay stroke at lines 60–70). Line 55: already mono — verify weight `.medium` matches spec (spec wants bold 700 for labels; medium is acceptable here as it's keyboard glyph display, not a label).

- [ ] **Step 2: CommandPaletteSheet.swift.**

Line 340: `Palette.accent` → `Palette.brandAcid`.
Line 365: `cornerRadius: 8` is already at spec — keep.
Line 366: `Palette.accent.opacity(0.14)` → `Palette.brandAcid.opacity(0.14)`.

- [ ] **Step 3: AudioCleanupSettingsView.swift.**

Line 211: `.tint(Palette.accent)` → `.tint(Palette.brandAcid)`. No structural changes.

- [ ] **Step 4: DiagnosticsSettingsView.swift.**

Line 18: `Palette.success` (green checkmark on export success) — keep, it's a `success` semantic (§1.4 keeps green for "committed / success utility only").

No edits needed. Verify with `grep -n "Palette.accent" Sotto/Views/Settings/DiagnosticsSettingsView.swift` → zero hits.

- [ ] **Step 5: Commit.**

```bash
git add Sotto/Views/Settings/EnhancementShortcutsView.swift \
        Sotto/Views/Settings/CommandPaletteSheet.swift \
        Sotto/Views/Settings/AudioCleanupSettingsView.swift
git commit -m "settings(C6): minor surfaces token swap + 2pt KeyChip"
```

### Task C7: PermissionsView re-skin

**Files:**
- Modify: `Sotto/Views/PermissionsView.swift`

- [ ] **Step 1: PermissionCard cornerRadius.**

Lines 98 + 103–109 + 178–183: `cornerRadius: 14` (GlassCard) → `8`; `cornerRadius: 10` (icon tile + CTA button) → `2` (icon tile) and `8` (CTA button).

- [ ] **Step 2: CTA button tokens.**

Line 180: `.fill(Palette.accent)` → `.fill(Palette.brandAcid)`.
Line 173: `.foregroundColor(.white)` — verify legibility on lime; spec wants black text on lime CTA per §1.4 implied contrast. Change to `.foregroundColor(.black)` for AAA-grade contrast.

- [ ] **Step 3: SF Mono labels.**

Lines 119–123 (title `.headline`) + 130–132 (description `.subheadline`) + 167–171 (CTA button text size 14 semibold) — add `design: .monospaced` + tracking.

- [ ] **Step 4: Permission status pill color.**

`StatusPill(text: "Granted"...)` (line 158) uses `tone: .positive` (green) which stays. `tone: .warning` (amber) stays. No edits to the pill — token semantics preserved.

- [ ] **Step 5: Commit.**

```bash
git add Sotto/Views/PermissionsView.swift
git commit -m "settings(C7): PermissionsView 8pt cards + lime CTA + SF Mono"
```

### Task C8: Group C integration + PR

- [ ] **Step 1: Build + smoke.**

`make local` → open every pane (Settings, Hands-free, Audio Input, Permissions) → verify every accent surface is lime, every card is 8pt.

- [ ] **Step 2: Regression check on AppStorage / SwiftData / KeyboardShortcuts.**

```bash
grep -rn "@AppStorage\|@Query" Sotto/Views/Settings/ Sotto/Views/PermissionsView.swift | wc -l
```
Compare against pre-Group-C count (capture in Step 0.3). Must match exactly — no key added/removed.

- [ ] **Step 3: PR.**

```bash
gh pr create --title "sotto-settings/C: non-Models panes re-skin" --base main \
  --body "$(cat <<'EOF'
## Summary
- SettingsView root pane: 25× accent → brandAcid.
- HandsFree / AudioInput / Permissions / RecorderStyle / CustomSound / CommandPalette / EnhancementShortcuts: tokens + cornerRadius collapse + SF Mono.
- Zero AppStorage / KeyboardShortcuts.Name / SwiftData @Query changes.
- StatusPill tone semantics preserved (positive=green, warning=amber, neutral=gray) — only `accent` flipped.

## Test plan
- [ ] Each sidebar pane renders w/ lime accents + 8pt cards
- [ ] Permission CTA reads black-on-lime cleanly
- [ ] Hands-free segmented controls render SF Mono
- [ ] All toggles + pickers persist via @AppStorage (regression check)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Group D — Accessibility integration

Spec §1.X and §4 require explicit A11y branches. Most are already routed via `AdaptiveGlassBackground` (Reduce-Transparency + High-Contrast); SETTINGS adds VoiceOver labels and a Reduce-Motion guard for the Settings-side animations (mostly DisclosureGroup chevron rotations and `ExpandableSettingsRow` cross-fades).

### Task D1: VoiceOver audit + labels

**Files:**
- Modify (light touch — only on rows missing labels): each pane in Group C

- [ ] **Step 1: Run VoiceOver audit.**

Open Sotto under VoiceOver (`Cmd+F5`). Cursor through Settings sidebar → each detail pane → each row. Note every row that announces as "Toggle" / "Picker" without context.

Expected gaps:
- `ExpandableSettingsRow`'s chevron — no a11y on the toggle expand state.
- `SidebarItemView`'s `›` glyph — already `accessibilityLabel("Configured")` on the dot (line 292); confirm the `›` doesn't double-announce. Add `.accessibilityHidden(true)` on the glyph Text.

- [ ] **Step 2: Patch `ExpandableSettingsRow` (lines 606–676 of SettingsView.swift).**

After line 640 (the `.contentShape(Rectangle())` + `.onTapGesture`), add `.accessibilityElement(children: .combine)` + `.accessibilityValue(isExpanded ? "Expanded" : "Collapsed")` so VoiceOver announces the toggle state explicitly.

- [ ] **Step 3: Patch `SidebarItemView` glyph.**

In `SidebarItemView.body` (post-A6), add `.accessibilityHidden(true)` on the `Text("›")` line.

- [ ] **Step 4: Commit.**

```bash
git add Sotto/Views/Settings/SettingsView.swift Sotto/Views/ContentView.swift
git commit -m "settings(D1): VoiceOver labels on Expandable rows + sidebar prompt"
```

### Task D2: Reduce Motion guard

**Files:**
- Modify: `Sotto/Views/Settings/SettingsView.swift` (ExpandableSettingsRow's `withAnimation` calls — lines 645, 666)
- Modify: `Sotto/Views/Settings/AudioCleanupSettingsView.swift` (same pattern lines 49, 88, 126, 199)

- [ ] **Step 1: Add `@Environment(\.accessibilityReduceMotion)` to both files.**

In each ExpandableSettingsRow or equivalent, replace the bare `withAnimation(Animation.haloPhaseCrossfade)` with a guard:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
// …
withAnimation(reduceMotion ? .none : Animation.haloPhaseCrossfade) {
    isExpanded.toggle()
}
```

Apply at every `withAnimation` site inside ExpandableSettingsRow (lines 645, 666) and AudioCleanupSettingsView (lines 49, 88, 126, 199).

- [ ] **Step 2: Verify under Reduce Motion.**

Toggle System Settings → Accessibility → Display → Reduce Motion. Tap an `ExpandableSettingsRow` chevron — expansion should be instant, no slide animation.

- [ ] **Step 3: Commit.**

```bash
git add Sotto/Views/Settings/SettingsView.swift Sotto/Views/Settings/AudioCleanupSettingsView.swift
git commit -m "settings(D2): Reduce Motion guard on Expandable + AudioCleanup"
```

### Task D3: High-Contrast pass

**Files:**
- Verify only — `AdaptiveGlassBackground` already routes through HC branch (lines 60–66).

- [ ] **Step 1: Enable Increase Contrast.**

System Settings → Accessibility → Display → Increase Contrast. Open Sotto → every pane should render with opaque `windowBackgroundColor` (no glass), per AdaptiveGlassBackground line 65.

- [ ] **Step 2: Verify lime selected-row remains visible.**

`Palette.brandAcid` on lime under HC should still hit AAA contrast against the system-adaptive `windowBackgroundColor`. If it fails, file a Group E follow-up — do NOT add ad-hoc HC color overrides here.

- [ ] **Step 3: No commit (verification only).**

### Task D4: Group D PR

- [ ] **Step 1: PR.**

```bash
gh pr create --title "sotto-settings/D: accessibility — VoiceOver + Reduce Motion" --base main \
  --body "$(cat <<'EOF'
## Summary
- VoiceOver: `ExpandableSettingsRow` announces expanded/collapsed state; sidebar `›` glyph hidden from announcement.
- Reduce Motion: SettingsView + AudioCleanup withAnimation guards.
- High-Contrast: AdaptiveGlassBackground already routes correctly; lime under HC verified AAA.

## Test plan
- [ ] VoiceOver reads each row label + control
- [ ] Reduce Motion → ExpandableSettingsRow no longer animates
- [ ] Increase Contrast → opaque windowBackgroundColor everywhere

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Group E — Coordination + audit report

### Task E1: W14F conformance audit report

**Files:**
- Create: `docs/superpowers/reports/2026-05-11-W14F-conformance.md`

- [ ] **Step 1: Write report.**

```bash
mkdir -p docs/superpowers/reports
```

Write `docs/superpowers/reports/2026-05-11-W14F-conformance.md` with these sections (verbatim — no placeholders):

```markdown
# W14F conformance audit — 2026-05-11

**Auditor:** SETTINGS pair (planner-settings → coder-settings)
**Scope:** ModelsView.swift + EnhancementProviderSection.swift + APIKeyManagementView.swift (shipped commits 924f9a6 + b1148d2 on main)
**Spec:** docs/superpowers/specs/2026-05-11-sotto-ui-redesign-design.md §6.2 + Appendix B.W14FConformance

## Verdict: Structurally conformant; visual delta required (closed by Group B PR)

### Conformant (no change)
- Two-tab segmented control (Enhancement / Transcriber) at top of pane — matches §6.1.surface-6
- `ActiveEnhancementProviderCard` focal card pattern — matches §1 focal-card vocabulary
- `OtherEnhancementProvidersAccordion` DisclosureGroup-style fold — matches §1 accordion vocabulary
- `ReorderablePromptGrid` drag-reorder — orthogonal to spec, preserved
- Sliding panel for prompt editor (`activePanel == .promptEditor`) — preserved
- AppStorage `ModelsViewSelectedTab` survives restart — preserved
- KeychainHelper writes via `ProviderCard.onActivate` — preserved

### Delta (closed by Group B PR)
| Spec § | W14F shipped | Delta | Closed by |
|---|---|---|---|
| §1.4 brandAcid lime `#D4FF3A` | `Palette.accent` tangerine `#FF5B3A` | wrong hue | Task B1 + B2 + B3 |
| §1.2 cornerRadius ≤ 8pt | `cornerRadius: 14` on focal cards + `9` on pictogram tiles | too rounded | Task B1 + B2 |
| §1 acceptance "no .regularMaterial / .ultraThinMaterial" | `.ultraThinMaterial` ad-hoc in 4+ sites | banned material | Task B1 + B2 (TacticalGlass swap) |
| §1.3 uppercase tracking +0.16em | `tracking(0.06 * N)` ~= 0.06em | tracking too tight | Task B2 |

### Open question (NOT in SETTINGS-pair scope)
- **B.ModeList chip rule:** spec §2.3 says left HUD chip displays `activePrompt?.title.uppercased()` truncated 9 chars; hide if nil. Current HUD code (`RecorderComponents.swift:160-170`) renders `activePrompt?.icon`, not the title. This is HUD-pair surface — flagged for HUD pair.

### Recommendation
Merge Group B PR. After merge: re-run this audit. Expected outcome: all "Delta" rows become "Conformant"; "Open question" remains pending HUD-pair landing.
```

- [ ] **Step 2: Commit.**

```bash
git add docs/superpowers/reports/2026-05-11-W14F-conformance.md
git commit -m "settings(E1): W14F conformance audit report"
```

### Task E2: Cross-pair coordination notes

- [ ] **Step 1: Confirm TacticalGlass + brandAcid landed by HUD.**

After HUD pair's Group A lands (track via `git log main`), find the `// TODO(HUD-TacticalGlass)` markers placed in Group B:

```bash
grep -rn "TODO(HUD-TacticalGlass)" Sotto/
```
Expected: 4–8 hits (from Tasks B1.Step 3, B2.Step 2, B3.Step 2). Replace each fallback `HaloMaterial` direct compose with `TacticalGlass(shape:phase:appearance:)`.

- [ ] **Step 2: Retire tangerine token (post-Group C verification).**

After all PRs Group A–C merged, every `Palette.accent` reference in surfaces SETTINGS owns must be `Palette.brandAcid`. Verify globally:

```bash
grep -rn "Palette.accent\b" Sotto/Views/Settings/ Sotto/Views/Models/ \
     "Sotto/Views/AI Models/" Sotto/Views/PermissionsView.swift \
     Sotto/Views/ContentView.swift
```
Expected: zero hits in SETTINGS surfaces. (Other pairs may still hold tangerine until they re-skin — that's fine; deletion of `Palette.accent` is the final step in the redesign integration branch, not this PR.)

- [ ] **Step 3: Final smoke + handoff message to team-lead.**

`make local` → click every sidebar entry → confirm Sotto §1 vocabulary applied. Then SendMessage team-lead with completion + audit report path.

---

## Acceptance — final §1 checklist

Each must be ✓ before integration:

- [ ] All SETTINGS surfaces (sidebar shell + 4 panes × 7 files) route every accent surface through `Palette.brandAcid` (no `Palette.accent` left).
- [ ] All cards in SETTINGS use `cornerRadius` ≤ 8pt (matte 2pt for tiles, 8pt for cards). No 10/12/14/16pt.
- [ ] All SETTINGS labels use SF Mono with `design: .monospaced`. User-typed prose (trigger phrase text fields, prompt editor body) MAY keep SF Pro.
- [ ] Uppercase labels track `+0.16em` (was `+0.06em` pre-redesign).
- [ ] Sidebar rows show `›` prefix; lime selected-row tint via `.tint(Palette.brandAcid)`.
- [ ] `Sotto.` wordmark renders w/ lime period at top of sidebar.
- [ ] `AdaptiveGlassBackground` layers RadialGradient bleed behind the blur.
- [ ] No `.ultraThinMaterial` ad-hoc in SETTINGS files (all routed through `TacticalGlass` or `GlassCard`).
- [ ] VoiceOver announces every row's state correctly under Cmd+F5.
- [ ] Reduce Motion disables `ExpandableSettingsRow` slide-down animation.
- [ ] Increase Contrast renders opaque pane backgrounds via existing AdaptiveGlassBackground HC branch.
- [ ] W14F conformance audit committed at `docs/superpowers/reports/2026-05-11-W14F-conformance.md`.
- [ ] Zero behavior change — every `@AppStorage`, `@Query`, `KeyboardShortcuts.Name`, `KeychainHelper` call site unchanged.

---

## Open spikes (escalated, not blocking)

- **B.ModeList HUD-side rule** (Task B4.Step 2): HUD pair must implement chip = `activePrompt?.title.uppercased()` truncated 9 chars; hide chip if nil. Currently renders `.icon`. Filed in audit report; ping HUD pair team-lead post-merge.
- **HC contrast on lime selected-row** (Task D3.Step 2): if AAA contrast fails under Increase Contrast, file a Group E follow-up for an HC-branch override in `Palette.brandAcid`. Don't add ad-hoc here.

---

## Unresolved questions

1. **TacticalGlass landing window:** Group A and Group C can land independently; Group B depends on HUD's `TacticalGlass` primitive. If HUD slips, Group B uses `HaloMaterial` direct (per Task B1.Step 3 fallback) and we retrofit the swap in Task E2 — adds one trailing PR.
2. **CompactHeroSection retirement:** currently used by `AudioInputSettingsView` (line 38) + `PermissionsView` (line 202). The Sotto spec doesn't explicitly enumerate hero sections — should each pane's hero stay, or fold into the sidebar's nav title? Default: keep (no spec violation), no extra work.
3. **`Sotto.` wordmark placement in sidebar:** Task A6.Step 2 replaces the existing "VoiceInk" header text with "Sotto." Worded heuristically per §5.1. If the wordmark requires its own dedicated section (e.g. larger, glow halo per §5.1), revisit in Group E.
