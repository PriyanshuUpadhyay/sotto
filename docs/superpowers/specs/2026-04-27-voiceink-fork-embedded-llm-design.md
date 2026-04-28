# VoiceInk Fork — Embedded LLM Providers (Design)

**Date:** 2026-04-27
**Author:** Priyanshu (personal)
**Status:** Draft for review

## Goal

Personal macOS dictation tool with low memory/native feel, broad model support including Parakeet, broad LLM post-processing including embedded on-device LLMs that don't require a background daemon. Migrate off Electron-based amical.

## Decision: adopt VoiceInk, fork privately, add two embedded LLM providers

Out of scope explicitly:
- Real-time meeting transcription (mic + system audio). Deferred. Use a separate tool (Recap, Granola) when needed.
- Any other VoiceInk feature changes.
- Public distribution. Fork stays on-device / private remote.

## Why VoiceInk + fork (not greenfield, not Tauri, not stay on Electron)

VoiceInk v1.74 already ships:
- Whisper.cpp + Parakeet (via FluidAudio on Neural Engine, ~80ms latency)
- AI Enhancement with OpenAI, Anthropic, Groq, Gemini, Mistral, Cerebras, OpenRouter, Ollama
- Power Mode (per-app context-aware formatting)
- Personal dictionary, in-app model downloader, floating widget, hotkeys, transcription history

This covers 5 of 6 stated essentials and both ASR engines. Greenfield Swift would rebuild months of polished UX for marginal gain. Tauri loses Apple-Silicon-optimized MLX/CoreML perf. Staying on Electron doesn't address RAM/native-feel/maintenance pain.

VoiceInk repo is closed to PRs, so fork is the only path. GPL-3 source license is compatible with private fork (no distribution → no obligation triggered). Hard pin to v1.74 release tag; pull upstream changes manually as needed.

## Gap to close

VoiceInk's AI Enhancement does not include:

1. **Foundation Models** (macOS 26+): Apple's built-in on-device LLM. No download, no daemon, in-process. Good enough for cleanup tasks. Cheap to add.
2. **mlx-swift**: in-process LLM inference using Apple's MLX framework. Best Apple-Silicon perf, wide model selection from HuggingFace mlx-community. Heavier weight than Foundation Models but flexible.

Both appear as additional providers in VoiceInk's existing AI Enhancement picker, alongside OpenAI/Ollama/OpenRouter. Selection is per-Power-Mode (matching existing pattern).

## Architecture

### Layering (assumed, verified in Phase 0 of implementation)

VoiceInk's `Services/` directory is presumed to host an AI Enhancement provider abstraction. Both new providers conform to whatever protocol the existing OpenAI / Ollama / OpenRouter providers use. **If no abstraction exists** — i.e. providers are hardcoded conditionals — the implementation plan's Phase 0 includes extracting a small protocol first. Effort estimate accommodates this.

### New components

```
VoiceInk/Services/Enhancement/
├── FoundationModelsProvider.swift     # uses FoundationModels framework
├── MLXProvider.swift                   # uses MLXLLM / MLXLMCommon
└── MLXModelRegistry.swift              # curated model list + download UI hook
```

### Foundation Models provider

- Single file. Wraps `LanguageModelSession`.
- Reuse one session per app launch; reset on long idle.
- Maps existing prompt/system-prompt structure to Foundation Models' chat-style API.
- No model file. No download UI. Always-available on macOS 26+.
- macOS version gate: `if #available(macOS 26, *)` — provider hidden on older.

### MLX-swift provider

- Add Swift packages: `mlx-swift`, `mlx-swift-examples` (specifically `MLXLLM`, `MLXLMCommon`, and the `Hub` model downloader).
- Model storage: `~/Library/Application Support/<voiceink-bundle-id>/MLXModels/<repo>/`
- Provider holds an in-memory loaded model + tokenizer. Lazy-load on first request.
- Idle eviction: unload model after N minutes of inactivity to release RAM (matches Ollama behavior). Configurable; default 10 min.
- Generation: temperature/top_p match existing provider knobs.

### Curated MLX model list

Hardcoded in `MLXModelRegistry.swift` — small, opinionated:

| Display name | HF repo | Quant | Size | Notes |
|---|---|---|---|---|
| Qwen 2.5 3B Instruct | `mlx-community/Qwen2.5-3B-Instruct-4bit` | 4-bit | ~2 GB | Fast default, good cleanup quality |
| Qwen 2.5 7B Instruct | `mlx-community/Qwen2.5-7B-Instruct-4bit` | 4-bit | ~4.5 GB | Higher quality, fits 32 GB easily |
| Llama 3.2 3B Instruct | `mlx-community/Llama-3.2-3B-Instruct-4bit` | 4-bit | ~2 GB | Alt small |
| Mistral 7B Instruct v0.3 | `mlx-community/Mistral-7B-Instruct-v0.3-4bit` | 4-bit | ~4.2 GB | Alt mid |

Plus a free-text "Custom HF repo" field for advanced use.

### Settings UI

In VoiceInk's existing AI Enhancement settings:

- "Foundation Models (built-in)" — appears only on macOS 26+
- "MLX (local, on-device)" — when selected, reveals a model sub-picker:
  - List of curated models with size + status (Not downloaded / Downloading X% / Downloaded)
  - "Download" button per row; cancel/delete actions
  - "Custom HF repo" text field at bottom

**First-time UX (chosen option b):** Selecting MLX provider does NOT auto-download. User picks a model explicitly. Generation requests fail with a clear error until a model is downloaded and selected.

### Toggle UX

Use VoiceInk's existing per-Power-Mode provider picker. Set provider once per Power Mode (e.g. Foundation Models for general dictation, MLX-Qwen-7B for code/IDE Power Mode). No new menubar/runtime toggle. If VoiceInk already exposes a runtime switch, it works for these new providers automatically.

### Storage

Settings persist alongside existing VoiceInk provider config (presumed `UserDefaults` or Core Data — verify Phase 0). Per-provider:
- Foundation Models: no config beyond enabled/disabled
- MLX: selected model id, idle-evict timeout, advanced HF repo override

## Data flow

```
User dictation → ASR (Whisper.cpp or Parakeet via FluidAudio)
    → raw transcript
    → AI Enhancement provider (selected per Power Mode)
        → Foundation Models | MLX | OpenRouter | Ollama | OpenAI | ...
    → final transcript inserted at cursor
```

No change to ASR side. Only the post-processing branch grows two providers.

## Error handling

- Foundation Models unavailable (pre-macOS 26): provider hidden in UI.
- MLX model not downloaded when invoked: surface a toast/notification "Model not downloaded. Configure in Settings." Fall back to passthrough (raw transcript) so dictation still inserts text.
- MLX OOM / load failure: log, surface error, fall back to passthrough.
- Idle eviction: silent.

## Testing

Personal app, no formal test infra required. Manual validation:

- Dictate one paragraph, post-process via Foundation Models → text inserted.
- Dictate one paragraph, post-process via MLX-Qwen-3B → text inserted.
- Switch Power Mode, confirm provider switches.
- Force model unload (wait past idle timeout), dictate again, confirm graceful reload.
- Select MLX without downloading model → confirm error UX.

## Fork management

- **Base:** pin to upstream tag `v1.74` (April 22 2026 release).
- **Branch:** `priyanshu/embedded-llm` off the v1.74 tag.
- **Remote:** private GitHub fork (or local-only `git remote` to private server). No public distribution.
- **Upstream upgrades:** manual cherry-pick or rebase from upstream when a wanted feature/fix lands. Document procedure in `FORK.md` at repo root.
- **Models / signing:** personal Apple ID dev cert sufficient for local install. No notarization required.

## Risks

1. **Provider abstraction may not exist in VoiceInk** — could need refactor in Phase 0. Mitigated by allotting time; risk is realised effort, not project failure.
2. **mlx-swift API churn** — package is young. Pin to a known-good version; document.
3. **Foundation Models capability** — Apple's model is small (~3B class). Quality may be insufficient for some Power Modes. Mitigation: MLX provider exists for those cases.
4. **VoiceInk closed-to-PRs upstream** — drift over time. Acceptable for personal use; rebase pain is bounded.
5. **GPL-3 in private fork** — only an issue if you ever distribute. Document this in `FORK.md` so future-you doesn't accidentally publish.

## Effort estimate

| Phase | Work | Days |
|---|---|---|
| 0 | Read VoiceInk source, verify provider abstraction | 0.5 |
| 1 | Foundation Models provider + UI entry | 1.5 |
| 2 | MLX-swift integration + provider class | 2 |
| 3 | Model picker UI + download flow + curated registry | 1.5 |
| 4 | Settings persistence + idle eviction + error UX | 0.5 |
| 5 | End-to-end manual testing on hardware | 0.5 |
| | **Total** | **6.5 days focused** |

Plus ongoing: ~1-2 hours/month rebase against upstream.

## Open items (none blocking)

- Default model on first MLX selection: none (user picks). Confirmed.
- Idle-evict timeout default: 10 minutes (open to change after real-world use).
- Whether to expose generation params (temperature, max tokens) in UI per provider, or hardcode sensible defaults — start hardcoded, add UI only if needed.
