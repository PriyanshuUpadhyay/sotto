# W13.E — AI Models Card Unification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` for executing tasks task-by-task. Reviewer: `superpowers:code-reviewer`. Steps use checkbox (`- [ ]`) syntax.

**Date:** 2026-04-30
**Author:** planner-w13e (team `voiceink-phase23`, task #21)
**Scope:** AI Models tab card surface — `WhisperModelCardView` (incl. `ImportedWhisperModelCardView`), `CloudModelCardView`, `FluidAudioModelCardView`, `NativeAppleModelCardView`, `CustomModelCardView`, `MLXModelPickerView` rows, plus a verify-only pass on `ProviderCard`. Optional sub-fix to `WhisperModelManager.DownloadProgressView` accent. Per R4 audit row 13-14, every card today bypasses `GlassCard` and re-implements `HaloMaterial(phase: .hidden) + stroke` inline with hardcoded `Color.accentColor` / `Color.white.opacity(0.08)`. The user opens this tab to download / pick models — second-most-visible surface after Metrics.

**Sources of truth:**
- R4 audit (the WHY): `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md` §1 row 4, §3 rows 13-14, §4 W13-E.
- Spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (tokens, glass primitive, motion grammar), §1.X (W8 wallpaper-glass contract), §2.4 (motion tokens), §6.4 (Reduce-Transparency / Increase-Contrast contract).
- Master plan §4 W13.E (the 4-bullet scope): `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` lines 183-186.
- Sibling shape (mirrored exactly): `docs/superpowers/plans/W13B-metrics-rebuild.md` — including its Per-axis Sweep/Defer/Flag table, Tasks list, Verification, Rollback, Risks, Open questions, Post-merge protocol sections.
- Sibling shape (axis grouping): `docs/superpowers/plans/W13A-token-sweep.md` — for the per-axis vocabulary table.
- Vocabulary primitives (verify, do not edit): `Palette.swift`, `GlassCard.swift`, `GlassChip.swift` (`glassChip` / `glassPanel` modifiers), `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` (under `VoiceInk/Views/Common/` and `VoiceInk/Views/Recorder/`).

**Goal:** Every AI Models card surface speaks the same vocabulary as the floating recorder cluster (per spec §1, §1.X, §2.4) — replacing the inline `HaloMaterial(phase:.hidden) + stroke` stack with the `GlassCard(cornerRadius: 16)` primitive and recolouring the active-state stroke from system blue to `Palette.accent`, the rest-state stroke from `Color.white.opacity(0.08)` to `Palette.hairline*`. Post-merge a user opens AI Models, expands a provider, picks a model — every card silhouette reads as one onyx/light glass family indistinguishable from the recorder cluster + Settings reskin (W5) + Metrics rebuild (W13.B).

**Locked decisions honored:**
- **Master plan §4 W13.E bullets** (verbatim): replace direct `HaloMaterial(phase: .hidden)` chrome with `GlassCard(cornerRadius: 16)`; replace hardcoded `Color.accentColor` with `Palette.accent`; replace `Color.white.opacity(0.08)` with `Palette.hairline*`; drop `.rounded` font usage on these surfaces.
- **Brief 2026-04-30 (team-lead)** — also drop rainbow per-card icon palette IF present (verify per audit, none on AI Models cards but flag if a reviewer surfaces one). WhisperModelManager progress bar restyle is in scope **only if** the screenshot diff at smoke-test reads off; otherwise routed to W13.G polish.
- **Q9-equivalent for cards:** there is no hero gradient on AI Models — this surface is unambiguously a regular-panel restyle. No exceptions to the 14-16pt corner-radius cap. No exceptions to the `.rounded` retirement.

---

## Prelude — packet shape + commit etiquette

**Shape.** Single coder + reviewer pair under team `voiceink-phase23` post-sign-off. Diff is bounded to **5 Swift files** plus this plan file:
1. `VoiceInk/Views/AI Models/WhisperModelCardView.swift` (covers `WhisperModelCardView` + `ImportedWhisperModelCardView` — both in one file)
2. `VoiceInk/Views/AI Models/CloudModelCardView.swift`
3. `VoiceInk/Views/AI Models/FluidAudioModelCardView.swift`
4. `VoiceInk/Views/AI Models/NativeModelCardView.swift` (struct: `NativeAppleModelCardView`)
5. `VoiceInk/Views/AI Models/CustomModelCardView.swift`

Plus, conditional within scope:
6. `VoiceInk/Views/AI Models/MLXModelPickerView.swift` (curated `modelRow` + `detectedRow` chrome — different pre-existing pattern, see Per-axis row 13-14)
7. `VoiceInk/Views/AI Models/ProviderCard.swift` (verify-only by default, see Per-axis row 15)

Estimated total LOC delta: ~150 lines edited, ~zero net new lines (subtractive — the inline material+stroke stack collapses into one `GlassCard {…}` wrapper). No new files. No new SPM deps. No new tokens beyond what `Palette.swift` already exposes. No deployment-target change (already 26.0 per W11.B). No test-infra change (Q10 deferred). No primitive edits.

**Commit cadence per `feedback_skip_per_packet_builds.md`.** Coder leaves edits uncommitted in the worktree. Lead runs single integration `make local` at merge time and commits:
```
docs(plans): W13E — AI Models card unification
feat(aesthetic): W13E — AI Models card unification
```
Coder does NOT commit. Coder does NOT run `xcodebuild` per task. The integration build is the gate.

**Worktree convention.** Spawn at `.worktrees/w13e/` ABSOLUTE path. Always `cd <main-repo>` before `git worktree add` to avoid cwd-drift (lead has been bitten by this).

**Comment policy.** Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code. Inline doc-comments may cite spec §1 / §2.3 / §2.4 + this plan path. Pre-existing spec-ref comments preserved (`MLXModelPickerView` W6/W9 banners, `ProviderCard` W6 banner).

**Visual verification.** This packet is verified by **screenshot diff**, not by automated tests (no visual-diff CI exists). The user runs the post-merge protocol in §Post-merge verification. Coder + reviewer eyeball the build locally.

---

## Per-axis Sweep / Defer / Flag table

Mirrors W13.B's shape. Each row is one axis × one surface; disposition is **Sweep** (land in W13.E), **Defer** (route to W13.F-G or sibling packet), or **Flag** (ambiguous; coder evaluates context, sweeps if obvious or leaves with comment).

| # | Surface | File:line | Axis | Current | W13.E Action | Disposition | Rationale |
|---|---|---|---|---|---|---|---|
| 1 | `WhisperModelCardView` chrome | `AI Models/WhisperModelCardView.swift:35-49` | material + stroke | `padding(16) → background(HaloMaterial(shape: RoundedRectangle 16, phase: .hidden)) → overlay(RoundedRectangle 16 .stroke(isCurrent ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.08), lineWidth: isCurrent ? 1.5 : 0.5)) → clipShape(RoundedRectangle 16)` | Wrap content in `GlassCard(cornerRadius: 16, padding: 16)`, then attach `.overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(isCurrent ? Palette.accent.opacity(0.55) : Palette.hairline, lineWidth: isCurrent ? 1.5 : 1))`. Drop the explicit `.clipShape` (GlassCard composes the clip via `HaloMaterial`'s shape arg). | **Sweep** | spec §1 / R4 §1 row 4 / master plan §4 W13.E. Mirrors `ProviderCard.swift:140-149` stroke pattern (`Palette.accent.opacity(0.55)` active / `Palette.hairline` rest, `1.5/1` widths). |
| 2 | `WhisperModelCardView` active stroke alpha | `AI Models/WhisperModelCardView.swift:45` | color (active stroke) | `Color.accentColor.opacity(0.45)` | `Palette.accent.opacity(0.55)` | **Sweep** | Matches `ProviderCard.swift:145` pattern — 0.55 is the AI-Models active-stroke alpha across the family post-W6. 0.45 was the pre-W6 cards' literal. Aligning. |
| 3 | `WhisperModelCardView` rest stroke | `AI Models/WhisperModelCardView.swift:45` | color (rest stroke) | `Color.white.opacity(0.08)` | `Palette.hairline` (= `white α 0.16`) | **Sweep** | spec §1; `Palette.hairline` is the sanctioned glass-rest stroke. White α 0.08 is below the locked vocabulary minimum (0.10 = `hairlineSoft`). Going to `hairline` (0.16) matches `ProviderCard.swift:145` and `MLXModelPickerView.swift:114`. |
| 4 | `WhisperModelCardView` rest stroke width | `AI Models/WhisperModelCardView.swift:46` | geometry (lineWidth) | `0.5` | `1` | **Sweep** | Aligns with `ProviderCard.swift:146` (`isActive ? 1.5 : 1`). 0.5pt was a v1 hairline; 1pt is the locked GlassCard family rest-stroke width. |
| 5 | `WhisperModelCardView` Download CTA capsule | `AI Models/WhisperModelCardView.swift:155-159` | color | `Capsule().fill(Color(.controlAccentColor)) + .shadow(color: Color(.controlAccentColor).opacity(0.2), radius: 2, x: 0, y: 1)` | `Capsule().fill(Palette.accent) + .shadow(color: Palette.accent.opacity(0.2), radius: 2, x: 0, y: 1)` | **Sweep** | spec §1 (single accent token). `Color(.controlAccentColor)` is the system blue NSColor; `Palette.accent` is the locked tangerine. Width/shadow params preserved. |
| 6 | `ImportedWhisperModelCardView` chrome | `AI Models/WhisperModelCardView.swift:255-269` | material + stroke | identical to row 1 (this struct duplicates the inline stack) | identical to row 1 fix (GlassCard wrap + Palette.accent/Palette.hairline overlay) | **Sweep** | Same file, same struct family — apply the same swap inline. |
| 7 | `CloudModelCardView` chrome | `AI Models/CloudModelCardView.swift:62-76` | material + stroke | `padding(16) → background(HaloMaterial(shape: RoundedRectangle 16, phase: .hidden)) → overlay(RoundedRectangle 16 .stroke(isCurrent ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.08), lineWidth: isCurrent ? 1.5 : 0.5)) → clipShape(...)` | identical to row 1 fix; **note:** content is `VStack(spacing: 0) { mainHStack + Divider + configurationSection }`. The expand-collapse means the GlassCard wraps the **outer** `VStack`, not the inner padded `HStack`. Inner sections keep their own `.padding(16)` calls; outer GlassCard uses `padding: 0` so inner padding is preserved. | **Sweep** | spec §1; structural note: when card content composes its own `.padding(16)` per section (CloudModelCardView, CustomModelCardView), pass `GlassCard(cornerRadius: 16, padding: 0)` so the outer wrap doesn't double-pad. |
| 8 | `CloudModelCardView` Configure CTA capsule | `AI Models/CloudModelCardView.swift:182-186` | color | `Capsule().fill(Color(.controlAccentColor)) + shadow(...)` | `Capsule().fill(Palette.accent) + shadow(color: Palette.accent.opacity(0.2), radius: 2, x: 0, y: 1)` | **Sweep** | identical to row 5 rationale |
| 9 | `CloudModelCardView` Verify capsule | `AI Models/CloudModelCardView.swift:236-239` | color | `Capsule().fill(verificationStatus == .success ? Color(.systemGreen) : Color(.controlAccentColor))` | `Capsule().fill(verificationStatus == .success ? Palette.success : Palette.accent)` | **Sweep** | spec §1 — `Palette.success` is the locked completion token (#30D158); `Color(.systemGreen)` is the system mid-saturation green which mostly matches but routes through the system tint. Aligning. |
| 10 | `FluidAudioModelCardView` chrome | `AI Models/FluidAudioModelCardView.swift:47-61` | material + stroke | identical to row 1 | identical to row 1 fix (GlassCard wrap + Palette stroke overlay) | **Sweep** | spec §1 / R4 §3 row 13. |
| 11 | `FluidAudioModelCardView` Download capsule | `AI Models/FluidAudioModelCardView.swift:158` | color | `Capsule().fill(Color.accentColor)` | `Capsule().fill(Palette.accent)` | **Sweep** | spec §1; same as row 5 but no shadow on this site (FluidAudio's button is flatter). Preserve the no-shadow shape. |
| 12 | `NativeAppleModelCardView` chrome | `AI Models/NativeModelCardView.swift:23-37` | material + stroke | identical to row 1 | identical to row 1 fix | **Sweep** | spec §1 / R4 §3 row 13 (NativeApple is one of the four "same pattern" cards). |
| 13 | `CustomModelCardView` chrome | `AI Models/CustomModelCardView.swift:26-40` | material + stroke | identical to row 7 (also expand-style outer VStack) | identical to row 7 fix (`GlassCard(cornerRadius: 16, padding: 0)` outer wrap; inner `.padding(16)` preserved) | **Sweep** | spec §1; not explicitly in R4's row 13 enumeration but matches the pattern character-for-character. Coder verifies via grep. |
| 14 | `MLXModelPickerView.modelRow` chrome | `AI Models/MLXModelPickerView.swift:103-117` | material + stroke | `padding(12) → background(RoundedRectangle 14 .fill(isActive ? Palette.accent.opacity(0.10) : Color.clear) → background(RoundedRectangle 14 .fill(.ultraThinMaterial))) → overlay(RoundedRectangle 14 .stroke(isActive ? Palette.accent.opacity(0.55) : Palette.hairline, lineWidth: isActive ? 1.5 : 1))` | Wrap content in `.modifier(GlassChip(cornerRadius: 14, paddingH: 12, paddingV: 12))` — uses the existing `GlassChip` primitive which composes the locked panel chrome (28pt blur + obsidian fill + hairline + innerHi sheen + drop shadow). Then preserve the active-state accent tint by adding an `.overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.accent.opacity(0.10)))` only when `isActive` (use `.allowsHitTesting(false)` on the overlay). Preserve the existing stroke overlay verbatim (`Palette.accent.opacity(0.55)` / `Palette.hairline`) — already vocabulary-clean. | **Sweep** | R4 §3 row 14 (audit prescribes `glassPanel(cornerRadius: 14)`; this plan uses the explicit `GlassChip` modifier with `paddingH/paddingV: 12` to match the existing 12pt vertical pad). The active-state opacity-tint overlay is a row-level affordance the audit's terse prescription doesn't cover; preserved to avoid silently dropping the active row's accent fill. **Coder note:** if `glassPanel(cornerRadius: 14)` (the modifier) preserves the visual feel without the manual `paddingH:paddingV:12` argument, prefer the modifier — simpler call site. Smoke-test gates the choice. |
| 15 | `MLXModelPickerView.detectedRow` chrome | `AI Models/MLXModelPickerView.swift:326-339` | material + stroke | identical to row 14 | identical to row 14 fix | **Sweep** | Same struct, same chrome — sweep symmetrically. |
| 16 | `ProviderCard` chrome | `AI Models/ProviderCard.swift:140-149` | material + stroke | already uses `HaloMaterial(shape: shape, phase: .hidden) + RoundedRectangle 14 .stroke(isActive ? Palette.accent.opacity(0.55) : Palette.hairline, lineWidth: isActive ? 1.5 : 1) → clipShape(shape)` | KEEP — this is the source-of-truth pattern the rest of the cards now match. **Optionally** migrate to `GlassCard(cornerRadius: 14, padding: 0)` wrap for primitive uniformity, but the existing inline composition is byte-equivalent and pre-W13.A reviewer-noted (`ProviderCard.swift:20-22` banner cites spec §2.3 + §3.7). | **Flag — preserve, optionally migrate** | spec §2.3; ProviderCard was the W6 reference implementation. The cards we're rebuilding match this pattern. Coder's call: if migrating to `GlassCard(...)` wrap is mechanical and preserves byte-equivalent visual output, sweep for primitive uniformity; otherwise leave (the strokes/colors are already vocabulary-clean). **Recommended: leave**, since the visual is identical and the inline composition has its own W6 spec-ref comment. |
| 17 | `ProviderCard` expand animation literal | `AI Models/ProviderCard.swift:150, 631` | animation grammar | `.spring(response: 0.32, dampingFraction: 0.85)` (2 instances — body modifier + toggleExpand action) | KEEP per W13.A's defer-to-W13.F policy on animation tokens — **OR** `Animation.haloExpand` if coder swaps both call sites in one pass | **Flag — defer to W13.F** | W13.F owns the animation codemod. W13.A's master table maps `spring(0.3, ~0.85)` → `Animation.haloExpand` ("reveal axis"). Touching this here drifts scope. Leave. |
| 18 | `WhisperModelManager.DownloadProgressView` track + fill | `Transcription/Whisper/WhisperModelManager.swift:439-445` | color | `RoundedRectangle 4 .fill(Color(.separatorColor).opacity(0.3))` track + `RoundedRectangle 4 .fill(Color(.controlAccentColor))` fill | `RoundedRectangle 4 .fill(Palette.hairlineSoft)` track + `RoundedRectangle 4 .fill(Palette.accent)` fill | **Flag — sweep if smoke-test surfaces drift** | brief 2026-04-30 says "WhisperModelManager progress bar — restyle if applicable per R4 audit." R4 doesn't enumerate this view, but the tangerine/hairline retint is a one-line each, mirrors `MLXModelPickerView.downloadProgressChip:241-262` vocabulary, and lives inside the Whisper card's progressSection at `WhisperModelCardView.swift:108-119`. **Recommended:** sweep — costs near zero and prevents a system-blue progress bar appearing inside a tangerine-stroked card. **Coder note:** this file lives outside `VoiceInk/Views/AI Models/`. If it triggers a build-target permission concern, drop and route to W13.G. |
| 19 | `WhisperModelManager.DownloadProgressView` animation | `Transcription/Whisper/WhisperModelManager.swift:458` | animation grammar | `.animation(.smooth, value: totalProgress)` | KEEP per row 17 rationale (defer to W13.F) | **Flag — defer** | `.smooth` is a SwiftUI sugar over a default spring. W13.F owns the codemod. Leave. |
| 20 | `ModelManagementView` defaultModelSection / filter pills / settings gear | `AI Models/ModelManagementView.swift:105-118, 128-167` | misc | already uses `GlassChip(cornerRadius: 16/22)` + `Palette.accent` + `Animation.haloExpand` | KEEP | **Flag — preserve** | already W6-aligned per R4 §3 rows 11-12. Out of W13.E scope. The `.foregroundColor(.accentColor)` at `:160` on the gear icon is one stray system-blue; W13.A's grep targets it but it's a 1-line drift — leave for W13.G polish unless coder spots in scope. |
| 21 | `AddCustomModelView` accent button + shadow | `AI Models/AddCustomModelView.swift:157` | color | `Color.accentColor` shadow + button colour | KEEP — defer to W13.A's already-shipped sweep | **Defer** | per W13.A modified-files list (`AddCustomModelView.swift` — accent button + accent shadow + accent verify-button (axis A)). If W13.A landed before W13.E, this should already be tangerine. Coder verifies via grep; if hits remain, route to W13.A re-run not W13.E. |
| 22 | `APIKeyManagementView` etc. | `AI Models/APIKeyManagementView.swift`, `LanguageSelectionView.swift` | various | various | KEEP | **Defer — out of scope** | Not in master plan §4 W13.E bullets; not in R4 audit row 13-14; not in brief's "5 card files + ProviderCard" list. |
| 23 | `MLXModelPickerView` rating-chip / latency-chip / detected-chip backgrounds | `AI Models/MLXModelPickerView.swift:151, 163, 179, 248` | color | `Color.white.opacity(0.04 / 0.05 / 0.06)` capsule fills | KEEP | **Defer — W13.A flagged as ambiguous** | per W13.A §File structure (`MLXModelPickerView.swift` — Color.white.opacity(0.04 / 0.05 / 0.06) chip-fills (axis B — ambiguous, see Risks; coder evaluates context)). These are sub-chip-scale capsule tints, not card-level chrome. Out of W13.E scope. Routed to W13.A or W13.G; coder eval-only. |
| 24 | Card content typography | all 5 card files | font | already system-default (no `.rounded` in scope per pre-grep) | KEEP | **Flag — verify, no edit** | brief 2026-04-30: "Drop `.rounded` font usage on these surfaces." Pre-grep confirms no `.rounded` hits in `VoiceInk/Views/AI Models/`. Verify at Task 0 grep. |
| 25 | Card icon palette | all 5 card files | color | no per-card icon palette (cards have NO leading icon tile — just text + metadata) | KEEP | **Flag — verify, no edit** | brief 2026-04-30: "Drop rainbow per-card icon palette IF present (verify in audit; W13.B already dropped rainbow on Metrics — same pattern here)." Pre-grep + Read confirms cards do NOT have a leading icon tile (unlike `MetricCard.swift`). The provider tile in `ProviderCard.swift:160-178` already uses `Palette.accent`. No rainbow exists on this surface. Verify at Task 0 grep. |
| 26 | Card content padding rhythm | all 5 card files | geometry | inner content `.padding(16)` (applied per-card to inner HStack/VStack) | KEEP — per row 1 / row 7 disposition | **Flag — preserve** | The `padding(16)` rhythm is the v1 metric-card scale; preserving it ensures the GlassCard rebuild reads visually identical at the silhouette boundary. Outer `GlassCard` is `padding: 16` (single-section cards: Whisper, FluidAudio, Native) or `padding: 0` (multi-section cards: Cloud, Custom — inner sections keep their own `.padding(16)`). |
| 27 | Card icon `.menuStyle(.borderlessButton)` ellipsis | all 5 card files | misc | `Image(systemName: "ellipsis.circle")` 14pt — system tint | KEEP | **Flag — preserve** | system tint is OK on chrome controls (the menu is a dropdown affordance, not state-bearing). spec §1 retires user-facing accent drift, not system controls. Preserves macOS contract. |

### Deferred (route to other W13 packets or sibling)

| File | Why deferred |
|---|---|
| `AI Models/ModelManagementView.swift:160` (`.foregroundColor(.accentColor)` on gear icon) | W13.G polish — one-liner, not in this packet's "5 card files + ProviderCard" scope |
| `AI Models/AddCustomModelView.swift:157` (accent button shadow) | W13.A already covers — coder verifies it landed; if not, route to W13.A re-run |
| `AI Models/MLXModelPickerView.swift:151, 163, 179, 248` (`Color.white.opacity(0.04-0.06)` chip fills) | W13.A flagged as ambiguous; sub-chip-scale tint; out of W13.E surface |
| `AI Models/MLXModelPickerView.swift:241-262` (`downloadProgressChip` accent) | already vocabulary-clean (`Palette.accent.opacity(0.55)` + `Palette.hairline`); preserve verbatim |
| `AI Models/CustomModelCardView.swift` if `.systemRed` / system-tinted chrome appears outside the chrome-rebuild | per row 13 — only the outer chrome is in scope; inner `Verify`/`error` text colours are deferred |
| `AI Models/APIKeyManagementView.swift`, `LanguageSelectionView.swift` | out of W13.E scope per master plan §4 W13.E bullets |
| `Transcription/Whisper/WhisperModelManager.swift:402-460` `DownloadProgressView` if Task 0 grep shows the file outside the AI-Models target's edit boundary | route to W13.G polish; keep W13.E to its 5-card-files scope |

### Flagged (no edit — context-eval at coder review)

| Item | Reason |
|---|---|
| `ProviderCard.swift:140-149` (already Palette-aligned inline composition) | Migrating to `GlassCard(...)` wrap is byte-equivalent visual but optional; recommended preserve (row 16). |
| `WhisperModelManager.DownloadProgressView` track + fill (row 18) | Sweep recommended; coder smoke-tests if drop is needed. |
| `ProviderCard.swift:150, 631` spring animation literals | W13.F owns animation codemod (row 17). |
| `WhisperModelManager.swift:458` `.smooth` animation | same reason (row 19). |
| `ModelCardView.swift` (delegating wrapper, no chrome of its own) | View-level dispatcher only; no edits needed. Verify byte-identical at Task 6. |

---

## Tasks

### Task 0 — Audit + grep validation (read-only)

**Files:** none.

- [ ] Re-run `rg` for the W13.E target patterns and confirm hit counts match this plan's Per-axis table:

  ```bash
  # Card chrome — HaloMaterial direct usage outside ProviderCard
  rg -n 'HaloMaterial' VoiceInk/Views/AI\ Models/

  # Hardcoded Color.accentColor in card chrome
  rg -n 'Color\.accentColor' VoiceInk/Views/AI\ Models/

  # Hardcoded Color.white.opacity(0.08) (or thereabouts) hairlines
  rg -n 'Color\.white\.opacity\(0\.0[68]\)' VoiceInk/Views/AI\ Models/

  # Capsule fills using system controlAccentColor
  rg -n 'controlAccentColor' VoiceInk/Views/AI\ Models/

  # Rainbow per-card palette (should be zero — verify)
  rg -n 'color: \.(purple|yellow|orange|red|blue|green)' VoiceInk/Views/AI\ Models/

  # .rounded in AI Models surface (should be zero)
  rg -n 'design:\s*\.rounded' VoiceInk/Views/AI\ Models/

  # Raw materials in AI Models (only MLXModelPickerView is expected)
  rg -n '\.thinMaterial|\.ultraThinMaterial' VoiceInk/Views/AI\ Models/

  # WhisperModelManager DownloadProgressView accent
  rg -n 'controlAccentColor|separatorColor' VoiceInk/Transcription/Whisper/WhisperModelManager.swift
  ```

  Expected hit counts (from this plan):
  - `HaloMaterial` in `AI Models/`: **6** (5 cards × 1 + ProviderCard × 1 = WhisperModelCardView line 37 + 257, CloudModelCardView 64, FluidAudioModelCardView 49, NativeModelCardView 25, CustomModelCardView 28, ProviderCard 141; ProviderCard preserves inline). Imported card duplicates Whisper file's pattern.
  - `Color.accentColor` in `AI Models/`: **6** (Whisper 45, ImportedWhisper 265, Cloud 72, FluidAudio 57, FluidAudio 158 button, Native 33, Custom 36 — totals 7 hits; Whisper file has 2). Recount via `rg -c`.
  - `Color.white.opacity(0.08)` in `AI Models/`: **6** (Whisper 45, ImportedWhisper 265, Cloud 72, FluidAudio 57, Native 33, Custom 36).
  - `controlAccentColor` in `AI Models/`: **5** (Whisper 157+158, Cloud 184+185+238). All inside Capsule button shells.
  - rainbow `color: .purple/.yellow/...`: **0** (verify; cards have no per-card icon palette).
  - `design: .rounded` in `AI Models/`: **0** (verify).
  - `.thinMaterial / .ultraThinMaterial` in `AI Models/`: **2** in MLXModelPickerView (lines 109, 332). Other files do not raw-material.
  - WhisperModelManager: **1** `controlAccentColor` (line 444) + **1** `separatorColor` (line 440).

- [ ] If hit counts differ, escalate to lead before drafting edits. Do not drift the scope.

- [ ] Read `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` in full to confirm the primitive APIs the edits below assume:
  - `GlassCard(cornerRadius:padding:appearance:)` — `cornerRadius` defaults to 16, `padding` to 14, `appearance` defaults to `nil` (resolves to `GlassAppearanceDetector.shared.current`). Content is a `@ViewBuilder` closure. Composes `HaloMaterial(shape: RoundedRectangle(cornerRadius:..., .continuous), phase: .hidden, appearance: resolved)`. **Crucially: composes the shape clip via `HaloMaterial`'s internal `.clipShape(shape)` at `:168` — caller does NOT need to add `.clipShape` outside the `GlassCard` wrap.**
  - `.glassChip(cornerRadius:)` — modifier; default 10pt; padded 11h/7v.
  - `.glassPanel(cornerRadius:)` — modifier; default 14pt; padded 14h/12v.
  - `Palette.accent` (`#FF5B3A`), `Palette.hairline` (`white α 0.16`), `Palette.hairlineSoft` (`white α 0.10`), `Palette.innerHi` (`white α 0.22`), `Palette.success` (`#30D158`), `Palette.onyxFg`, `Palette.accentMuted`, `Palette.accentGlow` available.
  - `Animation.haloExpand`, `.haloCollapse`, `.haloPhaseCrossfade`, `.haloBreathe` available.
  - `HaloMaterial.swift:107-271` — composes the layered material; `phase: .hidden` is the AI-Models cards' rest state.

### Task 1 — `WhisperModelCardView` chrome rebuild

**Files:** `VoiceInk/Views/AI Models/WhisperModelCardView.swift`.

- [ ] At lines 21-50, replace the chrome stack with a `GlassCard(cornerRadius: 16, padding: 16)` wrap. Final body skeleton:

  ```swift
  var body: some View {
      GlassCard(cornerRadius: 16, padding: 16) {
          HStack(alignment: .top, spacing: 16) {
              VStack(alignment: .leading, spacing: 6) {
                  headerSection
                  metadataSection
                  descriptionSection
                  progressSection
              }
              .frame(maxWidth: .infinity, alignment: .leading)

              actionSection
          }
      }
      .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(
                  isCurrent ? Palette.accent.opacity(0.55) : Palette.hairline,
                  lineWidth: isCurrent ? 1.5 : 1
              )
      )
  }
  ```

  Drop the explicit `.padding(16)` on the inner HStack (GlassCard's `padding: 16` argument carries it). Drop the `.clipShape(...)` (HaloMaterial's `.clipShape(shape)` at `:168` carries it).

- [ ] At line 155-159 (Download CTA capsule), swap `Color(.controlAccentColor)` → `Palette.accent`:

  ```swift
  .background(
      Capsule()
          .fill(Palette.accent)
          .shadow(color: Palette.accent.opacity(0.2), radius: 2, x: 0, y: 1)
  )
  ```

- [ ] At lines 200-269 (`ImportedWhisperModelCardView`), apply the identical chrome swap as the parent struct (rows 1-4 in Per-axis table).

**Verify:**
- `rg -n 'HaloMaterial' VoiceInk/Views/AI\ Models/WhisperModelCardView.swift` returns **0** hits.
- `rg -n 'Color\.accentColor' VoiceInk/Views/AI\ Models/WhisperModelCardView.swift` returns **0** hits.
- `rg -n 'Color\.white\.opacity\(0\.08\)' VoiceInk/Views/AI\ Models/WhisperModelCardView.swift` returns **0** hits.
- `rg -n 'controlAccentColor' VoiceInk/Views/AI\ Models/WhisperModelCardView.swift` returns **0** hits.
- Both card variants render with `HaloMaterial(phase: .hidden)` chrome via the `GlassCard` primitive (onyx/light adaptive via `GlassAppearanceDetector`).
- Active stroke at `Palette.accent.opacity(0.55)` lineWidth 1.5; rest stroke at `Palette.hairline` lineWidth 1.

### Task 2 — `CloudModelCardView` chrome rebuild

**Files:** `VoiceInk/Views/AI Models/CloudModelCardView.swift`.

- [ ] At lines 39-77, the existing body composes `VStack(alignment: .leading, spacing: 0) { mainHStack.padding(16) + Divider + configurationSection.padding(16) }`. Wrap the **outer** `VStack` in `GlassCard(cornerRadius: 16, padding: 0)` so the inner `.padding(16)` calls preserve the existing rhythm. Final body skeleton:

  ```swift
  var body: some View {
      GlassCard(cornerRadius: 16, padding: 0) {
          VStack(alignment: .leading, spacing: 0) {
              HStack(alignment: .top, spacing: 16) {
                  VStack(alignment: .leading, spacing: 6) {
                      headerSection
                      metadataSection
                      descriptionSection
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)

                  actionSection
              }
              .padding(16)

              if isExpanded {
                  Divider()
                      .padding(.horizontal, 16)

                  configurationSection
                      .padding(16)
              }
          }
      }
      .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(
                  isCurrent ? Palette.accent.opacity(0.55) : Palette.hairline,
                  lineWidth: isCurrent ? 1.5 : 1
              )
      )
      .onAppear {
          loadSavedAPIKey()
      }
  }
  ```

  Drop the explicit `.clipShape(...)`.

- [ ] At lines 182-186 (Configure CTA capsule), swap `Color(.controlAccentColor)` → `Palette.accent` (mirrors Task 1 row 5).

- [ ] At line 238 (Verify capsule), swap:

  ```swift
  .background(
      Capsule()
          .fill(verificationStatus == .success ? Palette.success : Palette.accent)
  )
  ```

  Preserve the rest of the conditional / `.disabled` / `.padding` / `.foregroundColor(.white)` behaviour.

**Verify:**
- File contains **0** `HaloMaterial`, **0** `Color.accentColor`, **0** `Color.white.opacity(0.08)`, **0** `controlAccentColor`, **0** `systemGreen` hits.
- Expand-collapse animation behavior identical pre/post (the `.interpolatingSpring(stiffness: 170, damping: 20)` at `:169` is **out of scope** — W13.F owns animation codemod).
- Card silhouette identical at rest pre/post; expand reveals a `Divider` followed by `configurationSection` inside the same outer `GlassCard`.

### Task 3 — `FluidAudioModelCardView` chrome rebuild

**Files:** `VoiceInk/Views/AI Models/FluidAudioModelCardView.swift`.

- [ ] At lines 35-62, replace the chrome stack with a `GlassCard(cornerRadius: 16, padding: 16)` wrap (mirrors Task 1 row 1).

- [ ] At line 158 (Download capsule), swap:

  ```swift
  .background(Capsule().fill(Palette.accent))
  ```

  No shadow on this site (FluidAudio's button is flatter — preserve).

**Verify:**
- File contains **0** `HaloMaterial`, **0** `Color.accentColor`, **0** `Color.white.opacity(0.08)` hits.

### Task 4 — `NativeAppleModelCardView` chrome rebuild

**Files:** `VoiceInk/Views/AI Models/NativeModelCardView.swift`.

- [ ] At lines 10-38, replace the chrome stack with a `GlassCard(cornerRadius: 16, padding: 16)` wrap (mirrors Task 1 row 1).

**Verify:**
- File contains **0** `HaloMaterial`, **0** `Color.accentColor`, **0** `Color.white.opacity(0.08)` hits.

### Task 5 — `CustomModelCardView` chrome rebuild

**Files:** `VoiceInk/Views/AI Models/CustomModelCardView.swift`.

- [ ] At lines 12-41, replace the chrome stack with a `GlassCard(cornerRadius: 16, padding: 0)` wrap (mirrors Task 2 / row 7 / row 13 — outer wrap with inner section padding preserved). The body's only inner section is the main HStack at `:14-25` with its own `.padding(16)`. Final body skeleton:

  ```swift
  var body: some View {
      GlassCard(cornerRadius: 16, padding: 0) {
          VStack(alignment: .leading, spacing: 0) {
              HStack(alignment: .top, spacing: 16) {
                  VStack(alignment: .leading, spacing: 6) {
                      headerSection
                      metadataSection
                      descriptionSection
                  }
                  .frame(maxWidth: .infinity, alignment: .leading)

                  actionSection
              }
              .padding(16)
          }
      }
      .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
              .stroke(
                  isCurrent ? Palette.accent.opacity(0.55) : Palette.hairline,
                  lineWidth: isCurrent ? 1.5 : 1
              )
      )
  }
  ```

  *Coder note:* the outer `VStack` is functionally redundant for the single-section custom card (no expand/collapse), but preserves the structural pattern symmetry with `CloudModelCardView`. Acceptable simplification: drop the outer VStack and pass the `HStack` directly into `GlassCard`. **Default: preserve VStack** for symmetry.

**Verify:**
- File contains **0** `HaloMaterial`, **0** `Color.accentColor`, **0** `Color.white.opacity(0.08)` hits.

### Task 6 — `MLXModelPickerView` rows chrome rebuild

**Files:** `VoiceInk/Views/AI Models/MLXModelPickerView.swift`.

- [ ] At lines 103-117 (`modelRow`), replace the chrome with `glassPanel(cornerRadius: 14)` modifier wrapping the row's content. Preserve the active-state accent fill via overlay. Final chrome skeleton:

  ```swift
  .glassPanel(cornerRadius: 14)
  .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(isActive ? Palette.accent.opacity(0.10) : Color.clear)
          .allowsHitTesting(false)
  )
  .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(
              isActive ? Palette.accent.opacity(0.55) : Palette.hairline,
              lineWidth: isActive ? 1.5 : 1
          )
  )
  ```

  *Caveat:* `glassPanel(cornerRadius: 14)` from `GlassChip.swift:72-74` defaults to `paddingH: 14, paddingV: 12`. The current row uses `.padding(12)` (square 12pt). Pad-mismatch results: row reads ~2pt taller / ~2pt wider per side. **Coder picks at smoke-test:**
  - **Option A (preferred):** drop the existing `.padding(12)` (the modifier supplies its own); accept the 14h/12v rhythm — closer to spec §1.
  - **Option B (preserve v1):** call the underlying modifier directly `.modifier(GlassChip(cornerRadius: 14, paddingH: 12, paddingV: 12))` to keep the 12pt square padding.

- [ ] At lines 326-339 (`detectedRow`), apply the identical chrome swap as `modelRow`.

- [ ] PRESERVE the existing `Palette.accent` / `Palette.hairline` strokes — already vocabulary-clean.

- [ ] PRESERVE the `Capsule().fill(Color.white.opacity(0.04 / 0.05 / 0.06))` rating-chip / latency-chip / detected-chip / progressChip backgrounds at lines 151, 163, 179, 248. These are sub-chip-scale tints flagged by W13.A as "ambiguous, defer" (Per-axis row 23). Out of W13.E scope.

**Verify:**
- `rg -n '\.ultraThinMaterial' VoiceInk/Views/AI\ Models/MLXModelPickerView.swift` returns **0** hits.
- `rg -n 'Color\.white\.opacity\(0\.0[456]\)' VoiceInk/Views/AI\ Models/MLXModelPickerView.swift` returns **4** hits (preserved per row 23).
- Active row tints accent-on-glass; rest row reads as obsidian-glass with hairline.

### Task 7 — `ProviderCard` verify-only

**Files:** `VoiceInk/Views/AI Models/ProviderCard.swift`.

- [ ] Verify `ProviderCard.swift:140-149` chrome composition is byte-identical pre/post (no edits).

- [ ] PRESERVE the `.spring(response: 0.32, dampingFraction: 0.85)` literals at `:150` and `:631` — W13.F owns animation codemod.

- [ ] If coder elects to migrate to `GlassCard(cornerRadius: 14, padding: 0)` wrap for primitive uniformity (per row 16):
  - Drop the explicit `HaloMaterial(shape: shape, phase: .hidden)` background at `:140-142`.
  - Drop the explicit `.clipShape(shape)` at `:149`.
  - Wrap the `VStack(alignment: .leading, spacing: 0) {…}` in `GlassCard(cornerRadius: 14, padding: 0)`.
  - Preserve the `.overlay(shape.stroke(...))` verbatim.
  - Preserve the spec-ref banner at `:20-22`.
  - **If migration introduces visual drift at smoke-test, revert.** This row is **Flag — preserve**.

**Verify:**
- ProviderCard byte-identical pre/post (default path).
- If migrated: rebuild reads visually identical to the pre-migrate state under all four mode/wallpaper combos.

### Task 8 — `WhisperModelManager.DownloadProgressView` accent retint (optional)

**Files:** `VoiceInk/Transcription/Whisper/WhisperModelManager.swift`.

- [ ] At lines 439-445, swap track + fill colours:

  ```swift
  RoundedRectangle(cornerRadius: 4)
      .fill(Palette.hairlineSoft)
      .frame(height: 6)

  RoundedRectangle(cornerRadius: 4)
      .fill(Palette.accent)
      .frame(width: max(0, min(geometry.size.width * totalProgress, geometry.size.width)), height: 6)
  ```

- [ ] PRESERVE the `Color(.secondaryLabelColor)` text foregrounds at `:435, :454` (system tint OK on chrome controls).

- [ ] PRESERVE the `.animation(.smooth, value: totalProgress)` at `:458` — W13.F owns animation codemod.

**Verify:**
- `rg -n 'controlAccentColor' VoiceInk/Transcription/Whisper/WhisperModelManager.swift` returns **0** hits.
- Progress bar reads tangerine-on-soft-hairline-track inside the Whisper card's `progressSection` during a download.

*Risk note:* this file lives outside `VoiceInk/Views/AI Models/`. If the build target separation triggers a permission concern at integration build, coder drops Task 8 and routes to W13.G polish. Default: **sweep** — costs near zero and prevents a visible system-blue progress bar.

### Task 9 — Self-review + grep follow-up

**Files:** none (read-only).

- [ ] Re-run all grep patterns from Task 0. Document remaining hits — they should ALL match this plan's "Defer" or "Flag — preserve" classification (Per-axis rows 16, 17, 19, 20, 21, 22, 23, 24, 25, 26, 27).

- [ ] Confirm `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift`, `RecorderComponents.swift`, all `Constellation/*.swift` are byte-identical pre/post.

- [ ] Confirm `Animation+Halo.swift` reviewer note at `:14-17` is preserved (W13.E doesn't edit that file).

- [ ] Confirm `ProviderCard.swift:20-22` W6 banner comment is preserved (default-preserve path).

- [ ] Confirm `ModelCardView.swift` (the dispatcher) is byte-identical pre/post — it has no chrome of its own, just a switch over provider type.

- [ ] Confirm `ModelManagementView.swift` is byte-identical pre/post (out of scope; the gear `.foregroundColor(.accentColor)` at `:160` is W13.G).

- [ ] Confirm `AddCustomModelView.swift`, `APIKeyManagementView.swift`, `LanguageSelectionView.swift` byte-identical pre/post.

- [ ] Regression guard: zero new `.rounded` introductions across W13.E surfaces — `rg -n 'design:\s*\.rounded' VoiceInk/Views/AI\ Models/` returns **0** hits.

- [ ] Regression guard: zero new `Color.white.opacity(...)` introductions on outer card chrome — only the deferred sub-chip-scale fills in `MLXModelPickerView.swift` lines 151, 163, 179, 248 should remain.

### Task 10 — Visual smoke pass (coder + reviewer)

**Files:** none.

- [ ] Open the app via `make local && open VoiceInk.app` (or via Xcode Run). Navigate to AI Models tab.

- [ ] Eyeball under all four mode/wallpaper combos:
  - (a) System Light + bright wallpaper
  - (b) System Light + dark wallpaper
  - (c) System Dark + bright wallpaper
  - (d) System Dark + dark wallpaper

- [ ] Confirm:
  - Each card variant (Whisper, ImportedWhisper, Cloud, FluidAudio, Native, Custom) renders with `HaloMaterial(phase: .hidden)` chrome via `GlassCard` — no flat opaque white-on-light backplate.
  - Active-card stroke is tangerine (`Palette.accent.opacity(0.55)`) at lineWidth 1.5; rest stroke is `Palette.hairline` at lineWidth 1. No system blue anywhere on card chrome.
  - Download / Configure / Verify CTA capsules are tangerine — no system blue.
  - Download buttons across cards visually align (same Capsule shape, same accent tint, same shadow on Whisper / Cloud sites; FluidAudio's flat-no-shadow preserved).
  - MLX picker rows: rest rows read as obsidian-glass panels with hairline border; active row gets a tangerine accent fill (10% alpha) on top of the glass, plus the 1.5pt accent stroke.
  - Provider card silhouette is unchanged (default path) — identical to pre-merge.
  - WhisperModelManager download progress bar (visible mid-download) reads tangerine-on-soft-hairline-track, not system-blue-on-separator-grey (Task 8).

- [ ] Confirm under Reduce-Transparency (System Settings → Accessibility → Display → Reduce transparency = ON), card chrome falls back to opaque per spec §6.4 (HaloMaterial branches to `AdaptiveGlass.contrastedFill(for: phase)` at `HaloMaterial.swift:138-142`). Cards remain legible.

- [ ] Confirm under Increase-Contrast (Increase contrast = ON), inner strokes become 1pt solid; cards remain legible.

- [ ] Confirm under Reduce Motion (Accessibility → Display → Reduce motion = ON), expand/collapse on Cloud and Provider cards still animates (those animations are out of scope per W13.F) but the visual chrome itself doesn't introduce motion regressions.

- [ ] Compare each card's footprint pre/post:
  - Outer corner radius 16pt (cards) / 14pt (MLX rows + ProviderCard) — unchanged.
  - Inner padding rhythm 16pt (single-section cards) / `padding(16)` per inner section (Cloud / Custom) — unchanged.
  - Active stroke width 1.5pt — unchanged.
  - Rest stroke width 1pt (was 0.5pt, now 1pt — verify visual reads better, not heavier).

### Task 11 — Report to lead

- [ ] Coder reports to `team-lead` via SendMessage:
  - File list edited (5 + 1 conditional + 1 conditional = up to 7 files): `WhisperModelCardView.swift`, `CloudModelCardView.swift`, `FluidAudioModelCardView.swift`, `NativeModelCardView.swift`, `CustomModelCardView.swift`, `MLXModelPickerView.swift`, `WhisperModelManager.swift` (Task 8 if shipped; otherwise 6 files).
  - LOC delta (estimate ~150 lines edited, near-zero net new).
  - Smoke-pass observations (any padding/stroke-width tweaks made vs. recommendations above; whether `glassPanel` modifier or explicit `GlassChip` modifier was used in MLXModelPickerView; whether ProviderCard was migrated or preserved).
  - Whether Task 8 (WhisperModelManager retint) was shipped or deferred.
  - Any flagged items left untouched (with reason).
  - Worktree path for lead's `make local` integration build.

- [ ] Lead handles commits per CLAUDE.md cadence:
  ```
  docs(plans): W13E — AI Models card unification   (this file)
  feat(aesthetic): W13E — AI Models card unification   (the source edits)
  ```

- [ ] After lead's `make local` returns green and the merge commit lands, lead runs the **Post-merge verification protocol** below (user-side).

---

## Verification (coder/reviewer side)

1. **Build green.** `xcodebuild build` (or `make local`) at lead's integration step. Zero warnings, zero errors related to W13.E surfaces.
2. **Grep follow-up clean.** Per Task 9 — all in-scope hits gone; out-of-scope hits unchanged.
3. **Visual smoke green.** Per Task 10 — all four mode/wallpaper combos read tangerine-on-glass for active cards, hairline-on-glass for rest cards.
4. **No primitive drift.** `Palette.swift`, `GlassCard.swift`, `GlassChip.swift`, `Animation+Halo.swift`, `AdaptiveGlassBackground.swift`, `HaloMaterial.swift` byte-identical pre/post.
5. **No recorder-cluster drift.** `RecorderComponents.swift`, `Constellation/ClusterMotion.swift`, all `Halo*Recorder*` panels byte-identical pre/post.
6. **No adjacent-AIModels drift.** `ModelManagementView.swift`, `AddCustomModelView.swift`, `APIKeyManagementView.swift`, `LanguageSelectionView.swift`, `ModelCardView.swift` byte-identical pre/post (those are out of scope or already W13.A-aligned).
7. **No expand-state regression.** Cloud and Provider cards still expand/collapse; Cloud's `Divider` separator still appears between mainHStack and configurationSection; verify state, key entry, key removal flows still work.

---

## Rollback plan

Single-commit packet (`feat(aesthetic): W13E — AI Models card unification`). If a regression surfaces post-merge:

```bash
git revert <feat-sha>
```

Reverts cleanly because every edit is bounded to ≤7 files, no schema migrations, no dependency changes, no test-fixture drift, no spec amendments. The `docs(plans): W13E — …` commit can stay (the plan document is reusable across re-attempts).

If a *partial* regression surfaces (e.g. the MLX row chrome reads off but the cards are fine), rollback the offending file via:

```bash
git checkout <feat-sha>~1 -- VoiceInk/Views/AI\ Models/MLXModelPickerView.swift
```

…and re-commit. Preserves the rest of the rebuild.

If Task 8 (WhisperModelManager retint) introduces a visual regression on a surface other than AI Models (e.g. if `DownloadProgressView` is reused elsewhere — verify via `rg -n 'DownloadProgressView' VoiceInk/`), rollback the single file:

```bash
git checkout <feat-sha>~1 -- VoiceInk/Transcription/Whisper/WhisperModelManager.swift
```

Pre-grep at planning shows `DownloadProgressView` is referenced only at `WhisperModelCardView.swift:111` — single call site. Risk: low.

---

## Risks

1. **GlassCard padding default vs explicit (low).** GlassCard's `padding` arg defaults to 14pt; v1 cards used `.padding(16)`. Tasks 1, 3, 4 pass `padding: 16` explicitly to preserve the v1 rhythm. Cloud / Custom (Tasks 2, 5) use `padding: 0` and let the inner section's `.padding(16)` carry. Risk: if a coder picks `padding: 14` on Tasks 1/3/4 (default), cards read ~2pt tighter than v1. Mitigation: explicit `padding: 16` per task above; smoke-test verifies.

2. **Active stroke alpha 0.45 → 0.55 visual delta (low).** v1 cards used `Color.accentColor.opacity(0.45)`; this plan moves to `Palette.accent.opacity(0.55)` matching `ProviderCard.swift:145`. Net: +0.10 alpha on the active stroke. Risk: active card reads slightly more saturated than v1. Mitigation: aligns with the rest of the AI Models surface (ProviderCard, MLXModelPickerView active row). Not a regression — this is the locked vocabulary alpha. If reviewer flags, fall back to `0.45` per-card site (minor drift from the family).

3. **Rest stroke width 0.5pt → 1pt visual delta (low).** v1 cards used `lineWidth: 0.5`; this plan moves to `1pt` matching `ProviderCard.swift:146` family default. Net: rest card outline reads slightly heavier. Mitigation: aligns with the family. If reviewer flags, fall back to `0.5pt` (minor drift).

4. **MLXModelPickerView padding regime (low).** `glassPanel(cornerRadius: 14)` modifier supplies 14h/12v padding by default; v1 row uses square `.padding(12)`. Two paths in Task 6: (A) drop `.padding(12)` and accept the modifier's 14h/12v (closer to spec §1; row reads slightly wider) or (B) call the explicit `GlassChip(cornerRadius: 14, paddingH: 12, paddingV: 12)` modifier (preserves v1 12pt square). Risk: visual drift either way. Mitigation: smoke-test gates the choice; default to (A) per W13.B's per-row defer-to-spec preference.

5. **CloudModelCardView expand-state divider visibility (low).** Outer GlassCard with `padding: 0` means the inner `Divider().padding(.horizontal, 16)` floats inside the GlassCard's hairline border. v1 had the same — verify that Divider still reads visually distinct from the inner stroke. If it bleeds into the GlassCard inner-edge sheen, switch to `Divider().background(Palette.hairlineSoft).padding(.horizontal, 16)` (explicit hairline tint).

6. **WhisperModelManager.DownloadProgressView reuse (low).** Risk: the struct is reused outside the AI Models card surface and our retint introduces visual drift elsewhere. Pre-grep shows single call site (`WhisperModelCardView.swift:111`). Mitigation: §Rollback's per-file revert path covers this; smoke-test catches it.

7. **`Color.white.opacity(0.08)` semantic clash (low).** Pre-W13 hairlines were 0.08; spec §1 locks 0.16 (`Palette.hairline`) and 0.10 (`hairlineSoft`). Risk: 0.08 was deliberately softer — moving to 0.16 reads slightly heavier. Mitigation: the locked vocabulary is 0.16; aligning. If a reviewer pushes back, fall back to `Palette.hairlineSoft` (0.10 — closer to v1 0.08) per-card site.

8. **ProviderCard Optional-migrate path (low).** If the coder elects to migrate ProviderCard from inline-HaloMaterial to GlassCard wrap, two things change visually: (a) the `.clipShape` is now applied inside HaloMaterial's `:168` (was inline at `:149`) — equivalent. (b) the `.background(HaloMaterial(...))` is wrapped in a content closure — equivalent. Net visual delta: zero. Risk: if migration introduces an unexpected SwiftUI layout difference (e.g. `frame` propagation), pre-merge smoke catches it. Mitigation: default-preserve. If migrated, smoke-test under all four mode/wallpaper combos.

9. **Verify-button `Color(.systemGreen)` → `Palette.success` semantic (low).** v1 used `.systemGreen` (#30D158-ish system); plan uses `Palette.success` (#30D158 locked). Visually nearly identical; semantic drift is a tighter palette. No risk.

10. **GlassCard composes its own `.clipShape` (verify, low).** Task 1-5 drop the inline `.clipShape(...)` since `HaloMaterial.swift:168` carries it. Risk: if there's a SwiftUI layout edge case where the outer `.overlay(...stroke...)` is clipped by `HaloMaterial`'s clipShape and the stroke vanishes outside the clip, the card reads strokeless. Mitigation: smoke-test verifies stroke is visible. If not, restore the outer `.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))` after the overlay.

---

## Open questions for lead

1. **ProviderCard migrate-or-preserve?** Per Per-axis row 16 — recommended preserve (visual identical, has its own W6 spec-ref banner). Alternative: migrate to `GlassCard(cornerRadius: 14, padding: 0)` for primitive uniformity across the AI Models tab. Lead picks at sign-off; coder defaults to preserve.

2. **WhisperModelManager Task 8 — ship or defer?** Per Per-axis row 18 — recommended ship (one-line each retint, prevents a system-blue progress bar inside a tangerine-stroked card). Alternative: defer to W13.G polish if the file's location outside `VoiceInk/Views/AI Models/` triggers a build-target permission concern at integration. Coder defaults to ship; can drop if integration build flags target boundaries.

3. **MLXModelPickerView padding regime — Option A (modifier default 14h/12v) or Option B (explicit 12pt square)?** Per Per-axis row 14 / Risks row 4. Recommended: Option A (closer to spec §1, GlassPanel canonical rhythm). Lead picks; coder smoke-tests.

4. **Active stroke alpha — `Palette.accent.opacity(0.55)` (family-aligned) or `0.45` (v1-preserved)?** Per Risks row 2. Recommended: `0.55` (locked family vocabulary). If reviewer pushes back during smoke, fall back to `0.45`. Lead picks if visual drift is a concern.

5. **Rest stroke width — `1pt` (family-aligned) or `0.5pt` (v1-preserved)?** Per Risks row 3. Recommended: `1pt`. Same fallback path as Q4.

6. **Rest stroke alpha — `Palette.hairline` (0.16, family-aligned) or `Palette.hairlineSoft` (0.10, closer to v1 0.08)?** Per Risks row 7. Recommended: `Palette.hairline` (locked vocabulary). Same fallback path as Q4.

7. **Cloud card Divider tint — preserve system or explicit `Palette.hairlineSoft`?** Per Risks row 5. Recommended: preserve system; smoke-test gates explicit retint.

8. **Adjacent surfaces — `AddCustomModelView`, `APIKeyManagementView`, `LanguageSelectionView` — fold into W13.E or split as siblings?** Per Per-axis row 22. Master plan §4 W13.E's bullets and brief 2026-04-30 explicitly limit scope to the 5 card files + ProviderCard. **Recommended: split out as W13.E2** (AddCustomModel + APIKeyManagement + LanguageSelection — small plan, single coder/reviewer pair). Lead picks; coder defers regardless.

---

## Post-merge verification protocol (USER-SIDE)

Run after lead merges `feat(aesthetic): W13E — …` to main and the build is green.

1. **Capture baseline screenshots BEFORE merge** (if not done at sign-off):
   - Navigate to AI Models tab. Expand at least one provider that exposes each card type:
     - **Whisper** (any local provider)
     - **ImportedWhisper** (if user has imported a custom whisper)
     - **Cloud** (e.g. OpenAI / Anthropic / Groq — any cloud provider configured or unconfigured)
     - **FluidAudio** (FluidAudio provider)
     - **Native** (Foundation Models provider on macOS 26+)
     - **Custom** (any custom OpenAI-compatible cloud model)
     - **MLX** (expand `mlx` provider; pick at least one curated model row + one detected row if available)
   - Screenshot each card variant at default window size, system Light + system Dark, on bright + dark wallpaper. (Roughly 28 screenshots — 7 variants × 4 mode/wallpaper combos.)
   - File these to `docs/superpowers/research/2026-04-30-W13E-pre-merge-screenshots/` for diff reference.

2. **Open the AI Models tab post-merge.** Compare each card variant against pre-merge screenshot:
   - Outer corner radius preserved (16pt cards / 14pt MLX rows + ProviderCard).
   - Active card stroke is tangerine (`Palette.accent.opacity(0.55)` at lineWidth 1.5).
   - Rest card stroke is `Palette.hairline` (white α 0.16) at lineWidth 1.
   - Card chrome adapts to wallpaper luminance (`GlassAppearanceDetector` switches onyx/light variant).

3. **CTAs:**
   - Download / Configure / Verify capsules are tangerine — no system blue.
   - Verify-success state is `Palette.success` green.
   - FluidAudio Download capsule preserves the v1 flat-no-shadow.

4. **MLX picker rows:**
   - Rest row reads as obsidian-glass panel with hairline border.
   - Active row gets tangerine accent fill (10% alpha) overlay on top of the glass.
   - Active stroke 1.5pt tangerine; rest stroke 1pt hairline.
   - Rating chips / latency chips / `(N) GB` chip / progressChip preserve their existing tints (white α 0.04-0.06 fills + `Palette.hairline` strokes — out of scope, do not retint).

5. **ProviderCard:**
   - Default path: byte-identical to pre-merge.
   - Migrated path (if coder chose): visually identical to pre-merge under all four mode/wallpaper combos. Spec-ref banner at `:20-22` preserved.

6. **Whisper download progress bar (Task 8 path):**
   - Track is `Palette.hairlineSoft` (white α 0.10) — soft glass-aligned grey, not system separatorColor.
   - Fill is `Palette.accent` tangerine — not system blue.
   - Animation cadence preserved (`.smooth` — W13.F owns the codemod).

7. **Cloud expand-state:**
   - Card still expands/collapses on Configure click.
   - Divider between mainHStack and configurationSection still visible.
   - API key entry, Verify, success/failure states still functional.
   - Verify-success switches to green `Palette.success` capsule.

8. **No `.rounded` font anywhere on this surface.** Confirm visually — all card text is system default.

9. **Accessibility passes:**
   - System Settings → Accessibility → Display → Reduce transparency = ON. Re-open AI Models. Card chrome falls back to opaque per spec §6.4. Cards remain legible.
   - Increase contrast = ON. Inner strokes become 1pt solid; cards remain legible.
   - Reduce motion = ON. Cloud expand/collapse no longer aggressively springs (out of scope per W13.F — verify it doesn't introduce a regression but don't chase the codemod here).

10. **If any check fails**, surface to lead via SendMessage with screenshot + verbal description. Hot-fix paths in §Rollback.

---

## Follow-ups for adjacent W13 packets

### W13.E2 — `AddCustomModelView` + `APIKeyManagementView` + `LanguageSelectionView` adjacent rebuild (recommended split)

`AI Models/AddCustomModelView.swift:157` accent button + accent shadow are already on W13.A's modified-files list (axis A). If W13.A landed, verify; otherwise route. `APIKeyManagementView.swift` and `LanguageSelectionView.swift` likely have residual system-blue / Form-host chrome — not in W13.E's scope. Small plan (~150 lines), single coder/reviewer pair, mirrors W13.E shape.

### W13.F — History window glass + animation codemod (already planned, separate task)

This packet owns the `.spring(0.32, 0.85)` literal at `ProviderCard.swift:150, 631` codemod, the `.interpolatingSpring(stiffness: 170, damping: 20)` at `CloudModelCardView.swift:169`, the `.easeInOut(duration: 0.3)` literals at `CloudModelCardView.swift:298, 321`, and `WhisperModelManager.swift:458` `.smooth`. W13.E preserves these verbatim.

### W13.G — Polish (already planned)

Owns the residual stragglers across AI Models surfaces:
- `ModelManagementView.swift:160` (`.foregroundColor(.accentColor)` on gear icon).
- `MLXModelPickerView.swift:151, 163, 179, 248` (`Color.white.opacity(0.04-0.06)` chip fills) — coder eval per W13.A's flag.
- Any residual `Color.white.opacity(...)` strokes on the MLX rating-chip / latency-chip / detected-chip surfaces if W13.A's flag escalates to a sweep.
- `AppNotificationView.swift` per-type rainbow → single-accent-with-motion-discriminator (master plan §4 W13.G).
- `CompactHeroSection.swift` blue→accent (master plan §4 W13.G).
- `EnhancementPromptPopover.swift` backdrop + force-dark-colorScheme drop (master plan §4 W13.G).

### Final spec extension (after W13.A-G land, per master plan §4 W13.G)

Amend `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1.X (or write `2026-04-30-aesthetic-redesign-W13-deltas.md`) with:
- W13.E sign-off: AI Models cards composed via `GlassCard(cornerRadius: 16)` primitive; active stroke is `Palette.accent.opacity(0.55)` at 1.5pt; rest stroke is `Palette.hairline` at 1pt. Cloud / Custom multi-section cards use `padding: 0` outer with inner `.padding(16)` per section.
- MLXModelPickerView rows composed via `glassPanel(cornerRadius: 14)` modifier; active-state fill is `Palette.accent.opacity(0.10)` overlay.
- ProviderCard inline composition is the source-of-truth pattern; cards mirror its stroke vocabulary.
- WhisperModelManager.DownloadProgressView retinted track + fill (if Task 8 shipped); spec amendment optional since this is sub-component chrome.
