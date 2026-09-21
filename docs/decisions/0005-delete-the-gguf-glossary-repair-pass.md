---
status: accepted
date: 2026-09-21
deciders: [PriyanshuUpadhyay]
related: [0001, 0002, 0003]
---
# 0005. Delete the GGUF glossary-repair pass

In the context of the opt-in grammar-constrained glossary repair added on 2026-09-16 (commit
f6a0d35), facing six days of production telemetry in which the pass ran 58 times, emitted zero
useful corrections, twice replaced a whole utterance with a glossary term ("Check its validity."
became "Anthropic"), and added 1.07s p50 in front of the review panel, we chose to delete the pass
and its implementation outright rather than move it off the latency path, add a timeout, or harden
`GlossaryCorrection.apply`, and neglected the possibility that a labelled corpus might still show
value, to achieve a pipeline that cannot silently destroy a dictation, accepting that proper-noun
mishears the phonetic stage misses now stay unrepaired.

## Why the alternatives were rejected

Moving the call after the preview fixes only the delay, and the destruction is what matters. A
timeout catches nothing, because both harmful calls finished in 0.583s and 0.503s. Hardening the
`apply` gates is new logic for a feature with zero demonstrated benefit in 58 production runs; the
hole is structural, since a `find` span of up to three words makes a three-word sentence a legal
target in full and no gate compares `find` with `replace`.

## Cost

Glossary terms that the phonetic stage cannot reach are no longer corrected at all. The per-word
confidence tracing from the same commit is unaffected and stays. Commit f6a0d35 remains in history
if the pass is ever re-tested offline; re-enabling it needs a labelled set showing real fixes and
no whole-span replacements, measured with the call placed after the preview appears.

Evidence, the unanimous three-model council verdict, and the full list of rejected changes are in
`docs/council/2026-09-21-pipeline-robustness-telemetry.md`.
