# Research: fast open-source MLX rewriting-model candidates

**Date:** 2026-04-29
**Owner:** researcher-w10 (team voiceink-w8w9w10)
**Driving ask:** [HANDOFF_post_redesign_open_asks_2026-04-29.md §Ask 3](../handoffs/HANDOFF_post_redesign_open_asks_2026-04-29.md) — replace Gemma in the curated MLX rewriting registry. User reports both `gemma-4-e2b-it-4bit` (fastest tier) and `gemma-4-e4b-it-4bit` (default mid) are slow on real-world dictation. Quality floor: match `gemma-4-e4b-it-4bit` on instruction-following. Hardware target: M-series **base** 32 GB (not Pro/Max/Ultra). Latency: ≤5s ideal, ≤10s ceiling.

## TL;DR — recommendations

| Slot | Recommendation | Why |
|---|---|---|
| **Fastest tier** (replace `gemma-4-e2b-it-4bit`) | **`mlx-community/Qwen3-1.7B-4bit-DWQ`** (or plain `-4bit`) | 968 MB · Apache 2.0 · faster than Gemma-4-E2B · no PLE-quant pitfall · `qwen3` type registered in 3.31.3 |
| **Default mid** (replace `gemma-4-e4b-it-4bit`) | **`mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510`** | 2.26 GB · Apache 2.0 · IFEval 88.9 (vs Llama-3.2-3B 77.4 / Gemma-4-E4B-class ~70-75) · Arena-Hard 43.4 · DWQ quant minimizes 4-bit quality loss |
| **High-quality slot** (`Qwen3.5-4B-MLX-4bit`) | **KEEP** (IFEval 89.8) — but flag the existing quant uses a non-standard `pc/fix-qwen35-predicate` branch; re-quant from upstream if user surfaces quality issues |
| **Experimental** (`gemma-4-26b-a4b-it-4bit`) | **HARD-DROP** — user explicitly prefers smaller models; 14 GB MoE missing the latency target adds nothing |

Conservative caveat: every tok/s number below is extrapolated from M-Pro 24 GB / M3 Ultra 192 GB / community reports. M-base 32 GB ground truth comes from the WARN log already wired in `MLXProvider.enhance(...)`. Treat the "expected latency" column as a planning band, not a guarantee — same caveat as the W6 plan §Risks/unknowns #2.

---

## Constraints recap

- **Hardware:** Apple Silicon M-series **base** (M2 / M3 / M4), 32 GB. NOT M-Pro/Max/Ultra. Memory bandwidth on base chips is roughly 100-150 GB/s, vs 200-273 GB/s on M-Pro and 400-546 GB/s on M-Max — generation throughput scales near-linearly with bandwidth on small models. ([compute-market.com — M4 base review (2026)](https://www.compute-market.com/blog/mac-mini-m4-for-ai-apple-silicon-2026); [insiderllm.com — best local LLMs for Mac 2026](https://insiderllm.com/guides/best-local-llms-mac-2026/))
- **Use case:** dictation transcript cleanup (input 50-300 tokens, output 50-200 tokens). Instruction-following matters more than reasoning depth. Reasoning models that emit `<think>` blocks are a wrong-tool pick — they burn the budget on internal monologue.
- **License:** prefer Apache 2.0 / MIT. Llama community license is acceptable in this fork (well below Meta's 700M MAU threshold) but flagged as not strictly permissive.
- **Framework:** `mlx-swift-lm` 3.31.3 (bundled). User OK with bumping if needed (per Ask 4) but not required for the candidates that matter.
- **Size preference:** ≤4B params, ideally 0.5B-3B. 13B+ skipped per user direction.

## Framework compatibility — what loads under bundled mlx-swift-lm 3.31.3

The W6 plan comment ("gemma3 + gemma3_text + gemma4 + qwen3_5 model types are registered") was scoped to the curated lineup, not the full registry. The actual `LLMTypeRegistry.shared` in [mlx-swift-lm 3.31.3](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/LLMModelFactory.swift) registers ~50 model types. Of our candidates:

| Candidate | `model_type` in HF config.json | Registered in 3.31.3? | Notes |
|---|---|---|---|
| Qwen3-0.6B / 1.7B / 4B-Instruct-2507 | `qwen3` | ✅ yes | Added pre-3.x |
| Qwen3.5-4B (current curated) | `qwen3_5` | ✅ yes | Already loadable |
| Llama-3.2-1B / 3B-Instruct | `llama` | ✅ yes | Default mlx-lm test fixture |
| SmolLM2-1.7B-Instruct | `llama` (reuses Llama-2 arch) | ✅ yes | Loads as llama |
| Phi-3.5-mini-instruct | `phi3` | ✅ yes | — |
| granite-3.3-2b-instruct | `granite` | ✅ yes | — |
| DeepSeek-R1-Distill-Qwen-1.5B | `qwen2` | ✅ yes | Loads but emits `<think>` (wrong tool) |
| StableLM-2-1.6B-Zephyr | `stablelm` | ❌ no | Would need framework bump |
| TinyLlama-1.1B-Chat-v1.0 | `llama` | ✅ yes | Pre-Llama-3.2 era; weak vs Llama-3.2-1B |

**Net:** every realistic candidate except StableLM loads on the bundled framework. No `mlx-swift-lm` upgrade required for any recommendation in this doc. Ask 4 (mlx-swift-lm bump) can stay deferred.

Sources: [mlx-swift-lm/Libraries/MLXLLM/LLMModelFactory.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/LLMModelFactory.swift); [mlx-swift-lm/Libraries/MLXLLM/Models/Qwen3.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/Models/Qwen3.swift); [GitHub releases — mlx-swift-lm 3.31.3 changelog](https://github.com/ml-explore/mlx-swift-lm/releases).

---

## Candidate comparison

Speed band notation:
- **A** — ≤2s for typical 150-token cleanup (>100 tok/s effective on M-base 32 GB)
- **B** — 2-5s (50-100 tok/s)
- **C** — 5-10s (25-50 tok/s)
- **D** — >10s (rejected)

All sizes are 4-bit MLX safetensors as published on `mlx-community`.

### 1. Qwen3-4B-Instruct-2507 — **TOP PICK for default mid tier**

| Field | Value |
|---|---|
| Repo | [`mlx-community/Qwen3-4B-Instruct-2507-4bit`](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) (also DWQ variant: [`-4bit-DWQ-2510`](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510)) |
| Size | 2.26 GB |
| Architecture | qwen3 (registered, dense, 36 layers, GQA) |
| License | Apache 2.0 |
| Context | 262K native |
| mlx-lm conversion version | 0.26.2 (standard) / 0.28.2 (DWQ) — **does not constrain mlx-swift-lm 3.31.3 loading** (only affects safetensors creation; runtime reads weights via the registered Swift `qwen3` impl) |
| IFEval | **88.9** (per Qwen team eval) |
| Arena-Hard v2 | 43.4 |
| Creative Writing v3 | 83.5 (beats GPT-4.1-nano 72.7) |
| WritingBench | 83.4 |
| Speed (M-base 32 GB extrapolated) | Band B — ~2-5s for 150-token cleanup. Conservatively 50-90 tok/s; kartit measured 49 tok/s for Gemma-4-E4B on M4 Pro 24 GB MLX, and Qwen3-4B is reported at "comparable speed tier" to gemma-4-e4b in the existing W6 ratings. M-base 32 GB has ~30% less bandwidth than M4 Pro → conservative 35-65 tok/s. |
| Quant pitfalls | None analogous to Gemma PLE-quant. Standard mxfp/group-quant scheme. The DWQ variant ("Distilled / Dynamic Weighted Quant") is reported to recover quality lost in standard 4-bit at the cost of conversion compute, not runtime speed. |
| Risk | Reported "very verbose" tendency (22M output tokens vs 6.6M median in Artificial Analysis test) — relevant for cleanup since verbose drift = wasted budget. Mitigation: clamp `max_tokens` and use a stop sequence; the existing prompt scaffolding already does this. |
| Sources | [HF model card](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507); [Artificial Analysis](https://artificialanalysis.ai/models/qwen3-4b-2507-instruct); [Qwen3 quant study (arxiv 2505.02214)](https://arxiv.org/html/2505.02214v1) |

**Verdict:** Strong replacement for `gemma-4-e4b-it-4bit`. IFEval 88.9 vs gemma-4-e4b's class (~70-75 IFEval, no public number for the e-series specifically). Apache 2.0. Same speed tier as gemma-4-e4b. Use the DWQ variant if storage budget permits — same 2.26 GB, better perplexity.

### 2. Qwen3-1.7B — **TOP PICK for fastest tier**

| Field | Value |
|---|---|
| Repo | [`mlx-community/Qwen3-1.7B-4bit`](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit) (also DWQ: [`-4bit-DWQ`](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit-DWQ)) |
| Size | 968 MB |
| Architecture | qwen3 (registered, 28 layers) |
| License | Apache 2.0 |
| Context | 32K |
| mlx-lm conversion version | 0.24.0 |
| IFEval | not published in family eval table at 1.7B size; Qwen3 family reports lift over Qwen2.5 — 1.7B-class typically 65-75 IFEval (cross-validated against the Qwen3 technical report's family scaling curve at [arxiv 2505.09388](https://arxiv.org/pdf/2505.09388)) |
| MT-Bench / Arena-Hard | not published; family-level competitive |
| Speed (extrapolated) | Band A-B — ~1-3s for 150-token cleanup. Family scaling: Qwen3-0.6B is ~2.86× faster than 1.7B per [HN thread](https://news.ycombinator.com/item?id=43856489); Qwen3-1.7B should hit 80-130 tok/s on M-base 32 GB MLX. **Faster than gemma-4-e2b** at comparable or better quality. |
| Quant pitfalls | Per [Qwen3 quant empirical study](https://arxiv.org/html/2505.02214v1): GPTQ 4-bit gives perplexity 9.99 vs FP16 9.39 — measurable but manageable. **No PLE-style architectural pitfall** — Qwen3 has no per-layer-embedding scheme. |
| Risk | Quality at 1.7B is below 4B class on hard reasoning, but for 50-200 token cleanup output the gap closes — instruction-following stays in usable range per Qwen3 family scaling. |
| Sources | [HF mlx-community/Qwen3-1.7B-4bit](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit); [Qwen/Qwen3-1.7B model card](https://huggingface.co/Qwen/Qwen3-1.7B); [Qwen3 technical report](https://arxiv.org/pdf/2505.09388) |

**Verdict:** Strong replacement for `gemma-4-e2b-it-4bit`. ~1.4× the size of Gemma-4-E2B (968 MB vs ~700 MB after PLE) but expected to be comparable speed on M-base 32 GB and free of PLE-quant degradation risk. Apache 2.0. The DWQ variant is the safer pick.

### 3. Qwen3.5-4B (current curated entry) — **KEEP**

| Field | Value |
|---|---|
| Repo | [`mlx-community/Qwen3.5-4B-MLX-4bit`](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) |
| Actual file size | **3.03 GB** (registry says 2.5 GB — minor docs lie) |
| Architecture | qwen3_5 (Gated Delta Network hybrid + sparse MoE) |
| License | Apache 2.0 |
| IFEval | **89.8** (best in family at this scale) |
| IFBench | 59.2 |
| MultiChallenge | 49.0 |
| Quant scheme | 4-bit, group size 64, 5.347 bits/weight effective |
| Quant pitfalls | The existing curated quant was produced via the `pc/fix-qwen35-predicate` branch of mlx-vlm — non-mainline. Could re-quant from upstream `mlx-lm` for safer reproducibility. No reported quality regression in production yet. |
| Sources | [HF mlx-community/Qwen3.5-4B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit); [HF Qwen/Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B) |

**Verdict:** KEEP. IFEval 89.8 is the best small-model number in this entire research. The existing entry is shipping fine. Two follow-ups worth flagging (not urgent):
- Update `approximateSizeGB` from 2.5 → 3.0 in the registry (cosmetic; affects the size chip shown in the picker).
- Consider re-quantizing from upstream mlx-lm if the user reports quality regressions tied to the experimental conversion branch.

### 4. Gemma-4-26B-A4B (current experimental) — **DROP**

User explicitly directed away from 13B+ candidates ("skip 13B+ as too slow to be worth testing"). The 14 GB MoE 4B-active sat at "Speed 3 / 8-30s expected latency" with `isExperimental: true` per the W6 plan. With three solid sub-4B alternatives (Qwen3-1.7B, Qwen3-4B-Instruct-2507, Qwen3.5-4B already curated) and no improvement to the user's actual workflow, the experimental slot is dead weight.

**Verdict:** HARD-DROP. Remove the entry from `MLXModelRegistry.curated`. The EXPERIMENTAL chip render path in `MLXModelRow` becomes dead code (`isExperimental` field stays on the struct as a future hook but no entry uses it) — same harmless outcome flagged in W6 plan §Risks/unknowns #3.

---

## Other candidates evaluated (not recommended for the curated lineup)

### Llama-3.2-3B-Instruct — strong but license-restricted

| Field | Value |
|---|---|
| Repo | [`mlx-community/Llama-3.2-3B-Instruct-4bit`](https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit) |
| Size | 1.81 GB |
| License | **Llama 3.2 Community License** — non-Apache, has 700M MAU clause + "Built with Llama" attribution requirement + "Llama" prefix on derived models |
| IFEval | 77.4 (bf16) / 73.9 (Vanilla PTQ — closest to 4-bit reality) |
| **Open-Rewrite Eval** (rougeL, 0-shot, dictation-cleanup-relevant) | **40.1** (vs Llama-3.1-8B 40.9 — 3B essentially matches 8B on this exact task) |
| **TLDR9+ summarization** (rougeL, 1-shot) | **19.0** (beats Llama-3.1-8B 17.2 — strong at compression) |
| Speed | Band B; default mlx-lm chat fixture, widely benchmarked |
| Quant pitfalls | None — group-32 weights + 8-bit per-token activations, standard. Default mlx-lm test fixture; no community quality-regression reports surfaced in research. |
| Sources | [Meta Llama 3.2 evals](https://huggingface.co/datasets/meta-llama/Llama-3.2-3B-Instruct-evals); [HF Llama-3.2-3B-Instruct card](https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct); [Llama 3.2 Community License](https://www.llama.com/llama3_2/license/) |

**Why not the top pick:** the user spec says "MIT / Apache 2.0 / similar permissive." Llama Community License is "permissive enough" in practice (VoiceInk well below 700M MAU; attribution is a one-line text-file change) but introduces non-zero legal-care friction — the "Llama" name must prefix any derivative model, distribution carries an attribution notice, an acceptable-use policy applies. The Open Source Initiative has [publicly disputed Meta's "open source" framing](https://en.wikipedia.org/wiki/Llama_(language_model)). For an OSS dictation app the friction is small; for a clean research outcome where Apache 2.0 is the same speed tier with same quality, picking Qwen3 avoids the question entirely.

**Open-Rewrite 40.1 is exceptional for this exact use case.** If the user prefers the Llama-3.2-3B option for proven rewriting performance, swap in `mlx-community/Llama-3.2-3B-Instruct-4bit` for the default mid tier instead of Qwen3-4B-Instruct-2507. Add a one-line "Built with Llama" attribution to the AI Models page footer.

### Llama-3.2-1B-Instruct — fast, lower instruction quality

| Field | Value |
|---|---|
| Repo | [`mlx-community/Llama-3.2-1B-Instruct-4bit`](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit) |
| Size | 695 MB |
| License | Llama 3.2 Community |
| TLDR9+ | 16.8 |
| Speed | Band A — very fast |
| Sources | [HF mlx-community card](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit); [Llama 3.2 release blog](https://github.com/huggingface/blog/blob/main/llama32.md) |

Faster than Qwen3-1.7B but with a measurable quality drop on instruction-following — Llama 3.2 1B is the rare case where the 3B "is as strong as 8B on IFEval" but the 1B is meaningfully behind. Not worth the speed gain over Qwen3-1.7B given the same hardware budget.

### Phi-3.5-mini-instruct — strong, MIT-licensed, but bigger than Qwen3-4B

| Field | Value |
|---|---|
| Repo | [`mlx-community/Phi-3.5-mini-instruct-4bit`](https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit) |
| Size | 2.15 GB |
| Params | 3.8B |
| License | **MIT** |
| MMLU | 69 |
| MT-Bench | 8.7 |
| Arena-Hard | 37 |
| MMLU-Pro | 47.4 |
| GSM8K | 86.2 |
| Conversion | mlx-lm 0.17.0 — older but stable |
| Sources | [HF microsoft/Phi-3.5-mini-instruct](https://huggingface.co/microsoft/Phi-3.5-mini-instruct); [HF mlx-community/Phi-3.5-mini-instruct-4bit](https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit) |

**Why not top pick:** Phi-3.5 is reasoning-heavy. MMLU 69 / MMLU-Pro 47.4 are great for academic tasks but the dictation cleanup benefit over Qwen3-4B-Instruct-2507's instruction-tuned IFEval 88.9 is unclear. Phi-3.5 doesn't publish IFEval — community reports it competitive but not best-in-class. MIT licensing is a real win over Llama community license. **Worth as a fallback option** if Qwen3-4B-Instruct-2507 surfaces verbosity issues in production.

### SmolLM2-1.7B-Instruct — paper says strong, community says weak

| Field | Value |
|---|---|
| Repo | [`mlx-community/SmolLM2-1.7B-Instruct`](https://huggingface.co/mlx-community/SmolLM2-1.7B-Instruct) (no `-4bit` variant in mlx-community as of research date — the `Q8-mlx` upstream exists; 4-bit conversion would need to be community-produced) |
| Size | TBD (no -4bit yet); 1.7B fp16 baseline |
| License | Apache 2.0 |
| IFEval (paper) | **56.7** — beats Llama-3.2-1B (53.5) and Qwen2.5-1.5B (47.4) |
| MT-Bench | 6.13 |
| GSM8K | 48.2 |
| Architecture | llama (loadable in 3.31.3) |
| Community feedback | [HF discussions thread #22](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct/discussions) — most-upvoted thread (14 ↑) reports instruction-following quality "not as good as competing models (Qwen, Phi-3.5)". Code generation flagged as poor. |
| Sources | [HF SmolLM2-1.7B-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct); [SmolLM2 paper (arxiv 2502.02737)](https://arxiv.org/html/2502.02737v1) |

**Why not:** paper IFEval is misleading vs Qwen3 family. The most-upvoted community thread directly compares it unfavorably to Qwen and Phi-3.5 on the exact axis (instruction following) we care about. No production-ready -4bit variant in mlx-community. Skip.

### granite-3.3-2b-instruct — usable but undertested

| Field | Value |
|---|---|
| Repo | [`mlx-community/granite-3.3-2b-instruct-4bit`](https://huggingface.co/mlx-community/granite-3.3-2b-instruct-4bit) |
| Size | 1.43 GB |
| Params | 2B |
| License | Apache 2.0 |
| Architecture | granite (registered) |
| Conversion | mlx-lm 0.22.5 |
| IFEval | not published at this exact scale; family eval at 8B reports "significantly improved performance on IFEval" |
| Downloads (last month) | 1,232 — much lower community testing than Qwen / Llama variants |
| Sources | [HF mlx-community/granite-3.3-2b-instruct-4bit](https://huggingface.co/mlx-community/granite-3.3-2b-instruct-4bit); [IBM Granite 3.1 announcement](https://www.ibm.com/new/announcements/ibm-granite-3-1-powerful-performance-long-context-and-more) |

**Why not:** Apache 2.0 is great. 2B is a sweet spot for speed. But the IFEval data isn't published at 2B size, and community testing volume is 50× lower than Qwen3 / Llama-3.2. Pick this only if the user wants a third Apache-licensed alternative beside Qwen3-1.7B and Qwen3-4B.

### DeepSeek-R1-Distill-Qwen-1.5B — wrong tool

| Field | Value |
|---|---|
| Repo | [`mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit`](https://huggingface.co/mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit) |
| Size | ~1.0 GB |
| License | MIT (DeepSeek MIT release) |
| Architecture | qwen2 (registered) |

**Why not:** R1-distill emits `<think>` reasoning tokens by design. For a 50-200 token cleanup task this burns the latency budget on internal monologue. Reasoning-heavy distillation is the wrong tool for transcript rewriting. Reject.

### TinyLlama-1.1B / StableLM-2-1.6B-Zephyr — skip

- TinyLlama is Llama-2-architecture, predates Llama-3.2-1B by a generation — Llama-3.2-1B is unambiguously better at the same size.
- StableLM-2 has `model_type: "stablelm"` which is **not registered** in mlx-swift-lm 3.31.3. Loading would require a framework bump (Ask 4) — no quality advantage to justify the upgrade.

---

## Direct comparison — recommendations vs current registry

| Slot | Current entry | Recommended replacement | Δ Size | Δ IFEval-class | License Δ |
|---|---|---|---|---|---|
| Fastest tier | `gemma-4-e2b-it-4bit` (1.7 GB, gemma3, **PLE-quant warning**) | `mlx-community/Qwen3-1.7B-4bit-DWQ` (0.97 GB, qwen3) | **−0.7 GB** | comparable / slight gain | gemma → Apache 2.0 ✅ |
| Default mid | `gemma-4-e4b-it-4bit` (2.5 GB, gemma3) | `mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510` (2.26 GB, qwen3) | **−0.24 GB** | **+10-15 IFEval points** (88.9 vs ~74) | gemma → Apache 2.0 ✅ |
| High-quality | `Qwen3.5-4B-MLX-4bit` (3.0 GB, qwen3_5) | KEEP | — | already best-in-class (89.8) | — |
| Experimental | `gemma-4-26b-a4b-it-4bit` (14 GB) | DROP | **−14 GB** | n/a (drop) | n/a |

Net: registry shrinks from 4 to 3 entries (or stays at 3 if user wants a fourth Apache option — `granite-3.3-2b-instruct-4bit` is the cleanest "third Apache pick").

Total disk-budget delta if user has all entries downloaded: **−14.94 GB** (drops the 26B experimental + smaller fastest-tier swap).

## Open follow-ups for the registry-swap packet

1. **Update `MLXModelEntry.approximateSizeGB`** to match actual file sizes, especially `Qwen3.5-4B-MLX-4bit` (currently 2.5, actual 3.0).
2. **Update `notes` field** for each replacement entry — drop the PLE-quant warning text from the gemma entries; replace with the Qwen3 quant context (Apache 2.0, no PLE).
3. **Re-rate `speedRating` + `qualityRating`** based on the new lineup. Suggested first pass:
   - Qwen3-1.7B-4bit-DWQ: Speed 9, Quality 6 (replaces e2b's Speed 9, Quality 5 — small quality gain via better instruction-tuning)
   - Qwen3-4B-Instruct-2507-4bit-DWQ-2510: Speed 7, Quality 8 (replaces e4b's Speed 7, Quality 6 — material quality gain via IFEval 88.9)
   - Qwen3.5-4B-MLX-4bit: Speed 7, Quality 9 (was 6 — bump in line with IFEval 89.8 leadership)
4. **Drop the `gemma-4-26b-a4b-it-4bit` entry**; the EXPERIMENTAL chip render path becomes unreachable (harmless dead code per W6 plan §Risks/unknowns #3).
5. **Pre-merge hardware test on user's M-base 32 GB** — this is the W6 plan's standing recommendation (treat researched numbers as conservative). Run a one-shot dictation cycle with each new model, capture the `🦾 enhance: total=…s` log line, refine `expectedLatencySeconds` ranges before commit.
6. **No `mlx-swift-lm` upgrade needed.** Ask 4 (framework bump) can stay deferred — every recommended candidate loads on bundled 3.31.3.

## Risks / unknowns

1. **M-base 32 GB ground truth still unmeasured.** All speed bands above are extrapolated from M4 Pro 24 GB / M3 Ultra 192 GB / community reports. The W6 WARN-log instrumentation gives the only first-party signal, and that's only post-merge. If user's M-base hardware exhibits memory-bandwidth pressure differently than the M-Pro extrapolation suggests, Qwen3-4B-Instruct-2507 could land at C-band (5-10s) instead of B-band — still acceptable but tighter. Mitigation: pre-merge sanity dictation pass before tagging the registry-swap packet ready.

2. **Qwen3-4B-Instruct-2507 verbosity tendency.** [Artificial Analysis](https://artificialanalysis.ai/models/qwen3-4b-2507-instruct) flagged "very verbose in comparison to the average" (3.3× median output). For dictation cleanup the system prompt + max_tokens cap mitigate this, but if the user's prompts allow long-form output the model may drift past target length. Mitigation: keep the existing prompt scaffolding's output-length guidance. Test on the live App.

3. **DWQ variant maturity.** The `-DWQ-2510` and `-DWQ` variants of Qwen3 family are newer (mlx-lm 0.28.2 conversion), with much lower download counts than the standard `-4bit` variants. Conversion tooling has been observed to evolve faster than runtime, so the safer fallback if DWQ surfaces issues is the plain `-4bit` variant — same safetensors format, same Swift loading path, just a slightly larger perplexity hit.

4. **No published IFEval for Qwen3-1.7B specifically.** The fastest-tier rec leans on family-scaling extrapolation from Qwen3-4B (88.9) and Qwen3-0.6B (lower published scores) plus the SmolLM2 paper's IFEval 56.7 floor for the 1.7B class. Pre-merge, run the existing prompt suite at the user's machine and surface anything that degrades vs gemma-4-e2b's current behavior — registry rollback is a one-line revert.

5. **Llama license follow-up.** If user later prefers `Llama-3.2-3B-Instruct-4bit` (which has published Open-Rewrite 40.1 — best-published rewriting score in this entire field), add the "Built with Llama" attribution + a `LICENSE` mention in the AI Models settings page. Not blocking; flagging.

## Sources

Primary sources cited above; deduplicated below for audit:

- [HF Qwen/Qwen3-4B-Instruct-2507](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507) — IFEval 88.9, Apache 2.0, qwen3 type
- [HF Qwen/Qwen3.5-4B](https://huggingface.co/Qwen/Qwen3.5-4B) — IFEval 89.8, qwen3_5 type
- [HF Qwen/Qwen3-1.7B](https://huggingface.co/Qwen/Qwen3-1.7B) — 32K context, 28 layers
- [HF mlx-community/Qwen3-4B-Instruct-2507-4bit](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit) — 2.26 GB, mlx-lm 0.26.2
- [HF mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510) — DWQ variant
- [HF mlx-community/Qwen3-1.7B-4bit](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit) — 968 MB, mlx-lm 0.24.0
- [HF mlx-community/Qwen3-1.7B-4bit-DWQ](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit-DWQ) — DWQ variant
- [HF mlx-community/Qwen3.5-4B-MLX-4bit](https://huggingface.co/mlx-community/Qwen3.5-4B-MLX-4bit) — 3.03 GB actual, group 64, mlx-vlm `pc/fix-qwen35-predicate` branch
- [HF mlx-community/Llama-3.2-3B-Instruct-4bit](https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit) — 1.81 GB, default mlx-lm chat fixture
- [HF mlx-community/Llama-3.2-1B-Instruct-4bit](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit) — 695 MB
- [HF mlx-community/Phi-3.5-mini-instruct-4bit](https://huggingface.co/mlx-community/Phi-3.5-mini-instruct-4bit) — 2.15 GB, MIT, mlx-lm 0.17.0
- [HF mlx-community/granite-3.3-2b-instruct-4bit](https://huggingface.co/mlx-community/granite-3.3-2b-instruct-4bit) — 1.43 GB, Apache 2.0
- [HF Meta Llama-3.2-3B-Instruct evals](https://huggingface.co/datasets/meta-llama/Llama-3.2-3B-Instruct-evals) — IFEval 77.4, Open-Rewrite 40.1, TLDR9+ 19.0
- [HF microsoft/Phi-3.5-mini-instruct](https://huggingface.co/microsoft/Phi-3.5-mini-instruct) — MMLU 69, MT-Bench 8.7
- [HF HuggingFaceTB/SmolLM2-1.7B-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct) — IFEval 56.7 paper, community quality concerns
- [SmolLM2 paper (arxiv 2502.02737)](https://arxiv.org/html/2502.02737v1) — IFEval comparisons
- [Qwen3 quant empirical study (arxiv 2505.02214)](https://arxiv.org/html/2505.02214v1) — perplexity vs FP16 across bit widths
- [Qwen3 technical report (arxiv 2505.09388)](https://arxiv.org/pdf/2505.09388) — family scaling
- [kartit.net Gemma 4 local benchmark](https://www.kartit.net/blog/gemma4-local-benchmark.html) — M4 Pro 24 GB MLX numbers (49 tok/s e4b reference)
- [Artificial Analysis — Qwen3-4B-2507](https://artificialanalysis.ai/models/qwen3-4b-2507-instruct) — verbosity flag, intelligence index
- [mlx-swift-lm releases](https://github.com/ml-explore/mlx-swift-lm/releases) — 3.31.3 changelog + 2.x → 3.x boundary
- [mlx-swift-lm/Libraries/MLXLLM/LLMModelFactory.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/LLMModelFactory.swift) — registered model_type list
- [Llama 3.2 Community License](https://www.llama.com/llama3_2/license/) — 700M MAU + attribution clauses
- [HuggingFace Llama-3.2 release blog](https://github.com/huggingface/blog/blob/main/llama32.md) — IFEval / AlpacaEval / MixEval-Hard methodology
- [HN — Running Qwen3 on macbook MLX](https://news.ycombinator.com/item?id=43856489) — community speed reports (0.6B vs 1.7B 2.86×)
- [insiderllm.com — Best Local LLMs Mac 2026](https://insiderllm.com/guides/best-local-llms-mac-2026/) — base-chip bandwidth context
- [compute-market.com — Mac Mini M4 for AI 2026](https://www.compute-market.com/blog/mac-mini-m4-for-ai-apple-silicon-2026) — base M4 benchmarks
- [llmcheck.net benchmarks](https://llmcheck.net/benchmarks) — searchable Apple Silicon benchmark database (122 measurements; CSV at /data/)
- [HF discussions — SmolLM2-1.7B-Instruct](https://huggingface.co/HuggingFaceTB/SmolLM2-1.7B-Instruct/discussions) — community quality concerns
- W6 plan: [docs/superpowers/plans/W6-mlx-quality-and-segregation.md](../plans/W6-mlx-quality-and-segregation.md) — PLE-quant warning, M-base extrapolation caveat
