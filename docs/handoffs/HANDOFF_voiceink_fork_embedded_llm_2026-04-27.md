# Handoff: VoiceInk Fork — Embedded LLM Providers

**Date:** 2026-04-27
**Branch:** `priyanshu/embedded-llm` (pinned to upstream `v1.74`)
**Status:** ready-to-execute (planning + critique complete; zero code written)

## Goal

Personal macOS dictation tool. Fork VoiceInk v1.74 and add two new AI Enhancement providers — Apple **Foundation Models** (macOS 26+, built-in) and **mlx-swift** on-device LLM (curated 4-model picker) — both in-process, no daemon. Selectable per Power Mode alongside existing OpenAI/Ollama/OpenRouter.

## Work Completed

- [x] Researched competitive landscape (VoiceInk, KeyVox, Speak2, MacParakeet, Sumi, Handy STT, Whispo, OpenWhispr, Muesli)
- [x] Verified VoiceInk v1.74 already supports Parakeet (FluidAudio), broad LLM providers (OpenAI/Anthropic/Groq/Gemini/Mistral/Cerebras/OpenRouter/Ollama), Power Mode, dictionary, history, floating widget, in-app downloader
- [x] Decided: fork VoiceInk, add 2 embedded providers; skip greenfield rewrite, skip Tauri, skip Electron-stay
- [x] Wrote design spec → `docs/superpowers/specs/2026-04-27-voiceink-fork-embedded-llm-design.md`
- [x] Wrote implementation plan → `docs/superpowers/plans/2026-04-27-voiceink-fork-embedded-llm.md`
- [x] Ran codex pre-approval critique → folded in 7 fixes (drop fatalError, actor isolation, cancellation, pinned SHAs, Application Support cache, disk pre-flight, passthrough fallback)
- [x] Cut from v1: custom HF repo input field, idle-evict timeout UI knob (codex scope-creep concession). Kept: 4 curated models.
- [x] Codex final verdict: **GO-with-caveats**
- [x] Cloned `https://github.com/Beingpax/VoiceInk` to `/Users/priyanshu/Desktop/Projects/pu/voiceink-fork`
- [x] Renamed `origin` → `upstream`; **no `origin` remote** (local-only / private-use)
- [x] Branched `priyanshu/embedded-llm` off tag `v1.74` (commit `851b260`)
- [x] Copied spec + plan into fork's `docs/superpowers/`

## Key Decisions

| Decision | Rationale |
|---|---|
| Fork VoiceInk (not greenfield, not Tauri) | v1.74 already covers 5 of 6 essentials + both ASR engines. Months of UI work avoided. Apple-Silicon-optimised stack stays optimal via MLX/CoreML. |
| Drop Windows | Personal use, mac-only |
| Drop real-time meeting transcription from v1 | Not load-bearing; use Recap/Granola separately. Add later if needed. |
| Add Foundation Models AND mlx-swift (toggle-able) | Foundation Models for cheap default; MLX for stronger models when needed. User on macOS 26 + 32 GB RAM. |
| Private fork, no GitHub `origin` | "Keep on device for now" — GPL-3 distribution obligation only triggers on distribute. |
| Pin to v1.74 (not track main) | Stable target; manual cherry-pick when upstream has wanted fixes. Documented in plan. |
| Both providers as Swift `actor` types | Codex critique — concurrency safety on `modelContainer`/`session`/`evictTask`. |
| No `fatalError` for availability gates | Codex critique — crash path. Throw `EnhancementError.providerUnavailable`; UI hides via `#available`. |
| HF cache root → Application Support, not Caches | Codex critique — Caches can be purged by macOS. Set via `HF_HOME`. |
| 4 curated MLX models (Qwen 3B/7B, Llama 3.2 3B, Mistral 7B), no custom-repo UI | Balance flexibility vs maintenance surface. |
| Hardcoded 10-min idle eviction (no UI knob) | Codex critique — premature UI. Defer the stepper. |
| Passthrough fallback on every failure path | Codex critique — dictation must never silently drop text. Raw transcript inserted on provider error. |
| SPM deps pinned to exact commit SHAs | Codex critique — `mlx-swift-examples` API churns fast. |
| No automated tests | Personal-fork scope; manual smoke checklist sufficient. |

## Files Changed

| File | Change |
|---|---|
| `docs/superpowers/specs/2026-04-27-voiceink-fork-embedded-llm-design.md` | New — design spec, ~250 lines |
| `docs/superpowers/plans/2026-04-27-voiceink-fork-embedded-llm.md` | New — implementation plan, ~750 lines, codex-critique-revised |
| `docs/handoffs/HANDOFF_voiceink_fork_embedded_llm_2026-04-27.md` | This file |

All untracked. Nothing committed yet.

## What Didn't Work

- Initial assumption that VoiceInk lacked Parakeet + broad providers — **wrong**. v1.74 (April 2026) added them. Saved a lot of intended work; the user's reference (originally said "Keybox", actually [KeyVox](https://github.com/macmixing/keyvox/)) is a different, simpler app with no LLM post-processing.
- Considered embedding llama.cpp instead of mlx-swift — rejected because MLX has materially better Apple Silicon perf and the user is on Apple Silicon.
- Considered staying on Electron amical with Parakeet + meeting transcription added — rejected because user explicitly wants off Electron (RAM, native feel, maintenance pain).
- Considered keeping idle-evict UI stepper — rejected per codex (premature UI for a default that's likely fine).
- Considered shipping 1 model only (codex's strongest scope-cut suggestion) — rejected because user explicitly asked for toggle-able multi-model support.

## Current State

- Fork on disk at `/Users/priyanshu/Desktop/Projects/pu/voiceink-fork/`
- Branch `priyanshu/embedded-llm` checked out at upstream commit `851b260` (v1.74 tag)
- Working tree: clean except for newly added `docs/` (spec, plan, this handoff) — untracked
- No `origin` remote. Only `upstream` → `https://github.com/Beingpax/VoiceInk.git`
- **No build attempted yet.** Plan Task 0.2 is "build from source, verify it runs."
- **No code changes yet.** Implementation has not started.

## Uncommitted Changes

```
On branch priyanshu/embedded-llm
Untracked files:
	docs/
```

Three new doc files under `docs/`. No source code modified.

## Next Steps

Plan execution mode: **subagent-driven-development** (recommended) — each task as a fresh subagent, review between tasks. Or use `superpowers:executing-plans` for inline batch execution. The plan file uses `- [ ]` checkboxes ready for either path.

1. [ ] **Decide commit-now or commit-later for the docs.** Either:
   - `git add docs/ && git commit -m "docs: brainstorming spec, implementation plan, handoff"` — recommended; gives clean baseline before code.
   - Or leave untracked until first code commit.
2. [ ] **Execute Phase 0 — Recon** (plan §"Phase 0"):
   - Task 0.2: Open `VoiceInk.xcodeproj` in Xcode, set personal Apple ID team in Signing & Capabilities, `Cmd+R`. Confirm app launches and basic dictation works against TextEdit. **Hard gate** — do not proceed if build fails. Document errors in `docs/RECON.md`.
   - Task 0.3: Recon the AI Enhancement provider abstraction (`rg` searches for protocol/enum/factory, settings UI, persistence keys, **cancellation/threading at the provider call site** — this is the codex-flagged §5 of RECON.md). Fill the strict template in plan Task 0.3 Step 7.
   - Commit `docs/RECON.md`.
3. [ ] **Phase 1 — Foundation Models provider** (Tasks 1.1–1.4): create the actor, register in enum/factory (no fatalError), expose in UI gated on macOS 26, smoke test. After Phase 1, you have a working Foundation-Models-enhanced fork — usable as a stopping point if MLX takes longer than expected.
4. [ ] **Phase 2-4 — MLX deps + impl + UI + integration** (per plan).
5. [ ] **Phase 5 — Docs (FORK.md) + final smoke checklist (13 items)**.

Estimated effort: ~5.5 days focused work + ~1-2 hrs/month rebase.

## Context the Next Session Needs

### Working directories
- **VoiceInk fork (target of all implementation work):** `/Users/priyanshu/Desktop/Projects/pu/voiceink-fork`
- **Original amical project (where this conversation happened, just for reference):** `/Users/priyanshu/Desktop/Projects/pu/amical`

The amical folder also has copies of the spec/plan; the source-of-truth copies for the next session are the ones inside the fork.

### Hardware / OS
- macOS 26 (Tahoe) — Foundation Models available
- 32 GB RAM — Qwen 7B-4bit and similar fit comfortably
- Apple Silicon

### User preferences
- Sentence fragments, short bullets, no pleasantries (per `~/.claude/CLAUDE.md`)
- Never `git push --force` without explicit confirmation
- Never commit without explicit ask
- Local-only, no public distribution

### Codex final reminders (do not forget)
1. **No text loss on any failure path** — every provider/integration error must passthrough raw transcript.
2. **Availability/safety checks must not crash** — `#available` gating, factory throws, UI hides unusable providers.
3. **Operational constraints exact** — pinned SHAs, `HF_HOME` under `Application Support/<bundle-id>/MLXModels/`, mandatory disk pre-flight before downloads.
4. **Biggest execution risk:** API drift in pinned MLX/HF surfaces. Phase 0 recon + green build is a **hard gate** before downstream wiring.

### License
- VoiceInk upstream: GPL-3
- Fork inherits GPL-3
- **Do not distribute** the fork. GPL-3 source-availability obligation triggers on distribution.

### Useful refs already discovered
- VoiceInk repo: https://github.com/Beingpax/VoiceInk (closed to PRs)
- VoiceInk model docs: https://tryvoiceink.com/docs/recommended-models
- FluidAudio (Parakeet for Swift, already used by VoiceInk): https://github.com/FluidInference/FluidAudio
- mlx-swift: https://github.com/ml-explore/mlx-swift
- mlx-swift-examples (`MLXLLM`, `MLXLMCommon`): https://github.com/ml-explore/mlx-swift-examples
- swift-transformers (`Hub`): https://github.com/huggingface/swift-transformers
- Muesli (reference if meeting transcription is ever added): https://github.com/pHequals7/muesli

### Key plan tasks that need RECON.md to disambiguate
The plan deliberately leaves protocol names, file paths, and exact integration sites *descriptive* until Phase 0 recon fills them in. These tasks reference RECON.md sections:
- Task 1.1 Step 1: substitute `<ProtocolName>` (RECON §1)
- Task 1.2 Step 3: factory wiring (RECON §1)
- Task 1.3 Step 1: settings picker site (RECON §3)
- Task 2.2 Step 1: substitute `<ProtocolName>` (RECON §1)
- Task 3.4 Step 1: integration call site for passthrough (RECON §5)
- Task 4.4 Step 1: settings UI conditional (RECON §3)

If RECON reveals VoiceInk has no provider protocol (just hardcoded if/else), STOP and surface — that's a finding, not a defect to silently work around.
