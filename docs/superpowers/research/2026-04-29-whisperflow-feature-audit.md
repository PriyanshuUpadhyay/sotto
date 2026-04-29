# Research: Wispr Flow feature audit + parity gap analysis vs VoiceInk

**Date:** 2026-04-29
**Owner:** researcher-whisperflow (team `w11-deep-research`, R3)
**Driving ask:** "the user wants to know which WhisperFlow features are essential to extend VoiceInk further" — comprehensive feature audit + gap analysis vs current VoiceInk capabilities, with priority ranking for what to ship in W12.

## 0. Naming clarification — "WhisperFlow" vs "Wispr Flow"

Two products with confusable names exist:

- **Wispr Flow** — `wisprflow.ai`, by Wispr AI. The actual incumbent. Launched Oct 1 2024 on Product Hunt (#1 of the day, #1 of the week). Mac/Windows/iOS/Android. ~$15/mo Pro. The product reviewers, Reddit, comparison sites and the "9 Best Wispr Flow Alternatives" coverage all point at. **This is the product the user means** — the product VoiceInk is benchmarked against by reviewers. ([Wispr Flow](https://wisprflow.ai/), [PH launch](https://www.producthunt.com/products/flow-voice/reviews))
- **Whisper Flow** — `whisperflow.app`, App Store ID `id6754533870`. Recent (post-Wispr) Mac/Windows/iPhone clone with near-identical marketing copy ("4x faster than typing", "220 wpm", filler removal, 100+ languages). Likely a fast-follower trading on Wispr's name. Distinct from Wispr Flow. No notable third-party reviews. ([whisperflow.app](https://whisperflow.app/))

This audit treats **Wispr Flow** as the canonical target. Whisper Flow appears to be a feature-shadow with no surface area Wispr doesn't already cover, so it adds nothing to the gap list.

---

## 1. TL;DR — top P0 features VoiceInk should add (W12)

In rough priority order. All have clean source files identified for the implementation handoff in §2.

1. **Voice Snippets / text expansion** — say a trigger phrase, expand to canned text. Wispr ships with sync, multi-line, team-share. VoiceInk has zero text-expansion vocabulary — `WordReplacement` is for misspell→correct only, not phrase→block. **P0** — table-stakes for power users; `aText`/`Raycast Snippets` users will not switch without it.
2. **Command Mode (highlight + voice rewrite)** — select text → press shortcut → speak instruction ("make this concise", "translate to Spanish", "bullet list") → result replaces selection, with undo. This is Wispr's #1 differentiator per multiple reviews. VoiceInk has the building blocks (`SelectedTextService`, `AIEnhancementService`, MLX) but no glue. **P0** — without this, VoiceInk is one-way speech→text while Wispr is bidirectional voice editing.
3. **Auto Cleanup levels (None / Light / Medium / High)** with **diff view + undo of AI edit** — Wispr's April 2026 redesign replaced Smart Formatting's binary toggle with 4 levels and an "Undo AI edit" reveal. VoiceInk currently does enhance-or-not via `isAIEnhancementEnabled` per PowerMode and has `WordDiffEngine` already — wiring is short. **P0** — fixes the user complaint that "enhance is bad" by giving them a dial instead of all-or-nothing.
4. **Hands-free / continuous mode** with auto-stop + "press enter" voice command — VoiceInk's current model is push-to-talk + tap-to-toggle; there's no continuous session with VAD-based stop, no voice-spoken submit. Wispr has 20-min sessions, double-tap for hands-free, voice "press enter" stripping. **P0** — accessibility-critical (Parkinson's users specifically cited Wispr for this) and the natural use case for long-form dictation (notes, journaling).
5. **Scratchpad (in-app voice notes editor)** — Mac/Windows window with `⌥+S` to open, dictate-into-place, auto-save, multi-tab, 50-version history with diff/restore, sync. VoiceInk has History (read-only past dictations) but no editable note surface. Doubles as a fallback when paste fails. **P0** — Wispr's most-requested feature in the v3 changelog and the only place users go when no foreground app has a text field.

---

## 2. Full feature table

Format: feature | category | Wispr Flow | VoiceInk current | priority | one-line justification

### A. Recording / transcription UX

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| Push-to-talk hotkey | ✓ default `Fn` Mac / `Ctrl+Win` Win | ✓ `HotkeyManager.swift`, `MiniRecorderShortcutManager.swift` — fully customizable | — | Parity |
| Hands-free / continuous (toggle + VAD) | ✓ `Fn+Space` Mac, double-tap, 20-min sessions | partial — toggle exists but no VAD auto-stop, no extended session model | **P0** | Long-form dictation use case; accessibility |
| Multiple bound shortcuts (up to 4 × 3 keys) | ✓ | partial — single global shortcut + mini-recorder shortcut | P2 | Power-user convenience; not driving adoption |
| Mouse button binding (Mouse4/5, middle click) | ✓ | ✗ | P2 | Niche but loved by gamers/streamers; KeyboardShortcuts dep doesn't expose this trivially |
| Cancel with `ESC` mid-dictation | ✓ rebindable | ✓ | — | Parity |
| Notch / floating bar / menubar surfaces | ✓ Flow Bar (single style) | ✓ **3 styles** — Halo Notch, Halo Floating, Constellation cluster — picker in `RecorderStylePicker.swift` | — | **VoiceInk advantage** |
| Live waveform / mic feedback | ✓ "white bars moving" | ✓ `AudioVisualizerView.swift` | — | Parity |
| Start/stop earcons (sound cues) | ✓ "ping" | ✓ **5-cue system** (start, transcribeComplete, enhanceComplete, cancel, fail) — `CueSynthesizer.swift`, user-overridable | — | **VoiceInk advantage** |
| In-bar microphone picker | ✓ right-click Flow Bar → mic | partial — Settings only (`AudioInputSettingsView.swift`); no quick-switch from recorder | P2 | Saves a navigation but not driving adoption |
| In-bar language picker | ✓ Mar 2026 changelog | ✗ language is per-PowerMode or global setting | P2 | Multilingual users only; PowerMode covers most cases |
| Auto-pause in banking/financial/password apps | ✓ Android + Flow Bubble auto-hides | ✗ no exclusion list | P1 | Privacy + safety; one bug-report away from press attention |
| Session length cap | 20 min desktop | none enforced | — | Parity-via-omission |
| Whisper-detection (works at low volume) | ✓ marketed feature | unknown — depends on whisper.cpp/parakeet front-end gain; not advertised | P2 | Office workers value it; would be a marketing-line item |

### B. AI enhance / auto-edit behaviors

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| Filler-word removal | ✓ default | ✓ via prompt; `TranscriptionAutoCleanupService.swift` does light cleanup | — | Parity |
| Auto-punctuation from pauses/tone | ✓ default | partial — depends on transcription model + enhance prompt | P2 | Parakeet handles much of this already |
| Mid-thought self-correction ("Backtrack") — "2… actually 3" | ✓ explicitly trained | ✗ depends on prompt; not advertised | P1 | High-impact user-visible delight; cheap prompt change |
| Auto-cleanup level dial (None / Light / Medium / High) | ✓ Apr 2026 | ✗ binary `isAIEnhancementEnabled` per PowerMode | **P0** | User complaint surface: "enhance is bad" → give them a dial |
| Diff view of what AI changed | ✓ `Fn+D` shows side-by-side | partial — `WordDiffEngine.swift` exists; not surfaced in UI | **P0** | Builds trust; un-blocks "I don't trust the rewrite" objections |
| Undo AI edit (revert to raw transcript) | ✓ in History 3-dot menu | ✗ raw not preserved alongside enhanced | **P0** | Pairs with diff view; both ship together |
| Custom prompt library | ✓ Snippets-as-prompts (limited) | ✓ **richer** — `CustomPrompt.swift`, `PredefinedPrompts.swift`, `PromptTemplates.swift`, trigger-words per prompt, enable/disable | — | **VoiceInk advantage** |
| Personalized styles (Formal / Casual / Excited / Very Casual) per app category | ✓ Email/Work/Personal/Other | partial — per-app PowerMode lets you set a prompt, but no built-in tone presets | P1 | Shorter ramp than custom prompts for novices |
| Auto-detect language + mid-sentence code-switching | ✓ 100+ langs | ✓ via `LanguageDictionary.swift`, but per-PowerMode language setting; not auto-switch mid-sentence | P2 | Only matters for bilingual users |
| Recipient/conversation-aware tone (read names/threads) | ✓ via accessibility API | partial — `useScreenCapture` + screencap OCR; not "read recipient field" | P1 | Wispr's killer Slack/email demo |

### C. Per-app integrations

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| Detect frontmost app | ✓ accessibility API | ✓ `ActiveWindowService.swift` | — | Parity |
| App-specific config | ✓ 4 fixed categories (Email/Work/Personal/Other) | ✓ **fully configurable PowerMode** — per-app and per-URL configs (`PowerModeConfig.swift`) | — | **VoiceInk advantage** |
| URL-specific config | ✓ recognizes specific websites | ✓ `BrowserURLService.swift` + `URLConfig` | — | Parity |
| Special handling: code editors (Cursor / VS Code / Windsurf) | ✓ Variable Recognition + File Tagging | partial — works fine; no symbol-context injection, no `@filename` voice tagging | P1 | Devs are a high-value segment for VoiceInk per existing PowerMode "developer" prompts |
| Special handling: terminals | ✓ Terminal.app/Warp/Ghostty/Hyper/iTerm direct paste; Shift+Insert fallback | partial — `CursorPaster.swift` uses standard paste; no per-terminal logic | P2 | Niche — most terminals just work |
| WSL / SSH / tmux paste fallback | ✓ "Paste Last Transcript" shortcut | ✗ — no last-transcript paste action | P2 | Niche |
| Browser injection across Chrome/Safari/Arc/Brave/Edge/Firefox/Opera | ✓ identifies site by URL | ✓ `BrowserURLService.swift` covers the majors | — | Parity |
| Slack thread context | ✓ reads channel/recipient | ✗ only screen capture | P1 | Common workflow; pairs with §B "recipient-aware tone" |
| Notion placeholder filtering | ✓ explicit filter | ✗ depends on screencap OCR luck | P2 | Notion-specific; low ROI |

### D. Dictionary + learning

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| Manual word addition | ✓ | ✓ `VocabularyView.swift`, `CustomVocabularyService.swift` | — | Parity |
| Misspelling → correction pairs | ✓ replacement rules | ✓ `WordReplacement.swift`, `WordReplacementView.swift` | — | Parity |
| Auto-learn from corrections | ✓ proper-noun filtered, ✨ icon | ✓ `AutoLearnVocabularyService.swift` — observes pasted text, watches AX changes | — | **Parity / VoiceInk slight lead** (already existed) |
| Bulk CSV import | ✓ 1000 entries / 3 MB | ✓ `ImportExportService.swift`, `VoiceInkCSVExportService.swift` | — | Parity |
| Cross-device sync | ✓ Mac/Win/iOS/Android | ✗ Mac-only product | — | Out of scope (positioning) |
| Star important terms / usage-based sort | ✓ Mar 2026 changelog | ✗ no priority signal in dictionary | P3 | Cosmetic; current sort is fine |
| Dictionary terms loaded into transcription context | ✓ sent server-side | ✓ `CustomVocabularyService` injects into Whisper prompt | — | Parity |

### E. Voice commands / output behaviors

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| "Press enter" voice trigger (auto-submit, strips phrase) | ✓ | ✗ only `autoSendKey` per-PowerMode, applied unconditionally | P1 | Users want voluntary submit, not automatic; ergonomic upgrade |
| Voice Snippets / text expansion | ✓ trigger → expansion, sync, team-share | ✗ no model, no UI, no service | **P0** | aText/Raycast users will not switch without it |
| Variables in snippets ({{date}}, {{time}}) | ✗ not supported by Wispr either | ✗ | P2 | Build it — beats Wispr |
| Paste vs type-out toggle | ✓ paste default; type fallback for unsupported fields | partial — `CursorPaster.swift` paste-only; clipboard fallback exists | P2 | Edge cases (password managers, locked fields) |
| Cursor preservation | ✓ inserts at cursor | ✓ `CursorPaster.swift` | — | Parity |
| Undo via Cmd+Z after paste | ✓ | ✓ inherited from paste | — | Parity |
| Highlighted-text selection awareness | ✓ Command Mode | ✓ `SelectedTextService.swift` reads selection — but no consumer that *transforms* it | **P0** | The primitive exists; the wiring is the W12 build |
| Paste-Last-Transcript shortcut | ✓ `⌘⌃V` Mac / `⇧⌥Z` Win | ✗ no last-transcript replay action | P2 | Helpful when paste lands in wrong field |

### F. Onboarding + settings polish

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| First-run welcome flow | ✓ welcome → auth → personalization Q's → mic test → lang → tutorial | ✗ — no `Onboarding*.swift`, no welcome surface; cold-start drops user at Permissions | P1 | First-run is the worst surface in VoiceInk today; cheap to fix |
| Mic test step | ✓ | partial — Settings has `AudioInputSettingsView.swift` but no in-flow test | P2 | Pairs with onboarding |
| Tutorial (dictate into simulated Slack/Gmail) | ✓ | ✗ | P2 | Pairs with onboarding |
| Personalization questions (typing habits, role) | ✓ tunes recommendations | ✗ | P3 | Privacy-skeptical user base may dislike |
| "Saved!" / "Formatted!" celebratory toast | ✓ contextual stickers | partial — `AppNotifications.swift` shows neutral state; no positive-feedback variants | P2 | Delight; small lift |
| Settings IA (sidebar) | ✓ Style / Snippets / Dictionary / Privacy / Shortcuts / etc. | ✓ `SettingsView.swift` with similar IA | — | Parity |
| Settings search | ✗ Wispr doesn't have it either | ✗ | P3 | Build it — beats Wispr |

### G. Status indicators (recording / transcribing / enhancing)

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| Visual: recording state | ✓ Flow Bar pulses + waveform | ✓ Halo + Constellation phases | — | **VoiceInk advantage** (richer states) |
| Visual: transcribing/enhancing distinction | unclear (one bar) | ✓ Constellation cluster phases (`ClusterPhase.swift`), Halo state | — | **VoiceInk advantage** |
| Audio: per-phase cues | minimal (start ping) | ✓ 5 distinct cues | — | **VoiceInk advantage** |
| Color/motion polish | ✓ minimalist | ✓ adaptive glass app-wide (W8 just landed) | — | Parity / per-taste |
| Bubble opacity / size customization | ✓ 20-100% slider, auto-shrink | ✗ recorder UI is fixed | P2 | Power-user setting |
| Notifications redesign / mute by category | ✓ Mar 2026 redesign | partial — `NotificationManager.swift` exists; no per-category mute | P2 | UX polish, not adoption-driving |

### H. History / search / export

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| History view of past dictations | ✓ time-grouped, app-filtered, searchable | ✓ `TranscriptionHistoryView.swift`, `InlineHistoryView.swift` | — | Parity |
| Time grouping (Today / Yesterday / This Week / Older) | ✓ | ✓ | — | Parity |
| Filter by source app | ✓ | partial — depends on what's stored on `Transcription` model | P2 | Confirm in `Transcription.swift` schema |
| Sort: newest / oldest / longest / most words | ✓ | partial — usually only newest-first | P2 | Cheap addition |
| Full-text search | ✓ | ✓ | — | Parity |
| Audio playback of past dictation | ✓ download `.wav` | ✓ `AudioPlayerView.swift`, `PlaybackController.swift`, `AudioTimelineView.swift` | — | **VoiceInk advantage** (built-in player) |
| Audio export | ✓ download `.wav` | partial — playback exists, explicit "export audio" UI unclear | P2 | Confirm; cheap to expose |
| Bulk transcript export | ✗ Wispr lacks it | ✓ `VoiceInkCSVExportService.swift`, `ImportExportService.swift` | — | **VoiceInk advantage** |
| Retry/re-transcribe stale entry | ✓ within 14 days | unknown — depends on audio retention policy | P2 | Useful when model upgraded mid-history |
| Raycast extension reading local DB | ✓ third-party `carterm/wispr-flow` | ✗ no public DB schema doc | P3 | Possible community contribution; not first-party |

### I. Delight features

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| Sound effects | basic | ✓ 5-cue + custom-file override | — | **VoiceInk advantage** |
| Haptic feedback | ✗ | ✗ | P3 | Trackpad-only, niche |
| Streak tracking (daily/weekly) | ✓ | ✗ no `Streak*.swift` | P3 | Subscription-monetization signal; ill-fit for paid-once VoiceInk |
| Leaderboard (team words/week) | ✓ enterprise | ✗ | P3 | Anti-aligned with privacy positioning |
| 100-words/day challenge | ✓ | ✗ | P3 | Same |
| Achievement badges | ✓ during waitlist | ✗ | P3 | Same |
| Referral rewards | ✓ Pro discount | n/a | P3 | Different monetization (paid-once) |

### J. Privacy + on-device

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| Local audio processing | ✗ cloud | ✓ whisper.cpp / Parakeet / native Apple / MLX — all local | — | **VoiceInk core advantage** |
| Local LLM enhance | ✗ cloud | ✓ MLX (Qwen3 1.7B / 4B), Foundation Models, Ollama, LocalCLI | — | **VoiceInk core advantage** |
| Cloud transcription provider option | ✓ default | ✓ Deepgram, Soniox, Speechmatics, ElevenLabs, Mistral, xAI, Gemini, Groq, OpenAI-compatible — opt-in | — | **VoiceInk advantage** (choice) |
| Privacy mode (zero retention server-side) | ✓ toggle | n/a — local by default | — | Out of scope by design |
| Local history retention controls | ✓ keep / 24h / never | partial — history kept; no auto-purge setting | P2 | Cheap setting; pairs with privacy positioning |
| HIPAA / SOC2 / ISO certifications | ✓ Enterprise | ✗ | P3 | Not where VoiceInk plays; see §5 |
| "Don't include screen content" toggle | ✓ Privacy Mode disables context | ✓ `useScreenCapture` toggle per PowerMode | — | Parity |
| Password-field exclusion | ✓ explicit | unclear — depends on screencap behavior | P1 | Liability mitigation |

### K. Pricing / business model

| Feature | Wispr | VoiceInk |
|---|---|---|
| Free tier | 2k words/wk Mac/Win | unrestricted (paid-once) |
| Pro | $15/mo or $12/mo annual | $25 lifetime (per reviewer comparison) |
| Enterprise | custom | n/a in scope |
| Free trial | 14 days no-CC | n/a — paid-once |

VoiceInk's monetization is paid-once + open-source; gated features and trials are misaligned. Pricing-derived features (streaks, leaderboards, referrals) all sort to P3.

### L. Developer-specific

| Feature | Wispr | VoiceInk | Priority | Justification |
|---|---|---|---|---|
| Variable Recognition (pulls symbols from open editor) | ✓ JS/TS/Py/Java/Swift/C++/C/Rust/Go; up to 50 fn / 50 class / 100 var per block | ✗ | P1 | Cursor / Windsurf / VS Code share is high among VoiceInk's likely users; biggest cited dev win |
| File Tagging by voice ("tag index dot ts") | ✓ Cursor + Windsurf only (not VS Code) | ✗ | P1 | Pairs with Variable Recognition |
| camelCase / snake_case syntax handling | ✓ | partial — depends on prompt | P2 | Hard without LLM post-processing |
| Acronym handling | ✓ | partial — via dictionary | — | Parity |
| Linux native | ✗ Wispr is Win-or-Mac+WSL only | ✗ Mac-only | — | Out of scope |

---

## 3. Notable findings — design choices to learn from

**Good ideas worth stealing wholesale:**

- **Auto Cleanup as a 4-position dial, not a toggle.** This is the single highest-leverage UX change for the "enhance is bad" complaint — gives users control without forcing them to author prompts. Maps cleanly onto VoiceInk's `AIEnhancementService` if the prompt is parameterized by aggressiveness. (Apr 2026 changelog.)
- **"Undo AI edit" as a first-class action in history.** Trivial when you keep the raw transcript on the `Transcription` model (`Transcription.swift`). Massive trust boost.
- **Voice "press enter"** that strips itself from the output. Better than the auto-send-on-stop model VoiceInk has — keeps keyboard hands-off without burning the user when they didn't actually want to submit. Just a token-tail check before paste.
- **Shortcut bound to a *mouse* button.** Push-to-talk on Mouse4/Mouse5 is huge for users who have one hand on the mouse anyway; small ergonomic win, almost-zero engineering. (Constraint: `KeyboardShortcuts` dep doesn't expose mouse buttons cleanly — would need `CGEvent` global tap. Defer P2.)
- **Scratchpad fallback when paste fails.** When the focused field rejects paste (web app, sandbox, password manager), Wispr automatically opens its Scratchpad and pastes there. VoiceInk currently silently fails or warns; this is a strictly better UX for the same failure mode.
- **In-app categorization of recipient apps** (Email vs Work-msg vs Personal-msg vs Other). VoiceInk's PowerMode is *more configurable* but *more setup*. Shipping an out-of-box default profile with these 4 buckets pre-filled would massively shorten the on-ramp for new users without removing the power-user surface.

**Bad ideas to avoid:**

- **Periodic screenshot of active window** sent to cloud is the most-cited reason users churn off Wispr (the Reddit thread that "went viral" + the privacy concerns at law firms). VoiceInk's PowerMode `useScreenCapture` is opt-in per profile and stays local — preserve this. Don't normalize implicit screen capture.
- **Cloud-only architecture** is brittle: 8-10s cold-start lag (per reviewer benchmarks), reports of accuracy degrading post-trial, Trustpilot 2.7/5 with reliability complaints clustering after payment. VoiceInk's local-first is durable; do not regress.
- **Streaks / leaderboards / referrals.** These are SaaS-retention plumbing; baking them into a paid-once / OSS app feels off-brand and adds maintenance with no aligned business value.
- **"Help improve Flow" data sharing as an opt-out default.** Default-off is the better stance for VoiceInk's positioning.
- **Subscription word-quotas** (2k/wk free → unlimited Pro). Maps poorly onto local processing where there's no marginal cost per word. Don't.

**Surprising omissions in Wispr** (positioning angles for VoiceInk):

- **No dynamic snippet variables** ({{date}}, {{user}}, {{clipboard}}). Wispr explicitly says "Snippets insert static text only." If VoiceInk ships snippets *with* variables, that's a bullet-point win.
- **No bulk transcript export.** VoiceInk already has CSV export.
- **No multiple recorder UI styles.** VoiceInk's 3-style picker (Notch / Floating / Constellation) is unique.
- **No rich custom-prompt library.** Wispr's "snippets-as-prompts" is shallower than VoiceInk's `CustomPrompt` + `triggerWords` + `PredefinedPrompts`.
- **No built-in audio playback in history.** VoiceInk's `AudioPlayerView` + `AudioTimelineView` is actually more than Wispr offers.
- **No Linux native** (matters for the dev segment they target — and irrelevant to VoiceInk too).

---

## 4. Source list

Wispr Flow primary:
- [wisprflow.ai](https://wisprflow.ai/) — landing
- [wisprflow.ai/features](https://wisprflow.ai/features) — feature list
- [wisprflow.ai/pricing](https://wisprflow.ai/pricing) — tiers
- [wisprflow.ai/whats-new](https://wisprflow.ai/whats-new) — changelog (was `roadmap.wisprflow.ai`, redirected)
- [wisprflow.ai/post/personalized-style](https://wisprflow.ai/post/personalized-style) — Style system
- [wisprflow.ai/post/wispr-flow-vs-voiceink-2025](https://wisprflow.ai/post/wispr-flow-vs-voiceink-2025) — Wispr's own competitor framing (their version)
- [wisprflow.ai/comparison/superwhisper-alternative](https://wisprflow.ai/comparison/superwhisper-alternative) — Wispr's vs-Superwhisper page
- [wisprflow.ai/data-controls](https://wisprflow.ai/data-controls) — privacy claims
- [wisprflow.ai/developers](https://wisprflow.ai/developers) — dev positioning

Wispr Flow help-center docs:
- [What is Flow?](https://docs.wisprflow.ai/articles/2772472373-what-is-flow)
- [Setup Guide](https://docs.wisprflow.ai/articles/3152211871-setup-guide)
- [Starting your first dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation)
- [Use Flow hands-free](https://docs.wisprflow.ai/articles/6391241694-use-flow-hands-free)
- [How to use Command Mode](https://docs.wisprflow.ai/articles/4816967992-how-to-use-command-mode)
- [Smart Formatting & Backtrack](https://docs.wisprflow.ai/articles/5373093536-how-do-i-use-smart-formatting-and-backtrack)
- [Personal dictionary](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary)
- [Snippets](https://docs.wisprflow.ai/articles/5784437944-create-and-use-snippets)
- [Bulk import dictionary/snippets](https://docs.wisprflow.ai/articles/8955301725-how-do-i-bulk-import-for-dictionary-and-snippets)
- [Context Awareness](https://docs.wisprflow.ai/articles/4678293671-feature-context-awareness)
- [Privacy Mode & Data Retention](https://docs.wisprflow.ai/articles/6274675613-privacy-mode-data-retention)
- [Style setup](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles)
- [Scratchpad](https://docs.wisprflow.ai/articles/9618237082-using-the-scratchpad-to-save-and-edit-notes)
- [Cursor / VS Code / IDE integration](https://docs.wisprflow.ai/articles/6434410694-use-flow-with-cursor-vs-code-and-other-ides)
- [Variable Recognition](https://docs.wisprflow.ai/articles/8554805225-variable-recognition)
- [File Tagging](https://docs.wisprflow.ai/articles/9805771321-file-tagging)
- [Linux/WSL/terminal](https://docs.wisprflow.ai/articles/6478598909-using-flow-with-linux-wsl-and-terminal-applications)
- [Keyboard shortcuts](https://docs.wisprflow.ai/articles/2612050838-supported-unsupported-keyboard-hotkey-shortcuts)
- [Microphone setup](https://docs.wisprflow.ai/articles/4351452717-troubleshooting-mic-issues)
- [Discreet microphone usage](https://docs.wisprflow.ai/articles/9192039587-using-wispr-flow-discreetly-microphone-guide)
- [Referral program](https://docs.wisprflow.ai/articles/6496688316-how-to-find-your-referral-link)

Reviews / comparisons:
- [Wispr Flow review — tldv.io](https://tldv.io/blog/wisprflow/)
- [WisprFlow Review: I write code at 179 WPM — zackproser](https://zackproser.com/blog/wisprflow-review)
- [Wispr Flow review tutorial — Samantha Kasbrick](https://www.samanthakasbrick.com/blog/wispr-flow-review-tutorial)
- [Why I cancelled my Wispr Flow subscription — Ryan Shrott](https://medium.com/@ryanshrott/why-i-cancelled-my-wispr-flow-subscription-and-what-im-using-instead-d783433f4411)
- [Wispr Flow Trust Gap — Ryan Shrott](https://medium.com/@ryanshrott/the-wispr-flow-trust-gap-why-reliability-matters-more-than-hype-in-2026-c7dd55392408)
- [Best Mac dictation apps 2026 — Ryan Shrott](https://medium.com/@ryanshrott/best-mac-dictation-apps-in-2026-dictaflow-wispr-flow-superwhisper-and-apple-dictation-compared-11911c671817)
- [Wispr Flow review — Cult of Mac](https://www.cultofmac.com/reviews/wispr-flow-mac-speech-to-text-app-review)
- [Wispr Flow vs Superwhisper — getvoibe](https://www.getvoibe.com/resources/wispr-flow-vs-superwhisper/)
- [Wispr Flow review — Voibe](https://www.getvoibe.com/resources/wispr-flow-review/)
- [9 best Wispr Flow alternatives — getvoibe](https://www.getvoibe.com/blog/wispr-flow-alternatives/)
- [Wispr Flow PH reviews](https://www.producthunt.com/products/flow-voice/reviews)
- [Wispr Flow review — eesel.ai](https://www.eesel.ai/blog/wispr-flow-review)
- [VoiceInk on openalternative.co](https://openalternative.co/voiceink)
- [VoiceInk Wispr Flow alternative page](https://tryvoiceink.com/wispr-flow-alternative)
- [Best AI dictation tools — afadingthought](https://afadingthought.substack.com/p/best-ai-dictation-tools-for-mac)

Other:
- [Whisper Flow (whisperflow.app)](https://whisperflow.app/) — clone product
- [Wispr Flow on Raycast Store](https://www.raycast.com/carterm/wispr-flow)
- [Wispr Flow App Store listing](https://apps.apple.com/us/app/wispr-flow-ai-voice-keyboard/id6497229487)
- [Whisper Flow App Store listing](https://apps.apple.com/us/app/whisper-flow-ai-voice-keyboard/id6754533870)

---

## 5. VoiceInk strengths Wispr Flow doesn't have (positioning angles)

Pull these forward in marketing + keep front of mind in W12 prioritization (don't regress them while pursuing parity):

1. **100% local processing — audio + transcription + LLM enhance never leave the machine.** Wispr is cloud-only. This is the single biggest differentiator for legal / medical / finance / NDA work. Wispr's *own* viral Reddit thread was about screenshots-to-cloud. VoiceInk's `useScreenCapture` is opt-in *and* OCR-locally-then-prompted, not raw-image-uploaded.
2. **Configurable PowerMode — per-app and per-URL profiles** vs Wispr's fixed 4 categories. App-specific prompt + transcription model + language + AI provider + autoSendKey + emoji icon. Far more powerful for power users; just needs better defaults for new users.
3. **3 recorder UI styles** — Halo Notch, Halo Floating, Constellation chip cluster. Wispr ships one Flow Bar.
4. **5-cue customizable sound system** with per-cue `.wav` overrides. Wispr has a single "ping."
5. **Rich custom-prompt library** with `triggerWords`, predefined templates, enable/disable per prompt. Wispr's prompt surface is a few "Snippets-as-prompts" examples.
6. **Multi-provider transcription choice** — whisper.cpp, Parakeet (FluidAudio), native Apple Speech, plus 9 cloud providers. Wispr is cloud-only with no choice.
7. **Multi-provider LLM enhance** — MLX, Apple Foundation Models, Ollama, LocalCLI. Wispr is cloud-only.
8. **Built-in audio playback + waveform timeline of past dictations** (`AudioPlayerView`, `AudioTimelineView`). Wispr only offers `.wav` download.
9. **Bulk CSV import/export** of dictionary, replacement rules, full transcript history. Wispr lacks bulk transcript export entirely.
10. **Adaptive glass design vocabulary** (W8) — visually richer than Wispr's flat bar.
11. **Open source / GPLv3** — community trust + auditability vs Wispr's closed cloud stack. Already cited as a top reason on alternatives sites.
12. **Paid-once $25** vs $144/yr. Massive lifetime-cost gap; aligns with the "tools you own" / Raycast / Sublime archetype.
13. **No telemetry / no usage dashboards / no leaderboards** — anti-surveillance positioning. Wispr's enterprise dashboard is something privacy-focused users actively avoid.

These strengths set the bar: VoiceInk is *the* private, configurable, local Mac dictation app. W12's parity work should add Wispr's missing UX without compromising any of items 1–13.

---

## 6. Implementation pointers for W12 (not a plan — just pointers)

To make the W12 plan-writer's life easier, here's where each P0/P1 lands in the codebase:

| Feature | Add / extend | Existing primitives to reuse |
|---|---|---|
| Voice Snippets (P0) | new `Models/Snippet.swift`, new `Services/SnippetService.swift`, new `Views/Snippets/` | `WordReplacement.swift` is the closest analogue; SwiftData is already in use |
| Command Mode (P0) | new `Services/CommandModeService.swift`, hotkey in `HotkeyManager.swift`, recorder mode in `RecorderUIManager.swift` | `SelectedTextService.swift` (read), `AIEnhancementService.swift` (rewrite), `CursorPaster.swift` (replace selection) |
| Auto Cleanup levels (P0) | parameterize `AIEnhancementService.swift` enhance prompt with `aggressiveness: .none/.light/.medium/.high`, expose as enum on `PowerModeConfig` (replaces / supplements `isAIEnhancementEnabled`) | `TranscriptionAutoCleanupService.swift` for the lightest tier |
| Diff view + Undo AI edit (P0) | extend `Transcription.swift` to keep raw + enhanced; surface in `TranscriptionDetailView.swift`; "Undo" writes raw back as the canonical text | `WordDiffEngine.swift` already produces word-level diffs |
| Hands-free + auto-stop + voice "press enter" (P0) | new `Services/HandsFreeSessionService.swift` with VAD on `CoreAudioRecorder` tail; tail-token stripping in pre-paste step | `Recorder.swift`, `CoreAudioRecorder.swift`, `CursorPaster.swift` |
| Scratchpad (P0) | new `Views/Scratchpad/`, new window controller, SwiftData `Note` model with versioning | reuse `MiniWindowManager` patterns; `AudioPlayerView` already shows the right window-management vocabulary |
| Backtrack mid-sentence corrections (P1) | prompt update only in `PredefinedPrompts.swift` / `AIPrompts.swift` | — |
| Personalized styles presets (P1) | seed PowerMode profiles for Email / Work-msg / Personal-msg / Other on first run; offer 4 tone variants per | `PowerModeConfig.swift`, `CustomPrompt.swift` |
| Recipient/conversation-aware tone (P1) | extend `ScreenCaptureService.swift` to OCR top-K-words near cursor and pass as context to enhance | `ActiveWindowService`, `BrowserURLService` |
| Auto-pause in banking/financial apps (P1) | exclusion list of bundle IDs in `PowerMode/ActiveWindowService.swift` | — |
| Variable Recognition / File Tagging (P1) | new `Services/EditorContextService.swift` reading AX tree of Cursor / Windsurf / VS Code | `ActiveWindowService.swift` |
| Onboarding flow (P1) | new `Views/Onboarding/` shown when `hasCompletedOnboarding == false` | `PermissionsView.swift` is the natural step 2; mic test = `AudioInputSettingsView`-derived |
| First-run mic test, tutorial, "Saved!" stickers (P2) | — | pairs with onboarding |
| Local history retention controls (P2) | settings UI + scheduled cleanup | `LastTranscriptionService`, `ImportExportService` |
| Mouse-button hotkeys (P2) | global `CGEvent` tap | not blocked by `KeyboardShortcuts` dep |
| Settings search (P3 — bonus over Wispr) | — | `SettingsView.swift` |
| Snippet variables (P3 — bonus over Wispr) | template engine in `SnippetService` | — |

## 7. Open questions for the plan-writer

1. **Snippet activation**: does the trigger phrase get matched *during* transcription (intercept in pre-paste filter) or *post*-transcription (find-and-replace before paste)? Wispr does the latter; the former gives more natural integration but is harder. **Recommendation: post-transcription, in `AIEnhancementOutputFilter` or a dedicated `SnippetExpansionFilter` running before paste.**
2. **Command Mode hotkey conflict**: Wispr uses `Fn+Ctrl` Mac. VoiceInk's `Fn` is push-to-talk. Need a second modifier or a chord — possibly `Fn+E` ("edit"). Defer to UX call.
3. **Auto Cleanup level granularity**: 4 levels (None / Light / Medium / High) or 3 (Off / Light / Aggressive)? Wispr's 4 maps onto distinct prompts; VoiceInk could simplify. **Recommendation: ship 4 to match Wispr's mental model, hide one if it underperforms.**
4. **Raw-transcript persistence**: store on `Transcription` model as second field, or separate table keyed by transcription ID? Cheaper to store inline; storage cost negligible.
5. **Scratchpad scope**: do we ship versioning on day 1 (Wispr has 50-version history with diff/restore), or MVP without? **Recommendation: MVP without; defer versioning to W13+.**
6. **PowerMode preset seeding**: seed Email / Work-msg / Personal-msg / Other profiles for new installs only, or also offer existing users a one-click "import Wispr-style defaults"? Latter is friendlier.
7. **Banking-app exclusion list**: hand-curated list of bundle IDs, or community-sourced? Hand-curated for MVP (Banking, Wells Fargo, Chase, Mint, 1Password, Bitwarden, etc.). Confirm with user before shipping — list is maintenance burden.
8. **Wispr "auto-detect language mid-sentence"** is a transcription-engine feature, not an app feature. Whether VoiceInk gets this depends on Parakeet / whisper.cpp roadmap, not on W12 work. Mark out-of-scope for W12.
