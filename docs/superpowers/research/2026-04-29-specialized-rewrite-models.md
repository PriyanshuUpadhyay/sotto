# Research: specialized rewrite models for VoiceInk MLX enhance pipeline (deep dive)

**Date:** 2026-04-29
**Owner:** researcher-models (team `w11-deep-research`)
**Driving ask:** W10 swap (Gemma-4 → Qwen3) still slow on real-world dictation. Find models PURPOSE-BUILT for transcript cleanup / grammar correction / rewriting that go BEYOND the general instruction-tuned LLMs already explored in [`2026-04-29-mlx-rewriting-models.md`](./2026-04-29-mlx-rewriting-models.md).
**Hardware:** Apple Silicon M-series base (M2/M3/M4 base, NOT Pro/Max/Ultra), 32 GB. Latency: ≤5s ideal, ≤10s ceiling. Typical input 50-300 tokens, output 50-200 tokens.

---

## 1. TL;DR — top 3 picks

| Rank | Pick | One-line why |
|---|---|---|
| **1** | **Apple Foundation Models framework** (macOS 26+ conditional path) | OS-built-in 3B AFM, 2-bit quantized, OS daemon already runs constrained + speculative decoding — VoiceInk ships zero model bytes, gets sub-150ms first-token on capable hardware, free. Gated on `@available(macOS 26.0, *)` so it sits next to the existing MLX path, not replacing it. |
| **2** | **Speculative decoding** via `mlx-community/speculative-decoding` Swift package, draft `Qwen3-0.6B-4bit` (335 MB) + target `Qwen3-4B-Instruct-2507-4bit-DWQ-2510` | 2–3× generation speedup with **exact** output equivalence (no quality regression). Native Swift API, drops into the existing MLXProvider with a focused refactor. Better lever than another model swap. |
| **3** | **`mlx-community/Qwen3-0.6B-4bit`** as new ULTRA-FAST tier (or as the speculative draft) | 335 MB, Apache 2.0, qwen3 type loadable in mlx-swift-lm 3.31.3 today. Sub-second cleanup achievable on M-base 32 GB. Use `enable_thinking=False` to skip the `<think>` block. |

**Architectural verdict for the W11 registry refresh:** stop trying to find a smaller decoder-only LLM that's both faster AND keeps quality — the curve is mostly tapped. The two real levers are (a) speculative decoding on the EXISTING Qwen3 lineup, and (b) tapping Apple's OS-built-in model on macOS 26+. Both are additive to W10. Detailed recommendations in §6.

---

## 2. Comparison table — every serious candidate

Speed bands: **A** ≤2s · **B** 2-5s · **C** 5-10s · **D** >10s (rejected). All sizes 4-bit unless noted.

| Candidate | Class | Size 4-bit | License | mlx-swift-lm 3.31.3 loadable? | Quality on rewrite | Speed band (M-base) | Verdict |
|---|---|---|---|---|---|---|---|
| **Apple Foundation Models (AFM-on-device)** | OS-builtin decoder | 0 (in OS) | OS framework, free for App Store apps | n/a (uses `FoundationModels` Swift framework, not mlx-swift) | strong; constrained decoding + safety filters | **A** (sub-150ms TTFT prewarm) | **TOP — conditional on macOS 26** |
| **Qwen3-0.6B-4bit** | dense decoder, qwen3 | 335 MB | Apache 2.0 | ✅ yes (`qwen3`) | family-extrapolated IFEval ~50-60 | **A** | **NEW fastest tier OR draft** |
| **Qwen3-1.7B-4bit-DWQ** (current fastest) | dense decoder, qwen3 | 968 MB | Apache 2.0 | ✅ yes | IFEval ~65-75 (extrap.) | **A-B** | KEEP (current W10 lineup) |
| **Qwen3-4B-Instruct-2507-4bit-DWQ-2510** (current mid) | dense decoder, qwen3 | 2.26 GB | Apache 2.0 | ✅ yes | IFEval **88.9** | **B** | KEEP — pair with spec-decode |
| **SmolLM3-3B-4bit-DWQ** | dense decoder, smollm3 | ~1.7 GB | Apache 2.0 | ✅ yes (`smollm3` registered) | IFEval **76.7** (no-think) — best in 3B class | **B** | OPTIONAL alt to Qwen3-4B (smaller, simpler) |
| **LFM2.5-1.2B-Instruct** | hybrid (Liquid arch) | 580 MB est. | **lfm1.0 (restrictive)** ❌ | ✅ yes (`lfm2`) | **IFEval 86.23** (best <2B) | **A-B** | **REJECT** — non-permissive license |
| **Apple OpenELM-450M-Instruct** | Apple-trained decoder | ~250 MB | **Apple AMLR (proprietary)** ❌ | ✅ yes (`openelm`) | ARC/HS/PIQA only — weak instruction tuning | **A** | **REJECT** — license incompatible w/ OSS |
| **Phi-4-mini-instruct (3.8B)** | dense decoder, phi3 | ~2.3 GB | MIT ✅ | ✅ yes (`phi3`) | IFEval 73.8 | **B** | Lower IFEval than Qwen3-4B-Instruct-2507; skip |
| **Lille-130m-instruct-4bit** | dense decoder | ~80 MB | (custom open) | ✅ yes (`lille-130m`) | very weak (130M trained on 4.27B tok single 4070-Ti) | A+ | Useful only as **draft model**; not a primary cleanup tier |
| **CoEdIT-large** (T5-based) | encoder-decoder, T5 | ~770M params, ~400 MB FP16 | **CC-BY-NC-4.0** ❌ | ❌ no (no T5/encoder-decoder type registered) | SOTA on text-edit benchmarks (60× smaller than competing LLMs) | n/a (can't load) | **DOUBLE REJECT** — license + framework |
| **GECToR** (sequence tagger) | BERT/RoBERTa+tagger | <500 MB | Apache 2.0 ✅ | ❌ no | F0.5 65.3 CoNLL-2014 / 72.4 BEA-2019; **10× faster than seq2seq** | n/a (can't load) | REJECT for primary path; flag for grammar-only mode |
| **flan-t5-small / -base** | encoder-decoder, T5 | 80-250 MB | Apache 2.0 ✅ | ❌ no | weak vs Qwen3 family on instruction-following | n/a (can't load) | REJECT (framework) |
| **Granite-3.3-2b-instruct** | dense decoder, granite | 1.43 GB | Apache 2.0 ✅ | ✅ yes (`granite`) | family-level competitive; no published 2B IFEval | **B** | Acceptable third Apache option; not a clear win |
| **Harper** (rule-based) | non-LLM, Rust crate | <10 MB | Apache 2.0 ✅ | n/a (not an LLM) | rule-based GEC + punctuation; <10ms latency | A+ | OPTIONAL pre-LLM filter / "no AI" mode |

---

## 3. Per-candidate detail

### 3.1 Apple Foundation Models framework — TOP STRATEGIC PICK (gated on macOS 26)

Apple shipped a Swift-native `FoundationModels` framework at WWDC25 / macOS 26 that exposes the on-device 3B AFM model directly to apps. ([Apple Developer — Foundation Models](https://developer.apple.com/documentation/FoundationModels), [Apple ML research — 2025 updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates), [Apple ML research — Tech Report 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025)).

| Field | Value |
|---|---|
| Model | ~3B AFM-on-device, **2-bit quantized weights via QAT + LoRA adapters** for 8-12 GB RAM target |
| Distribution | OS-bundled — VoiceInk app would ship **zero model bytes** |
| Licensing for OSS apps | Free for all apps; subject to Apple's [Acceptable use requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/) |
| OS minimum | **macOS 26 (Tahoe)** — public Sept 2025 |
| Hardware minimum | Apple Intelligence-capable Mac (M1+); user must turn on Apple Intelligence in System Settings |
| Context window | **4096 tokens combined** (input + output) — fine for our 50-300 in / 50-200 out |
| Latency | with `session.prewarm()` first-token <150ms on A18-class silicon; "first-token latency cut by up to 40%" ([Apple WWDC25 video 286](https://developer.apple.com/videos/play/wwdc2025/286/)) |
| Built-in optimizations | OS daemon **already runs speculative decoding + constrained decoding** for guided generation — the speedup recommended in §3.5 below is provided automatically |
| Streaming API | Yes — `LanguageModelSession.streamResponse(...)` |
| Languages | English, French, German, Italian, Portuguese (BR), Spanish, Japanese, Korean, Chinese (simplified) — covers VoiceInk's primary languages |
| Quality eval | Apple's reported MMLU/MMMLU benchmarks beat Qwen-2.5-3B and rival Qwen-3-4B / Gemma-3-4B in English ([Apple Tech Report 2025](https://arxiv.org/pdf/2507.13575), [Apple ML Research](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)) |
| Risk | Heavy safety filters — has shown false-positives on legitimate prompts. Mitigation: keep the MLX path as fallback when AFM declines a prompt. Outdated training cutoff (~Oct 2023) — fine for cleanup tasks (no fresh-knowledge requirement). |

**Why this matters for VoiceInk:** the enhance step is exactly what AFM was tuned for ("composition and revision of existing text content" per Apple positioning). VoiceInk's current minimum is **macOS 14.4 / 15.0** (per `VoiceInk.xcodeproj/project.pbxproj`). A `@available(macOS 26.0, *) ` capability check inside `AIEnhancementService` lets newer-OS users hit the OS-built-in path while pre-26 users fall back to MLX. This is additive — doesn't disrupt the W10 model lineup at all.

### 3.2 Speculative decoding — `mlx-community/speculative-decoding` Swift package

[GitHub — mlx-community/speculative-decoding](https://github.com/mlx-community/speculative-decoding) provides a **native Swift package** for speculative decoding on top of mlx-swift, exposing:

```swift
import SpeculativeDecoding

let output = try await SpeculativeDecoding.generate(
    prompt: "Cleanup the following dictation: …",
    draftModelId: "mlx-community/Qwen3-0.6B-4bit",
    targetModelId: "mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510"
)
```

| Field | Value |
|---|---|
| API surface | `SpeculativeDecoding.generate(...)`, `.generateStream(...)`, `DraftTargetPair.load(...)`, `SpeculativeGenerator` (low-level) |
| Backbone | mlx-swift (Apple's array framework). Runs side-by-side with mlx-swift-lm. **No fork of mlx-swift-lm needed.** |
| Reported speedup | **2-3× exact-equivalence**. README cites 40 tok/s with 2.4 tokens-per-step, draft Qwen2.5-0.5B + target Qwen2.5-3B on M4 Pro. |
| Output equivalence | Maintains exact target-model output distribution (rejection sampling). Quality is identical to running target alone. |
| Model pairs documented | Qwen2.5 0.5B + 3B; Qwen3 0.6B + 4B is the natural transposition (same vocab + tokenizer family, max compatibility). |
| Memory cost | Both models loaded simultaneously. Draft 335 MB + target 2.26 GB ≈ 2.6 GB activations. Within M-base 32 GB budget. |
| Risk | Smaller package, ~tens of stars; not battle-tested at VoiceInk's user-base scale. Mitigation: feature-flag behind a Settings toggle. Speedup degrades on high entropy prompts (creative writing) but our cleanup task is low-entropy = ideal. |

**Compatibility note:** the package targets mlx-swift directly — does NOT explicitly pin a mlx-swift-lm version. The two coexist as siblings on top of mlx-swift. Worst case, the package needs a minor SPM update if their API drifts; the implementation pattern (manifold-compatible draft + verify) is well-known and stable.

**Apple's own recurrent-drafter research:** Apple's [Recurrent Drafter](https://machinelearning.apple.com/research/recurrent-drafter) paper (MLX team, 2024) shows the same pattern internally — speculative decoding is a first-class lever Apple themselves use for AFM. Adding it for the MLX fallback path is consistent with where the platform is heading.

### 3.3 Qwen3-0.6B-4bit — true ULTRA-fast tier

[`mlx-community/Qwen3-0.6B-4bit`](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit) — 335 MB, Apache 2.0, qwen3 architecture (loadable in mlx-swift-lm 3.31.3), mlx-lm 0.24.0 conversion.

| Field | Value |
|---|---|
| Params | 0.6B total (0.44B non-embedding), 28 layers, 16 Q heads / 8 KV heads (GQA), 32K context |
| License | Apache 2.0 |
| Special note | Supports `enable_thinking=True/False` toggle. **Always pass `False`** for cleanup — `<think>` blocks burn the latency budget on internal monologue (same wrong-tool category as DeepSeek-R1-Distill flagged in the existing W10 doc). |
| IFEval at 0.6B | not published in the Qwen3 family table; family-scaling extrapolation suggests 50-60 (per the [Qwen3 tech report Fig. 6](https://arxiv.org/pdf/2505.09388)) |
| Speed reference | 8-bit Qwen3-0.6B benchmarked at **417.9 tok/s** on Apple Silicon ([llmcheck.net](https://llmcheck.net/benchmarks)); 4-bit will be similar or higher. Family scaling: Qwen3-0.6B is ~2.86× faster than 1.7B per [HN community report](https://news.ycombinator.com/item?id=43856489). |
| Best use | (a) dedicated "ultra-fast" tier when user wants <1s cleanup at any quality cost; (b) **draft model for speculative decoding** with Qwen3-4B target. |
| Risk | Quality at 0.6B is below the 1.7B cleanup-floor in the existing W10 research. Don't make it the default mid-tier. Use as a draft, or as an opt-in fastest tier. |

### 3.4 SmolLM3-3B-4bit-DWQ — best-in-class small open instruction model

[`mlx-community/SmolLM3-3B-4bit-DWQ`](https://huggingface.co/mlx-community/SmolLM3-3B-4bit-DWQ) — ~1.7 GB, Apache 2.0, smollm3 architecture (registered in mlx-swift-lm 3.31.3, per `LLMModelFactory.swift`).

| Field | Value |
|---|---|
| Params | 3B total |
| Architecture | decoder-only transformer with GQA + NoPE (3:1), pretrained on 11.2T tokens |
| License | Apache 2.0 |
| Context | 64K trained, 128K with YARN |
| **IFEval (no-think)** | **76.7%** — best published in 3B class ([HuggingFace SmolLM3 release blog](https://huggingface.co/blog/smollm3)) |
| Tool calling (BFCL) | 92.3% |
| GSM-Plus | 72.8% (no-think) / 83.4% (think) |
| Multilingual | EN/FR/ES/DE/IT/PT native (matches AFM language coverage) |
| Special note | Dual-mode reasoning. Apply `/no_think` system prompt or `enable_thinking=False` for cleanup — same caveat as Qwen3-0.6B. |
| MLX variants | 4-bit, 4-bit-DWQ, 3-bit, 5-bit, 6-bit, 8-bit, bf16 all in mlx-community |
| Risk | IFEval 76.7 is below Qwen3-4B-Instruct-2507's 88.9 — picking SmolLM3 is a small quality regression. Speed gain is uncertain — both are 3B-class dense decoders. |

**Verdict:** SmolLM3 is a credible **alternative** to Qwen3-4B-Instruct-2507, especially if the user prefers the simpler model lineage / fully open training stack. Not a clear win on quality. Not faster materially. Worth flagging if Qwen3-4B-Instruct-2507's verbosity tendency (flagged in W10 doc §1) surfaces in production — SmolLM3 is less verbose by report.

### 3.5 LFM2.5-1.2B-Instruct — best IFEval at <2B but license is a hard NO

[LiquidAI/LFM2.5-1.2B-Instruct](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct) reports **IFEval 86.23** — highest in sub-2B. Architecture: hybrid (Liquid neural arch). Loadable in mlx-swift-lm via `lfm2` registered type. 1.17B params, ~580 MB at 4-bit.

**License:** custom **lfm1.0** — restrictive, **proprietary to Liquid AI**. ([HF model card](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct))

**REJECT** for VoiceInk's permissive-license target. Even though the framework loads it and the IFEval is exceptional, shipping a model under a custom restrictive license in an OSS dictation app introduces redistribution risk. Flagging in case the user wants to evaluate manually for personal use.

### 3.6 Apple OpenELM-270M / 450M / 1.1B — license blocker

Apple's own family — registered as `openelm` in mlx-swift-lm 3.31.3 and explicitly designed for on-device speculative decoding. **License: Apple AMLR (Apple ML Research)** — proprietary, non-permissive ([HF model card](https://huggingface.co/apple/OpenELM-450M-Instruct)). Cannot be redistributed in an OSS app.

OpenLLM Leaderboard average for OpenELM-450M-Instruct is 49.25% — the model is also weaker than Qwen3-1.7B for general instruction-following. **REJECT.**

### 3.7 CoEdIT — purpose-built for editing but double-blocked

Grammarly's [`grammarly/coedit-large`](https://huggingface.co/grammarly/coedit-large) is the canonical "rewriting model" — instruction-tuned T5-large (770M) for text editing, SOTA on text-edit benchmarks at ~60× smaller than competing LLMs ([Grammarly blog](https://www.grammarly.com/blog/engineering/coedit-text-editing/)).

**Two hard blockers:**

1. **License is `cc-by-nc-4.0`** — non-commercial use only ([model card](https://huggingface.co/grammarly/coedit-large), [coedit-xxl README](https://huggingface.co/grammarly/coedit-xxl/raw/main/README.md)). VoiceInk is OSS but used commercially; CC-BY-NC-4.0 cannot ship.
2. **Architecture is T5 / encoder-decoder.** mlx-swift-lm 3.31.3's `LLMTypeRegistry.shared` registers ~50 model types — none are T5/flan-t5/encoder-decoder. Source-of-truth: [LLMModelFactory.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/LLMModelFactory.swift). Confirmed registered list: `mistral, llama, phi, phi3, phimoe, gemma, gemma2, gemma3, gemma3_text, gemma3n, gemma4, gemma4_text, qwen2, qwen3, qwen3_moe, qwen3_next, qwen3_5, qwen3_5_moe, qwen3_5_text, minicpm, starcoder2, cohere, openelm, internlm2, deepseek_v3, granite, granitemoehybrid, mimo, mimo_v2_flash, minimax, glm4, glm4_moe, glm4_moe_lite, acereason, falcon_h1, bitnet, smollm3, ernie4_5, lfm2, baichuan_m1, exaone4, gpt_oss, lille-130m, olmoe, olmo2, olmo3, bailing_moe, lfm2_moe, nanochat, nemotron_h, afmoe, jamba_3b, mistral3, apertus`.

Loading CoEdIT (or any flan-t5 / mt5 / byT5 / PEGASUS variant) requires implementing a T5-Swift module from scratch in mlx-swift-lm — multi-week effort, no upstream patch in flight ([mlx-swift-lm repo](https://github.com/ml-explore/mlx-swift-lm)).

**REJECT.** The "encoder-decoder is faster than decoder-only at the same task" thesis from the spec is **architecturally true** (T5 has half the per-token decode cost; non-autoregressive variants like GECToR are 10× faster at inference) but **practically blocked** for VoiceInk in W11.

### 3.8 GECToR — non-autoregressive grammar tagger; same blocker

[GitHub — grammarly/gector](https://github.com/grammarly/gector), [paper arxiv 2005.12592](https://arxiv.org/abs/2005.12592). Predicts edit tags (KEEP / REPLACE / APPEND) per-token instead of generating sequence — **10× faster than seq2seq** because it parallelizes across the input. Best ensemble: F0.5 66.5 on CoNLL-2014, F0.5 73.6 on BEA-2019.

License: **Apache 2.0** ✅ — much better than CoEdIT.

But: encoder backbone is BERT/RoBERTa with a custom tagging head. mlx-swift-lm does not register `bert` / `roberta` / `gector` types. Same framework blocker as CoEdIT.

**REJECT for primary cleanup path.** Worth a "grammar-only mode" feature flag if VoiceInk later adds a Python sidecar (out of scope for W11).

### 3.9 Harper — rule-based grammar checker, sub-millisecond

[writewithharper.com](https://writewithharper.com) — Apache 2.0, **rule-based** (NOT LLM), Rust crate / WASM, **<10ms** latency, no GPU required.

Capabilities: misspelled words, improper capitalization, punctuation errors. Not a full transcript rewriter (no "make this more formal" capability). For VoiceInk this is a candidate for:
- A "no AI cleanup" / "fast pass" mode that runs Harper on transcripts before ever loading an MLX model
- A pre-filter that catches the cheap stuff (capitalization, terminal punctuation) so the LLM only handles meaningful rewrites

Integration cost: needs a Rust sidecar or a Swift wrapper around `harper-core`. Real but bounded. Out of scope for the W11 model registry refresh; flag for W12 if the user wants a "minimal AI" mode for privacy / speed.

### 3.10 Other candidates examined and dropped

| Candidate | Reject reason |
|---|---|
| flan-t5-small/-base (Apache 2.0) | T5 not in mlx-swift-lm registry; same as CoEdIT framework blocker |
| mT5-small / byT5-small | Same — T5 family |
| PEGASUS-rewriting distillations | Same — not in registry |
| Phi-3-mini-128k variants | IFEval ~70-class, no win over Phi-3.5 / Phi-4-mini |
| Phi-4-mini-instruct (3.8B, MIT) | IFEval 73.8 < Qwen3-4B-Instruct-2507 88.9; not faster materially |
| Granite-3.3-2b-instruct (Apache 2.0) | Already covered in W10 research; usable but undertested |
| TinyLlama-1.1B / StableLM-2 | Already covered in W10; weak vs Qwen3-1.7B |
| Apple AFM when fine-tuned for verbatim/medical (rumored 2026 roadmap) | Speculative — flag only |
| OLMo3 / OLMoE | Apache 2.0, registered as `olmo3` / `olmoe`; community testing volume is much lower than Qwen / SmolLM. No clear win over the curated lineup. |

---

## 4. Speculative-decoding feasibility — definitive answer

**Yes, achievable today on mlx-swift / mlx-swift-lm 3.31.3 — but not via mlx-swift-lm's own API.**

### What works

1. **`mlx-community/speculative-decoding`** — Swift package, native API, drop-in. Tested with Qwen2.5 0.5B + 3B, claims 2-3× exact-equivalence speedup. Direct path: add as SPM dep, wrap in `MLXProvider.enhance(...)`.
2. **`Aryagm/dflash-mlx`** ([repo](https://github.com/Aryagm/dflash-mlx)) — block-diffusion-based speculative decoding for MLX. Reports up to 4.4× speedup ([z-lab/dflash paper](https://github.com/z-lab/dflash)) but the MLX port is newer / less-tested.
3. **`humanrouter/ddtree-mlx`** — tree-based speculative decoding for MLX with custom Metal kernels. ~10-15% faster than DFlash on code, ~1.5× over autoregressive. Most experimental of the three.

### What does NOT work (yet)

mlx-swift-lm 3.31.3 itself **does not expose a speculative-decoding API.** The bundled framework offers single-model `generate(...)` only. Source: [mlx-swift-lm repo + 3.31.3 changelog](https://github.com/ml-explore/mlx-swift-lm/releases) — no `DraftModel` / `SpeculativeGenerator` types in the public API surface. Apple's own [recurrent-drafter research](https://machinelearning.apple.com/research/recurrent-drafter) signals the team's direction but isn't yet in the framework.

### Concrete path for VoiceInk W11

1. Add `mlx-community/speculative-decoding` as SPM dep in `VoiceInk.xcodeproj`.
2. Refactor `MLXProvider.enhance(...)` to:
   - Default: existing single-model path (Qwen3-4B-Instruct-2507 alone) — no behavior change for users without spec-decode toggled on.
   - Opt-in flag `enableSpeculativeDecoding` in Settings → AI Enhancement.
   - When flag enabled: call `SpeculativeDecoding.generateStream(...)` with `Qwen3-0.6B-4bit` as draft and the user-selected model as target.
3. Surface the 2-3× speedup band in the model picker UI subtitle when the flag is on.
4. Behind the flag because: (a) doubles model download (extra 335 MB for the draft), (b) speedup degrades on high-entropy prompts, (c) needs first-party validation on M-base 32 GB.

**This is a strictly additive lever. It does not require dropping any model from the W10 lineup.**

### Caveats from existing literature

- ["mlx-engine #269 — speculative decoding not supported for batched MLX models"](https://github.com/lmstudio-ai/mlx-engine/issues/269) — known-limitation in LM Studio's mlx-engine. Doesn't apply here because VoiceInk runs single-prompt synchronously, not batched.
- ["mlx-lm #1132 — warn when speculative decoding is unlikely to help (MoE)"](https://github.com/ml-explore/mlx-lm/issues/1132) — speculative decoding underperforms on MoE targets. We're targeting dense Qwen3-4B-Instruct-2507. No issue.
- [thc1006/qwen3.6-speculative-decoding-rtx3090 benchmark](https://github.com/thc1006/qwen3.6-speculative-decoding-rtx3090) — found "no variant achieves net speedup on Ampere + A3B MoE." Same MoE caveat. Not our target.

---

## 5. Encoder-decoder vs decoder-only verdict for VoiceInk's hardware target

### The thesis (from the brief)

> Encoder-decoder rewriting models — much smaller and faster than decoder-only LLMs at the same task quality.

### Architectural reality

The thesis is correct **at the cost-per-token level** for a few reasons:
- T5 / encoder-decoder splits cost: encoder runs once over the full input (parallelizable, very fast), decoder is autoregressive but smaller per-step than a same-size decoder-only.
- GECToR-style **sequence taggers are non-autoregressive** — predict all edits in one forward pass = no autoregressive bottleneck.
- 770M T5 (CoEdIT-large) reportedly competitive with much-larger LLMs on text-edit benchmarks ([Grammarly blog](https://www.grammarly.com/blog/engineering/coedit-text-editing/)).

### Why it doesn't pay off for VoiceInk in W11

1. **mlx-swift-lm 3.31.3 doesn't load T5 or GECToR architectures.** Confirmed via [LLMModelFactory.swift](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/LLMModelFactory.swift). Adding T5 support is a multi-month upstream contribution — not a W11 lever.
2. **The Apache-2.0 encoder-decoder option (CoEdIT) is licensed CC-BY-NC-4.0** — non-commercial.
3. **The Apache-2.0 sequence-tagger option (GECToR) is genuinely fast** but only does grammar correction, not stylistic rewriting. VoiceInk's enhance step does both ("make formal", "fix punctuation"). GECToR alone wouldn't replace the LLM step.
4. **Decoder-only at small scale already gets us in the latency band.** Qwen3-0.6B's 335 MB at expected 80-130 tok/s on M-base 32 GB is sub-2-second for typical cleanup outputs. The bottleneck the user is hitting is **not architectural** — it's something else (see R2 enhance pipeline audit).

**Verdict:** the architectural switch would pay off in theory but is blocked by framework + license today. Decoder-only Qwen3-0.6B + speculative decoding gets us comparable speed without the framework rewrite. If the W11 work doesn't close the latency gap, escalate to: (a) T5-Swift implementation (multi-month) or (b) shelling out to llama.cpp / ONNX which DO support T5 (regresses the "single Swift framework" simplicity W6 set up).

---

## 6. Recommendations for the W11 registry refresh

### Primary recommendation — "the W10 model lineup is not the bottleneck"

Per existing W10 research, the curated MLX lineup (Qwen3-1.7B-DWQ + Qwen3-4B-Instruct-2507-DWQ-2510 + Qwen3.5-4B-MLX-4bit) is already in the right speed band on paper. If real-world dictation is still slow, the lever is **not** another model swap. The two productive levers are:

#### Lever A — Apple Foundation Models conditional path (HIGHEST LEVERAGE)

- **What:** add an `@available(macOS 26.0, *)` code path in `AIEnhancementService` that uses `FoundationModels.LanguageModelSession` instead of the MLX provider when the user's OS supports it AND Apple Intelligence is enabled.
- **Why:** OS-bundled, free, sub-150ms first-token with prewarm, no model download, no MLX framework cost, OS daemon already runs speculative + constrained decoding.
- **How big:** medium — new provider class, fall-through logic if the framework declines a prompt (safety filter), Settings toggle "Use Apple Intelligence when available".
- **Risk:** content filters may reject some legitimate dictation. Always keep MLX path as fallback.
- **Hardware floor:** Apple Intelligence-capable Mac (M1+) on macOS 26+. A meaningful subset of VoiceInk's user base in 2026; growing.

#### Lever B — Speculative decoding on the existing MLX lineup

- **What:** add `mlx-community/speculative-decoding` SPM dep, wire `SpeculativeGenerator` into `MLXProvider.enhance(...)`, draft `Qwen3-0.6B-4bit` (335 MB) + target whatever model the user selected.
- **Why:** 2-3× speedup with **exact** output equivalence. Better than swapping models (which regresses quality). Same Apache 2.0 stack.
- **How big:** medium — new SPM dep, enhance(...) refactor, Settings toggle, disk budget +335 MB.
- **Risk:** small package, less battle-tested at scale. Feature-flag behind opt-in.

#### Lever C — Add Qwen3-0.6B-4bit as opt-in ULTRA-FAST tier in the curated registry

- **What:** add `mlx-community/Qwen3-0.6B-4bit` to `MLXModelRegistry.curated` as a fourth tier, labelled "Ultra-fast (lower quality)".
- **Why:** users who explicitly want sub-1-second cleanup at any quality cost have a tier. Same tier's model serves double duty as the spec-decode draft.
- **How big:** small — registry entry + UI labelling.
- **Risk:** quality drop is real at 0.6B; UI must signal that.

### Secondary recommendation — keep the W10 lineup as-is

- `mlx-community/Qwen3-1.7B-4bit-DWQ` — KEEP as fastest tier
- `mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510` — KEEP as default
- `mlx-community/Qwen3.5-4B-MLX-4bit` — KEEP as high-quality
- W10's hard-drop of `gemma-4-26b-a4b-it-4bit` — already shipped, no action

### Optional swaps to consider (not strong recommendations)

- **Add `mlx-community/SmolLM3-3B-4bit-DWQ`** as an Apache 2.0 alternative to Qwen3-4B-Instruct-2507 in case verbosity issues surface in production. IFEval 76.7 (no-think) is below Qwen3-4B but the simpler / fully-open lineage is appealing for a dictation app.
- **Add Harper rule-based pre-filter** in W12+ as a "no AI" / "fast pass" mode — orthogonal to the model registry.

### What NOT to do

- **Don't** chase encoder-decoder rewriting models (CoEdIT, flan-t5, GECToR) for W11 — framework blocker.
- **Don't** swap to OpenELM or LFM2.5 — license blockers.
- **Don't** swap to Phi-4-mini — IFEval is below Qwen3-4B-Instruct-2507.
- **Don't** assume the bottleneck is the model. Run R2's enhance pipeline audit first; if the audit reveals startup latency / tokenizer cost / KV-cache thrash dominating, model swaps don't help.

---

## 7. Open follow-ups + risks

1. **macOS 26 deployment fence.** If VoiceInk supports macOS 14.4+, the AFM path is opt-in for newer-OS users only. Need product decision: bump deployment target, or ship dual-path.
2. **Spec-decode SPM dep stability.** The `mlx-community/speculative-decoding` package is small. Worth pinning to a known-good revision and tracking its API.
3. **Qwen3-0.6B IFEval not published.** The "ultra-fast tier" recommendation rests on family-scaling extrapolation. Pre-merge test on M-base 32 GB with the existing prompt suite is mandatory.
4. **Apple AFM safety filters** may reject some dictation content (medical, legal verbatim). Always keep MLX path as fallback when AFM declines.
5. **DWQ variant churn.** SmolLM3-3B-4bit-DWQ has 1 download — newer than 4-bit-plain (3.29k downloads). DWQ variants of Qwen3 have similar small download counts. Standard `-4bit` variants are the safer fallback if DWQ surfaces issues.
6. **Speculative-decoding draft selection.** Qwen3-0.6B + Qwen3-4B-Instruct-2507 share the qwen tokenizer family — most compatible. If the user later swaps target to SmolLM3, draft-target tokenizer mismatch will break spec-decode. Doc the constraint in Settings.

---

## 8. Sources (deduplicated)

### Apple Foundation Models framework
- [Apple Developer — Foundation Models](https://developer.apple.com/documentation/FoundationModels)
- [Apple Developer — Foundation Models Acceptable Use](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework/)
- [WWDC25 — Meet the Foundation Models framework (286)](https://developer.apple.com/videos/play/wwdc2025/286/)
- [WWDC25 — Deep dive into the Foundation Models framework (301)](https://developer.apple.com/videos/play/wwdc2025/301/)
- [Apple ML Research — 2025 updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [Apple ML Research — Tech Report 2025 (arxiv 2507.13575)](https://arxiv.org/pdf/2507.13575)
- [Apple ML Research — Recurrent Drafter](https://machinelearning.apple.com/research/recurrent-drafter)
- [Apple Newsroom — Foundation Models framework launch (Sept 2025)](https://www.apple.com/newsroom/2025/09/apples-foundation-models-framework-unlocks-new-intelligent-app-experiences/)
- [createwithswift.com — Exploring the Foundation Models framework](https://www.createwithswift.com/exploring-the-foundation-models-framework/)
- [natashatherobot.com — Apple FoundationModels limitations & capabilities](https://www.natashatherobot.com/p/apple-foundation-models)
- [AzamSharp guide to Foundation Models (2025-06-18)](https://azamsharp.com/2025/06/18/the-ultimate-guide-to-the-foundation-models-framework.html)

### Speculative decoding on MLX / mlx-swift
- [GitHub — mlx-community/speculative-decoding](https://github.com/mlx-community/speculative-decoding)
- [GitHub — Aryagm/dflash-mlx](https://github.com/Aryagm/dflash-mlx)
- [GitHub — bstnxbt/dflash-mlx (Lossless DFlash port)](https://github.com/bstnxbt/dflash-mlx)
- [GitHub — humanrouter/ddtree-mlx (tree-based)](https://github.com/humanrouter/ddtree-mlx)
- [GitHub — z-lab/dflash (block-diffusion paper)](https://github.com/z-lab/dflash)
- [GitHub — SharpAI/SwiftLM (dual-model spec-decode infra)](https://github.com/SharpAI/SwiftLM)
- [GitHub issue — mlx-engine #269 (batched-spec-decode unsupported)](https://github.com/lmstudio-ai/mlx-engine/issues/269)
- [GitHub issue — mlx-lm #1132 (MoE warning)](https://github.com/ml-explore/mlx-lm/issues/1132)
- [LM Studio Blog — Speculative Decoding 0.3.10](https://lmstudio.ai/blog/lmstudio-v0.3.10)
- [thc1006/qwen3.6-speculative-decoding-rtx3090 (negative result on MoE)](https://github.com/thc1006/qwen3.6-speculative-decoding-rtx3090)
- [kaitchup — Qwen3.5 GGUF Evals + SSD](https://kaitchup.substack.com/p/more-qwen35-gguf-evals-and-speculative)

### MLX-swift-lm framework + registered model types
- [GitHub — ml-explore/mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm)
- [LLMModelFactory.swift (registered model_type list)](https://github.com/ml-explore/mlx-swift-lm/blob/main/Libraries/MLXLLM/LLMModelFactory.swift)
- [GitHub — ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift)
- [GitHub — ml-explore/mlx-lm](https://github.com/ml-explore/mlx-lm)
- [Swift.org — On-device ML research with MLX and Swift](https://www.swift.org/blog/mlx-swift/)

### Models — primary cards
- [HF Qwen/Qwen3-0.6B](https://huggingface.co/Qwen/Qwen3-0.6B) — 0.6B, Apache 2.0, qwen3
- [HF mlx-community/Qwen3-0.6B-4bit](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit) — 335 MB, mlx-lm 0.24.0
- [HF mlx-community/Qwen3-1.7B-4bit-DWQ](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit-DWQ) — current W10 fastest tier
- [HF mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit-DWQ-2510) — current W10 default
- [HF HuggingFaceTB/SmolLM3-3B](https://huggingface.co/HuggingFaceTB/SmolLM3-3B) — 3B, Apache 2.0, IFEval 76.7
- [HuggingFace blog — SmolLM3 release](https://huggingface.co/blog/smollm3)
- [HF mlx-community/SmolLM3-3B-4bit-DWQ](https://huggingface.co/mlx-community/SmolLM3-3B-4bit-DWQ) — 1.73 GB
- [HF collection — mlx-community/SmolLM3 variants](https://huggingface.co/collections/mlx-community/smollm3)
- [HF apple/OpenELM-450M-Instruct](https://huggingface.co/apple/OpenELM-450M-Instruct) — Apple AMLR (REJECT)
- [HF LiquidAI/LFM2.5-1.2B-Instruct](https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct) — IFEval 86.23, lfm1.0 license (REJECT)
- [HF microsoft/Phi-4-mini-instruct](https://huggingface.co/microsoft/Phi-4-mini-instruct) — MIT, IFEval 73.8
- [HF mlx-community/lille-130m-instruct-4bit](https://huggingface.co/mlx-community/lille-130m-instruct-4bit) — possible draft
- [HF Nikity/lille-130m-instruct](https://huggingface.co/Nikity/lille-130m-instruct) — base model card
- [GitHub — Nikityyy/lille](https://github.com/Nikityyy/lille)

### Encoder-decoder / sequence-tagger candidates (rejected)
- [HF grammarly/coedit-large](https://huggingface.co/grammarly/coedit-large) — CC-BY-NC-4.0
- [HF grammarly/coedit-xxl](https://huggingface.co/grammarly/coedit-xxl)
- [HF grammarly/coedit-xl-composite](https://huggingface.co/grammarly/coedit-xl-composite)
- [HF collection — grammarly/coedit](https://huggingface.co/collections/grammarly/coedit)
- [Grammarly blog — CoEdIT](https://www.grammarly.com/blog/engineering/coedit-text-editing/)
- [GitHub — vipulraheja/coedit](https://github.com/vipulraheja/coedit)
- [GitHub — grammarly/gector](https://github.com/grammarly/gector)
- [arxiv 2005.12592 — GECToR](https://arxiv.org/abs/2005.12592)
- [Grammarly blog — Experimenting with GECToR](https://www.grammarly.com/blog/engineering/experimenting-with-gector/)
- [arxiv 2410.16473 — Multi-head sequence tagging GEC](https://arxiv.org/html/2410.16473v1)
- [HF google/flan-t5-small](https://huggingface.co/google/flan-t5-small)
- [HF google/flan-t5-base](https://huggingface.co/google/flan-t5-base)

### Rule-based / non-LLM grammar tools
- [Harper — writewithharper.com](https://writewithharper.com/) — Apache 2.0
- [GitHub — PrithivirajDamodaran/Gramformer](https://github.com/PrithivirajDamodaran/Gramformer)
- [GitHub — bedapudi6788/deepcorrect](https://github.com/bedapudi6788/deepcorrect)
- [GitHub — xashru/punctuation-restoration](https://github.com/xashru/punctuation-restoration)
- [GitHub — Chunngai/gec-papers](https://github.com/Chunngai/gec-papers)

### Apple Silicon performance + benchmarks
- [llmcheck.net benchmarks](https://llmcheck.net/benchmarks)
- [siliconscore.com — Qwen 3 4B on Apple Silicon](https://siliconscore.com/models/qwen-3-4b/)
- [HN — Running Qwen3 on macbook MLX](https://news.ycombinator.com/item?id=43856489)
- [insiderllm.com — Best Local LLMs Mac 2026](https://insiderllm.com/guides/best-local-llms-mac-2026/)
- [insiderllm.com — Best Models Under 3B](https://insiderllm.com/guides/best-models-under-3b-parameters/)
- [Will It Run AI — Qwen 3.5 on Apple Silicon MLX (2026)](https://willitrunai.com/blog/qwen-3-5-mlx-apple-silicon-guide)
- [Apple ML Research — Exploring LLMs with MLX and the Neural Accelerators in the M5 GPU](https://machinelearning.apple.com/research/exploring-llms-mlx-m5)
- [arxiv 2510.18921 — Benchmarking On-Device ML on Apple Silicon with MLX](https://arxiv.org/html/2510.18921v1)

### Quant + technical reports
- [arxiv 2505.09388 — Qwen3 technical report](https://arxiv.org/pdf/2505.09388)
- [arxiv 2505.02214 — Qwen3 quant empirical study](https://arxiv.org/html/2505.02214v1)
- [arxiv 2502.02737 — SmolLM2 paper](https://arxiv.org/html/2502.02737v1)
- [arxiv 2404.14619 — OpenELM](https://arxiv.org/html/2404.14619v2)
- [arxiv 2503.01743 — Phi-4-Mini Technical Report](https://arxiv.org/html/2503.01743v1)
- [arxiv 2511.23404 — LFM2 Technical Report](https://arxiv.org/abs/2511.23404)
- [smcleod.net — Measuring Model Quantisation Quality with KL Divergence](https://smcleod.net/2026/04/measuring-model-quantisation-quality-with-kl-divergence/)

### Cross-references to existing project research
- [W10 rewriting models research](./2026-04-29-mlx-rewriting-models.md)
- W6 plan: `docs/superpowers/plans/W6-mlx-quality-and-segregation.md` (PLE-quant warning; M-base extrapolation caveat)
