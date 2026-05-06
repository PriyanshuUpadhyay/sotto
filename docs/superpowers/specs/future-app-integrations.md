# Future App Integrations — Parking Lot

**Status:** parking lot, not a spec. Pick items up when there's appetite.

Companion to `2026-05-06-pipeline-tightening-design.md`. Phase A ships incident response; Phase B ships ACTIVE_APP tag + Power Mode preset scaffolds. Everything below is *post-Phase B* — ideas worth capturing now so they don't drift away, but not designed.

---

## Custom app integrations

Ideas for app-specific behaviors that go beyond "switch which prompt template runs" (what Power Mode does today). Each would need its own spec.

### Ghostty + Claude Code — pick up last user message from terminal scrollback

When the active terminal is running Claude Code (or any LLM CLI), reach into the visible scrollback and inject the most recent user-authored message as anchor text. Disambiguates "what was I asking about" without forcing the user to re-state context.

Open questions: window-content scraping vs. AX tree traversal, how to detect Claude Code session vs. plain shell, latency budget for scrollback read.

### VS Code / Cursor — use selected code as anchor

When the active app is VS Code/Cursor and there's a selection, inject `<SELECTED_CODE>` block. Different from Power Mode's existing prompt switching — this is content injection, not template switching.

Already partially possible via `<CURRENTLY_SELECTED_TEXT>` (AXIsProcessTrusted gate); the question is whether to give code selections their own framing tag the model can recognize.

### Slack — thread vs DM detection

Slack DMs vs threads vs channels have different formality norms. Detecting which surface the user is dictating into (via window title or AX) and switching auto-formality accordingly.

### Mail — format as email

When the active app is Mail (or a webmail tab), bias the cleanup template toward email conventions: greeting/signoff if present, paragraphing, less aggressive contraction-stripping.

---

## Per-app prompt template content (Phase B follow-up)

Phase B ships preset *scaffolds* — Power Mode entries with the right bundle IDs, clipboard toggles, and auto-send behavior, but pointing at the existing `Default` and `Chat` prompt templates. The actual prompt *text* per preset is TBD.

Ideas to brainstorm when the presets are in user hands:

- **Slack prompt** — bias to chat-message length, emoji-friendly, never wrap in quotes.
- **Ghostty / Terminal prompt** — terse, command-form, never add prose framing.
- **Claude Code prompt** — preserve technical precision, structure asks as bullets when 2+, never paraphrase code identifiers.
- **VS Code / Cursor prompt** — when selection present, treat dictation as instruction *about* the selection, not as text-to-clean.

---

## Prompt-content storage hardening

After Phase A's T3 plugs the unified-log broadcast, full prompt + transcript content is still retained in two places that survive across launches:

1. `lastSystemMessageSent` / `lastUserMessageSent` `@Published` properties on `AIEnhancementService` (in-memory; observed by `EnhancementSettingsPanel.LastSystemPromptViewer`).
2. `Transcription.aiRequestSystemMessage` / `aiRequestUserMessage` SwiftData fields populated from those properties at five call sites (`TranscriptionPipeline`, `AudioPlayerView`, `AudioFileTranscriptionManager`, `AudioFileTranscriptionService`, `TranscriptionDetailView`).

Both are user-local and app-sandboxed, but a privacy-conscious user may prefer to opt out of the SwiftData persistence (debug pane already gates by hover/expand). Possible designs:

- `RetainEnhancementPromptText` UserDefault, default ON. When OFF, properties stay in memory for the debug pane but the SwiftData fields receive `nil`. Lightweight; preserves the debug feature.
- Move the debug-pane viewer behind an "Advanced" disclosure or developer-mode flag.
- Truncate retained content to first 200 chars + ellipsis at the SwiftData write sites.

Pick when the user signals they care; not blocking Phase A.

## Browser URL injection (`<ACTIVE_URL>`)

Phase B ships `<ACTIVE_APP>`. URL is the obvious next layer — `BrowserURLService` already exists in PowerMode and pulls the URL from Safari/Chrome/Arc/etc.

Risks to design around:
- URLs are sensitive (auth tokens in query params, internal hostnames).
- Need an opt-in toggle separate from `useActiveAppContext`.
- Domain-only mode (`<ACTIVE_URL>github.com</ACTIVE_URL>`) might be the right default; full URL behind a separate "include path/query" toggle.

---

## Window-title-based subdetection

Many apps multiplex very different surfaces under one bundle ID. Slack window title tells you DM vs channel vs canvas. Notion vs Notion Calendar. Browser tabs already covered by URL but the title gives extra signal.

`NSWorkspace.shared.frontmostApplication` doesn't expose window title — needs AX tree walk via `AXUIElementCopyAttributeValue(_, kAXTitleAttribute as CFString, _)`. Same accessibility-permission gate as `<CURRENTLY_SELECTED_TEXT>`.

---

## Model evaluation queue

Models worth benchmarking against current Qwen3-4B-Instruct-2507-4bit-DWQ-2510 baseline.

### Gemma family (MLX)

User-requested. Candidates worth pulling and timing on the same `enhancement-timings.csv` corpus:

- `mlx-community/gemma-3-1b-it-4bit` — direct LFM2.5-1.2B replacement candidate (small, fast, hopefully better quality).
- `mlx-community/gemma-3-4b-it-4bit` — Qwen3-4B alternative.
- `mlx-community/gemma-2-2b-it-4bit` — middle ground.

Evaluation rubric:
- Resists chat-instruct drift on questiony dictations (the W11-era root cause).
- Handles code identifiers without paraphrasing them.
- p95 latency on Apple Silicon comparable to or better than current Qwen3-4B baseline.

### Other candidates worth tracking

- Latest LFM family revisions (LFM2.5 successors with quality fixes).
- Apple Foundation Models successors (post-26.0 OS revs).
- Any community 1.5–3B fine-tunes specifically for cleanup/rewrite tasks.

---

## Maintenance

This file is a parking lot, not a spec. Each item gets a brief paragraph capturing the idea + open questions. When promoted to active work:

1. Move the item to its own spec at `docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`.
2. Strike through (~~~~) here with a forward-link.
3. Don't expand items in place — keep this file scannable.
