---
status: accepted
date: 2026-09-16
deciders: [PriyanshuUpadhyay]
related: [0001, 0003]
informed-by: [eval/results/bench/report.md, ~/.claude/reports/2026-09-15-dictation-cleanup-models-web.md]
---
# 0002. Curate s1-mini and SpeakoFlow-Mini as the two downloadable GGUF models

## Context and Problem Statement
The GGUF provider needs a short list of models a user can download. We benchmarked fifteen
candidates under 1B parameters against Sotto's real recordings and synthetic sets, scoring warm
latency, exact match, agreement with AFM, and content loss.

## Considered Options
- superwhisper/s1-mini 0.6B q4 (461 MB): 0.15 s warm, 67% synthetic exact match, 1.0% content loss.
- SpeakoFlow-Mini 0.8B Q8 (795 MB): 0.33 s warm, best agreement with AFM (dist 0.049), 3% loss.
- Handy editor LFM2.5 350M (218 MB): 0.11 s warm, 12% content loss.
- FlowScribe Qwen2.5 0.5B (379 MB): 0.16 s warm, 18% content loss.
- Token taggers (Typurr 82M, fdt 11M): no hallucination but no rewrite; Typurr's labels are undocumented, fdt is non-commercial.
- Gemma 3n / Gemma 4 E2B: slower than AFM and 2.4 GB.

## Decision Outcome
Chosen: s1-mini as the default and SpeakoFlow-Mini as the second option, because they are the
only two purpose-built rewriters that lose under 3% of content, and s1-mini is both the fastest
and the closest to the reference answers.

### Consequences
- Good: enhancement drops from 1.3 s (AFM) to about 0.2 s with s1-mini.
- Bad: every quality number comes from our own bench and the authors' model cards; there is no
  independent evaluation, and s1-mini's license is Apache 2.0 with a naming clause that must be
  kept in the About text.
