# Sotto UI — MAIN Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the main window (sidebar, transcript history, dashboard tiles, snippets, scratchpad, dictionary) to Sotto §1 vocabulary — SF Mono, Acid Lime (`brandAcid`), `TacticalGlass`, corner radii ≤ 8pt, `›` prompt glyphs, wallpaper bleed-through background.

**Architecture:** Visual-only re-skin on top of existing `NavigationSplitView`. No behavior changes. All glass surfaces route through `TacticalGlass` (wraps `HaloMaterial`). Typography switches to SF Mono throughout; `Palette.brandAcid` replaces all tangerine `Palette.accent` references in MAIN surfaces only.

**Tech Stack:** SwiftUI 5 (macOS 14.4+), `Font.system(.body, design: .monospaced)`, `HaloMaterial` / `GlassCard` / `AdaptiveGlass` pattern from `VoiceInk/Views/Recorder/HaloMaterial.swift` and `VoiceInk/Views/Common/`.

**Dependencies:**
- **RENAME pair** must land first (file paths; plan works on `VoiceInk/` paths until then)
- **HUD pair** owns `TacticalGlass.swift` + `Palette.brandAcid`. Task 1 adds stubs — coordinate at merge to eliminate duplicates.

---

## File Map

| File | Change |
|---|---|
| `VoiceInk/Views/Common/Palette.swift` | Add `brandAcid` + `ghost` tokens (stub; HUD pair owns final) |
| `VoiceInk/Views/Common/TacticalGlass.swift` | New stub (owned by HUD; used by MAIN) |
| `VoiceInk/Views/ContentView.swift` | Wallpaper bleed bg, wordmark header, tint swap, `isSelected` pass-through |
| `VoiceInk/Views/Metrics/MetricCard.swift` | SF Mono, `brandAcid`, `cornerRadius 2pt` |
| `VoiceInk/Views/Metrics/MetricsContent.swift` | Hero section → TacticalGlass + brandAcid; text → SF Mono; "VoiceInk" → "Sotto" |
| `VoiceInk/Views/Metrics/ModelPerformancePanel.swift` | Panel header + model/enhancement tiles → SF Mono, TacticalGlass |
| `VoiceInk/Views/History/InlineHistoryView.swift` | Search bar, card rows, expanded body, panel header → SF Mono; `cornerRadius 2pt` |
| `VoiceInk/Views/Snippets/SnippetsSettingsView.swift` | Tint → `brandAcid` |
| `VoiceInk/Views/Scratchpad/ScratchpadView.swift` | Tab strip → SF Mono, `brandAcid` active |
| `VoiceInk/Views/Dictionary/DictionarySettingsView.swift` | `SectionCard` → `brandAcid`, SF Mono |
| (multiple) | VoiceOver labels, `accessibilityReduceMotion` guards |

---

## Task 1: Stub dependencies — `Palette.brandAcid`, `ghost`, `TacticalGlass`

> Skip token additions if HUD has already landed `Palette.brandAcid`. Skip TacticalGlass.swift if HUD has already created it.

**Files:**
- Modify: `VoiceInk/Views/Common/Palette.swift:43` (after `accentGlow`)
- Create: `VoiceInk/Views/Common/TacticalGlass.swift`

- [ ] **Step 1: Check if `Palette.brandAcid` already exists**

```bash
grep -n "brandAcid" VoiceInk/Views/Common/Palette.swift
```
Expected: no output (HUD hasn't landed yet). If it exists → skip Step 2.

- [ ] **Step 2: Add `brandAcid` + `ghost` to `Palette.swift` after line 43**

In `VoiceInk/Views/Common/Palette.swift`, add after the `accentGlow` line (~line 43):

```swift
    /// #D4FF3A — Acid Lime. Sidebar selected rows, section labels, CTA glyphs,
    /// HUD bars. Replaces tangerine `accent` on all Sotto surfaces. §1.4.
    /// NOTE: HUD pair owns this token; stub added here for MAIN compilation.
    /// Remove duplicate at merge.
    static let brandAcid = Color(red: 0.831, green: 1.000, blue: 0.227)  // #D4FF3A

    /// rgba(255,255,255,0.42) — secondary text on glass. §1.4.
    static let ghost = Color.white.opacity(0.42)
```

- [ ] **Step 3: Check if `TacticalGlass.swift` already exists**

```bash
find VoiceInk -name "TacticalGlass.swift"
```
Expected: no output. If it exists → skip Step 4.

- [ ] **Step 4: Create `TacticalGlass.swift` stub**

```swift
// VoiceInk/Views/Common/TacticalGlass.swift
// Sotto Tactical Glass primitive §1.1.
// NOTE: HUD pair owns this file; stub added for MAIN compilation.
// Remove duplicate at merge — defer to HUD's version.
import SwiftUI

struct TacticalGlass<S: Shape>: View {
    let shape: S
    var phase: HaloPhase = .hidden
    var appearance: GlassAppearance = .onyx

    var body: some View {
        HaloMaterial(shape: shape, phase: phase, appearance: appearance)
    }
}
```

- [ ] **Step 5: Build to confirm no errors**

```bash
make local 2>&1 | tail -20
```
Expected: build succeeds (no errors on `brandAcid` or `TacticalGlass`).

- [ ] **Step 6: Commit**

```bash
git add VoiceInk/Views/Common/Palette.swift VoiceInk/Views/Common/TacticalGlass.swift
git commit -m "chore(main): stub brandAcid token + TacticalGlass for MAIN re-skin"
```

---

## Task 2: `ContentView.swift` — wallpaper bleed background + sidebar tokens

Acceptance (§1): wallpaper bleed present under root window; wordmark shows "Sotto."; `tint` uses `brandAcid`; `SidebarItemView` passes selection state for `›` coloring.

**Files:**
- Modify: `VoiceInk/Views/ContentView.swift`

- [ ] **Step 1: Add `sottoBackground` private computed property before `body`**

In `ContentView` (before `var body: some View {`, ~line 95), add:

```swift
    private var sottoBackground: some View {
        ZStack {
            Color(red: 0.051, green: 0.051, blue: 0.063)  // #0d0d10
            GeometryReader { geo in
                RadialGradient(
                    colors: [
                        Color(red: 0.431, green: 0.243, blue: 0.714).opacity(0.18),
                        .clear
                    ],
                    center: UnitPoint(x: 0.20, y: 0.0),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.55
                )
                RadialGradient(
                    colors: [Palette.brandAcid.opacity(0.06), .clear],
                    center: UnitPoint(x: 1.0, y: 1.0),
                    startRadius: 0,
                    endRadius: geo.size.width * 0.45
                )
            }
        }
        .ignoresSafeArea()
    }
```

- [ ] **Step 2: Replace `.adaptiveGlassBackground()` backstop with `sottoBackground`**

In `ContentView.body`, the `.adaptiveGlassBackground()` at ~line 150 is the "backstop" that applies to the `NavigationSplitView`. Replace it with `.background(sottoBackground)`:

Old (line 150):
```swift
        .adaptiveGlassBackground()
```

New:
```swift
        .background(sottoBackground)
```

- [ ] **Step 3: Swap sidebar `tint` to `brandAcid`**

Line 131:
```swift
// Old:
            .tint(Palette.accent)
// New:
            .tint(Palette.brandAcid)
```

- [ ] **Step 4: Replace sidebar app-header wordmark**

Lines 100–113 (the `HStack` with AppIcon + "VoiceInk" text):

```swift
// Old:
                HStack(spacing: 6) {
                    if let appIcon = NSImage(named: "AppIcon") {
                        Image(nsImage: appIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .cornerRadius(8)
                    }

                    Text("VoiceInk")
                        .font(.system(size: 14, weight: .semibold))

                    Spacer()
                }
                .padding(.vertical, 4)

// New:
                HStack(spacing: 0) {
                    Text("Sotto")
                        .font(.system(size: 15, design: .monospaced).weight(.bold))
                        .foregroundStyle(.primary)
                    Text(".")
                        .font(.system(size: 15, design: .monospaced).weight(.black))
                        .foregroundStyle(Palette.brandAcid)
                    Spacer()
                }
                .padding(.vertical, 4)
```

- [ ] **Step 5: Pass `isSelected` to `SidebarItemView`**

In the `ForEach` loop (~line 117–128), change the `SidebarItemView` call to pass selection:

```swift
// Old:
                        NavigationLink(value: viewType) {
                            SidebarItemView(
                                viewType: viewType,
                                isConfigured: isConfigured(viewType)
                            )
                        }

// New:
                        NavigationLink(value: viewType) {
                            SidebarItemView(
                                viewType: viewType,
                                isConfigured: isConfigured(viewType),
                                isSelected: viewType == selectedView
                            )
                        }
```

- [ ] **Step 6: Rewrite `SidebarItemView` (lines 269–300)**

Replace the entire `SidebarItemView` struct:

```swift
private struct SidebarItemView: View {
    let viewType: ViewType
    let isConfigured: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text("›")
                .font(.system(size: 13, design: .monospaced).weight(.bold))
                .foregroundStyle(isSelected ? Palette.brandAcid : Palette.ghost)
                .accessibilityHidden(true)

            Text(viewType.rawValue.uppercased())
                .font(.system(size: 12, design: .monospaced).weight(.bold))
                .tracking(0.16 * 12)   // +0.16em at 12pt
                .foregroundStyle(isSelected ? Color.primary : Palette.ghost)

            Spacer()

            if isConfigured {
                Circle()
                    .fill(Palette.brandAcid.opacity(0.75))
                    .frame(width: 5, height: 5)
                    .accessibilityLabel("Configured")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewType.rawValue)
        .accessibilityAddTraits(isConfigured ? [.isSelected] : [])
    }
}
```

- [ ] **Step 7: Build to confirm no errors**

```bash
make local 2>&1 | tail -20
```
Expected: clean build.

- [ ] **Step 8: Commit**

```bash
git add VoiceInk/Views/ContentView.swift
git commit -m "feat(main-t2): sidebar › prompts, SF Mono, brandAcid, Sotto wordmark, wallpaper bleed"
```

---

## Task 3: `MetricCard` + `MetricsContent` + `ModelPerformancePanel` (Dashboard tiles)

Acceptance (§1): no `cornerRadius > 8pt`; SF Mono throughout; `brandAcid` replaces tangerine; "VoiceInk" → "Sotto" in hero text; hero section on `TacticalGlass`; ModelPerformancePanel tiles use `TacticalGlass`.

**Files:**
- Modify: `VoiceInk/Views/Metrics/MetricCard.swift`
- Modify: `VoiceInk/Views/Metrics/MetricsContent.swift`
- Modify: `VoiceInk/Views/Metrics/ModelPerformancePanel.swift`

### MetricCard.swift (lines 1–47)

- [ ] **Step 1: Re-skin `MetricCard` body**

Replace the full `body` property in `MetricCard`:

```swift
    var body: some View {
        GlassCard(cornerRadius: 2) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Palette.brandAcid.opacity(0.12))
                        Image(systemName: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Palette.brandAcid)
                    }
                    .frame(width: 30, height: 30)

                    Text(title.uppercased())
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 10)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(Palette.ghost)
                }

                Text(value)
                    .font(.system(size: 22, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.brandAcid)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.ghost)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)\(detail.map { ", \($0)" } ?? "")")
    }
```

Note: `detail` is `let detail: String?` — the `detail.map` call correctly handles `nil`.

- [ ] **Step 2: Build MetricCard**

```bash
make local 2>&1 | grep -E "error:|MetricCard" | head -10
```
Expected: no errors.

### MetricsContent.swift

- [ ] **Step 3: Replace `heroSection` in `MetricsContent`**

Replace `heroSection` computed property (~lines 162–206):

```swift
    private var heroSection: some View {
        VStack(spacing: 8) {
            HStack {
                Spacer(minLength: 0)
                (
                    Text("You have saved ")
                        .font(.system(size: 22, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                    + Text(formattedTimeSaved)
                        .font(.system(size: 28, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.brandAcid)
                    + Text(" with Sotto")
                        .font(.system(size: 22, design: .monospaced).weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.85))
                )
                .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)

            Text(heroSubtitle)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Palette.ghost)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            TacticalGlass(
                shape: RoundedRectangle(cornerRadius: 8, style: .continuous),
                phase: .done
            )
        )
    }
```

- [ ] **Step 4: Replace `heroSubtitle` "VoiceInk" → "Sotto"**

In `heroSubtitle` (~line 268), change:
```swift
// Old:
        return "Dictated \(wordsText) words across \(totalCount) \(sessionText)."
// New (same text, no VoiceInk reference):
        return "Dictated \(wordsText) words across \(totalCount) \(sessionText)."
```

Also change `emptyStateView` (~line 147):
```swift
// Old:
            Text("No Recorder Sessions Yet")
                .font(.title3.weight(.semibold))
            Text("Start your first recording to unlock value insights.")
                .foregroundColor(.secondary)

// New:
            Text("NO SESSIONS YET")
                .font(.system(size: 15, design: .monospaced).weight(.bold))
                .foregroundStyle(Palette.ghost)
            Text("start your first recording")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.ghost.opacity(0.7))
```

- [ ] **Step 5: Re-skin `footerActionsView` buttons in `MetricsContent`**

Replace `footerActionsView` (~lines 242–259):

```swift
    private var footerActionsView: some View {
        HStack(spacing: 8) {
            Button(action: {
                withAnimation(.smooth(duration: 0.3)) { isModelStatsPanelPresented = true }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "gauge")
                        .font(.system(size: 11))
                    Text("▸ MODEL PERF")
                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 11)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Palette.brandAcid.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Palette.hairline, lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.brandAcid)
            .help("View transcription and enhancement model performance")
            CopySystemInfoButton()
        }
    }
```

- [ ] **Step 6: Delete `heroGradient` computed property — it's now unused**

Remove lines ~278–287 (the `heroGradient` property). Build will flag it as unused if left; remove to keep code clean:

```swift
// DELETE this block:
    private var heroGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                Palette.accent,
                Palette.accent.opacity(0.85),
                Palette.accent.opacity(0.7)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
```

### ModelPerformancePanel.swift

- [ ] **Step 7: Re-skin `ModelPerformancePanel` header**

Replace `header` computed property (~lines 53–76):

```swift
    private var header: some View {
        HStack(spacing: 10) {
            Text("MODEL PERFORMANCE")
                .font(.system(size: 11, design: .monospaced).weight(.bold))
                .tracking(0.16 * 11)
                .foregroundStyle(Palette.ghost)
            Spacer()
            Picker("", selection: Binding(get: { filter }, set: { filterRaw = $0.rawValue })) {
                ForEach(TimeFilter.allCases) { f in
                    Text(f.rawValue.uppercased())
                        .font(.system(size: 11, design: .monospaced))
                        .tag(f)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            Button(action: onClose) {
                Text("✕")
                    .font(.system(size: 12, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.ghost)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
        }
    }
```

Also replace the panel background. In `body`, change:
```swift
// Old:
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(Divider().opacity(0.5), alignment: .bottom)
// New:
                .background(
                    TacticalGlass(
                        shape: Rectangle(),
                        phase: .hidden
                    )
                )
                .overlay(
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 0.5),
                    alignment: .bottom
                )
```

- [ ] **Step 8: Re-skin `modelTile` in `ModelPerformancePanelContent`**

Replace `modelTile` function (~lines 167–220):

```swift
    private func modelTile(_ stat: ModelPerformanceStat) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(stat.name.uppercased())
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(0.16 * 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)
                Text("\(stat.sessionCount) sessions")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.ghost)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text(String(format: "%.1fx", stat.speedFactor))
                    .font(.system(size: 20, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.brandAcid)
                Text(stat.speedFactor >= 1.0 ? "faster than real-time" : "slower than real-time")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.ghost)
            }

            Rectangle()
                .fill(Palette.hairline)
                .frame(height: 0.5)
                .padding(.horizontal, 4)

            HStack(spacing: 0) {
                VStack(spacing: 2) {
                    Text(formatDuration(stat.avgAudioDuration))
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.ghost)
                    Text("AVG AUDIO")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(0.16 * 8)
                        .foregroundStyle(Palette.ghost.opacity(0.6))
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 0.5, height: 20)

                VStack(spacing: 2) {
                    Text(String(format: "%.2fs", stat.avgProcessingTime))
                        .font(.system(size: 10, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.ghost)
                    Text("AVG PROC")
                        .font(.system(size: 8, design: .monospaced))
                        .tracking(0.16 * 8)
                        .foregroundStyle(Palette.ghost.opacity(0.6))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(
            TacticalGlass(shape: RoundedRectangle(cornerRadius: 2, style: .continuous), phase: .hidden)
        )
    }
```

- [ ] **Step 9: Re-skin `enhancementTile`**

Replace `enhancementTile` function (~lines 235–260):

```swift
    private func enhancementTile(_ stat: EnhancementStat) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(stat.name.uppercased())
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(0.16 * 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.primary)
                Text("\(stat.sessionCount) sessions")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.ghost)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                Text(String(format: "%.2fs", stat.avgDuration))
                    .font(.system(size: 20, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.brandAcid)
                Text("avg enhancement time")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Palette.ghost)
            }
        }
        .padding(12)
        .background(
            TacticalGlass(shape: RoundedRectangle(cornerRadius: 2, style: .continuous), phase: .hidden)
        )
    }
```

- [ ] **Step 10: Re-skin `sectionHeader` helper**

Replace `sectionHeader` function (~lines 264–270):

```swift
    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text("›")
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .foregroundStyle(Palette.brandAcid)
                .accessibilityHidden(true)
            Text(title.uppercased())
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .tracking(0.16 * 10)
                .foregroundStyle(Palette.ghost)
        }
    }
```

- [ ] **Step 11: Build — confirm no errors**

```bash
make local 2>&1 | tail -20
```
Expected: clean build.

- [ ] **Step 12: Commit**

```bash
git add VoiceInk/Views/Metrics/MetricCard.swift \
        VoiceInk/Views/Metrics/MetricsContent.swift \
        VoiceInk/Views/Metrics/ModelPerformancePanel.swift
git commit -m "feat(main-t3): dashboard tiles SF Mono + brandAcid + TacticalGlass re-skin"
```

---

## Task 4: `InlineHistoryView` — transcript history surface

Acceptance (§1): SF Mono throughout; `GlassCard(cornerRadius: 2)`; `brandAcid` selection accent; section header with `›`; VoiceOver on row actions.

**Files:**
- Modify: `VoiceInk/Views/History/InlineHistoryView.swift`

- [ ] **Step 1: Re-skin `topBar`**

Replace `topBar` computed property (~lines 152–172):

```swift
    private var topBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.ghost)
                    .font(.system(size: 11, design: .monospaced))
                TextField("search transcriptions…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Palette.hairline, lineWidth: 0.5)
                    )
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
```

- [ ] **Step 2: Re-skin `selectionBar`**

Replace `selectionBar` (~lines 174–231):

```swift
    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text("\(selectedTranscriptions.count) selected")
                .font(.system(size: 11, design: .monospaced).weight(.bold))
                .tracking(0.16 * 11)
                .foregroundStyle(Palette.ghost)
                .textCase(.uppercase)

            Spacer()

            Button(action: {
                panelMode = .analysis
                withAnimation(Animation.haloExpand) { isPanelPresented = true }
            }) {
                Text("▸ ANALYZE")
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(0.16 * 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.brandAcid)

            Button(action: {
                exportService.exportTranscriptionsToCSV(transcriptions: Array(selectedTranscriptions))
            }) {
                Text("▸ EXPORT")
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(0.16 * 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.ghost)

            Button(action: { showDeleteConfirmation = true }) {
                Text("▸ DELETE")
                    .font(.system(size: 10, design: .monospaced).weight(.bold))
                    .tracking(0.16 * 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 1.0, green: 0.231, blue: 0.188).opacity(0.8))  // recRed

            Rectangle()
                .fill(Palette.hairline)
                .frame(width: 0.5, height: 14)

            if allSelected {
                Button("DESEL ALL") {
                    selectedTranscriptions.removeAll()
                }
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .buttonStyle(.plain)
                .foregroundStyle(Palette.ghost)
            } else {
                Button("SEL ALL") {
                    Task { await selectAllTranscriptions() }
                }
                .font(.system(size: 10, design: .monospaced).weight(.bold))
                .buttonStyle(.plain)
                .foregroundStyle(Palette.ghost)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .adaptableGlassBackground(intensity: .panel)
        .shadow(color: Color.black.opacity(0.1), radius: 3, y: -2)
    }
```

Note: `adaptableGlassBackground` is the existing modifier — keep as-is; do not change to `sottoBackground`.

Wait — the method is `.adaptiveGlassBackground` (not `.adaptableGlassBackground`). Fix that in Step 2: use `.adaptiveGlassBackground(intensity: .panel)`.

- [ ] **Step 3: Re-skin `emptyStateView`**

Replace `emptyStateView` (~lines 235–250):

```swift
    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Spacer()
            Text(searchText.isEmpty ? "NO TRANSCRIPTIONS YET" : "NO RESULTS")
                .font(.system(size: 13, design: .monospaced).weight(.bold))
                .tracking(0.16 * 13)
                .foregroundStyle(Palette.ghost)
            Text(searchText.isEmpty ? "history will appear here" : "try a different term")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ghost.opacity(0.6))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

- [ ] **Step 4: Lower `GlassCard` `cornerRadius` in `cardListView`**

In `cardListView` (~lines 254–302), change `GlassCard(cornerRadius: 14)` → `GlassCard(cornerRadius: 2)` (appears twice — for transcription rows and "Load More" row):

```swift
// Both occurrences:
// Old: GlassCard(cornerRadius: 14)
// New: GlassCard(cornerRadius: 2)
```

- [ ] **Step 5: Re-skin `HistoryCardRow` — timestamp + collapsed preview text**

In `HistoryCardRow.body` (~lines 517–555), update the `VStack` with timestamp + preview:

```swift
// Old:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        if !isExpanded {
                            Text(transcription.enhancedText ?? transcription.text)
                                .font(.system(size: 13))
                                .lineLimit(2)
                                .foregroundColor(.primary)
                        }
                    }

// New:
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transcription.timestamp, format: .dateTime.month(.abbreviated).day().hour().minute())
                            .font(.system(size: 10, design: .monospaced).weight(.bold))
                            .tracking(0.16 * 10)
                            .foregroundStyle(Palette.ghost)
                        if !isExpanded {
                            Text(transcription.enhancedText ?? transcription.text)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(2)
                                .foregroundStyle(.primary)
                        }
                    }
```

- [ ] **Step 6: Re-skin `expandedContent` — tab selectors + body text**

In `expandedContent` (~lines 559–616):

Tab buttons (lines ~563–583):
```swift
// Old: 
                            Text(tab.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(selectedTab == tab ? Color.secondary.opacity(0.15) : Color.clear)
                                )

// New:
                            Text(tab.rawValue.uppercased())
                                .font(.system(size: 10, design: .monospaced).weight(.bold))
                                .tracking(0.16 * 10)
                                .foregroundStyle(selectedTab == tab ? Palette.brandAcid : Palette.ghost)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(selectedTab == tab
                                              ? Palette.brandAcid.opacity(0.10)
                                              : Color.clear)
                                )
```

Body text (lines ~586–591):
```swift
// Old: 
                Text(displayText)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

// New:
                Text(displayText)
                    .font(.system(.body, design: .monospaced))
                    .tracking(0.02 * 14)   // +0.02em body tracking §1.3
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
```

- [ ] **Step 7: Re-skin info panel header in `infoPanelContent`**

In `infoPanelContent` (~lines 326–359), update the header:

```swift
// Old:
                Text("Info")
                    .font(.headline)
                    .fontWeight(.semibold)

// New:
                HStack(spacing: 4) {
                    Text("›")
                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.brandAcid)
                        .accessibilityHidden(true)
                    Text("INFO")
                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 11)
                        .foregroundStyle(Palette.ghost)
                }
```

And the close button (xmark):
```swift
// Old:
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(6)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Circle())

// New:
                    Text("✕")
                        .font(.system(size: 12, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.ghost)
                        .frame(width: 20, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white.opacity(0.06))
                        )
                        .accessibilityLabel("Close panel")
```

- [ ] **Step 8: Build — confirm no errors**

```bash
make local 2>&1 | tail -20
```
Expected: clean build.

- [ ] **Step 9: Commit**

```bash
git add VoiceInk/Views/History/InlineHistoryView.swift
git commit -m "feat(main-t4): history view SF Mono, brandAcid, cornerRadius 2pt, › section headers"
```

---

## Task 5: `SnippetsSettingsView` re-skin

Acceptance (§1): `brandAcid` tint on action button; `›` prefix on section label.

**Files:**
- Modify: `VoiceInk/Views/Snippets/SnippetsSettingsView.swift`

- [ ] **Step 1: Swap tint on "Add Snippet" button**

Line 73:
```swift
// Old:
                .tint(Palette.accent)
// New:
                .tint(Palette.brandAcid)
```

- [ ] **Step 2: Update button label to `▸` style**

Lines 67–70:
```swift
// Old:
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brandAcid)

// New:
                Button {
                    showingAddSheet = true
                } label: {
                    Text("▸ ADD SNIPPET")
                        .font(.system(size: 11, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.brandAcid)
```

- [ ] **Step 3: Build + commit**

```bash
make local 2>&1 | tail -5
git add VoiceInk/Views/Snippets/SnippetsSettingsView.swift
git commit -m "feat(main-t5): snippets brandAcid tint + ▸ button label"
```

---

## Task 6: `ScratchpadView` re-skin

Acceptance (§1): active tab uses `brandAcid`; tab text SF Mono; add `+` button is lime.

**Files:**
- Modify: `VoiceInk/Views/Scratchpad/ScratchpadView.swift`

- [ ] **Step 1: Re-skin `tabCell`**

Replace `tabCell` function (~lines 58–89):

```swift
    private func tabCell(_ doc: ScratchpadDocument) -> some View {
        let isActive = doc.id == store.activeTabId
        return HStack(spacing: 5) {
            Text(doc.title.isEmpty ? "UNTITLED" : doc.title.uppercased())
                .font(.system(size: 10, design: .monospaced).weight(isActive ? .bold : .regular))
                .tracking(0.16 * 10)
                .foregroundStyle(isActive ? Palette.brandAcid : Palette.ghost)
                .lineLimit(1)
            Button(action: { store.closeTab(doc) }) {
                Text("✕")
                    .font(.system(size: 8, design: .monospaced).weight(.bold))
                    .foregroundStyle(Palette.ghost.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close tab \(doc.title.isEmpty ? "Untitled" : doc.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isActive ? Palette.brandAcid.opacity(0.12) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(isActive ? Palette.brandAcid.opacity(0.35) : Palette.hairlineSoft, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let prev = activeDocument, prev.id != doc.id {
                store.captureVersion(prev, force: true)
            }
            store.activeTabId = doc.id
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(doc.title.isEmpty ? "Untitled tab" : doc.title)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
```

- [ ] **Step 2: Re-skin `addTabButton`**

Replace `addTabButton` computed property (~lines 91–100):

```swift
    private var addTabButton: some View {
        Button(action: { _ = store.createTab() }) {
            Text("+")
                .font(.system(size: 12, design: .monospaced).weight(.bold))
                .foregroundStyle(store.documents.count >= ScratchpadStore.maxTabs
                                 ? Palette.ghost.opacity(0.3)
                                 : Palette.brandAcid)
                .frame(width: 22, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(store.documents.count >= ScratchpadStore.maxTabs)
        .accessibilityLabel("New tab")
    }
```

- [ ] **Step 3: Re-skin `emptyState`**

Replace `emptyState` computed property (~lines 33–42):

```swift
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("NO TABS")
                .font(.system(size: 13, design: .monospaced).weight(.bold))
                .tracking(0.16 * 13)
                .foregroundStyle(Palette.ghost)
            Text("⌘T to create one")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.ghost.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
```

- [ ] **Step 4: Build + commit**

```bash
make local 2>&1 | tail -5
git add VoiceInk/Views/Scratchpad/ScratchpadView.swift
git commit -m "feat(main-t6): scratchpad tab strip SF Mono + brandAcid active state"
```

---

## Task 7: `DictionarySettingsView` + Accessibility pass

Acceptance (§1): `SectionCard` uses `brandAcid`; SF Mono text; VoiceOver labels on key interactive elements; Reduce Motion guards added where animations exist; HC already handled by `AdaptiveGlass` in `HaloMaterial`.

**Files:**
- Modify: `VoiceInk/Views/Dictionary/DictionarySettingsView.swift`
- Modify: `VoiceInk/Views/History/InlineHistoryView.swift` (Reduce Motion guard)
- Modify: `VoiceInk/Views/Metrics/MetricsContent.swift` (Reduce Motion guard)

### DictionarySettingsView.swift

- [ ] **Step 1: Re-skin `SectionCard` body**

Replace `SectionCard.body` (~lines 127–165):

```swift
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Palette.brandAcid.opacity(isSelected ? 0.18 : 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(Palette.brandAcid.opacity(isSelected ? 0.40 : 0.16), lineWidth: 0.5)
                    )
                    .overlay(
                        Image(systemName: section.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(Palette.brandAcid)
                    )
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 3) {
                    Text(section.rawValue.uppercased())
                        .font(.system(size: 12, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 12)
                        .foregroundStyle(isSelected ? Palette.brandAcid : .primary)

                    Text(section.description)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.ghost)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .modifier(GlassChip(cornerRadius: 4, paddingH: 0, paddingV: 0))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Palette.brandAcid.opacity(isSelected ? 0.5 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.rawValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
```

- [ ] **Step 2: Re-skin `sectionSelector` heading + settings button**

In `sectionSelector` (~lines 70–100), update:

```swift
// Old:
            HStack {
                Text("Select Section")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button { ... } label: {
                    Image(systemName: "gear")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isShowingSettings ? .accentColor : .secondary)
                }
            }

// New:
            HStack {
                HStack(spacing: 4) {
                    Text("›")
                        .font(.system(size: 12, design: .monospaced).weight(.bold))
                        .foregroundStyle(Palette.brandAcid)
                        .accessibilityHidden(true)
                    Text("SELECT SECTION")
                        .font(.system(size: 12, design: .monospaced).weight(.bold))
                        .tracking(0.16 * 12)
                        .foregroundStyle(Palette.ghost)
                }
                Spacer()
                Button {
                    withAnimation(Animation.haloExpand) {
                        isShowingSettings.toggle()
                    }
                } label: {
                    Text("⚙")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundStyle(isShowingSettings ? Palette.brandAcid : Palette.ghost)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dictionary settings")
                .help("Dictionary settings")
            }
```

### Accessibility guards

- [ ] **Step 3: Add Reduce Motion guard to `MetricsContent` loading animation**

In `MetricsContent.body` where `ProgressView("Loading metrics...")` is shown (~line 23), it has no looping animation we control — skip.

In the `footerActionsView` button's `withAnimation(.smooth(duration: 0.3))` — these are one-shot transitions, not loops. No Reduce Motion guard needed per spec (only "multi-second loops" require fallbacks per §1.X).

For `CopySystemInfoButton` in MetricsContent (~lines 338–374), the `.rotationEffect` + `.scaleEffect` are tied to `isCopied` one-shot. Not a loop. No guard needed.

- [ ] **Step 4: Add Reduce Motion guard to `InlineHistoryView` expand animation**

In `InlineHistoryView`, the expand/collapse animation `Animation.haloPhaseCrossfade` is a brief transition — not a loop. No guard needed.

The `slidePanel` / `isPanelPresented` slide-in uses `Animation.haloExpand` — one-shot, not looping. No guard needed.

*Note: MAIN surfaces contain no multi-second looping animations. All motion is one-shot transitions. Reduce Motion loops in MAIN are therefore all compliant. HUD pair owns the multi-second loops (recording pulse, breathe, sweep, blink) and their Reduce Motion fallbacks.*

- [ ] **Step 5: VoiceOver audit — `HistoryCardRow` row actions**

In `HistoryCardRow.body`, the `.contentShape(Rectangle()).onTapGesture { onToggleExpand() }` HStack needs a label. Add at the end of the row's `HStack`:

```swift
// After the .contentShape(Rectangle()) line, add:
        .accessibilityLabel(
            (transcription.enhancedText ?? transcription.text)
                .prefix(80) + " — tap to expand"
        )
        .accessibilityHint("Double-tap to expand or collapse transcription")
```

The `onShowInfo` button (if no audio file, ~line 606):
```swift
                    Button(action: onShowInfo) {
                        Image(systemName: "info.circle")
                            ...
                    }
                    .accessibilityLabel("Show transcription info")
```
This is already present as `.help("View details")`. Add `.accessibilityLabel("View details")` as well.

- [ ] **Step 6: Build — confirm no errors**

```bash
make local 2>&1 | tail -20
```
Expected: clean build.

- [ ] **Step 7: Final build + smoke launch**

```bash
make reload 2>&1 | tail -20
```
Expected: app launches, main window shows Sotto wordmark, lime sidebar `›` prompts, SF Mono text throughout, brandAcid accents on tiles and active row, wallpaper bleed gradient visible.

- [ ] **Step 8: Commit**

```bash
git add VoiceInk/Views/Dictionary/DictionarySettingsView.swift \
        VoiceInk/Views/History/InlineHistoryView.swift \
        VoiceInk/Views/Metrics/MetricsContent.swift
git commit -m "feat(main-t7): dictionary brandAcid SectionCard, SF Mono; a11y VoiceOver labels"
```

---

## Spec Coverage Checklist

Mapped against §1 acceptance criteria:

| Criterion | Task | Notes |
|---|---|---|
| All glass → `TacticalGlass` (wraps `HaloMaterial`) | T3, T4 | Hero section + tiles; `GlassCard` already routes through `HaloMaterial` for other surfaces |
| SF Mono text throughout | T2–T7 | All modified views |
| Uppercase labels track +0.16em | T2–T7 | All uppercase labels get `.tracking(0.16 * size)` |
| Sidebar rows use `›`; chips/buttons use `▸` | T2 | Sidebar gets `›`; action buttons get `▸` |
| No `cornerRadius > 8pt` | T3, T4 | `GlassCard(cornerRadius: 2)`, tiles 0–2pt |
| No inner highlights (only `HaloMaterial` prescribed) | All | Not adding any new gradient highlights |
| All color uses §1.4 tokens | T1–T7 | `brandAcid`, `ghost`, `hairline` |
| Tangerine `Palette.accent` retired (MAIN surfaces) | T1–T7 | All `Palette.accent` refs in MAIN files → `Palette.brandAcid` |
| Reduce Motion fallback for every multi-second loop | T7 | MAIN has no loops; confirmed |
| Committed `✓` + fail `✗` glyphs (shape-based) | HUD pair | Out of MAIN scope |
| VoiceOver labels | T2, T4, T7 | SidebarItemView, MetricCard, HistoryCardRow |
| HC via `AdaptiveGlass` | Inherited | `GlassCard` → `HaloMaterial` → `AdaptiveGlass` — already shipping |
| Wallpaper bleed-through under root | T2 | `sottoBackground` on `NavigationSplitView` |

---

## Open Questions

1. **`Palette.brandAcid` conflict at merge** — if HUD lands `brandAcid` before MAIN, the Task 1 stub will create a duplicate definition. Plan: MAIN coder adds `// MAIN stub — remove if HUD has landed` comment; reviewer confirms at PR time.
2. **`ScratchpadTabEditor` typography** — plan does not touch `ScratchpadTabEditor.swift`. The editor `TextEditor` text is user content and MAY stay in SF Pro per §1.3 ("User-typed prose (notes textareas) MAY use SF Pro inside the field"). Confirm at review.
3. **`SettingsCard` + `SettingsRow` shared components** — used in `SnippetsSettingsView` and others. Not re-skinned here since they're shared. If those components need SF Mono / brandAcid, it should be a separate task coordinated with SETTINGS pair to avoid conflicts.
4. **`CompactHeroSection` in `DictionarySettingsView`** — shared component, not re-skinned in this plan. Coordinate with SETTINGS pair.
