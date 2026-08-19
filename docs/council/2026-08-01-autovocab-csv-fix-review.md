# Council review — auto-vocab junk-adds fix + CSV transcriptChars fix

- Date: 2026-08-01 · Run: `135a533a-sotto-fix-review` · Backend: Herdr panes
- Artifact: uncommitted diff on `main` (6 files, +81/−19) — strict 1:1 substitution alignment + NSSpellChecker OOV gate + >3 burst guard in `AutoLearnVocabularyService`; `inputChars`→`transcriptChars` threading in the AFM telemetry chain.
- Models: CLAUDE = Opus (pane), GPT = gpt-5.6-sol (codex pane, workspace-write scoped to council dir — herdr read-only-hang exception), GEMINI = Gemini 3.1 Pro (agy pane).
- Round 0: NO QUESTIONS ×3.

## Council verdict: GO-WITH-CHANGES (unanimous once accepted changes land)

Consensus reasoning: All three voices independently traced the diff and found both fixes correct and completely threaded (call sites, CSV rotation, test traces). The only required change is comment-level: `AFMProvider.swift:152–162` still documents the removed MLX fallback contract. No voice found a concrete input that fabricates a vocab candidate surviving the new guards.

Required changes (accepted, dispatched to implementer):
1. Correct stale MLX-fallback doc comment above `AFMProvider.enhance` (CLAUDE).
2. Inject the misspelled-predicate into `isLikelyProperTerm` so the `oovGate` test is machine-independent (risk flagged by CLAUDE + GPT).
3. Document the equal-length recall cut ("jon smyth"→"John Smith" spans no longer mined) at the call site (CLAUDE).

Dissent / residual risk: GEMINI — a bogus whole-field read-back containing ≤3 OOV typos among dictionary words can still pass the burst guard (mitigated upstream by strict 1:1 alignment); accepted as residual. CLAUDE — burst guard counts candidates before the existing-vocab filter; rare, flag-only.

Per-model trail:
- GEMINI: GO — cross-product fix is fundamental; OOV gate and threading verified correct.
- GPT: GO, "no major issues" — traced pasted-token filter retention, guard ordering, full AFM chain.
- CLAUDE: GO-WITH-CHANGES — fixes verified by trace; stale doc comment in touched file; machine-dependent test; undocumented second recall cut.

## Addendum — 2026-08-02 delta review (rounds 2–4)
GPT seat re-reviewed the follow-up rounds: found 1 HIGH (round-3 `maximumResponseTokens` = silent-truncation paste risk, `streamResponse` exposes no finish reason). Disposition: valid → cap removed, greedy kept, budget helper+tests deleted. Final verdict: "no major issues". Final test run: 613 passed / 1 pre-existing unrelated failure (`MatteTokenTests.testPhosphorAccentValue`).
