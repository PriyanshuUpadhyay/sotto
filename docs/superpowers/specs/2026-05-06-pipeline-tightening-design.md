# Pipeline Tightening — Phase A Incident Response

**Date:** 2026-05-06
**Status:** approved (codex pass 1 + 2 GO-WITH-CAVEATS)
**Phases:** A ships now; B and C are deferred sister specs

## Problem

W14F refreshed the curated MLX lineup, swapping cleanup default from `mlx-community/LFM2.5-1.2B-Instruct-4bit` (0.3–1.7s total) to `mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510` (5–7s total). Default `EnhancementTimeoutSeconds=7` now produces an 11% timeout rate on Qwen3-4B (1/9 calls in last 30m, observed 11:02 timeout on a 723-char input). LFM2.5-1.2B is fast enough but cleanup quality is poor on questiony or long dictations — dropping back is not the answer.

Secondary: `lastSystemMessageSent` and `lastUserMessageSent` retain full transcripts in memory and surface them in the UI debug pane. Clipboard and screen-capture context blocks are unbounded — a 50KB clipboard would tank Qwen3-4B latency and risk MLX KV-cache pressure. Failures are silent: no UI signal when an enhancement times out.

## Goal

Land a tight, reversible incident response that:

1. Cuts Qwen3-4B timeout rate below 2% without abandoning the W14F quality gain.
2. Plugs the prompt-logging privacy leak.
3. Makes failures visible.
4. Bounds context blocks so future app-aware features (Phase B) can't blow up latency.

Phase A is incident response. App-awareness (ACTIVE_APP tag, Power Mode presets) and metrics infra (SessionMetric cherry-pick) are sister specs that ship only after Phase A's gates hold for ≥2 days.

## Phase A — Tracks

### T1 — Timeout bump + MLX fallback chain

Change `EnhancementTimeoutSeconds` default from `7` to `15`. User-configurable via existing settings.

On MLX path timeout, retry once with `mlx-community/LFM2.5-1.2B-Instruct-4bit` if downloaded; otherwise surface failure. Single-shot; no retry loop. Fallback fires only from the MLX path (not Ollama, LocalCLI, AFM, cloud) — those providers have their own timeout semantics and crossing the boundary risks silent provider swap.

Gated by `EnableMLXFallback` UserDefault, default `true`. This is the **first-line rollback knob** if the fallback misbehaves: flip to `false`, fork stays on single-attempt flow.

Files: `AIEnhancementService.swift` (`makeRequest`, `makeRequestWithRetry`), `AppDefaults.swift` or wherever `EnhancementTimeoutSeconds` is registered.

### T1 + T5 commit granularity

T1 and T5 land as **two separate commits**, validated jointly because T5 reduces input size that drives T1's timeout window. Joint validation means the verification ritual runs once after both commits land — not that they squash into one. Rollback is independent: revert T1 leaves T5's redaction in place; revert T5 leaves T1's timeout/fallback in place.

### T2 — LFM2.5-1.2B lineup handling

Remove `LFM2.5-1.2B-Instruct-4bit` from the user-visible curated MLX lineup. Keep it downloadable and loadable so T1's fallback chain can use it. If the user already has it as their selected model, leave it selected — don't force-migrate.

Files: `CuratedMLXModels.swift` (or wherever the W14F lineup lives).

### T3 — Prompt-redaction cherry-pick

**Status (2026-05-06 verification): NO-OP — already met by prior W11/W14 work.**

Cherry-pick upstream `94be2ff` "Remove system prompt and user message logging from AI services". Removes the `logger.notice("AI Enhancement - System Message: …")` and `…User Message: …` calls from `AIEnhancementService.swift` + `OllamaService.swift`. Net effect: the unified-log subsystem (`com.prakashjoshipax.voiceink`) no longer broadcasts full prompts and transcripts where any process with logging-read access — or `log show` + Console.app + a logarchive export — can read them.

Pre-execution `grep` against our tree shows neither the `"AI Enhancement - System Message"` log calls nor the `print("Original Text:…")` / `print("System Prompt:…")` / `print("Enhanced Text:…")` debug prints exist. Our W11/W14 refactor (which replaced the original logging with the `🦾 enhance: level=…` count-only style and migrated `OllamaService` to `LLMkit.OllamaClient`) already eliminated every broadcast `94be2ff` would delete. All remaining logger calls log only counts (`input=\(userPrompt.count)c`), never content. Privacy goal already met.

T3 verifies-only and proceeds without a commit. Documented in plan Task 1 readout.

Out of scope for T3 (NOT what this commit does):
- `lastSystemMessageSent` / `lastUserMessageSent` `@Published` properties remain (in-memory, observed by debug UI).
- SwiftData persistence of `aiRequestSystemMessage` / `aiRequestUserMessage` on the `Transcription` record remains (user-local, sandboxed, useful for transcription history).
- `EnhancementSettingsPanel.swift:401` "Last System Prompt Viewer" debug pane remains.

The remaining surfaces are user-local and discretionary. Hardening them (full-property removal, optional debug-pane gating) is a future-hardening task tracked in `future-app-integrations.md`.

Conflict surface is small. Our W11/W14 work added breadcrumbs around the now-removed `logger.notice` calls (one in `AIEnhancementService.swift:212` adjacent area), not new readers. Take upstream's removal verbatim and resolve any context-line conflicts.

### T4 — Failure visibility + clipboard restore + Power Mode default

**Status (2026-05-06 verification):**
- `cfc6a87`: PARTIAL — failure notification path already exists at `TranscriptionPipeline.swift:233-237` (W11+ added `NotificationManager.shared.showNotification(title: "Enhancement failed: \(shortReason)", type: .warning)`). Only the `EnableEnhancementFailureNotification` kill-switch wrap is new work.
- `46c5ed7` / `34a7f5e` / `05cc14a` clipboard restore stack: NO-OP. Our `AppDefaults.swift` already registers `restoreClipboardAfterPaste: true`; `CursorPaster.swift:94` already does `max(restoreDelay, 0.25)`; `SettingsView.swift:313-318` already exposes 250ms/500ms picker tags. Final state of all three upstream commits is already absorbed.
- `13240f3`: NO-OP. `PowerModeConfigView.swift:460,471` already uses `transcriptionModelManager.currentTranscriptionModel?.name` (the W11+ equivalent of upstream's `whisperState.currentTranscriptionModel?.name` after a dependency-injection rename).

T4 collapses to: **add `EnableEnhancementFailureNotification` kill-switch wrap** around the existing notification call. ~5 lines. The clipboard stack and Power Mode default verify-only.

### T5 — Hard context budget + redaction

New centralized helper in `AIEnhancementService` (or a small `ContextRedactor` extension):

```
func sanitizeContext(_ raw: String, maxBytes: Int) -> String
```

Behavior:
1. **Line-level secret redaction.** Drop any line matching either of these (case-insensitive):
   - **Key-shape pattern:** `\b(password|passwd|api[_-]?key|apikey|access[_-]?token|auth[_-]?token|secret[_-]?key|client[_-]?secret|private[_-]?key|aws[_-]?secret|github[_-]?token)\b\s*[:=]\s*\S` — anchored on word boundaries to avoid `secretary`/`api`-suffix false positives, requires a `:` or `=` separator and at least one non-space value char.
   - **Auth header pattern:** `\b(authorization|x-api-key)\s*:\s*\S+` plus standalone `\bbearer\s+[A-Za-z0-9._/+-]+\b` (handles base64url tokens with `/`, `+`, `=` padding).
2. Truncate to last `maxBytes` UTF-8 bytes (prefer the *tail* — for a paste-into target, recent content is more relevant). Prepend "…[truncated]…\n" marker. Truncation operates on bytes but cuts only at line boundaries to avoid producing invalid UTF-8.
3. Idempotent (calling twice changes nothing). Verify with a unit test or quick repro before merging.

The patterns deliberately *under-redact* over *over-redacting* — false positives that delete benign clipboard lines are worse for cleanup quality than the rare uncaught secret format, since this is a defense-in-depth layer (the user's main protection is not pasting secrets into a clipboard they then dictate alongside). Track exotic formats (multi-line PEM blocks, JWT-shape regex, env-var dumps) in `future-app-integrations.md` for hardening if they show up in practice.

Apply at every context-block construction site:
- `<CLIPBOARD_CONTEXT>`: 2KB cap.
- `<CURRENT_WINDOW_CONTEXT>`: 2KB cap.
- `<CURRENTLY_SELECTED_TEXT>`: 2KB cap.
- `<CUSTOM_VOCABULARY>`: 1KB cap.

Three call paths must all use the helper: `getSystemMessage` (live enhance), `enhancePreview` (Prompts editor — note: preview deliberately omits clipboard/screen capture per the existing spec, but the helper still applies to anything else passed through), `commandModeRewrite` (W12.B). Codex flagged this as non-negotiable — verify with `grep -n 'CLIPBOARD_CONTEXT\|CURRENT_WINDOW_CONTEXT\|CURRENTLY_SELECTED_TEXT\|CUSTOM_VOCABULARY' VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` shows every match passes through `sanitizeContext`.

Gated by `EnableContextSanitization` UserDefault, default `true`. Kill-switch if redaction over-fires on real-world clipboards.

Files: `AIEnhancementService.swift` (`getSystemMessage`, `enhancePreview`, `commandModeRewrite`).

### Order

T3 → T4 → T2 → T1+T5. Privacy first, visibility second, lineup third, behavioral changes (timeout + fallback + budget) together because T5 reduces input size that drives T1's timeout window and they must validate jointly.

Each track is one commit on a feature branch. No squashing.

## Success gates

Measured against `enhancement-timings.csv` rolling window of the last 50 calls **filtered to provider=mlx and model=mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510**. Cloud, Ollama, AFM, LocalCLI calls and fallback retries (LFM2.5-1.2B-Instruct-4bit) are excluded — they have their own latency profiles and shouldn't dilute the signal we're measuring.

Fallback retries should be tallied separately as a *fallback rate* metric — high fallback rate is itself a signal, but doesn't count against the primary timeout-rate gate (the primary call timed out is what matters; the retry succeeding is a recovery, not a fresh failure).

- Primary-call timeout rate (Qwen3-4B only): < **2%**.
- Fallback-fired rate: tracked, no fixed gate yet — anything > 10% means Qwen3-4B is too slow on the workload and we should reconsider the model lineup.
- Qwen3-4B p95 enhancement total (success path, excluding fallback retries): ≤ **8s**.
- No regression in paste success vs the pre-Phase-A baseline (capture this baseline as the first step of execution — `git log -1` of current HEAD + a 20-call paste-success ratio).
- No new context-leak surface beyond what redaction allows. Verify by grepping all context-block construction sites use `sanitizeContext`.

Hold gates for ≥2 days before writing Phase B.

## Rollback

Behavioral tracks (T1, T4, T5) get UserDefault kill-switches so rollback under pressure doesn't require code reverts. Tracks that change presentation or remove a known leak (T2, T3) don't — there's no production scenario where you'd want them disabled, and a kill-switch would be a regression vector ("re-show LFM2.5", "re-enable transcript logging") with no benefit. Their rollback is `git revert <hash>`.

All kill-switches default to `true` (track behavior enabled); flip to `false` to disable.

| Switch | Track | Disables |
|---|---|---|
| `EnableMLXFallback` | T1 | MLX timeout retry with LFM2.5; restores single-attempt flow |
| `EnableEnhancementFailureNotification` | T4 | NSUserNotification on enhancement failure |
| `EnableClipboardRestore` (only if cherry-picked behavior doesn't already have its own toggle) | T4 | Reverts to pre-T4 clipboard-restore behavior |
| `EnableContextSanitization` | T5 | Redaction + truncation; restores raw context blocks |

Tracks without a kill-switch:
- **T2** — LFM2.5 lineup hide is a presentation change; rollback is re-adding it to `CuratedMLXModels.swift` via `git revert`.
- **T3** — `94be2ff` cherry-pick removes a privacy leak; rolling back means re-introducing it, which should never happen via a runtime toggle.

**First-line rollback under pressure** (in priority order, single-knob):
1. `EnableMLXFallback=false` — covers timeout-retry misbehavior.
2. `EnableContextSanitization=false` — covers redaction over-firing or breaking cleanup quality.
3. `EnableEnhancementFailureNotification=false` — covers notification spam.

**Escalation if kill-switches don't recover:**
- Timeout rate > 5% over 20 calls (after `EnableMLXFallback=false`) → bump `EnhancementTimeoutSeconds` default further (15 → 25).
- p95 latency > 12s sustained → reconsider model lineup; T2 reversal (re-promote LFM2.5 to user-visible) is a candidate.
- Paste-success regression that survives `EnableClipboardRestore=false` → `git revert` the T4 clipboard-restore commits specifically.
- Multi-regression scenario (timeouts + paste failures + context issues simultaneously) → flip all three first-line switches, ship, then `git revert` per track once stable.

Each track is a separate commit; `git revert <hash>` is the per-track mechanic of last resort.

## Verification ritual

Per track, before moving to the next:

1. `xcodebuild -scheme VoiceInk -configuration Debug build` lands clean. (W14E lands artifacts in `/Applications`.)
2. Smoke test: short ("hello world") and long (>120c) recordings, confirm enhancement runs and pastes correctly into a TextEdit window.
3. T1 fallback test: provoke timeout by setting `EnhancementTimeoutSeconds=1` in UserDefaults (`defaults write com.prakashjoshipax.VoiceInk EnhancementTimeoutSeconds 1`), confirm:
   - Qwen3-4B times out fast.
   - LFM2.5-1.2B retry runs (visible in unified log: `🦾 enhance` from MLXProvider with the smaller model id).
   - Output pastes successfully.
   - Failure notification surfaces if LFM2.5 is *not* downloaded (forces the fallback-failed path).
   - Reset `EnhancementTimeoutSeconds=15` after.
4. T5 redaction test: dictate a short transcript with clipboard containing literal text `password=foo123\napi_key=bar456\nnormal line`. Verify in unified log (or the still-existing Logger trace) that those redacted lines do not appear in the system prompt sent to MLX.

## Out of scope (deferred to sister specs)

### Phase B — App-aware enhancements (separate spec, after Phase A gates hold ≥2 days)

- `<ACTIVE_APP>` tag injection in `getSystemMessage()`. Capture `NSWorkspace.shared.frontmostApplication` at enhancement time. Layered with Power Mode (apps with preset get tailored prompt + tag; apps without preset get default + tag). New `useActiveAppContext` UserDefault, default ON.
- Power Mode `useClipboardContext: Bool` field. `decodeIfPresent` defaulting `false` for back-compat with existing UserDefaults configs.
- Three preset scaffolds (Slack, Ghostty, Claude Code), seeded once via `seededAppPresets_v1` flag. Slack: `com.tinyspeck.slackmacgap`, prompt "Chat", clipboard ON, autoSend ⌘⏎. Ghostty: `com.mitchellh.ghostty`, prompt Default, clipboard ON. Claude Code: matches Ghostty + iTerm + Apple Terminal bundles, prompt Default, clipboard ON.
- Phase B reuses Phase A's `sanitizeContext` helper for the new `<ACTIVE_APP>` block.

### Phase C — SessionMetric infra (separate epic, when there's appetite)

- Cherry-pick `9864d6d` + follow-ups (`a374702`, `caf94ae`, `e6236e3`, `2eedd96`, `60bc7a0`).
- Reconcile with existing `enhancement-timings.csv` (CSV stays for token-level detail; SessionMetric becomes user-facing source of truth).
- Conflict surface is moderate (TranscriptionPipeline.swift, VoiceInk.swift, MetricsContent.swift). Decoupled from incident response per critique.

### Parking lot

Written as part of Phase A so ideas don't get lost: `docs/superpowers/specs/future-app-integrations.md`. Sections:

- Custom integrations: Ghostty + Claude Code "pick up last user message from terminal scrollback"; VS Code / Cursor "use selected code as anchor"; Slack "thread vs DM detection"; Mail "format as email".
- Per-app prompt template content for Phase B presets (currently they all point at Default; tailored prompts TBD).
- Browser URL injection (`<ACTIVE_URL>`).
- Window-title-based subdetection.
- Gemma 2/3 family MLX evaluation queue.

## Migration policy

1. **`EnhancementTimeoutSeconds` default change (7→15).** Users who never wrote the key see 15s. Users who explicitly wrote a value keep their value. Verified via the existing `UserDefaults.standard.integer(forKey:) > 0 ? stored : default` pattern at `AIEnhancementService.swift:88`.
2. **`EnableMLXFallback` new key.** Default `true`. New key, no migration needed.
3. **LFM2.5-1.2B in user-visible lineup (T2).** If a user has the model selected as their cleanup model, do not auto-deselect. The model continues to load and run; it just stops being offered to new users. The Settings UI for the curated lineup must handle "selected model not in curated list" gracefully (already does via `customMLXModels` mechanics).
4. **`94be2ff` cherry-pick (T3).** Removes only the `logger.notice` broadcasts. No property removal, no UI changes. If conflict surface is just context lines (likely), accept upstream's deletion. Build should be green immediately.

## Unresolved questions

None blocking Phase A. Items deferred to Phase B / C / parking lot are tracked in those documents.
