# Enhance Pipeline Performance Audit — 2026-04-29

**Author:** `researcher-pipeline` (W11 deep-research, Task #2)
**Scope:** static analysis only. No code edits. No app runs. Method = read every file in the enhance call path + cross-reference against `mlx-swift-lm` 3.31.3 sources in `.local-build/SourcePackages/checkouts/mlx-swift-lm/`.
**Hardware target:** Apple Silicon M-base 32 GB (user's machine).

---

## 1. TL;DR

Ranking of where wall-clock time goes on a typical "first-enhance after 10 min idle" cycle, worst → fixable:

1. **`prep` + prefill of an oversized system prompt** is the biggest fixable cost. Default System-Default template + wrapper = ~5,100 chars / **~1,275 tokens of system context** before any user/clipboard/screen-OCR additions. For a 50-token transcript that's a **~25× system:user ratio**, dominating both `prep=` and the model's first-forward pass (the bulk of `ttft=`). A short-transcript fast-path that drops the wrapper to ≤200 tokens is the highest-leverage P0.
2. **Cold model-load on every recording session** (idle-evict 600s, **no MLX prewarm**). `ModelPrewarmService.swift:107-115` only prewarms whisper/fluidAudio — the entire MLX side is unprewarmed. The first enhance after launch / wake / ≥10 min idle pays full disk → wired-memory load. On a 1.7B 4-bit DWQ model from disk that's ~1-2s, on a 4B ~2-4s.
3. **No KV-cache reuse across calls**. Same 1,275-token system prefill recomputed on every enhance. mlx-swift-lm 3.x supports prompt-cache round-trip (see release notes for 3.31.3 / 2.31.3 — `ArraysCache`/`MambaCache`/`CacheList` serialization is in). With cache reuse, second-onward enhances skip the system prefill entirely.
4. **Sampler config triggers the heavier code path**. `temperature: 0.1, topP: 0.9` dispatches `TopPSampler` (sort + categorical sample). `temperature: 0.0` dispatches `ArgMaxSampler` (just argmax). For deterministic cleanup, this is a free perf win + zero quality cost.
5. **`max_tokens` ceiling without a wall-clock timeout**. For a rambling model, `192…768` tokens × poor tok/s = the user's "still slow" complaint. A wall-clock generation timeout (e.g. 8s) on top of token-cap is the safety net the existing 10s WARN log only observes after the fact.

**Generate-loop itself (`for await item in stream`) is fine.** String concat overhead is sub-millisecond. The chat-template apply path is slightly more expensive than raw-text but the quality cost of bypassing it on a chat-instruct model isn't worth the milliseconds saved.

**Framework version is fine.** `mlx-swift-lm 3.31.3` is the latest release (published 2026-04-15). Perf work in 3.31.3 ("consolidating RoPE calls") is already in our build. No newer release pending.

The "model is slow" framing is half-true: the model is doing more work than it needs to, mostly because of how WE shaped its input. Five of the seven hypotheses below have concrete fixes that don't require swapping models.

---

## 2. Per-hypothesis evaluation

### H1 — Cold-load dominates wall-clock. ✅ CONFIRMED bottleneck

**Evidence:**
- `MLXProvider.swift:50` — `idleEvictSeconds: TimeInterval = 600` (10 min). After 10 min idle, model is evicted; next enhance pays full reload.
- `MLXProvider.swift:223-240` — eviction is implemented as a `Task.sleep` followed by `modelContainer = nil` (line 237). ARC then frees weights.
- `MLXProvider.swift:66-70` — load is timed and only logs if `loadElapsed > 0.05s`. So the field actually appears on every cold load.
- `ModelPrewarmService.swift:107-115` — `shouldPrewarm()` returns true ONLY for `.whisper` and `.fluidAudio` providers. **MLX is not in the switch.** That means MLX is never prewarmed on app launch (line 47-53) or on `NSWorkspace.didWakeNotification` (line 30-39).
- `MLXProvider.swift:162-189` — `loadModel()` calls `loadModelContainer(...)` from `swift-huggingface`. On warm cache (post-download) this is purely a disk → MLX wired-memory copy. Sources/timing: `ModelContainer.swift:154-157` (prepare) and `LLMModelFactory.swift:497+` (`_load`). For ~1 GB weights the I/O bound is ~0.5-1.5s on internal SSD; for 2.3-3.0 GB it's ~1.5-3.5s. Plus tokenizer + config decode ~0.05s.

**Severity:** HIGH. This is plausibly a 2-4s spike on first enhance after every break.

**Fix sketch:**
- Add MLX to `ModelPrewarmService.shouldPrewarm()`'s switch — call `MLXProvider.loadModel()` (no enhance, just load) on app launch + on wake.
- Even better: trigger MLX warm-up on **recording start** (`VoiceInkEngine.swift:223-227` already runs a `Task.detached` that captures clipboard/screen context; add `await aiService.warmMLX()` to the same scope so the load runs in parallel with audio capture).
- Make `idleEvictSeconds` user-configurable via `@AppStorage("MLXIdleEvictSeconds", default: 1800)` and expose in MLX picker. 10 min default is too aggressive for "I dictate every 20 minutes" usage.
- Also consider DROPPING idle eviction entirely on machines with 32 GB+ RAM — a 4B 4-bit weight blob (~2.3 GB resident) is small relative to system RAM, and the user's pain is way worse than the RAM cost.

### H2 — `max_tokens` heuristic too generous. ⚠️ PARTIAL

**Evidence:**
- `MLXProvider.swift:79-80` — `let dynamicMaxTokens = max(192, min(768, approxInputTokens * 3))`.
- For a 50-token transcript: max=192. For a 100-token transcript: max=300. For a 250-token transcript: max=750. Floor of 192 covers very-short cases.
- `MLXProvider.swift:106-124` — generation streams; loop only breaks on `Task.isCancelled` or stream end. **No wall-clock timeout per-generation.**
- The `🦾 enhance: WARN total=…s exceeds 10s ceiling` log (line 134) observes overruns but doesn't enforce.
- Stop-token wiring: chat template appends `<|im_end|>` (Qwen) or equivalent. mlx-swift-lm's `TextToolTokenLoopHandler` (Evaluate.swift:1965-2010) yields a `.chunk` per token until the stop token fires inside the iterator. That iterator IS configured to stop on EOS — see `extraEOSTokens` plumbing (Evaluate.swift:1174). So a well-behaved model emits ~50-200 tokens then stops.

**Risk case:** model rambles past EOS. At ~12 tok/s on a 4B-class model, 768 tokens = **64 s** worst case. Even 192 tokens at ~12 tok/s = 16s — already over the 10s ceiling.

**Severity:** MEDIUM. Likely not the *common* pain-point (most cleanup outputs respect EOS), but the absence of a wall-clock timeout makes it the *worst-case* pain-point.

**Fix sketch:**
- Add a generation wall-clock timeout: wrap the `for await item in stream` loop in `Task.timeout(8s)` (or whichever value the user picks via the existing `EnhancementTimeoutSeconds` AppStorage key — see `AIEnhancementService.swift:73-76`). Currently that key only applies to remote-API providers (line 307, 325, 575).
- Drop the floor from 192 → 96 for transcripts under ~30 chars. Sub-30-char dictation rarely needs 192 tokens of cleanup output.
- Drop the ceiling from 768 → 512. 768 was conservative; 512 is still 2× expected cleanup length.

### H3 — `prep` overhead. ⚠️ MEASURABLE but not primary

**Evidence:**
- `MLXProvider.swift:85-92` — `prep` measures only the user-input → tokens conversion (`container.prepare(input:)`). Not the model prefill.
- `ModelContainer.swift:154-157` — `prepare(input:)` calls the processor's `prepare(input:)`.
- `LLMModelFactory.swift:445-463` (`LLMUserInputProcessor.prepare`) — calls `messageGenerator.generate(from:)` (Chat.swift:101-110) then `tokenizer.applyChatTemplate(messages:tools:additionalContext:)`.
- `applyChatTemplate` runs the model's Jinja chat template. For Qwen3 the template is small (~30 lines). swift-jinja parses it once and applies. Token cost: ~20-25 chat-template overhead tokens (`<|im_start|>system\n...<|im_end|>\n<|im_start|>user\n...<|im_end|>\n<|im_start|>assistant\n`).
- Pure tokenization of 1,275 system + 50 user = 1,325 tokens via swift-transformers BPE: realistic ~30-150ms on M-base. **Negligible compared to model prefill**.

**Severity:** LOW (prep proper). But `prep=` log is sometimes confused with TTFT — the prep time is just CPU tokenization. The actual prefill (model forward pass on those tokens to populate KV cache) is folded into `ttft=`.

**Fix sketch:** none needed at the `prep` boundary itself. The win is upstream — making the system prompt shorter (H6) shrinks both prep and prefill.

### H4 — Sampling parameters suboptimal. ✅ CONFIRMED minor win

**Evidence:**
- `MLXProvider.swift:94-98` — `temperature: 0.1, topP: 0.9`.
- `Evaluate.swift:141-153` — `GenerateParameters.sampler()`:
  ```swift
  if temperature == 0 {
      return ArgMaxSampler()
  } else if usesTopP || usesTopK || usesMinP {
      return TopPSampler(temperature: temperature, topP: topP, topK: topK, minP: minP)
  } else {
      return CategoricalSampler(temperature: temperature)
  }
  ```
- With `temperature: 0.1`, `topP: 0.9` (i.e. `topP > 0 && topP < 1`), the dispatched sampler is `TopPSampler`. This sorts logits and samples from the top-p mass.
- With `temperature: 0.0`, the dispatched sampler is `ArgMaxSampler` — pure argmax, no sort, no probability normalization.

The 2.31.3 release notes ("perf: eliminate CPU←GPU sync in penalty processors, optimize TopPSampler" — PR #147) shipped a TopPSampler optimization, but ArgMaxSampler is still strictly cheaper.

**Severity:** LOW per-token, but it's per-token and we generate 50-200 of them, so the effect compounds. Estimated saving: 5-15ms per generation on M-base.

**Quality impact:** essentially zero for this task. The cleanup transformation is near-deterministic; the model chosen at temp=0.1 vs argmax differs only on the rare token where the second-best prob is within 10% of the best — which for a well-trained instruction-tuned model on cleanup is a tiny fraction of tokens. WhisperFlow / Superwhisper-style apps universally run greedy decode for this task.

**Fix sketch:** drop the `GenerateParameters` to `temperature: 0.0` (omit `topP`, since it's ignored at temp=0). Also bump `repetitionPenalty: 1.05` if any lingering repeat-token issues — but the chat template should already keep this clean.

### H5 — Chat format vs raw text completion. ❌ NOT WORTH FIXING

**Evidence:**
- `MLXProvider.swift:86-91` builds `[Chat.Message]` and passes through `UserInput(chat:)`.
- `LLMModelFactory.swift:445-463` — `prepare()` calls `tokenizer.applyChatTemplate(messages:tools:additionalContext:)`. This goes through swift-jinja (~10-30ms per call cached; first call ~50-100ms).
- Bypassing the chat template is technically possible (use `UserInput(prompt: .text(...))` with a manually-formatted string). Output of `LLMUserInputProcessor.prepare`'s catch branch (line 452-461) shows what raw-text path looks like: just system+user joined by `\n\n` and tokenized.
- BUT: Qwen3-Instruct models are heavily fine-tuned on the chat template. Skipping it = the model sees a string that doesn't match its training distribution → erratic output, more frequent failures to emit `<|im_end|>` (which is itself part of the template), more rambling. **The 30ms saved is dwarfed by the time we'd waste re-running on bad outputs.**

**Severity:** N/A — net negative.

**Fix sketch:** none. Keep chat format.

### H6 — System prompt bloat. ✅ CONFIRMED biggest fixable bottleneck

**Evidence:**
- `AIEnhancementService.swift:148-205` — `getSystemMessage(for:)` builds the final system prompt.
- It calls `activePrompt.finalPromptText` (CustomPrompt.swift:128-134) which wraps the user's prompt body in `AIPrompts.customPromptTemplate` (AIPrompts.swift:2-40).
- The wrapper itself is **~2,700 chars / ~675 tokens** (counted via reading lines 2-40). It includes 4 numbered XML rules, a punctuation contract, three multi-line cleanup examples, and a final warning.
- The `%@` slot is filled with the user's selected prompt's body. For "Default", that's PromptTemplates.swift:50-70 ("System Default") = **~2,400 chars / ~600 tokens** of cleanup rules + punctuation contract + DO NOT lists.
- **Combined: ~5,100 chars / ~1,275 tokens** before any context.
- Then context sections are concatenated:
  - `selectedTextContext` — variable, typically 0-200 tokens.
  - `clipboardContext` (off by default but on for many users) — variable, often 50-500 tokens.
  - `screenCaptureContext` (off by default; if on, can be large) — `ScreenCaptureService.swift:32-76` runs `VNRecognizeTextRequest` on the active window screenshot. For a code editor or browser window this can yield **2,000-10,000 tokens** of OCR'd text trivially.
  - `customVocabularySection` — variable.
- All concatenated as plain text, no truncation.

**For a 50-token transcript with default+clipboard ON, the system prompt is ~1,500 tokens. With screen-capture ON in a code editor, easily 5,000+. The model prefills all of that on every call.**

**Severity:** HIGH. This is the dominant component of `ttft=` for typical use.

**Why prefill cost matters:** prefill runs the transformer forward pass over every prompt token. mlx-swift-lm prefills in chunks of `prefillStepSize=512` (Evaluate.swift:121). 1,275 tokens = 3 prefill chunks; 5,000 tokens = 10 chunks. Each chunk runs the full attention + MLP stack. This is the part of TTFT that scales linearly with prompt length. On Qwen3-1.7B M-base prefill is ~600 tokens/s; on Qwen3-4B it's ~250 tok/s. For a 1,275-token prefill, that's 2-5s of TTFT.

**Fix sketch:**
- Short-transcript fast path: if user transcript is ≤30 tokens AND no screen/clipboard context, swap the giant wrapper for a 5-line minimal cleanup prompt (~50 tokens). The full punctuation contract isn't needed for a 5-second dictation.
- Truncate `screenCaptureContext` to first ~1,500 chars (~375 tokens). Most window OCR has headers/sidebars that aren't relevant to the transcript anyway.
- Optional: skip `screenCaptureContext` entirely when transcript is ≤20 tokens (cleanup of "send the email" doesn't need the user's IDE state).
- Cache the chat-template-applied tokenized system prompt in `MLXProvider`. When the same system prompt arrives next call, reuse the prefilled KV cache (see H-bonus below).

### H7 — Streaming → string concat. ❌ NOT A BOTTLENECK

**Evidence:**
- `MLXProvider.swift:101, 117` — `var output = ""` then `output += chunk`.
- For ~200 chunks at ~3 chars each, total writes are ~600 chars. Swift's `String` uses copy-on-write with growth doubling; amortized O(N). Total cost: sub-millisecond.

**Severity:** NONE.

**Fix sketch:** none.

### H8 — mlx-swift-lm 3.x perf regressions. ❌ NOT A BOTTLENECK

**Evidence:**
- We're pinned to `exactVersion = 3.31.3` (`VoiceInk.xcodeproj/project.pbxproj`).
- `gh release list -R ml-explore/mlx-swift-lm --limit 15` confirms 3.31.3 is the latest release (published 2026-04-15). No 3.32.x or 4.x exists.
- 3.31.3 release notes include perf work: "Batched LLM inference part 1 - consolidating RoPE calls" (PR #178). 2.31.3 included "perf: eliminate CPU←GPU sync in penalty processors, optimize TopPSampler" (PR #147) — already in our build via the 3.31.3 cumulative.
- 2.x → 3.x is a major API rev (KVCache renames, Sendable cleanups, swift-tools 6.1) — no documented perf regressions.

**Severity:** NONE.

**Fix sketch:** stay on 3.31.3. Re-evaluate if a 3.32+ ships with prefill perf work.

---

### Bonus findings (beyond the brief)

#### B1 — No KV-cache reuse across enhancements

`MLXProvider.enhance(...)` builds a fresh `LMInput` and full prefill on every call. The system prompt is identical between calls (until the user switches prompt template), so the first ~1,275 tokens of every prefill are redundant.

mlx-swift-lm 3.x supports persistent KV caches across calls — see `Evaluate.swift:1184-1208` which accepts an optional `cache: [KVCache]?` and reuses it across `TokenIterator` constructions (`init(input:model:cache:parameters:)` line 585-604). The 2.31.3/3.31.3 release notes explicitly mention "Fix prompt-cache round-trip support for `ArraysCache`, `MambaCache`, and `CacheList`" (PR #155).

**Implication:** if `MLXProvider` retained a `prefillCache: [KVCache]?` keyed by `(systemPromptHash, contextHash)` and reused it on subsequent calls within the idle window, the second-onward enhance would skip the entire system-prompt prefill — potentially saving 1.5-3s per call on M-base. This is the highest-leverage fix beyond H6.

**Risk:** cache memory ~ system_prompt_tokens × num_layers × kv_dim × dtype_bytes. For Qwen3-4B (36 layers, 256 head dim, 4 KV heads, fp16): 1,275 × 36 × 4 × 256 × 2 × 2 = ~94 MB. Acceptable.

#### B2 — `Task.checkCancellation()` placement is decent but not airtight

`MLXProvider.swift:62, 83, 130, 164, 179` — checks at major boundaries. Inside the streaming loop, line 111 checks `Task.isCancelled` per token. Good enough; cancellation latency is bounded by per-token time (~30-100ms).

#### B3 — `mlxProvider(for:)` cache thrash on model toggles

`AIService.swift:273-285` — switching to a different model resets the cache and discards the previous model's weights. For users who toggle between two models in a session, this means churning two cold loads per toggle. Not a bug, but a counter to the "always keep one warm" strategy. Document or warn.

#### B4 — Eviction timer is reset on every enhance

`MLXProvider.swift:73, 223-231` — every successful enhance schedules a NEW eviction task that supersedes the previous one. So 10 min after the *last* enhance, not 10 min after the first. Correct behavior; flagged here only to confirm it's not the bug.

#### B5 — No `🦾 enhance:` log captures with real numbers exist in the repo

Searched `docs/superpowers/handoffs/` and `docs/superpowers/research/` for any prior captures of `total=…s` numbers from real runs. None found. The W10 plan §639-647 explicitly defers this to a "user runs sequential dictation cycles" step that hasn't been logged-back-to-repo yet. **The user's qualitative "still slow" report is the only evidence we have.** See §6 ground-truth recommendation for what to capture.

---

## 3. Pipeline breakdown table

Estimated wall-clock for a typical "first enhance after 10 min idle" with default settings, 50-token transcript, clipboard ON, screen-capture OFF, on M-base 32 GB. Numbers are extrapolated from mlx-swift-lm code paths + research notes; **none are measured on the user's specific machine**.

| Phase | What happens | Current cost | Recommended fix | Expected new cost |
|---|---|---|---|---|
| Model load (cold) | `loadModelContainer` reads ~2.3 GB safetensors → MLX wired memory | **1.5 - 4.0 s** (Qwen3-4B from disk) | Prewarm on app launch + on recording start; raise `idleEvictSeconds` to 1800 or disable on 32 GB | **0 s** in 90% of cases (warm) |
| Model load (warm) | Cache hit, no I/O | ~0 s | n/a | ~0 s |
| `prep` (tokenize + chat template) | swift-transformers BPE + swift-jinja apply | ~30-150 ms | Cache tokenized system prompt | ~5-10 ms |
| Prefill (system prompt) | Forward pass on ~1,275 system tokens | **~2.0 - 5.0 s** (Qwen3-4B at ~250 tok/s) | Shrink system prompt for short transcripts (H6) **+ KV-cache reuse (B1)** | **0.3 - 0.8 s** first call; **~0 s** subsequent |
| Prefill (user prompt) | Forward pass on ~50 user tokens | ~50-200 ms | n/a | ~50-200 ms |
| Sampler init | Build LogitSampler/Processor | <1 ms | Switch to `temperature: 0.0` → ArgMaxSampler | <1 ms (slightly faster per-token) |
| Generation (50-150 tokens) | Token loop, sample, detokenize, yield | **1.5 - 6.0 s** (12-100 tok/s × 50-150 tokens) | Greedy + tighter `max_tokens` ceiling + wall-clock timeout | 1.5 - 6.0 s but bounded ≤8 s |
| Output filter | Regex strip `<thinking>` etc | <1 ms | n/a | <1 ms |
| `stripPreamble` | First-line preamble heuristic | <1 ms | n/a | <1 ms |
| **Total (cold first)** | | **~5 - 15 s** | | **~2 - 7 s** |
| **Total (warm subsequent)** | | **~3 - 10 s** | | **~1 - 4 s** |

The user's "still slow" report is consistent with the high end of the cold-first and the low end of the warm-subsequent. A first-recording-after-coffee + clipboard ON + Qwen3-4B = the uncomfortable sweet spot.

---

## 4. Top 5 P0 fixes

Each fix is concrete, scoped, and low-risk. None require swapping models. Listed by leverage (highest first).

### P0-1 — Add MLX prewarm to `ModelPrewarmService` + on recording start
**File:** `VoiceInk/Services/ModelPrewarmService.swift:107-115` (extend the switch to include `.mlx`); **also** `VoiceInk/Transcription/Engine/VoiceInkEngine.swift:223-227` (add `await aiService.warmMLX()` to the existing `Task.detached` that captures clipboard/screen).
**Change:** add a `warmMLX()` method on `AIService` that calls `mlxProvider(for:).loadModel()` (need to expose loadModel or a public `warm()` shim on `MLXProvider`) without enhancing. **Wins ~2-4s of first-enhance latency in the common case.**

### P0-2 — Short-transcript fast-path system prompt
**File:** `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift:207-263` (the `if aiService.selectedProvider == .mlx` block, line 250-263).
**Change:** if `text.count < 200` AND `useClipboardContext == false` AND `useScreenCaptureContext == false`, swap `systemMessage` for a compact ~50-token "fix punctuation/grammar, output only cleaned text" prompt. **Drops system prefill from ~1,275 → ~50 tokens for short dictations. Wins ~1.5-4s.**

### P0-3 — Switch sampler to greedy
**File:** `VoiceInk/Services/AIEnhancement/MLXProvider.swift:94-98`.
**Change:** `GenerateParameters(maxTokens: dynamicMaxTokens, temperature: 0.0)`. Drop the `topP: 0.9`. **Routes to `ArgMaxSampler` per `Evaluate.swift:147`. Saves 5-15ms across a 100-token generation; quality impact zero on cleanup task.**

### P0-4 — Wall-clock generation timeout
**File:** `VoiceInk/Services/AIEnhancement/MLXProvider.swift:104-124`.
**Change:** wrap the `for await item in stream` loop in a `withTimeout(8s)` helper (or honor existing `EnhancementTimeoutSeconds` AppStorage key). On timeout, break the loop and return what we have (or throw `.generationFailed("Timed out")` — caller falls through to raw transcript per `TranscriptionPipeline.swift:149-167`). **Caps worst-case rambling at 8s; the existing 10s WARN log finally has a teeth.**

### P0-5 — Raise `idleEvictSeconds` default + expose in settings
**File:** `VoiceInk/Services/AIEnhancement/AIService.swift:282` (the `MLXProvider(modelId: modelId, idleEvictSeconds: 600)` call).
**Change:** read from `@AppStorage("MLXIdleEvictSeconds", default: 1800)` (30 min default). Add a slider/picker in MLX settings ("0 = never evict; 30 min default"). On a 32 GB Mac the model RAM cost is acceptable. **Reduces frequency of cold-load surprise.**

### P1 (deferred but high-value) — KV-cache reuse for system prompt
Track in a follow-up. Implementation is ~30 lines in `MLXProvider`: on first call, capture `cache = model.newCache(parameters:)` and run prefill inside a custom `TokenIterator` so the cache survives. Key by hash of (systemPrompt, model). On second call with matching key, pass `cache:` into `TokenIterator(input:model:cache:parameters:)` (Evaluate.swift:585-604). **This is the single biggest steady-state win** — second-onward enhances skip the system prefill. Listed as P1 because it requires understanding how `ModelContainer.generate(...)` interleaves with caller-supplied caches; that's a focused implementation packet on its own.

---

## 5. What's NOT worth fixing

- **Streaming `output += chunk`** — sub-ms total; rewriting to use `Array<String>` + `joined()` adds complexity for no measurable win (`MLXProvider.swift:101, 117`).
- **Bypassing chat template** — see H5. Quality regression dwarfs the 30ms saved.
- **Switching to a `RotatingKVCache`** (`maxKVSize` parameter on `GenerateParameters`) — for our typical ~150 generated tokens + ~1,500 prompt tokens, the regular `KVCacheSimple` is fine. Rotating cache only helps for >>32k context, which we never hit.
- **KV cache quantization** (`kvBits` on `GenerateParameters`) — saves RAM, costs accuracy + a quantize/dequantize cycle per layer per step. For our short-context cleanup task, net loss.
- **`prefillStepSize` tuning** — default 512 is fine for our prompt sizes. Smaller = more chunks = more sync overhead; larger = waste on short prompts.
- **Replacing `NaiveStreamingDetokenizer`** — already cheap; the per-token decode + suffix slice is microseconds.
- **`mlx-swift-lm` upgrade** — 3.31.3 is latest. No newer release. Don't preemptively pin to `main`.
- **Switching from `AsyncStream` → callback API** — same backing impl per `Evaluate.swift:1358+` and `:1455+`; the deprecated callback variants still run through `runSynchronousGenerationLoop`. No win.
- **Fancier `stripPreamble` regex** — already O(lines), runs on output ≤200 tokens, cost is negligible.

---

## 6. Ground-truth recommendation — what the user should run

Before implementing ANY of P0-1 through P0-5, capture **5 real `🦾 enhance: total=…s` log lines** so we have a baseline to compare against. Method:

### Setup
1. Open Console.app on the Mac.
2. Filter: `subsystem:com.prakashjoshipax.voiceink category:MLXProvider` (or just paste `🦾 enhance:` into the search field).
3. Have VoiceInk running with MLX selected as the AI Enhancement provider, default prompt active, clipboard context enabled (typical user state).
4. Pick the model: `Qwen3-4B-Instruct-2507-4bit-DWQ-2510` (the new W10 default). Make sure it's downloaded.

### Capture sequence
Run these 5 dictations sequentially. After each, **copy the full block of `🦾 enhance: ...` log lines from Console** and paste into a scratch doc. Each block has 4 lines (model-load if cold, prep, gen, total).

| # | Scenario | What to dictate | When |
|---|---|---|---|
| 1 | **Cold first** | "Hey Alex, can you send me the slides from yesterday's meeting?" | Right after launching the app (or after waiting ≥10 min since last enhance) |
| 2 | **Warm short** | "Yeah totally, thanks." | Within 30 seconds of #1 |
| 3 | **Warm medium** | "I think the issue is that we're not handling the empty case in the parser. Can you take a look at the file we discussed?" | Within 30 seconds of #2 |
| 4 | **Warm long** | A 30-second monologue describing what you did today (~150-300 words) | Within 30 seconds of #3 |
| 5 | **Cold-after-idle** | "Quick reminder for tomorrow morning standup." | Wait 11+ minutes after #4 (forces idle eviction), then dictate |

### What to look at in each capture
- **`model-load took X.XXs (cold)`** — should appear on #1 and #5 only. If it appears on #2/3/4, eviction timing is broken.
- **`prep=X.XXs maxTokens=N input=Mc`** — `prep` should be <0.2s. `maxTokens` shows the dynamic cap. `input=Mc` shows user-prompt char count.
- **`gen=X.XXs ttft=Y.YYs tokens≈N (Z.Z tok/s) output=Lc`** — `ttft` is time from `generate()` call → first chunk (≈ system prefill cost). `tok/s` is the steady-state rate. **Compare ttft #1 vs #2: the delta is the cold-load cost.** **Compare ttft #2 vs gen #2: ttft should be ~50-80% of gen.** If ttft is most of gen, the system prompt is dominating — that's H6.
- **`total=X.XXs`** — wall-clock the user feels.
- **`WARN total=X.XXs exceeds 10s ceiling`** — should not appear on any of #1-#5. If it does, that scenario is the worst case to optimize first.

### What good numbers look like
On M-base 32 GB with Qwen3-4B-Instruct-2507:
- #1 cold: load ~1.5-3.5s, ttft ~2-4s, gen ~2-5s, **total ~5-11s** (the discomfort case)
- #2 warm short: load 0s, ttft ~1.5-2.5s, gen ~1-2s, **total ~2.5-4.5s**
- #5 cold-after-idle: similar to #1

If your numbers cluster at the **high end** of those bands, H6 (system prompt) and H1 (cold load) are confirmed as the dominant costs and the P0 fixes will give you the biggest wins. If they cluster at the **low end**, the user's "still slow" perception is more about *consistent slowness across many dictations* than about catastrophic cold spikes — in which case P0-2 (short-transcript fast-path) and P1 (KV-cache reuse) are the bigger levers.

### Optional bonus capture
Repeat #2 and #3 with `Qwen3-1.7B-4bit-DWQ` selected. Compare warm-short total. If 1.7B is ≤2s and 4B is ≤4s, the speed-vs-quality tradeoff is well-shaped and the user might just want 1.7B as default for short dictation. If 1.7B is >3s on warm-short, system-prompt prefill is dominating both models and H6 is the unambiguous fix to lead with.

---

## Sources

- VoiceInk source files cited inline (`MLXProvider.swift`, `MLXModelRegistry.swift`, `AIEnhancementService.swift`, `AIEnhancementOutputFilter.swift`, `ModelPrewarmService.swift`, `AIService.swift`, `VoiceInkEngine.swift`, `TranscriptionPipeline.swift`, `AIPrompts.swift`, `PromptTemplates.swift`, `CustomPrompt.swift`, `ScreenCaptureService.swift`, `SelectedTextService.swift`).
- mlx-swift-lm 3.31.3 sources at `.local-build/SourcePackages/checkouts/mlx-swift-lm/Libraries/MLXLMCommon/{Evaluate,ModelContainer,Chat,UserInput,Tokenizer,ModelFactory}.swift` and `Libraries/MLXLLM/LLMModelFactory.swift`.
- [mlx-swift-lm 3.31.3 release notes](https://github.com/ml-explore/mlx-swift-lm/releases/tag/3.31.3) — confirms latest, perf work landed.
- [mlx-swift-lm 2.31.3 release notes](https://github.com/ml-explore/mlx-swift-lm/releases/tag/2.31.3) — TopPSampler perf PR #147.
- W6 plan `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` — origin of the 10s WARN log + speed-rating framework.
- W10 plan `docs/superpowers/plans/W10-mlx-registry-swap.md` — current Qwen3 registry rationale + sequential pre-merge testing protocol.
- Existing model research `docs/superpowers/research/2026-04-29-mlx-rewriting-models.md` — speed extrapolations.
- Handoff `docs/superpowers/handoffs/HANDOFF_post_redesign_open_asks_2026-04-29.md` — user's "Gemma is too slow" report (motivated W10).
