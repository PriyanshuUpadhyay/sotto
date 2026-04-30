# W12.E — Scratchpad Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Reviewer is `superpowers:code-reviewer`.
>
> **Phase 2 packet — final.** W12.E is the largest dependency surface in the W12 phase: a NEW summoned window, multi-tab SwiftUI editor, two NEW SwiftData `@Model` types with versioning + FIFO eviction, hotkey registration, cross-cut into the paste-failure branch of `CursorPaster`, and a dictation-into-place hook on the existing pipeline. Lands AFTER W12.A (merged 0759019), W12.B (in flight), W12.C (in flight), W12.D (in flight). Sequenced last per master plan §6 Phase 3.

**Date:** 2026-04-30
**Scope:** Add a new always-available dictation surface. Summoned via `⌥+S`, the Scratchpad window hosts multi-tab plain-text editors backed by SwiftData; each document auto-saves on a debounced typing tick; per-document version snapshots are captured every 30s of active typing OR on tab switch / window close, capped at 50 per document FIFO. The active tab acts as a valid recorder target — pressing the recorder hotkey while Scratchpad is focused inserts the transcript at the cursor position in the active tab instead of routing through `CursorPaster`. The Scratchpad doubles as a paste-fallback target: when `CursorPaster.pasteAtCursor(...)` detects no focused text field (existing `focusedElementAcceptsText()` predicate returns false), the would-be-pasted text is also appended as a NEW tab in the Scratchpad — additive, the existing clipboard-fallback notification path stays unchanged.

**Sources of truth:**
- R3 audit (the WHY for Scratchpad as a P0): `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` §1 P0-5, §2.E (Voice commands / output behaviors — paste-fallback target), §3 ("Scratchpad fallback when paste fails").
- Master plan §3 W12.E scope: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md`. Defines scope (new window, multi-tab, auto-save + 50-version history, paste-fallback target).
- W12.A as the sibling-shape reference (packet etiquette, Codable migration, derived-view migration approach): `docs/superpowers/plans/W12A-auto-cleanup-levels.md`.
- W11.B routing reality (deployment target already at macOS 26.0): no deployment-target change here. SwiftUI APIs used here (`TextEditor`, `TabView`, `AttributedString`) are all macOS 13+ — comfortably under 26.0.
- Aesthetic spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (window-glass vocabulary), §6.1 (NSWindow flags for adaptive glass), §3.7 (SettingsCard idiom — re-used for the version-history sheet).
- Source-surface references:
  - `VoiceInk/WindowManager.swift` — main window flags (isOpaque=false, backgroundColor=.clear, fullSizeContentView). Mirror these in the Scratchpad window.
  - `VoiceInk/HistoryWindowController.swift` — the canonical "summoned window" idiom (singleton controller, identifier-keyed reuse, autosave-named frame). The Scratchpad controller is a near-copy with the new identifier and content view.
  - `VoiceInk/CursorPaster.swift` — paste-fallback branch lives at line 41-50 (`mustForceClipboard` early return). The W12.E hook fires INSIDE this branch — additive, never on the happy path.
  - `VoiceInk/Models/Transcription.swift` — pattern reference for SwiftData `@Model` (this is the existing model in the local "default" store; W12.E adds two siblings to the same store).
  - `VoiceInk/HotkeyManager.swift:7-15` — `KeyboardShortcuts.Name` registry; W12.E adds one new entry (`scratchpadToggle`).
  - `VoiceInk/Views/Common/AdaptiveGlassBackground.swift` — the `.adaptiveGlassBackground()` modifier the Scratchpad root view wraps in.

**Goal:** users get a `⌥+S`-summoned dictation surface that is always available, persistent across launches, multi-tab, history-aware, and that gracefully catches paste failures. The Scratchpad is single-device only (no sync); plain text only (no markdown rendering, no rich text); no search across tabs; no export. v1 is the always-on note-taking surface that closes the Wispr Scratchpad gap (R3 §1 P0-5) without bringing along the Wispr-specific cross-device-sync expectations that misalign with VoiceInk's local-first positioning.

---

## Prelude — packet shape + commit etiquette

W12.E is **one logical packet** but its diff straddles two new SwiftData `@Model` types + a new singleton service + a new window controller + a new SwiftUI view + a new `KeyboardShortcuts.Name` + a new branch in `CursorPaster` + a new branch in the dictation pipeline + the plan doc itself. Per CLAUDE.md `feedback_skip_per_packet_builds.md` the lead does ONE integration `make local` at merge time and ONE squashed `feat:` commit.

- `docs(plans): W12E — scratchpad plan` — this file. Lands FIRST, before any code, after lead sign-off.
- `feat(scratchpad): W12E — summoned window + multi-tab + 50-version history + paste fallback` — code edits across model + service + window + view + hotkey + paste-branch + pipeline hook. **Single squashed commit** at merge time.

Coder leaves edits uncommitted; lead handles both commits. No per-task build is run during the packet; the integration `make local` runs once at the end (Task 12). Worktree at `/Users/priyanshu/Desktop/Projects/pu/voiceink-fork/.worktrees/w12e/` (absolute path; per CLAUDE.md teammate-context lifecycle).

---

## Pre-merge ground-truth gate (NONE)

W12.E is a feature-add, not a perf-refactor. There is no pre-merge baseline to capture analogous to W11.A's `🦾 enhance: total=…s` rows. The post-merge verification protocol (Task 12.3) is purely qualitative — does the window summon, do tabs persist across launch, does dictation-into-place insert at cursor, does the paste-fallback branch fire when there's no focused field. No CSV row to validate.

---

## Architecture (W12.E change list — T1 through T10)

```
Task   Where                                                                     Risk
─────  ────────────────────────────────────────────────────────────────────────  ─────
T1     Define ScratchpadDocument + ScratchpadVersion @Models                     MED
       VoiceInk/Models/ScratchpadDocument.swift (NEW)                            — SwiftData store add =
       VoiceInk/Models/ScratchpadVersion.swift (NEW)                                first-launch DB migration.
       VoiceInk/VoiceInk.swift (Schema + container config)                          Land carefully.

T2     Register .scratchpadToggle KeyboardShortcuts.Name                         LOW
       VoiceInk/HotkeyManager.swift                                              — pure additive enum case.

T3     ScratchpadStore — SwiftData CRUD + 800ms autosave debounce +              MED
       30s version snapshot + 50-version FIFO eviction
       VoiceInk/Services/ScratchpadStore.swift (NEW)                             — async save coalescing
                                                                                    is the load-bearing wall.

T4     ScratchpadWindowController + ScratchpadWindow (NSPanel-style)             MED
       VoiceInk/Views/Scratchpad/ScratchpadWindowController.swift (NEW)          — mirror WindowManager glass
       VoiceInk/Views/Scratchpad/ScratchpadWindow.swift (NEW)                       flags. Reuse HistoryWindow
                                                                                    controller pattern.

T5     ScratchpadView root — TabView chrome + cap=10 + ⌘T / ⌘W                   MED
       VoiceInk/Views/Scratchpad/ScratchpadView.swift (NEW)                      — SwiftUI TabView styling on
                                                                                    macOS is finicky; custom
                                                                                    chrome required.

T6     ScratchpadTabEditor — TextEditor + cursor-position read +                 MED
       autosave wiring + version-history sheet
       VoiceInk/Views/Scratchpad/ScratchpadTabEditor.swift (NEW)                 — NSText cursor pos via
                                                                                    NSTextView coordinator.

T7     Hotkey wiring — toggle (open/focus/close) on .scratchpadToggle            LOW
       VoiceInk/HotkeyManager.swift                                              — single onKeyUp handler.

T8     CursorPaster paste-fallback branch                                        MED
       VoiceInk/CursorPaster.swift                                               — MUST NOT alter happy path.
                                                                                    Single line in the
                                                                                    `mustForceClipboard` branch.

T9     Dictation-into-place — TranscriptionPipeline branch                       MED
       VoiceInk/Transcription/Engine/TranscriptionPipeline.swift                 — divert paste when the
                                                                                    Scratchpad is the active
                                                                                    focused window.

T10    Settings shortcut row — let user rebind                                   LOW
       VoiceInk/Views/Settings/HotkeySettingsView.swift (or wherever the         — UI; no behavior change.
       existing shortcut rows live)
```

**Combined target:** users press `⌥+S` and a glass-backdrop window slides in; they type into a tab, switch tabs with `⌘1`/`⌘2`/…, open new tabs with `⌘T`, close with `⌘W`. They start the recorder while the Scratchpad is focused and the transcript inserts at their cursor. They open the version history sheet for any tab and pick any of the last 50 snapshots to restore. When they dictate into a sandboxed app where paste fails (e.g., 1Password), the text appears as a new Scratchpad tab the next time they open the window.

---

## Tech Stack

Swift 5.x, SwiftUI, AppKit, SwiftData. **No SPM additions.** macOS 26.0 deployment target (post-W11.B).

T6's cursor-position read uses `NSTextView` via a `NSViewRepresentable` wrapper around `TextEditor` — SwiftUI's pure-`TextEditor` does not expose selection range. The wrapper's coordinator reads `selectedRange()` and writes back via `replaceCharacters(in:with:)` for dictation insertion. Both APIs are macOS 10.10+ — comfortably supported.

T1's SwiftData `@Model` types live in the existing local "default" store (alongside `Transcription`) per `VoiceInk.swift:239-244`. They DO NOT join the CloudKit-synced "dictionary" store (`VocabularyWord`, `WordReplacement`) — Scratchpad is single-device per master plan §3 W12.E out-of-scope. Adding two `@Model` types to an existing store is a one-time SwiftData lightweight migration; both are net-new entities, no field renames or type changes — SwiftData handles this automatically on first launch.

Build via `make local` (~3 min cold). One integration build at Task 12, per CLAUDE.md cadence.

---

## Spec refs

- Research: `docs/superpowers/research/2026-04-29-whisperflow-feature-audit.md` §1 P0-5 ("Scratchpad — Wispr's most-requested feature in the v3 changelog"), §2.E (paste-fallback hook), §3 ("Scratchpad fallback when paste fails. When the focused field rejects paste (web app, sandbox, password manager), Wispr automatically opens its Scratchpad and pastes there. VoiceInk currently silently fails or warns; this is a strictly better UX for the same failure mode").
- Master plan: `docs/superpowers/plans/2026-04-29-W11-W13-master-plan.md` §3 W12.E scope ("New window: `⌥+S` opens a dictation-into-place editor. Multi-tab + auto-save + 50-version history with restore. Doubles as the paste-fallback target when `CursorPaster` fails").
- Aesthetic spec: `docs/superpowers/specs/2026-04-28-aesthetic-redesign.md` §1 (window-glass vocabulary), §6.1 (NSWindow flags), §3.7 (SettingsCard chrome reused for the version-history list).
- W12.A precedent for plan shape, Codable backward-compat, derived-view migration, single-feat-commit etiquette.
- W12.A's `WordDiffEngine.tokenLevelDiff(...)` is reused INDIRECTLY in the version-history sheet — the user can compare any version against the current text via the existing inline-diff code path. (Confirm reuse is desirable; falls back to plain text-list if reviewer prefers v1 simplicity.)

---

## CLAUDE.md cadence rules respected

- **Single integration build at merge time.** No `make local` per task; one full build at Task 12. Per `feedback_skip_per_packet_builds.md`.
- **One squashed commit at merge time.** No per-task commits during execution.
- **Sentence-fragment commits, no PR-reference comments, no obvious-explainer comments, no emojis in code.** The existing `🦾` log markers stay (W6/W11 instrumentation, documented exception). The Scratchpad code path adds a single new log marker `🗒️ scratchpad: …` for autosave/version events — flagged for lead approval (alternative is plain text prefix, e.g. `scratchpad:`).
- **No new test files.** Per master plan §0 Q10=defer, validation is build-only.
- **No SPM additions, no deployment-target bump.**
- **No pbxproj edits.** Files added under `VoiceInk/` auto-included by Xcode 16 PBXFileSystemSynchronizedRootGroup.
- **NEVER commit directly to main.** Worktree at `.worktrees/w12e/`, branch off `main` at `0759019`.

---

## File structure

### New files

- `VoiceInk/Models/ScratchpadDocument.swift` (~80 LOC) — defines `@Model` `ScratchpadDocument { id; title; content; tabIndex; createdAt; updatedAt }`. Initializer + a `currentVersionsSorted: [ScratchpadVersion]` computed convenience that sorts the relationship by `capturedAt` descending. Conforms to `Identifiable`. Field defaults: `title = "Untitled"`, `content = ""`, `tabIndex = 0`. SwiftData relationship to versions defined here as `@Relationship(deleteRule: .cascade) var versions: [ScratchpadVersion] = []`. Cascade ensures version rows die with the document.

- `VoiceInk/Models/ScratchpadVersion.swift` (~50 LOC) — defines `@Model` `ScratchpadVersion { id; content; capturedAt }`. Backward relationship `@Relationship(inverse: \ScratchpadDocument.versions) var document: ScratchpadDocument?`. Initializer takes `content: String, document: ScratchpadDocument`.

- `VoiceInk/Services/ScratchpadStore.swift` (~250 LOC) — `@MainActor class ScratchpadStore: ObservableObject`. Holds `@Published var documents: [ScratchpadDocument]`. Methods: `loadDocuments()`, `createTab(at index: Int) -> ScratchpadDocument`, `closeTab(_ document: ScratchpadDocument)`, `updateContent(_ doc: ScratchpadDocument, content: String)` (debounced 800ms autosave + per-doc 30s version-snapshot timer), `captureVersion(_ doc: ScratchpadDocument, force: Bool = false)`, `restoreVersion(_ version: ScratchpadVersion, in doc: ScratchpadDocument)`, `evictOldVersionsIfNeeded(_ doc: ScratchpadDocument)` (FIFO eviction at the 50-cap), `appendFallbackTab(text: String)` (the paste-fallback hook landing site). Owns the `Task` that drives the autosave debounce and the version-snapshot interval.

- `VoiceInk/Views/Scratchpad/ScratchpadWindowController.swift` (~95 LOC) — singleton `class ScratchpadWindowController: NSObject, NSWindowDelegate` mirroring `HistoryWindowController` shape. `static let shared`. `func toggle(modelContainer:)` (open/focus/close based on key state), `func show(modelContainer:)`, `func appendAsNewTab(text:, modelContainer:)` (used by the paste-fallback hook). Owns the `NSWindow`, identifier `com.prakashjoshipax.voiceink.scratchpadWindow`, autosave name `VoiceInkScratchpadWindowFrame`. The window is created via `createScratchpadWindow(modelContainer:)` which wires the SwiftUI hosting controller and applies the WindowManager-mirrored flags (isOpaque=false, backgroundColor=.clear, fullSizeContentView).

- `VoiceInk/Views/Scratchpad/ScratchpadWindow.swift` (~60 LOC) — `class ScratchpadWindow: NSWindow` overriding `canBecomeKey`/`canBecomeMain` to `true` (default). Style mask: `[.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`. Distinct from `MiniRecorderPanel.swift` (which is an NSPanel — non-activating). Scratchpad WANTS to activate so dictation-into-place + ⌘+T/⌘+W chord routing works. The window is a regular `NSWindow`, not a panel.

- `VoiceInk/Views/Scratchpad/ScratchpadView.swift` (~250 LOC) — root SwiftUI view. Hosts the multi-tab chrome: a horizontal tab strip (custom-styled, NOT default `TabView`'s top-tabs idiom — the default chrome doesn't blend with the glass backdrop). Each tab cell shows the document `title` (or "Untitled" if blank) with a small `×` close button. `+` button at the right edge for new tab (cap at 10). Active tab's `ScratchpadTabEditor` fills the rest of the window. Keyboard shortcuts via `.keyboardShortcut(...)` view modifiers: `⌘T` (new tab), `⌘W` (close active tab). `⌘1`-`⌘9` switch to tab N (matches Safari/Cursor mental model). The view is wrapped in `.adaptiveGlassBackground(intensity: .panel)` to consume the wallpaper-glass behind it (per spec §1).

- `VoiceInk/Views/Scratchpad/ScratchpadTabEditor.swift` (~200 LOC) — single-tab editor. `NSViewRepresentable` wrapper around `NSTextView` (since `TextEditor` doesn't expose selection range or programmatic insertion). `Binding<String>` for content; on every `textDidChange` callback, calls `store.updateContent(...)` to drive the autosave debounce. Exposes a coordinator method `insertAtCursor(_ text: String)` used by the dictation-into-place hook. Below the text view: a small footer with the timestamp of the last version snapshot ("Saved 3s ago") + a "History" button that opens the version-history sheet.

- `VoiceInk/Views/Scratchpad/ScratchpadVersionHistorySheet.swift` (~150 LOC) — modal sheet listing the 50 most-recent versions for the active document. Each row: `capturedAt` formatted ("Today, 14:23"), a 2-line preview of `content`, a "Restore" button. On Restore: capture the CURRENT state as a new version FIRST (so restore is reversible), then replace `document.content` with the chosen version's `content`. Status text confirms ("Restored to 14:23"). Optional: a "Compare to current" disclosure that uses `WordDiffEngine.tokenLevelDiff(original: version.content, edited: document.content)` to render an inline diff — flagged for lead approval (Task 11 alternative if the diff render adds too much UI complexity).

### Modified files

- `VoiceInk/HotkeyManager.swift` — T2 + T7. Add `static let scratchpadToggle = Self("scratchpadToggle")` to the `KeyboardShortcuts.Name` extension at line 7-15 (alongside the other 7 entries). T7 adds an `onKeyUp(for: .scratchpadToggle) { … }` block in the existing init (~line 192-200, near the `openHistoryWindow` registration — the two are sibling shapes). The handler invokes `ScratchpadWindowController.shared.toggle(modelContainer: self.engine.modelContext.container)`. ~+12 LOC.

- `VoiceInk/MiniRecorderShortcutManager.swift` — T7 (default shortcut binding). The default-shortcut registration at line 140-144 sets `.option`-modifier defaults for PowerMode hotkeys. Add a sibling `KeyboardShortcuts.setShortcut(.init(.s, modifiers: .option), for: .scratchpadToggle)` ONLY IF `KeyboardShortcuts.getShortcut(for: .scratchpadToggle) == nil` — first-run only, never overwrites a user customization. (NOTE: confirm at audit time which file actually owns first-run shortcut defaults; `MiniRecorderShortcutManager` is the closest analogue but the lead may have moved this elsewhere — see Task 0.) ~+5 LOC.

- `VoiceInk/CursorPaster.swift` — T8. Inside the `mustForceClipboard` branch at line 41-50, AFTER the existing `NotificationManager.shared.showNotification(...)` call and BEFORE `return`, add a single dispatch to `ScratchpadStore.appendFallbackTab(text:)`. The notification stays. The clipboard set stays. The early return stays. The Scratchpad receives the text additively. The happy path (line 52-95) is UNTOUCHED. ~+8 LOC.

- `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift` — T9. The paste call at line 205 (`CursorPaster.pasteAtCursor(textToPaste + (appendSpace ? " " : ""))`) is gated on whether the Scratchpad is the active focused window. New helper `ScratchpadWindowController.shared.isFocusedAndKey -> Bool` returns true when the Scratchpad window is `isKeyWindow == true` AND has a focused tab editor. When true, route the text to the active tab's `insertAtCursor(_:)` instead of `CursorPaster.pasteAtCursor(...)`. **Critical:** all the surrounding logic (the `didEnhance`/`didFireTranscribeCue` cue selection at line 199-203, the `autoSendKey` post-paste handling at line 207-212) must continue to work — the cue choice is the same; the auto-send is SUPPRESSED when the route is into-Scratchpad (you don't want to fire ⏎ inside the Scratchpad). ~+25 LOC, -1 LOC.

- `VoiceInk/VoiceInk.swift` — T1 (schema + container config). Add `ScratchpadDocument.self, ScratchpadVersion.self` to:
  - The top-level `Schema([Transcription.self, VocabularyWord.self, WordReplacement.self])` at line 53-57 → adds two entries.
  - `createPersistentContainer.transcriptSchema` at line 239 → joins the local "default" store: `Schema([Transcription.self, ScratchpadDocument.self, ScratchpadVersion.self])`.
  - `createInMemoryContainer.transcriptSchema` at line 275 → same addition.
  These are net-new entities — no field renames, no type changes — SwiftData handles this as a lightweight migration on first launch automatically. The dictionary store (CloudKit-synced) is UNTOUCHED — Scratchpad is single-device per master plan §3 W12.E out-of-scope. ~+6 LOC, 0 LOC removed.

- `VoiceInk/Views/Settings/HotkeySettingsView.swift` (or wherever `KeyboardShortcuts.Recorder(...)` rows for the existing shortcuts live — confirm at Task 0) — T10. Add a `KeyboardShortcuts.Recorder("Scratchpad", name: .scratchpadToggle)` row alongside the existing `pasteLastTranscription`, `pasteLastEnhancement`, `retryLastTranscription`, `openHistoryWindow`, `quickAddToDictionary` rows. Lets the user rebind. ~+3 LOC.

### Untouched (explicit list — coder do NOT drift)

- `VoiceInk/WindowManager.swift` — UNTOUCHED. Scratchpad has its OWN window controller (mirrors but doesn't share). The `mainWindowIdentifier` registry stays main-window-only.
- `VoiceInk/HistoryWindowController.swift` — UNTOUCHED. Scratchpad mirrors the shape but does not extend or share state with this controller.
- `VoiceInk/Views/Recorder/MiniWindowManager.swift`, `MiniRecorderPanel.swift`, `NotchWindowManager.swift` — UNTOUCHED. Recorder windows are separate. The Scratchpad is a regular `NSWindow`, not a panel — different lifecycle.
- `VoiceInk/CursorPaster.swift:11-39` (the happy path) — UNTOUCHED. The W12.E hook lives ONLY in the `mustForceClipboard` branch (line 41-50). Constraint per master plan: "The paste-fallback wiring MUST NOT change `CursorPaster.paste()` happy-path behavior. New branch only."
- `VoiceInk/Models/Transcription.swift`, `VocabularyWord.swift`, `WordReplacement.swift` — UNTOUCHED. The new `@Model` types are siblings, not extensions.
- `VoiceInk/AppDelegate.swift`, `VoiceInkEngine.swift`, `RecorderUIManager.swift` — UNTOUCHED. The Scratchpad doesn't subscribe to engine state; the dictation-into-place hook lives in `TranscriptionPipeline.swift` (the only pipeline-side touchpoint).
- All test files — W12.E ships no new tests. Per master plan §0 Q10.
- Existing `MiniRecorderShortcutManager.setupRecorderShortcuts(...)` body — UNTOUCHED behaviorally. T7's first-run default registration is additive (one new line in the existing block).
- `Info.plist`, entitlements files — UNTOUCHED. The Scratchpad uses no new system-level capabilities; the existing accessibility entitlement (already required for `CursorPaster`) covers cursor-position reads.
- `AppDefaults.swift` — UNTOUCHED. Scratchpad has no global flags worth registering as a default; first-launch state is "zero documents" which is computed implicitly.

---

## Migration policy (resolves ambiguity for each design point)

The lead pinned the following architecture decisions for this packet. Restated as the authoritative ruleset for the coder.

1. **SwiftData store choice: local "default" store, NOT the CloudKit "dictionary" store.** Per master plan §3 W12.E ("Single-device persistence only"). The two new `@Model` types join the existing `transcriptSchema` (`Transcription.self` + new siblings) at `VoiceInk.swift:239` and `:275`. The container migration is automatic on first launch (SwiftData lightweight-migration handles net-new entities without app intervention). No `Migration` plan struct, no version stamps. Rationale: Scratchpad is a single-machine workspace; sync conflicts on multi-tab editors are a nightmare to resolve and out-of-scope for v1 per master plan.

2. **Tab cap = 10.** Hard limit. Attempting to open the 11th tab (`⌘T` or `+` button) shows a transient `NotificationManager.shared.showNotification(title: "Tab limit reached (10). Close a tab to add a new one.", type: .info)`. No silent failure. Rationale: the multi-tab UI is intended for a small working set, not a Notion replacement; the 10-cap signals "this is a scratch surface, archive elsewhere if you have more". The cap is `Self.maxTabs = 10` in `ScratchpadStore` (a `static let`). Bump in a follow-up if user reports.

3. **Default first-launch tab count = 1.** When `ScratchpadStore.loadDocuments()` finds zero documents on first launch, it auto-creates one with `title = "Untitled"`, `content = ""`, `tabIndex = 0`. Rationale: empty Scratchpad with no tabs is a confusing UX — the user opens the window and sees nothing. The auto-tab gives them an immediate target.

4. **Tab title derivation: first non-empty line, capped at 30 chars.** The tab strip cell shows `document.title` if explicitly set; otherwise computes "first non-empty line, trimmed, max 30 chars" from `content`, fallback `"Untitled"`. The user MAY rename the tab via a tab-cell long-press (right-click context menu in v1 — simpler than inline edit). The title is auto-recomputed on every save tick UNLESS the user explicitly renamed (sentinel: a separate `userRenamedTitle: Bool` is OUT of scope; v1 always recomputes — if the user renames, on the next typing tick it gets overwritten, which is a known v1 limitation flagged in Risks).

5. **Autosave debounce = 800ms.** Per master plan §3 W12.E. The `ScratchpadStore.updateContent(...)` schedules a Task (`autosaveTask` per document, cancelled on each new keystroke) that sleeps 800ms then writes `document.content = newContent` + `document.updatedAt = Date()` + `try? modelContext.save()`. If the user keeps typing, the task is cancelled and rescheduled. On window close / app quit, the in-flight task is awaited synchronously (or replaced with an immediate save) to ensure no data loss. `windowWillClose` at the controller level calls `store.flushAll()` which awaits any pending autosave tasks.

6. **Version snapshot trigger: every 30s of ACTIVE typing OR on tab switch / window close.** Per master plan §3 W12.E. Implementation: each document carries an in-memory `lastVersionedAt: Date` timestamp (NOT stored — recomputed on launch from the most recent version's `capturedAt`). Each call to `ScratchpadStore.updateContent(...)` checks `if Date().timeIntervalSince(lastVersionedAt) >= 30 { captureVersion(doc); lastVersionedAt = Date() }`. On tab switch (UI signal): `captureVersion(currentDoc, force: true)`. On window close: `captureVersion(currentDoc, force: true)` for the active tab. Rationale: avoids version spam (a single 5-min editing burst gets ~10 snapshots, not one per keystroke) while still capturing every meaningful editing arc.

7. **Version FIFO eviction at 50.** Per master plan §3 W12.E. After every `captureVersion(...)` call, `evictOldVersionsIfNeeded(_ doc:)` queries `doc.versions.sorted { $0.capturedAt < $1.capturedAt }` and `modelContext.delete(...)`s the oldest until count ≤ 50. The cap is `Self.maxVersionsPerDocument = 50` (a `static let`). Cascade delete-rule on the `@Relationship(deleteRule: .cascade)` from `ScratchpadDocument` ensures versions die with the document; the eviction loop is an in-document FIFO bound. Rationale: matches the master plan figure; 50 versions × ~10kB content = 500kB worst case per document × 10 documents = 5MB — negligible storage cost; bound prevents pathological growth.

8. **Restore = capture-then-replace (reversible).** Per master plan §3 W12.E. `ScratchpadStore.restoreVersion(_ version: in doc:)` does:
   1. `captureVersion(doc, force: true)` — snapshot CURRENT state first.
   2. `doc.content = version.content`, `doc.updatedAt = Date()`.
   3. `try? modelContext.save()`.
   4. The new (current) snapshot AND the restored content are both versions in the chain, so the user can undo by restoring the CURRENT-state snapshot. No third "restored" state is stored.

9. **Hotkey toggle semantics: open if closed, focus if open-but-not-key, close if key.** The handler at HotkeyManager:`onKeyUp(for: .scratchpadToggle)` calls `ScratchpadWindowController.shared.toggle(...)`. The controller's `toggle(...)` resolves three states:
   - Window doesn't exist → call `show(modelContainer:)` which creates and orders front.
   - Window exists but `isKeyWindow == false` → `makeKeyAndOrderFront(nil)` + `NSApplication.shared.activate(ignoringOtherApps: true)`.
   - Window exists AND `isKeyWindow == true` → `orderOut(nil)` (hide, don't destroy — preserve tab state).
   Rationale: matches the user's intuition for "toggle" — same key flips state every press. Lifecycle: hide preserves all state (autosave already persisted to SwiftData), show reads from SwiftData on next open.

10. **Default hotkey: `⌥+S` (Option+S).** Per master plan §3 W12.E. Set in `MiniRecorderShortcutManager` (or wherever first-run defaults live — confirm at Task 0). FIRST RUN ONLY (`if KeyboardShortcuts.getShortcut(for: .scratchpadToggle) == nil`). User can rebind via Settings (T10).

11. **Paste-fallback wiring: append the would-be-pasted text as a NEW tab.** Per master plan §3 W12.E. NOT prepend to the active tab — the paste-fallback path fires precisely when the user dictated into something that didn't accept the paste; THEY MAY NOT EVEN HAVE THE SCRATCHPAD OPEN. Forcing the text into the active tab would silently mutate state they're not looking at. Appending as a new tab makes the rescue visible the next time they `⌥+S` to inspect the Scratchpad. The new tab's title auto-derives from the first line (Migration policy #4); content is the rescued text verbatim. **Tab cap interaction:** if the Scratchpad is already at 10 tabs, the rescue tab still gets created — the cap is only enforced on USER-initiated `createTab` calls. The `appendFallbackTab(text:)` path is exempt. Rationale: the rescue path is data-recovery; never silently lose the user's dictation just because they had 10 tabs open. Coder may add a notification ("Paste rescued to Scratchpad — 11 tabs") to surface the cap-bypass.

12. **Dictation-into-place: insert at the active tab's cursor position, REPLACE selected range if any.** When `TranscriptionPipeline` is about to paste AND `ScratchpadWindowController.shared.isFocusedAndKey == true`, instead of `CursorPaster.pasteAtCursor(...)` it calls `ScratchpadWindowController.shared.insertIntoActiveTab(_:)`. The active tab editor's coordinator reads the current `selectedRange()`; if length > 0, it replaces that range with the transcript; otherwise inserts at the caret. The active tab's `content` binding fires its update, which kicks the autosave debounce (Migration policy #5). Cursor moves to the end of the inserted text. **autoSend (Enter, Shift+Enter, etc.) is SUPPRESSED on this path** — see TranscriptionPipeline:207-212; gate the auto-send block on `!Scratchpad.active`.

13. **Paste-fallback DOES NOT also dictate-into-place.** A user can be dictating from anywhere; the Scratchpad-active branch (T9) and the paste-fallback branch (T8) are MUTUALLY EXCLUSIVE: dictation-into-place fires when the Scratchpad IS the focused/key window; paste-fallback fires when SOME OTHER app's text-field rejects the paste. The two paths don't compose. T9's gate at TranscriptionPipeline:205 is the FIRST decision point (Scratchpad?  insert at cursor); else falls through to `CursorPaster.pasteAtCursor(...)` which itself has the W12.E paste-fallback branch (T8).

14. **No glass-backdrop animation on hotkey-summon.** The Scratchpad just orders front. Animation on summon (slide-in, cross-fade) is a polish item; out of scope. The recorder cluster has motion vocabulary; the Scratchpad doesn't need it.

15. **Plain text only.** Per master plan §3 W12.E out-of-scope ("Markdown rendering / rich text. Plain text v1"). The `NSTextView` wrapper sets `isRichText = false`. The `content` field is `String`, never `NSAttributedString`. If the user pastes formatted text, it strips to plain.

16. **No "Untitled 1, Untitled 2" auto-numbering.** Per Migration policy #4, the title auto-derives from content. New empty tab is `"Untitled"` always; once the user types, the title becomes the first line. Multiple "Untitled" tabs are allowed (the tab strip distinguishes by position).

17. **Dictionary CloudKit store DOES NOT receive Scratchpad models.** Per Migration policy #1. If a future packet decides to sync Scratchpad across devices, that packet owns moving the schema to a CloudKit-eligible store + handling conflict resolution. This packet is local-only.

18. **No emoji in new code.** Existing `🦾` log markers stay verbatim (W6/W11 instrumentation). The new `🗒️` log marker for Scratchpad events is FLAGGED as an open question — alternative is plain `scratchpad:` prefix. Recommend lead picks at sign-off; coder ships whichever the lead picks. Documented exception precedent: `🦾`. New convention: case-by-case, lead approves.

19. **No new SPM deps, no deployment-target bump.** Already at 26.0 from W11.B. All APIs used (SwiftData, SwiftUI `TabView`/`TextEditor`, `NSTextView`, `NSWindow`, `KeyboardShortcuts`) are pre-existing.

20. **Single feat commit.** The plan-doc commit + the code commit. Two commits total at merge time. The code commit subject: `feat(scratchpad): W12E — summoned window + multi-tab + 50-version history + paste fallback`. Rollback per `git revert <code-commit-sha>` restores pre-W12.E behavior; SwiftData on-disk rows for `ScratchpadDocument`/`ScratchpadVersion` orphan harmlessly (no read sites left).

---

## Tasks

### Task 0 — Audit + read references

**Files:** none (read-only).

- [ ] **Step 0.1 — Confirm `Transcription` and the existing local-store schema**

```bash
grep -n "Schema\|Transcription.self\|transcriptSchema" VoiceInk/VoiceInk.swift
```

Expected: a top-level `Schema([Transcription.self, VocabularyWord.self, WordReplacement.self])` AND two helpers `createPersistentContainer` / `createInMemoryContainer` each with their own `transcriptSchema` and `dictionarySchema`. The Scratchpad models join `transcriptSchema` (local-only). If the structure has changed (e.g., the helpers were collapsed), reconcile with the lead before proceeding.

- [ ] **Step 0.2 — Confirm `KeyboardShortcuts.Name` registry shape**

```bash
grep -n "KeyboardShortcuts.Name\|static let " VoiceInk/HotkeyManager.swift VoiceInk/MiniRecorderShortcutManager.swift
```

Expected: extension at `HotkeyManager.swift:7-15` declaring `toggleMiniRecorder`, `toggleMiniRecorder2`, `pasteLastTranscription`, `pasteLastEnhancement`, `retryLastTranscription`, `openHistoryWindow`, `quickAddToDictionary` plus the `MiniRecorderShortcutManager.swift` extension declaring `escapeRecorder`, `cancelRecorder`, `toggleEnhancement`, `selectPowerMode1`-`5`. Pick `HotkeyManager.swift:7-15` as the home for `.scratchpadToggle` (it's the global shortcuts namespace; `MiniRecorderShortcutManager`'s namespace is recorder-modal-only).

- [ ] **Step 0.3 — Confirm `HistoryWindowController` shape (mirror target)**

```bash
sed -n '1,82p' VoiceInk/HistoryWindowController.swift
```

Expected: 82-LOC singleton with `static let shared`, `historyWindow: NSWindow?`, `windowIdentifier`, `windowAutosaveName`, `showHistoryWindow(modelContainer:engine:)`, `createHistoryWindow(modelContainer:engine:)`, `windowWillClose(_:)`, `windowDidBecomeKey(_:)`. The Scratchpad controller is a near-copy with two differences: (a) different identifier + autosave name, (b) `appendAsNewTab(text:)` and `insertIntoActiveTab(_:)` extra methods for the paste-fallback / dictation-into-place hooks.

- [ ] **Step 0.4 — Confirm `WindowManager.configureWindow(_:)` glass flags**

```bash
sed -n '19,48p' VoiceInk/WindowManager.swift
```

Expected: `requiredStyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]`, `titlebarAppearsTransparent = true`, `titleVisibility = .hidden`, `backgroundColor = .clear`, `isReleasedWhenClosed = false`, `isOpaque = false`. Mirror these in `ScratchpadWindowController.createScratchpadWindow(...)`. **Do NOT call `WindowManager.shared.configureWindow(...)` directly** — that registers the window as the main app window, which would overwrite the `mainWindow` weak ref.

- [ ] **Step 0.5 — Confirm `CursorPaster` paste-fallback branch shape**

```bash
sed -n '34,50p' VoiceInk/CursorPaster.swift
```

Expected: `let hasPasteTarget = focusedElementAcceptsText()`; `let mustForceClipboard = !hasPasteTarget`; sets clipboard non-transient if `mustForceClipboard`; logs notice; shows notification "Copied to clipboard (no text field focused)"; `return`. T8 inserts a single dispatch (`ScratchpadStore.shared.appendFallbackTab(text:)`) BEFORE the `return`. The notification stays — the user sees "Copied to clipboard (no text field focused)" PLUS the rescue tab appears.

- [ ] **Step 0.6 — Confirm pipeline paste call site**

```bash
grep -n "CursorPaster.pasteAtCursor\|performAutoSend" VoiceInk/Transcription/Engine/TranscriptionPipeline.swift
```

Expected: call at line 205 + the auto-send block at line 207-212. T9 wraps both in a Scratchpad-active gate.

- [ ] **Step 0.7 — Locate the existing first-run shortcut-default registration**

```bash
grep -rn "setShortcut.*\.init\|setShortcut(\.init" VoiceInk --include="*.swift"
```

Expected: matches in `MiniRecorderShortcutManager.swift:140-144` (PowerMode 1-5 defaults) plus possibly `MiniRecorderShortcutManager.swift:94` (escape default). Pick the closest analogue for the Scratchpad's `⌥+S` first-run default. If the lead has moved first-run shortcut defaults elsewhere (e.g., a dedicated `DefaultShortcuts.swift`), use that.

- [ ] **Step 0.8 — Confirm SettingsCard / hotkey settings host file**

```bash
grep -rn "KeyboardShortcuts.Recorder\|HotkeySettingsView\|GeneralSettingsView" VoiceInk/Views --include="*.swift" | head -10
```

Expected: at least one `KeyboardShortcuts.Recorder("…", name: .…)` row in a settings file. T10 adds a sibling row for `.scratchpadToggle`. If no such file is found (different shortcut UX in the fork), reconcile with lead.

- [ ] **Step 0.9 — Confirm `NotificationManager` shape for the 10-tab cap notification**

```bash
grep -n "showNotification\|NotificationManager" VoiceInk/Notifications/AppNotifications.swift VoiceInk/Notifications/NotificationManager.swift 2>/dev/null
```

Expected: `NotificationManager.shared.showNotification(title:type:)` exists and accepts `.info`/`.warn` types. T3's tab-cap path calls this when the user tries to open the 11th tab.

---

### Task 1 — Define `ScratchpadDocument` + `ScratchpadVersion` `@Model` types

**Files:**
- Create: `VoiceInk/Models/ScratchpadDocument.swift`
- Create: `VoiceInk/Models/ScratchpadVersion.swift`
- Modify: `VoiceInk/VoiceInk.swift` (Schema + container config)

- [ ] **Step 1.1 — Write `ScratchpadDocument`**

```swift
import Foundation
import SwiftData

/// W12.E Scratchpad document. One per tab. Plain-text content with auto-save
/// (debounced 800ms) and per-document version history (50-cap FIFO via
/// `ScratchpadVersion`). Local-only (no CloudKit). See plan
/// `docs/superpowers/plans/W12E-scratchpad.md` §Migration policy #1.
@Model
final class ScratchpadDocument {
    var id: UUID
    var title: String
    var content: String
    var tabIndex: Int
    var createdAt: Date
    var updatedAt: Date

    /// Cascade delete-rule: when a document is deleted, its version snapshots
    /// die with it. Bounded count (Migration policy #7); blast radius is
    /// per-document.
    @Relationship(deleteRule: .cascade, inverse: \ScratchpadVersion.document)
    var versions: [ScratchpadVersion] = []

    init(title: String = "Untitled",
         content: String = "",
         tabIndex: Int = 0) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.tabIndex = tabIndex
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
```

- [ ] **Step 1.2 — Write `ScratchpadVersion`**

```swift
import Foundation
import SwiftData

/// W12.E version snapshot of a Scratchpad document. Captured every 30s of
/// active typing OR on tab switch / window close. FIFO-evicted at 50 per
/// document. See plan `docs/superpowers/plans/W12E-scratchpad.md`
/// §Migration policy #6 + #7.
@Model
final class ScratchpadVersion {
    var id: UUID
    var content: String
    var capturedAt: Date

    var document: ScratchpadDocument?

    init(content: String, document: ScratchpadDocument) {
        self.id = UUID()
        self.content = content
        self.capturedAt = Date()
        self.document = document
    }
}
```

- [ ] **Step 1.3 — Add the new entities to the Schema**

In `VoiceInk/VoiceInk.swift`, three sites:

1. Top-level schema at line 53-57:

```swift
let schema = Schema([
    Transcription.self,
    VocabularyWord.self,
    WordReplacement.self,
    ScratchpadDocument.self,   // W12.E
    ScratchpadVersion.self     // W12.E
])
```

2. Persistent container's `transcriptSchema` at line 239:

```swift
let transcriptSchema = Schema([
    Transcription.self,
    ScratchpadDocument.self,   // W12.E — local-only, joins default store
    ScratchpadVersion.self     // W12.E
])
```

3. In-memory container's `transcriptSchema` at line 275:

```swift
let transcriptSchema = Schema([
    Transcription.self,
    ScratchpadDocument.self,
    ScratchpadVersion.self
])
```

The `dictionarySchema` (CloudKit-synced) is UNTOUCHED at both lines 248 and 283.

- [ ] **Step 1.4 — Verify**

```bash
grep -rn "ScratchpadDocument\|ScratchpadVersion" VoiceInk --include="*.swift"
```

Expected: definitions in the two new files + 3 schema additions in `VoiceInk.swift`. No call sites yet (T3 onwards add them).

**Risk:** MED — adding entities to the SwiftData store on first launch triggers a lightweight migration. SwiftData handles net-new entities without intervention IF the existing `Schema` array decisions don't conflict (they don't — Transcription is independent). If reviewer prefers an explicit `MigrationPlan`, push that to a follow-up.

**Verification:** type-check passes. Manual: launch app, observe no crash on container init. Confirm via Console that no SwiftData migration error surfaces.

---

### Task 2 — Register `.scratchpadToggle`

**Files:**
- Modify: `VoiceInk/HotkeyManager.swift`

- [ ] **Step 2.1 — Add the new shortcut name**

In `VoiceInk/HotkeyManager.swift:7-15`, append:

```swift
extension KeyboardShortcuts.Name {
    static let toggleMiniRecorder = Self("toggleMiniRecorder")
    static let toggleMiniRecorder2 = Self("toggleMiniRecorder2")
    static let pasteLastTranscription = Self("pasteLastTranscription")
    static let pasteLastEnhancement = Self("pasteLastEnhancement")
    static let retryLastTranscription = Self("retryLastTranscription")
    static let openHistoryWindow = Self("openHistoryWindow")
    static let quickAddToDictionary = Self("quickAddToDictionary")
    static let scratchpadToggle = Self("scratchpadToggle")  // W12.E
}
```

- [ ] **Step 2.2 — Verify**

```bash
grep -n "scratchpadToggle" VoiceInk/HotkeyManager.swift
```

Expected: one match (the static-let definition). T7 will add the `onKeyUp` handler.

**Risk:** LOW — pure additive extension case. The `KeyboardShortcuts` library auto-persists user customization keyed by raw string; no migration needed.

**Verification:** type-check passes.

---

### Task 3 — `ScratchpadStore` service

**Files:**
- Create: `VoiceInk/Services/ScratchpadStore.swift`

- [ ] **Step 3.1 — Skeleton**

```swift
import Foundation
import SwiftData
import SwiftUI
import os

/// W12.E Scratchpad store. Owns SwiftData CRUD for `ScratchpadDocument` +
/// `ScratchpadVersion`, the 800ms autosave debounce, the 30s version-snapshot
/// cadence, the 50-version FIFO eviction, and the paste-fallback append path.
/// See plan `docs/superpowers/plans/W12E-scratchpad.md` §Task 3 +
/// §Migration policy #5/#6/#7/#11.
@MainActor
final class ScratchpadStore: ObservableObject {

    static let maxTabs = 10                  // §Migration policy #2
    static let maxVersionsPerDocument = 50   // §Migration policy #7
    private static let autosaveDebounceMs: UInt64 = 800_000_000
    private static let versionInterval: TimeInterval = 30  // seconds

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink",
                                 category: "ScratchpadStore")

    @Published private(set) var documents: [ScratchpadDocument] = []
    @Published var activeTabId: UUID?

    private var autosaveTasks: [UUID: Task<Void, Never>] = [:]
    private var lastVersionedAt: [UUID: Date] = [:]

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadDocuments()
        if documents.isEmpty {
            _ = createTab(at: 0)
        }
        activeTabId = documents.first?.id
    }
```

- [ ] **Step 3.2 — `loadDocuments`**

```swift
    func loadDocuments() {
        let descriptor = FetchDescriptor<ScratchpadDocument>(
            sortBy: [SortDescriptor(\.tabIndex, order: .forward)]
        )
        documents = (try? modelContext.fetch(descriptor)) ?? []
        // Seed lastVersionedAt from the most recent version per document.
        for doc in documents {
            if let latest = doc.versions.max(by: { $0.capturedAt < $1.capturedAt }) {
                lastVersionedAt[doc.id] = latest.capturedAt
            }
        }
    }
```

- [ ] **Step 3.3 — `createTab` / `closeTab` (with cap enforcement)**

```swift
    /// Returns the new document, or nil if at the cap.
    @discardableResult
    func createTab(at index: Int? = nil) -> ScratchpadDocument? {
        guard documents.count < Self.maxTabs else {
            NotificationManager.shared.showNotification(
                title: "Tab limit reached (\(Self.maxTabs)). Close a tab to add a new one.",
                type: .info
            )
            return nil
        }
        let insertAt = index ?? documents.count
        let doc = ScratchpadDocument(tabIndex: insertAt)
        modelContext.insert(doc)
        // Reindex tabs at or after the insertion point.
        for existing in documents where existing.tabIndex >= insertAt {
            existing.tabIndex += 1
        }
        documents.insert(doc, at: insertAt)
        activeTabId = doc.id
        try? modelContext.save()
        return doc
    }

    func closeTab(_ document: ScratchpadDocument) {
        // Capture-then-evict so closing isn't a silent data loss.
        captureVersion(document, force: true)
        cancelAutosave(document.id)
        modelContext.delete(document)
        documents.removeAll { $0.id == document.id }
        // Reindex.
        for (idx, existing) in documents.enumerated() {
            existing.tabIndex = idx
        }
        // Activate the next available tab; create one if all are gone.
        if activeTabId == document.id {
            if let next = documents.first {
                activeTabId = next.id
            } else {
                _ = createTab()
            }
        }
        try? modelContext.save()
    }
```

- [ ] **Step 3.4 — `updateContent` with debounced autosave + version-snapshot cadence**

```swift
    /// Called from the SwiftUI editor on every text change. Schedules a
    /// debounced 800ms write + checks the 30s version-snapshot cadence.
    func updateContent(_ document: ScratchpadDocument, content: String) {
        document.content = content
        document.title = derivedTitle(from: content)
        document.updatedAt = Date()

        // Cancel any pending autosave for this doc; reschedule.
        cancelAutosave(document.id)
        let docId = document.id
        autosaveTasks[docId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autosaveDebounceMs)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                try? self.modelContext.save()
                self.maybeCaptureVersion(document)
                self.autosaveTasks[docId] = nil
            }
        }
    }

    private func maybeCaptureVersion(_ document: ScratchpadDocument) {
        let last = lastVersionedAt[document.id] ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.versionInterval {
            captureVersion(document, force: false)
        }
    }

    private func cancelAutosave(_ id: UUID) {
        autosaveTasks[id]?.cancel()
        autosaveTasks[id] = nil
    }
```

- [ ] **Step 3.5 — `captureVersion` + FIFO eviction**

```swift
    func captureVersion(_ document: ScratchpadDocument, force: Bool) {
        // Defensive: don't snapshot empty content unless the user explicitly
        // asked (force=true). Avoids a snapshot on every newly-opened tab.
        if !force && document.content.isEmpty { return }

        let version = ScratchpadVersion(content: document.content, document: document)
        modelContext.insert(version)
        lastVersionedAt[document.id] = Date()
        evictOldVersionsIfNeeded(document)
        try? modelContext.save()
        logger.notice("scratchpad: captured version for \(document.id, privacy: .public) — \(document.versions.count, privacy: .public) total")
    }

    private func evictOldVersionsIfNeeded(_ document: ScratchpadDocument) {
        guard document.versions.count > Self.maxVersionsPerDocument else { return }
        let sorted = document.versions.sorted { $0.capturedAt < $1.capturedAt }
        let evictionCount = document.versions.count - Self.maxVersionsPerDocument
        for victim in sorted.prefix(evictionCount) {
            modelContext.delete(victim)
        }
    }
```

- [ ] **Step 3.6 — `restoreVersion` (capture-then-replace)**

```swift
    func restoreVersion(_ version: ScratchpadVersion, in document: ScratchpadDocument) {
        // Capture current state FIRST so restore is reversible.
        captureVersion(document, force: true)
        document.content = version.content
        document.updatedAt = Date()
        try? modelContext.save()
    }
```

- [ ] **Step 3.7 — `appendFallbackTab` (paste-fallback hook)**

```swift
    /// Paste-fallback landing site. The text the user dictated couldn't be
    /// pasted into the foreground app (no focused text field, sandbox refusal,
    /// etc.) — `CursorPaster` calls this to rescue the dictation into a new
    /// Scratchpad tab. Bypasses the user-tab-cap (Migration policy #11).
    func appendFallbackTab(text: String) {
        let doc = ScratchpadDocument(
            content: text,
            tabIndex: documents.count
        )
        modelContext.insert(doc)
        documents.append(doc)
        try? modelContext.save()
        logger.notice("scratchpad: rescued paste into new tab — total \(self.documents.count, privacy: .public)")
        if documents.count > Self.maxTabs {
            NotificationManager.shared.showNotification(
                title: "Paste rescued to Scratchpad — \(self.documents.count) tabs (over \(Self.maxTabs)-cap)",
                type: .info
            )
        } else {
            NotificationManager.shared.showNotification(
                title: "Paste rescued to Scratchpad — open with ⌥+S",
                type: .info
            )
        }
    }
```

- [ ] **Step 3.8 — `flushAll` for window close**

```swift
    /// Awaits any pending autosave tasks. Called from the window controller's
    /// `windowWillClose` to ensure no in-flight 800ms debounce drops content.
    func flushAll() async {
        let tasks = Array(autosaveTasks.values)
        for task in tasks { _ = await task.value }
        try? modelContext.save()
    }
```

- [ ] **Step 3.9 — Title derivation helper**

```swift
    private func derivedTitle(from content: String) -> String {
        let firstLine = content
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        if firstLine.isEmpty { return "Untitled" }
        return String(firstLine.prefix(30))
    }
}
```

- [ ] **Step 3.10 — Verify**

```bash
grep -rn "ScratchpadStore" VoiceInk --include="*.swift"
```

Expected: only the new file. T4-T9 add call sites.

**Risk:** MED — async coalescing of autosave tasks + the 30s cadence interplay can produce surprising lost-write windows. The skeleton is conservative (capture-on-close via `flushAll`, capture-on-tab-switch via the View layer calling `captureVersion(force: true)`).

**Verification:** type-check passes. Manual scenario: type 5s, pause 1s, type 5s → expect ONE version snapshot at the 30s mark, NOT two; the second typing burst extends the cadence window.

---

### Task 4 — `ScratchpadWindowController` + `ScratchpadWindow`

**Files:**
- Create: `VoiceInk/Views/Scratchpad/ScratchpadWindowController.swift`
- Create: `VoiceInk/Views/Scratchpad/ScratchpadWindow.swift`

- [ ] **Step 4.1 — Write `ScratchpadWindow`**

```swift
import AppKit

/// W12.E Scratchpad window. Activatable (unlike `MiniRecorderPanel`) so the
/// hosted `TextEditor` can become first responder, ⌘T/⌘W chord routing
/// works, and the dictation-into-place hook can read selectedRange. See plan
/// §Task 4.
final class ScratchpadWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

- [ ] **Step 4.2 — Write `ScratchpadWindowController`**

```swift
import SwiftUI
import SwiftData
import AppKit

/// W12.E summoned-window controller. Mirrors `HistoryWindowController` shape;
/// adds `appendAsNewTab(text:)` and `insertIntoActiveTab(_:)` for paste-
/// fallback and dictation-into-place. See plan §Task 4 + §Migration policy #9.
@MainActor
final class ScratchpadWindowController: NSObject, NSWindowDelegate {
    static let shared = ScratchpadWindowController()

    private var window: ScratchpadWindow?
    private var store: ScratchpadStore?
    private let identifier = NSUserInterfaceItemIdentifier("com.prakashjoshipax.voiceink.scratchpadWindow")
    private let autosaveName = NSWindow.FrameAutosaveName("VoiceInkScratchpadWindowFrame")

    private override init() { super.init() }

    /// Returns true when the Scratchpad is the key window AND a tab editor
    /// is the first responder — the dictation-into-place gate.
    var isFocusedAndKey: Bool {
        guard let window, window.isKeyWindow else { return false }
        // First-responder is a chain — accept any descendant of the contentView.
        return window.firstResponder is NSTextView
    }

    func toggle(modelContainer: ModelContainer) {
        if window == nil {
            show(modelContainer: modelContainer)
        } else if window?.isKeyWindow == true {
            window?.orderOut(nil)
        } else {
            window?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func show(modelContainer: ModelContainer) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            return
        }
        let store = ScratchpadStore(modelContext: modelContainer.mainContext)
        self.store = store
        window = createScratchpadWindow(store: store, modelContainer: modelContainer)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    /// Paste-fallback hook — append the rescued text as a new tab. Does NOT
    /// open the window (the user finds it via ⌥+S; opening unprompted would
    /// steal focus from whatever they're currently doing).
    func appendAsNewTab(text: String, modelContainer: ModelContainer) {
        if store == nil {
            store = ScratchpadStore(modelContext: modelContainer.mainContext)
        }
        store?.appendFallbackTab(text: text)
    }

    /// Dictation-into-place hook — insert at the active editor's cursor.
    func insertIntoActiveTab(_ text: String) {
        guard let textView = window?.firstResponder as? NSTextView else { return }
        let range = textView.selectedRange()
        textView.replaceCharacters(in: range, with: text)
    }

    // MARK: - Window construction

    private func createScratchpadWindow(store: ScratchpadStore,
                                         modelContainer: ModelContainer) -> ScratchpadWindow {
        let view = ScratchpadView(store: store)
            .modelContainer(modelContainer)
            .frame(minWidth: 720, minHeight: 480)

        let host = NSHostingController(rootView: view)

        let win = ScratchpadWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.contentViewController = host
        win.title = "VoiceInk — Scratchpad"
        win.identifier = identifier
        win.delegate = self
        // Mirror `WindowManager.configureWindow` glass flags. Per plan
        // §Migration policy via spec §6.1 / W8.
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.backgroundColor = .clear
        win.isReleasedWhenClosed = false
        win.isOpaque = false
        win.collectionBehavior = [.fullScreenPrimary]
        win.minSize = NSSize(width: 720, height: 480)
        win.setFrameAutosaveName(autosaveName)
        if !win.setFrameUsingName(autosaveName) {
            win.center()
        }
        return win
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let win = notification.object as? NSWindow,
              win.identifier == identifier else { return }
        // Flush any in-flight autosave debounces so close isn't lossy.
        Task { [store] in
            await store?.flushAll()
        }
        window = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 4.3 — Verify**

```bash
grep -rn "ScratchpadWindowController" VoiceInk --include="*.swift"
```

Expected: only the two new files. T7-T9 add call sites.

**Risk:** MED — `firstResponder is NSTextView` is the load-bearing check for `isFocusedAndKey`; if the SwiftUI editor's underlying responder shape differs (a wrapping `NSScrollView` etc.), the gate misses. Confirm the responder type at smoke time (Task 12.2).

**Verification:** type-check passes. Manual: `⌥+S` opens the window with the glass flags; close button releases the window; `⌥+S` again recreates.

---

### Task 5 — `ScratchpadView` root (multi-tab chrome)

**Files:**
- Create: `VoiceInk/Views/Scratchpad/ScratchpadView.swift`

- [ ] **Step 5.1 — Skeleton**

```swift
import SwiftUI
import SwiftData

/// W12.E root view. Multi-tab chrome with custom strip, ⌘T new, ⌘W close,
/// ⌘1-⌘9 jump. Capped at 10 user-created tabs (paste-fallback bypasses the
/// cap). See plan §Migration policy #2.
struct ScratchpadView: View {
    @ObservedObject var store: ScratchpadStore

    var body: some View {
        VStack(spacing: 0) {
            tabStrip
            Divider().opacity(0.4)
            if let active = activeDocument {
                ScratchpadTabEditor(document: active, store: store)
                    .id(active.id)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .adaptiveGlassBackground(intensity: .panel)
        .background(KeyShortcutCatcher(store: store))
    }

    private var activeDocument: ScratchpadDocument? {
        store.documents.first { $0.id == store.activeTabId }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(.secondary)
            Text("No tabs. Press ⌘T to create one.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(store.documents.enumerated()), id: \.element.id) { idx, doc in
                    tabCell(doc, index: idx)
                }
                addTabButton
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    private func tabCell(_ doc: ScratchpadDocument, index: Int) -> some View {
        let isActive = doc.id == store.activeTabId
        return HStack(spacing: 6) {
            Text(doc.title.isEmpty ? "Untitled" : doc.title)
                .font(.system(size: 12, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
            Button(action: { store.closeTab(doc) }) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? Palette.accent.opacity(0.18) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Palette.hairlineSoft, lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            // Capture the previous tab's state on switch.
            if let prev = activeDocument, prev.id != doc.id {
                store.captureVersion(prev, force: true)
            }
            store.activeTabId = doc.id
        }
    }

    private var addTabButton: some View {
        Button(action: { _ = store.createTab() }) {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .disabled(store.documents.count >= ScratchpadStore.maxTabs)
        .opacity(store.documents.count >= ScratchpadStore.maxTabs ? 0.4 : 1.0)
    }
}
```

- [ ] **Step 5.2 — `KeyShortcutCatcher` for ⌘T / ⌘W / ⌘1-⌘9**

```swift
/// W12.E keyboard chord routing. SwiftUI's `.keyboardShortcut(...)` doesn't
/// reliably bubble through `TextEditor`'s consumed-events, so we use a
/// hidden `NSView`-backed event monitor that fires on the local event queue
/// only when the Scratchpad window is key.
private struct KeyShortcutCatcher: NSViewRepresentable {
    @ObservedObject var store: ScratchpadStore

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers {
            case "t":
                _ = store.createTab()
                return nil
            case "w":
                if let active = store.documents.first(where: { $0.id == store.activeTabId }) {
                    store.closeTab(active)
                }
                return nil
            default:
                if let chars = event.charactersIgnoringModifiers,
                   let n = Int(chars), (1...9).contains(n),
                   n - 1 < store.documents.count {
                    let target = store.documents[n - 1]
                    if let prev = store.documents.first(where: { $0.id == store.activeTabId }),
                       prev.id != target.id {
                        store.captureVersion(prev, force: true)
                    }
                    store.activeTabId = target.id
                    return nil
                }
                return event
            }
        }
        context.coordinator.monitor = monitor
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var monitor: Any?
    }
}
```

- [ ] **Step 5.3 — Verify**

```bash
grep -rn "ScratchpadView\|KeyShortcutCatcher" VoiceInk --include="*.swift"
```

Expected: only the new file + the use-site in `ScratchpadWindowController`.

**Risk:** MED — SwiftUI `TabView` with custom chrome on macOS is finicky; the design here SKIPS `TabView` entirely (custom strip + active-doc switch), which is more controllable but does mean keyboard chord routing must be implemented by hand (the `KeyShortcutCatcher` `NSView`). The local-monitor approach is the same one `HotkeyManager` uses for modifier-key tracking — known-good idiom.

**Verification:** type-check passes. Manual: open Scratchpad, ⌘T creates a tab, ⌘W closes it, ⌘1/⌘2 jump.

---

### Task 6 — `ScratchpadTabEditor` (NSTextView wrapper) + version-history sheet

**Files:**
- Create: `VoiceInk/Views/Scratchpad/ScratchpadTabEditor.swift`
- Create: `VoiceInk/Views/Scratchpad/ScratchpadVersionHistorySheet.swift`

- [ ] **Step 6.1 — Editor body**

```swift
import SwiftUI
import AppKit

/// W12.E single-tab editor. Wraps `NSTextView` so we can read selectedRange
/// (for dictation-into-place) and drive autosave via `textDidChange`.
/// `TextEditor` doesn't expose either.
struct ScratchpadTabEditor: View {
    @ObservedObject var document: ScratchpadDocument
    @ObservedObject var store: ScratchpadStore

    @State private var showHistory = false

    var body: some View {
        VStack(spacing: 0) {
            ScratchpadTextView(document: document, store: store)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(savedAgoString)
                .font(.caption2)
                .foregroundColor(.secondary)
            Spacer()
            Button("History") { showHistory = true }
                .buttonStyle(.borderless)
                .font(.caption)
                .disabled(document.versions.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(isPresented: $showHistory) {
            ScratchpadVersionHistorySheet(document: document, store: store)
        }
    }

    private var savedAgoString: String {
        let delta = Date().timeIntervalSince(document.updatedAt)
        if delta < 2 { return "Saved" }
        if delta < 60 { return "Saved \(Int(delta))s ago" }
        let minutes = Int(delta / 60)
        return "Saved \(minutes)m ago"
    }
}
```

- [ ] **Step 6.2 — `ScratchpadTextView` (NSViewRepresentable)**

```swift
private struct ScratchpadTextView: NSViewRepresentable {
    @ObservedObject var document: ScratchpadDocument
    @ObservedObject var store: ScratchpadStore

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = document.content
        context.coordinator.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Reflect external changes (e.g., restoreVersion) without breaking
        // the user's in-flight selection.
        if textView.string != document.content {
            let range = textView.selectedRange()
            textView.string = document.content
            // Clamp the prior selection to the new text length.
            let clamped = NSRange(
                location: min(range.location, document.content.utf16.count),
                length: 0
            )
            textView.setSelectedRange(clamped)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: ScratchpadTextView
        weak var textView: NSTextView?

        init(_ parent: ScratchpadTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.store.updateContent(parent.document, content: textView.string)
        }
    }
}
```

- [ ] **Step 6.3 — `ScratchpadVersionHistorySheet`**

```swift
import SwiftUI

/// W12.E version-history sheet. Lists up to 50 most-recent snapshots; user
/// taps Restore to capture-then-replace (Migration policy #8). See plan
/// §Task 6.
struct ScratchpadVersionHistorySheet: View {
    @ObservedObject var document: ScratchpadDocument
    @ObservedObject var store: ScratchpadStore
    @Environment(\.dismiss) private var dismiss

    private var sortedVersions: [ScratchpadVersion] {
        document.versions.sorted { $0.capturedAt > $1.capturedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Version History")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            if sortedVersions.isEmpty {
                Spacer()
                Text("No versions captured yet.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(sortedVersions, id: \.id) { v in
                            row(v)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    private func row(_ v: ScratchpadVersion) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(formatted(v.capturedAt))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                Text(v.content.prefix(120))
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Restore") {
                store.restoreVersion(v, in: document)
                dismiss()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.gray.opacity(0.06))
        )
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    private func formatted(_ date: Date) -> String {
        Self.formatter.string(from: date)
    }
}
```

- [ ] **Step 6.4 — Verify**

```bash
grep -rn "ScratchpadTabEditor\|ScratchpadVersionHistorySheet\|ScratchpadTextView" VoiceInk --include="*.swift"
```

Expected: definitions in the two new files + use-site in `ScratchpadView`.

**Risk:** MED — `NSTextView`'s `string` property assignment in `updateNSView` rewrites the buffer; the selection-clamp dance preserves cursor across external rewrites (e.g., restoreVersion). Edge case: if the user is mid-paragraph and `restoreVersion` fires, selection drops to position 0 (clamp truncates length to 0). Acceptable for v1; the user explicitly invoked Restore.

**Verification:** type-check passes. Manual: type into the editor, see "Saved 1s ago" → "Saved 5s ago". Open History after 30s+ of typing — see at least one version. Tap Restore — content reverts, current state captured first.

---

### Task 7 — Hotkey wiring (default + onKeyUp)

**Files:**
- Modify: `VoiceInk/HotkeyManager.swift`
- Modify: `VoiceInk/MiniRecorderShortcutManager.swift` (or wherever first-run defaults live — confirmed at Task 0.7)

- [ ] **Step 7.1 — Add `onKeyUp` handler in `HotkeyManager.init`**

In `VoiceInk/HotkeyManager.swift` near line 192-200 (alongside `openHistoryWindow`), add:

```swift
KeyboardShortcuts.onKeyUp(for: .scratchpadToggle) { [weak self] in
    guard let self = self else { return }
    Task { @MainActor in
        ScratchpadWindowController.shared.toggle(
            modelContainer: self.engine.modelContext.container
        )
    }
}
```

- [ ] **Step 7.2 — Set first-run default `⌥+S`**

In `VoiceInk/MiniRecorderShortcutManager.swift` near line 140-144 (the first-run defaults block; confirm exact location at Task 0.7), add:

```swift
if KeyboardShortcuts.getShortcut(for: .scratchpadToggle) == nil {
    KeyboardShortcuts.setShortcut(.init(.s, modifiers: .option), for: .scratchpadToggle)
}
```

The `if` guard ensures we never overwrite user customization (the lead's CLAUDE.md `feedback_no_confirmation_trivial.md` rule indirectly applies — user config wins, never silently mutated).

- [ ] **Step 7.3 — Verify**

```bash
grep -rn "scratchpadToggle" VoiceInk --include="*.swift"
```

Expected: Name extension + onKeyUp + first-run default + (T10) Settings recorder row.

**Risk:** LOW — sibling-shape registration. The `⌥+S` default may collide with a user-bound shortcut elsewhere in their system (Mission Control, Spotlight, third-party apps). The `KeyboardShortcuts` library handles conflicts gracefully (the user can rebind via T10). Open question for lead: confirm `⌥+S` is acceptable as default given the user's keyboard shortcut landscape.

**Verification:** type-check passes. Manual: fresh launch, press `⌥+S` → window opens. Press again → closes. Press while window is open but app is in background → window comes forward.

---

### Task 8 — `CursorPaster` paste-fallback branch

**Files:**
- Modify: `VoiceInk/CursorPaster.swift`

- [ ] **Step 8.1 — Add the rescue dispatch INSIDE the existing `mustForceClipboard` branch**

In `VoiceInk/CursorPaster.swift:41-50`, replace:

```swift
if mustForceClipboard {
    logger.notice("No focused text field — text copied to clipboard, skipping paste keystroke")
    Task { @MainActor in
        NotificationManager.shared.showNotification(
            title: "Copied to clipboard (no text field focused)",
            type: .info
        )
    }
    return
}
```

with:

```swift
if mustForceClipboard {
    logger.notice("No focused text field — text copied to clipboard, skipping paste keystroke")
    // W12.E paste-fallback: append the rescued text as a new Scratchpad tab
    // so the user can recover it via ⌥+S. Does NOT open the Scratchpad
    // window; the existing notification surfaces the rescue. Migration
    // policy #11 + plan §Task 8.
    Task { @MainActor in
        NotificationManager.shared.showNotification(
            title: "Copied to clipboard (no text field focused)",
            type: .info
        )
        if let container = ScratchpadModelContainerProvider.shared.modelContainer {
            ScratchpadWindowController.shared.appendAsNewTab(
                text: text, modelContainer: container
            )
        }
    }
    return
}
```

- [ ] **Step 8.2 — Wire the model container provider**

`CursorPaster` is a `class` with `static func`s — no inherent access to the SwiftData container. Add a tiny container-provider singleton so the paste-fallback can reach it:

Create `VoiceInk/Services/ScratchpadModelContainerProvider.swift` (~25 LOC):

```swift
import Foundation
import SwiftData

/// W12.E shim — exposes the app-level SwiftData container to static call
/// sites (chiefly `CursorPaster`). Wired during `VoiceInkApp.init` after the
/// container is created. See plan §Task 8.2.
@MainActor
final class ScratchpadModelContainerProvider {
    static let shared = ScratchpadModelContainerProvider()
    private init() {}
    var modelContainer: ModelContainer?
}
```

In `VoiceInk/VoiceInk.swift`, after the `container = ...` assignment in `init()` (around line 90), add:

```swift
ScratchpadModelContainerProvider.shared.modelContainer = container
```

- [ ] **Step 8.3 — Verify the happy path is untouched**

```bash
sed -n '11,98p' VoiceInk/CursorPaster.swift
```

Expected: lines 11-39 (clipboard save + `hasPasteTarget` detection + clipboard set) UNCHANGED. Lines 41-50 (the `mustForceClipboard` branch) gain the W12.E rescue dispatch. Lines 52-95 (the happy-path keystroke) UNCHANGED. Lines 100-135 (`focusedElementAcceptsText`) UNCHANGED.

**Risk:** MED — the constraint is "MUST NOT change `CursorPaster.paste()` happy-path behavior". Confirm by diffing the function start-to-end and noting that all changes are inside `if mustForceClipboard { … }` block. The rescue dispatch is on the main queue Task (already used for the notification), so it doesn't add new threading cost.

**Verification:** type-check passes. Manual: dictate into a sandboxed app where paste fails (e.g., 1Password lock screen) → notification appears + Scratchpad window receives a new tab next time `⌥+S` opens it.

---

### Task 9 — Dictation-into-place hook in `TranscriptionPipeline`

**Files:**
- Modify: `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift`

- [ ] **Step 9.1 — Gate the paste call on `Scratchpad.isFocusedAndKey`**

In `VoiceInk/Transcription/Engine/TranscriptionPipeline.swift:191-214`, replace the `if let textToPaste = finalPastedText, …` block with:

```swift
if let textToPaste = finalPastedText,
   transcription.transcriptionStatus == TranscriptionStatus.completed.rawValue {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.015) {
        // P3.F: pre-paste cue. (unchanged; see prior comment)
        if didEnhance {
            SoundManager.shared.playEnhanceComplete()
        } else if !didFireTranscribeCue {
            SoundManager.shared.playTranscribeComplete()
        }
        let appendSpace = UserDefaults.standard.bool(forKey: "AppendTrailingSpace")
        let textToInsert = textToPaste + (appendSpace ? " " : "")

        // W12.E dictation-into-place: when the Scratchpad is the key window
        // and a tab editor holds first-responder, route the transcript into
        // the active tab at cursor position. Suppresses auto-send (no
        // unwanted ⏎ inside the Scratchpad). See plan §Migration policy #12.
        if ScratchpadWindowController.shared.isFocusedAndKey {
            ScratchpadWindowController.shared.insertIntoActiveTab(textToInsert)
            return
        }

        CursorPaster.pasteAtCursor(textToInsert)

        let powerMode = PowerModeManager.shared
        if let activeConfig = powerMode.currentActiveConfiguration, activeConfig.autoSendKey.isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                CursorPaster.performAutoSend(activeConfig.autoSendKey)
            }
        }
    }
}
```

The `return` after `insertIntoActiveTab(...)` SUPPRESSES the auto-send block (Migration policy #12 — never fire ⏎ inside the Scratchpad).

- [ ] **Step 9.2 — Verify**

```bash
grep -n "ScratchpadWindowController\|isFocusedAndKey\|insertIntoActiveTab" VoiceInk/Transcription/Engine/TranscriptionPipeline.swift
```

Expected: the new gate at the paste site.

**Risk:** MED — the `firstResponder is NSTextView` predicate inside `isFocusedAndKey` (Task 4.2) is the gate. If the `ScratchpadTextView`'s underlying responder is wrapped (e.g., NSText layer manager), the gate misses. Confirm at Task 12.2 smoke time by dictating into the Scratchpad with the editor focused and observing the transcript inserted at cursor (NOT pasted to the system clipboard).

**Verification:** type-check passes. Manual: open Scratchpad, click into a tab, start the recorder via the existing hotkey, dictate "hello world" → transcript inserts at the cursor position in the Scratchpad tab. The auto-send (if a PowerMode is active with `autoSendKey = .enter`) is SUPPRESSED.

---

### Task 10 — Settings shortcut row

**Files:**
- Modify: existing hotkey settings file (confirmed at Task 0.8)

- [ ] **Step 10.1 — Add the recorder row**

In the file that hosts the existing `KeyboardShortcuts.Recorder("Open History Window", name: .openHistoryWindow)` row (likely `VoiceInk/Views/Settings/HotkeySettingsView.swift` or similar — confirm at Task 0.8), add a sibling row:

```swift
KeyboardShortcuts.Recorder("Toggle Scratchpad", name: .scratchpadToggle)
```

Match the surrounding row's chrome (likely a `LabeledContent` or `Form { Section { … } }` cell).

- [ ] **Step 10.2 — Verify**

```bash
grep -rn "Toggle Scratchpad\|scratchpadToggle" VoiceInk/Views --include="*.swift"
```

Expected: one match (the new recorder row).

**Risk:** LOW — additive UI row.

**Verification:** type-check passes. Manual: Settings → Hotkeys → see "Toggle Scratchpad" row with `⌥+S` recorded; rebind to anything; press the new binding; window toggles.

---

### Task 11 — Static checks (coder-runnable, no build)

**Files:** none (read-only verification).

- [ ] **Step 11.1 — All touched files compile in isolation via SourceKit**

The coder's environment runs SourceKit live. Verify:
- No undefined-symbol errors after each task.
- `ScratchpadDocument.swift` / `ScratchpadVersion.swift` import `Foundation` + `SwiftData`.
- `ScratchpadStore.swift` imports `Foundation`, `SwiftData`, `SwiftUI`, `os`.
- `ScratchpadWindowController.swift` imports `SwiftUI`, `SwiftData`, `AppKit`.
- `ScratchpadView.swift` imports `SwiftUI`, `SwiftData`.
- `ScratchpadTabEditor.swift` imports `SwiftUI`, `AppKit`.
- `ScratchpadVersionHistorySheet.swift` imports `SwiftUI`.
- No circular imports introduced.

- [ ] **Step 11.2 — No orphan references to old constants**

```bash
grep -rn "ScratchpadDocument\|ScratchpadVersion\|ScratchpadStore\|ScratchpadWindowController\|ScratchpadModelContainerProvider" VoiceInk --include="*.swift" | wc -l
```

Expected: ≥20 matches across the new files + the modified `VoiceInk.swift` / `CursorPaster.swift` / `TranscriptionPipeline.swift` / `HotkeyManager.swift` / `MiniRecorderShortcutManager.swift` / settings file.

```bash
grep -rn "scratchpadToggle\|.scratchpadToggle" VoiceInk --include="*.swift"
```

Expected: 4-5 matches (Name extension, onKeyUp handler, first-run default, settings recorder row, Migration policy #10 confirmations).

- [ ] **Step 11.3 — Confirm `CursorPaster` happy path untouched**

```bash
git diff main -- VoiceInk/CursorPaster.swift
```

Expected: changes ONLY inside the `if mustForceClipboard { … }` block at the previous lines 41-50. Lines 11-39 + 52-218 UNCHANGED. Constraint per master plan W12.E ("MUST NOT change `CursorPaster.paste()` happy-path behavior").

- [ ] **Step 11.4 — Confirm SwiftData schema additions are present in three places**

```bash
grep -n "ScratchpadDocument\.self\|ScratchpadVersion\.self" VoiceInk/VoiceInk.swift
```

Expected: 6 matches (top-level Schema + persistent `transcriptSchema` + in-memory `transcriptSchema`, each with both entities).

- [ ] **Step 11.5 — Confirm dictation-into-place gate is the FIRST decision**

```bash
sed -n '191,225p' VoiceInk/Transcription/Engine/TranscriptionPipeline.swift
```

Expected: the `if ScratchpadWindowController.shared.isFocusedAndKey` branch occurs BEFORE the `CursorPaster.pasteAtCursor(...)` call. Migration policy #13 mutual-exclusivity preserved.

---

### Task 12 — Integration build + post-merge verification

**Files:** none (verification + report).

- [ ] **Step 12.1 — Single integration build**

```bash
make local
```

Expected: clean build. Common failure modes:
- `ScratchpadModelContainerProvider` not visible at `CursorPaster` call site → add `import` (it's in `VoiceInk/Services/`; same module — should not need import). If the project uses internal modules, may need `@_exported`.
- `ScratchpadWindow` `canBecomeKey` override warning → expected; SourceKit may complain if not annotated. Add `// swiftlint:disable:next override_in_extension` only if linter complains.
- `NSTextView.scrollableTextView()` deprecation in macOS 15+ → use `NSScrollView()` + `NSTextView()` manually if SourceKit warns. Acceptable v1 fallback; comment with `// W12.E` and proceed.
- SwiftData migration error on first launch with existing on-disk store → this should NOT happen for net-new entities; if it does, file an immediate issue and add a manual `MigrationPlan`.

Per CLAUDE.md cadence, this is the only build run during the packet.

- [ ] **Step 12.2 — Coder smoke pass (manual)**

Open the freshly-built app. Smoke checklist:

1. **Window summon (T7).** Press `⌥+S`. Scratchpad window slides in (no animation expected; just orders front). Window has glass backdrop + transparent titlebar matching the main app.
2. **Default tab (Migration policy #3).** A tab labeled "Untitled" is present.
3. **Multi-tab + chord routing (T5).** Press `⌘T` → second tab "Untitled" appears, becomes active. Type "Hello" in tab 2. Tab title updates to "Hello". Press `⌘1` → switch to tab 1. Press `⌘2` → switch to tab 2. Press `⌘W` → tab 2 closes, tab 1 active.
4. **Tab cap (Migration policy #2).** Open 9 more tabs (`⌘T` × 9). The 10th `+` button becomes disabled. Press `⌘T` → notification "Tab limit reached (10)" appears.
5. **Autosave (T3, T6).** Type continuously in a tab for 5s; pause. After 800ms, footer reads "Saved". Quit + relaunch the app, `⌥+S` → all tabs and content present.
6. **Version snapshot (T3 §3.4-3.5).** Type continuously for 35s. Open History sheet. See at least 1 version captured. Tap Restore on an earlier version → current state captured first; content reverts.
7. **Version FIFO eviction (T3 §3.5).** (Synthetic test — coder may skip if time is short.) Manually call `store.captureVersion(doc, force: true)` 60 times in a debugger; confirm `doc.versions.count == 50` after each batch ≥50.
8. **Paste-fallback (T8).** Click into a sandboxed UI with no text input (e.g., the macOS lock screen — hard to test; alternative: defocus all apps then dictate). When `CursorPaster` reports "no focused text field", a NEW tab appears in the Scratchpad with the dictated content. Notification "Paste rescued to Scratchpad — open with ⌥+S" appears.
9. **Dictation-into-place (T9).** Open Scratchpad, click into a tab. Start the recorder hotkey. Dictate "hello world". The transcript inserts at the cursor position (NOT routed through `CursorPaster`). If a PowerMode with `autoSendKey = .enter` is active, the ⏎ is SUPPRESSED.
10. **Toggle semantics (Migration policy #9).** Press `⌥+S` while window is focused → window hides. Press `⌥+S` while another app is focused → window comes forward (doesn't toggle off).
11. **Hotkey rebind (T10).** Settings → Hotkeys → "Toggle Scratchpad" row. Rebind to `⌃+⇧+S`. Press the new binding → window toggles. Press old `⌥+S` → no longer toggles.
12. **No happy-path regression (T8).** Dictate into a known-good text field (e.g., TextEdit). Confirm `CursorPaster.pasteAtCursor` fires — transcript pastes normally. Auto-send (if configured) fires.

- [ ] **Step 12.3 — User-side post-merge verification protocol**

After the code commit lands, the user runs the qualitative verification:

1. Press `⌥+S` → window appears with one Untitled tab. Type a paragraph. Quit + relaunch + `⌥+S` → tab + content persists.
2. Open 5 tabs, type unique content in each, quit + relaunch → all 5 tabs return with their content. Tab order preserved.
3. Type into one tab continuously for ~2 minutes. Open History sheet → at least 4 version snapshots present. Tap Restore on the oldest → content reverts; current state was captured first (verify by re-opening History and finding a fresh version with the post-Restore-reverted-from content).
4. Restore that fresh version → confirms restore is reversible.
5. Open 10 tabs (the cap). Press `⌘T` → notification "Tab limit reached (10)" appears.
6. Configure a PowerMode with `autoSendKey = .enter`. Activate it. Dictate into a regular app → ⏎ fires after paste. Open Scratchpad, click into a tab, dictate → transcript inserts at cursor; ⏎ does NOT fire (Migration policy #12).
7. Defocus all apps (`⌘⌥H` to hide all + a few `⌘H`s). Dictate. Notification "Copied to clipboard (no text field focused)" + "Paste rescued to Scratchpad — open with ⌥+S" appear. Press `⌥+S` → new tab with the dictated content.
8. Settings → Hotkeys → rebind Scratchpad to a new shortcut. Confirm the new shortcut works and the old one doesn't.
9. Open the System Console; filter for `category:ScratchpadStore`. Type for 35s. Observe `scratchpad: captured version for <uuid>` log. Then type 50 more bursts of 35s each (or simulate via test) → confirm log shows count never exceeds 50.

- [ ] **Step 12.4 — Coder report to lead**

Send the lead:
- Confirmation of all 10 tasks completed (or which deferred per §Risks).
- Build status.
- Smoke-dictation Console log (window summon + autosave + version capture + paste-fallback + dictation-into-place).
- Screenshots of Scratchpad window with multiple tabs, History sheet, Settings → Hotkeys row.
- Any architectural surprises encountered (especially around `NSTextView` first-responder detection, SwiftData lightweight migration on first launch, or the `KeyShortcutCatcher` event-monitor lifecycle).

The lead handles the two commits + push + final handoff doc.

---

## Test plan

Per master plan §0 Q10 (test-infra deferred): no `xcodebuild test` runs. Validation is build-only via `make local` (Task 12.1) plus smoke + manual exercises (Task 12.2-12.3).

**What `xcodebuild build` runs:**
- Single `make local` invocation at Task 12.1. ~3 min cold; warm rebuilds are seconds.

**What the user does for smoke validation:**
- Coder smoke (Task 12.2): the 12-point checklist above.
- User verification (Task 12.3): the 9-step qualitative protocol.

If any expected behavior doesn't materialize, the failing task is the candidate for a focused follow-up packet — see §Rollback plan.

---

## Rollback plan

**Single-commit packet → `git revert <code commit sha>` restores the entire pre-W12.E behavior.** Plan doc commit stays (not reverted) so the historical record is preserved.

**Why squashed-not-split:**
- T1 (schema add) + T3 (store) + T4-6 (window/view/editor) form an interlocked surface — splitting per-task creates revert dependencies (e.g., reverting T1 alone leaves T3 with broken `@Model` references).
- T8 (paste-fallback) and T9 (dictation-into-place) reference `ScratchpadWindowController` which only exists if T4 lands. Per-task revert would break.
- T2 (Name extension) + T7 (handler) trivially co-evolve.

**Per-feature surgical revert** (if a single feature turns out worse):
- **Hotkey collision:** remove the first-run default at T7.2; user rebinds via Settings. Behavior: window only opens if user binds something. Restores no-Scratchpad flow.
- **Paste-fallback regression:** comment out the rescue dispatch in T8 (`if let container = ScratchpadModelContainerProvider…` block). The notification-only path remains; user loses the rescue but no broken state.
- **Dictation-into-place misbehavior:** force `ScratchpadWindowController.isFocusedAndKey` to `return false` always. Recorder-into-Scratchpad falls back to `CursorPaster.pasteAtCursor(...)` — works, just doesn't position cursor.
- **Version-history sheet crashes:** disable the History button in T6.1's footer. The data is still captured; the user just can't browse versions. Snapshot rows accumulate harmlessly bounded by FIFO.
- **Tab-cap UX regression:** raise the cap (e.g., `static let maxTabs = 50`). Trivial follow-up patch.

**Detection signals** (which production data tells us a revert is needed):
- App crash on launch after upgrade → SwiftData migration failed despite the entities being net-new. Investigate the migration logs; possibly a corrupted on-disk store from prior failed migration. Revert and add an explicit `MigrationPlan` in a follow-up.
- `⌥+S` doesn't open the window → `KeyboardShortcuts` library didn't pick up the new Name. Re-check first-run default registration.
- Dictation-into-place silently routes to `CursorPaster` even when the Scratchpad is focused → `firstResponder is NSTextView` predicate misses the SwiftUI-wrapped responder. Inspect the responder chain at smoke time; possible fix: switch to `NSView`-bottom-up search instead of single-class check.
- Paste-fallback rescues nothing → `ScratchpadModelContainerProvider.shared.modelContainer` is nil at the call site (race with `VoiceInkApp.init`). Fix: assert non-nil at app launch + fail loudly in DEBUG.

**Blast radius of a full revert:** zero data loss for non-Scratchpad workflows. Scratchpad documents + versions persist as orphaned SwiftData rows after revert (no read sites left); they reappear if the user re-installs a W12.E build. Manual cleanup is `rm ~/Library/Application Support/com.prakashjoshipax.VoiceInk/default.store*` — destructive (loses Transcription history too), so DON'T recommend unless absolutely necessary.

---

## Risks / unknowns

1. **SwiftData lightweight migration on first launch with existing on-disk store.** Adding two `@Model` types to an existing store SHOULD trigger a no-op lightweight migration. If the user's on-disk store has any prior corruption or schema drift, the migration may fail. **Mitigation:** Task 12.1's build doesn't catch runtime migration errors — Task 12.2 smoke step 1 (window summon) IS the migration test. If the store fails to open, the app falls back to in-memory storage (existing `createInMemoryContainer` path), surfacing the alert "Storage Warning". Revert and add explicit `MigrationPlan` in a follow-up.

2. **First-responder detection for dictation-into-place.** `firstResponder is NSTextView` is brittle if SwiftUI's `NSViewRepresentable` wraps the text view in another view (`NSScrollView` → `NSClipView` → `NSTextView`). The smoke at Task 12.2 step 9 is the validation. **Mitigation:** if the gate misses, switch to a responder-chain walk (recursively look for `NSTextView` ancestor). Out of scope to pre-implement; flagged for smoke-time discovery.

3. **`KeyShortcutCatcher` `NSEvent.addLocalMonitorForEvents` lifecycle.** The monitor is registered on view appear and removed on dismantle. SwiftUI may recreate the wrapping `NSView` more often than expected, causing monitor churn. **Mitigation:** the dismantle handler removes the monitor; `addLocalMonitorForEvents` is idempotent enough that even a leak window is bounded by view lifecycle. Track via the System Console — repeated `Local event monitor registered` log lines would indicate churn. Acceptable for v1; if memory pressure is observed, refactor to a single window-level monitor in `ScratchpadWindowController`.

4. **`⌘W` chord may close other windows.** macOS convention: `⌘W` closes the key window. Our `KeyShortcutCatcher` consumes the event (returns nil from the local monitor) — but if the Scratchpad window has child windows or sheets open, the event might also reach the parent's window-close handler. **Mitigation:** the `local monitor` only fires when the Scratchpad is key; if the History sheet is presented, the sheet receives the chord first (its own keyboard-shortcut bindings — `keyboardShortcut(.defaultAction)` on Done captures ⏎ but not ⌘W). Smoke test step 3 catches mis-routing.

5. **Auto-save Task race vs window close.** A user closes the window 100ms after typing; the 800ms autosave Task is still pending. `windowWillClose` calls `flushAll()` which awaits all in-flight tasks. If the user quits the app (not just closes the window), the Task may be killed mid-execution and the last 100ms of typing lost. **Mitigation:** acceptable for v1 — same drop window as macOS standard text editors. Follow-up: register an `NSApplication.willTerminateNotification` observer that calls `flushAll()` before exit. Out of scope here.

6. **Tab-strip overflow with 10 tabs.** The horizontal scroll at Task 5.1's `tabStrip` works but the user can't see all 10 cells without scrolling on a small window. **Mitigation:** acceptable for v1. Follow-up: tab cell becomes more compact when N≥6 (icon-only + tooltip). Out of scope.

7. **Cap-bypass for paste-fallback may surprise.** Migration policy #11 says paste-fallback ALWAYS creates a tab even at 11/10. If the user has 10 tabs and gets a rescue, they end up with 11 — unusable from the `+` button (still disabled at >=10) but visible in the strip. **Mitigation:** the notification flags it. The user closes a tab to get back under cap. Acceptable v1 trade-off; data preservation > strict cap.

8. **Plain-text paste strips formatting.** Migration policy #15. If the user pastes Markdown or rich text into the Scratchpad expecting it to render, it won't. **Mitigation:** master plan explicitly out-of-scope. Document in a footer hint or release notes if user complains.

9. **No search across tabs.** Per master plan §3 W12.E out-of-scope. User can `⌘F` within a tab (NSTextView built-in), but no cross-tab search. **Mitigation:** acceptable v1 limit. Follow-up packet if user requests.

10. **Title auto-recompute clobbers user-rename.** Migration policy #4. If the user right-clicks a tab → "Rename" (which we don't ship in v1 but might add) and types a custom title, the next typing tick recomputes it from `content`. **Mitigation:** v1 doesn't ship rename; the auto-derive is the only title path. Follow-up: store `userRenamedTitle: Bool` sentinel + branch the auto-derive on it.

11. **`KeyboardShortcuts.Recorder` UI on macOS may not honor non-character chords cleanly.** `⌥+S` is a simple chord; should work fine. But user-rebinds to a multi-modifier chord (e.g., `⌃⇧⌥+S`) may surface SwiftUI rendering quirks. **Mitigation:** the `KeyboardShortcuts` library handles this; acceptable v1 risk.

12. **`MiniRecorderShortcutManager` is the wrong home for the first-run default.** Task 0.7 confirms; if the lead has a dedicated first-run-defaults file, move T7.2's registration there. **Mitigation:** the audit step catches this; coder picks the right home.

13. **The "shared" `ScratchpadModelContainerProvider` is global state.** This is the shim that lets `CursorPaster` (a `class` of `static func`s) reach the SwiftData container. Global singletons are a code-smell. **Mitigation:** rewriting `CursorPaster` to be instance-based is a much bigger refactor; the shim is the lowest-risk path. Follow-up: thread the container through `CursorPaster.pasteAtCursor(_:container:)` in a focused refactor packet.

14. **Test infra deferred per Q10.** `xcodebuild test` env-blocked. No automated regression catch for the SwiftData migration boundary, the autosave-debounce coalescing, or the FIFO eviction. **Mitigation:** smoke + manual upgrade dance (Task 12.3). If a regression slips, blast radius is per-document (each Scratchpad operation is independent).

15. **`adaptiveGlassBackground(intensity: .panel)` may not paint correctly with non-zero `.fullSizeContentView` flag.** The Scratchpad window mirrors `WindowManager.configureWindow` flags, but the wrapping `ScratchpadView` calls `.adaptiveGlassBackground(...)` from the SwiftUI side. **Mitigation:** if the glass doesn't render, fall back to `.background(VisualEffectBlur(material: .hudWindow))` or similar. Smoke step 1 catches.

16. **Version snapshots can grow `default.store` quickly during heavy use.** 50 versions × ~10kB content × 10 documents = 5MB. Trivial. But if a user pastes a large block into a tab (50kB+), 50 versions × 50kB × 10 documents = 25MB. **Mitigation:** acceptable v1. Follow-up: clip version content size at 100kB or skip version capture for large pastes.

---

## Out of scope (explicit) for follow-ups

- **Cross-device sync (CloudKit).** Per Migration policy #1 + master plan §3 W12.E. Future packet would move the schema to a CloudKit-eligible store + handle conflict resolution.
- **Markdown rendering / rich text.** Per Migration policy #15.
- **Search across all tabs.** Per Risk #9. Follow-up packet if user requests.
- **Export to file.** Per master plan §3 W12.E out-of-scope. Easy follow-up: `⌘E` exports active tab to `.txt`.
- **Tab rename UI.** Per Migration policy #4 + Risk #10. Follow-up: right-click context menu with "Rename" + a `userRenamedTitle: Bool` sentinel.
- **Auto-numbered "Untitled 1", "Untitled 2".** Per Migration policy #16. Future polish if reviewer requests.
- **Tab-strip animation on summon.** Per Migration policy #14. Polish, not function.
- **Drag-to-reorder tabs.** Out of scope for v1.
- **Per-tab pinned state.** Out of scope.
- **Snapshot diffing UI in version history.** Currently the History sheet shows preview text only; reuse of `WordDiffEngine.tokenLevelDiff` is flagged in §File structure as optional. Lead picks at sign-off; coder ships with-or-without per the lead's call.
- **Window animation on hotkey-summon (slide-in / cross-fade).** Per Migration policy #14. Follow-up if user asks.
- **`⌃+S` / other-default hotkey.** Default is `⌥+S` per master plan; user rebinds via Settings. Follow-up: per-modifier UX choice if `⌥+S` collides with the user's keymap.
- **Auto-save flush on app quit.** Per Risk #5. Follow-up: register `NSApplication.willTerminateNotification`.
- **Session-blob snapshot of Scratchpad state.** PowerMode has session snapshots; Scratchpad doesn't. Out of scope.
- **Scratchpad as a recorder-target picker source.** A future feature could let the user explicitly say "dictate into Scratchpad tab 3" without focusing the window. Out of scope; current dictation-into-place is implicit-on-focus.
- **Per-tab autosave-debounce tuning.** v1 uses 800ms uniform. Follow-up if a power user asks for instant-save / longer-debounce.
- **Test infrastructure unblock.** Per master plan §0 Q10. Separate session.
- **Context-sensitive 11th-tab handling on cap-bypass.** Currently the strip simply shows 11 tabs; the user closes one to recover. Future polish: visually mark the cap-bypass tab.
- **Threading the SwiftData container into `CursorPaster.pasteAtCursor(...)` directly.** Per Risk #13. Refactor packet.
- **Session-restore on launch into the most recent Scratchpad tab.** Currently the active-tab is reset to first on launch. Follow-up: `@AppStorage("scratchpadLastActiveTabId")`.

---

## Open questions for lead

1. **Default hotkey `⌥+S` vs alternatives.** Master plan says `⌥+S` (Migration policy #10). **Confirm:** any system collision the user wants to avoid? `⌥+S` is the default Spotlight-Open-with-System-Sound shortcut on some legacy macOS builds — should be free on macOS 26.0. Recommend ship as `⌥+S`; user rebinds if collision.

2. **Log marker emoji `🗒️` vs plain prefix `scratchpad:`.** Migration policy #18 + CLAUDE.md says no new emoji in code. `🦾` is the documented exception (W6/W11 instrumentation). **Confirm:** ship the new logs as plain `scratchpad:` prefix, or grandfather an `🗒️` like `🦾`? Recommend plain prefix — keeps the no-emoji rule clean. Coder ships plain unless lead overrides.

3. **Tab cap = 10 vs alternative.** Migration policy #2. **Confirm:** 10 is intuitive but arbitrary; user might want 5 (forces archive discipline) or 20 (lots of scratch surfaces). Recommend ship as 10; tune in follow-up.

4. **Version snapshot interval = 30s vs alternative.** Migration policy #6. **Confirm:** 30s catches editing arcs but not rapid undo-after-30s. 10s would be more granular but bloat versions. Recommend ship as 30s.

5. **Version cap = 50 vs alternative.** Migration policy #7. Master plan says 50. **Confirm:** locked at 50.

6. **Paste-fallback notification text.** Migration policy #11 ships `"Paste rescued to Scratchpad — open with ⌥+S"`. **Confirm:** OK to mention the hotkey in the notification text? Some users will rebind the hotkey, in which case the notification is misleading. Alternative: `"Paste rescued to Scratchpad"` only. Recommend ship the simpler form; coder does the simpler form unless lead overrides.

7. **Dictation-into-place on PowerMode override.** Currently auto-send is SUPPRESSED when routing into the Scratchpad (Migration policy #12). **Confirm:** a user with `autoSendKey = .enter` who deliberately dictates into the Scratchpad would expect ⏎ to be suppressed. If they instead expected the ⏎ to land in the Scratchpad as a newline, that's a different design — recommend leave as suppress (simpler v1; the user can type ⏎ themselves).

8. **Version-history sheet — diff vs preview.** Task 6.3 currently shows 2-line preview text. Reusing `WordDiffEngine.tokenLevelDiff` from W12.A would let users see exactly what changed between versions. **Confirm:** ship preview-only for v1, or include diff render? Recommend preview-only for v1 (simpler; the Restore action is the primary flow). Diff render is a follow-up polish.

9. **Window initial size / position.** Task 4.2 ships 820×560 (initial), 720×480 (min), centered on first launch via `setFrameAutosaveName`. **Confirm:** acceptable defaults? Larger would suit longer-form notes; smaller would suit quick-capture. Recommend ship the proposed defaults.

10. **Title-auto-derive on user-rename collision.** Migration policy #4 says title auto-recomputes on every save tick. We don't ship rename in v1. **Confirm:** OK to defer the rename UI + the `userRenamedTitle` sentinel to a follow-up? Recommend yes — auto-derive is sufficient for v1.

11. **Pre-merge gate — none. Confirm OK to skip?** Unlike W12.A's qualitative reference set, W12.E has no perf or behavioral baseline to capture pre-merge. Coder smoke + user verification (Task 12.2-12.3) are the validation. Recommend skip; lead may decide to demo-test before merge.

12. **Worktree path.** Plan ships at `.worktrees/w12e/` ABSOLUTE per CLAUDE.md teammate-context lifecycle. **Confirm:** accept.

---

## Post-merge verification protocol (USER-SIDE)

1. **Window summon, default tab, persistence.** Press `⌥+S` → Scratchpad opens with one Untitled tab. Type "hello world" → tab title becomes "hello world", footer reads "Saved". Quit + relaunch → `⌥+S` → tab + content present.

2. **Multi-tab + chord routing.** `⌘T` → second tab. Type uniquely in each. `⌘1` / `⌘2` switches. `⌘W` closes active. Tab order preserved across launch.

3. **Tab cap.** Open 10 tabs (`⌘T` × 9 from the default). 11th `⌘T` triggers notification "Tab limit reached (10)". `+` button is disabled.

4. **Autosave + version cadence.** Type continuously for ~35s. Open History → see 1 version. Type for another 35s → see 2. Stop at 5 versions.

5. **Restore is reversible.** Tap Restore on version 1 (the oldest captured). Content reverts. Open History again → see versions 1-5 PLUS a new version 6 (the captured-current state from before restore). Tap Restore on version 6 → content goes back to where it was before. Confirms reversibility.

6. **FIFO eviction.** This is hard to verify manually; trust the implementation + Task 12.2.7. Optional: dictate or paste 60+ × 35s editing arcs into one tab; confirm `document.versions.count == 50` (via Console log `scratchpad: captured version for <uuid> — 50 total` plateau).

7. **Paste-fallback.** Defocus all apps + dictate. Notification "Paste rescued to Scratchpad" (or whatever the lead picks for Q6) appears. `⌥+S` → new tab with the dictated content visible.

8. **Dictation-into-place.** Open Scratchpad, click into a tab, position cursor mid-paragraph. Recorder hotkey → dictate "inserted at cursor". The transcript inserts at the cursor (replacing any selected range; otherwise inserting at caret).

9. **Auto-send suppression on Scratchpad.** Configure a PowerMode with `autoSendKey = .enter`. Activate it. Dictate into Scratchpad → transcript inserts; ⏎ does NOT fire. Dictate into a regular text field → transcript pastes; ⏎ fires.

10. **Toggle semantics.** Press `⌥+S` while Scratchpad is focused → window hides. Press `⌥+S` while another app is focused → Scratchpad comes forward (doesn't toggle off-then-on).

11. **Hotkey rebind.** Settings → Hotkeys → "Toggle Scratchpad" row. Rebind to `⌃⇧+S`. Old `⌥+S` no longer toggles. New `⌃⇧+S` does.

12. **Quit + relaunch persistence.** All Scratchpad tabs + content + version history present after quit + relaunch. Active-tab on relaunch is the first tab (per current implementation; follow-up: most-recent-active-tab restoration).

If any step fails, log the failure mode + which task is implicated, and SendMessage the lead. Tasks 1-10 are independently revertible per §Rollback plan.

---

## Notes for the lead

- **Largest packet of W12.** ~9 new files, 5 modified files, ~1100 LOC of new code. Equivalent to W12.A's diff in size + an additional new-window/SwiftUI surface. Plan to budget ~1.5× a normal coder packet for execution; ~1× for review.
- **`Transcription` schema unchanged.** The two new `@Model` types are siblings, not extensions. No migration to Transcription rows.
- **CursorPaster happy path is sacrosanct.** Per master plan and Migration policy. Reviewer must diff-check this explicitly.
- **`firstResponder is NSTextView` is the load-bearing predicate** for dictation-into-place. If any smoke-time variant of the SwiftUI editor wraps the responder differently, the gate misses. Worth a careful review at smoke time.
- **No new tests.** Build is the gate. Per Q10 deferral.
- **One integration build.** Per `feedback_skip_per_packet_builds.md`. Coder does NOT run `make local` during execution.
- **Two commits, not one.** Plan doc lands first (`docs(plans): W12E — scratchpad plan`). Code lands after lead sign-off (`feat(scratchpad): W12E — summoned window + multi-tab + 50-version history + paste fallback`).
- **Forward-compat with future Scratchpad work.** The `ScratchpadStore` API is the surface; future packets (search, export, cross-device sync, rich text) extend it without rewriting. The `@Model` types are simple enough to evolve via SwiftData lightweight migrations (add fields, default values).
- **Session-blob is not modified.** PowerModeSessionManager doesn't touch Scratchpad state — Scratchpad is its own surface, not a PowerMode-overridable behavior.
- **Open questions:** 12 above. Items #1, #6, #7 are user-facing UX choices; #2 is a code-style nit; #11 is a process question; the rest are mostly recommend-as-proposed.
