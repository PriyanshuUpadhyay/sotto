---
status: accepted
date: 2026-09-16
deciders: [PriyanshuUpadhyay]
related: [0002, 0003]
informed-by: [~/Library/Application Support/com.sotto.Sotto/enhancement-timings.csv, eval/results/bench/report.md]
---
# 0001. Replace the MLX Gemma enhancement path with a llama.cpp GGUF provider

## Context and Problem Statement
The enhancement step turns raw dictation into clean text. Apple Foundation Models (AFM) does this
in about 1.3 s per dictation. An uncommitted MLX path ran Gemma 4 E2B on device, but the timing
log showed 2-6 s per dictation and frequent 7.5 s timeouts. Causes: a 4.9k-char system prompt
prefilled on every call with no KV reuse, a 600 s idle eviction that made most dictations pay a
6-13 s cold load against a 7.5 s timeout, and a Debug (-Onone) build of mlx-swift. The weights
were 2.4 GB. We needed a small on-device rewriter that loads in about a second.

## Considered Options
- Keep MLX and fix it (KV-cache prompt reuse, longer eviction window, Release build).
- Replace MLX with llama.cpp vendored as an xcframework, like whisper.cpp, and run GGUF models.
- Keep MLX and add llama.cpp beside it.
- Drop local models and keep AFM only.

## Decision Outcome
Chosen: replace MLX with llama.cpp GGUF, because the best fixed Gemma path would still not beat
AFM, the candidate models that do beat it (see 0002) ship as GGUF, and the app already builds
and embeds a ggml xcframework the same way.

### Consequences
- Good: one vendoring pattern (Makefile `llama` target mirrors `whisper`), no Swift packages,
  models of 0.5-0.8 GB that load in under a second.
- Bad: whisper.xcframework and llama.xcframework each bundle ggml headers, and Clang accepts them
  only when the headers are byte-identical; a `make whisper` rebuild can reintroduce type
  redefinition errors until both are rebuilt from the same upstream day.
