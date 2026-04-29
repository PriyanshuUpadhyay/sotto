# STATUS — Live tracker (W11 deep research session)

**Started:** 2026-04-29
**Driver ask (user):** the W10 model swap (Qwen3) is still slow on real-world dictation; parakeet (transcription) is fast but the enhance step is bad. Plus the app aesthetic doesn't match the floating status bar style. Plus WhisperFlow has features we're missing. All three need to be tackled.

**Strategy:** four parallel research teammates in team `w11-deep-research`. No time cap per teammate — go deep. Results synthesize into a master plan with three phases (W11 model perf, W12 WhisperFlow parity, W13 aesthetic unification).

## Research tracks (live)

| # | Track | Owner | Status | Output doc |
|---|---|---|---|---|
| R1 | Fast specialized rewrite models for MLX | researcher-models | **complete** | `docs/superpowers/research/2026-04-29-specialized-rewrite-models.md` |
| R2 | Enhance pipeline performance audit | researcher-pipeline | **complete** | `docs/superpowers/research/2026-04-29-enhance-pipeline-perf-audit.md` |
| R3 | WhisperFlow feature parity audit | researcher-whisperflow | **complete** | `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` |
| R4 | Aesthetic gap audit (main app vs floating bar) | researcher-aesthetic | **complete** | `docs/superpowers/research/2026-04-29-aesthetic-gap-audit.md` |

## Decisions / open questions

- **R1 (models, complete):** the W10 model lineup is not the bottleneck — encoder-decoder rewrite paths (CoEdIT/GECToR/flan-t5) are blocked by mlx-swift-lm 3.31.3 type registry + license issues. Two real levers for W11: (a) Apple Foundation Models framework via `@available(macOS 26.0, *)` conditional path (zero model bytes shipped, sub-150ms TTFT, OS daemon already runs spec+constrained decoding), (b) `mlx-community/speculative-decoding` Swift SPM dep with Qwen3-0.6B draft + Qwen3-4B target for 2-3× exact-equivalence speedup. Optional: add `Qwen3-0.6B-4bit` (335 MB, Apache 2.0) as an opt-in ULTRA-FAST tier. Open Qs: (1) is bumping deployment target from macOS 14.4 → 26 acceptable, or do we ship dual-path? (2) Does R2 audit reveal non-model bottlenecks (startup latency / KV-cache / tokenizer cost) that override the model-side recommendations?
- **R2 (pipeline, complete):** confirms R1 Q2 — non-model bottlenecks dominate. Top wins are NOT model-side: (1) **no MLX prewarm** (`ModelPrewarmService.swift:107-115` only warms whisper/fluidAudio) → 1.5-4s cold spike on every recording-after-idle; (2) **system prompt is ~1,275 tokens** before context (`AIPrompts.customPromptTemplate` ~675 tok wrapper + System Default body ~600 tok) → dominates `ttft=` for short transcripts; (3) **no KV-cache reuse across calls** (mlx-swift-lm 3.31.3 supports it; see PR #155) → wastes the same system prefill on every enhance; (4) **`temperature: 0.1, topP: 0.9`** dispatches `TopPSampler`; greedy (`temperature: 0.0`) routes to `ArgMaxSampler` for free; (5) **no wall-clock generation timeout** — `max_tokens=192…768` × poor tok/s = 16-64s worst case. Five P0 fixes documented (none require model swap). Framework version is fine — 3.31.3 is latest. Ground-truth capture protocol (5 dictations) defined for the user to validate before any implementation.
- **R3 (WhisperFlow parity, complete):** target product is **Wispr Flow** (`wisprflow.ai`); `whisperflow.app` is a clone with no unique surface. Five P0s for W12: (1) **Voice Snippets / text expansion** — VoiceInk has zero text-expansion model; (2) **Command Mode** (highlight + voice rewrite) — primitives exist (`SelectedTextService`, `AIEnhancementService`, MLX) but no glue; (3) **Auto Cleanup as 4-position dial (None/Light/Medium/High)** with **diff view + Undo AI edit** — directly addresses the "enhance is bad" complaint by giving a dial instead of binary toggle, and `WordDiffEngine` already exists; (4) **Hands-free / continuous mode** with VAD auto-stop + voice "press enter" trigger that strips itself from output; (5) **Scratchpad** (in-app voice notes editor + paste-fallback). P1: Backtrack mid-sentence prompt update, recipient/conversation-aware tone via `ScreenCaptureService` extension, banking-app auto-pause exclusion list, Variable Recognition + File Tagging in Cursor/Windsurf, first-run onboarding flow. **VoiceInk strengths to preserve and lead with:** 100% local, configurable PowerMode (per-app + per-URL), 3 recorder UIs vs Wispr's 1, 5-cue sound system, multi-provider transcription + LLM choice, paid-once $25 vs $144/yr, GPLv3 OSS, no telemetry/leaderboards. Don't import Wispr's screenshot-to-cloud pattern, streaks, or word-quota gating. Open Qs at the end of the doc — most consequential: (a) Snippet activation = post-transcription filter or in-prompt? (b) Command Mode hotkey when `Fn` is taken? (c) Auto Cleanup levels = 4 or 3?
- **R4 (aesthetic, complete):** 33 surfaces audited against Halo / Glass / AdaptiveGlassBackground vocabulary. Top offenders: MetricsView dashboard (raw `.thinMaterial` cards + system-blue gradient + `.rounded` font), Permissions cards (hand-rolled glass instead of `glassPanel`), EnhancementSettingsView + AudioTranscribeView queue + InlineHistoryView card list + PromptEditorView + EnhancementSettingsPanel still on `Form { Section }` (W5 abandoned this), AI Models cards bypass `GlassCard` and use `Color.accentColor`/`Color.white α 0.08` instead of `Palette.accent`/`Palette.hairline`, History window opaque (W8 wallpaper-glass broken — explicit W8 follow-up unfinished). Plus: `CompactHeroSection` icon hardcoded `.blue`, AppNotificationView per-type rainbow colors, ad-hoc `spring/smooth/easeInOut` durations everywhere instead of named `Animation.halo*` tokens. W13 sequenced as A (token sweep) → B (Metrics rebuild) → C (Permissions+AudioTranscribe) → D (Form host purge) → E (AI Models cards) → F (History window glass + animation codemod) → G (polish). 7 open questions surfaced for the lead to ask the user before W13 starts.

## Pre-research context

- W10 just landed (commits 93c4af9 + adff75b + e2be357 + 74c4be1): swapped gemma-4-e2b → Qwen3-1.7B-4bit-DWQ, gemma-4-e4b → Qwen3-4B-Instruct-2507-4bit-DWQ-2510, dropped 26B-A4B experimental.
- W8 (15bf19d) landed adaptive glass app-wide — but user reports app aesthetic still feels off vs floating bars.
- Existing rewrite-model research: `docs/superpowers/research/2026-04-29-mlx-rewriting-models.md`. R1 should go beyond it.
- Floating-bar aesthetic source files: `VoiceInk/Views/Recorder/Halo*.swift`, `NotchRecorderPanel.swift`, `MiniRecorderPanel.swift`. Glass vocabulary in `VoiceInk/Views/Common/Glass*.swift`.
- Enhance pipeline source: `VoiceInk/Services/AIEnhancement/MLXProvider.swift`, `MLXModelRegistry.swift`, `AIEnhancementService.swift`.

## Master plan

See `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` — **fully populated** with W11/W12/W13 phase plans, packet sequencing, and 10 consolidated open questions for user sign-off.

## Next step

✅ All 10 open questions ANSWERED (2026-04-29). Decisions locked at master plan §0.

**Headlines:** Q1=b (bump min target → macOS 26.0; AFM primary path); Q3=c (spec-decode as MLX-fallback opt-in toggle); Q5=Caps+9 (Hyper+9 via Karabiner) for Command Mode; Q6=a (4-level Auto Cleanup dial); Q10=defer (continue build-only validation).

**Recommended next:** spawn `w11a-pipeline-fixes` team. First action — capture ground-truth baseline (5 `🦾 enhance: total=…s` lines on current build) at `docs/superpowers/research/2026-04-29-baseline-enhance-timings.md` BEFORE any code edits land.
