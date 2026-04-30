# W12.C — Voice Snippets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.
>
> **Phase 2 packet — third (parallelizable with W12.A and B; sits on the most isolated surface).** W12.C closes the text-expansion gap. aText / Raycast Snippets users won't switch without trigger→expansion. Wispr Flow has it; VoiceInk has zero coverage today (`WordReplacement` is misspell→correction only, not phrase→block).

**Date:** 2026-04-30
**Scope:** Add a SwiftData-backed `Snippet { id, trigger, expansion, tags, isEnabled, createdAt, updatedAt }` model + `SnippetExpansionService` that runs a pre-enhance, word-boundary regex pass over the raw transcript and splices expansions in BEFORE the enhance call. Wire a settings surface (`SnippetsSettingsView`) for CRUD + extend `ImportExportService` to round-trip the table alongside existing PowerMode / CustomPrompt / dictionary exports. Register a sidebar entry (`ViewType.snippets`) so users can find the surface. First-run ships zero default snippets — pure user opt-in.

**Sources of truth:**
- R3 audit (the WHY for snippets as a P0): `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` §1 P0-1, §2.E "Voice Snippets / text expansion", §6 implementation pointers ("new `Models/Snippet.swift`, new `Services/SnippetService.swift`, new `Views/Snippets/`"), §7 open question 1 (recommended post-transcription pre-paste).
- Master plan §0 Q4=c (locked: pre-enhance regex on raw transcript) + §3 W12.C scope: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`.
- W12.A shape reference (sibling): `docs/superpowers/plans/W12A-auto-cleanup-levels.md`.
- W11.A pipeline shape: `docs/superpowers/plans/W11A-pipeline-fixes.md`.
- Aesthetic spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §3.3 (W5 SettingsCard idiom; new `SnippetsSettingsView` uses it directly).
- `Models/CustomPrompt.swift` — Codable model pattern reference for the export format.
- `Models/VocabularyWord.swift` + `Models/WordReplacement.swift` — SwiftData `@Model` shape reference.

**Goal:** users define short triggers (e.g. `;sig`) and get back full expansions (e.g. their email signature block) on every dictation. No behavior change for users who never create a snippet. Pre-enhance: each active trigger gets a word-boundary regex replace; the enhance call sees the EXPANDED text. No phrase-level / multi-word triggers, no variable substitution, no per-app sets, no collision UI in v1.

---

## Prelude — packet shape + commit etiquette

W12.C is **one logical packet** spanning a new SwiftData @Model + new service + new settings view + ImportExportService extension + Schema registration + ContentView sidebar entry. Per CLAUDE.md `feedback_skip_per_packet_builds.md` the lead does ONE integration `make local` at merge time and ONE squashed `feat:` commit.

- `docs(plans): W12C — voice snippets plan` — this file. Lands FIRST, before any code, after lead sign-off.
- `feat(snippets): W12C — voice snippets pre-enhance expansion + settings UI` — code edits. **Single squashed commit** at merge time.

Coder leaves edits uncommitted; lead handles both commits. No per-task build is run during the packet; the integration `make local` runs once at the end (Task 10).

---

## Pre-merge ground-truth gate (NONE — net-new feature)

Unlike W11.A (perf baseline) and W12.A (qualitative cleanup-level reference), W12.C is a **net-new feature with zero coverage today**. There is no regression baseline to capture. The packet is purely additive — no existing user flow is modified except the pre-enhance hook, which is gated on `snippets.isEmpty == false` (Migration policy #2 below).

The lead may optionally ask the user to draft 2-3 example snippets ahead of merge (e.g. `;sig` → email signature, `;addr` → mailing address, `;date` → "today's date" placeholder string) so post-merge verification has a concrete sample set, but this is purely a usability nice-to-have.

---

## Architecture (W12.C change list — T1 through T9)

```
Task   Where                                                          Risk
─────  ─────────────────────────────────────────────────────────────  ─────
T1     Define Snippet @Model + validation + tag struct                 LOW
       VoiceInk/Models/Snippet.swift (NEW)                              — additive SwiftData type.

T2     Register Snippet.self in the SwiftData schema                   MED
       VoiceInk/VoiceInk.swift (Schema([...]) array)                    — schema migration boundary.
       Note: persistent + in-memory containers BOTH need it.

T3     New SnippetExpansionService                                     MED
       VoiceInk/Services/SnippetExpansionService.swift (NEW)            — regex word-boundary semantics
                                                                          + cache invalidation.

T4     Splice the service into TranscriptionPipeline                   MED
       VoiceInk/Transcription/Engine/TranscriptionPipeline.swift        — must remain a no-op when
                                                                          the snippet table is empty.

T5     New SnippetsSettingsView (CRUD)                                  LOW
       VoiceInk/Views/Snippets/SnippetsSettingsView.swift (NEW)
       VoiceInk/Views/Snippets/SnippetEditorSheet.swift (NEW)

T6     Add Snippets sidebar entry                                       LOW
       VoiceInk/Views/ContentView.swift                                 — additive ViewType case.

T7     Extend ImportExportService for [Snippet]                         MED
       VoiceInk/Services/ImportExportService.swift                      — VoiceInkExportedSettings shape
                                                                          adds a new optional field.

T8     Register feature default(s)                                      LOW
       VoiceInk/AppDefaults.swift                                       — debug toggle (off by default,
                                                                          see Migration policy #11).

T9     Static checks + post-merge verification protocol                 —
       (verification only, no file edits)
```

**Combined target:** users see a "Snippets" sidebar entry. CRUD surface lets them add `;sig → ...long signature block...`. They dictate "send this off thanks ;sig". Word-boundary regex matches `;sig`, expands inline, enhance runs on the expanded text, paste lands the expanded text in the cursor field. No model swap, no SPM dep, no deployment-target bump.

---

## Tech Stack

Swift 5.x, SwiftUI, SwiftData, AppKit. **No SPM additions.** macOS 26.0 deployment target (post-W11.B).

T3's regex pass uses `NSRegularExpression` (SwiftData and Foundation already imported app-wide; `Regex` literals are an option but `NSRegularExpression` gives cleaner per-trigger compile + error reporting and matches the existing surface in `WordReplacementService.swift` / `WhisperTextFormatter.swift`). T5's CRUD surface uses standard `@Query` + `@Environment(\.modelContext)` per the SwiftData idiom already used in `DictionarySettingsView.swift`.

Build via `make local` (~3 min cold). One integration build at Task 10, per CLAUDE.md cadence.

---

## Spec refs

- Research: `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` §1 (P0-1 — Voice Snippets / text expansion), §2.E (Voice commands / output behaviors — "Voice Snippets / text expansion: VoiceInk has no model, no UI, no service"), §3 ("No dynamic snippet variables — Wispr Flow explicitly says snippets insert static text only" → variables out of scope here per master plan; v1 plain text), §6 implementation pointers, §7 open question 1.
- Master plan: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` §0 Q4=c (locked: pre-enhance regex on raw transcript) + §3 W12.C scope (3-paragraph sketch).
- Aesthetic spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §3.3 (SettingsCard / SettingsRow vocabulary).
- W11A precedent for plan shape + commit etiquette + Codable forward-compat pattern.
- W12A precedent for plan shape + sibling-packet migration policy section.

---

## CLAUDE.md cadence rules respected

- **Single integration build at merge time.** No `make local` per task; one full build at Task 10. Per `feedback_skip_per_packet_builds.md`.
- **One squashed commit at merge time.** No per-task commits during execution.
- **Sentence-fragment doc-comments, no PR-reference comments, no obvious-explainer comments, no emojis in code.** Existing `🦾` log markers in `MLXProvider.swift` / `AIEnhancementService.swift` / `TranscriptionPipeline.swift` are W6+W11 instrumentation; SnippetExpansionService adds `🦾 snippets: expanded N triggers` to the same log surface for parity.
- **No new test files.** Per master plan §0 Q10=defer, validation is build-only.
- **No SPM additions, no deployment-target bump.**
- **No pbxproj edits.** New files under `VoiceInk/` auto-include via Xcode 16 PBXFileSystemSynchronizedRootGroup.

---

## File structure

### New files

- `VoiceInk/Models/Snippet.swift` (~80 LOC) — `@Model final class Snippet { id, trigger, expansion, tags, isEnabled, createdAt, updatedAt }`. Tags stored as `[String]` via SwiftData's default collection encoding (already used implicitly elsewhere — see Migration policy #4). Static `validate(trigger:)` + `validate(expansion:)` helpers used by the editor sheet.

- `VoiceInk/Services/SnippetExpansionService.swift` (~120 LOC) — `@MainActor final class SnippetExpansionService`. Single shared instance (`.shared`). Caches the active snippet table on first call + invalidates on SwiftData insert/update/delete via NotificationCenter (`.NSManagedObjectContextDidSave` equivalent for SwiftData — see Migration policy #7). Public API: `expand(text: String) -> (expanded: String, expandedCount: Int)`. Private: `compileRegex(for: Snippet) -> NSRegularExpression?`.

- `VoiceInk/Views/Snippets/SnippetsSettingsView.swift` (~180 LOC) — `ScrollView { LazyVStack(spacing: 16) { SettingsCard(...) { ForEach(snippets) { row } + Add button } } }`. Mirrors `SettingsView.swift`'s vocabulary. Uses `@Query` for the snippet list. Each row: trigger pill + truncated expansion preview + tags chip + isEnabled toggle + Edit / Delete buttons. Empty state: gentle copy ("Add your first snippet to expand triggers like `;sig` into long-form text.").

- `VoiceInk/Views/Snippets/SnippetEditorSheet.swift` (~140 LOC) — Modal sheet for Add / Edit. Two-field form (trigger + multiline expansion) + tags chip strip + isEnabled toggle. Validates on Save: non-empty trigger, must match `^[A-Za-z0-9;_./@-]{1,32}$` (Migration policy #6), unique vs the existing table (case-sensitivity per Migration policy #5). On collision, surface inline error message; do not save.

### Modified files

- `VoiceInk/VoiceInk.swift` — T2. Add `Snippet.self` to the Schema array at lines 53-57. Persistent and in-memory container init paths both need the `Snippet.self` registration. Lines 53-57 (main schema), 248 (`dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])` — extend to `[VocabularyWord.self, WordReplacement.self, Snippet.self]` since snippets share the same persistence concern as dictionary entries; or place under a third config — see Migration policy #3). ~+1-3 LOC.

- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` — T4. Insert a single call between line 99 (post WordReplacement) and line 101 (pre AVURLAsset duration block). Specifically:
  ```swift
  text = WordReplacementService.shared.applyReplacements(to: text, using: modelContext)
  logger.notice("📝 WordReplacement: \(text, privacy: .public)")

  // W12.C: pre-enhance snippet expansion. No-op when the snippet table is
  // empty. Service caches the active snippet list in memory; cache invalidates
  // on insert/update/delete via NotificationCenter.
  let snippetResult = SnippetExpansionService.shared.expand(text: text, modelContext: modelContext)
  if snippetResult.expandedCount > 0 {
      text = snippetResult.expanded
      logger.notice("🦾 snippets: expanded \(snippetResult.expandedCount, privacy: .public) triggers")
      logger.notice("📝 Snippet expansion: \(text, privacy: .public)")
  }
  ```
  This expands the trigger BEFORE `transcription.text = text` (line 104) so both the saved raw history record AND the enhance call see the same expanded text. ~+8 LOC.

- `VoiceInk/Services/ImportExportService.swift` — T7. Extend `VoiceInkExportedSettings` struct (line 38-47) with a new optional field `let snippets: [SnippetExportData]?`. Define a sibling `SnippetExportData: Codable` struct (sibling of `VocabularyWordData` at line 33-36) — encodes trigger / expansion / tags / isEnabled / createdAt / updatedAt as plain values. The `Snippet` SwiftData @Model is NOT directly Codable (SwiftData @Model + Codable doesn't compose cleanly per Migration policy #8); the export struct is a transit type. Export path: fetch snippets via `FetchDescriptor<Snippet>` and map → `SnippetExportData`. Import path: insert each `SnippetExportData` into modelContext as a new `Snippet`, dedupe-by-trigger against the existing table (skip with log on conflict). Existing fields untouched. ~+50 LOC.

- `VoiceInk/Views/ContentView.swift` — T6. Add `case snippets = "Snippets"` to the `ViewType` enum (after `.dictionary`, before `.settings`); add icon `"square.text.square"` (or `"text.cursor"` — coder discretion within SF Symbols catalog) in the `icon` switch; add `case .snippets: SnippetsSettingsView()` route in `detailView(for:)`. Sidebar entry is always visible (no `powerModeUIFlag`-style gate — snippets is opt-in by being empty by default, not by feature flag). ~+5 LOC.

- `VoiceInk/AppDefaults.swift` — T8. Optionally register `"DebugLogSnippetExpansion": false` if T3 ships the verbose-expansion-log debug toggle (Migration policy #11). If the coder elects to skip the debug toggle (rare; ships always-on), no edit needed. ~0-1 LOC.

### Untouched (explicit list — coder do NOT drift)

- `VoiceInk/Services/WordReplacementService.swift` — UNTOUCHED. Snippets are a separate concern (phrase trigger → expansion vs. misspell → correction). No shared call-site even though the regex semantics are similar; both run on `text` independently in the pipeline. **WordReplacement runs FIRST (line 99), then snippet expansion (T4 insertion).** Order matters: a user could have a misspelling rule that maps `siggy → ;sig` and expect the snippet to fire — order it dictionary→snippet to support that flow.
- `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift` — UNTOUCHED. The service operates on the post-snippet-expanded text passed in via the existing `enhance(_:)` API. The `<TRANSCRIPT>` wrap inside the enhance system message wraps already-expanded text — the model never sees `;sig`. Per master plan §0 Q4=c, the LLM stays blind to trigger logic.
- `VoiceInk/Services/AIEnhancement/MLXProvider.swift`, `AFMProvider.swift`, `AIService.swift` provider implementations — UNTOUCHED.
- `VoiceInk/Models/Transcription.swift` schema — UNTOUCHED. `Transcription.text` already holds the post-WordReplacement-and-now-post-snippet-expansion raw transcript. No new column.
- `VoiceInk/Models/CustomPrompt.swift` — UNTOUCHED (referenced as a Codable pattern; not modified).
- `VoiceInk/Models/VocabularyWord.swift`, `WordReplacement.swift` — UNTOUCHED.
- `VoiceInk/Views/Settings/SettingsView.swift` — UNTOUCHED. Snippets gets its own sidebar entry, NOT a section inside Settings. Reasoning: aText / Raycast users expect snippets to be a top-level surface they can navigate to directly.
- `VoiceInk/Views/Dictionary/DictionarySettingsView.swift` — UNTOUCHED. Tempting to bundle snippets into the Dictionary surface (similar CRUD vocabulary) but Dictionary's audience is "speech recognition vocabulary tuning" while Snippets is "text expansion". Different mental models → different sidebar entries. Per R3 §6.
- `VoiceInk/PowerMode/PowerModeConfig.swift` — UNTOUCHED. Per-app snippet sets are explicitly out of scope (master plan §3 W12.C "Out of scope" list).
- `VoiceInk/Models/AIPrompts.swift` — UNTOUCHED. Snippet expansion happens UPSTREAM of the prompt build; the prompt body is unaffected.
- All test files (`VoiceInkTests/*.swift`) — W12.C ships no new tests. Per master plan §0 Q10.

---

## Migration policy (resolves ambiguity for each design point)

The lead pinned the following architecture decisions for this packet. Restated as the authoritative ruleset for the coder.

1. **No per-app / per-PowerMode snippet sets in v1.** All snippets are global; the same trigger fires regardless of active app or PowerMode. Per master plan §3 W12.C "Out of scope". Rationale: matches Wispr Flow's v1 ("global snippet table"); per-app sets add a UX burden that doesn't pay off until the user's snippet count exceeds ~20-30. Follow-up if user requests.

2. **Pre-enhance hook is additive — gated on `!snippets.isEmpty`.** The TranscriptionPipeline insertion at T4 calls `SnippetExpansionService.shared.expand(...)` unconditionally; the service short-circuits with `(text, 0)` when the snippet cache is empty. So no measurable cost when the user has no snippets defined. Concrete contract: when `expandedCount == 0`, the call must NOT modify `text` and must NOT emit the `🦾 snippets: …` log line. The pipeline already-pristine code path should be byte-identical to today's behavior under that condition.

3. **SwiftData schema placement: dictionary store config.** The existing `createPersistentContainer` in `VoiceInk.swift` splits the schema across two ModelConfiguration blobs — `transcriptSchema = Schema([Transcription.self])` and `dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])`. Snippet aligns with the dictionary store (lightweight, user-curated, no audio refs); add `Snippet.self` to the dictionary schema. **Both** `createPersistentContainer` AND `createInMemoryContainer` need the addition. **AND** the top-level `Schema([Transcription.self, VocabularyWord.self, WordReplacement.self])` at line 53 needs `Snippet.self`. Coder must edit all three locations; missing one causes a runtime "model not found" crash.

4. **Tags storage: `[String]` via SwiftData default codable encoding.** SwiftData @Model auto-Codables `[String]` properties via the underlying Core Data store. No custom transformer needed. Confirmed pattern: WordReplacement uses `var originalText: String` (single string), but more complex tag-array shapes are supported across SwiftData. If the coder hits a "non-Codable type" Xcode warning, fall back to a comma-joined `String` storage with a computed `tags: [String]` view (split/join). The fallback adds ~10 LOC; flag for the lead if needed.

5. **Trigger case-sensitivity: case-sensitive matching, case-sensitive uniqueness.** A trigger `;Sig` is distinct from `;sig`. The regex compiled in T3 does NOT include `.caseInsensitive` flag. The validation in T1's `validate(trigger:)` rejects a new trigger if the existing table has the SAME-CASE trigger (case-sensitive `==` comparison). Rationale: voice triggers are typed by the user as part of their dictation; the speech recognizer's casing on the trigger is what the user sees in the raw transcript, and case-sensitive matching gives the user fine control (e.g. `;HTTP` → "HTTP/1.1" and `;http` → "Hypertext Transfer Protocol" can both coexist). Open question for lead: flip to case-insensitive if user requests after dogfood.

6. **Trigger validation: 1-32 chars matching `^[A-Za-z0-9;_./@-]{1,32}$`.** Permits the common Wispr / aText / TextExpander conventions (`;sig`, `:date`, `/code`, `@addr`, `email_sig`, etc.) plus alphanumeric pure tokens. Rejects whitespace inside the trigger (since the regex word-boundary `\b` semantics break for whitespace-containing triggers — see Migration policy #9), rejects backslash / quotes / brackets (regex injection risk; sanitization tax). Length cap 32 keeps the in-memory regex compile cheap. Validation surfaces inline in the editor sheet on Save attempt; never silently truncates. **Trigger MUST not be empty** — covered by `{1,32}`.

7. **Cache invalidation: SwiftData persistent-history notification + manual refresh.** SwiftData posts a `ModelContext.didSave` notification (named varies by macOS version; coder uses the `NotificationCenter.default` observer pattern that DictionarySettingsView already uses, OR the `@Query` reactive idiom which auto-fires on table change). For SnippetExpansionService — which runs OUTSIDE the SwiftUI render loop — the cleanest path is: invalidate cache on every `expand(text:modelContext:)` call by checking a lightweight version counter (per-call `FetchDescriptor<Snippet>().fetchCount` is fine; SwiftData fetch is fast enough for this size). Alternative: register an `NSNotification.Name.NSManagedObjectContextDidSave` observer at service init. Coder picks; recommend the version-counter / fetchCount approach since it's simplest and SnippetExpansionService stays free of NotificationCenter coupling.

   **Concrete rule:** the service's `expand(...)` MUST always reflect snippets created or updated in the same app session. There is no "cache-staleness window" the user could observe. If implementing the version-counter approach, the counter is incremented in `SnippetEditorSheet.save()` and `SnippetsSettingsView` row delete handlers via a service-side `invalidateCache()` call.

8. **Snippet @Model + Codable separation.** SwiftData @Model classes don't auto-conform to Codable cleanly; attempting `final class Snippet: Codable` triggers compiler errors around init / store-only properties. The export shape (T7) uses a sibling `SnippetExportData: Codable` struct with plain value-typed fields. Coder maps `Snippet` ↔ `SnippetExportData` explicitly in `ImportExportService`. This is the same dance VocabularyWord uses (`VocabularyWordData: Codable` at line 33-36 of `ImportExportService.swift`). **Do NOT attempt to retrofit @Model to Codable.**

9. **Word-boundary regex: `\b<trigger>\b` with token-level escaping.** The compiled regex per snippet is `NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: trigger) + "\\b", options: [])`. Edge cases:
   - Triggers starting with a non-word character (`;sig`, `:date`, `/code`, `@addr`) — `\b` matches the boundary BETWEEN `;` (non-word) and `s` (word) only if the preceding char is whitespace or word-char. NSRegularExpression's `\b` is "transition between word char and non-word char (or string boundary)". For `;sig`, the leading `;` is non-word, so `\b` matches between the preceding char (typically space) and `;` ONLY if the preceding char is a word-char — which fails for "send this off ;sig" (space preceding, non-word). **Fix:** use `(?:\\b|^|(?<=\\s))` as the leading anchor, and `(?:\\b|$|(?=\\s))` as the trailing anchor. Document the exact pattern in `SnippetExpansionService.compileRegex(for:)` with a one-paragraph doc-comment citing this plan.
   - Triggers ending with a non-word character — symmetric handling via the trailing anchor.
   - Triggers that are pure alphanumeric (`sig`, `addr`) — both anchors collapse to `\b` cleanly. Test cases for the coder to mentally verify per Migration policy #9.

   **Concrete rule:** the regex matches a trigger embedded in any whitespace-delimited or string-edge context. It does NOT match a trigger embedded inside another word (e.g. `;sig` inside `assignmenT;sigh` — `;sig` in that context would match if the `\b` boundary fires; for the leading anchor pattern above, it does not match because the char preceding `;` is `T` (word) and the char preceding `s` is `;` (non-word) but neither is a whitespace nor string-edge — pattern correctly skips). Verify in T3.5 with a small set of mental test cases logged via `print(...)` debug-only (stripped before commit).

10. **Multiple expansions per dictation: counted, not capped.** A single `expand(...)` call MAY fire multiple triggers (e.g. "send to ;addr signed ;sig"). Each trigger is replaced via the regex's `stringByReplacingMatches(...)` call; the loop iterates over all active snippets in `sortOrder` (insertion order, by `createdAt` ascending). The reported `expandedCount` is the sum across all triggers. **No upper bound** on expansion count per call. Risk: an expansion that itself contains another snippet's trigger does NOT recursively expand (the regex pass is single-pass). Acceptable v1; flag for follow-up if user requests recursive expansion.

11. **Verbose log toggle (`DebugLogSnippetExpansion`).** OPTIONAL. If included, controls whether `🦾 snippets: expanded N triggers` AND a follow-up `📝 Snippet expansion: <full text>` line are logged on every successful expansion. Default false → only the count line fires (matches Migration policy #2's no-op-when-empty contract). When true, both lines fire. Useful for the user to debug a misbehaving trigger. Coder may ship without this toggle (T8 then becomes a 0-LOC edit); recommend including it for symmetry with `DebugLogShortPath` from W11.A2.

12. **First-run defaults: zero default snippets.** No seeded `;sig` / `;addr` / etc. The user explicitly opts in by adding their first snippet. Rationale: any seeded default would land in the user's expanded text on every dictation containing that token (e.g. seeded `;sig` would expand for ANY dictation containing `;sig`, even if the user wanted that literal string). User opt-in eliminates surprise. Per the team-lead message + master plan §3 W12.C scope.

13. **Collision handling: editor-sheet save rejects, no UI for resolving.** When the user attempts to add a snippet whose trigger duplicates an existing one (case-sensitive per Migration policy #5), the editor sheet's Save button shows an inline error ("Trigger `;sig` is already in use. Pick a different trigger or edit the existing snippet."). No "merge" or "replace" UI. The user can either pick a new trigger or close the sheet, navigate to the existing snippet, and edit it. v1 keeps this simple. Out of scope: trigger-collision warning in a multi-snippet bulk import. The import path (T7) silently skips a colliding-trigger import row and logs the skip via `print(...)`.

14. **No new SPM deps. No deployment-target bump.** Already at 26.0 from W11.B. `NSRegularExpression` available since macOS 10.7 — comfortably supported.

15. **No emoji in new code.** Existing `🦾` log markers stay verbatim; new ones may add `🦾 snippets: …` to the existing surface (W6+W11 instrumentation; documented exception). All NEW Swift files are emoji-free per CLAUDE.md.

16. **Out of scope (master plan + team-lead message):** phrase / multi-word triggers, variable substitution (`${date}`, `${cursor}`, etc.), per-app snippet sets, Power Mode integration, trigger-collision merge UI, recursive expansion, SwiftData CloudKit sync, snippet usage counters / analytics, "smart" trigger suggestions. All deferred — see §Out of scope below.

---

## Tasks

### Task 0 — Audit + read references

**Files:** none (read-only).

- [ ] **Step 0.1 — Confirm SwiftData schema layout**

```bash
grep -n "Schema\|@Model\|ModelConfiguration\|persistentContainer\|inMemoryContainer" VoiceInk/VoiceInk.swift | head -25
```

Expected: `Schema([Transcription.self, VocabularyWord.self, WordReplacement.self])` at ~line 53; `transcriptSchema = Schema([Transcription.self])` at ~line 239 / 275; `dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self])` at ~line 248 / 283. T2 needs to add `Snippet.self` to all three locations.

- [ ] **Step 0.2 — Confirm pipeline insertion point**

```bash
grep -n "WordReplacementService\|isEnhancementEnabled\|isConfigured" VoiceInk/Transcription/Engine/TranscriptionPipeline.swift | head -20
```

Expected: `WordReplacementService.shared.applyReplacements` at ~line 98, `enhancementService.isEnhancementEnabled` at ~line 124. T4 inserts the snippet expansion call between line 99 (post WordReplacement) and line 101 (pre AVURLAsset duration block). Confirm the line numbers are still accurate at coder time; insertion point is "right after WordReplacement, before the duration computation".

- [ ] **Step 0.3 — Confirm ImportExportService Codable shape**

```bash
grep -n "VoiceInkExportedSettings\|VocabularyWordData\|FetchDescriptor" VoiceInk/Services/ImportExportService.swift | head -20
```

Expected: `struct VoiceInkExportedSettings: Codable` at ~line 38 with optional fields (`vocabularyWords: [VocabularyWordData]?`, etc.); `struct VocabularyWordData: Codable` at ~line 33. T7 mirrors the `VocabularyWordData` shape with `SnippetExportData` and adds an optional `snippets: [SnippetExportData]?` field.

- [ ] **Step 0.4 — Confirm ContentView ViewType enum + sidebar idiom**

```bash
grep -n "case dictionary\|case settings\|case .dictionary\|DictionarySettingsView" VoiceInk/Views/ContentView.swift | head -10
```

Expected: `.dictionary` case at ~line 16, `.settings` case at ~line 17, route in `detailView(for:)` at ~line 178. T6 inserts `case snippets = "Snippets"` between `.dictionary` and `.settings`.

- [ ] **Step 0.5 — Confirm DictionarySettingsView shape (for Snippets view IA reference)**

```bash
ls VoiceInk/Views/Dictionary/ 2>&1 | head -10
```

Expected: dictionary view files. The new `VoiceInk/Views/Snippets/` directory will mirror that structure (one container view + one editor sheet).

- [ ] **Step 0.6 — Confirm SettingsCard / SettingsRow availability**

```bash
grep -n "struct SettingsCard\|struct SettingsRow" VoiceInk/Views/Common/SettingsCard.swift VoiceInk/Views/Common/SettingsRow.swift
```

Expected: both structs defined under `VoiceInk/Views/Common/`. T5 imports nothing extra (same module); uses `SettingsCard(...) { ... }` directly.

---

### Task 1 — Define `Snippet` SwiftData @Model

**Files:**
- Create: `VoiceInk/Models/Snippet.swift`

- [ ] **Step 1.1 — Write the @Model class**

```swift
import Foundation
import SwiftData

/// W12.C voice-snippet expansion. User-curated trigger → expansion pairs.
/// Pre-enhance pipeline pass replaces every `\b<trigger>\b` occurrence with
/// the expansion before the AI cleanup pass runs. See plan
/// `docs/superpowers/plans/W12C-voice-snippets.md` §Migration policy #2.
@Model
final class Snippet {
    /// Stable identifier (CloudKit-safe should sync land later).
    var id: UUID = UUID()

    /// Short typed token. Case-sensitive uniqueness; 1-32 chars matching
    /// `^[A-Za-z0-9;_./@-]{1,32}$`. Enforced at insert / update via
    /// `Snippet.validate(trigger:against:)`. See plan §Migration policy #6.
    var trigger: String = ""

    /// Long-form text spliced in place of the trigger. Plain text only;
    /// no variable substitution in v1 (see plan §Out of scope).
    var expansion: String = ""

    /// Optional user-curated tags for grouping / filtering. Stored as a
    /// SwiftData-encoded `[String]`. Empty by default.
    var tags: [String] = []

    /// User-controlled enable / disable; gates whether the trigger fires.
    /// Disabled snippets remain in the table for round-trip but are skipped
    /// by `SnippetExpansionService.expand(...)`.
    var isEnabled: Bool = true

    /// Insert timestamp (used for stable ordering in CRUD UI).
    var createdAt: Date = Date()

    /// Last-edit timestamp (touched on every update).
    var updatedAt: Date = Date()

    init(
        trigger: String,
        expansion: String,
        tags: [String] = [],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = UUID()
        self.trigger = trigger
        self.expansion = expansion
        self.tags = tags
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }
}

extension Snippet {
    /// Permitted character set per plan §Migration policy #6.
    /// Anchored full-string match; rejects empty + over-length.
    static let triggerPattern = #"^[A-Za-z0-9;_./@\-]{1,32}$"#

    /// Validation result. `.ok` permits the save; everything else is a
    /// user-facing reason rendered inline in the editor sheet.
    enum ValidationError: LocalizedError, Equatable {
        case empty
        case malformed
        case duplicate(existingTrigger: String)

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Trigger cannot be empty."
            case .malformed:
                return "Trigger may only contain letters, numbers, and these symbols: ; _ . / @ -"
            case .duplicate(let existing):
                return "Trigger '\(existing)' is already in use. Pick a different trigger."
            }
        }
    }

    /// Validate a candidate trigger against the existing table. Case-sensitive.
    static func validate(
        trigger candidate: String,
        against existing: [Snippet],
        editingId: UUID? = nil
    ) -> ValidationError? {
        if candidate.isEmpty { return .empty }
        guard candidate.range(of: triggerPattern, options: .regularExpression) != nil else {
            return .malformed
        }
        // Case-sensitive duplicate check; allow an in-place edit to keep its
        // own trigger.
        if let dup = existing.first(where: { $0.trigger == candidate && $0.id != editingId }) {
            return .duplicate(existingTrigger: dup.trigger)
        }
        return nil
    }
}
```

- [ ] **Step 1.2 — Confirm no orphan references**

```bash
grep -rn "Snippet\b" VoiceInk --include="*.swift"
```

Expected: only the new file (definition). Tasks 2-9 will add call sites.

**Risk:** LOW — pure additive @Model. SwiftData handles the persistence shape automatically; the `[String]` tag storage uses the default codable encoding (Migration policy #4).

**Verification:** type-check passes; SwiftData migration is a no-op (table is created fresh).

---

### Task 2 — Register `Snippet.self` in the SwiftData schema

**Files:**
- Modify: `VoiceInk/VoiceInk.swift`

- [ ] **Step 2.1 — Top-level Schema array (line ~53)**

```swift
let schema = Schema([
    Transcription.self,
    VocabularyWord.self,
    WordReplacement.self,
    Snippet.self
])
```

- [ ] **Step 2.2 — Persistent dictionarySchema (line ~248)**

```swift
let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self, Snippet.self])
```

- [ ] **Step 2.3 — In-memory dictionarySchema (line ~283)**

```swift
let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self, Snippet.self])
```

- [ ] **Step 2.4 — Verify ModelContainer init paths**

```bash
grep -n "Schema(\[" VoiceInk/VoiceInk.swift
```

Expected: 3 schema declarations, ALL containing `Snippet.self`. Missing one causes a runtime "model not found" crash on the first SwiftData fetch / save.

**Risk:** MED — schema migration boundary. Test by launching the app post-edit; if SwiftData fails to migrate the existing on-disk store, the persistent path falls back to in-memory and surfaces the existing "Storage Warning" alert. **Snippet is a new table — no migration needed for existing data; the table is created fresh on first launch with the new schema.**

**Verification:** type-check passes. Runtime: app launches without "ModelContainer initialization failed" log line.

---

### Task 3 — `SnippetExpansionService`

**Files:**
- Create: `VoiceInk/Services/SnippetExpansionService.swift`

- [ ] **Step 3.1 — Service skeleton + cache**

```swift
import Foundation
import SwiftData
import os

/// W12.C pre-enhance pipeline pass. Replaces `\b<trigger>\b` occurrences in
/// the raw transcript with the user's expansion text BEFORE the AI cleanup
/// pass runs. See plan
/// `docs/superpowers/plans/W12C-voice-snippets.md` §Migration policy #2.
///
/// Threading: `@MainActor` because all callers (TranscriptionPipeline + UI
/// CRUD) are MainActor-bound. The cache lives in-memory; SwiftData itself
/// owns the persistence.
@MainActor
final class SnippetExpansionService {
    static let shared = SnippetExpansionService()

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "SnippetExpansionService"
    )

    /// Cached active-snippet list (filtered to `isEnabled == true`).
    /// Refilled on every cache-miss. See plan §Migration policy #7.
    private var cache: [(trigger: String, expansion: String, regex: NSRegularExpression)] = []
    private var cacheVersion: Int = -1
    private var cachedFetchCount: Int = -1

    private init() {}

    /// Manually invalidate the cache. Called from CRUD UI (Add / Edit / Delete)
    /// so the next pipeline call reflects the change immediately.
    func invalidateCache() {
        cache.removeAll()
        cacheVersion = -1
        cachedFetchCount = -1
    }

    /// Returns the input text with all enabled-snippet triggers expanded,
    /// plus the count of triggers that matched. When zero snippets are
    /// defined OR none match, returns `(text, 0)` unchanged.
    /// Per plan §Migration policy #2 the no-match path MUST NOT log.
    func expand(text: String, modelContext: ModelContext) -> (expanded: String, expandedCount: Int) {
        refreshCacheIfNeeded(modelContext: modelContext)

        guard !cache.isEmpty else { return (text, 0) }

        var working = text
        var totalCount = 0

        for entry in cache {
            let range = NSRange(working.startIndex..<working.endIndex, in: working)
            let matches = entry.regex.numberOfMatches(in: working, options: [], range: range)
            guard matches > 0 else { continue }
            working = entry.regex.stringByReplacingMatches(
                in: working,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: entry.expansion)
            )
            totalCount += matches
        }

        return (working, totalCount)
    }

    private func refreshCacheIfNeeded(modelContext: ModelContext) {
        // Lightweight version probe: SwiftData fetchCount is a small query and
        // changes whenever the table changes (insert / delete). Editor-sheet
        // saves additionally call invalidateCache() to cover same-count edits.
        let descriptor = FetchDescriptor<Snippet>()
        let liveCount = (try? modelContext.fetchCount(descriptor)) ?? 0
        if liveCount == cachedFetchCount && cacheVersion >= 0 { return }

        let snippets = (try? modelContext.fetch(descriptor)) ?? []
        let active = snippets
            .filter { $0.isEnabled && !$0.trigger.isEmpty }
            .sorted { $0.createdAt < $1.createdAt }

        cache = active.compactMap { snippet in
            guard let regex = compileRegex(for: snippet.trigger) else { return nil }
            return (trigger: snippet.trigger, expansion: snippet.expansion, regex: regex)
        }
        cacheVersion += 1
        cachedFetchCount = liveCount
    }

    /// Build a word-boundary regex that handles triggers starting OR ending
    /// with non-word characters (`;sig`, `:date`). Uses lookahead + lookbehind
    /// + alternation so a `;` directly preceded by whitespace OR string-edge
    /// is treated as a boundary. Per plan §Migration policy #9.
    private func compileRegex(for trigger: String) -> NSRegularExpression? {
        let escaped = NSRegularExpression.escapedPattern(for: trigger)
        // Leading anchor: word-boundary OR string-start OR after-whitespace.
        // Trailing anchor: symmetric. Together they fire on any trigger
        // surrounded by whitespace or string edges, regardless of whether the
        // trigger's first/last char is a word character.
        let pattern = #"(?:\b|^|(?<=\s))"# + escaped + #"(?:\b|$|(?=\s))"#
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            logger.error("snippet regex compile failed for trigger \(trigger, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
```

- [ ] **Step 3.2 — Confirm threading + access pattern**

The service is `@MainActor`-bound to match the existing TranscriptionPipeline call site (`@MainActor class TranscriptionPipeline`). The service's `expand(...)` is called from within the pipeline's main-thread `do { ... }` block — no thread switching needed. CRUD UI runs on the main actor by default.

- [ ] **Step 3.3 — Verify**

```bash
grep -rn "SnippetExpansionService" VoiceInk --include="*.swift"
```

Expected: only the new file (definition). T4 will add the call site.

**Risk:** MED — regex word-boundary semantics for non-word-leading triggers (Migration policy #9). The pattern `(?:\b|^|(?<=\s))<escaped-trigger>(?:\b|$|(?=\s))` handles the typical `;sig` / `:date` cases; pathological triggers (e.g. ` ;sig` with leading whitespace baked in) are rejected at validation time per Migration policy #6.

**Verification:** type-check passes. Manual mental test cases (verbal walk-through, no test file):
- `";sig"` matches "send this off ;sig" → yes (` ` before `;`, end-of-string after).
- `";sig"` matches ";sig at the start" → yes (string-start before `;`).
- `";sig"` matches "assignment;sig" → no (preceded by word-char `t`, not whitespace nor edge).
- `"sig"` matches "the sig is" → yes (word boundaries around `sig`).
- `"sig"` matches "designsigner" → no (no word boundary inside the run).

---

### Task 4 — Splice the service into TranscriptionPipeline

**Files:**
- Modify: `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`

- [ ] **Step 4.1 — Insert the call after WordReplacement**

In `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`, between line 99 (post WordReplacement log) and line 101 (AVURLAsset duration block), insert:

```swift
// W12.C: pre-enhance snippet expansion. No-op when the snippet table is
// empty. Service caches the active list in memory; the cache invalidates
// on every CRUD action via `invalidateCache()`. See plan
// `docs/superpowers/plans/W12C-voice-snippets.md` §Migration policy #2.
let snippetResult = SnippetExpansionService.shared.expand(
    text: text,
    modelContext: modelContext
)
if snippetResult.expandedCount > 0 {
    text = snippetResult.expanded
    logger.notice("🦾 snippets: expanded \(snippetResult.expandedCount, privacy: .public) triggers")
    if UserDefaults.standard.bool(forKey: "DebugLogSnippetExpansion") {
        logger.notice("📝 Snippet expansion: \(text, privacy: .public)")
    }
}
```

- [ ] **Step 4.2 — Verify pipeline ordering**

The full ordering after the insertion is:
1. Transcribe (line 73-78)
2. Output filter (line 80)
3. Trim (line 91)
4. WhisperTextFormatter format (line 93-96, gated)
5. WordReplacement applyReplacements (line 98-99)
6. **SnippetExpansionService.expand (NEW — T4)**
7. AVURLAsset duration (line 101-102)
8. transcription.text = text (line 104)
9. Prompt detection (line 112-116)
10. Enhance gate + enhance (line 123-169)
11. Save + paste (line 187+)

Snippet expansion fires AFTER WordReplacement (so a misspell rule like `siggy → ;sig` cascades into snippet expansion) but BEFORE `transcription.text = text` (so the saved raw history record reflects the expanded text). Both the saved raw and the enhance call see the expanded text.

- [ ] **Step 4.3 — Verify no orphan references**

```bash
grep -rn "SnippetExpansionService" VoiceInk --include="*.swift"
```

Expected: definition + this single call site.

**Risk:** MED — pipeline insertion. The service short-circuits with `(text, 0)` when the snippet table is empty (Migration policy #2), so the no-snippet path is byte-identical to today. The non-empty path runs O(snippet_count) regex passes; for ~10-100 snippets the cost is sub-millisecond.

**Verification:** type-check passes. Runtime smoke (Task 10.2): with zero snippets, dictate normally; CSV log shows no `🦾 snippets: …` line. With one `;sig` snippet, dictate "send ;sig"; log shows `🦾 snippets: expanded 1 triggers`; pasted text contains the full signature.

---

### Task 5 — `SnippetsSettingsView` + `SnippetEditorSheet`

**Files:**
- Create: `VoiceInk/Views/Snippets/SnippetsSettingsView.swift`
- Create: `VoiceInk/Views/Snippets/SnippetEditorSheet.swift`

- [ ] **Step 5.1 — `SnippetsSettingsView`**

Mirrors `SettingsView.swift`'s `ScrollView { LazyVStack { SettingsCard } }` idiom. One card per snippet section. Top card houses the snippet table; an Add button at the bottom of the table opens the editor sheet.

```swift
import SwiftUI
import SwiftData

/// W12.C voice-snippets settings surface. CRUD over `Snippet` SwiftData
/// records. See plan `docs/superpowers/plans/W12C-voice-snippets.md` §T5.
struct SnippetsSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.createdAt, order: .forward) private var snippets: [Snippet]
    @State private var editorSnippet: Snippet? = nil
    @State private var showingAddSheet: Bool = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                snippetsCard
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .adaptiveGlassBackground()
        .sheet(isPresented: $showingAddSheet) {
            SnippetEditorSheet(
                editing: nil,
                existingSnippets: snippets,
                onSave: addSnippet,
                onCancel: { showingAddSheet = false }
            )
        }
        .sheet(item: $editorSnippet) { snippet in
            SnippetEditorSheet(
                editing: snippet,
                existingSnippets: snippets,
                onSave: { updated in updateSnippet(snippet, with: updated); editorSnippet = nil },
                onCancel: { editorSnippet = nil }
            )
        }
    }

    private var snippetsCard: some View {
        SettingsCard(
            iconSystemName: "text.cursor",
            iconTint: Palette.accent,
            title: "Snippets",
            subtitle: "Type a trigger; speak it; expand it.",
            statusText: snippets.isEmpty ? "Empty" : "\(snippets.count) defined",
            statusTone: snippets.isEmpty ? .neutral : .positive
        ) {
            if snippets.isEmpty {
                Text("Add your first snippet to expand triggers like `;sig` into long-form text.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snippets) { snippet in
                        snippetRow(snippet)
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Snippet", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
        }
    }

    private func snippetRow(_ snippet: Snippet) -> some View {
        SettingsRow(
            iconSystemName: snippet.isEnabled ? "checkmark.circle" : "circle.slash",
            label: snippet.trigger,
            subtitle: previewExpansion(snippet.expansion),
            iconTint: snippet.isEnabled ? Palette.success : Palette.neutral
        ) {
            HStack(spacing: 8) {
                Toggle("", isOn: bindingForEnabled(snippet)).labelsHidden()
                Button {
                    editorSnippet = snippet
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                Button(role: .destructive) {
                    deleteSnippet(snippet)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func previewExpansion(_ expansion: String) -> String {
        let trimmed = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 60 { return trimmed }
        return String(trimmed.prefix(57)) + "..."
    }

    private func bindingForEnabled(_ snippet: Snippet) -> Binding<Bool> {
        Binding(
            get: { snippet.isEnabled },
            set: { newValue in
                snippet.isEnabled = newValue
                snippet.updatedAt = Date()
                try? modelContext.save()
                SnippetExpansionService.shared.invalidateCache()
            }
        )
    }

    private func addSnippet(_ candidate: Snippet) {
        modelContext.insert(candidate)
        try? modelContext.save()
        SnippetExpansionService.shared.invalidateCache()
        showingAddSheet = false
    }

    private func updateSnippet(_ existing: Snippet, with candidate: Snippet) {
        existing.trigger = candidate.trigger
        existing.expansion = candidate.expansion
        existing.tags = candidate.tags
        existing.isEnabled = candidate.isEnabled
        existing.updatedAt = Date()
        try? modelContext.save()
        SnippetExpansionService.shared.invalidateCache()
    }

    private func deleteSnippet(_ snippet: Snippet) {
        modelContext.delete(snippet)
        try? modelContext.save()
        SnippetExpansionService.shared.invalidateCache()
    }
}
```

- [ ] **Step 5.2 — `SnippetEditorSheet`**

```swift
import SwiftUI

/// W12.C add / edit modal. Validates trigger format + uniqueness on Save.
/// See plan `docs/superpowers/plans/W12C-voice-snippets.md` §T5 +
/// §Migration policy #6 + §Migration policy #13.
struct SnippetEditorSheet: View {
    let editing: Snippet?
    let existingSnippets: [Snippet]
    let onSave: (Snippet) -> Void
    let onCancel: () -> Void

    @State private var trigger: String = ""
    @State private var expansion: String = ""
    @State private var tagsText: String = ""
    @State private var isEnabled: Bool = true
    @State private var inlineError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "Add Snippet" : "Edit Snippet")
                .font(.system(size: 16, weight: .semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Trigger")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField(";sig", text: $trigger)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Text("Letters, numbers, and ;_./@- are allowed. 1-32 chars.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Expansion")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextEditor(text: $expansion)
                    .frame(minHeight: 120, maxHeight: 240)
                    .font(.system(.body))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Tags (comma-separated, optional)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                TextField("personal, signature", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("Enabled", isOn: $isEnabled)

            if let inlineError {
                Text(inlineError)
                    .font(.system(size: 11))
                    .foregroundColor(Palette.warn)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save", action: validateAndSave)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        if let editing {
            trigger = editing.trigger
            expansion = editing.expansion
            tagsText = editing.tags.joined(separator: ", ")
            isEnabled = editing.isEnabled
        }
    }

    private func validateAndSave() {
        let trimmedTrigger = trigger.trimmingCharacters(in: .whitespaces)
        let trimmedExpansion = expansion // preserve user spacing in expansion body

        if let validation = Snippet.validate(
            trigger: trimmedTrigger,
            against: existingSnippets,
            editingId: editing?.id
        ) {
            inlineError = validation.errorDescription
            return
        }
        if trimmedExpansion.isEmpty {
            inlineError = "Expansion cannot be empty."
            return
        }

        let parsedTags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let snippet = Snippet(
            trigger: trimmedTrigger,
            expansion: trimmedExpansion,
            tags: parsedTags,
            isEnabled: isEnabled,
            createdAt: editing?.createdAt ?? Date(),
            updatedAt: Date()
        )
        onSave(snippet)
    }
}
```

- [ ] **Step 5.3 — Verify**

```bash
grep -rn "SnippetsSettingsView\|SnippetEditorSheet" VoiceInk --include="*.swift"
```

Expected: definitions + T6 call site (after T6 lands).

**Risk:** LOW — UI work; uses existing SettingsCard / SettingsRow / Palette / SwiftData @Query idioms. Edge cases: large `expansion` body (TextEditor handles fine up to a few KB); very long trigger lists (LazyVStack scrolls).

**Verification:** type-check passes. Runtime smoke (Task 10.2): open Snippets sidebar; see empty state; tap Add Snippet; create `;sig` → block of text; save; row appears; edit; toggle disable; delete.

---

### Task 6 — Add Snippets sidebar entry to ContentView

**Files:**
- Modify: `VoiceInk/Views/ContentView.swift`

- [ ] **Step 6.1 — Add `.snippets` case**

In `VoiceInk/Views/ContentView.swift:7-18`, replace:

```swift
enum ViewType: String, CaseIterable, Identifiable {
    case metrics = "Dashboard"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case models = "AI Models"
    case enhancement = "Enhancement"
    case powerMode = "Power Mode"
    case permissions = "Permissions"
    case audioInput = "Audio Input"
    case dictionary = "Dictionary"
    case settings = "Settings"
```

with (insert `.snippets` between `.dictionary` and `.settings`):

```swift
enum ViewType: String, CaseIterable, Identifiable {
    case metrics = "Dashboard"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case models = "AI Models"
    case enhancement = "Enhancement"
    case powerMode = "Power Mode"
    case permissions = "Permissions"
    case audioInput = "Audio Input"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case settings = "Settings"
```

- [ ] **Step 6.2 — Add icon mapping**

In the `var icon: String` switch (line 22-33), add:

```swift
case .snippets: return "text.cursor"
```

(coder may swap to another SF Symbol like `"square.text.square"`, `"text.append"`, or `"keyboard.badge.ellipsis"` if visually preferred — not architecture-critical).

- [ ] **Step 6.3 — Add detailView route**

In `detailView(for:)` (line 162-186), add:

```swift
case .snippets:
    SnippetsSettingsView()
```

before `case .settings`.

- [ ] **Step 6.4 — Sidebar visibility**

Snippets is always visible in the sidebar (no `powerModeUIFlag`-style gate). The empty-state copy in `SnippetsSettingsView` covers the "user has no snippets" UX cleanly. Per Migration policy #12.

- [ ] **Step 6.5 — Verify**

```bash
grep -n "case snippets\|case .snippets\|SnippetsSettingsView" VoiceInk/Views/ContentView.swift
```

Expected: 3 matches (enum case, icon switch, detailView switch route).

**Risk:** LOW — additive ViewType case. Sidebar order: snippets between dictionary and settings keeps the IA grouped (text-management surfaces stay clustered: Dictionary above Snippets).

**Verification:** type-check passes. Runtime: sidebar shows new "Snippets" item with the chosen icon; tapping it routes to `SnippetsSettingsView`.

---

### Task 7 — Extend `ImportExportService` for `[Snippet]`

**Files:**
- Modify: `VoiceInk/Services/ImportExportService.swift`

- [ ] **Step 7.1 — Define `SnippetExportData` struct**

Near `VocabularyWordData` at line 33-36, add:

```swift
/// W12.C snippet export transit type. Plain Codable mirror of the SwiftData
/// `Snippet` @Model — that class can't conform to Codable directly.
/// See plan §Migration policy #8.
struct SnippetExportData: Codable {
    let trigger: String
    let expansion: String
    let tags: [String]?
    let isEnabled: Bool?
    let createdAt: Date?
    let updatedAt: Date?
}
```

- [ ] **Step 7.2 — Extend `VoiceInkExportedSettings`**

In the `struct VoiceInkExportedSettings: Codable` block at line 38-47, add a new optional field at the bottom:

```swift
struct VoiceInkExportedSettings: Codable {
    let version: String
    let customPrompts: [CustomPrompt]
    let powerModeConfigs: [PowerModeConfig]
    let vocabularyWords: [VocabularyWordData]?
    let wordReplacements: [String: String]?
    let generalSettings: GeneralSettings?
    let customEmojis: [String]?
    let customCloudModels: [CustomCloudModel]?
    let snippets: [SnippetExportData]?  // W12.C
}
```

The new field is OPTIONAL so existing exports (pre-W12.C) decode cleanly into a `nil` value.

- [ ] **Step 7.3 — Export path**

In `exportSettings(...)` (line 76-167), after the `customModels` fetch (line 85), add:

```swift
// W12.C: fetch snippets
var exportedSnippets: [SnippetExportData]? = nil
let snippetDescriptor = FetchDescriptor<Snippet>(sortBy: [SortDescriptor(\Snippet.createdAt, order: .forward)])
if let snippets = try? modelContext.fetch(snippetDescriptor), !snippets.isEmpty {
    exportedSnippets = snippets.map {
        SnippetExportData(
            trigger: $0.trigger,
            expansion: $0.expansion,
            tags: $0.tags,
            isEnabled: $0.isEnabled,
            createdAt: $0.createdAt,
            updatedAt: $0.updatedAt
        )
    }
}
```

Add the field to the `VoiceInkExportedSettings` constructor at line 126-135:

```swift
let exportedSettings = VoiceInkExportedSettings(
    version: currentSettingsVersion,
    customPrompts: exportablePrompts,
    powerModeConfigs: powerConfigs,
    vocabularyWords: exportedDictionaryItems,
    wordReplacements: exportedWordReplacements,
    generalSettings: generalSettingsToExport,
    customEmojis: emojiManager.customEmojis,
    customCloudModels: customModels,
    snippets: exportedSnippets  // W12.C
)
```

- [ ] **Step 7.4 — Import path**

In `importSettings(...)` (line 169-366), after the `wordReplacements` import block (~line 280-282), add a new block:

```swift
// W12.C: import snippets — dedupe by trigger (case-sensitive). See plan
// §Migration policy #13.
if let snippetsToImport = importedSettings.snippets {
    let snippetDescriptor = FetchDescriptor<Snippet>()
    let existingSnippets = (try? modelContext.fetch(snippetDescriptor)) ?? []
    let existingTriggers = Set(existingSnippets.map { $0.trigger })
    var importedCount = 0
    for entry in snippetsToImport {
        if existingTriggers.contains(entry.trigger) {
            print("W12.C: skipping import of conflicting trigger \(entry.trigger)")
            continue
        }
        let newSnippet = Snippet(
            trigger: entry.trigger,
            expansion: entry.expansion,
            tags: entry.tags ?? [],
            isEnabled: entry.isEnabled ?? true,
            createdAt: entry.createdAt ?? Date(),
            updatedAt: entry.updatedAt
        )
        modelContext.insert(newSnippet)
        importedCount += 1
    }
    try? modelContext.save()
    SnippetExpansionService.shared.invalidateCache()
    print("Successfully imported \(importedCount) snippets to SwiftData (\(snippetsToImport.count - importedCount) skipped due to trigger conflicts).")
} else {
    print("No snippets found in the imported file. Existing snippets remain unchanged.")
}
```

- [ ] **Step 7.5 — Verify**

```bash
grep -n "snippets\|SnippetExportData" VoiceInk/Services/ImportExportService.swift | head -15
```

Expected: ≥6 matches (struct definition, VoiceInkExportedSettings field, export-fetch block, export constructor field, import block, import log).

**Risk:** MED — the optional-field shape preserves backward compat (pre-W12.C exports decode with `snippets = nil`; new exports decode on pre-W12.C builds via the OPTIONAL key being silently ignored — Swift's auto-Codable handles unknown keys cleanly).

**Verification:** type-check passes. Runtime: export, inspect JSON in a text editor — see `"snippets": [{...}]` block. Re-import — see all snippets restored. Import on an empty new install — the snippets land in SwiftData and Pre-enhance pipeline picks them up.

---

### Task 8 — Register `DebugLogSnippetExpansion` default (optional)

**Files:**
- Modify: `VoiceInk/AppDefaults.swift`

- [ ] **Step 8.1 — Add to defaults**

In `VoiceInk/AppDefaults.swift:5-53`, add to the registered defaults dictionary, in the existing "Recording & Transcription" or near a related section:

```swift
"DebugLogSnippetExpansion": false,  // W12.C — verbose snippet log
```

If the coder elects to omit the verbose log entirely (Migration policy #11), skip this task — the count line still fires unconditionally on non-empty expansion.

- [ ] **Step 8.2 — Verify**

```bash
grep -n "DebugLogSnippetExpansion" VoiceInk/AppDefaults.swift VoiceInk/Transcription/Engine/TranscriptionPipeline.swift
```

Expected: registered in AppDefaults + read in TranscriptionPipeline. Both or neither.

**Risk:** LOW — additive AppStorage key.

**Verification:** type-check passes. Runtime: setting `DebugLogSnippetExpansion=true` in Console / `defaults write` lights up the verbose log line; default false keeps it quiet.

---

### Task 9 — Static checks (coder-runnable, no build)

**Files:** none (read-only verification).

- [ ] **Step 9.1 — All touched files compile in isolation via SourceKit**

The coder's environment runs SourceKit live. Verify:
- No undefined-symbol errors after each task.
- `Snippet.swift` imports `Foundation` + `SwiftData`.
- `SnippetExpansionService.swift` imports `Foundation` + `SwiftData` + `os`.
- `SnippetsSettingsView.swift` imports `SwiftUI` + `SwiftData`.
- `SnippetEditorSheet.swift` imports `SwiftUI`.
- No circular imports introduced.

- [ ] **Step 9.2 — No orphan references**

```bash
grep -rn "Snippet\b" VoiceInk --include="*.swift" | wc -l
```

Expected: ≥10 distinct references across model, service, settings view, editor sheet, ContentView, ImportExportService, VoiceInk.swift schemas, TranscriptionPipeline.

```bash
grep -rn "SnippetExpansionService" VoiceInk --include="*.swift" | wc -l
```

Expected: ≥4 references (service file + TranscriptionPipeline call site + 3-4 invalidateCache calls in CRUD UI + import path).

- [ ] **Step 9.3 — Schema registration**

```bash
grep -n "Snippet.self" VoiceInk/VoiceInk.swift | wc -l
```

Expected: 3 matches (top-level Schema, persistent dictionarySchema, in-memory dictionarySchema).

- [ ] **Step 9.4 — ContentView wiring**

```bash
grep -n "snippets\|Snippets" VoiceInk/Views/ContentView.swift | head -10
```

Expected: enum case, icon switch case, detailView route. 3 matches.

- [ ] **Step 9.5 — ImportExportService extension**

```bash
grep -c "SnippetExportData\|snippets:" VoiceInk/Services/ImportExportService.swift
```

Expected: ≥4 (struct def + VoiceInkExportedSettings field + export block + import block).

- [ ] **Step 9.6 — Pipeline insertion is single, additive**

```bash
grep -c "SnippetExpansionService" VoiceInk/Transcription/Engine/TranscriptionPipeline.swift
```

Expected: 1 — the single call site at the post-WordReplacement boundary.

---

### Task 10 — Integration build + post-merge verification

**Files:** none (verification + report).

- [ ] **Step 10.1 — Single integration build**

```bash
make local
```

Expected: clean build. If it fails:
- Most likely: a SwiftData @Model storage error. Re-check `Schema([..., Snippet.self])` lands in all THREE locations (top-level + persistent dictionarySchema + in-memory dictionarySchema).
- Second-most-likely: `[String]` tag storage triggers a "non-Codable type" warning. Per Migration policy #4, fall back to comma-joined `String` storage with a computed `tags: [String]` view.
- Third-most-likely: NSRegularExpression pattern fails to compile for an edge-case trigger. Per Migration policy #6, validation rejects malformed triggers at insert time; the regex compile in `SnippetExpansionService.compileRegex(for:)` should never see one. If it does, the service logs and skips (returns nil from compileRegex).

Per CLAUDE.md cadence, this is the only build run during the packet.

- [ ] **Step 10.2 — Coder smoke pass (manual)**

Pick MLX / AFM with the active model. Smoke checklist:
- Open the new Snippets sidebar entry. See empty state.
- Tap "Add Snippet". Editor sheet opens.
- Fill `;sig` + a 3-line signature block. Save. Row appears.
- Try to add another snippet with the same `;sig` trigger. Expect inline error "Trigger ';sig' is already in use."
- Try `;si g` (whitespace inside trigger). Expect inline error about malformed trigger.
- Edit the existing snippet — change expansion text. Save. Row preview updates.
- Toggle isEnabled off. Row icon changes to `circle.slash`.
- Toggle back on.
- Dictate "send this off ;sig" with enhancement on. Pasted text contains the FULL signature, NOT `;sig`. Console shows `🦾 snippets: expanded 1 triggers`.
- Dictate "send this off" (no trigger). Pasted text is normal; no `🦾 snippets:` log line.
- Toggle the snippet OFF. Dictate "send this off ;sig". Pasted text contains literal `;sig` (no expansion).
- Toggle back ON, delete the snippet, dictate "send this off ;sig" — same: literal `;sig` pastes.
- With one active snippet, export settings. Inspect the exported JSON in a text editor — confirm `"snippets": [{...}]` block. Re-import on a fresh install (or after manually deleting all snippets) — snippets reappear.

- [ ] **Step 10.3 — User-side post-merge verification protocol**

After the code commit lands, the user runs the verification scenarios:

1. Add 2-3 snippets (`;sig` → email signature, `;addr` → mailing address, `:date` → "today's date").
2. Dictate a sentence with one trigger ("please email me at ;addr"). Confirm pasted text contains the address.
3. Dictate a sentence with two triggers ("send to ;addr signed ;sig"). Confirm both expand.
4. Disable one snippet, dictate the same sentence. Confirm the disabled trigger DOES NOT expand.
5. Dictate a sentence containing the trigger as part of a longer word ("assignment;sigh"). Confirm NO expansion (per Migration policy #9 mental test cases).
6. Test with `enhanceLevel = .high`: confirm the model treats the EXPANDED text as input (it sees the full signature, not `;sig`).
7. Test with `enhanceLevel = .none`: confirm the snippet still expands (the pre-enhance hook fires regardless of enhance level — see Risks #2).
8. Export → save JSON file → manually delete a snippet → import from JSON → confirm the snippet returns.
9. Edit a snippet's trigger. Confirm cache invalidates (next dictation reflects the new trigger).
10. Quit + relaunch app. Confirm snippets persist.

- [ ] **Step 10.4 — Coder report to lead**

Send the lead:
- Confirmation of all 9 tasks completed (or which deferred per §Risks).
- Build status.
- Smoke-dictation Console log (no-snippet path quiet; one-snippet path logs `🦾 snippets: expanded 1 triggers`).
- `SnippetsSettingsView` + editor sheet screenshots showing CRUD + validation errors (optional but useful).
- Any architectural surprises encountered (especially around SwiftData `[String]` tag encoding, regex word-boundary edge cases, or import dedup).

The lead handles the two commits + push + final handoff doc.

---

## Test plan

Per master plan §0 Q10 (test-infra deferred): no `xcodebuild test` runs. Validation is build-only via `make local` (Task 10.1) plus smoke dictation (Task 10.2) plus user-side post-merge verification (Task 10.3).

**What `xcodebuild build` runs:**
- Single `make local` invocation at Task 10.1. ~3 min cold; warm rebuilds are seconds.

**What the user does for smoke validation:**
- Coder smoke (Task 10.2): the 11-point checklist above.
- User verification (Task 10.3): the 10-step qualitative protocol.

If any of those expected behaviors don't materialize, the failing task is the candidate for a focused follow-up packet — see §Rollback plan.

---

## Rollback plan

**Single-commit packet → `git revert <code commit sha>` restores pre-W12.C behavior.** Plan doc commit stays (not reverted) so the historical record is preserved.

**Why squashed-not-split:**
- T1 + T2 are tightly coupled (the @Model shape + schema registration). Reverting one without the other leaves a broken SwiftData container.
- T3 + T4 are coupled (the service + the call site).
- T5 + T6 share the navigation surface (the view + the sidebar entry).
- T7's ImportExportService extension assumes T1's Snippet @Model exists.
- A per-task commit matrix would create a brittle revert (e.g., reverting T2 alone would leave T4's pipeline call referencing a nonexistent `Snippet` schema).

**Per-feature surgical revert** (if a single feature turns out worse):
- **Pipeline expansion regress:** comment out the T4 insertion block in `TranscriptionPipeline.swift`. Snippets remain in SwiftData + UI, but the pre-enhance hook becomes a no-op. Effectively makes the feature a "draft mode" — user can manage snippets without them firing.
- **Settings UI regress:** comment out the ContentView sidebar entry (T6) so users can't navigate to the surface. Existing data persists; restore later by re-enabling the case.
- **Import/Export regress:** comment out the T7 import + export blocks. Existing exports lose snippet data (transient regression); future exports skip the field.

**Detection signals** (which production data tells us a revert is needed):
- User reports unexpected text expansion in dictations not containing triggers → regex word-boundary bug. Investigate `compileRegex(for:)`; revert T4 if unfixable.
- App crashes on launch with "ModelContainer initialization failed" → schema registration missed one of three locations. Re-check Task 2 steps.
- App crashes on opening Snippets sidebar → `@Query` against a missing schema entity. Re-check Task 2.
- Snippet expansion is correct but enhance "fixes" the expansion (e.g. polishes the user's signature block) → not a bug, an artifact of enhancement level. Workaround: switch `enhanceLevel` to `.light` or `.none`. Document as a known limitation for v1.
- Import doesn't restore snippets → the optional field decode is failing silently. Inspect the imported JSON; re-check Task 7.

**Blast radius of a full revert:** zero data loss for existing user state. The Snippet table is a NEW table — reverting drops the table contents (the user's snippets). The reverted code stops reading the table, so the on-disk store contains orphan data until the next migration. Re-applying the feature later restores read access. Recommend the user export their snippets to JSON before any revert.

---

## Risks / unknowns

1. **Regex word-boundary semantics for non-word-leading triggers.** Per Migration policy #9, the pattern `(?:\b|^|(?<=\s))<escaped-trigger>(?:\b|$|(?=\s))` handles the typical `;sig` / `:date` cases. **Mitigation:** the validation in T1 + the mental-test cases in Task 3.3 cover the edge cases. If user reports a false-positive expansion (trigger fires inside a word), capture the offending input + log + adjust the pattern. Out-of-scope: full ICU word-boundary (`\u{2060}`-aware) handling — overkill for English-first dictation.

2. **Snippet expansion fires regardless of `enhanceLevel`.** A user with `enhanceLevel = .none` (raw paste) still gets snippet expansion. Rationale: snippets are an INPUT-side feature — the user typed `;sig` expecting expansion, regardless of whether AI cleanup runs after. **Mitigation:** documented as expected behavior. If the user wants pure raw output, they can disable specific snippets per-dictation (toggle in the UI) or keep their snippet table empty for that session. Out of scope: snippet-aware level filter.

3. **Enhance pass may "polish" the snippet expansion at `.high`.** A multi-line signature block at `enhanceLevel = .high` may get rephrased / line-wrapped / re-indented by the model. **Mitigation:** documented limitation. Workaround: drop to `.light` for sessions with snippet-heavy dictations. Follow-up: a "preserve snippets" prompt directive that wraps each expansion in `<PRESERVE>` tags so the model leaves them alone — out of scope here, would be a W12.A directive refinement.

4. **Multi-trigger expansion ordering.** Per Migration policy #10, expansion runs in `createdAt` ascending order. A snippet whose expansion contains another trigger does NOT recursively expand (single-pass regex). **Mitigation:** documented. Follow-up: recursive expansion if user requests; each pass would need a recursion guard (e.g. max-depth 3).

5. **Cache freshness across rapid CRUD.** The fetchCount-based version check (Migration policy #7) catches insert / delete but misses same-count edits (e.g. user changes the expansion body without touching the trigger). **Mitigation:** every CRUD action explicitly calls `SnippetExpansionService.shared.invalidateCache()`. The next `expand(...)` call rebuilds the cache regardless of fetchCount.

6. **`[String]` tag storage on SwiftData.** Per Migration policy #4, `[String]` properties auto-Codable on @Model. **Mitigation:** if a build error surfaces at T1, fall back to comma-joined `String` storage with a computed `tags: [String]` view. Adds ~10 LOC; flag for the lead.

7. **Trigger uniqueness collision after import.** Per Migration policy #13, the import path silently skips a colliding-trigger row. The user has no UI to resolve the conflict. **Mitigation:** print log line says how many rows were skipped. Follow-up: a "merge / replace / skip" UI for bulk-import collisions.

8. **No undo on snippet delete.** Confirm-before-delete is missing. **Mitigation:** v1 ships without confirmation per CLAUDE.md `feedback_no_confirmation_trivial.md` (snippets are recoverable via re-create). Follow-up: an Undo toast like W12.A's "Undo AI edit".

9. **Empty trigger / expansion edge case after edit.** If a user clears the trigger text in the editor and saves, validation rejects. If a user pastes whitespace-only into the expansion field, the Save validation rejects (`trimmedExpansion.isEmpty`). **Mitigation:** validation in T5.2 covers both. Verify in coder smoke (Task 10.2).

10. **No feature flag toggle.** Snippets is always-on; the only "off" state is an empty table. **Mitigation:** per Migration policy #2, the no-snippet path is byte-identical to today's behavior — no feature flag needed. If user reports rare interference (e.g. an unintended trigger fires), the workaround is to delete the offending snippet.

11. **Test infra deferred per Q10.** `xcodebuild test` env-blocked. Means no automated regression catch for the regex word-boundary semantics or the SwiftData migration. **Mitigation:** smoke + manual verification (Task 10.3). The mental test cases in Task 3.3 are the closest thing to a regression suite for this packet.

12. **CloudKit sync future-proofing.** SwiftData @Model with `var` defaults + UUID id + Date timestamps is already CloudKit-shape-compatible. **Mitigation:** future sync packet is unblocked structurally; not in scope here.

---

## Out of scope (explicit) for follow-ups

- **Phrase / multi-word triggers.** Single-token only in v1. Per master plan §3 W12.C "Out of scope".
- **Variable substitution inside expansions** (`${date}`, `${cursor}`, `${clipboard}`, etc.). Per master plan §3 W12.C + R3 §2.E "Wispr explicitly says snippets insert static text only".
- **Per-app snippet sets / Power Mode integration.** Per master plan §3 W12.C "Out of scope". Future packet if user requests.
- **Trigger-collision merge / replace UI.** Per Migration policy #13 — v1 silently rejects on Add, silently skips on Import.
- **Recursive expansion** (snippet whose expansion contains another trigger). Per Migration policy #10 — single-pass v1.
- **Snippet usage counters / analytics.** Out of scope for VoiceInk's no-telemetry positioning. Per R3 §3 "Bad ideas to avoid".
- **CloudKit sync / cross-device.** Out of scope per master plan §1 "Cross-device sync (Wispr ships Mac/Win/iOS/Android; VoiceInk is Mac-only by positioning)".
- **"Preserve snippets" enhance directive** (wrap expansions in tags so the model leaves them alone). Per Risks #3 — follow-up if user reports the polishing artifact.
- **Snippet-aware enhance-level filter.** Per Risks #2 — out of scope.
- **Bulk CSV import for snippets.** Existing `ImportExportService` uses the JSON shape; a CSV path would mirror the dictionary CSV import. Follow-up if user requests.
- **Smart trigger suggestions / autocomplete from history.** Out of scope.
- **Confirm-before-delete on snippet rows.** Per CLAUDE.md `feedback_no_confirmation_trivial.md`; v1 ships without.
- **Snippet UI on quick-toggle surfaces** (menubar, recorder popover). Out of scope; the management surface lives in the dedicated sidebar entry.
- **Undo toast on snippet delete.** Per Risks #8 — follow-up if user requests.
- **Tags filter / search in `SnippetsSettingsView`.** v1 ships a flat list; if user reports list-management pain past ~30 snippets, add a search field + tag chip filter. Follow-up.
- **Test infrastructure unblock.** Per master plan §0 Q10. Separate session.
- **Other W12 packets (B/D/E).** Each gets its own plan file later.

---

## Open questions for lead

1. **Trigger character set.** Migration policy #6 proposes `^[A-Za-z0-9;_./@-]{1,32}$`. **Confirm or expand:** add `:` (used by `:date`-style triggers in some text-expanders) or `&`? Recommend: ship the proposed set; add `:` if user reports needing it. Already include `;` `_` `.` `/` `@` `-`.

2. **Case-sensitivity.** Migration policy #5 ships case-sensitive (matching + uniqueness). **Confirm or flip:** `;Sig` and `;sig` distinct, OR collapse to one? Recommend: ship case-sensitive — matches Wispr's UX and gives the user fine control. Follow-up if user reports surprise.

3. **Sidebar position.** T6 inserts `.snippets` between `.dictionary` and `.settings`. **Confirm or move:** above `.dictionary` (treat as a "top-of-text-tools" surface)? Below `.dictionary` (current proposal)? Recommend: keep as proposed — Dictionary covers speech-recognition vocabulary; Snippets covers text expansion; both are user-curated text surfaces and group cleanly.

4. **Sidebar icon.** T6.2 proposes `"text.cursor"`. **Confirm or swap:** `"square.text.square"`, `"text.append"`, or `"keyboard.badge.ellipsis"` are alternatives. Recommend: ship `"text.cursor"`; swap is a 1-line diff if reviewer prefers.

5. **Verbose log toggle (`DebugLogSnippetExpansion`).** Migration policy #11 proposes ship-with-toggle (default off). **Confirm or skip:** ship the toggle, OR omit it and always log the count line? Recommend: ship the toggle for symmetry with W11.A's `DebugLogShortPath`. Coder may skip if Task 8 feels orphan-y for a 1-line edit.

6. **Tags storage shape.** Migration policy #4 ships `[String]` direct. **Fall back to comma-joined string** if the SwiftData encoding fails? Recommend: try `[String]` first; if it fails at build time, the coder applies the Migration policy #4 fallback (comma-joined String + computed `[String]` view).

7. **Cache invalidation strategy.** Migration policy #7 proposes fetchCount + manual invalidate from CRUD. **Confirm or simplify:** drop the fetchCount probe entirely + rely solely on CRUD-side `invalidateCache()` calls? Recommend: keep fetchCount probe as defense-in-depth — covers the case where SwiftData backgrounds the cache invalidation across processes (unlikely in v1 but harmless).

8. **Enhance-level interaction.** Risks #2 + #3 flag that snippets always expand regardless of `enhanceLevel`, and that `.high` may polish the expansion. **Confirm:** ship as-is for v1; document as a known limitation? Recommend: yes — the alternative (level-aware expansion) is more complex and ships against the master plan §0 Q4=c decision.

9. **Empty-state copy.** T5.1 proposes "Add your first snippet to expand triggers like `;sig` into long-form text." **Confirm or rewrite:** prefer a different phrasing (e.g. "Define triggers for text you type often.")? Recommend: ship as proposed; copy is editable in a 1-line diff later.

10. **Pre-merge gate.** No qualitative reference set is required (net-new feature). **Confirm:** does the lead want the user to draft 2-3 example snippets ahead of merge for the post-merge verification checklist (Task 10.3), OR can the user create them post-merge? Recommend: post-merge — the smoke checklist already exercises CRUD + expansion paths.

---

## Post-merge verification protocol (USER-SIDE)

1. Open the new "Snippets" sidebar entry. Confirm the empty state copy appears. Confirm the icon and label render.

2. Tap "Add Snippet". Sheet opens. Fill `;sig` + a 3-line signature block (real one). Save. Row appears.

3. Try to add another `;sig` (case-sensitive duplicate). Confirm inline error.

4. Try `;si g` (whitespace inside trigger). Confirm inline error.

5. Try a 33-char trigger. Confirm inline error.

6. Add a second snippet `;addr` → mailing address. Save. Two rows visible.

7. Add a third snippet `:date` → "today's date" placeholder. Save. Three rows visible.

8. Dictate "send this off ;sig". Confirm:
   - Pasted text contains the FULL signature, NOT `;sig`.
   - Console shows `🦾 snippets: expanded 1 triggers`.
   - History entry's raw text (`Transcription.text`) contains the EXPANDED signature (raw record reflects post-snippet-expansion content).

9. Dictate "please email me at ;addr signed ;sig". Confirm:
   - Both expansions land.
   - Console shows `🦾 snippets: expanded 2 triggers`.

10. Toggle `;sig` to disabled in the sidebar. Dictate "send this off ;sig". Confirm:
    - Pasted text contains literal `;sig` (no expansion).
    - Console shows NO `🦾 snippets:` log line (no expansions fired).

11. Re-enable `;sig`. Edit the expansion body (change a word). Save. Dictate "send ;sig". Confirm pasted text reflects the EDITED expansion (cache invalidated).

12. Delete `;addr`. Dictate "email me at ;addr". Confirm pasted text contains literal `;addr`.

13. Quit + relaunch app. Confirm `;sig` and `:date` persist (no `;addr`, since deleted).

14. Export settings via Settings → Backup → Export. Save the JSON to disk. Open in a text editor — confirm a `"snippets": [...]` block contains both surviving snippets. Confirm the existing keys (`customPrompts`, `powerModeConfigs`, etc.) are preserved.

15. Delete `;sig` and `:date` from the Snippets surface. Confirm 0 snippets.

16. Re-import the JSON via Settings → Backup → Import. Confirm both snippets reappear after the import + restart prompt.

17. Test snippet at each `enhanceLevel`:
    - `.none`: raw paste — snippet expands; pasted text contains the expansion verbatim.
    - `.light`: enhance pass keeps the expansion as-is (filler removal only).
    - `.medium`: enhance may fix grammar in the expansion (acceptable).
    - `.high`: enhance may polish the expansion (acceptable; documented under Risks #3).

18. Test trigger inside-a-word case (Migration policy #9). Add a snippet `xyz` → "FOO". Dictate "the abcxyzdef thing". Confirm pasted text is "the abcxyzdef thing" — NO expansion (no whitespace boundary around `xyz`).

If any step fails, log the failure mode + which task is implicated, and SendMessage the lead. Tasks 1-9 are independently revertible per §Rollback plan.

---

## Notes for the lead

- **Net-new feature.** Zero coverage today. No regression baseline; rollback drops user data (their newly created snippets). Recommend the user export-to-JSON before any revert.
- **Pre-enhance hook is byte-identical to today on the empty-table path.** Migration policy #2 — the service short-circuits with `(text, 0)` when the cache is empty; the pipeline's `if expandedCount > 0` gate skips the log + the text reassignment. No measurable cost.
- **SwiftData schema is registered in THREE locations** (`VoiceInk.swift` lines ~53, ~248, ~283). All three need `Snippet.self`. Missing one causes a runtime crash on first save.
- **`Snippet` @Model is NOT Codable.** Export/import uses the sibling `SnippetExportData: Codable` struct (Migration policy #8) — same dance VocabularyWord uses.
- **Two commits, not one.** Plan doc lands first (`docs(plans): W12C — voice snippets plan`). Code lands after lead sign-off (`feat(snippets): W12C — voice snippets pre-enhance expansion + settings UI`).
- **No new tests.** Build is the gate. Per Q10 deferral.
- **One integration build.** Per `feedback_skip_per_packet_builds.md`. Coder does NOT run `make local` during execution.
- **Forward-compat with W12.D / W12.E.** The `Snippet` model + service are isolated from recorder-state code (W12.D's territory) and Scratchpad (W12.E's territory). No cross-packet dependencies. W12.C can land before, after, or in parallel with W12.B / D / E.
- **Backward-compat with pre-W12.C exports.** The new `snippets` field on `VoiceInkExportedSettings` is OPTIONAL — old exports decode with `snippets = nil`. New exports decode on hypothetical pre-W12.C builds via Swift's auto-Codable ignoring unknown keys.
- **Open questions:** 10 above. None block the plan structure; most are wording / placement / shape choices the lead may accept-as-proposed for v1.
