# VoiceInk — Known Issues

Tracker for app bugs not currently scheduled. Tackled after the aesthetic-redesign packets (W1–W7) land. New entries: append at top with date and a short ID.

---

## 2026-04-28

### KI-01 · Stale paste-target state shown at start of next transcription

**Symptom:** When a previous transcription has been auto-pasted (or copy-pasted) into a target app (e.g. Ghostty), the "pasted to <app>" state is no longer visible in the current UI. But when the *next* transcription is triggered, the cluster/recorder briefly displays the *old* paste-target state ("Pasted to Ghostty") for a frame or two before the new recording flow takes over.

**Hypothesis:** Paste-completed state is cached on the cluster/state model and not cleared on `recording.start()`. Likely needs a transition from `done`/`pasted` → `idle` before the next `armed` → `recording` transition is allowed to render.

**Next steps when picked up:**
- Find where `done`/paste-completed state is set; verify it gets cleared on next-recording-start, not just on done-dwell timeout.
- Likely owner: `ConstellationCard.swift` or `RecordingStateObserver`. Note: cluster owner may shift in W2 — re-locate if needed.

---

### KI-02 · Slack auto-paste fails silently

**Symptom:** When VoiceInk attempts to auto-paste into Slack, paste does not land. Manual ⌘C/⌘V works fine. No error UI shown — silent failure.

**Hypothesis:** Slack uses a non-standard text input (Electron-based RichTextEditor / Lexical / draft-js). Standard `NSPasteboard` + simulated ⌘V keystroke may not register as a paste in Slack's input.

**Notes:**
- Ghostty paste works.
- No `error` event surfaced — the failure path doesn't trigger any user-visible state. Will trigger `FailureRegistry` once W3 lands, IF the paste layer is wired into it.

**Next steps when picked up:**
- Reproduce; capture Accessibility tree of Slack input field at paste time.
- Test alternative: `AXUIElementSetAttribute` directly into the focused element vs. simulated keystroke.
- If non-standard input fails — fall back to leaving content on clipboard + user-visible "couldn't auto-paste, content copied" notification.

---

### KI-03 · Enhancement model lacks contextual awareness for short utterances

**Symptom:** Short, ambiguous dictation utterances are output literally instead of rewritten with context. Example: dictating "create a **doc**" produced "create a **do g**" (model heard "doc" and didn't infer "document"/"Google Doc").

**Hypothesis:** The enhancement model (currently `gemma-4-e4b-it-4bit`, soon `gemma-3-1b-it-qat-4bit` per backlog) doesn't have enough hint that "doc" is short-form for "document". The System Default prompt in `VoiceInk/Models/PromptTemplates.swift` is a generic cleanup prompt with no examples and no context-seed.

**Investigation to do (before committing to a fix):**
- Does few-shot prompting help small/mid-size models (Gemma 3 1B / Gemma 4 4B) on text-cleanup tasks, or does it leak example content into outputs?
- Gemma prompt guidelines: short instruction-tuned prompts, structured `<TRANSCRIPT>` blocks, no chain-of-thought wrapper for cleanup tasks. Verify guidance against current Google docs.
- Open question: do 2–3 generalizable input/output pairs (e.g. `"doc"` → `"doc"`/`"document"`, `"ill"` → `"I'll"`, `"im"` → `"I'm"`) help — or hurt — cleanup quality on small models.

**Possible directions:**
1. Add 2–3 minimal examples to the System Default prompt's `promptText`.
2. Use a separate `examples:` field on `PromptTemplate` (if/when introduced) instead of inlining.
3. Swap to a higher-quality model (e.g. Gemma 3 4B QAT instead of 1B QAT) at cost of latency.
4. Add a context-seeding mechanism — last paste target's app name or focused-window title as a hint inside the prompt.

**Next steps when picked up:**
- Build a small eval harness with ~10 ambiguous-but-realistic dictation samples; compare cleanup quality across {no-examples, with-examples, larger-model, with-context-seed}. Pick the best.

---

### KI-06 · Small MLX models (gemma-3-1b QAT) produce low-quality cleanup on short utterances

**Symptom:** With a clean prompt + correctly-routed input, gemma-3-1b-it-qat-4bit can still produce mediocre or off-topic output on very short or contextually ambiguous transcripts. Larger MLX models (gemma-4-e4b-it-4bit) handle the same input correctly.

**Hypothesis:** 1B parameters is genuinely too few for the cleanup task's combination of (a) instruction-following (b) preserving meaning (c) light grammar fixing. QAT (quantization-aware training) helps recover quality vs naive 4-bit but doesn't change the underlying capacity ceiling.

**Mitigations to consider (when picked up):**
1. Re-tier the registry: move gemma-3-1b-qat to a "Speed (experimental)" label so users opt in knowingly; keep gemma-4-e4b as the default "Fast" tier.
2. Build the eval harness from KI-03 — pick the smallest model that hits acceptable quality on the eval set.
3. If 1B quality is genuinely good enough for the bulk of users' inputs (and only fails on edge cases like very-short ambiguous utterances), ship as a known-limitation note in the picker rather than a tier change.

This is a model-capacity issue, not a prompt or routing issue. Prompt fixes for the meta-refusal / XML-wrapping failure modes (resolved) don't address the underlying capability gap.

---

## How to use this file

- **Adding an issue:** new section under the latest date, ID prefix `KI-NN` (continuing). Symptom → hypothesis → next steps. No fix code — that goes in the commit when the fix lands.
- **Removing an issue:** when fixed, delete the section and reference the fix commit in that PR/commit's body.
- **Triage:** issues here are NOT scheduled. Move to a plan or spec when a packet picks them up.
