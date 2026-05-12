# Mission kickoff: Voiceink Phase D — Sotto UI redesign + rebrand

**Date drafted:** 2026-05-12
**Status:** ready for `/mission` Phase 1 planning
**Prerequisite:** Phase C merged to `origin/main` at `fdeb92c`. PR #2 closed. Spec + 7 per-pair plans on disk.

## How to invoke

From a fresh session, in any cwd:

```
/mission Read ~/foyer/repos/dotfiles/docs/handoffs/MISSION_voiceink-phaseD-sotto-redesign_2026-05-12.md and run /mission's Phase 1 to draft plan.md + per-milestone contracts. Wait for approval.
```

`/mission` will create its own worktree at `~/.worktrees/voiceink-phaseD-sotto/`, copy this file as orientation, draft a thin `plan.md` that REFERENCES the 7 existing per-pair plans (do NOT redraft them), per-milestone `contract.yaml` files, then halt for approval.

## Goal

Implement the Sotto UI redesign + rebrand — the full visual + brand overhaul drafted during a 6-foundation iterative-visual-mockups brainstorm, 3-critic adversarial review (codex + opus + sonnet), 2-designer synthesis (minimal-touch + structural), and 7 per-pair implementation plans. Land it in 7 parallel pairs over ~3 weeks on a `redesign/sotto` integration branch, then merge to `main`.

**Spec (locked):**
- `/Users/priyanshu/Desktop/Projects/pu/voiceink-fork/docs/superpowers/specs/2026-05-11-sotto-ui-redesign-design.md`

**Per-pair plans:**
- `docs/superpowers/plans/2026-05-11-sotto-rename-plan.md` (1,421 lines · 10 steps · 3 phases)
- `docs/superpowers/plans/2026-05-11-sotto-icon-plan.md` (728 lines · 7 tasks)
- `docs/superpowers/plans/2026-05-11-sotto-menubar-plan.md` (1,394 lines · 8 tasks + spike)
- `docs/superpowers/plans/2026-05-11-sotto-hud-plan.md` (1,941 lines · 31 tasks · 6 groups · 6 landable PRs)
- `docs/superpowers/plans/2026-05-11-sotto-settings-plan.md` (1,039 lines · 25 tasks · 5 groups)
- `docs/superpowers/plans/2026-05-11-sotto-main-plan.md` (1,322 lines · 7 tasks)
- `docs/superpowers/plans/2026-05-11-sotto-onboarding-plan.md` (1,533 lines · 17 steps · 3 groups)

Total planning: ~9,378 lines across 7 plans.

## Confirmed locked foundations (do NOT re-litigate)

| Foundation | Locked value |
|---|---|
| Brand name | **Sotto** (Italian *sotto voce*, "under one's voice") |
| Material | Tactical Glass — `HaloMaterial`-grounded 8-layer compose, NOT CSS-equivalent |
| Accent | Acid Lime `#D4FF3A` |
| Structure | Bay — single NSPanel + capsule + 2 stalactite chips (NOT 3 panels) |
| Chips | Symmetric Glass (Q4.5 — user override of Asymmetric Command) |
| Idle | Invisible — `orderOut` + SwiftUI subtree unmount (NOT ambient whisper) |
| State morphology | 7 states with dual-surface (notch HUD + menubar icon) — `idle / arming / recording / transcribing / enhancing / committed / fail` |
| Scope tier | Recommended (7 teammate pairs · ~3 weeks parallel) |
| Domain | **None.** No public web presence. Sparkle policy TBD (see open questions). |

## Suggested milestone breakdown (advisory — /mission's Phase 1 may revise)

Plans already enumerate per-pair tasks. /mission Phase 1 wraps these as milestones:

| Milestone | Pair(s) | Why | Plan refs |
|---|---|---|---|
| **m01 — RENAME** | RENAME (solo) | Critical path. UserDefaults shim, SwiftData store move, bundle ID, OSLog 51-call swap, Keychain dual-list, pbxproj surgery. Everyone else's file paths depend on this. | `sotto-rename-plan.md` |
| **m02 — Foundation parallel** | HUD + ICON + MENUBAR | Independent of each other after RENAME. HUD owns `TacticalGlass` primitive + `Palette.brandAcid` + state machinery — produces shared tokens. ICON exports glyph assets. MENUBAR Task 0 spike branches Path A (Canvas) vs Path B (asset fallback). | `sotto-hud-plan.md`, `sotto-icon-plan.md`, `sotto-menubar-plan.md` |
| **m03 — Settings + Main parallel** | SETTINGS + MAIN | Both depend on HUD's `TacticalGlass` primitive. Visual re-skin only — no behavior changes. W14F Models pane is shipped (commits `924f9a6` + `b1148d2`); SETTINGS audit + delta only, no reimplementation. | `sotto-settings-plan.md`, `sotto-main-plan.md` |
| **m04 — ONBOARDING** | ONBOARDING | Net-new (no existing onboarding view — monetization stripped). Largest design-decisions footprint (13 items D1–D13). Lands last so toast styling can consume final HUD state colors. | `sotto-onboarding-plan.md` |

**Total: 7 features across 4 milestones.** Meets `/mission`'s capability-advisor floor (≥3 milestones, ≥5 features).

Phase 1 should resolve open-question batch (below) BEFORE generating `contract.yaml` files — several decisions feed contract `forbid_patterns` and `paths.forbidden`.

## Open questions for user (Phase 1 surfaces these in `plan.md`)

### Sparkle policy

- **Q1**: Drop Sparkle auto-update entirely (build-from-source only) OR GH Pages feed at `https://priyanshuupadhyay.github.io/voiceink-fork/appcast.xml`?
- **Default**: drop entirely (no domain ≈ no public release ≈ no Sparkle).

### Trademark spike

- **Q2**: Keep the USPTO Class 9/42 trademark spike for "Sotto", or drop it given no public shipping?
- **Default**: drop. Personal/internal-fork branding doesn't trigger trademark scrutiny.

### HUD spike defaults (3) — `sotto-hud-plan.md` resolved these in-plan; user confirms or overrides

- **Q3 — B.MultiMonitor anchoring**: 240pt virtual-notch fallback on external/non-notch displays. (default)
- **Q4 — B.ArmingSkip threshold**: always render arming for ≥120ms (skip mic-init optimization). (default)
- **Q5 — B.UndoCollision**: hotkey re-invocation within 1.5s commits window → new recording wins; UNDO requires explicit chip tap. (default)

### ONBOARDING design decisions D1–D13 — `sotto-onboarding-plan.md` blocks Group B until resolved

All have defaults — user rubber-stamps or individually overrides. Summary:

| ID | Decision | Default |
|---|---|---|
| D1 | Welcome tagline copy | `› sotto voce · under your voice` |
| D2 | Get-started CTA label | `▸ Get started` |
| D3 | Permissions layout | wizard (one screen per permission) |
| D4 | Mic permission required-to-advance | yes |
| D5 | A11y + screen-rec permission level | recommended (not required) |
| D6 | Model-download flow | defer to Settings |
| D7 | Hotkey reminder presentation | one-shot top-anchored toast |
| D8 | Onboarding window topology | borderless 480×640 panel |
| D9 | Skip-all escape hatch | yes, top-right `›` |
| D10 | First-invocation signal | any path counts (vs hotkey-only) |
| D11 | Toast position | top under notch (HUD-state) / bottom (system info) |
| D12 | Reduce-motion toast entry | opacity-only fade |
| D13 | Finish CTA label | `▸ Finish` |

### Minor coordination (defer to PR review, not Phase 1 approval)

- **Q6** — `brandAcid` token merge timing between RENAME pair and HUD pair (HUD owns `Palette.brandAcid`; RENAME may temporarily stub).
- **Q7** — `ScratchpadTabEditor` body text: SF Pro (user-typed prose) per §1 carve-out, or SF Mono throughout?
- **Q8** — SETTINGS chip-rendering coordination — HUD pair owns `B.ModeList` (9-char uppercase truncation); SETTINGS imports.
- **Q9** — ICON §5.2 underscore-width discrepancy (plan uses 0.92S vs spec'd 1.00S — imperceptible at 22px).

### Already decided (do NOT re-open in Phase 1)

- Domain: **none** (no public release).
- Trademark: dropped (see Q2 default).
- "Sotto" brand name: **locked**.
- All material / structure / state / scope foundations: **locked** (see table above).

## Out of scope (parking-lot items — DO NOT include)

Per `docs/superpowers/specs/2026-05-06-handoff-and-next-steps.md` § "Parking lot":

- Phase **C2** — CSV reconciliation + Phase B/C cleanup (has its own handoff: `MISSION_voiceink-phaseC2-cleanup_2026-05-11.md`). Independent of Phase D — can run before, after, or in parallel.
- Phase **E** — per-app prompt template content
- Phase **F** — `<ACTIVE_URL>` browser URL injection
- Phase **G** — window-title-based subdetection
- Phase **H** — Gemma 2/3 MLX evaluation
- Phase **I** — prompt-content storage hardening
- Phase **J** — custom integrations (Ghostty / VS Code / Cursor / Slack / Mail)

**Within-Phase-D out of scope:** new features (CLI, command palette, snippet library, sound design, marketing site). All seven appear in the Recommended-tier scope §6.4 as "Deferred (post-redesign backlog)."

If `/mission` Phase 1 surfaces any of these, the user should `edit` them out before `approved`.

## Phase A + B + C non-interference constraints

Bake into every contract's `forbid_patterns`:

```
- EnableMLXFallback
- EnhancementTimeoutSeconds
- ContextSanitizer\.sanitize
- MLXProvider\.ProviderError\.timedOut
- EnableContextSanitization
- EnableEnhancementFailureNotification
- SessionMetric\s+@Model       # Phase C surface — don't redefine
- stats\.store                  # Phase C container path — read-only
- enhancement-timings\.csv      # Phase C2 territory — don't touch CSV writer
```

Bake into every contract's `paths.forbidden`:

```
- "VoiceInk/Transcription/Whisper/**"      # transcription engine — out of scope for redesign
- "VoiceInk/Transcription/FluidAudio/**"   # speaker-id engine — out of scope
- "VoiceInk/Transcription/Engine/**"       # NotchRecorderPanel + RecorderUIManager allowed via paths.source per HUD plan
- "VoiceInk/Resources/models/**"           # ML model assets — read-only
- "VoiceInk-Dependencies/**"               # vendored frameworks — read-only
- "**/*.xcodeproj/project.pbxproj"         # ONLY RENAME pair touches this (allow via paths.source)
- "**/*.xcuserstate"
- "**/xcuserdata/**"
```

**Per-pair paths.source allowances** (specified in each plan's "files touched" section):

- **RENAME** owns: `*.xcodeproj/project.pbxproj`, `VoiceInk/VoiceInk.swift` (SwiftData paths), `VoiceInk/VoiceInk.entitlements`, `VoiceInk/Info.plist`, all `Logger(subsystem:)` call sites (51 across 5 unique subsystems).
- **HUD** owns: `VoiceInk/Views/Recorder/**`, `VoiceInk/Views/Common/Palette.swift`, `VoiceInk/Transcription/Engine/RecorderUIManager.swift`, new `Sotto/Theme/MotionTokens.swift`.
- **MENUBAR** owns: `VoiceInk/Views/Common/MenuBarIconRenderer.swift`, `VoiceInk/VoiceInk.swift` lines 476–502.
- **ICON** owns: `VoiceInk/Assets.xcassets/**`.
- **SETTINGS** owns: `VoiceInk/Views/Settings/**`, `VoiceInk/Views/Models/**`, `VoiceInk/Views/AI Models/**`, `VoiceInk/Views/PermissionsView.swift` (shared w/ ONBOARDING via PermissionRow extraction).
- **MAIN** owns: `VoiceInk/Views/ContentView.swift`, `VoiceInk/Views/MetricsView.swift`, `VoiceInk/Views/Metrics/**`, `VoiceInk/Views/Snippets/**`, `VoiceInk/Views/Scratchpad/**`, `VoiceInk/Views/Dictionary/**`.
- **ONBOARDING** owns: new `Sotto/Views/Onboarding/**`, `VoiceInk/HotkeyManager.swift` line 21 (first-run sentinel), `VoiceInk/Notifications/AnnouncementManager.swift`.

`AIEnhancementService.swift` remains under `forbid_patterns` for HUD's mode-list reconciliation (read-only — confirm names against `PredefinedPrompts.all`).

## Stack / build recipe

- Stack: swift (Xcode project, no Package.swift for primary target)
- Worktree pattern: `~/.worktrees/voiceink-phaseD-sotto/`
- Branch: `mission/2026-05-12-voiceink-phaseD-sotto`
- Integration branch (within the worktree): `redesign/sotto` — each pair lands a PR onto this; final merge to `main` after holistic QA.
- Base SHA: `fdeb92c` (current `origin/main` tip after Phase C merge)

Signing recipe (verbatim for all `xcodebuild test/build` commands — `voiceink-fork-local` cert must be in keychain; see Bug #12 in Phase B `findings.md`):

```
-configuration Debug -xcconfig LocalBuild.xcconfig -skipMacroValidation -quiet \
  CODE_SIGN_IDENTITY=voiceink-fork-local CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM= ENABLE_HARDENED_RUNTIME=NO \
  CODE_SIGN_ENTITLEMENTS=$PWD/VoiceInk/VoiceInk.local.entitlements
```

Pre-flight check (mission orchestrator should run at Phase 1 start):

```
security find-identity -p codesigning -v | grep voiceink-fork-local
```

Verified 2026-05-11: cert present in keychain (2 entries).

**Special pre-flight for Phase D — keychain entitlement during RENAME:**

The RENAME pair adds a transitional dual-list keychain access group (`$(AppIdentifierPrefix)com.prakashjoshipax.VoiceInk` AND `$(AppIdentifierPrefix)com.sotto.Sotto`) per spec §7.1.Keychain. After m01 lands, signing recipe stays the same; the entitlements file gets the second access group. Validators must verify the dual-list survives test builds.

## Pointers for the orchestrator

- **Skill location:** `~/.claude/skills/mission/` (symlinked to `~/foyer/repos/dotfiles/home/.claude/skills/mission/`)
- **Codex CLI:** `/opt/homebrew/bin/codex` v0.121.0 — preferred validator per `state.yaml.models.validator=codex`. Dispatch non-interactively via `codex exec --full-auto -s workspace-write -C <worktree> --skip-git-repo-check '<prompt>'`. Codex sandbox blocks outbound `api.github.com`; capture output to `/tmp/*.md` and post via parent's `gh pr review --body-file` when needed.
- **Agent model enum** does NOT include codex. Codex teammates run via background Bash; opus + sonnet + haiku run via Agent teammate.
- **Bash-only libs:** all `~/.claude/skills/mission/references/lib/*.sh` refuse zsh. Wrap every invocation in `/bin/bash -c '...'` — Bash tool defaults to zsh on macOS.
- **`state_write` contract:** content-as-string, not a path. Read-modify-write NOT supported — use `yq -i` to mutate `state.yaml`, then `state_verify_with_manual_ack` to rebake the hash via `manual_edit_at`.
- **Worktree vs canonical clone:** canonical clone at `~/Desktop/Projects/pu/voiceink-fork` should be on `main` at `fdeb92c` or later. Mission worktree fresh at `~/.worktrees/voiceink-phaseD-sotto/`.

## Mission strategy notes (advisory for Phase 1)

Phase D's per-pair plans are unusually thick (1,941 lines for HUD alone). Phase 1's `plan.md` should be THIN and reference-heavy — pointing at the 7 plan docs rather than copying them. Per-milestone `contract.yaml` files include:

- `success_criteria`: per the pair's plan's "acceptance" section
- `feature_test_cmd`: usually `xcodebuild test ... -only-testing:VoiceInkTests/<pair>Tests` once tests exist; otherwise the build-only `xcodebuild build` with signing recipe
- `must_exist`: file paths from the plan's "files created" section
- `paths.source`: exact entries from the per-pair table above

**Integration branch strategy:**

- Each pair lands its PR(s) onto `redesign/sotto` (not `main`)
- HUD pair has 6 internal PRs (per its plan); each lands on `redesign/sotto`
- After all pairs land + QA passes holistically (highest risk: RENAME's bundle ID + UserDefaults migration seam), `redesign/sotto` → `main` as a single merge

**`/mission` self-heal budget per the orchestrator spec:** 3 rounds per feature, 3 rounds per milestone gate, infra-retry exception once. RENAME's UserDefaults migration shim is the most likely defect-loop candidate — pair should write the shim test FIRST (TDD via `superpowers:test-driven-development`).

## Current session state (snapshot at handoff time)

This handoff is being drafted at the conclusion of a multi-step UI brainstorm + plan-writing session on team `voiceink-ui-d1`:

**Phase D — Sotto UI redesign:**
- 6-foundation iterative-visual-mockups brainstorm complete. All 6 foundations locked.
- Spec drafted (v1) → 3-critic adversarial review (codex cross-family + critic-d1 opus + prod-d1 sonnet) → 2-designer synthesis (designer-d2 minimal-touch sonnet + designer-d3 structural opus) → final canonical spec at `2026-05-11-sotto-ui-redesign-design.md` (629 lines).
- 7 per-pair plans drafted in parallel by `planner-{rename,icon,menubar,hud,settings,main,onboarding}` teammates. All 7 on disk.
- Team `voiceink-ui-d1` now empty (all teammates terminated cleanly).

**Phase C2 — Cleanup mission** (separate handoff at `MISSION_voiceink-phaseC2-cleanup_2026-05-11.md`):
- Drafted but not yet executed. Independent of Phase D.

**Uncommitted state on `main`:**
- Spec + 3 variant specs (`-v2a-minimal.md` + `-v2b-structural.md` as audit trail) untracked in `docs/superpowers/specs/`
- 7 plans untracked in `docs/superpowers/plans/`
- Brainstorm artifacts at `.superpowers/brainstorm/59608-1778494162/` (gitignored, persist on disk)
- No code changes — nothing under `VoiceInk/**` touched

**Recommended pre-kickoff hygiene** (optional):
- Commit the spec + plans before kicking off `/mission` so the worktree branches from a clean tree.
- `git add docs/superpowers/specs/2026-05-11-sotto*.md docs/superpowers/plans/2026-05-11-sotto-*.md && git commit -m "spec: Sotto UI redesign (Phase D) — locked spec + 7 plans"`
- Or skip — `/mission` will create the worktree from `HEAD` regardless.

## Where Phase D work integrates back to main

On `done` + `land`:
- `/mission` invokes `superpowers:finishing-a-development-branch`
- Each pair PR lands on `redesign/sotto`
- After all 7 pairs land + QA passes: `redesign/sotto` → `main` via single merge PR
- After merge: fast-forward local `main` ref in canonical clone via `git fetch origin main:main`
- No brew cask update (no domain → no distribution → no cask).

## Prior-session artifacts (read-only context)

**Specs:**
- Canonical: `~/Desktop/Projects/pu/voiceink-fork/docs/superpowers/specs/2026-05-11-sotto-ui-redesign-design.md`
- Variant audit trail: `-v2a-minimal.md`, `-v2b-structural.md` (same dir)
- Brainstorm-era specs (not v1 of Sotto — older work): `2026-04-27-voiceink-fork-embedded-llm-design.md`, `2026-04-28-aesthetic-redesign.md`, etc.

**Plans:** all 7 per-pair plans listed in **Goal** section above.

**Brainstorm mockups + 3-critic review:**
- `~/Desktop/Projects/pu/voiceink-fork/.superpowers/brainstorm/59608-1778494162/content/` — 9 HTML mockups (material · accent · accent-tactical-glass · structure · idle · state-cycle · chips · brand · scope · waiting-spec)
- Critique sources: `/tmp/codex-sotto-spec-review.md`, `/tmp/critic-d1-sotto-spec.md`, `/tmp/prod-d1-sotto-spec.md` (transient — `/tmp` may have been cleared by the time you read this)

**Phase B handoff:** `~/foyer/repos/dotfiles/docs/handoffs/HANDOFF_voiceink-phaseB-complete_2026-05-11.md`
**Phase C handoff:** `~/foyer/repos/dotfiles/docs/handoffs/MISSION_voiceink-phaseC-sessionmetric_2026-05-11.md`
**Phase C2 handoff:** `~/foyer/repos/dotfiles/docs/handoffs/MISSION_voiceink-phaseC2-cleanup_2026-05-11.md`

**Phase C mission audit trail:** `~/.worktrees/voiceink-phaseC-sessionmetric/.mission/2026-05-11-voiceink-phaseC/` (events.jsonl, plan.md, milestones/)

**Roadmap / parking lot:** `~/Desktop/Projects/pu/voiceink-fork/docs/superpowers/specs/2026-05-06-handoff-and-next-steps.md`

**Foundation source commits (Phase C):**
- m01 SessionMetric core: `7cc15b6` (model) · `d1e7d25` (container) · `15ec8ea` (migration)
- m02 instrumentation: `5854f4f` (recorder) · `b0912ed` (pipeline)
- m03 UI: `bda92c1` (panel scaffold) · `eee2e36` (mount)

**W14F (already shipped on main, audit-only for SETTINGS pair):**
- `924f9a6 feat(settings): W14F — Models pane two-tab + provider accordion`
- `b1148d2 feat(mlx): W14F — refresh curated lineup post hunter/challenger research`
- Post-ship report: `W14F_ui_redesign_report.md` at repo root (untracked)
