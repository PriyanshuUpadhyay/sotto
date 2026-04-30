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

## Phase 1 — DONE (2026-04-29 → 2026-04-30)

| # | Packet | Merge | Notes |
|---|---|---|---|
| 1 | `w11-models-expand` | `14f092a` | Registry + cache auto-detect; 5 new curated entries (Qwen3-0.6B, Phi-3.5-mini, Llama-3.2-3B, Granite, SmolLM3); DETECTED picker section. |
| 2 | W11.A pipeline fixes | `84ac7bf` | A1 prewarm + A2 short-transcript fast-path + A4 greedy + A5 wall-clock timeout + A6 idle-evict slider + A7 max-tokens cap. A3 deferred at the time. |
| 3 | W11-prompt-fix | `3247736` | MLX userPrompt now wrapped in `<TRANSCRIPT>` tags + closing suffix. Resolves Qwen3 "replies instead of cleans" bug. |
| 4 | W11.D timing telemetry | `42edcbe` | CSV log at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv` + diagnostic logs (prompt-mode, prewarm, idle-evict, timeout) + Settings UI buttons. |
| 5 | W11.A.A3 KV-cache reuse | `201fb8f` | Token-diff splitter, opt-in via `MLXKVCacheReuseEnabled` UserDefault (default off). chatml templates → full benefit; legacy → graceful no-op. |
| 6 | W11.B AFM primary path | `e228f73` | Deployment target 14.4 → 26.0. AFMProvider replaces FoundationModelsProvider. Routing: AFM-first when `SystemLanguageModel.default.isAvailable`; only `safetyRefusal` falls back to MLX silently. AFM prewarm + telemetry wired. |
| 7 | W11.C spec-decode | ⏸ deferred | `mlx-community/speculative-decoding` Package.swift pins `mlx-swift-lm <3.0.0` — irreconcilable with our 3.31.3 pin needed for qwen3 + KV-cache. Three forward options in `PHASE-TRACKING.md`. |

Plus aesthetic Phase 3 partial start (W13.A token sweep, merge `e196cda`).

## Phase tracker

See `docs/superpowers/PHASE-TRACKING.md` — full status matrix for W11 / W12 / W13.

## Currently waiting on

- **User validation pass.** Build at `~/Downloads/VoiceInk.app` is current as of `2026-04-30 10:24` IST (post-Phase-1). Settings → AI Enhancement → Provider must be set to **MLX** to surface the W11.D buttons + W11.B "Active path: …" indicator + W11.A.A6 idle-evict slider — they all live inside the MLX section, gated by `selectedProvider == .mlx`. CSV at `~/Library/Application Support/com.prakashjoshipax.VoiceInk/enhancement-timings.csv` captures rows automatically per enhancement.

## Next phase

Phase 1 closed (modulo W11.C upstream blocker). Awaiting user direction on Phase 2 (Wispr Flow parity — recommended start: W12.A Auto Cleanup levels) or Phase 3 remainder (aesthetic — recommended start: W13.B Metrics dashboard rebuild). Both have zero file overlap; can run parallel teams.
