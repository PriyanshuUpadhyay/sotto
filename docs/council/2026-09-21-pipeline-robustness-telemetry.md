# Council — Sotto pipeline robustness from production telemetry

- Date: 2026-09-21
- Artifact under review: the transcription + enhancement pipeline on `main` at `1f63a93`, judged
  only on 6 days of the user's own dictation telemetry (2026-09-15 to 2026-09-21).
- Convened by: the user, "get council to opine and lmk what are the actionables to make the
  pipeline more robust".
- Converged at: round 3.

## Models actually used

| Seat | Route | Model | Effort |
|------|-------|-------|--------|
| claude | `council.claude` | `claude-fable-5-1` | xhigh |
| gpt | `council.gpt` | `gpt-6-astra` (codex) | high |
| gemini | `council.gemini` | `gemini-3.8-flash-high` (agy) | high |

Host: Herdr / swarm session 45, three visible panes. No seat degraded, no fallback used.

## Round 0 — clarify

All three seats answered `NO QUESTIONS`. No resolved constraints were added.

## Verdict

**NO-GO (unanimous)** — two defects are destroying user dictations in the shipped build today.
Row 1 alone moves the pipeline to GO-WITH-CHANGES.

## Required changes

1. **Turn `IsGlossaryRepairEnabled` off now, then delete the repair block
   `TranscriptionPipeline.swift:225-249`.** 58 repair runs, 0 useful corrections, 2 runs that
   replaced the whole utterance "Check its validity." with "Anthropic"
   (`pipeline-trace.jsonl:212-213`). `:244,253,297` makes the destroyed text the only raw copy.
   Cost is +1.07s p50 before any text is visible. Delete ~25 lines.
2. **Reject an empty enhancement output.** Two rows in `enhancement-timings.csv` (file lines
   397-398) carry `outcome=success` with `outputChars=0`; the empty string reaches
   `finalPastedText` at `TranscriptionPipeline.swift:315`. Two places, both tiny:
   - `EnhancementSanityCheck.swift:37` treats an empty output as `.clean` (chair finding — see
     dissent). One line makes it `.suspect([.sentenceDrop])`, which routes into the existing
     hardened-retry and deterministic-cleanup ladder and covers every provider, including the
     identical AFM hole at `AFMProvider.swift:280,328-329`.
   - `GGUFProvider.swift:395` returns the trimmed output with no check, so the CSV records
     `.success`. Three lines throwing `ProviderError.generationFailed` when the output is empty and
     the input is not makes the telemetry truthful.
3. **Delete the code row 1 leaves dead, in the same release.** `GlossaryCorrection.swift`,
   `GGUFProvider.swift:39-44` and `:185-304`, plus `AIService.swift:180-183`,
   `SottoTests/GlossaryCorrectionTests.swift`, and the `glossaryRepair` trace members
   (`TranscriptionTrace.swift:33,54,142-145`; `TranscriptionTraceTests.swift:161`). Chair verified
   the caller set; `correctGlossaryWithGGUF` has exactly one call site. Delete ~258 lines.
4. **Read stop-to-preview as the first-text metric; keep stop-to-paste for total elapsed time.**
   Costs 0 lines. `onPreviewShown` never fires on the direct-paste path
   (`TranscriptionPipeline.swift:42-44`), so stop-to-paste remains the only end-to-end span when
   review is off.

## Rejected, with the evidence that rejects them

- **Move glossary repair after the preview, or add a timeout.** Fixes the latency only. Both
  destructive calls took 0.583s and 0.503s, so no timeout catches them.
- **Harden `GlossaryCorrection.apply`.** New logic for a feature with 0 demonstrated value in 58
  production runs.
- **Delete `llama_memory_clear` at `GGUFProvider.swift:248`.** `runEnhance` clears the same memory
  at `:334` on every call. Measured: enhancement p50 0.441s with repair (n=27) against 0.440s
  without (n=3). Deleting it is also unsafe, because `llama_batch_get_one` at `:255` appends to
  whatever the context holds.
- **A length-shrink guard on enhanced text.** Only 2 shrinks of 105 changed runs reach 10%. The bad
  one is -11.9% from the retired mlx-gemma; the -52.4% one ("let's let's let's see" to "Let's see.")
  is correct. No threshold separates them.
- **A safety-refusal fallback.** Already implemented at `TranscriptionPipeline.swift:329-346`.
- **New metric code in `SottoEngine.swift`.** The machine-only metric already exists at
  `SottoEngine.swift:470-482`.
- **A word-substitution guard on enhancement.** 3 wrong edits in 38, across both GGUF models, and no
  rule separates `updated -> the` (bad) from `graze -> grace` (good).
- **Reverting to mlx-gemma, pre-warming AFM, optimizing ASR, choosing a GGUF model on its no-op
  rate, or changing the GGUF timeout.** All rejected on the numbers; see the round artifacts.

## Dissent / residual risk

- **gpt** would not sign "everything else is healthy", citing `Tmax -> Taxis`, `updated -> the`, and
  `recapsels` in the enhancement output. It agrees no safe small guard is provable from 38 edits.
  The risk is real and unmeasured; the sample must grow before a rule is written.
- **claude** rates the empty-output defect low in urgency: both events came 11 seconds apart in the
  first GGUF session on 09-16, with 156 clean calls since, which fits a root cause already fixed
  that morning. It holds the guard is still correct because nothing in the current path rejects an
  empty success.
- **Chair amendment, not a seat position.** The seats placed the empty-output fix in
  `GGUFProvider.swift` only, because `EnhancementSanityCheck.swift` and `AIEnhancementService.swift`
  were outside the pinned coordinates — a defect in the chair's brief, not in the seats' reasoning.
  The chair found the actual root cause at `EnhancementSanityCheck.swift:37`, where the repair guard
  that exists to catch bad enhancement output declares an empty output `.clean`. The `claude` seat
  argued against a guard at `TranscriptionPipeline.swift:306` and its reasons hold there; they do
  not reach the sanity check inside `performEnhance`. No seat has judged this location.

## Per-model trail

- **GEMINI**: opened with 6 rows, conceded 4 of them in round 2 with citations, finished at 3 rows,
  `REMAINING OBJECTION: NONE`.
- **GPT**: caught that the pinned brief was stale mid-round-1 by re-deriving from the growing trace
  file, which is how the "Check its validity." destruction surfaced at all. Withdrew its own comment
  row. Held one scoping caution about deleting helpers outside its permitted files.
- **CLAUDE**: gave the exact latency attribution (preview minus repair = 0.221s, the old baseline),
  found the second defect (empty success output) in round 2, and conceded its own round-1 "2 rows is
  the floor" and "everything else is healthy".

## Round wall times

| Round | Dispatched | Last artifact | Elapsed |
|-------|-----------|---------------|---------|
| 0 | 11:25:28 | 11:28:04 | 2m 36s |
| 1 | 11:28:29 | 11:34:28 | 5m 59s |
| 2 | 11:35:08 | 11:38:53 | 3m 45s |
| 3 | 11:39:47 | 11:41:34 | 1m 47s |

Total 16m 06s.

## The decision that remains with the user

The council recommends and does not implement. Nothing above has been applied. Row 1's first half
(turning the key off) is reversible and costs no code; the rest is a normal change.
