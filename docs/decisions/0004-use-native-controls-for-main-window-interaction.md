---
status: accepted
date: 2026-09-18
deciders: [PriyanshuUpadhyay]
related: []
informed-by: [Sotto/Views/History/InlineHistoryView.swift, SottoTests/SettingsWindowTests.swift]
---
# 0004. Use native SwiftUI controls for main-window interaction, not hand-built rows

## Context and Problem Statement
History rows did not expand and their checkboxes did not select. Each row was a hand-built card,
and its hover highlight was a filled shape drawn above the row content at 4% opacity. That layer
took every click, so the controls under it never got one. The fault had been there since the first
commit. Other main-window surfaces used the same approach: a hand-built sidebar, an accordion with a
whole-row tap gesture and a debounce flag, card buttons that act as radio groups, and a custom
drag-and-drop reorder.

## Considered Options
- Keep the hand-built rows and fix the hover overlay (one line: stop it taking clicks).
- Move interaction to native controls: `List(selection:)`, `DisclosureGroup`, `Picker`,
  `.contextMenu(forSelectionType:)`, `.onDeleteCommand`, `.onCopyCommand`, `.onMove`, `.inspector`.

## Decision Outcome
Chosen: native controls, because the platform then owns click, ⌘/⇧-click, arrow keys, ⌘A,
Delete, Copy, disclosure and VoiceOver, and a stray layer cannot break them again. Brand visuals
(cards, fonts, colours) stay only where they take no clicks. The recorder HUD, Liquid Glass panels
and the ⌘K palette stay custom.

### Consequences
- Good: selection, expansion, keyboard and accessibility behave like every other Mac app with no
  hand-written key or gesture handling to keep in sync.
- Bad: the native selection highlight replaces the matte sidebar style chosen on 2026-09-02; a
  `List` inside a page-level `ScrollView` (Dictionary) needs an explicit height; the sidebar must
  still not sit in a `NavigationSplitView`, because NSView-backed controls
  (KeyboardShortcuts.Recorder, NSSearchField) re-enter layout and crash inside one; and
  `ImageRenderer` snapshots cannot draw a `List`.
