# Aesthetic Gap Audit — Main app vs floating bar

**Date:** 2026-04-29
**Author:** researcher-aesthetic (W11 deep-research, team `w11-deep-research`, task R4)
**User feedback (verbatim):** *"the aesthetic of the whole app is still shitty it does not share the aesthetic of the floating status bars"*
**Scope:** Read-only audit. No code edits. Goal: locate divergences from the floating-recorder vocabulary so the W13 packet can fix them.

---

## 1. TL;DR — top 5 cohesion offenders + highest-leverage fix

Ranked by perceived breakage of vocabulary. Each fix is one short edit, not a rewrite.

| # | Surface | One highest-leverage fix |
|---|---|---|
| **1** | **Metrics / Dashboard** (`MetricsContent.heroSection` `:179-188` + `MetricCard.swift:46-49` + `HelpAndResourcesSection:39-46`) | Replace the controlAccentColor hero gradient + `.thinMaterial` cards + windowBackgroundColor card with `GlassCard`. Today this is the first surface a new user sees and the only one that lives in raw Apple-system blue, breaking the orange-accent-on-onyx-glass language for the whole app. |
| **2** | **Permissions** (`PermissionsView.PermissionCard.swift:188-201`) | The card hand-rolls `ultraThinMaterial + obsidian fill + hairline overlay` and a 14pt radius — exactly the spec's chip vocabulary, just inlined. Swap to the `GlassCard(cornerRadius: 14)` primitive (or `glassPanel()` modifier). One change unifies four cards. |
| **3** | **Enhancement settings** (`EnhancementSettingsView.swift:52-159`) | Still a `Form { Section { } }` host — the v1 layout SettingsView abandoned at W5 per `SettingsCard.swift:21-23` doc. Result: section headers wear `SettingsSectionHeader` but the rows are macOS Form chrome (light grouped boxes), not glass cards. Move to `ScrollView { LazyVStack { SettingsCard } }` like `SettingsView.swift:51-71` — same body, no Form. |
| **4** | **AI Models cards** (`WhisperModelCardView.swift:36-49`, `CloudModelCardView.swift:63-76`, `FluidAudioModelCardView.swift:48-60`, `MLXModelPickerView.swift:78-90`) | Use `HaloMaterial(phase: .hidden)` directly with hardcoded `Color.accentColor` / `Color.white.opacity(0.08)` strokes — not `GlassCard`, not `Palette.accent`, not `Palette.hairline`. Replace with `GlassCard(cornerRadius: 16)` and use `Palette.accent` / `Palette.hairline`. Four cards collapse into one vocabulary. |
| **5** | **History — TranscriptionHistoryView (separate window)** (`TranscriptionHistoryView.swift` + `HistoryWindowController.swift:54`) | The History window's `NSWindow.backgroundColor = NSColor.windowBackgroundColor` and `isOpaque` defaults to `true`. So the W8 `.adaptiveGlassBackground` contract (window must be `isOpaque=false` + `.clear`) does not hold. Spec §1.X explicitly tracks this as W8 follow-up but it has not been done. Mirror `WindowManager.configureWindow:36-41`'s flags in `HistoryWindowController.createHistoryWindow:32-65`. The right-sidebar empty state at `:321` and the analysis panel at `:133, :392` then need to drop their hardcoded `Color(NSColor.windowBackgroundColor)` calls. |

---

## 2. Floating-bar vocabulary spec (captured)

Source-of-truth tokens, with citations. Every value below is a fixed point we audit divergence against. None of it is being made up — it is what the floating recorder + `Glass*` primitives express.

### 2.1 Material (recorder cluster + GlassChip)

| Layer | Onyx variant | Light variant | Citation |
|---|---|---|---|
| Backdrop | `NSVisualEffectView .hudWindow / .behindWindow / .darkAqua` (or `.aqua`) — opens to wallpaper | same, `.aqua` | `HaloMaterial.swift:130-134` |
| Fill | `Color.black.opacity(0.78)` | `Color.white.opacity(0.32)` | `HaloMaterial.swift:221-226` |
| Inner top gloss | 1.5pt linear `white α 0.30 → 0` | 1.5pt linear `white α 0.70 → α 0.18` | `HaloMaterial.swift:228-235` |
| Inner stroke | 0.5pt `white α 0.16` | 0.5pt `white α 0.55` | `HaloMaterial.swift:237-242` |
| Bottom inner stroke | 0.5pt `white α 0.05` | 0.5pt `white α 0.18` | `HaloMaterial.swift:244-249` |
| Drop shadow | 14px / `(0, 6)` / `black α 0.45` | 24px / `(0, 8)` / `black α 0.18` | `HaloMaterial.swift:251-269` |
| Halo glow | state-keyed, 24px blur, alpha from `Palette.HaloIntensity` (.soft 0.18 / .medium 0.22 / .strong 0.28) | same | `HaloMaterial.swift:201-208`, `Palette.swift:65-78` |

`GlassChip` re-exposes the same vocabulary at chip scale: 28pt backdrop blur, `rgba(20,20,28, 0.55)` fill, `Palette.hairline` (`white α 0.16`) border, `Palette.innerHi` (`white α 0.22`) top-edge sheen, `(0, 14, 36)` `black α 0.55` shadow, **10pt corner radius** for chips, **14pt for panels** (`GlassChip.swift:23-75`).

`AdaptiveGlassBackground` is the pane-scale derivative — `.fullScreenUI / .behindWindow`, two intensities (`.pane` 0.42 / 0.18 alpha; `.panel` 0.52 / 0.26), full-bleed Rectangle (`AdaptiveGlassBackground.swift:48-86`).

### 2.2 Geometry tokens

- **Chip radius:** 10pt. Spec: "chips" (`GlassChip.swift:64-68`, spec §1).
- **Panel/card radius:** 14pt. (`GlassChip.swift:71-74`, spec §1).
- **GlassCard radius default:** 16pt (`GlassCard.swift:20`). Slight stretch over the 14pt spec — but it's the chrome's own decision and should be the upper limit anywhere.
- **NEVER 999pt pills** (spec §1, line 41). Capsules stay tight: chip status pills, switches.
- **Padding rhythm:** chip `11×7`, panel `14×12` (`GlassChip.swift:25-27, 71-74`); GlassCard `14` default (`GlassCard.swift:21`); SettingsCard `18` (`SettingsCard.swift:36`); MetricsContent ScrollView `28v / 32h` (`MetricsContent.swift:38-39`).

### 2.3 Color / palette

- **Live-state accent:** `Palette.accent = #FF5B3A` (tangerine). Single accent for recording / transcribing / enhancing / failed; motion is the discriminator (`Palette.swift:32-36`, spec §4). Forbidden: `Palette.recording`, `Palette.transcribe`, `Palette.enhance` (already retired, spec §1).
- **Onyx text:** `Palette.onyxFg #EDEDF0`, `Palette.onyxMute #8A8A93` (`Palette.swift:48-53`).
- **Glass borders:** `Palette.hairline` `white α 0.16`; `Palette.hairlineSoft` `white α 0.10` (`Palette.swift:55-59`).
- **Inner highlight:** `Palette.innerHi` `white α 0.22` (`Palette.swift:61-63`).
- **Section icon palette:** spec §2.5 keys icon backgrounds to functional tokens (Recording → mic.fill on `recording`, Shortcuts → command on `enhance`, Privacy → `lock.fill` on `success`, etc.). After W1 retirement of `recording/transcribe/enhance`, `Palette.accent` now plays all roles via `SettingsRow.iconTint:` parameter (`SettingsRow.swift:21-27`). Used as such in `SettingsView` (Shortcuts / Recording Feedback / Interface use `Palette.accent`; Privacy uses `Palette.success`; Power Mode `Palette.warn`; Diagnostics `Palette.warn`).

### 2.4 Type

- **Body / prose:** `-apple-system` (default `.system`), regular 13pt. (Spec §1.)
- **Display tier:** `.system(.body)` semibold; section header 14pt semibold (`SettingsSectionHeader.swift:46-48`).
- **Mono identity for state labels and keys:** `.system(size: ~9.5–11, weight: .semibold, design: .monospaced).tracking(0.06 * size)` (uppercase, see `MLXModelPickerView` `:65-70, 97-127`, `SettingsSectionHeader.swift:60-63`).
- **No `.rounded` outside designated places** (spec §5#9, W7 packet).
- **Recorder text colors (onyx context):** `.white` and `.white.opacity(0.6/0.7/0.8)` for hierarchy (`RecorderComponents.swift:37-39, 274-277`; `EnhancementPromptPopover.swift:81-86`).

### 2.5 Motion grammar (locked, `Animation+Halo.swift`)

| Token | Value | Use |
|---|---|---|
| `.haloExpand` | `spring(0.38, 0.78)` | expand, reveal, morph-up |
| `.haloCollapse` | `spring(0.42, 1.00)` | contract, dismiss, morph-down |
| `.haloBreathe` | `easeInOut(1.6).repeatForever` | enhancing breath |
| `.haloPhaseCrossfade` | `easeInOut(0.22)` + opacity + scale 0.96→1.0 | phase swaps |
| `Reduce-Motion fallback` | 0.18s opacity, no scale | accessibility |
| `HaloPulse` | scale 1.0↔1.18 over 1.0s | recording dot |
| `HaloBreathOrb` | scale 1.0↔1.15 over 1.6s | enhancing dot |
| `HaloShake` | x-offset {-6,6,-4,4,-2,0} over 0.32s | failure |
| `HaloShimmer` | 1.6s `TimelineView` phase | transcribing |

**Reviewer note** (`Animation+Halo.swift:14-17`): "Every numeric in this file is a spec constant. Call sites must not hand-roll their own `easeInOut(duration:)` / scale / offset values."

### 2.6 Iconography

- **SF Symbols only**, no custom (spec §2.5).
- **Sizing in chips:** 10–14pt. Recorder buttons use 13pt (`RecorderComponents.swift:36, 38`).
- **Section icon tile:** rounded 7pt rectangle, 28×28pt, `accent.opacity(0.16)` fill, `accent.opacity(0.32)` stroke 0.5pt (`SettingsSectionHeader.swift:32-43`). Row icon tile is the same vocabulary at 16×16pt / 6pt rad / 0.16 fill (`SettingsRow.swift:54-68`).

### 2.7 Density

The recorder cluster is dense, tight, monospaced. Floating chips are ~11pt vertical / ~22pt height. Glass cards are ~14pt padding. Compare to a settings row that's 13pt label + 11pt subtitle in a 12pt-spaced VStack — same density.

What it does NOT look like: 28pt bold rounded headers, 16pt body, multi-line description blocks, 240pt-wide adaptive grids. (Those exist in MetricsView and they read disconnected.)

---

## 3. Per-surface audit

Score per axis 1 (identical to recorder vocab) – 5 (wildly off-brand). Sum is rough cohesion penalty.

| # | Surface | File:line | Material | Radius | Padding | Motion | Type/icon | Density | **Σ** | Top divergence | Concrete fix |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **MetricsView dashboard hero** | `Metrics/MetricsContent.swift:144-188` | 5 | 4 | 4 | 5 | 5 | 4 | **27** | Hand-rolled `RoundedRectangle 24pt + LinearGradient(controlAccentColor)` — system-blue, no glass, no `Palette.accent`, animated with `spring(0.3, 0.7)` not haloExpand | Wrap title text in `GlassCard(cornerRadius: 16, padding: 28)` + `Palette.accent` for the time-saved colorant; drop the gradient or restrict it to a tangerine `Palette.accent → accentMuted` variant (`MetricsContent.swift:179-188, 248-258`) |
| 2 | **MetricsView MetricCard grid** | `Metrics/MetricCard.swift:46-49` | 5 | 1 | 2 | 1 | 4 | 3 | **16** | Raw `.thinMaterial` background — no NSVisualEffectView behindWindow, no hairline border, no inner gloss, no shadow. Per-card icon tint `Color.purple/.yellow/.orange` is rainbow-palette retired in spec §1 | Replace `RoundedRectangle 16pt + .thinMaterial` with `GlassCard(cornerRadius: 16, padding: 16)`; remap rainbow `color` argument call sites at `MetricsContent.swift:198, 205, 215, 223` to `Palette.accent` / `Palette.success` / `Palette.neutral` |
| 3 | **MetricsView Help section** | `Metrics/HelpAndResourcesSection.swift:39-46` | 4 | 5 | 3 | 1 | 3 | 3 | **19** | Card uses `Color(nsColor: .windowBackgroundColor)` (opaque), `28pt` radius (forbidden — spec caps at 14–16), `Color.primary.opacity(0.1)` border instead of `Palette.hairline`. Inner link rows use `Color.primary.opacity(0.05)` + 12pt radius | Swap outer `RoundedRectangle 28pt` → `GlassCard(cornerRadius: 16)`; use `Palette.hairline` border; inner rows already 12pt — bring to 10pt to match chip vocab |
| 4 | **MetricsView footer button** | `Metrics/MetricsContent.swift:332` | 4 | 1 | 1 | 2 | 2 | 1 | **11** | Bare `Capsule().fill(.thinMaterial)` instead of `glassChip()` modifier; copy-confirm spring is `spring(0.3, 0.7)` not `haloExpand` (`MetricsContent.swift:324-336`) | Apply `.glassChip()`; replace springs with `Animation.haloExpand` |
| 5 | **PermissionsView card** | `PermissionsView.swift:188-203` | 2 | 2 | 1 | 3 | 2 | 2 | **12** | Manually re-implements glass-chip vocabulary inline (28pt blur via `.ultraThinMaterial` + 0.078/0.078/0.110@0.28 fill + `Palette.hairline` 14pt) — exactly `glassPanel()` | Replace background+overlay+clip stack with `.modifier(GlassChip(cornerRadius: 14, paddingH: 0, paddingV: 0))` or `glassPanel()` |
| 6 | **PermissionsView CTA button** | `PermissionsView.swift:163-186` | 3 | 2 | 1 | 1 | 2 | 1 | **10** | Solid `Palette.accent` `RoundedRectangle 10pt` + white text — fine palette token but no glass treatment / no `accentMuted` baseline. Reads as iOS button against the glass card | Wrap as `glassChip(cornerRadius: 10)` with `Palette.accentMuted` fill + `Palette.accent` foreground; or accept solid-fill exception and document |
| 7 | **PermissionsView icon tile** | `PermissionsView.swift:101-114` | 2 | 1 | 1 | 1 | 2 | 1 | **8** | 10pt radius / 0.18 fill / 0.36 stroke 0.5pt — close to spec but spec calls 7pt/0.16/0.32 (`SettingsSectionHeader.swift:32-37`). Drift, not divergence | Realign to `SettingsSectionHeader` icon-tile constants for symmetry |
| 8 | **PermissionsView CompactHeroSection** | `Common/CompactHeroSection.swift:13` | 1 | 1 | 1 | 1 | **5** | 1 | **10** | Icon hardcoded `.foregroundStyle(.blue)` — directly violates spec §1 (rainbow palette retirement) | One-line edit: `.foregroundStyle(Palette.accent)` (used by Permissions, AudioInputSettings, DictionarySettings) |
| 9 | **EnhancementSettingsView host** | `EnhancementSettingsView.swift:52-159` | 4 | — | 3 | 4 | 3 | 4 | **18** | Uses `Form { Section { } header: { SettingsSectionHeader } }` with `.formStyle(.grouped) + .scrollContentBackground(.hidden)`. Sections render macOS-grouped chrome — no glass card silhouette, no spacing rhythm, no rounded SettingsCard. SettingsView at W5 explicitly abandoned this | Migrate to `ScrollView { LazyVStack(spacing: 16) { SettingsCard {...} } }` mirroring `SettingsView.swift:51-71` |
| 10 | **EnhancementSettingsView header buttons** | `EnhancementSettingsView.swift:80-95, 130-150` | 2 | 2 | 1 | 3 | 2 | 1 | **11** | Inline `.ultraThinMaterial` 8pt-radius + `Palette.hairline` 1pt — close but not `glassChip` modifier; smooth(0.3) animation not `haloExpand` | Apply `.glassChip(cornerRadius: 8)` and `Animation.haloExpand` |
| 11 | **AI Models — ModelManagementView filter pills** | `AI Models/ModelManagementView.swift:128-167` | 1 | 1 | 1 | 2 | 1 | 1 | **7** | Already uses `GlassChip` modifier + `Palette.accent` selected stroke. Animation `spring(0.3, 0.8)` instead of `haloExpand` | One-line: `.spring(response: 0.3, dampingFraction: 0.8)` → `Animation.haloExpand` |
| 12 | **AI Models — Default Model section** | `AI Models/ModelManagementView.swift:105-118` | 1 | 1 | 2 | 1 | 1 | 2 | **8** | Subtitle "Default Model" `.headline` + body `.title2.bold` is too large vs the rest of the app's section-header rhythm | Replace `.headline / .title2` with `SettingsSectionHeader` |
| 13 | **AI Models — WhisperModelCardView** | `AI Models/WhisperModelCardView.swift:36-49` | 1 | 1 | 1 | — | 4 | 2 | **9** | Uses `HaloMaterial(phase: .hidden)` directly — bypasses GlassCard. Border `Color.accentColor.opacity(0.45)` / `Color.white.opacity(0.08)` — should be `Palette.accent` / `Palette.hairline`. Same pattern in CloudModelCardView, FluidAudioModelCardView, NativeAppleModelCardView | Replace material+overlay stack with `GlassCard(cornerRadius: 16) { ... }`; recolor strokes to `Palette.accent`/`Palette.hairline` (`WhisperModelCardView.swift:36-49`, `CloudModelCardView.swift:63-76`, `FluidAudioModelCardView.swift:48-60`) |
| 14 | **AI Models — MLXModelPickerView row** | `AI Models/MLXModelPickerView.swift:78-90` | 2 | 2 | 1 | 1 | 1 | 1 | **8** | Same as #13 — `RoundedRectangle 14pt + .ultraThinMaterial` instead of `glassPanel()` modifier | Wrap row content in `.modifier(GlassChip(cornerRadius: 14, ...))` |
| 15 | **History detail (InlineHistoryView)** | `History/InlineHistoryView.swift:69-148, 254-301` | 3 | 3 | 2 | 4 | 2 | 3 | **17** | Top bar at `:152-172` uses `Capsule().fill(Color.secondary.opacity(0.08))` for search — not glassChip. Card list `:254-301` uses `Form { Section } .formStyle(.grouped)` instead of `LazyVStack { GlassCard }`. Selection bar at `:174-231` uses `.adaptiveGlassBackground(intensity: .panel)` correctly | Replace search capsule with `glassChip(cornerRadius: 10)` containing the field; replace cardListView Form with `LazyVStack(spacing: 12) { GlassCard { HistoryCardRow } }` |
| 16 | **History (separate window) — TranscriptionHistoryView** | `History/TranscriptionHistoryView.swift:175-322`, `HistoryWindowController.swift:32-65` | 5 | 4 | 3 | 3 | 2 | 3 | **20** | Window itself opaque (`HistoryWindowController.swift:54`) — W8 wallpaper-glass pipeline broken. Center pane "No Selection" wraps `HaloMaterial(shape: Rectangle())` with `.windowBackgroundColor` (`:295-301`). Right sidebar empty state `.controlBackgroundColor` (`:321`). Selection toolbar `:392` `.windowBackgroundColor`. Search at `:184` `.thinMaterial` not glassChip. Analysis panel at `:133` `.windowBackgroundColor` | (a) Mirror WindowManager.configureWindow flags in HistoryWindowController.createHistoryWindow; (b) replace all `Color(NSColor.windowBackgroundColor / .controlBackgroundColor)` with `.adaptiveGlassBackground()`; (c) search field → `glassChip` |
| 17 | **AudioTranscribeView empty state** | `AudioTranscribeView.swift:50-94` | 4 | 3 | 1 | 4 | 2 | 2 | **16** | Drop zone uses `Color(.windowBackgroundColor).opacity(0.4)` + dashed system-accent border + 12pt radius. Borrow from glass vocab — should be `glassPanel(cornerRadius: 14)` + `Palette.accent` dash. Buttons `Color.secondary.opacity(0.12)` Capsule everywhere | Swap drop-zone background to `glassPanel(cornerRadius: 14)`; recolor border with `Palette.accent` when targeted; topBar buttons → `glassChip()` |
| 18 | **AudioTranscribeView queue** | `AudioTranscribeView.swift:98-141` | 4 | — | 3 | 3 | 2 | 4 | **16** | `Form { Section { AudioFileRow } }.formStyle(.grouped).scrollContentBackground(.hidden)` — same Form-chrome divergence as Enhancement settings | Migrate to LazyVStack of GlassCards (matches W5 pattern) |
| 19 | **AudioInputSettingsView** | `Settings/AudioInputSettingsView.swift:1-460` | 1 | 1 | 1 | 1 | 2 | 2 | **8** | Already uses GlassChip everywhere; CompactHeroSection icon is `.blue` (#8); `.title2.fontWeight(.semibold)` section labels are heavier than spec §3.3 — but consistent across the page | Fix CompactHeroSection blue (#8); align headers with `SettingsSectionHeader` |
| 20 | **DictionarySettingsView** | `Dictionary/DictionarySettingsView.swift:1-165` | 1 | 1 | 1 | 1 | 2 | 2 | **8** | Same as AudioInput — uses GlassChip + Palette.accent. CompactHeroSection blue (#8). Section labels `.title2` heavy | Same as #19 |
| 21 | **PromptEditorView host** | `PromptEditorView.swift:72-220` | 1 | 1 | 1 | 1 | 1 | 2 | **7** | Uses `.adaptiveGlassBackground(intensity: .panel)`, GlassCard, hairlines. Close button etc. use `.ultraThinMaterial` 8pt — could be `glassChip` | Tiny: replace `RoundedRectangle 8pt + .ultraThinMaterial` with `glassChip(cornerRadius: 8)` |
| 22 | **PromptEditorView — Form panes** | `PromptEditorView.swift:223-366` | 4 | — | 2 | 1 | 2 | 3 | **12** | Inside the editor pane, content is still `Form { Section { TextEditor } }.formStyle(.grouped).scrollContentBackground(.hidden)`. Functional but visually heavy | Migrate to flat VStack with custom labeled rows or accept inside the panel context |
| 23 | **PromptEditorView trigger word chips** | `PromptEditorView.swift:471-478` | 3 | 5 | 1 | 1 | 1 | 1 | **12** | `.background(.ultraThinMaterial).cornerRadius(4)` — 4pt radius below spec's 10pt minimum, no hairline | `.glassChip(cornerRadius: 10)` |
| 24 | **PromptEditorView icon tile** | `PromptEditorView.swift:281-292` | 2 | 1 | 1 | 1 | 1 | 1 | **7** | `.ultraThinMaterial` 10pt + `Color.secondary.opacity(0.2)` 1pt — uses system-secondary not `Palette.hairline` | Recolor stroke to `Palette.hairline` |
| 25 | **PredefinedPromptsView template buttons** | `PredefinedPromptsView.swift:67-89` | 5 | 1 | 1 | 1 | 4 | 2 | **14** | Card background `Color(NSColor.controlBackgroundColor)` (opaque), `Color(NSColor.separatorColor)` gradient stroke, `Color(NSColor.shadowColor)` shadow. Icon container `unemphasizedSelectedTextBackgroundColor`. Zero glass | Replace whole card with `GlassCard(cornerRadius: 16)`; recolor icon BG to `Palette.accent.opacity(0.16)` per `SettingsSectionHeader` |
| 26 | **PromptChipPicker / EnhancementSettingsPanel** | `Common/PromptChipPicker.swift`, `Components/EnhancementSettingsPanel.swift:1-300` | 2 | 1 | 1 | 3 | 1 | 2 | **10** | Header uses `.adaptiveGlassBackground(intensity: .panel)` (good); body is `Form { Section } .formStyle(.grouped) .scrollContentBackground(.hidden)` (W5 pattern bypassed); close button is `ultraThinMaterial` 8pt as elsewhere | Lift Form to LazyVStack/SettingsCard pattern; close button → `.glassChip(cornerRadius: 8)` |
| 27 | **EnhancementPromptPopover (recorder satellite)** | `Recorder/EnhancementPromptPopover.swift:50-66` | 2 | 2 | 1 | 1 | 1 | 1 | **8** | `.ultraThinMaterial 12pt + Palette.hairline` — close to chip vocab but uses 12pt radius (not 10pt chip / 14pt panel) and `.environment(\.colorScheme, .dark)` is hardcoded — won't track GlassAppearanceDetector | Replace background with `glassPanel(cornerRadius: 14)`; remove forced dark colorScheme so it follows the recorder's onyx/light variant |
| 28 | **PowerModeView** | `PowerMode/PowerModeView.swift:84-207` | 1 | 1 | 1 | 1 | 2 | 1 | **7** | Hero header text is plain — `.system(28, .bold)` not `SettingsSectionHeader`; other surfaces are spec-compliant | Use `SettingsSectionHeader(icon: "bolt.fill", title: "Power Modes", accent: Palette.warn)` |
| 29 | **ContentView sidebar** | `Views/ContentView.swift:77-130` | 2 | 1 | 1 | 1 | 2 | 2 | **9** | Uses `.listStyle(.sidebar)` (system) so divergence is bounded by NSOutlineView chrome. Sidebar header at `:81-95` is plain HStack — no glass treatment. `.tint(Palette.accent)` is correct | Could keep system sidebar; if cohesion is critical, wrap header row in a `glassChip(cornerRadius: 10)` |
| 30 | **InlineHistoryView search bar** | `History/InlineHistoryView.swift:152-172` | 4 | 2 | 1 | 1 | 1 | 2 | **11** | `Capsule().fill(Color.secondary.opacity(0.08))` — not glass | `.glassChip(cornerRadius: 999)` (use Capsule shape) — or `GlassChip(cornerRadius: 16)` |
| 31 | **MenuBarView dropdown** | `Views/MenuBarView.swift:32-148` | — | — | — | — | — | — | **OOS** | Uses `MenuBarExtra(...).menuBarExtraStyle(.menu)` — system NSMenu, not skinnable. Spec §1.X line 73 marks this out-of-scope | No-op (or open question — see §5) |
| 32 | **AppNotificationView (HUD)** | `Notifications/AppNotificationView.swift:39-80` | 3 | 2 | 2 | 1 | 4 | 2 | **14** | Already on HUD glass; rainbow per-type icon colors `.red/.yellow/.blue/.green`; CTA uses `type.iconColor.opacity(0.15)` 6pt rad | Recolor to single `Palette.accent` for `.error/.warning`, `Palette.success` for `.success`, `Palette.neutral` for `.info`; CTA → `glassChip(cornerRadius: 10)` with same accent |
| 33 | **AddCustomModelView / EnhancementShortcutsView etc.** | `AI Models/AddCustomModelView.swift:157`, `Settings/EnhancementShortcutsView.swift:61`, `Dictionary/VocabularyView.swift:173`, `Dictionary/DictionaryQuickAddPanel.swift:367`, `Common/CopyIconButton.swift:13`, `Common/SaveIconButton.swift:21`, `Metrics/MetricsSetupView.swift:62`, `Metrics/PerformanceAnalysisView.swift:159, 432`, `History/HistoryShortcutTipView.swift:40`, `Settings/AudioInputSettingsView.swift:426` | 3 | — | — | — | — | — | **—** | Mass usage of opaque `Color(NSColor.controlBackgroundColor / .windowBackgroundColor)` as fills/borders — bypasses the W8 glass pipeline | Audit each: drop window-background overlays where the W8 backdrop already paints; or wrap content in `glassChip` / `glassPanel` |

### 3.1 Patterns of divergence (summary)

| Anti-pattern | Hit count | Why it hurts |
|---|---|---|
| Raw `RoundedRectangle.fill(.thinMaterial / .ultraThinMaterial)` | ~14 sites | Bypasses HaloMaterial layered stack — no inner-stroke / inner-gloss / drop-shadow vocabulary, no NSVisualEffectView behindWindow, no adaptive onyx/light variant |
| Hand-rolled glass (`ultraThinMaterial + obsidian fill + hairline overlay + clip`) inline | PermissionsView, MetricsView help section, AudioTranscribeView drop zone, EnhancementSettingsView buttons, PromptEditorView triggers | Same vocabulary expressed inline 5–10 lines instead of one `glassChip()` modifier — drift accumulates fast |
| `Form { Section }` host, even with `SettingsSectionHeader` | EnhancementSettingsView, AudioTranscribeView queue, InlineHistoryView card list, PromptEditorView panes, EnhancementSettingsPanel body | macOS Form chrome (grouped section bg, list separators, indentation) double-layers under the glass and reads as Apple-default. SettingsView abandoned this at W5 (see SettingsCard.swift:21-23) |
| Hardcoded NSColor opaque backgrounds | ~13 sites (see #33) | Defeats the W8 wallpaper-glass; user sees a flat windowBackground rectangle where they expected glass |
| Ad-hoc `.spring(0.3, 0.7/0.8)` / `.smooth(0.3)` / `.easeInOut(0.15/0.2/0.3/0.5)` | MetricsContent, ModelManagementView, EnhancementSettingsView, AudioTranscribeView, PermissionsView, InlineHistoryView, PowerModeView | Spec §2.4 names exactly four animation tokens (`haloExpand`, `haloCollapse`, `haloBreathe`, `haloPhaseCrossfade`). The recorder cluster's snappy 0.38s spring cohesion is broken whenever a card opens with a different timing |
| `Color.purple / .yellow / .blue / .green / .orange / .red` direct refs | MetricsContent (cards), PermissionsView (icons), AppNotificationView (per-type), CompactHeroSection (`.blue`) | Spec §1 retired the rainbow. `Palette.accent / .success / .warn / .neutral` are the four sanctioned tokens |
| `.font(.system(... design: .rounded))` outside designated places | MetricsContent hero (`size: 36`) + MetricCard value (`size: 24, weight: .black, design: .rounded`) | Spec §5#9 / W7 explicitly retired `.rounded` on body / card content |
| `Color.accentColor` (system) in place of `Palette.accent` | All AI Models cards (Whisper / Cloud / FluidAudio / NativeApple), EnhancementSettingsView icon (`Palette.accent` correct, but the gear background uses `.accentColor` indirectly), MetricsContent hero gradient | Pre-W1 leftover. System accent on macOS is blue by default — diverges from tangerine immediately |
| `28pt` corner radii (HelpAndResourcesSection) | 1 site | Spec caps panels at 14pt. 28pt is the v1 "card" radius retired in spec §1 |
| Forced colorScheme | EnhancementPromptPopover (`.dark`) | Bypasses GlassAppearanceDetector — won't pick light variant on bright wallpapers |

---

## 4. Recommended W13 sequencing

The work fans out cleanly. Suggested order — each packet ≤ 1 coder/reviewer pair, reviewable independently.

### W13-A — Token + primitive refresh (foundation, must land first)

1. **CompactHeroSection blue → accent**: one-line edit at `Common/CompactHeroSection.swift:13`. Touches Permissions, AudioInputSettings, DictionarySettings simultaneously.
2. **AppNotificationView per-type colors → Palette tokens** (`Notifications/AppNotificationView.swift:30-36`).
3. **Add `Palette.glow` halo helpers / verify Palette.success / accentMuted exist** for substitution.
4. **Audit `Color.accentColor` call sites** — codemod to `Palette.accent` (excluding tinted `.controlAccentColor` system-driven affordances like menubar):
   - `AI Models/{WhisperModel, CloudModel, FluidAudio, NativeApple}CardView.swift` strokes
   - `MetricsContent.swift` hero gradient
5. **Add `glassChip(cornerRadius: 8)` overload (already supported)** if needed for 8pt close-button affordance — confirm `GlassChip.swift:67-68` covers it.

Acceptance: build clean; visual diff shows tangerine instead of system-blue across Permissions / AudioInput / Dictionary / model cards; HUD notifications recolor.

### W13-B — Metrics dashboard rebuild (highest user-visible impact)

1. **MetricCard** → wrap `RoundedRectangle 16pt + .thinMaterial` with `GlassCard(cornerRadius: 16)`.
2. **MetricsContent hero** → reduce font weight/size to `.system(32, .bold)` (drop `.rounded`); replace controlAccentColor gradient with onyx glass; tangerine accent only on the time-saved value.
3. **HelpAndResourcesSection** → `GlassCard(cornerRadius: 16)`; inner link rows → `glassChip(cornerRadius: 10)`.
4. **CopySystemInfoButton** → `glassChip(cornerRadius: 999)` (Capsule); animation `.spring(0.3, 0.7)` → `Animation.haloExpand`.
5. Per-card icon colors: drop rainbow palette, key all to `Palette.accent` (or one of the four sanctioned tokens).

Acceptance: opening the app → first surface (dashboard) reads as glass-on-wallpaper with tangerine accent. No raw `.thinMaterial`, no `Color.purple/.yellow`, no `.rounded` in this file.

### W13-C — Permissions + AudioTranscribe re-skin

1. **PermissionsView.PermissionCard** background → `GlassCard(cornerRadius: 14)`. Icon tile constants → `SettingsSectionHeader.swift:32` constants. CTA → `Palette.accentMuted`-fill `glassChip(cornerRadius: 10)`.
2. **AudioTranscribeView** drop zone → `glassPanel(cornerRadius: 14)` with `Palette.accent` dashed stroke.
3. **AudioTranscribeView** topBar pill buttons → `glassChip()`.
4. **AudioTranscribeView queue** → `LazyVStack(spacing: 12) { GlassCard }` (drops `Form`).

Acceptance: Permissions cards visually match SettingsCards; drop zone reads as active glass not Apple-default border.

### W13-D — Form-host purge (Enhancement + History inline + Prompt editor + Audio queue)

Migrate every `Form { Section { } header: { SettingsSectionHeader } } .formStyle(.grouped)` to `ScrollView { LazyVStack(spacing: 16) { SettingsCard {...} } }` per W5/`SettingsView` pattern.

1. `EnhancementSettingsView.swift:52-159` (highest pri — surface user opens via Enhancement tab)
2. `History/InlineHistoryView.swift:254-301` cardListView
3. `PromptEditorView.swift:223-366` editorPane forms
4. `Components/EnhancementSettingsPanel.swift` body forms
5. `AudioTranscribeView.swift:98-141` queue Form

Acceptance: Form-grouped chrome is gone everywhere except where user-installed system controls (NSPicker etc.) require it.

### W13-E — AI Models card unification

1. **WhisperModelCardView / CloudModelCardView / FluidAudioModelCardView / NativeAppleModelCardView** → uniform `GlassCard(cornerRadius: 16)` wrapper. Strokes recolor to `Palette.accent` (active) / `Palette.hairline` (rest).
2. **MLXModelPickerView row** wrap → `glassPanel(cornerRadius: 14)`.
3. **ModelManagementView default-model section** → `SettingsSectionHeader` instead of `.headline / .title2`.

Acceptance: all 6 model card variants share one card silhouette.

### W13-F — History window glass + animation token sweep

1. **HistoryWindowController.createHistoryWindow** → set `isOpaque = false` and `backgroundColor = .clear`; reuse `WindowManager.configureWindow` flags. Drop `Color(NSColor.windowBackgroundColor)` fallbacks at `TranscriptionHistoryView.swift:133, 295-301, 321, 392`.
2. **InlineHistoryView search field** at `:152-172` → `glassChip`.
3. **Animation grammar codemod**: every `withAnimation(.spring(0.3, 0.7))` / `.smooth(duration: 0.3)` / `.easeInOut(duration: 0.15-0.5)` → `Animation.haloExpand` / `.haloCollapse` / `.haloPhaseCrossfade`. Reviewer note at `Animation+Halo.swift:14-17` calls this out as already-prohibited.

Acceptance: opening Show History from menu bar pops a glass window, not an opaque controlBackgroundColor box. All animations use named tokens.

### W13-G — Polish (deferrable)

- PredefinedPromptsView buttons → `GlassCard`.
- EnhancementPromptPopover backdrop → `glassPanel`; drop `.dark` colorScheme override.
- PromptEditorView trigger-word chips → `glassChip(10pt)`.
- PowerModeView hero → `SettingsSectionHeader`.
- ContentView sidebar header row → optional `glassChip` wrapper.

---

## 5. Open questions for the user (lead must ask before W13 starts)

These are places where the spec is ambiguous, the lead could legitimately go either way, or new product decisions need user input:

1. **MenuBarView dropdown — keep system NSMenu or migrate to `.window` style for glass?**
   Spec §1.X (line 74) says "OOS — system NSMenu via `.menuBarExtraStyle(.menu)` — not skinnable." VoiceInk.swift:391 comment notes: *"the earlier `.window` glass popover was deemed too sparse (no recording action, no recents copy) — reverted per user request."* So `.menu` was a deliberate choice. Re-asking: the user complaint is that the app aesthetic doesn't match the floating-bar — does the menu bar dropdown count? If yes, accepting some sparseness vs. system-menu cohesion is the trade.

2. **History window — separate NSWindow or embed in ContentView?**
   Today menu bar's "Show History…" opens a separate NSWindow via HistoryWindowController; ContentView also embeds an InlineHistoryView for the History tab. Two histories with different layouts. Should the standalone window be retired (route everything through main-window navigation) or kept for power users? If kept, should it adopt the glass pipeline (W13-F) or stay system-default?

3. **Metrics hero gradient — keep or drop?**
   `MetricsContent.heroSection` uses `controlAccentColor` linear gradient with white text. If we recolor with `Palette.accent`, do we keep the gradient identity (making it a tangerine box on glass) or drop the gradient entirely and let the time-saved number sit on plain glass (more cohesive but less "celebratory")?

4. **Per-card icon palette in Metrics — single accent or restored functional colors?**
   Spec §2.5 keys section icons to functional palette tokens (Recording=accent / Privacy=success / Power Mode=warn). MetricCard uses `.purple / .yellow / .orange / .controlAccentColor` per-card; nothing in spec covers metric-card icons specifically. Options: (a) one accent for all (cohesion, less data-vis); (b) keep functional differentiation using only the 4 sanctioned tokens.

5. **AppNotificationView per-type recolor — preserve red-error semantics?**
   Spec §1 says single tangerine for live states; failed uses tangerine + amber dwell at the recorder (HaloPhase.failed). HUD app-notification at top-right is a separate vocabulary. Keep `.red` for `.error` (legibility / common-sense) or unify to `Palette.accent`?

6. **`.rounded` typography exceptions?**
   Spec retires `.rounded` for body/card content. MetricsContent hero uses `.system(36, design: .rounded)` — rounded is part of the "celebratory dashboard" feel. Hard rule (drop rounded everywhere) or one-off exception for the hero?

7. **Widget for `Color.accentColor` system tint vs. `Palette.accent`?**
   Some controls (sidebar selection tint, native pickers, Toggle on-state) inherit from `.tint(Palette.accent)`. Other native elements (`Image(systemName:).foregroundColor(.accentColor)`) take system blue. Open: install a `.tint(Palette.accent)` higher in the tree and audit `.accentColor` references? Or leave system controls system-tinted and only enforce in custom views?

---

## 6. Citations index

Every divergence claim above carries a `file:line` citation. Prime spec-of-record:

- **Spec source:** `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1, §2.5, §3.3, §5#9, §6.1, §6.4
- **App-wide design:** `docs/superpowers/specs/2026-04-28-app-visual-redesign-design.md` §2.3, §2.4, §3.1
- **Material primitive:** `VoiceInk/Views/Recorder/HaloMaterial.swift:107-271`
- **Chip primitive:** `VoiceInk/Views/Common/GlassChip.swift:23-75`
- **Card primitive:** `VoiceInk/Views/Common/GlassCard.swift:19-45`
- **Pane backdrop:** `VoiceInk/Views/Common/AdaptiveGlassBackground.swift:48-86`
- **Motion grammar:** `VoiceInk/Views/Common/Animation+Halo.swift:19-33` (with reviewer note `:14-17`)
- **Palette tokens:** `VoiceInk/Views/Common/Palette.swift:32-78`
- **Section header:** `VoiceInk/Views/Common/SettingsSectionHeader.swift:29-79`
- **Settings card pattern:** `VoiceInk/Views/Common/SettingsCard.swift:25-59`
- **Settings host (ref):** `VoiceInk/Views/Settings/SettingsView.swift:51-71` (this is the pattern to copy)
- **Window flag pattern:** `VoiceInk/WindowManager.swift:36-41` (mirror in HistoryWindowController)
