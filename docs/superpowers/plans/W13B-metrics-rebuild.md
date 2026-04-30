# W13.B — Metrics / Dashboard Rebuild Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` for executing tasks task-by-task. Reviewer: `superpowers:code-reviewer`. Steps use checkbox (`- [ ]`) syntax.

**Date:** 2026-04-30
**Author:** planner-w13b (team `voiceink-phase23`, task #6)
**Scope:** Metrics dashboard surface — `MetricsContent.heroSection`, `MetricCard`, `HelpAndResourcesSection`. The first surface a new user sees post-install. Per R4 the worst aesthetic-cohesion offender in the app.

**Sources of truth:**
- R4 audit (the WHY): `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md` §1 row 1, §3 rows 1-4, §3.1, §5 Qs 3-4-6.
- Spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (tokens, glass primitive, motion grammar), §1.X (W8 wallpaper-glass contract), §2.4 (motion tokens), §6.4 (Reduce-Transparency / Increase-Contrast contract).
- Master plan §0 Q9=a (locked decision — keep hero gradient identity, swap source color to `Palette.accent`) and §4 W13.B (4-bullet scope): `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`.
- Sibling shape (mirrored exactly): `docs/superpowers/plans/W13A-token-sweep.md` — including its per-axis Sweep/Defer/Flag table and Migration policy section.
- Vocabulary primitives: `Palette.swift`, `GlassCard.swift`, `GlassChip.swift` (glassChip / glassPanel modifiers), `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` (under `VoiceInk/Views/`).

**Goal:** Every Metrics / Dashboard surface speaks the same vocabulary as the floating recorder cluster (per spec §1, §1.X, §2.4) — without losing the hero gradient's signature. Post-merge a new user opens the app, sees a tangerine-on-glass dashboard whose visual language is indistinguishable from the recorder cluster + Settings reskin (W5).

**Locked decisions honored:**
- **Q9=a** — preserve hero gradient SHAPE (linear, three-stop, .topLeading→.bottomTrailing), preserve hero corner radius (24pt — the hero's signature, not a regular panel), preserve hero animation behavior. **Only the gradient's source color changes** from `Color(nsColor: .controlAccentColor)` to `Palette.accent`. (Master plan §0; team-lead brief 2026-04-30.)
- **Q4=b (R4 §5 Q4)** — single `Palette.accent` icon tint across all four MetricCards. Motion of metric value updates carries the discriminator (per team-lead brief). Functional-token differentiation (accent/success/neutral per R4 §5 Q4 option b) listed as Open Question for lead — recommended `Palette.accent`-only.

---

## Prelude — packet shape + commit etiquette

**Shape.** Single coder + reviewer pair under team `voiceink-phase23` post-sign-off. Diff is bounded to three Swift files (`MetricsContent.swift`, `MetricCard.swift`, `HelpAndResourcesSection.swift`) plus this plan file. Estimated total LOC delta: ~80 lines of edits, ~zero net new lines. No new files. No new SPM deps. No new tokens beyond what `Palette.swift` already exposes. No deployment-target change (already 26.0 per W11.B). No test-infra change (Q10 deferred).

**Commit cadence per `feedback_skip_per_packet_builds.md`.** Coder leaves edits uncommitted in the worktree. Lead runs single integration `make local` at merge time and commits:
```
docs(plans): W13B — Metrics / Dashboard rebuild
feat(aesthetic): W13B — Metrics / Dashboard rebuild
```
Coder does NOT commit. Coder does NOT run `xcodebuild` per task. The integration build is the gate.

**Worktree convention.** Spawn at `.worktrees/w13b/` ABSOLUTE path. Always `cd <main-repo>` before `git worktree add` to avoid cwd-drift (lead has been bitten by this).

**Comment policy.** Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code. Inline doc-comments may cite spec §1.X / §2.4 + this plan path. Pre-existing spec-ref comments preserved.

**Visual verification.** This packet is verified by **screenshot diff**, not by automated tests (no visual-diff CI exists). The user runs the post-merge protocol in §Post-merge verification. Coder + reviewer eyeball the build locally.

---

## Per-axis Sweep / Defer / Flag table

Mirrors W13.A's shape. Each row is one axis × one surface; disposition is **Sweep** (land in W13.B), **Defer** (route to W13.C-G), or **Flag** (ambiguous; coder evaluates context, sweeps if obvious or leaves with comment).

| # | Surface | File:line | Axis | Current | W13.B Action | Disposition | Rationale |
|---|---|---|---|---|---|---|---|
| 1 | `MetricsContent.heroSection` background gradient | `Metrics/MetricsContent.swift:248-258` (3 stops) + `:181` (call site) | color | `Color(nsColor: .controlAccentColor)` × 3 stops with α 1.0 / 0.85 / 0.70 | `Palette.accent` × 3 stops with α 1.0 / 0.85 / 0.70 | **Sweep** | Q9=a — gradient SHAPE preserved (.topLeading→.bottomTrailing, three-stop, same alphas). Source color only. |
| 2 | `MetricsContent.heroSection` border stroke | `Metrics/MetricsContent.swift:184-186` | color (hairline) | `Color.white.opacity(0.1).strokeBorder(lineWidth: 1)` | `Palette.hairlineSoft` (= `white α 0.10`) | **Sweep** | exact 0.10 hairline-soft; vocabulary alignment with spec §1 |
| 3 | `MetricsContent.heroSection` corner radius | `Metrics/MetricsContent.swift:180, 184` | geometry | `RoundedRectangle(cornerRadius: 24)` | KEEP — 24pt (hero signature, not a regular panel) | **Flag — preserve** | Q9=a SHAPE preservation. Spec §1 caps regular panels at 14pt; the hero is hand-rolled chrome, not a `GlassCard` instance. Documented exception. |
| 4 | `MetricsContent.heroSection` drop shadow | `Metrics/MetricsContent.swift:187` | shadow | `.shadow(color: Color.black.opacity(0.08), radius: 30, x: 0, y: 16)` | KEEP — preserves hero depth signature | **Flag — preserve** | Q9=a — hero card depth is part of the gradient look; shadow color/blur align with broad "soft drop on hero" idiom. Not aligned with HaloMaterial onyx-shadow (radius 14, y 6, α 0.45) — acceptable because hero is NOT a HaloMaterial-backed card. |
| 5 | `MetricsContent.heroSection` body text foreground | `Metrics/MetricsContent.swift:151, 156, 160, 172` | color (text on accent) | `Color.white.opacity(0.85)` (3×) + `.foregroundStyle(.white)` (1×) | KEEP — white-on-tangerine reads. Track contrast at smoke-test (tangerine #FF5B3A is mid-saturation, white α 0.85 reads ~4.0 contrast — pass-with-margin) | **Flag — preserve, smoke-test** | Per R4 §5 Q3 the gradient identity reads as "celebratory" with white text. Visual smoke at Task 7 is the gate. If contrast reads marginal under the new tangerine, fall back to `Palette.onyxFg` (#EDEDF0). |
| 6 | `MetricsContent.heroSection` formatted-time-saved font | `Metrics/MetricsContent.swift:155` | font (design: .rounded) | `.font(.system(size: 36, design: .rounded))` | `.font(.system(size: 36))` (drop `design: .rounded`) | **Sweep** | Spec §1 / §5#9 — `.rounded` retired outside recorder cluster. Team-lead brief 2026-04-30 explicit: "Drop `.rounded` font usage from this surface entirely." Overrides W13.A's preserve-disposition (W13.A's "KEEP per Q9" was over-cautious; Q9 only locks gradient, not type). |
| 7 | `MetricsContent.heroSection` size-30 outer text font | `Metrics/MetricsContent.swift:162` | font | `.font(.system(size: 30))` | KEEP — already system default, no `design:` modifier | **Flag — verify, no edit** | Already spec-compliant. |
| 8 | `MetricCard` background material | `Metrics/MetricCard.swift:46-49` | material | `RoundedRectangle(cornerRadius: 16) + .fill(.thinMaterial)` | Wrap card content with `GlassCard(cornerRadius: 16)` (drops the hand-rolled rect+thinMaterial stack entirely; GlassCard composes `HaloMaterial(phase: .hidden)` per spec §1, §2.3) | **Sweep** | spec §1 / R4 §3 row 2; one of W13.B's four canonical bullets per master plan §4. |
| 9 | `MetricCard` icon tile fill | `Metrics/MetricCard.swift:14-15` | color (per-card rainbow) | `RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.15))` (where `color` is `.purple / .yellow / .orange / .controlAccentColor` per call site) | `Palette.accent.opacity(0.15)` — single accent across all four cards | **Sweep** | spec §1 — rainbow palette retired. Brief 2026-04-30: "Tint icons via Palette.accent ... motion of metric value updates can carry the discriminator." |
| 10 | `MetricCard` icon foreground | `Metrics/MetricCard.swift:20` | color (per-card rainbow) | `.foregroundColor(color)` | `.foregroundColor(Palette.accent)` | **Sweep** | same row 9 rationale |
| 11 | `MetricCard` value font | `Metrics/MetricCard.swift:31` | font (design: .rounded) | `.font(.system(size: 24, weight: .black, design: .rounded))` | `.font(.system(size: 24, weight: .black))` (drop `design: .rounded`) | **Sweep** | same row 6 rationale — brief explicit drop |
| 12 | `MetricCard` icon tile geometry | `Metrics/MetricCard.swift:14, 22` | geometry | 10pt radius / 34×34 size | KEEP — 10pt matches `SettingsRow` icon tile (6pt at 16×16 / 0.16 fill); 34×34 is the metric-card scale | **Flag — preserve** | spec §2.5 / `SettingsRow.swift:54-68` — 10pt-rad icon tile at metric-card scale is a reasonable mirror; not blocking. |
| 13 | MetricsContent metricsSection per-card `color:` argument | `Metrics/MetricsContent.swift:198, 205, 215, 223` | color (rainbow) | `color: .purple` / `color: Color(nsColor: .controlAccentColor)` / `color: .yellow` / `color: .orange` | Drop the `color:` argument entirely from `MetricCard` initializer (signature change; only call sites are these 4) — OR keep signature and pass `Palette.accent` × 4. **Recommended: drop the parameter.** | **Sweep** | spec §1; eliminates the rainbow plumbing at the type level so a future call-site can't reintroduce it. Coder's call: signature change is preferred (cleaner) but acceptable to keep + pass accent if signature change feels like scope drift. |
| 14 | `HelpAndResourcesSection` outer card background | `Metrics/HelpAndResourcesSection.swift:39-46` | material + corner radius | `RoundedRectangle(cornerRadius: 28).fill(Color(nsColor: .windowBackgroundColor))` + `Color.primary.opacity(0.1)` 1pt stroke | `.glassPanel(cornerRadius: 16)` (or wrap content in `GlassCard(cornerRadius: 16)` — coder picks per surface fit; recommend `glassPanel()` for the lighter footprint) | **Sweep** | spec §1 (panel cap 14-16pt; 28pt explicitly retired per audit row 3); R4 §3 row 3; one of W13.B's four canonical bullets per master plan §4. |
| 15 | `HelpAndResourcesSection` inner link rows background | `Metrics/HelpAndResourcesSection.swift:73-74` | material + corner radius | `Color.primary.opacity(0.05)` fill + `RoundedRectangle(cornerRadius: 12)` clip | `.glassChip(cornerRadius: 10)` (matches spec §1 chip vocabulary; replaces the inline 0.05-opacity backplate) | **Sweep** | spec §1 — chip radius is 10pt; R4 §3 row 3 second-half fix. |
| 16 | `HelpAndResourcesSection` link icon foreground | `Metrics/HelpAndResourcesSection.swift:60` | color | `.foregroundColor(.accentColor)` | `.foregroundColor(Palette.accent)` | **Sweep** | spec §1 — `Color.accentColor` (system blue default) → tangerine token. |
| 17 | `HelpAndResourcesSection` body title font | `Metrics/HelpAndResourcesSection.swift:6-7` | font | `Text("Help & Resources").font(.system(size: 20, weight: .bold)).foregroundColor(.primary.opacity(0.8))` | `SettingsSectionHeader(title: "Help & Resources", systemImage: "book.fill", accent: Palette.accent)` — OR keep current text but recolor to `Palette.onyxFg` if SettingsSectionHeader doesn't fit visually | **Flag — coder evaluates** | spec §3.3 + `SettingsSectionHeader.swift` — section headers should use the unified primitive. Coder confirms SettingsSectionHeader's signature matches; if not, leave the inline header but drop the bold-on-0.8-primary opacity (just `.foregroundColor(.primary)`). |
| 18 | `CopySystemInfoButton` background | `Metrics/MetricsContent.swift:332` | material | `Capsule().fill(.thinMaterial)` | `.glassChip(cornerRadius: 999)` (use Capsule shape via large radius — GlassChip clips to RoundedRectangle which approximates Capsule at large radius). Actually: `glassChip()` takes a corner radius parameter; for true Capsule shape, Coder's call: either accept a `RoundedRectangle(cornerRadius: 999)` approximation via `glassChip(cornerRadius: 999)`, OR leave as `.thinMaterial` + flag for spec amendment to add a `.capsule` variant of glassChip. **Recommended: `glassChip(cornerRadius: 18)`** (button height ~36pt; 18pt-rad reads as capsule at this scale and stays within spec radius range). | **Sweep — coder picks radius** | R4 §3 row 4 — `.thinMaterial` capsule is a hand-rolled glass chip. Use the primitive. Stay within spec radius range (≤16pt panel, 10pt chip; 18pt is a soft pill that reads as capsule). |
| 19 | `CopySystemInfoButton` animation literals | `Metrics/MetricsContent.swift:324, 327, 336, 342, 347` (5×) | animation grammar | `.spring(response: 0.3, dampingFraction: 0.7)` (5 instances — copy-icon rotation, copy-text label, scaleEffect, withAnimation isCopied=true, withAnimation isCopied=false) | `Animation.haloExpand` (5×) | **Sweep** | spec §2.4; W13.A migration policy table maps `spring(0.3, 0.7)` → `haloExpand` ("reveal axis"). |
| 20 | `MetricsContent.emptyStateView` waveform icon | `Metrics/MetricsContent.swift:131-138` | font + color | `.font(.system(size: 56, weight: .semibold))` + `.foregroundColor(.secondary)` | KEEP — pre-data state, not a dashboard surface; .secondary text is system-adaptive and reads correctly | **Flag — preserve** | Empty state is a legitimate "before any metric exists" path. Not part of the rebuild scope. If lead wants polish, this routes to W13.G. |
| 21 | MetricsContent ScrollView padding rhythm | `Metrics/MetricsContent.swift:38-39` | geometry | `.padding(.vertical, 28).padding(.horizontal, 32)` | KEEP | **Flag — preserve** | spec §2.7 / R4 §2.2 — MetricsContent ScrollView 28v/32h is the canonical metric-pane padding. |

### Deferred (route to other W13 packets)

| File | Why deferred |
|---|---|
| `Metrics/MetricsSetupView.swift` (welcome/setup flow — `controlBackgroundColor` + accent buttons + 28pt `.rounded`) | **Adjacent surface — recommend split out as sibling W13.B2 packet** (or fold into W13.G polish). Master plan §4 W13.B's 4 bullets do NOT include MetricsSetupView. W13.A defers it to W13.B but team-lead brief 2026-04-30 says "do NOT widen scope — Optional within scope if W13.A notes it as deferred-here." See Open Question 4. |
| `Metrics/PerformanceAnalysisView.swift` + `Metrics/PerformanceAnalysisPanelView.swift` (`windowBackgroundColor` pane chrome + `.rounded` numerals KEEP per W7) | **Adjacent surface — recommend split out as sibling W13.B3 packet.** Same Open Question 4 rationale. Charts surfaces have a separate spec §1.X rule (W8 OOS: "Charts hosts — opaque bg required for chart legibility") so the rebuild here is non-trivial. |
| `Metrics/MetricsContent.swift:155` (.rounded hero numeral) | NOT deferred — **swept** per row 6 above. (W13.A had this preserved; team-lead brief overrides.) |

### Flagged (no edit — context-eval at coder review)

| Item | Reason |
|---|---|
| Hero corner radius 24pt vs spec's 14-16pt cap | Q9=a hero exception — hand-rolled chrome, not a regular panel (row 3) |
| Hero drop-shadow params | Q9=a hero exception (row 4) |
| Hero white-on-tangerine text contrast | Visual smoke at Task 7 is the gate (row 5) |
| Empty-state view (waveform icon, .secondary text) | Pre-data path; not in scope (row 20) |

---

## Tasks

### Task 0 — Audit + grep validation (read-only)

**Files:** none.

- [ ] Re-run `rg` for the W13.B target patterns and confirm hit counts match this plan's Per-axis table:

  ```bash
  # Hero gradient call sites
  rg -n 'controlAccentColor' VoiceInk/Views/Metrics/

  # MetricCard rainbow palette
  rg -n 'color: \.(purple|yellow|orange)' VoiceInk/Views/Metrics/

  # .rounded in Metrics
  rg -n 'design:\s*\.rounded' VoiceInk/Views/Metrics/

  # Hand-rolled materials in Metrics
  rg -n '\.thinMaterial|\.ultraThinMaterial' VoiceInk/Views/Metrics/

  # window/control background opacity in Metrics
  rg -n 'windowBackgroundColor|controlBackgroundColor' VoiceInk/Views/Metrics/

  # Spring 0.3, 0.7 in MetricsContent
  rg -n 'spring\(response: 0\.3, dampingFraction: 0\.7\)' VoiceInk/Views/Metrics/
  ```

  Expected hit counts (from this plan):
  - `controlAccentColor` in Metrics/: **3** (MetricsContent.swift:251, 252, 253) + 1 call site (MetricsContent.swift:205 inside metricsSection — counts in rainbow grep too).
  - rainbow `.purple/.yellow/.orange`: **3** in MetricsContent.swift (198, 215, 223).
  - `design: .rounded` in Metrics: **2** in scope (MetricsContent.swift:155, MetricCard.swift:31). The other 7 hits (MetricsSetupView, PerformanceAnalysis*) are out-of-scope for W13.B (deferred).
  - `.thinMaterial`: **2** in scope (MetricCard.swift:48, MetricsContent.swift:332). HelpAndResourcesSection uses `Color(nsColor: .windowBackgroundColor)`, not thinMaterial.
  - `windowBackgroundColor`: **1** in scope (HelpAndResourcesSection.swift:41). MetricsSetupView and PerformanceAnalysis* hits are out-of-scope.
  - `spring(response: 0.3, dampingFraction: 0.7)`: **5** in MetricsContent.swift (CopySystemInfoButton at 324, 327, 336, 342, 347).

- [ ] If hit counts differ, escalate to lead before drafting edits. Do not drift the scope.

- [ ] Read `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift` in full to confirm the primitive APIs the edits below assume:
  - `GlassCard(cornerRadius:padding:appearance:)` — `cornerRadius` defaults to 16, `padding` to 14, `appearance` defaults to `nil` (resolves to `GlassAppearanceDetector.shared.current`). Content is a `@ViewBuilder` closure.
  - `.glassChip(cornerRadius:)` — modifier; default 10pt; padded 11h/7v.
  - `.glassPanel(cornerRadius:)` — modifier; default 14pt; padded 14h/12v.
  - `Palette.accent`, `Palette.hairline`, `Palette.hairlineSoft`, `Palette.innerHi`, `Palette.onyxFg`, `Palette.accentMuted` available.
  - `Animation.haloExpand`, `.haloCollapse`, `.haloPhaseCrossfade` available.

### Task 1 — heroSection gradient retint (Q9=a)

**Files:** `VoiceInk/Views/Metrics/MetricsContent.swift`.

- [ ] At `MetricsContent.swift:248-258`, replace the three `Color(nsColor: .controlAccentColor)` gradient stops with `Palette.accent`. Preserve alpha stepping (1.0 / 0.85 / 0.70), preserve `.topLeading → .bottomTrailing` direction. Final body:

  ```swift
  private var heroGradient: LinearGradient {
      LinearGradient(
          gradient: Gradient(colors: [
              Palette.accent,
              Palette.accent.opacity(0.85),
              Palette.accent.opacity(0.70)
          ]),
          startPoint: .topLeading,
          endPoint: .bottomTrailing
      )
  }
  ```

- [ ] At `MetricsContent.swift:185`, swap `Color.white.opacity(0.1)` → `Palette.hairlineSoft`. Preserve `.strokeBorder(... lineWidth: 1)`.

- [ ] At `MetricsContent.swift:155`, drop `design: .rounded`:

  ```swift
  .font(.system(size: 36))
  ```

- [ ] PRESERVE `.shadow(color: Color.black.opacity(0.08), radius: 30, x: 0, y: 16)` at `:187` (Q9=a hero signature).

- [ ] PRESERVE `RoundedRectangle(cornerRadius: 24, style: .continuous)` at `:180, :184` (Q9=a hero signature).

- [ ] PRESERVE all four `Color.white.opacity(0.85)` body-text foregrounds (`:151, :160, :172`) and `.foregroundStyle(.white)` at `:156` — white text on tangerine is the celebratory hero look. Smoke-test at Task 7 confirms contrast reads OK.

**Verify:**
- Gradient SHAPE identical pre/post (linear, three-stop, .topLeading→.bottomTrailing).
- Source color shifted from system-blue to `Palette.accent` (#FF5B3A tangerine).
- `design: .rounded` no longer present in heroSection.
- 24pt corner radius and 30/(0,16)/black α0.08 shadow byte-identical pre/post.

### Task 2 — MetricCard → GlassCard wrap

**Files:** `VoiceInk/Views/Metrics/MetricCard.swift`.

- [ ] Replace the hand-rolled `RoundedRectangle(cornerRadius: 16) + .fill(.thinMaterial)` background stack at `:46-49` with a `GlassCard(cornerRadius: 16)` wrapper around the existing VStack content. Final body skeleton:

  ```swift
  var body: some View {
      GlassCard(cornerRadius: 16) {
          VStack(alignment: .leading, spacing: 12) {
              HStack(alignment: .center, spacing: 12) {
                  ZStack {
                      RoundedRectangle(cornerRadius: 10, style: .continuous)
                          .fill(Palette.accent.opacity(0.15))
                      Image(systemName: icon)
                          .resizable()
                          .scaledToFit()
                          .frame(width: 18, height: 18)
                          .foregroundColor(Palette.accent)
                  }
                  .frame(width: 34, height: 34)

                  Text(title)
                      .font(.system(size: 13, weight: .semibold))
                      .lineLimit(1)
                      .minimumScaleFactor(0.8)
              }

              Text(value)
                  .font(.system(size: 24, weight: .black))
                  .lineLimit(1)
                  .minimumScaleFactor(0.6)

              if let detail, !detail.isEmpty {
                  Text(detail)
                      .font(.system(size: 11))
                      .foregroundColor(.secondary)
                      .lineLimit(2)
                      .multilineTextAlignment(.leading)
                      .fixedSize(horizontal: false, vertical: true)
              }
          }
          .frame(maxWidth: .infinity, alignment: .topLeading)
      }
  }
  ```

- [ ] Drop the `let color: Color` stored property (and remove the now-unused `color:` initializer parameter — see Task 4 for the call-site updates). Keep `icon`, `title`, `value`, `detail`. **Recommended:** signature change. **Acceptable fallback:** keep `color: Color` parameter, ignore at body, mark deprecated — only if signature change feels like drift.

- [ ] Drop `design: .rounded` from value font at `:31`. Keep `weight: .black` and `size: 24`.

- [ ] PRESERVE the icon-tile geometry: 10pt radius, 34×34 outer frame, 18×18 inner symbol. Spec-aligned per `SettingsRow.swift:54-68`.

- [ ] PRESERVE the outer `.padding(16)` (now redundant — GlassCard's default padding is 14, plus 16 from VStack-internal — confirm visual rhythm at smoke-test). **If padding feels heavy:** drop the outer `.padding(16)` since `GlassCard(cornerRadius: 16)` already pads 14pt by default. Default to keep, smoke-test, drop if oversized.

  *Note:* Re-reading the audit fix (R4 §3 row 2): "Replace `RoundedRectangle 16pt + .thinMaterial` with `GlassCard(cornerRadius: 16, padding: 16)`". Coder picks the padding value at smoke-test — `padding: 16` matches the original feel; `padding: 14` (GlassCard default) is the spec-canonical default.

**Verify:**
- `MetricCard.swift` no longer references `.thinMaterial`, `RoundedRectangle ... .fill(.thinMaterial)`, or `design: .rounded`.
- All four metric cards in the dashboard render with HaloMaterial(phase: .hidden) chrome (onyx/light adaptive via `GlassAppearanceDetector`).
- Icon tile is `Palette.accent.opacity(0.15)` fill + `Palette.accent` foreground for ALL four cards (no rainbow).

### Task 3 — Drop rainbow per-card icon palette + signature

**Files:** `VoiceInk/Views/Metrics/MetricsContent.swift`.

- [ ] At `MetricsContent.swift:192-225` (`metricsSection`), update the four `MetricCard(...)` call sites to drop the `color:` argument (matching Task 2's signature change):

  ```swift
  MetricCard(icon: "mic.fill",          title: "Sessions Recorded", value: "\(totalCount)", detail: "VoiceInk sessions completed")
  MetricCard(icon: "text.alignleft",    title: "Words Dictated",    value: Formatters.formattedNumber(totalWords), detail: "words generated")
  MetricCard(icon: "speedometer",       title: "Words Per Minute",  value: averageWordsPerMinute > 0 ? String(format: "%.1f", averageWordsPerMinute) : "–", detail: "VoiceInk vs. typing by hand")
  MetricCard(icon: "keyboard.fill",     title: "Keystrokes Saved",  value: Formatters.formattedNumber(totalKeystrokesSaved), detail: "fewer keystrokes")
  ```

- [ ] **Acceptable alternative if Task 2 kept the `color:` parameter:** pass `color: Palette.accent` × 4 instead of dropping the argument. Body-side ignore is the same; signature stability is the trade.

**Verify:**
- `rg -n 'color: \.(purple|yellow|orange)' VoiceInk/Views/Metrics/` returns **0** hits.
- `rg -n 'controlAccentColor' VoiceInk/Views/Metrics/` returns **0** hits.

### Task 4 — CopySystemInfoButton chrome + animation codemod

**Files:** `VoiceInk/Views/Metrics/MetricsContent.swift`.

- [ ] At `MetricsContent.swift:332`, replace `Capsule().fill(.thinMaterial)` background with `.glassChip(cornerRadius: 18)` modifier (recommended). Final body skeleton for the button label:

  ```swift
  HStack(spacing: 8) {
      Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
          .rotationEffect(.degrees(isCopied ? 360 : 0))
          .animation(.haloExpand, value: isCopied)

      Text(isCopied ? "Copied!" : "Copy System Info")
          .animation(.haloExpand, value: isCopied)
  }
  .font(.system(size: 13, weight: .medium))
  .glassChip(cornerRadius: 18)
  ```

  *Note:* `.glassChip(cornerRadius: 18)` includes its own padding (11h/7v) — drop the existing `.padding(.horizontal, 12).padding(.vertical, 8)` calls since the modifier already pads. If visual rhythm feels off (button reads smaller than v1), restore the outer padding as `.padding(.horizontal, 4)` to add ~4pt extra horizontal breathing room.

- [ ] At `:324, :327, :336, :342, :347` — replace all 5× `.spring(response: 0.3, dampingFraction: 0.7)` with `Animation.haloExpand`. Both forms hit:
  - `.animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCopied)` (3×) → `.animation(.haloExpand, value: isCopied)`
  - `withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { ... }` (2×) → `withAnimation(.haloExpand) { ... }`

**Verify:**
- `rg -n 'spring\(response: 0\.3, dampingFraction: 0\.7\)' VoiceInk/Views/Metrics/MetricsContent.swift` returns **0** hits.
- `rg -n '\.thinMaterial' VoiceInk/Views/Metrics/MetricsContent.swift` returns **0** hits.
- Button reads as a glass capsule against the dashboard scroll view.

### Task 5 — HelpAndResourcesSection rebuild

**Files:** `VoiceInk/Views/Metrics/HelpAndResourcesSection.swift`.

- [ ] Replace the outer `VStack(spacing: 14) { ... }.padding(18).background(RoundedRectangle(cornerRadius: 28).fill(.windowBackgroundColor)).overlay(.stroke(.primary.opacity(0.1)))` stack at `:38-46` with a `.glassPanel(cornerRadius: 16)` modifier on the inner content. Recommended final body:

  ```swift
  var body: some View {
      VStack(alignment: .leading, spacing: 14) {
          Text("Help & Resources")
              .font(.system(size: 20, weight: .bold))
              .foregroundColor(.primary)

          VStack(alignment: .leading, spacing: 10) {
              resourceLink(...)
              resourceLink(...)
              resourceLink(...)
              resourceLink(...)
          }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .glassPanel(cornerRadius: 16)
  }
  ```

  *Note:* `glassPanel(cornerRadius: 16)` adds 14h/12v padding via the modifier — replaces the explicit `.padding(18)`. Coder confirms visual rhythm at smoke-test; if 14h/12v reads tight against the 4 link rows, alternative is wrapping in `GlassCard(cornerRadius: 16, padding: 18)` for the v1-equivalent padding.

- [ ] Drop `Color.primary.opacity(0.8)` on the title text — `glassPanel` already handles foreground contrast via the inner-stroke + onyx fill. Use `Color.primary` (system-adaptive) or `Palette.onyxFg` (force onyx) — coder picks, default `.primary` for system adaptiveness.

- [ ] At `HelpAndResourcesSection.swift:60`, swap `.foregroundColor(.accentColor)` → `.foregroundColor(Palette.accent)`.

- [ ] At `:73-74`, replace the inline link-row backplate with `.glassChip(cornerRadius: 10)`:

  ```swift
  HStack {
      Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundColor(Palette.accent).frame(width: 20)
      Text(title).font(.system(size: 13)).fontWeight(.semibold)
      Spacer()
      Image(systemName: "arrow.up.right").foregroundColor(.secondary)
  }
  .glassChip(cornerRadius: 10)
  ```

  *Note:* `.glassChip(cornerRadius: 10)` adds 11h/7v padding — replaces the explicit `.padding(12)`. Smoke-test at Task 7.

**Verify:**
- `rg -n 'windowBackgroundColor' VoiceInk/Views/Metrics/HelpAndResourcesSection.swift` returns **0** hits.
- `rg -n 'accentColor' VoiceInk/Views/Metrics/HelpAndResourcesSection.swift` returns **0** hits (Palette.accent doesn't match this pattern).
- 28pt radius gone — outer wrapper now reads as a 16pt panel.
- Inner link rows are GlassChip(10pt) — match spec §1 chip radius.

### Task 6 — Self-review + grep follow-up

**Files:** none (read-only).

- [ ] Re-run all six axis greps from Task 0. Document remaining hits — they should ALL match this plan's "Defer" or "Flag — preserve" classification.

- [ ] Confirm `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift`, `RecorderComponents.swift`, all `Constellation/*.swift` are byte-identical pre/post.

- [ ] Confirm `Animation+Halo.swift` reviewer note at `:14-17` (the "every numeric in this file is a spec constant" note) is preserved — should be untouched since W13.B doesn't edit that file.

- [ ] Confirm MetricsSetupView, PerformanceAnalysisView, PerformanceAnalysisPanelView are byte-identical pre/post (these are deferred per §Per-axis table).

- [ ] Confirm zero new `.rounded` introductions (regression guard): `rg -n 'design:\s*\.rounded' VoiceInk/Views/Metrics/` returns 7 hits, all in MetricsSetupView (1) + PerformanceAnalysisView (3) + PerformanceAnalysisPanelView (3) — all OUT of W13.B scope.

### Task 7 — Visual smoke pass (coder + reviewer)

**Files:** none.

- [ ] Open the app via `make local && open VoiceInk.app` (or via Xcode Run). Navigate to the Metrics dashboard tab.

- [ ] Eyeball under all four mode/wallpaper combos:
  - (a) System Light + bright wallpaper
  - (b) System Light + dark wallpaper
  - (c) System Dark + bright wallpaper
  - (d) System Dark + dark wallpaper

- [ ] Confirm:
  - Hero gradient SHAPE matches v1 (linear, .topLeading→.bottomTrailing, three-stop with α 1.0/0.85/0.70). Color is tangerine (#FF5B3A), not system blue.
  - Hero white text reads with adequate contrast against the tangerine. If marginal under any combo, fall back to `Palette.onyxFg` (#EDEDF0) — flag at sign-off, do not silently change.
  - Hero corner radius is 24pt (signature shape preserved per Q9=a).
  - Four metric cards show GlassCard chrome (onyx/light adaptive) — no `.thinMaterial`-blue, no opaque white-on-light backplate.
  - All four icon tiles tint with `Palette.accent` (no purple, yellow, orange, system-blue).
  - All four metric value numerals render in system default (NOT `.rounded`).
  - Help & Resources panel reads as a glass panel — NOT an opaque windowBackgroundColor box. 16pt corner radius (NOT 28pt). Inner link rows are 10pt-rad chips with tangerine icons.
  - Copy System Info button is a glass capsule with tangerine animation.

- [ ] Confirm under Reduce-Transparency (System Settings → Accessibility → Display → Reduce transparency = ON) and Increase-Contrast (Increase contrast = ON), the dashboard remains legible. (`AdaptiveGlassBackground` and `HaloMaterial` both branch to opaque under these flags per spec §6.4.)

- [ ] Confirm under Reduce Motion (Accessibility → Display → Reduce motion = ON), the CopySystemInfoButton no longer scales/rotates aggressively. (`Animation.haloExpand` is a spring; SwiftUI's `accessibilityReduceMotion` honor depends on the call site — verify at smoke-test.)

### Task 8 — Report to lead

- [ ] Coder reports to `team-lead` via SendMessage:
  - File list edited (3 files): `MetricsContent.swift`, `MetricCard.swift`, `HelpAndResourcesSection.swift`.
  - LOC delta (estimate ~80 lines edited, near-zero net new).
  - Smoke-pass observations (any contrast/padding tweaks made vs. recommendations above).
  - Any flagged items left untouched (with reason).
  - Worktree path for lead's `make local` integration build.

- [ ] Lead handles commits per CLAUDE.md cadence:
  ```
  docs(plans): W13B — Metrics / Dashboard rebuild   (this file)
  feat(aesthetic): W13B — Metrics / Dashboard rebuild   (the 3 source edits)
  ```

- [ ] After lead's `make local` returns green and the merge commit lands, lead runs the **Post-merge verification protocol** below (user-side).

---

## Verification (coder/reviewer side)

1. **Build green.** `xcodebuild build` (or `make local`) at lead's integration step. Zero warnings, zero errors related to W13.B surfaces.
2. **Grep follow-up clean.** Per Task 6 — all in-scope hits gone; out-of-scope hits unchanged.
3. **Visual smoke green.** Per Task 7 — all four mode/wallpaper combos read tangerine-on-glass, gradient identity preserved.
4. **No primitive drift.** `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` byte-identical pre/post.
5. **No recorder-cluster drift.** `RecorderComponents.swift`, `Constellation/ClusterMotion.swift`, all `Halo*Recorder*` panels byte-identical pre/post.
6. **No adjacent-Metrics drift.** `MetricsSetupView.swift`, `PerformanceAnalysisView.swift`, `PerformanceAnalysisPanelView.swift` byte-identical pre/post (those route to W13.B2/B3 sibling packets per Open Question 4).

---

## Rollback plan

Single-commit packet (`feat(aesthetic): W13B — Metrics / Dashboard rebuild`). If a regression surfaces post-merge:

```bash
git revert <feat-sha>
```

Reverts cleanly because every edit is bounded to three files, no schema migrations, no dependency changes, no test-fixture drift, no spec amendments. The `docs(plans): W13B — …` commit can stay (the plan document is reusable across re-attempts).

If a *partial* regression surfaces (e.g. the hero gradient retint reads off but the MetricCard rewrap is fine), rollback the offending file via:

```bash
git checkout <feat-sha>~1 -- VoiceInk/Views/Metrics/MetricsContent.swift
```

…and re-commit. Preserves the rest of the rebuild.

If the white-on-tangerine hero text contrast reads marginal (smoke-test at Task 7 catches this), the fix is one line: swap `Color.white.opacity(0.85)` → `Palette.onyxFg` (#EDEDF0) at three call sites. Hot-fix commit, no rollback needed.

---

## Risks

1. **White text on tangerine contrast (medium).** `Color.white.opacity(0.85)` on `Palette.accent` (#FF5B3A) reads ~3.8-4.2 contrast ratio (WCAG AA threshold is 4.5 for body text; passes for large text 3.0). The hero text mixes 30pt and 36pt — both qualify as large text under WCAG. Mitigation: smoke-test at Task 7. If marginal under any wallpaper/system mode, swap to `Palette.onyxFg`. Documented as a hot-fix path in §Rollback.

2. **Hero corner radius 24pt vs spec §1's 14-16pt panel cap (low).** Documented Q9=a hero exception; not a blocker. Risk: future spec extension drifts the hero radius down. Mitigation: when the W13 polish packet (W13.G) lands, codify the hero exception in the spec amendment — add §1.X note that "hero / dashboard centerpiece surfaces may run 24pt corner radius as part of their celebratory identity, off-limits for regular panels."

3. **GlassCard padding vs MetricCard's existing padding(16) (low).** GlassCard default is `padding: 14`; the original v1 MetricCard wraps content in `.padding(16)`. Coder picks at smoke-test:
   - Drop outer `.padding(16)` and accept GlassCard's default (14) — slightly tighter.
   - Pass `GlassCard(cornerRadius: 16, padding: 16)` — preserves v1 rhythm.
   - Default recommendation: try GlassCard's default first; if metric-card grid feels cramped, bump to `padding: 16`.

4. **MetricCard signature change (low).** Dropping the `color: Color` parameter touches 4 call sites (already in scope). Risk: external code references `MetricCard.color` — none found in repo (`rg -n 'MetricCard\(' VoiceInk/`). Acceptable fallback: keep parameter, body ignores it. Coder picks; recommended drop.

5. **`glassChip(cornerRadius: 18)` for CopySystemInfoButton vs true Capsule (low).** Spec radius range tops at 14-16pt for panels. Using 18pt is a soft pill. Alternative: 999pt (true capsule) but that's spec-forbidden ("NEVER 999pt pills" per spec §1 line 41). 18pt is a small but deliberate exception for button pills. Documented in §Per-axis row 18. If reviewer rejects, fall back to GlassChip's default 10pt (button reads boxier but spec-canonical).

6. **HelpAndResourcesSection bold-on-0.8-primary title (low).** R4 §3 row 3 doesn't prescribe a swap; this plan recommends `.foregroundColor(.primary)` (drop the .8 opacity). Risk: removing the muted treatment makes the title feel heavier. Smoke-test at Task 7. If too heavy, restore `.opacity(0.8)` or use `Palette.onyxMute` for a lighter mute that tracks onyx vocabulary.

7. **`glassPanel(cornerRadius: 16)` vs `GlassCard(cornerRadius: 16)` for HelpAndResourcesSection outer (low).** `glassPanel` is a thinner, brighter variant (rgba 20,20,28 0.55 fill); `GlassCard` composes the full HaloMaterial(phase: .hidden) stack (onyx/light adaptive). For a dashboard sub-panel, `glassPanel` is lighter-touch. Coder picks at smoke-test; recommended `glassPanel(cornerRadius: 16)` for the lighter footprint.

8. **`SettingsSectionHeader` adoption for "Help & Resources" title (low).** R4 didn't prescribe this; spec §3.3 implies it. Coder confirms the primitive's signature (`SettingsSectionHeader(title:systemImage:accent:)` — read `Common/SettingsSectionHeader.swift` to verify) and either adopts or leaves the inline `.font(.system(size: 20, weight: .bold))`. If reviewer pushes back, leave inline. Not blocking.

---

## Open questions for lead

1. **Hero white-on-tangerine contrast — proactive switch to `Palette.onyxFg`?** Smoke-test at Task 7 is the gate; lead may prefer to switch white→onyxFg unconditionally (avoids any wallpaper-mode marginal cases). Recommend: keep white, smoke-test, hot-fix if needed.

2. **Per-card icon palette — single `Palette.accent` vs functional accent/success/neutral split (R4 §5 Q4)?** Brief 2026-04-30 leans single accent; R4 §5 Q4 option (b) suggests functional differentiation (e.g. Sessions=accent, Words=success, WPM=neutral, Keystrokes=accent). Recommended: single `Palette.accent` for cohesion + motion-as-discriminator. Lead picks at sign-off.

3. **MetricCard signature change — drop `color: Color` parameter or keep + ignore?** Recommended drop (cleaner type-level guard against rainbow regression). Acceptable fallback: keep, ignore at body. Lead picks.

4. **Adjacent surfaces — split out `MetricsSetupView` + `PerformanceAnalysis*` as W13.B2 / W13.B3 sibling packets, fold into W13.G polish, or skip entirely?** W13.A explicitly defers these to W13.B per its §File structure routing. Master plan §4 W13.B's 4 bullets do NOT include them. Team-lead brief 2026-04-30 says "do NOT widen scope — Optional within scope." Recommended: split out as **W13.B2** (MetricsSetupView welcome rebuild — small) and **W13.B3** (PerformanceAnalysisView/Panel charts surface — larger; W8 OOS for opaque-bg-required charts requires careful spec read). Each gets its own short plan file, commits in series after W13.B's merge.

5. **`SettingsSectionHeader` adoption for "Help & Resources" panel title?** Spec §3.3 implies; R4 doesn't enforce. Recommended: adopt if signature fits (`SettingsSectionHeader(title: "Help & Resources", systemImage: "book.fill", accent: Palette.accent)`); else leave inline. Lead picks.

6. **CopySystemInfoButton corner radius — 18pt soft-pill vs 10pt boxier chip?** Spec line 41 forbids 999pt true capsules; 18pt is a soft exception, 10pt is canonical chip. Recommended: 18pt for the v1-feel preservation. Lead picks.

7. **GlassCard padding for MetricCard — default 14pt vs explicit 16pt to match v1?** Visual judgment. Recommended: try default 14pt first, smoke-test, bump to 16 if grid feels cramped.

---

## Post-merge verification protocol (USER-SIDE)

Run after lead merges `feat(aesthetic): W13B — …` to main and the build is green.

1. **Capture baseline screenshots BEFORE merge** (if not done at sign-off):
   - Navigate to Metrics dashboard with at least one transcription so totalCount > 0 and the heroSection renders.
   - Screenshot the full dashboard scroll view at default window size, system Light + system Dark, on bright + dark wallpaper. (4 screenshots.)
   - File these to `docs/superpowers/research/2026-04-30-W13B-pre-merge-screenshots/` for diff reference.

2. **Open the Metrics dashboard post-merge.** Compare hero gradient against pre-merge screenshot:
   - Gradient SHAPE identical (linear, .topLeading→.bottomTrailing, three-stop).
   - Source color shifted from system blue to tangerine (#FF5B3A).
   - 24pt corner radius preserved.
   - Drop shadow preserved.

3. **Each MetricCard:**
   - GlassCard(16) chrome — no opaque-white `.thinMaterial`. Adaptive onyx/light per wallpaper luminance.
   - Icon tint uniform `Palette.accent` (tangerine) across all four cards.
   - Numeral font is system default — NO `.rounded` curvature.

4. **Help & Resources panel:**
   - Reads as glass panel — NO opaque windowBackgroundColor box.
   - 16pt outer corner radius (NOT 28pt).
   - Inner link rows are 10pt-rad chips with tangerine icons.
   - "Help & Resources" title reads as a section header (not a v1 bold-prose block).

5. **Copy System Info button:**
   - Glass capsule chrome (NOT opaque white-blue thinMaterial).
   - Spring on copy/uncopy reads at `Animation.haloExpand` cadence (0.38s spring) — slightly snappier than v1.

6. **No `.rounded` font anywhere on this surface.** Confirm visually — the time-saved numeral and the four metric values are all system default.

7. **Accessibility passes:**
   - System Settings → Accessibility → Display → Reduce transparency = ON. Re-open dashboard. Glass surfaces fall back to opaque `controlBackgroundColor` per spec §6.4. Dashboard remains legible.
   - Increase contrast = ON. Inner strokes become 1pt solid; gradient remains. Dashboard remains legible.
   - Reduce motion = ON. Copy button no longer scales/rotates aggressively.

8. **If any check fails**, surface to lead via SendMessage with screenshot + verbal description. Hot-fix paths in §Rollback.

---

## Follow-ups for adjacent W13 packets

### W13.B2 — MetricsSetupView welcome rebuild (recommended split)

`Metrics/MetricsSetupView.swift:62, 103, 104, 140, 145` — `controlBackgroundColor` welcome-card chrome + accent buttons + 28pt corner radius + `.rounded` welcome-marquee numeral. Small plan (~150 lines), single coder/reviewer pair, mirrors W13.B shape.

### W13.B3 — PerformanceAnalysisView + PerformanceAnalysisPanelView charts surface (recommended split)

`Metrics/PerformanceAnalysisView.swift:159, 432, 265, 346, 409` + `Metrics/PerformanceAnalysisPanelView.swift:20, 109, 82, 170, 243` — `windowBackgroundColor` + `controlBackgroundColor` pane chrome + `.rounded` numerals (KEEP per W7 — chart numerals are a sanctioned exception). Charts hosts have a W8-OOS rule (opaque bg required for chart legibility per spec §1.X line 76); rebuild here is non-trivial. Plan needs careful spec read on how to honor charts-bg-opaque while still tracking the dashboard glass aesthetic.

### W13.C — Permissions + AudioTranscribe (already planned)

Cross-references: `PermissionsView.swift:191` PermissionCard rebuild + AudioTranscribeView drop-zone + queue Form purge. No overlap with W13.B.

### W13.D — Form-host purge (already planned)

5 surfaces (EnhancementSettingsView, EnhancementSettingsPanel, PromptEditorView, InlineHistoryView cardListView, AudioTranscribeView queue). No overlap with W13.B.

### W13.E — AI Models card unification (already planned)

5 model cards + ProviderCard + MLXModelPickerView + WhisperModelManager progress bar. No overlap with W13.B.

### W13.F — History window glass + animation codemod (already planned)

HistoryWindowController.createHistoryWindow non-opaque flip + TranscriptionHistoryView glass + 5× `.smooth(0.3)` codemod. No overlap with W13.B.

### W13.G — Polish (already planned)

CompactHeroSection blue→accent, AppNotificationView per-type rainbow, PowerModeView hero header, PromptEditorView trigger chips, EnhancementPromptPopover backdrop, PredefinedPromptsView buttons, CustomPrompt promptIcon tile rebuild, plus CopyIconButton/SaveIconButton/HistoryShortcutTipView/EnhancementShortcutsView/PowerModeConfigView/AudioInputSettingsView/DictionaryQuickAddPanel `controlBackgroundColor` polish. Plus PromptChipPicker custom-2-phase animation, PowerModeStripView sub-150ms eases — spec amendment candidates.

### Final spec extension (after W13.A-G land, per master plan §4 W13.G)

Amend `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.X (or write `2026-04-30-aesthetic-redesign-W13-deltas.md`) with:
- Q9=a sign-off: hero gradient retained on `Palette.accent` source. Hero corner radius 24pt is a sanctioned exception for dashboard centerpiece surfaces (codify at amendment time).
- W13.B icon-palette decision: single `Palette.accent` for metric-card icon tiles; motion is the discriminator.
- Confirm `glassPanel(cornerRadius: 16)` is the canonical Help/Resources panel idiom.
