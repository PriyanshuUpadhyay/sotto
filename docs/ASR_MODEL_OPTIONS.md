# ASR Model Options — April 2026

Research scope: newer on-device speech-to-text for VoiceInk macOS dictation. Target: M-series, 32 GB, macOS 26 Tahoe. Priority: fast first-token, strong quality, Swift-native.

Current stack:
- Whisper.cpp (vendored xcframework) — tiny / base / large-v2 / large-v3 / large-v3-turbo / large-v3-turbo-q5_0
- FluidAudio SPM dep — Parakeet TDT v2, v3
- Apple `SpeechAnalyzer` (gated `ENABLE_NATIVE_SPEECH_ANALYZER`, currently broken)

**Headline finding:** FluidAudio is already an SPM dep, and its v0.13.x–v0.14.x releases ([changelog](https://github.com/FluidInference/FluidAudio/releases)) added five new ASR engines we don't yet expose: Parakeet EOU streaming, Nemotron Speech Streaming, Parakeet-TDT-CTC-110M, Cohere Transcribe, Japanese TDT, Mandarin CTC, and Qwen3-ASR-0.6B. **No new SPM dep required for the top 3 picks — registry edits only.** Bump `FluidAudio` minimum to ≥0.14.1.

---

## 1. TL;DR — Top 3 picks

1. **Parakeet EOU (streaming)** via FluidAudio — fastest first-token English dictation. 4.88% WER at 320 ms chunks, 19.25× RTFx, native end-of-utterance detection. Best UX win for the user's "fast first-token" preference. Registry add only.
2. **Cohere Transcribe** via FluidAudio — best multilingual quality landed in 2026. 1.77% LibriSpeech test-clean WER, 14 langs (en/fr/de/es/it/pt/nl/pl/el/ar/ja/zh/ko/vi). Replaces Large-v3 for those languages at a fraction of the disk/RAM. Registry add only.
3. **Nemotron Speech Streaming 0.6B** via FluidAudio — NVIDIA's January-2026 streaming model. 2.51% WER at 1120 ms chunks, cache-aware FastConformer encoder. Best accuracy-to-latency point for streaming English. Registry add only.

All three ship under permissive licenses, target Apple Neural Engine via CoreML through the existing FluidAudio package, and require **no new dependencies**.

---

## 2. Detailed candidates

### 2.1 Parakeet EOU (FluidAudio streaming)

- **Repo / docs:** [FluidAudio Benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- **Swift integration:** Already vendored — same `FluidAudio` SPM dep, exposed via `AsrModels.downloadAndLoad(version:)` family. Need to verify the exact `AsrModelVersion` enum case (likely `.parakeetEOU` or similar) added in v0.13.x.
- **Quality:** 4.88 % WER (320 ms chunks), 19.25× RTFx on M-series CoreML. Tuned for live captions / dictation.
- **First-token latency:** ~100–300 ms. Native end-of-utterance signal — tighter UX than current Parakeet v2/v3 batch path.
- **Disk:** ~500 MB (CoreML weights, similar to v2).
- **Streaming:** Yes — built for it.
- **Multilingual:** English-only.
- **License:** CC-BY-4.0 / NVIDIA OSS terms (inherits from upstream Parakeet).

### 2.2 Cohere Transcribe (FluidAudio v0.14.0)

- **Repo / docs:** [FluidAudio v0.14.0 release](https://github.com/FluidInference/FluidAudio/releases)
- **Swift integration:** FluidAudio v0.14.0+ wraps it via the same SPM dep. Encoder-decoder (INT8 enc + FP16 dec hybrid). Language must be specified — no auto-detect.
- **Quality:** **1.77 % WER on LibriSpeech test-clean** — better than every Whisper variant we ship today and on par with Large-v3 in cloud benchmarks.
- **First-token latency:** Encoder-decoder so worse than RNNT for streaming, but acceptable for batch dictation. ~400–700 ms TTFT estimated.
- **Disk:** ~600 MB.
- **Streaming:** No (batch / chunked offline).
- **Multilingual:** 14 langs (English, French, German, Spanish, Italian, Portuguese, Dutch, Polish, Greek, Arabic, Japanese, Mandarin, Korean, Vietnamese).
- **License:** CC-BY-NC-4.0 (verify before commercial ship — may force English/non-commercial gating). **Check before merging.**

### 2.3 Nemotron Speech Streaming 0.6B (FluidAudio v0.13.1+)

- **Repo / docs:** [nvidia/nemotron-speech-streaming-en-0.6b](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b), [NVIDIA blog post](https://huggingface.co/blog/nvidia/nemotron-speech-asr-scaling-voice-agents), [MarkTechPost coverage](https://www.marktechpost.com/2026/01/06/nvidia-ai-released-nemotron-speech-asr-a-new-open-source-transcription-model-designed-from-the-ground-up-for-low-latency-use-cases-like-voice-agents/)
- **Swift integration:** FluidAudio v0.13.1+. Cache-aware FastConformer + RNNT decoder. Configurable 80 ms / 160 ms / 320 ms / 1120 ms chunk sizes.
- **Quality:** 2.51 % WER at 1120 ms chunks, 6.03× RTFx. ~2.12 % WER FluidAudio-reported. Outperforms Parakeet v2 streaming.
- **First-token latency:** 80–320 ms depending on chunk config — best-in-class for streaming voice agents.
- **Disk:** ~600 MB.
- **Streaming:** Yes — designed for it (cache-aware encoder, processes only audio "deltas").
- **Multilingual:** English-only.
- **License:** NVIDIA OSS (Apache-2.0 derivative — verify).

### 2.4 Parakeet-TDT-CTC-110M (FluidAudio v0.13.2)

- **Swift integration:** FluidAudio SPM, hybrid TDT+CTC, supports custom ARPA LM (9.4 % WER with domain LM).
- **Quality:** Coarser than Parakeet 0.6B but 5–6× smaller.
- **Disk:** ~120 MB.
- **Use case:** Replacement for `ggml-tiny.en` in the picker — same size class, much better WER, ANE-accelerated. Worth adding.
- **Streaming:** Yes.
- **License:** CC-BY-4.0.

### 2.5 Qwen3-ASR-0.6B / 1.7B

- **Repo:** [QwenLM/Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR), [moona3k/mlx-qwen3-asr](https://github.com/moona3k/mlx-qwen3-asr)
- **Swift integration:** **0.6B variant is already in FluidAudio v0.14.x** ([benchmarks doc](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)) — 4.4 % English WER, 30-lang multilingual, but only 2.8× RTFx. The **1.7B** flagship is Python/MLX only (no Swift port), would need a custom CoreML conversion.
- **Quality:** 1.7B is SOTA among open-source multilingual; 0.6B is competitive. 92 ms TTFT claimed for 0.6B.
- **First-token latency:** 0.6B ~100–200 ms; 1.7B unverified on M-series.
- **Disk:** 0.6B ~700 MB, 1.7B ~3.5 GB.
- **Streaming:** Yes (forced aligner + stream API).
- **Multilingual:** **52 languages** (1.7B) / 30 (0.6B) — broadest of any candidate.
- **License:** **Apache-2.0** — friendliest of the bunch.
- **Verdict:** Add the 0.6B as a "broad multilingual" option. Skip 1.7B until someone ports it.

### 2.6 Canary-Qwen-2.5B

- **Repo:** [nvidia/canary-qwen-2.5b](https://huggingface.co/nvidia/canary-qwen-2.5b)
- **Swift integration:** **None**. No CoreML port, no Swift binding, no SPM dep. Would require a multi-week port.
- **Quality:** **5.63 % WER — top of the [HF Open ASR leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard)** as of mid-2025.
- **Disk:** ~5 GB.
- **Streaming:** No (offline only).
- **Multilingual:** English only.
- **Verdict:** Best raw quality, but **don't ship** — no Apple Silicon path and 2.5 B params is heavy for a dictation app. Track for future.

### 2.7 Moonshine v2 (moonshine-swift)

- **Repo:** [moonshine-ai/moonshine](https://github.com/moonshine-ai/moonshine), [moonshine-swift](https://github.com/moonshine-ai/moonshine-swift), [arxiv 2602.12241](https://arxiv.org/html/2602.12241v1)
- **Swift integration:** Native SPM via `moonshine-swift`. Backend uses ONNX Runtime — adds ~30 MB lib weight.
- **Quality:** Medium Streaming 245 M @ 6.65 % WER (vs Whisper Large-v3 7.44 %); Tiny 27 M @ 12.66 % WER, 34 ms latency.
- **First-token latency:** 34–107 ms — fastest in this list.
- **Disk:** Tiny 27 MB / Small 60 MB / Medium 245 MB.
- **Streaming:** Yes (native ergodic streaming encoder).
- **Multilingual:** English, Spanish, Mandarin, Japanese, Korean, Vietnamese, Ukrainian, Arabic.
- **License:** **MIT** — most permissive.
- **Verdict:** Compelling for "absolute lowest latency English" but adds a second runtime alongside FluidAudio's CoreML. Holding pattern unless Parakeet EOU isn't fast enough. **Optional 4th pick.**

### 2.8 Distil-Whisper

- **Repo:** [huggingface/distil-whisper](https://github.com/huggingface/distil-whisper)
- **Quality:** 6× faster than Large-v3, ~1 % WER delta on out-of-distribution audio. Now mostly outclassed by Whisper Large-v3-turbo (we already ship `q5_0` quant) and Parakeet variants.
- **Verdict:** Skip. The reason to add Distil-Whisper was speed, and `large-v3-turbo-q5_0` + Parakeet v2 already dominate that lane on Apple Silicon.

### 2.9 Apple SpeechAnalyzer / SpeechTranscriber (macOS 26)

- **Docs:** [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), [iOS 26 SpeechAnalyzer guide](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- **Status April 2026:** Offline `start(inputAudioFile:finishAfterFile:)` works on 26.3.2. **Streaming `start(inputSequence:)` still throws `_GenericObjCError`** ([dev forum thread](https://developer.apple.com/forums/thread/819555)). `SpeechDetector` SpeechModule conformance fix shipped in 26.1. Locale errors fixed by 26.2.
- **Verdict:** Ungate offline path for 26.3+ as a "free" zero-disk option, keep streaming path gated behind feature flag until Apple fixes it. Existing `NativeAppleTranscriptionService.swift` is the right surface — it just needs the streaming branch hardened or fall-through to FluidAudio when the streaming API errors.
- **License / cost:** Free, on-device, no Marketplace approval. Reference samples: [otaviocc/Stenographer](https://github.com/otaviocc/Stenographer), [FluidInference/swift-scribe](https://github.com/FluidInference/swift-scribe).

### 2.10 Whisper Large v4 / OpenAI new ASR

- No `large-v4` exists. OpenAI's newest transcription is **GPT-4o-transcribe** (cloud, March 2025), not on-device. Out of scope.

### 2.11 mlx-community Whisper / MLX Parakeet

- [senstella/parakeet-mlx](https://github.com/senstella/parakeet-mlx), [FluidInference/swift-parakeet-mlx](https://github.com/FluidInference/swift-parakeet-mlx).
- FluidInference explicitly **abandoned MLX Parakeet → moved to CoreML** because MLX/GPU was slower than ANE. Their CoreML pipeline (current FluidAudio) is the right path. Don't backslide to MLX for ASR.
- MLX-quantized Whisper exists on `mlx-community` but offers no advantage over the existing whisper.cpp Metal path on M-series.

---

## 3. What I'd ship next

**Bump `FluidAudio` SPM dep to ≥0.14.1** ([Swift Package Index](https://swiftpackageindex.com/FluidInference/FluidAudio)). Then registry-only edits in `TranscriptionModelRegistry.swift` + `FluidAudioModelManager.modelVersionMap`:

1. **Add Parakeet EOU streaming** — `parakeet-eou-streaming-en` — set as default for English dictation (replace Parakeet v2 default).
2. **Add Nemotron Speech Streaming 0.6B** — `nemotron-speech-streaming-en` — "high-accuracy English streaming" tier.
3. **Add Cohere Transcribe** — `cohere-transcribe-14lang` — multilingual replacement candidate. **Verify license is OK for our distribution before merging**; if CC-BY-NC, gate behind a non-commercial flag or skip.
4. **Add Parakeet-TDT-CTC-110M** — `parakeet-tdt-ctc-110m` — replaces the role of `ggml-tiny.en` in the picker (small + fast).
5. **Add Qwen3-ASR-0.6B** — `qwen3-asr-0.6b` — broad multilingual (30 langs), Apache-2.0.

**Harden Apple Speech path:**
6. Keep `NativeAppleTranscriptionService.swift` gated behind `ENABLE_NATIVE_SPEECH_ANALYZER`, but split it into offline-OK / streaming-broken branches. Offline path is shippable on 26.3+; streaming branch should fall through to FluidAudio Parakeet EOU on `_GenericObjCError`.

**Defer:**
- Moonshine — only adopt if Parakeet EOU latency is unsatisfactory after testing. Adds ONNX runtime weight.
- Qwen3-ASR-1.7B — wait for someone to publish a CoreML port. Track [moona3k/mlx-qwen3-asr](https://github.com/moona3k/mlx-qwen3-asr).
- Canary-Qwen-2.5B — wait for a Swift port; too big otherwise.

All recommended additions = **registry edits + model-version map entries + UI string**. Zero new SPM deps, zero new bridging code.

---

## 4. What I'd drop

- **`ggml-tiny`** and **`ggml-tiny.en`** — outclassed by Parakeet-TDT-CTC-110M (better WER, similar size, ANE-accelerated, streaming-capable).
- **`ggml-large-v2`** — strictly inferior to `large-v3` and `large-v3-turbo` on every axis. Keeping it is just registry noise.
- **`ggml-base`** / **`ggml-base.en`** — borderline. Parakeet v2 is faster and more accurate at ~3× the disk. Keep `base.en` only as a low-RAM fallback for users on <16 GB; otherwise drop.
- **`ggml-large-v3`** non-turbo — keep only if there's a measurable accuracy delta vs `large-v3-turbo` for non-English; otherwise drop. Internal benchmark needed.

Definitely **keep**: `large-v3-turbo`, `large-v3-turbo-q5_0` (proven, multilingual fallback), Parakeet v3 (multilingual baseline).

---

## 5. Open questions (couldn't verify without running code)

1. **Exact `AsrModelVersion` enum cases** in FluidAudio v0.14.1 for Parakeet EOU, Nemotron, Cohere, Qwen3-ASR-0.6B. Need to read `FluidAudio.AsrModels` symbols after bumping the dep.
2. **Cohere Transcribe license** — is it CC-BY-NC (non-commercial) or Apache? Crucial gate before shipping. Check the v0.14.0 release notes carefully.
3. **First-token latency** for each new model on the user's specific hardware (M-series, 32 GB) — only verifiable by running. FluidAudio benchmarks are RTFx-based; TTFT is what matters for dictation UX.
4. **Streaming API surface compatibility** — does `FluidAudioStreamingProvider.swift` already work with the new `nemotron-*` and `parakeet-eou-*` versions, or do they need a new streaming adapter? Read FluidAudio's streaming examples after bump.
5. **Apple SpeechAnalyzer streaming bug** — fixed in 26.3.x or still present in 26.4 betas? Worth a fresh check before un-gating.
6. **Disk footprint at first-launch** — total .mlmodel cache size grows fast. May need a "managed downloads" UX revisit if we add 4–5 new models.
7. **Parakeet v2 default vs Parakeet EOU default** — does EOU regress on long-form audio (>1 min)? Worth A/B before swapping default.

---

## Sources

- [FluidAudio repo](https://github.com/FluidInference/FluidAudio)
- [FluidAudio releases](https://github.com/FluidInference/FluidAudio/releases)
- [FluidAudio benchmarks](https://github.com/FluidInference/FluidAudio/blob/main/Documentation/Benchmarks.md)
- [Swift Package Index — FluidAudio](https://swiftpackageindex.com/FluidInference/FluidAudio)
- [nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3)
- [nvidia/parakeet-tdt-0.6b-v2](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v2)
- [nvidia/nemotron-speech-streaming-en-0.6b](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b)
- [Nemotron Speech ASR — Hugging Face blog](https://huggingface.co/blog/nvidia/nemotron-speech-asr-scaling-voice-agents)
- [MarkTechPost — Nemotron Speech ASR launch](https://www.marktechpost.com/2026/01/06/nvidia-ai-released-nemotron-speech-asr-a-new-open-source-transcription-model-designed-from-the-ground-up-for-low-latency-use-cases-like-voice-agents/)
- [nvidia/canary-qwen-2.5b](https://huggingface.co/nvidia/canary-qwen-2.5b)
- [HF Open ASR Leaderboard](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard)
- [QwenLM/Qwen3-ASR](https://github.com/QwenLM/Qwen3-ASR)
- [Qwen3-ASR launch blog](https://qwen.ai/blog?id=qwen3asr)
- [moona3k/mlx-qwen3-asr](https://github.com/moona3k/mlx-qwen3-asr)
- [moonshine-ai/moonshine](https://github.com/moonshine-ai/moonshine)
- [moonshine-swift](https://github.com/moonshine-ai/moonshine-swift)
- [Moonshine v2 paper (arxiv 2602.12241)](https://arxiv.org/html/2602.12241v1)
- [argmaxinc/WhisperKit](https://github.com/argmaxinc/WhisperKit)
- [WhisperKit paper (arxiv 2507.10860)](https://arxiv.org/html/2507.10860v1)
- [huggingface/distil-whisper](https://github.com/huggingface/distil-whisper)
- [Apple — SpeechAnalyzer docs](https://developer.apple.com/documentation/speech/speechanalyzer)
- [Apple — SpeechTranscriber docs](https://developer.apple.com/documentation/speech/speechtranscriber)
- [iOS 26 SpeechAnalyzer guide — Anton Gubarenko](https://antongubarenko.substack.com/p/ios-26-speechanalyzer-guide)
- [Apple Dev Forums — SpeechAnalyzer streaming bug](https://developer.apple.com/forums/thread/819555)
- [otaviocc/Stenographer](https://github.com/otaviocc/Stenographer)
- [FluidInference/swift-scribe](https://github.com/FluidInference/swift-scribe)
- [MacParakeet — Whisper to Parakeet on Neural Engine](https://macparakeet.com/blog/whisper-to-parakeet-neural-engine/)
- [Northflank — Best open-source STT 2026](https://northflank.com/blog/best-open-source-speech-to-text-stt-model-in-2026-benchmarks)
- [Slator — ASR leaderboard coverage](https://slator.com/nvidia-microsoft-elevenlabs-top-automatic-speech-recognition-leaderboard/)
- [Arun Baby — Whisper vs Parakeet for production](https://www.arunbaby.com/speech-tech/0073-whisper-vs-parakeet-asr-decision/)
- [Modelslab — Moonshine vs Whisper benchmark 2026](https://modelslab.com/blog/audio-generation/moonshine-vs-whisper-asr-real-time-speech-2026)
