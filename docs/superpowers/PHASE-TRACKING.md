# Phase tracking — W11 / W12 / W13 implementation packets

**Source plan:** `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` (decisions §0)
**Live status:** `docs/superpowers/STATUS.md`
**Started:** 2026-04-29 · last updated: 2026-04-30

Status legend: ⬜ pending · 🟡 in_progress · ✅ done · ⏸ blocked / deferred

---

## Phase 1 — W11 (enhance speed real fix)

| Packet | Status | Notes |
|---|---|---|
| **W11.A** — pipeline fixes (A1+A2+A4+A5+A6+A7) | ✅ | Merged 2026-04-29 (`84ac7bf`). A3 deferred. |
| **W11.A.A3 follow-up** — KV-cache reuse for system prefill | ✅ | Merged 2026-04-30 (`201fb8f`). Path B token-diff splitter, gated behind `MLXKVCacheReuseEnabled` UserDefault (default off). chatml templates → full benefit; legacy `[INST]<<SYS>>` skipped via `n<32` floor → standard fallback. CSV writes `promptMode=kvCacheReuse` on hits. |
| **W11.D** — Enhancement timing telemetry (new) | ✅ | Merged 2026-04-30 (`42edcbe`). CSV at `~/Library/Application Support/<bundle>/enhancement-timings.csv`; diagnostic logs for fastPath/prewarm/idle-evict/timeout; UI buttons in Settings. |
| **W11-prompt-fix** — MLX prompt-wrap correctness | ✅ | Merged 2026-04-29 (`3247736`). Unblocks empirical perf measurement (broken prompt was masking timing differences). |
| **W11-models-expand** — registry + auto-detect cache | ✅ | Merged 2026-04-29 (`14f092a`). 5 new curated entries + `MLXModelDownloader.detectInstalledModels()` + DETECTED picker section. |
| **W11.B** — Apple Foundation Models primary path | ✅ | Merged 2026-04-30 (`e228f73`). Deployment target 14.4 → 26.0. AFMProvider replaces FoundationModelsProvider. Routing: AFM-first when `SystemLanguageModel.default.isAvailable`; only `safetyRefusal` falls back to MLX silently, other errors propagate. AFM prewarm wired. CSV `promptMode=afm` populated. Live AFM-disabled fallback path not exercised pre-merge (deferred to user-machine validation). |
| **W11.C** — Speculative decoding opt-in (MLX fallback) | ⏸ | **Deferred 2026-04-30** (no commit; worktree clean). Upstream `mlx-community/speculative-decoding` Package.swift pins `mlx-swift-lm from: "2.29.2"` (<3.0.0 ceiling) — irreconcilable with our `exactVersion 3.31.3` pin needed for qwen3 model_type, KV-cache APIs (W11.A.A3), and `swift-huggingface` 0.9.0 cache layout. Forward options (each its own future packet): (a) fork to `pu-foyer/speculative-decoding` + bump its mlx-swift-lm dep to 3.x and patch any 2→3 source breaks, (b) port the algorithm in-tree against mlx-swift-lm 3.x primitives (~500-1000 LOC), (c) wait for upstream — repo active, last commit 2025-12-08. |

**Phase 1 status — DONE (modulo W11.C upstream blocker):**
1. ✅ W11.D timing telemetry (merged `42edcbe`)
2. ✅ W11.A.A3 KV-cache reuse (merged `201fb8f`, opt-in)
3. ✅ W11.B AFM primary path (merged `e228f73`, deployment target → macOS 26.0)
4. ⏸ W11.C spec-decode opt-in — deferred (upstream SPM SemVer conflict; not a decision we can make on our side)

→ Ready to proceed to Phase 2 (Wispr Flow parity) per master plan §6.

---

## Phase 2 — W12 (Wispr Flow parity)

| Packet | Status | Notes |
|---|---|---|
| **W12.A** — Auto Cleanup levels + diff + Undo | ⬜ | Replace binary `isAIEnhancementEnabled` with 4-level dial (None/Light/Medium/High); wire `WordDiffEngine` into result UI; persist raw transcript alongside enhanced. Highest user-leverage. |
| **W12.B** — Command Mode | ⬜ | Caps+9 (Hyper+9) hotkey; capture selection → record voice → enhance with spoken instruction → paste replacement + undo. |
| **W12.C** — Voice Snippets (text expansion) | ⬜ | New `Snippet` model; pre-enhance regex (Q4=c) splices triggers into expansions; CRUD UI; import/export. |
| **W12.D** — Hands-free + VAD + voice "press enter" | ⬜ | Continuous-mode toggle/double-tap; VAD silence threshold; voice trigger phrase strips itself + fires `autoSendKey`. |
| **W12.E** — Scratchpad | ⬜ | New window (⌥+S); multi-tab; auto-save; 50-version history; doubles as paste-fallback target. |

---

## Phase 3 — W13 (aesthetic unification)

| Packet | Status | Notes |
|---|---|---|
| **W13.A** — token sweep | ✅ | Merged 2026-04-29 (`e196cda`). 26 files swept across A/B/F axes. C/E/F deferrals routed to later packets. |
| **W13.B** — Metrics dashboard rebuild | ⬜ | First surface a new user sees. Replace controlAccentColor hero gradient (keep gradient, swap to `Palette.accent` glow per Q9=a); replace `MetricCard` `.thinMaterial` with `GlassCard(cornerRadius: 16)`; drop rainbow per-card icon palette. |
| **W13.C** — Permissions + AudioTranscribe | ⬜ | Swap hand-rolled `ultraThinMaterial + obsidian fill + hairline overlay` chrome for `GlassCard(cornerRadius: 14)` / `glassPanel()`. |
| **W13.D** — Form-host purge | ⬜ | 5 surfaces still on v1 `Form { Section { } }`: `EnhancementSettingsView`, `AudioTranscribeView` queue, `InlineHistoryView` cardList, `PromptEditorView`, `EnhancementSettingsPanel`. Migrate to W5 `ScrollView { LazyVStack { SettingsCard } }` pattern. |
| **W13.E** — AI Models cards | ⬜ | `WhisperModelCardView`, `CloudModelCardView`, `FluidAudioModelCardView`, `MLXModelPickerView` row cards: replace direct `HaloMaterial(phase: .hidden)` + hardcoded `Color.accentColor` / `Color.white α 0.08` with `GlassCard(cornerRadius: 16)` + `Palette.accent` / `Palette.hairline`. |
| **W13.F** — History window glass + animation codemod | ⬜ | Mirror `WindowManager.configureWindow:36-41` flags into `HistoryWindowController.createHistoryWindow:32-65` (`isOpaque=false`, `backgroundColor=.clear`); drop hardcoded `Color(NSColor.windowBackgroundColor)` calls in `TranscriptionHistoryView`. Animation codemod: ad-hoc durations → `Animation.halo*` named tokens. |
| **W13.G** — Polish | ⬜ | `CompactHeroSection` icon (currently `.blue` hardcoded) → `Palette.accent`; `AppNotificationView` per-type rainbow → single accent + motion as discriminator. Final spec extension. |

---

## Carryover (separate sessions)

- Test-infrastructure unblock — `xcodebuild test` env-blocked (Mac Development cert + macros-trust + IPC bootstrap). User-machine fix.
- Push to origin — currently 45 commits ahead; user pushes manually.

---

## How this doc updates

- After each packet merges to `main`, flip its row to ✅ + record the merge commit short-SHA.
- Phase 1 row order = sequencing order. Phase 2/3 row order = recommended dispatch order from master plan §6.
- New packets discovered mid-phase get inserted into their phase table with a `(new)` annotation.
- Carryover items only move out of "carryover" if user explicitly redirects.
