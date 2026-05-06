# Handoff & Next Steps — 2026-05-06

**Audience:** future-me / new-chat picking this up after the 2-day Phase A measurement window (target: **on or after 2026-05-08**).

## TL;DR

- **Phase A is shipped.** 5 commits on `origin/main` plus a recorder full-screen fix. Build is live at `/Applications/VoiceInk.app`.
- **Action required from the user (Day-1 / Day-2):** dogfood VoiceInk normally for 2 days, then evaluate the success gates below.
- **If gates hold:** Phase B (ACTIVE_APP tag + Power Mode Slack/Ghostty/Claude Code presets) is unblocked. Spec section already exists in the Phase A design doc — a fresh design pass is the right starting point.
- **If gates fail:** rollback knobs are documented below; flip the relevant `Enable*` UserDefault, no code revert needed.

## What shipped

### Phase A — incident response (codex GREEN, deployed 2026-05-06)

Branch `phaseA-pipeline-tightening` merged fast-forward to `main` at `9908546`. Five commits in order:

| SHA | Track | What |
|---|---|---|
| `9e13493` | T4a | `EnableEnhancementFailureNotification` kill-switch around the existing `NotificationManager.shared.showNotification(...)` |
| `3655ac0` | T2 | Hide `mlx-community/LFM2.5-1.2B-Instruct-4bit` from the curated MLX picker; `lfm2` model_type stays in the loadable allow-list |
| `217c97b` | T1 | Bump `EnhancementTimeoutSeconds` default 7→15s; add `MLXProvider.ProviderError.timedOut(seconds:)`; single-shot MLX→LFM2.5 fallback chain on timeout, gated by `EnableMLXFallback` |
| `2d0803d` | T5 | New `ContextSanitizer.swift` (idempotent, tail-prefer truncation + line-level secret redaction); wired into all 4 context-block sites in `getSystemMessage` via `bound()` helper; gated by `EnableContextSanitization` |
| `9908546` | docs | Phase A spec, plan, and parking lot doc |

Three originally-planned spec tracks (T3 prompt-redaction, T4b clipboard restore, T4c Power Mode default model) were **verified as already-absorbed no-ops** by W11/W14 work — see `docs/superpowers/specs/2026-05-06-pipeline-tightening-design.md` for the verification details.

### Notch recorder full-screen visibility fix (2026-05-06, deployed)

Commit `77ec33c` on `main`. Two changes to `VoiceInk/Views/Recorder/NotchRecorderPanel.swift`:

1. Window level bumped from `.statusBar + 3` (28) to `.popUpMenu` (101) — composites above Metal-presented and stage-manager-style full-screen apps.
2. Observer for `NSWorkspace.activeSpaceDidChangeNotification` (NSWorkspace's own notificationCenter, not the default) — re-anchors + `orderFrontRegardless` on Space changes, gated by `isVisible` so we don't surface onto Spaces where the user had hidden it.

Independent of Phase A; verify alongside the Day-1/Day-2 dogfood.

## Day-1 / Day-2 — what to do

### Day-of-launch sanity (already done by previous session, verify)

```bash
# 1. Confirm the running binary is /Applications, not a worktree's
pgrep -lf "VoiceInk\.app/Contents/MacOS/VoiceInk$"
# Should show /Applications/VoiceInk.app — if not: killall VoiceInk; open /Applications/VoiceInk.app

# 2. Confirm the Phase A defaults are present
defaults read com.prakashjoshipax.VoiceInk EnableMLXFallback           # should be 1
defaults read com.prakashjoshipax.VoiceInk EnableContextSanitization   # should be 1
defaults read com.prakashjoshipax.VoiceInk EnableEnhancementFailureNotification  # should be 1
defaults read com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds   # 15 if never written, else user's chosen value
```

### Daily check — measurement window

```bash
# Tail the timing log (post-Phase-A rows accumulate here)
tail -50 ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv

# Count Qwen3-4B-only rows since Phase A merged
awk -F',' '$2 == "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510" && $1 >= "2026-05-06"' \
  ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv | wc -l
```

Need ~50 Qwen3-4B-only rows for the gates to be meaningful.

### Success gates (binding for Phase B unblock)

Filter rows to `provider=mlx` AND `model=mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510`. Exclude fallback retries (LFM2.5-1.2B rows that fired from T1's recovery path).

- **Primary-call timeout rate < 2%** over the rolling 50-call window.
- **Qwen3-4B p95 ≤ 8s** (success path only, excludes fallback retries).
- **No paste-success regression** vs the pre-Phase-A baseline at `/tmp/phaseA_baseline_timings.csv` (139 rows captured at SHA `b79ee67`).
- **No new context-leak surface** — verify with `grep -n 'CLIPBOARD_CONTEXT\|CURRENT_WINDOW_CONTEXT\|CURRENTLY_SELECTED_TEXT\|CUSTOM_VOCABULARY' VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` showing every value-interpolation passes through `bound(...)`.

If gates hold for ≥2 days → start Phase B.

### Fallback-rate sanity (informational, not a hard gate)

```bash
# Count "🦾 mlx fallback: ✅ recovered" log entries — these are recoveries, not failures
/usr/bin/log show --predicate 'subsystem == "com.prakashjoshipax.voiceink" AND eventMessage CONTAINS "mlx fallback"' --info --last 24h
```

If fallback fires more than ~10% of the time → Qwen3-4B is too slow on the workload, reconsider the model lineup (T2 reversal — re-promote LFM2.5 — is the candidate; or evaluate Gemma 2/3 from the parking-lot queue).

## If something misbehaves

First-line rollback knobs (priority order). All flip via `defaults write` — no code revert.

```bash
# Timeout-retry misbehaving (recursing, evicting primary, etc.):
defaults write com.prakashjoshipax.VoiceInk EnableMLXFallback -bool false

# Redaction over-firing on real-world clipboards (deleting benign content):
defaults write com.prakashjoshipax.VoiceInk EnableContextSanitization -bool false

# Notification spam from transient cloud-provider blips:
defaults write com.prakashjoshipax.VoiceInk EnableEnhancementFailureNotification -bool false
```

Escalation if the kill-switches don't recover (per `docs/superpowers/specs/2026-05-06-pipeline-tightening-design.md` Rollback section):

- Timeout rate > 5% over 20 calls (after `EnableMLXFallback=false`) → bump `EnhancementTimeoutSeconds` further (15 → 25).
- p95 latency > 12s sustained → reconsider the curated lineup; T2 reversal is a candidate.
- Paste-success regression that survives `EnableClipboardRestore=false` → `git revert` the T4 cherry-picks.

Tracks T2 (LFM2.5 hide) and T3 (the no-op verification) intentionally have no kill-switch — both are presentation/documentation changes where a runtime toggle would be a regression vector. Rollback for those is `git revert`.

## Next implementation phase — Phase B

**Status:** spec drafted (in the Phase A design doc, "Out of scope (deferred to sister specs)" → "Phase B" section). Ready for a fresh design pass once Phase A gates hold.

### Goals

1. **`<ACTIVE_APP>` tag in the system prompt.** Capture `NSWorkspace.shared.frontmostApplication` at enhancement time (NOT recording time — match what the user is about to paste into). Append a block alongside `<CLIPBOARD_CONTEXT>`:
   ```
   <ACTIVE_APP>
   name=Slack
   bundle=com.tinyspeck.slackmacgap
   </ACTIVE_APP>
   ```
   New `useActiveAppContext` UserDefault, default ON, toggleable in Settings Context section. Reuses Phase A's `bound()` helper for size-bounding.

2. **Power Mode `useClipboardContext: Bool` field.** `decodeIfPresent` defaulting `false` for back-compat with existing UserDefaults configs. Settings UI gets a new toggle row next to "Use Screen Capture".

3. **Preset scaffolds, seeded once via `seededAppPresets_v1` flag.** Editable post-creation. Match user's stated workflow:
   - **Slack** — `com.tinyspeck.slackmacgap`, prompt = existing "Chat", clipboard ON, screen capture OFF, autoSend ⌘⏎.
   - **Ghostty** — `com.mitchellh.ghostty`, prompt = Default, clipboard ON, screen capture OFF, no autoSend.
   - **Claude Code** — Ghostty + iTerm + Apple Terminal bundles, prompt = Default, clipboard ON, screen capture OFF, no autoSend (Claude Code is a CLI inside whatever terminal; no own bundle).

### Order to build

1. Add `useClipboardContext` field to `PowerModeConfig` + decoder (back-compat) + `PowerModeSessionManager` record/restore + `PowerModeConfigView` toggle. Foundation for everything else.
2. Inject `<ACTIVE_APP>` block in `getSystemMessage()` behind `useActiveAppContext` toggle.
3. Seed the three preset scaffolds.

### Suggested workflow

Start a fresh chat. Hand it this doc. Brainstorm Phase B (the design pass for prompt content of each preset; this doc has scaffolds but the *prompt text* per preset is still TBD per the parking lot). Then `superpowers:writing-plans` → `superpowers:subagent-driven-development`.

Existing process artifacts (re-read for grounding):
- `docs/superpowers/specs/2026-05-06-pipeline-tightening-design.md` — Phase A spec including the "Phase B" sister-spec stub.
- `docs/superpowers/specs/future-app-integrations.md` — parking lot. Phase B preset prompt content lives here as the "Per-app prompt template content" section.
- `docs/superpowers/plans/2026-05-06-PhaseA-pipeline-tightening.md` — execution plan for Phase A; Phase B will get its own.

## Decoupled epics

### Phase C — SessionMetric infra

Cherry-pick `9864d6d` + follow-ups (`a374702`, `caf94ae`, `e6236e3`, `2eedd96`, `60bc7a0`). Adds `SessionMetric` model + separate `stats.store` + `ModelPerformancePanel` UI with time filters. ~200 LOC + reconciliation work with our existing `enhancement-timings.csv`.

Decoupled from Phase A/B per codex's pre-approval critique: it's infra adoption, not incident response or product. Run when there's appetite for the Settings UI improvement.

### Parking lot

See `docs/superpowers/specs/future-app-integrations.md`:

- **Custom integrations** — Ghostty + Claude Code "pick up last user message from terminal scrollback" (your original ask), VS Code/Cursor "use selected code as anchor", Slack "thread vs DM detection", Mail "format as email".
- **Per-app prompt template content** — actual prompt text per preset, deferred from Phase B.
- **Browser URL injection** — `<ACTIVE_URL>` extension to Phase B with privacy gating.
- **Window-title-based subdetection** — distinguish Slack DM vs canvas, Notion vs Notion Calendar, Claude Code session vs plain terminal.
- **Gemma 2/3 family MLX evaluation queue** — benchmark against current Qwen3-4B baseline. Candidates: `mlx-community/gemma-3-1b-it-4bit`, `mlx-community/gemma-3-4b-it-4bit`, `mlx-community/gemma-2-2b-it-4bit`. Rubric: resists chat-instruct drift on questiony dictations, handles code identifiers without paraphrasing, p95 latency comparable to Qwen3-4B.
- **Prompt-content storage hardening** — `lastSystemMessageSent`/`lastUserMessageSent` `@Published` properties + SwiftData persistence (the bits 94be2ff didn't touch — they're user-local and sandboxed; opt-in via a new `RetainEnhancementPromptText` UserDefault if a privacy-conscious user asks).

## Where the truth lives

- **Code:** `origin/main` at `77ec33c` or later.
- **Specs:** `docs/superpowers/specs/2026-05-06-pipeline-tightening-design.md` (Phase A, codex GREEN).
- **Parking lot:** `docs/superpowers/specs/future-app-integrations.md` (Phase B preset content + ideas).
- **Plan archive:** `docs/superpowers/plans/2026-05-06-PhaseA-pipeline-tightening.md`.
- **This doc:** `docs/superpowers/specs/2026-05-06-handoff-and-next-steps.md`.

## When to delete this doc

After Phase B kicks off and Phase B gets its own design + plan docs, the "Day-1/Day-2" sections here are stale. The "What shipped" and "Decoupled epics" sections may still be useful but duplicate other docs. At that point, this doc can be deleted or moved to an `archive/` subdirectory — whichever the future-session prefers.
