---
status: accepted
date: 2026-09-21
deciders: [PriyanshuUpadhyay]
related: [0003, 0005]
---
# 0006. An empty enhancement output is a failure, not a result

In the context of the enhancement repair guard, facing two production calls that returned an empty
string with `outcome=success` and had it pasted over the dictation, we chose to treat an empty
output for non-empty input as a failure in `EnhancementSanityCheck.detect`, and to throw it in the
GGUF provider as well, rather than guard only at the pipeline's assignment site, accepting one
extra retry on the rare run where a model legitimately has nothing to say.

The guard in `detect` covers every provider, including the identical hole in `AFMProvider`, and
routes the run into the existing hardened retry and then `deterministicCleanup`, so the user
receives cleaned raw text instead of nothing. The separate provider throw exists so the timings CSV
stops recording a lost dictation as a success. ADR 0003 already records that s1-mini returns empty
output when its prompt shape is wrong, which makes this defense in depth for a known failure mode.
