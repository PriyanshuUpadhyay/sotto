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

### KI-04 · Enhancement model emits meta-refusal even when a real transcript is present

**Symptom:** With a non-empty transcript present, the model still returns a refusal claiming no transcript was provided. Observed output:

> "I cannot fulfill this request because no transcript text was provided for me to summarize or clean up. Please provide the text you would like me to work on."

The transcript was real and non-empty when this fired — this is NOT an empty-input edge case, it's the model hallucinating the absence of content that's actually there.

**Candidate root causes (must instrument before fixing):**

1. **Placeholder substitution failure** (highest-priority to rule out). The System Default prompt references `<TRANSCRIPT>` as a placeholder name in its prose ("the <TRANSCRIPT> below…") but the actual hydration step may not be wrapping the user's transcript in `<TRANSCRIPT>...</TRANSCRIPT>` tags — the model could be receiving the prose *and* the raw transcript text without a tagged boundary, making the placeholder look unfilled. Audit `VoiceInk/Services/AIEnhancement/EnhancementService.swift` (or wherever `composedPrompt(for:)` lives) to confirm how the transcript is embedded.
2. **Model hallucination on small models.** Gemma 4 E4B / Gemma 3 1B QAT can over-correct on RLHF priors and refuse a task they don't recognize. Same family as KI-03 (literal "doc" output) and KI-05 (output wrapping).
3. **Tokenization edge.** If the transcript contains unusual Unicode, control chars, or unbalanced markup, the model may see noise and fall back to refusal.

**Next steps when picked up:**

- **Step 1 — instrument.** Log the exact prompt string sent to the model in `MLXProvider`. Reproduce the failure. Inspect:
  - Is `<TRANSCRIPT>` substituted with the actual text, wrapped in literal tags?
  - If unsubstituted → fix the substitution code first; this is likely the actual bug, not a model issue.
  - If substituted correctly but model still refuses → it's the priors issue.
- **Step 2 — defense in depth.** In `MLXProvider`, detect meta-refusal patterns in the model output (`"I cannot"`, `"I'm unable"`, `"no transcript"`, `"please provide"`) when the input was non-empty → fall back to raw transcript rather than pasting the refusal. Same defensive shape as KI-05's post-processing strip-list.
- **Step 3 — eval harness.** Add a "model emits meta-refusal on real transcript" failure mode to KI-03's eval harness; track regression rate across model swaps.

---

### KI-05 · Enhancement model wraps output in XML tags / adds prefix or suffix

**Symptom:** The model occasionally returns its output wrapped in XML-like tags (likely `<TRANSCRIPT>...</TRANSCRIPT>` mirroring the prompt template's placeholder), or adds a prose prefix ("Here's the cleaned text:") or suffix ("Let me know if you'd like changes."). The output should be the transformed text only — no wrapping, no prefix, no suffix, no commentary.

**Hypothesis:**
- The System Default prompt uses `<TRANSCRIPT>` as a structural placeholder. Smaller models with weaker instruction-following mirror that markup back into the response.
- Same RLHF-prior issue as KI-03 / KI-04 — small models default to conversational scaffolding ("Sure! Here's…", "Output:") around any text they produce.

**Next steps when picked up:**
- **Prompt-side mitigation:** add a literal output-format rule to the System Default prompt:
  > Output ONLY the cleaned text. Do NOT wrap it in XML tags, do NOT prefix it with "Here's the…" or any meta-comment, do NOT add a trailing question. Output is consumed verbatim — every character you emit lands in the user's text editor.
- **Code-side post-processing in `MLXProvider`:** strip a small set of known wrapping patterns from the model output before returning to the pipeline:
  - leading/trailing whitespace
  - leading/trailing `<TRANSCRIPT>` / `</TRANSCRIPT>` (or any `<…>` tag wrapping the entire body)
  - common prose prefixes (`Here's the cleaned text:`, `Sure,`, `Output:`, `Cleaned:`)
  - common prose suffixes (`Let me know…`, `Hope this helps`)
  Keep the strip list short and well-tested — over-stripping is worse than the original issue.
- **Structured-decoding option:** if `mlx-swift-lm` exposes constrained generation (regex / grammar / JSON schema), constrain the output to plain text without tag patterns. Heavier lift; revisit if prompt + post-processing aren't enough.
- Add this failure mode to the eval harness from KI-03's investigation.

---

## How to use this file

- **Adding an issue:** new section under the latest date, ID prefix `KI-NN` (continuing). Symptom → hypothesis → next steps. No fix code — that goes in the commit when the fix lands.
- **Removing an issue:** when fixed, delete the section and reference the fix commit in that PR/commit's body.
- **Triage:** issues here are NOT scheduled. Move to a plan or spec when a packet picks them up.
