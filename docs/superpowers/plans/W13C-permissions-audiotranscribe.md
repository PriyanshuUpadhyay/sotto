# W13.C — Permissions + AudioTranscribe Styling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` for executing tasks task-by-task. Reviewer: `superpowers:code-reviewer`. Steps use checkbox (`- [ ]`) syntax.

**Date:** 2026-04-30
**Author:** planner-w13c (team `voiceink-phase23`, task #19)
**Scope:** Permissions surface (`PermissionsView.PermissionCard` chrome) + AudioTranscribe drop-zone, drop-overlay, top-bar action pills, and minimal queue-row palette/animation alignment. Stylistic only — zero behavioral change.

**Sources of truth:**
- R4 audit (the WHY): `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md` §1 row 2, §3 rows 5-8 + 17-18, §3.1, §4 W13-C, §5 Q-context.
- Spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (tokens, glass primitive, motion grammar), §1.X (W8 wallpaper-glass contract), §2.4 (motion tokens), §6.4 (Reduce-Transparency / Increase-Contrast contract).
- Master plan §4 W13.C (2-bullet scope) + §6 sequencing: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`.
- Sibling shape (mirrored exactly — including per-axis Sweep/Defer/Flag table): `docs/superpowers/plans/W13B-metrics-rebuild.md`.
- Vocabulary primitives (verify, do not edit): `Palette.swift`, `GlassCard.swift`, `GlassChip.swift` (`glassChip` / `glassPanel` modifiers), `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` under `VoiceInk/Views/Common/`.

**Goal:** Permissions cards + AudioTranscribe drop-zone + queue action pills speak the same vocabulary as the floating recorder cluster (per spec §1, §1.X, §2.4) — without altering behavior, layout, or the queue Form host (W13.D's territory). Post-merge a user opening the Permissions tab or dropping a file into AudioTranscribe sees tangerine-on-glass, motion-tokenized chrome consistent with the W5/W13.B reskin.

**Locked decisions honored:**
- Master plan §4 W13.C — two scope bullets: PermissionCard glass swap; AudioTranscribeView queue-card / drop-zone glass swap.
- Brief 2026-04-30 — Form host purge for the queue area is **W13.D's territory**. W13.C only restyles existing chrome inside the surface, never the Form structure.
- Brief 2026-04-30 — drop `.rounded` font if present (regression-guard — pre-grep finds zero hits in scope).
- Brief 2026-04-30 — drop `.windowBackgroundColor` / `.controlBackgroundColor` if present (drop-zone has both — see Per-axis row 7).

---

## Prelude — packet shape + commit etiquette

**Shape.** Single coder + reviewer pair under team `voiceink-phase23` post-sign-off. Diff is bounded to three Swift files (`PermissionsView.swift`, `AudioTranscribeView.swift`, `AudioFileRow.swift`) plus this plan file. Estimated total LOC delta: ~70 lines edited, near-zero net new lines. No new files. No new SPM deps. No new tokens beyond what `Palette.swift` already exposes. No deployment-target change (already 26.0 per W11.B). No test-infra change (Q10 deferred).

**Commit cadence per `feedback_skip_per_packet_builds.md`.** Coder leaves edits uncommitted in the worktree. Lead runs single integration `make local` at merge time and commits:
```
docs(plans): W13C — Permissions + AudioTranscribe styling
feat(aesthetic): W13C — Permissions + AudioTranscribe styling
```
Coder does NOT commit. Coder does NOT run `xcodebuild` per task. The integration build is the gate.

**Worktree convention.** Spawn at `.worktrees/w13c/` ABSOLUTE path. Always `cd <main-repo>` before `git worktree add` to avoid cwd-drift (lead has been bitten by this).

**Comment policy.** Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code. Inline doc-comments may cite spec §1 / §2.4 + this plan path. Pre-existing spec-ref comments preserved.

**Visual verification.** This packet is verified by **screenshot diff**, not by automated tests (no visual-diff CI exists). The user runs the post-merge protocol in §Post-merge verification. Coder + reviewer eyeball the build locally.

---

## Per-axis Sweep / Defer / Flag table

Mirrors W13.B's shape. Each row is one axis × one surface; disposition is **Sweep** (land in W13.C), **Defer** (route to other W13 packet), or **Flag** (ambiguous; coder evaluates context, sweeps if obvious or leaves with comment).

| # | Surface | File:line | Axis | Current | W13.C Action | Disposition | Rationale |
|---|---|---|---|---|---|---|---|
| 1 | `PermissionCard` background hand-rolled glass | `PermissionsView.swift:188-201` | material + geometry | `.padding(20) + RoundedRectangle(14).fill(.ultraThinMaterial) + obsidian fill 0.078,0.078,0.110@0.28 + Palette.hairline 1pt overlay + clipShape(14)` | Replace background+overlay+clip stack with `GlassCard(cornerRadius: 14, padding: 20)` wrapper around the existing inner VStack. Drops 11 lines of inline glass chrome. | **Sweep** | spec §1 / R4 §1 row 2; one of W13.C's two canonical bullets per master plan §4. PermissionCard is "exactly the spec's chip vocabulary, just inlined" (R4). |
| 2 | `PermissionCard` outer padding | `PermissionsView.swift:188` | geometry | `.padding(20)` | Pass `padding: 20` to GlassCard explicitly to preserve v1 rhythm (GlassCard default is 14 — noticeably tighter on a 4-card grid). | **Flag — coder picks at smoke-test** | Visual judgment. Recommended: 20 to preserve v1 feel; smoke-test at Task 8, drop to GlassCard default 14 if cards feel airy. |
| 3 | `PermissionCard` CTA button chrome | `PermissionsView.swift:163-186` | material/color | solid `Palette.accent` 10pt RoundedRectangle + `.white` text + `Palette.hairline` 1pt overlay | KEEP — solid tangerine capsule reads as primary CTA. R4 row 6 routes to W13.G polish. | **Defer (W13.G)** | Master plan §4 W13.C bullets do NOT include the CTA button. R4 §1 row 6 + R4 §4 W13-A flags this for the polish packet (option: glassChip + `Palette.accentMuted` fill + `Palette.accent` foreground). Open Question 1 for lead. |
| 4 | `PermissionCard` icon tile | `PermissionsView.swift:101-114` | geometry / color | 10pt rad / 44×44 / `Palette.success`-or-`.warn` 0.18 fill / 0.36 stroke 0.5pt | KEEP — `Palette.success` / `Palette.warn` functional tokens are spec-correct (non-state semantics: granted=success, needs=warn). | **Flag — preserve** | spec §1 — `success` / `warn` retained for non-state semantics. R4 §3 row 7 flags drift from `SettingsSectionHeader` constants (7pt rad / 0.16 fill / 0.32 stroke) — defers to W13.G polish. |
| 5 | `PermissionCard` refresh button animation | `PermissionsView.swift:138` | animation | `Animation.haloExpand` | KEEP | **Flag — verify, no edit** | Already spec-compliant. Regression-guard at Task 7. |
| 6 | `PermissionsView.CompactHeroSection` icon | `Common/CompactHeroSection.swift:13` | color (rainbow) | `.foregroundStyle(.blue)` | DEFER to W13.G polish | **Defer (W13.G)** | Master plan §4 W13.G assigns `CompactHeroSection icon (.blue) → Palette.accent`. Touches Permissions + AudioInputSettings + DictionarySettings simultaneously — must not be edited piecemeal in W13.C. |
| 7 | `AudioTranscribeView` drop-zone background | `AudioTranscribeView.swift:54-64` | material + geometry | `RoundedRectangle(12).fill(Color(.windowBackgroundColor).opacity(0.4))` + `RoundedRectangle(12).strokeBorder(StrokeStyle(lineWidth: 2, dash: [8])).foregroundColor(isDropTargeted ? .accentColor : .gray.opacity(0.5))` | Replace fill rect with `.glassPanel(cornerRadius: 14)` modifier on the inner `VStack(spacing: 14)`; keep the dashed strokeBorder as an `.overlay(RoundedRectangle(cornerRadius: 14)...)` recolored to `Palette.accent` (active) / `Palette.hairlineSoft` (rest); bump radius 12 → 14. | **Sweep** | spec §1 (panel cap 14pt; chip 10pt) + R4 §1 row 17; one of W13.C's two canonical bullets per master plan §4. `windowBackgroundColor` retired per brief 2026-04-30. |
| 8 | drop-zone icon foreground | `AudioTranscribeView.swift:69` | color | `isDropTargeted ? .accentColor : .gray` | `isDropTargeted ? Palette.accent : Palette.onyxMute` | **Sweep** | spec §1 — `Color.accentColor` (system blue default) → `Palette.accent`; `.gray` → `Palette.onyxMute`. |
| 9 | drop-zone "Choose Files" button | `AudioTranscribeView.swift:77-80` | style | `.buttonStyle(.bordered)` (system) | KEEP system-bordered — it's a button inside a glass panel, not chrome; system-bordered is acceptable inside a glassPanel context. | **Flag — preserve** | Spec §1 doesn't prescribe button style for system-default-context buttons inside a panel. Reviewer note acceptable. |
| 10 | drop-zone foreground crossfade animation | `AudioTranscribeView.swift:64` | animation | `.easeInOut(duration: 0.15)` on `isDropTargeted` value-change | `Animation.haloPhaseCrossfade` (0.22s easeInOut — closest spec match for foreground-color crossfade) | **Sweep** | spec §2.4 — sanctioned tokens are `.haloExpand / .haloCollapse / .haloBreathe / .haloPhaseCrossfade`. The 0.15s easeInOut is closest to `.haloPhaseCrossfade` (0.22s). |
| 11 | `dropOverlay` border + fill | `AudioTranscribeView.swift:283-288` | color | `Color.accentColor` strokeBorder dashed + `Color.accentColor.opacity(0.06)` fill | `Palette.accent` strokeBorder dashed + `Palette.accent.opacity(0.06)` fill | **Sweep** | spec §1 token alignment. |
| 12 | `dropOverlay` radius | `AudioTranscribeView.swift:283, 286` | geometry | 12pt | 14pt (panel canonical) | **Sweep** | spec §1 — chip 10pt / panel 14pt. |
| 13 | `dropOverlay` text foreground | `AudioTranscribeView.swift:292` | color | `.foregroundColor(.accentColor)` | `.foregroundColor(Palette.accent)` | **Sweep** | spec §1. |
| 14 | `dropOverlay` animation | `AudioTranscribeView.swift:296` | animation | `.easeInOut(duration: 0.15)` on `isDropTargeted` | `Animation.haloPhaseCrossfade` | **Sweep** | spec §2.4 — same row 10 rationale. |
| 15 | topBar **Add** button | `AudioTranscribeView.swift:150-167` | material | `Capsule().fill(Color.secondary.opacity(0.12))` + manual `.padding(.horizontal, 10).padding(.vertical, 5)` | Drop the `.background(Capsule().fill(...))` + manual padding; apply `.glassChip(cornerRadius: 10)` modifier (which provides 11h/7v padding — matches v1 visual rhythm). | **Sweep** | R4 §3 row 17 second-half: "topBar buttons → `glassChip()`." |
| 16 | topBar **Clear** button | `AudioTranscribeView.swift:216-237` | material | same as Add | same fix as Add — `.glassChip(cornerRadius: 10)` | **Sweep** | same row 15 rationale. |
| 17 | topBar **Cancel** button | `AudioTranscribeView.swift:175-193` | material/color | `Capsule().fill(Color.red.opacity(0.12))` + `.foregroundColor(.red)` | `.glassChip(cornerRadius: 10)` background + `.foregroundColor(.secondary)` (cancel is a passive action, not error). Recommended `.secondary`; alternative `Palette.warn`. **Open Question 3.** | **Sweep — coder/lead picks color** | spec §1 — direct `.red` retired in favor of functional palette tokens. `.warn` (amber) is the closest "alarming" token; `.secondary` reads more passive. Lead picks. |
| 18 | topBar **Start** button | `AudioTranscribeView.swift:195-214` | material/color | `Capsule().fill(Color(.controlAccentColor))` + shadow + `.foregroundColor(.white)` + `.font(weight: .semibold)` | Replace fill with `Capsule().fill(Palette.accent)` + drop `Color(.controlAccentColor)` shadow (or recolor shadow to `Palette.accentGlow`); KEEP solid-fill capsule (mirrors PermissionCard CTA — primary action affordance). **Open Question 4** asks whether to wrap in glassChip instead. | **Sweep — coder/lead picks** | spec §1 — `.controlAccentColor` retired. Recommend solid `Palette.accent` capsule (matches PermissionCard CTA at row 3). Alternative: `.glassChip(cornerRadius: 10)` background + `Palette.accent` foreground for chip-vocabulary cohesion. Lead picks at sign-off. |
| 19 | topBar button animations | `AudioTranscribeView.swift:217` | animation | `.easeInOut(duration: 0.2)` (Clear button) | `Animation.haloExpand` | **Sweep** | spec §2.4. |
| 20 | `AudioTranscribeView` queue Form host | `AudioTranscribeView.swift:103-131` | structure | `Form { ForEach { Section { AudioFileRow(...) } } } .formStyle(.grouped) .scrollContentBackground(.hidden)` | KEEP Form structure intact — W13.D handles purge. | **Defer (W13.D)** | Brief 2026-04-30 explicit: "Keep `Form { Section }` structure intact (W13.D's territory)." |
| 21 | `AudioFileRow` palette refs | `AudioFileRow.swift:86, 172` | color | `.foregroundColor(.accentColor)` (×2) | `.foregroundColor(Palette.accent)` (×2) | **Sweep** | spec §1 — system blue retired. Within W13.C scope per "queue card chrome (the styling of individual queue items)." |
| 22 | `AudioFileRow` row chrome (full glass wrap) | `AudioFileRow.swift` body | material | plain HStack content; chrome currently provided by Form Section grouping | DEFER to W13.D — wrapping rows in `glassPanel()` while Form host stays would create double-chrome conflict. Full glass wrap lands at W13.D when Form is purged and rows live in `LazyVStack(spacing: 12) { GlassCard }`. | **Defer (W13.D)** | Brief 2026-04-30 — "Keep Form { Section } structure intact." Visual conflict if both layers wear chrome. Open Question 5 for lead. |
| 23 | `AudioFileRow` expand/collapse animations | `AudioTranscribeView.swift:41, 110, 115` | animation | `.easeInOut(duration: 0.3)` (1×) + `.easeInOut(duration: 0.2)` (2×) | `Animation.haloExpand` (×3 — these are reveal/morph axis animations) | **Sweep** | spec §2.4; W13.B precedent — `spring(0.3, 0.7)` mapped to `.haloExpand`. The 0.2-0.3s easeInOut here is the same "reveal-axis" intent. |
| 24 | `.rounded` font in scope (regression guard) | both files | font | none present | KEEP — verify zero hits at Task 7 | **Flag — verify** | Brief 2026-04-30 explicit "Drop `.rounded` font if present" — already absent. Pre-grep at Task 0 confirms 0 hits in `PermissionsView.swift / AudioTranscribeView.swift / AudioFileRow.swift`. Regression-guard. |

### Deferred (route to other W13 packets)

| File / surface | Why deferred |
|---|---|
| `Common/CompactHeroSection.swift:13` (`.foregroundStyle(.blue)`) | **W13.G** — touches Permissions + AudioInputSettings + DictionarySettings simultaneously per master plan §4. Single edit, must land all-in-one. |
| `PermissionCard` CTA button chip-wrap (R4 row 6) | **W13.G** polish — solid tangerine capsule reads as primary CTA today; chip-wrap is a vocabulary-cohesion polish, not in master plan §4 W13.C bullets. |
| `PermissionCard` icon tile geometry drift (R4 row 7) | **W13.G** polish — 10pt vs 7pt rad / 0.18 vs 0.16 fill / 0.36 vs 0.32 stroke is drift, not divergence. Realign to `SettingsSectionHeader` constants in polish packet. |
| `AudioTranscribeView` queue Form host purge (`Form { Section }` → `LazyVStack { GlassCard }`) | **W13.D** — explicit territory per brief 2026-04-30 + master plan §4 W13.D bullet. |
| `AudioFileRow` full chrome rebuild | **W13.D** — paired with the Form purge; touching both at the same time avoids double-chrome conflict. W13.C limits to palette + animation token swaps. |
| `AppNotificationView` per-type rainbow + recorder-cluster-vocab alignment | **W13.G** polish — separate notification surface, OOS for W13.C. |

### Flagged (no edit — context-eval at coder review)

| Item | Reason |
|---|---|
| `PermissionCard` outer padding 20pt vs GlassCard default 14pt (row 2) | Visual judgment; smoke-test at Task 8. Recommend 20 for v1-feel preservation. |
| `PermissionCard` CTA button (row 3) | W13.G territory; preserve current solid tangerine capsule. Open Q1. |
| `PermissionCard` icon tile geometry (row 4) | Drift, not divergence; W13.G territory. |
| `PermissionCard` refresh button animation (row 5) | Already spec-compliant — regression-guard. |
| Drop-zone "Choose Files" button (row 9) | Acceptable system-bordered button inside a glassPanel context. |
| `.rounded` font regression guard (row 24) | Already absent — guard against re-introduction. |

---

## Tasks

### Task 0 — Audit + grep validation (read-only)

**Files:** none.

- [ ] Re-run `rg` for the W13.C target patterns and confirm hit counts match this plan's Per-axis table:

  ```bash
  # Hand-rolled glass + palette anti-patterns in PermissionsView
  rg -n 'ultraThinMaterial|windowBackgroundColor|controlBackgroundColor|controlAccentColor|accentColor' VoiceInk/Views/PermissionsView.swift VoiceInk/Views/AudioTranscribeView.swift VoiceInk/Views/AudioFileRow.swift

  # Ad-hoc easeInOut / spring in scope
  rg -n 'easeInOut\(duration:|spring\(response:' VoiceInk/Views/PermissionsView.swift VoiceInk/Views/AudioTranscribeView.swift VoiceInk/Views/AudioFileRow.swift

  # .rounded font (regression guard — should be 0)
  rg -n 'design:\s*\.rounded' VoiceInk/Views/PermissionsView.swift VoiceInk/Views/AudioTranscribeView.swift VoiceInk/Views/AudioFileRow.swift

  # Capsule().fill(...) anti-pattern in AudioTranscribeView
  rg -n 'Capsule\(\)' VoiceInk/Views/AudioTranscribeView.swift
  ```

  Expected hit counts (from this plan):
  - `ultraThinMaterial`: **1** in scope (`PermissionsView.swift:191`).
  - `windowBackgroundColor`: **1** in scope (`AudioTranscribeView.swift:56`).
  - `controlAccentColor`: **2** in scope (`AudioTranscribeView.swift:209, 210`).
  - `accentColor` (bare): **5** in scope — `AudioTranscribeView.swift:62, 69, 284, 287, 292` + `AudioFileRow.swift:86, 172`. (Total **7** when AudioFileRow grep included.)
  - `easeInOut(duration:`: **5** in scope — `AudioTranscribeView.swift:41, 64, 110, 115, 217, 296`. (Six lines actually — recount in implementation; treat 5-7 as acceptable range.)
  - `spring(response:`: **0** in scope.
  - `design: .rounded`: **0** in scope (regression guard — must remain 0).
  - `Capsule()`: **5** in scope (`AudioTranscribeView.swift:163, 188, 208, 232` + `:283-286` overlay where Capsule isn't used — actual count in topBar 4: Add/Cancel/Start/Clear).

- [ ] If hit counts differ materially, escalate to lead before drafting edits. Do not drift the scope.

- [ ] Read `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift` in full to confirm the primitive APIs the edits below assume:
  - `GlassCard(cornerRadius:padding:appearance:)` — `cornerRadius` defaults to 16, `padding` to 14, `appearance` defaults to `nil` (resolves to `GlassAppearanceDetector.shared.current`). Content is a `@ViewBuilder` closure.
  - `.glassChip(cornerRadius:)` — modifier; default 10pt; padded 11h/7v.
  - `.glassPanel(cornerRadius:)` — modifier; default 14pt; padded 14h/12v.
  - `Palette.accent`, `Palette.accentMuted`, `Palette.accentGlow`, `Palette.hairline`, `Palette.hairlineSoft`, `Palette.innerHi`, `Palette.onyxFg`, `Palette.onyxMute`, `Palette.success`, `Palette.warn`, `Palette.neutral` available.
  - `Animation.haloExpand`, `.haloCollapse`, `.haloBreathe`, `.haloPhaseCrossfade` available.

- [ ] Confirm `PermissionsView.PermissionCard` is the only PermissionCard struct in repo (`rg -n 'struct PermissionCard' VoiceInk/`). If multiple definitions exist, escalate.

### Task 1 — PermissionCard background → GlassCard wrap

**Files:** `VoiceInk/Views/PermissionsView.swift`.

- [ ] At `PermissionsView.swift:97-202` (the PermissionCard struct body), replace the inline `.padding(20) + .background(...) + .overlay(...) + .clipShape(...)` chrome stack at `:188-201` with a `GlassCard(cornerRadius: 14, padding: 20)` wrapper around the existing top-level `VStack(alignment: .leading, spacing: 16)`. Preserve every child view byte-identical. Final body skeleton:

  ```swift
  var body: some View {
      GlassCard(cornerRadius: 14, padding: 20) {
          VStack(alignment: .leading, spacing: 16) {
              HStack(spacing: 16) {
                  // existing icon ZStack (lines 101-114) — unchanged
                  // existing title/description VStack (lines 116-131) — unchanged
                  Spacer()
                  // existing refresh + StatusPill HStack (lines 136-160) — unchanged
              }

              if !isGranted {
                  // existing CTA Button (lines 164-186) — unchanged
              }
          }
      }
  }
  ```

- [ ] Drop the entire `.padding(20)` + `.background(RoundedRectangle(14)...)` + `.overlay(RoundedRectangle(14)...)` + `.clipShape(RoundedRectangle(14)...)` chain at `:188-201` (12 lines). GlassCard composes the equivalent (HaloMaterial(phase: .hidden), `Palette.hairline` border, `Palette.innerHi` inner sheen, drop shadow) per spec §1.

- [ ] PRESERVE the icon ZStack (`:101-114`) — `Palette.success`/`.warn` functional tokens are spec-correct; geometry drift defers to W13.G.

- [ ] PRESERVE the CTA button (`:164-186`) — solid `Palette.accent` capsule reads as primary CTA; R4 row 6 defers chip-wrap to W13.G. Do NOT change this in W13.C.

- [ ] PRESERVE the refresh button animation `Animation.haloExpand` at `:138` — already spec-compliant.

**Verify:**
- `PermissionCard` body no longer references `.ultraThinMaterial`, `Color(red: 0.078, green: 0.078, blue: 0.110)`, `RoundedRectangle(cornerRadius: 14)` (the GlassCard's `cornerRadius: 14` parameter doesn't show as a literal RoundedRectangle).
- Visual rhythm: 20pt outer padding preserved (passed to GlassCard).
- All 4 PermissionCards in PermissionsView render with HaloMaterial(phase: .hidden) chrome (onyx/light adaptive via `GlassAppearanceDetector`).

### Task 2 — AudioTranscribeView drop-zone re-skin

**Files:** `VoiceInk/Views/AudioTranscribeView.swift`.

- [ ] At `:50-94` (`emptyStateView`), restructure the `ZStack { RoundedRectangle(12).fill(...) ; RoundedRectangle(12).strokeBorder(...) ; VStack { ... } }` into a `VStack { ... }.glassPanel(cornerRadius: 14).overlay(dashed border)` shape. Recommended final body:

  ```swift
  private var emptyStateView: some View {
      VStack(spacing: 0) {
          Spacer()

          VStack(spacing: 14) {
              Image(systemName: "arrow.down.doc")
                  .font(.system(size: 32))
                  .foregroundColor(isDropTargeted ? Palette.accent : Palette.onyxMute)

              Text("Drop audio or video files here")
                  .font(.headline)

              Text("or")
                  .foregroundColor(.secondary)

              Button("Choose Files") {
                  selectFiles()
              }
              .buttonStyle(.bordered)
          }
          .padding(32)
          .frame(maxWidth: 480, maxHeight: 200)
          .glassPanel(cornerRadius: 14)
          .overlay(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .strokeBorder(
                      style: StrokeStyle(lineWidth: 2, dash: [8])
                  )
                  .foregroundColor(isDropTargeted ? Palette.accent : Palette.hairlineSoft)
          )
          .animation(.haloPhaseCrossfade, value: isDropTargeted)

          Text("Supports WAV, MP3, M4A, AIFF, MP4, MOV, AAC, FLAC, CAF, AMR, OGG, OPUS, 3GP")
              .font(.caption)
              .foregroundColor(.secondary)
              .padding(.top, 12)

          Spacer()
      }
      .padding()
  }
  ```

  *Note 1:* `glassPanel(cornerRadius: 14)` adds 14h/12v padding via the modifier. The pre-existing `.padding(32)` on the inner VStack reads as content-padding *inside* the glass panel and remains. If visual rhythm feels off (panel reads cramped), reduce the inner `.padding(32)` to `.padding(24)`. Smoke-test at Task 8.

  *Note 2:* The dashed strokeBorder overlay sits on top of the panel — same z-order as v1. `Palette.hairlineSoft` (white α 0.10) is the rest-state token; `Palette.accent` is the targeted-state token. v1 used `.gray.opacity(0.5)` rest-state — `Palette.hairlineSoft` is closer to spec. If smoke-test shows dashed border is too faint at rest, fall back to `Palette.hairline` (white α 0.16).

- [ ] Drop the original `ZStack`. Remove `Color(.windowBackgroundColor).opacity(0.4)` fill — replaced by `glassPanel`'s `rgba(20,20,28, 0.55)` fill per spec §1.

- [ ] Bump corner radius 12 → 14 (panel canonical per spec §1).

**Verify:**
- `rg -n 'windowBackgroundColor' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits.
- `rg -n 'cornerRadius: 12' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits in scope (the dropOverlay 12pt is fixed in Task 3).
- Drop zone reads as a glass panel against the wallpaper (not an opaque windowBackgroundColor box).

### Task 3 — dropOverlay re-skin

**Files:** `VoiceInk/Views/AudioTranscribeView.swift`.

- [ ] At `:282-297`, swap the dropOverlay tokens:

  ```swift
  private var dropOverlay: some View {
      RoundedRectangle(cornerRadius: 14, style: .continuous)
          .strokeBorder(Palette.accent, style: StrokeStyle(lineWidth: 2, dash: [8]))
          .background(
              RoundedRectangle(cornerRadius: 14, style: .continuous)
                  .fill(Palette.accent.opacity(0.06))
          )
          .overlay {
              Text("Drop to add files")
                  .font(.subheadline.weight(.medium))
                  .foregroundColor(Palette.accent)
          }
          .padding(16)
          .transition(.opacity)
          .animation(.haloPhaseCrossfade, value: isDropTargeted)
  }
  ```

- [ ] Bump radius 12 → 14 (panel canonical, two sites at `:283, :286`).

- [ ] Replace 3 × `Color.accentColor` with `Palette.accent` at `:284, :287, :292`.

- [ ] Replace `.easeInOut(duration: 0.15)` with `Animation.haloPhaseCrossfade` at `:296`.

**Verify:**
- `rg -n 'Color\.accentColor' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits within `dropOverlay`.
- Radius 14 across the dropOverlay rect.

### Task 4 — topBar action pills → glassChip codemod

**Files:** `VoiceInk/Views/AudioTranscribeView.swift`.

- [ ] At `:150-167` (Add button), drop `.padding(.horizontal, 10).padding(.vertical, 5).background(Capsule().fill(Color.secondary.opacity(0.12)))`; apply `.glassChip(cornerRadius: 10)` modifier:

  ```swift
  Button {
      selectFiles()
  } label: {
      HStack(spacing: 4) {
          Image(systemName: "plus").font(.system(size: 12, weight: .medium))
          Text("Add").font(.system(size: 12, weight: .medium))
      }
      .foregroundColor(.secondary)
      .glassChip(cornerRadius: 10)
  }
  .buttonStyle(.plain)
  .help("Add files")
  ```

- [ ] At `:216-237` (Clear button), apply the same fix — `.glassChip(cornerRadius: 10)` replaces the Capsule + manual padding.

- [ ] At `:175-193` (Cancel button), apply `.glassChip(cornerRadius: 10)`. **Foreground color choice (Open Q3):**
  - **Recommended:** `.foregroundColor(.secondary)` — cancel is a passive action; secondary reads correctly inside a glass chip.
  - **Alternative:** `.foregroundColor(Palette.warn)` — preserves "alarming" cue; may read overly warn-tone for what is just a cancel.
  - **Anti-recommendation:** keep `.foregroundColor(.red)` — direct `.red` retired per spec §1.

  ```swift
  Button {
      transcriptionManager.cancelProcessing()
  } label: {
      HStack(spacing: 4) {
          Image(systemName: "stop.fill").font(.system(size: 10, weight: .medium))
          Text("Cancel").font(.system(size: 12, weight: .medium))
      }
      .foregroundColor(.secondary)  // see Open Q3
      .glassChip(cornerRadius: 10)
  }
  .buttonStyle(.plain)
  .help("Cancel transcription")
  ```

- [ ] At `:195-214` (Start button — primary action), restyle. **Style choice (Open Q4):**
  - **Recommended (option A):** Solid `Palette.accent` Capsule + `.white` foreground (mirrors `PermissionCard` CTA at `PermissionsView.swift:163-186`). Drop the `Color(.controlAccentColor)` shadow OR recolor it to `Palette.accentGlow`.
  - **Alternative (option B):** `.glassChip(cornerRadius: 10)` background + `Palette.accent` foreground (chip-vocabulary cohesion with the other 3 topBar pills, but loses the "primary action" hierarchy).

  Recommended (option A) final body:

  ```swift
  Button {
      transcriptionManager.startProcessing(modelContext: modelContext, engine: engine)
  } label: {
      HStack(spacing: 4) {
          Image(systemName: "play.fill").font(.system(size: 10, weight: .medium))
          Text("Start").font(.system(size: 12, weight: .semibold))
      }
      .foregroundColor(.white)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
          Capsule()
              .fill(Palette.accent)
              .shadow(color: Palette.accentGlow, radius: 2, x: 0, y: 1)
      )
  }
  .buttonStyle(.plain)
  ```

- [ ] At `:217` (`withAnimation(.easeInOut(duration: 0.2)) { ... }` for clearAll), replace with `withAnimation(.haloExpand) { ... }`.

**Verify:**
- `rg -n 'Color\(\.controlAccentColor\)' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits.
- `rg -n 'Color\.secondary\.opacity\(0\.12\)' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits.
- `rg -n 'Color\.red\.opacity' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits.
- All 4 topBar action pills render via `glassChip(10)` (or `Palette.accent` Capsule for Start per option A).

### Task 5 — AudioFileRow palette swaps (minimal touch)

**Files:** `VoiceInk/Views/AudioFileRow.swift`.

- [ ] At `:86`, replace `.foregroundColor(.accentColor)` with `.foregroundColor(Palette.accent)`.

- [ ] At `:172`, replace `.foregroundColor(selectedTab == tab ? .accentColor : .secondary)` with `.foregroundColor(selectedTab == tab ? Palette.accent : .secondary)`.

- [ ] DO NOT wrap the row body in `glassPanel()` / `GlassCard` — full chrome rebuild is W13.D's territory (after Form purge). Open Q5.

**Verify:**
- `rg -n 'Color\.accentColor|\.foregroundColor\(\.accentColor\)' VoiceInk/Views/AudioFileRow.swift` returns **0** hits.
- AudioFileRow body byte-identical apart from those two line edits.

### Task 6 — AudioTranscribeView animation token codemod

**Files:** `VoiceInk/Views/AudioTranscribeView.swift`.

- [ ] At `:41` (`onChange(of: lastCompletedItemId)` — `withAnimation(.easeInOut(duration: 0.3))`), replace with `withAnimation(.haloExpand)`.

- [ ] At `:110` (`AudioFileRow.onToggleExpand` — `withAnimation(.easeInOut(duration: 0.2))`), replace with `withAnimation(.haloExpand)`.

- [ ] At `:115` (`AudioFileRow.onRemove` — `withAnimation(.easeInOut(duration: 0.2))`), replace with `withAnimation(.haloExpand)`.

- [ ] At `:217` (already covered in Task 4 — Clear button `withAnimation`), confirm replaced.

- [ ] At `:64` (drop-zone foreground crossfade) and `:296` (dropOverlay crossfade) — already covered in Tasks 2-3. Confirm replaced with `Animation.haloPhaseCrossfade`.

**Verify:**
- `rg -n 'easeInOut\(duration:' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits.
- `rg -n 'spring\(response:' VoiceInk/Views/AudioTranscribeView.swift` returns **0** hits.

### Task 7 — Self-review + grep follow-up

**Files:** none (read-only).

- [ ] Re-run all six axis greps from Task 0. Document remaining hits — they should ALL match this plan's "Defer" or "Flag — preserve" classification.

  Expected post-implementation state:
  - `ultraThinMaterial`: 0 hits in scope.
  - `windowBackgroundColor`: 0 hits in scope.
  - `controlAccentColor`: 0 hits in scope.
  - `accentColor` (bare): 0 hits in `AudioTranscribeView.swift / AudioFileRow.swift / PermissionsView.swift`.
  - `easeInOut(duration:`: 0 hits in scope.
  - `Capsule()`: 1 hit in scope (`AudioTranscribeView.swift` — Start button per Task 4 option A; or 0 if option B chosen).
  - `design: .rounded`: 0 hits in scope (regression guard).

- [ ] Confirm `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift`, `RecorderComponents.swift`, all `Constellation/*.swift`, `Common/CompactHeroSection.swift`, `Common/SettingsSectionHeader.swift`, `Common/SettingsCard.swift`, `Common/StatusPill.swift` (or its host `AI Models/APIKeyManagementView.swift`), `Common/InfoTip.swift` are byte-identical pre/post.

- [ ] Confirm `Animation+Halo.swift` reviewer note at `:14-17` is preserved.

- [ ] Confirm adjacent Permissions-host file `PermissionsView.PermissionsView` body (the outer ScrollView at `:209-300`) is byte-identical pre/post — only `PermissionCard` body changed.

- [ ] Confirm `AudioTranscribeView` queue Form host at `:103-131` is byte-identical pre/post (W13.D defers structural change).

- [ ] Confirm zero new `.rounded` introductions: `rg -n 'design:\s*\.rounded' VoiceInk/Views/PermissionsView.swift VoiceInk/Views/AudioTranscribeView.swift VoiceInk/Views/AudioFileRow.swift` returns 0.

- [ ] Confirm zero new `Color.accentColor` introductions in scope.

### Task 8 — Visual smoke pass (coder + reviewer)

**Files:** none.

- [ ] Open the app via `make local && open VoiceInk.app` (or via Xcode Run). Navigate to:
  - **Permissions tab** (sidebar → Permissions, or first-launch flow).
  - **AudioTranscribe tab** (sidebar → Audio Transcribe).

- [ ] Eyeball under all four mode/wallpaper combos:
  - (a) System Light + bright wallpaper
  - (b) System Light + dark wallpaper
  - (c) System Dark + bright wallpaper
  - (d) System Dark + dark wallpaper

- [ ] **Permissions surface — confirm:**
  - 4 PermissionCards render with GlassCard chrome (HaloMaterial onyx/light adaptive). No raw `.ultraThinMaterial` look, no obsidian-fill rectangle.
  - 14pt corner radius preserved.
  - 20pt outer padding preserved (or adjusted to 14 if smoke-test shows airy — see row 2).
  - Icon tiles still tint `Palette.success` (granted) / `Palette.warn` (needs access). Spec-correct functional tokens.
  - CTA button still solid tangerine capsule (W13.G defers chip-wrap).
  - StatusPill, refresh button untouched.
  - CompactHeroSection icon still `.blue` (W13.G defers).

- [ ] **AudioTranscribe surface (empty state) — confirm:**
  - Drop zone reads as a glass panel against wallpaper (NOT an opaque windowBackgroundColor box).
  - 14pt corner radius (NOT 12pt).
  - Dashed strokeBorder visible at rest in `Palette.hairlineSoft` (white α 0.10) — adjust to `Palette.hairline` if too faint.
  - On hover/drag-target, dashed border + icon tint flip to `Palette.accent` (tangerine, not system blue).
  - Crossfade animation reads at `Animation.haloPhaseCrossfade` cadence (~0.22s easeInOut).
  - "Choose Files" button still system-bordered.

- [ ] **AudioTranscribe surface (queue with at least 2 files) — confirm:**
  - topBar Add / Clear / Cancel pills render via `glassChip(10)` chrome — NOT `Color.secondary.opacity(0.12)` Capsule.
  - topBar Start button — solid tangerine Capsule (option A) or chip-wrapped (option B per Open Q4).
  - Cancel button color: `.secondary` (recommended) / `Palette.warn` (alternative) — see Open Q3.
  - Form { Section { AudioFileRow } } structure intact (W13.D defers).
  - Within `AudioFileRow`, tab indicators + accent text render `Palette.accent`, NOT system blue.
  - Expand/collapse animations read at `Animation.haloExpand` cadence (0.38s spring) — slightly snappier than v1.

- [ ] **Drop overlay (drag a file onto the queue view) — confirm:**
  - Dashed border + fill color tangerine (`Palette.accent`).
  - 14pt corner radius.
  - Crossfade animation `Animation.haloPhaseCrossfade`.

- [ ] **Accessibility passes:**
  - System Settings → Accessibility → Display → Reduce transparency = ON. Re-open both tabs. Glass surfaces fall back to opaque `controlBackgroundColor` per spec §6.4. Both surfaces remain legible.
  - Increase contrast = ON. Hairline strokes become 1pt solid; both surfaces remain legible.
  - Reduce motion = ON. Drop-zone crossfade and expand/collapse animations honor reduce-motion (degrade to 0.18s opacity per `AccessibilityMotionMonitor.shared`).

### Task 9 — Report to lead

- [ ] Coder reports to `team-lead` via SendMessage:
  - File list edited (3 files): `PermissionsView.swift`, `AudioTranscribeView.swift`, `AudioFileRow.swift`.
  - LOC delta (estimate ~70 lines edited, near-zero net new).
  - Smoke-pass observations (any padding / color / animation tweaks made vs. recommendations above).
  - Cancel button color choice landed (Open Q3).
  - Start button style choice landed (Open Q4).
  - Any flagged items left untouched (with reason).
  - Worktree path for lead's `make local` integration build.

- [ ] Lead handles commits per CLAUDE.md cadence:
  ```
  docs(plans): W13C — Permissions + AudioTranscribe styling   (this file)
  feat(aesthetic): W13C — Permissions + AudioTranscribe styling   (the 3 source edits)
  ```

- [ ] After lead's `make local` returns green and the merge commit lands, lead runs the **Post-merge verification protocol** below (user-side).

---

## Verification (coder/reviewer side)

1. **Build green.** `xcodebuild build` (or `make local`) at lead's integration step. Zero warnings, zero errors related to W13.C surfaces.
2. **Grep follow-up clean.** Per Task 7 — all in-scope hits gone; out-of-scope hits unchanged.
3. **Visual smoke green.** Per Task 8 — all four mode/wallpaper combos read tangerine-on-glass; PermissionCard + drop-zone + topBar pills consistent with floating-bar vocabulary.
4. **No primitive drift.** `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` byte-identical pre/post.
5. **No recorder-cluster drift.** `RecorderComponents.swift`, `Constellation/ClusterMotion.swift`, all `Halo*Recorder*` panels byte-identical pre/post.
6. **No adjacent-surface drift.** `Common/CompactHeroSection.swift`, `Common/SettingsCard.swift`, `Common/SettingsSectionHeader.swift`, `Common/InfoTip.swift`, `AI Models/APIKeyManagementView.swift` (StatusPill host) byte-identical pre/post.
7. **No Form host change.** `AudioTranscribeView.swift:103-131` Form { Section { AudioFileRow } } structure byte-identical (W13.D territory).

---

## Rollback plan

Single-commit packet (`feat(aesthetic): W13C — Permissions + AudioTranscribe styling`). If a regression surfaces post-merge:

```bash
git revert <feat-sha>
```

Reverts cleanly because every edit is bounded to three files, no schema migrations, no dependency changes, no test-fixture drift, no spec amendments, no behavioral changes. The `docs(plans): W13C — …` commit can stay (the plan document is reusable across re-attempts).

If a *partial* regression surfaces (e.g. PermissionCard rewrap is fine but the drop-zone retint reads off), rollback the offending file via:

```bash
git checkout <feat-sha>~1 -- VoiceInk/Views/AudioTranscribeView.swift
```

…and re-commit. Preserves the rest of the rebuild.

If the dashed strokeBorder reads too faint at rest under any wallpaper combo, hot-fix is one line: swap `Palette.hairlineSoft` → `Palette.hairline` at the drop-zone overlay site.

If the Cancel button `.secondary` reads too passive (loses the "alarming" cue), hot-fix is one line: swap `.foregroundColor(.secondary)` → `.foregroundColor(Palette.warn)`.

---

## Risks

1. **PermissionCard padding visual rhythm (low).** GlassCard default `padding: 14` is noticeably tighter than the v1 hand-rolled `.padding(20)`. Recommendation: pass `padding: 20` explicitly. Risk: 20pt with the GlassCard's bundled inner spacing reads airy. Mitigation: smoke-test at Task 8; drop to default 14 if needed. Documented in Per-axis row 2.

2. **Drop-zone dashed border contrast at rest (medium).** `Palette.hairlineSoft` (white α 0.10) is the spec-canonical rest hairline. v1 used `.gray.opacity(0.5)` — significantly more visible. On bright wallpapers under System Light, hairlineSoft may read too faint, breaking the "drop here" affordance. Mitigation: smoke-test at Task 8; fall back to `Palette.hairline` (white α 0.16) if marginal. Documented in Task 2 Note 2 + Rollback.

3. **Cancel button color cue (medium).** v1's `.foregroundColor(.red)` is a strong "alarming" cue — conventional for cancel-during-processing. Spec §1 retires direct `.red`. Recommended `.secondary` is passive; `Palette.warn` is amber (alarming but not error-tone). Mitigation: lead picks at sign-off (Open Q3); hot-fix path documented.

4. **Start button hierarchy after chip-swap (medium).** The Start button is the primary action when the queue has pending items. If glassChip-wrapped (option B), it loses the "elevated CTA" hierarchy and reads at the same visual weight as Add/Cancel/Clear. Mitigation: recommend solid `Palette.accent` Capsule (option A — matches PermissionCard CTA pattern). Lead picks at sign-off (Open Q4).

5. **AudioFileRow double-chrome conflict if W13.C wraps row body (low).** Wrapping `AudioFileRow` in `glassPanel()` while the Form host stays would render glass-inside-Form-grouping = visual fight. Mitigation: this plan defers the row chrome rebuild to W13.D entirely. W13.C limits AudioFileRow touch to palette token swaps (`.accentColor` → `Palette.accent` ×2) + animation tokens. Documented in Per-axis rows 22-23 + Open Q5.

6. **Animation token mapping (low).** v1 uses `.easeInOut(duration: 0.15)` (foreground crossfade) and `.easeInOut(duration: 0.2-0.3)` (expand/collapse). Spec §2.4 sanctions four tokens: `.haloExpand` (0.38s spring), `.haloCollapse` (0.42s spring), `.haloBreathe` (1.6s repeating), `.haloPhaseCrossfade` (0.22s easeInOut). This plan maps:
   - 0.15s easeInOut foreground crossfade → `.haloPhaseCrossfade` (closest match — both are easeInOut crossfades).
   - 0.2-0.3s easeInOut expand/collapse → `.haloExpand` (W13.B precedent).
   Risk: the 0.15s → 0.22s shift makes the drop-zone hover feel slightly slower; the 0.2-0.3s → 0.38s shift makes expand/collapse noticeably bouncier. Mitigation: smoke-test at Task 8; if reviewer pushes back on `.haloExpand` for the row expand/collapse (says it feels too bouncy for a row toggle), fall back to `.haloPhaseCrossfade` (0.22s). Open Q6 for lead.

7. **Drop-zone glassPanel vs GlassCard primitive choice (low).** R4 §3 row 17 prescribes `glassPanel(cornerRadius: 14)` for the drop zone. `GlassCard(cornerRadius: 14, padding: 32)` is an alternative — composes the full HaloMaterial stack rather than the lighter glassPanel chip vocabulary. Mitigation: recommend `glassPanel` per R4; coder picks at smoke-test if `GlassCard` reads better against the AudioTranscribe-tab `.adaptiveGlassBackground()` host. Documented in Per-axis row 7. Open Q2.

8. **`Palette.warn` vs `.red` for Cancel during transcription (low).** Cancel during a long-running transcription is destructive-of-progress (loses partial work). v1's `.red` matches the "destructive" mental model. `Palette.warn` is amber — closer to "caution" than "danger." Mitigation: lead picks at sign-off (Open Q3). If lead picks `.warn`, document that VoiceInk's destructive-action color is `.warn` for spec amendment in W13.G.

---

## Open questions for lead

1. **PermissionCard CTA button — keep solid `Palette.accent` capsule or wrap in `glassChip`?** R4 §1 row 6 routes the chip-wrap to W13.G polish. This plan recommends KEEP for W13.C (preserves the "primary action" feel). Lead picks: keep, or pull the polish forward into W13.C.

2. **AudioTranscribe drop-zone primitive — `glassPanel(cornerRadius: 14)` or `GlassCard(cornerRadius: 14)`?** R4 §3 row 17 prescribes `glassPanel`. Coder picks at smoke-test. Lead can pre-lock if a preference exists.

3. **Cancel button foreground — `.secondary` (recommended), `Palette.warn` (alarming cue), or keep `.red`?** Spec §1 retires `.red`. Lead picks. Cancel-during-transcription is destructive-of-progress; `.warn` (amber) is closer to v1's `.red` mental model. `.secondary` is passive but spec-clean.

4. **Start button — solid `Palette.accent` Capsule (option A, mirrors PermissionCard CTA) or `glassChip` + `Palette.accent` foreground (option B, chip-vocabulary cohesion)?** Recommended option A for primary-action hierarchy.

5. **AudioFileRow chrome touch in W13.C — palette + animation tokens only (recommended), or full `glassPanel()` wrap with the Form host still in place?** Recommended palette+anim only; full wrap lands at W13.D when Form is purged. Lead picks.

6. **Animation token mapping — `.haloExpand` (0.38s spring) for the row expand/collapse, or `.haloPhaseCrossfade` (0.22s easeInOut) for the tighter feel?** W13.B precedent uses `.haloExpand` for `spring(0.3, 0.7)` mappings. Row toggle feels closer to a phase-swap than a reveal — Open for lead read.

7. **Drop-zone rest hairline — `Palette.hairlineSoft` (white α 0.10, recommended) or `Palette.hairline` (white α 0.16)?** Pre-spec read says `hairlineSoft` for nested/secondary edges; the dashed drop-zone border at rest IS an active affordance ("drop here") — `hairline` may read better. Smoke-test at Task 8.

---

## Post-merge verification protocol (USER-SIDE)

Run after lead merges `feat(aesthetic): W13C — …` to main and the build is green.

1. **Capture baseline screenshots BEFORE merge** (if not done at sign-off):
   - Permissions tab (default state): 4-card grid screenshot at default window size, system Light + system Dark, on bright + dark wallpaper. (4 screenshots.)
   - AudioTranscribe empty state (no files queued): screenshot at default + during drag-hover (`isDropTargeted = true`). 4 mode/wallpaper combos × 2 states = 8 screenshots.
   - AudioTranscribe with at least 2 files queued: screenshot showing the topBar (Add / Cancel / Start / Clear pills visible) + AudioFileRow expanded. 4 mode/wallpaper combos = 4 screenshots.
   - File these to `docs/superpowers/research/2026-04-30-W13C-pre-merge-screenshots/` for diff reference.

2. **Open the Permissions tab post-merge.** Compare against pre-merge screenshots:
   - 4 PermissionCards render with GlassCard(14) chrome — adaptive onyx/light per wallpaper luminance.
   - Inner content (icon, title, description, refresh button, StatusPill, CTA button) is layout-byte-identical to v1.
   - Outer corner radius 14pt preserved.
   - Outer padding 20pt preserved (or 14pt if smoke-test reduced).
   - CTA button still solid tangerine (W13.G defers chip-wrap).

3. **Open the AudioTranscribe tab (empty state) post-merge:**
   - Drop zone reads as a glass panel against wallpaper.
   - 14pt corner radius (NOT 12pt).
   - Dashed strokeBorder visible at rest in `Palette.hairlineSoft` (or `hairline` if hot-fixed per Risk 2).
   - On drag-target, dashed border + icon tint flip to `Palette.accent` (tangerine) — NOT system blue.

4. **Drag a file onto the AudioTranscribe queue view post-merge:**
   - Drop overlay renders with `Palette.accent` dashed border + `Palette.accent.opacity(0.06)` fill + tangerine "Drop to add files" text.
   - 14pt corner radius.
   - Crossfade animation `Animation.haloPhaseCrossfade` (~0.22s easeInOut).

5. **Add 2+ files to the queue post-merge:**
   - topBar Add / Clear pills render via `glassChip(10)` chrome.
   - topBar Cancel pill — `.secondary` text on glass (or `Palette.warn` if landed per Open Q3).
   - topBar Start pill — solid tangerine Capsule (option A) or glass chip (option B per Open Q4).
   - Form { Section { AudioFileRow } } structure intact.
   - Within AudioFileRow: tab indicators + accent text render `Palette.accent`, NOT system blue.
   - Expand/collapse on row toggle reads at `Animation.haloExpand` cadence — slightly snappier than v1.

6. **Accessibility passes:**
   - System Settings → Accessibility → Display → Reduce transparency = ON. Re-open both tabs. Glass surfaces fall back to opaque `controlBackgroundColor` per spec §6.4. Both tabs remain legible.
   - Increase contrast = ON. Hairline strokes solidify; both tabs remain legible.
   - Reduce motion = ON. Drop-zone crossfade + row expand/collapse honor reduce-motion (~0.18s opacity, no spring).

7. **If any check fails**, surface to lead via SendMessage with screenshot + verbal description. Hot-fix paths in §Rollback.

---

## Follow-ups for adjacent W13 packets

### W13.D — Form-host purge (5 surfaces) — **immediate next**

Cross-references W13.C in two places:
- `AudioTranscribeView.swift:103-131` — Form { Section { AudioFileRow } } purge to `LazyVStack(spacing: 12) { GlassCard }`. After purge, AudioFileRow body wraps in `glassPanel()` for proper row chrome.
- `AudioFileRow.swift` body — full chrome rebuild paired with the Form purge.

W13.D plan should reference W13.C's `AudioFileRow` palette/animation token swaps as already-landed; only the chrome wrap remains.

### W13.E — AI Models card unification

5 model cards + ProviderCard + MLXModelPickerView + WhisperModelManager progress bar. No overlap with W13.C.

### W13.F — History window glass + animation codemod

`HistoryWindowController.createHistoryWindow` non-opaque flip + TranscriptionHistoryView glass + 5× `.smooth(0.3)` codemod. No overlap with W13.C.

### W13.G — Polish

Three W13.C-deferred items land here:
- `Common/CompactHeroSection.swift:13` `.foregroundStyle(.blue)` → `Palette.accent` (touches Permissions + AudioInputSettings + DictionarySettings simultaneously).
- `PermissionsView.PermissionCard` CTA button (R4 row 6) — optional `glassChip` wrap with `Palette.accentMuted` fill.
- `PermissionsView.PermissionCard` icon tile geometry drift (R4 row 7) — realign to `SettingsSectionHeader` constants (7pt rad / 0.16 fill / 0.32 stroke).

Plus: AppNotificationView per-type rainbow → single accent + motion as discriminator. PowerModeView hero header. PromptEditorView trigger chips. EnhancementPromptPopover backdrop. PredefinedPromptsView buttons.

### Final spec extension (after W13.A-G land, per master plan §4 W13.G)

Amend `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.X (or write `2026-04-30-aesthetic-redesign-W13-deltas.md`) with:
- W13.C confirmation: PermissionCard adopts `GlassCard(cornerRadius: 14, padding: 20)`. Drop-zone adopts `glassPanel(cornerRadius: 14)` + `Palette.hairlineSoft`-or-`.accent` dashed strokeBorder. topBar action pills adopt `glassChip(10)`.
- Cancel-button destructive-action color decision (Open Q3 outcome) for spec §1 amendment.
- `Animation.haloPhaseCrossfade` is the canonical mapping for foreground-color crossfades; `Animation.haloExpand` is the canonical mapping for row expand/collapse.
