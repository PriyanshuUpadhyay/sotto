import SwiftUI
import AppKit

// MARK: - CommandPaletteSheet (W14D)
//
// ⌘K-activated search palette over the Settings window. Two-layer corpus:
// the 11 sidebar entries (`ViewType`) and the ~23 SettingsCard-shaped
// destinations on those panes. Result activation routes by setting
// `ContentView.selectedView` to the entry's `parent` ViewType. Scroll-to-
// card is deferred (would need ScrollViewReader retrofits across every
// destination plus an anchor convention SettingsCard's API doesn't expose).
//
// All helper types in this file are `private` per the W14E micro-rule —
// promote when (and only when) a third caller appears.

// MARK: Entry model

/// A single searchable destination inside Settings.
private struct CommandPaletteEntry: Identifiable {
    let id: String
    let icon: String
    let title: String
    let aliases: [String]
    /// Where ↵ lands. Sidebar-row entries have `breadcrumb == "Sidebar"`.
    let breadcrumb: String
    let parent: ViewType
}

// MARK: Static index
//
// Hand-curated corpus. Ordering of card entries within each parent is
// loose — search ranking handles surfacing. The order *within the array*
// breaks rank ties (stable sort), so put high-priority items earlier when
// natural.
//
// When you add a new SettingsCard to a destination, add a row here. Keep
// alias counts loose (2–5) — add what feels like a likely user query, drop
// what doesn't earn its keep.

private let commandPaletteEntries: [CommandPaletteEntry] = [
    // ─── Sidebar entries (11) ───
    .init(id: "sb.metrics",         icon: "gauge.medium",                title: "Dashboard",        aliases: ["home", "stats", "summary", "metrics"], breadcrumb: "Sidebar", parent: .metrics),
    .init(id: "sb.history",         icon: "doc.text.fill",               title: "History",          aliases: ["logs", "past", "transcripts"],         breadcrumb: "Sidebar", parent: .history),
    .init(id: "sb.models",          icon: "brain.head.profile",          title: "Models",           aliases: ["ai", "whisper", "llm", "enhance", "providers"], breadcrumb: "Sidebar", parent: .models),
    .init(id: "sb.handsFree",       icon: "ear.fill",                    title: "Hands-free",       aliases: ["voice", "wake", "trigger", "continuous"], breadcrumb: "Sidebar", parent: .handsFree),
    .init(id: "sb.permissions",     icon: "shield.fill",                 title: "Permissions",      aliases: ["mic", "accessibility", "screen", "privacy"], breadcrumb: "Sidebar", parent: .permissions),
    .init(id: "sb.audioInput",      icon: "mic.fill",                    title: "Audio Input",      aliases: ["mic", "device", "microphone", "source"], breadcrumb: "Sidebar", parent: .audioInput),
    .init(id: "sb.dictionary",      icon: "character.book.closed.fill",  title: "Dictionary",       aliases: ["vocabulary", "replace", "words", "custom"], breadcrumb: "Sidebar", parent: .dictionary),
    .init(id: "sb.snippets",        icon: "text.cursor",                 title: "Snippets",         aliases: ["abbreviation", "expand", "shortcut"], breadcrumb: "Sidebar", parent: .snippets),
    .init(id: "sb.settings",        icon: "gearshape.fill",              title: "Settings",         aliases: ["preferences", "options", "general"], breadcrumb: "Sidebar", parent: .settings),
    .init(id: "sb.transcribeAudio", icon: "waveform.circle.fill",        title: "Transcribe Audio", aliases: ["file", "batch", "import", "upload"], breadcrumb: "Sidebar", parent: .transcribeAudio),
    .init(id: "sb.powerMode",       icon: "sparkles.square.fill.on.square", title: "Power Mode",    aliases: ["per-app", "context", "profile"],     breadcrumb: "Sidebar", parent: .powerMode),

    // ─── Dashboard cards (1) ───
    .init(id: "card.metrics.summary",     icon: "list.bullet.rectangle",       title: "What's configured",      aliases: ["summary", "overview", "status"],            breadcrumb: "Dashboard › Configuration",                  parent: .metrics),

    // ─── Models cards (6) ───
    .init(id: "card.models.default",      icon: "brain.head.profile",          title: "Default Model",          aliases: ["active", "current", "transcription"],       breadcrumb: "Models › Transcription",                     parent: .models),
    .init(id: "card.models.language",     icon: "globe",                       title: "Language Selection",     aliases: ["language", "locale", "lang"],               breadcrumb: "Models › Transcription",                     parent: .models),
    .init(id: "card.models.gallery",      icon: "square.grid.2x2",             title: "Available Models",       aliases: ["gallery", "download", "recommended"],       breadcrumb: "Models › Transcription",                     parent: .models),
    .init(id: "card.models.enhancement",  icon: "wand.and.stars",              title: "Enhancement",            aliases: ["llm", "enhance", "polish"],                 breadcrumb: "Models › Enhancement",                       parent: .models),
    .init(id: "card.models.aiProvider",   icon: "key.fill",                    title: "AI Provider Integration", aliases: ["api", "key", "provider", "openai", "anthropic"], breadcrumb: "Models › Enhancement",                  parent: .models),
    .init(id: "card.models.prompts",      icon: "text.bubble",                 title: "Enhancement Prompts",    aliases: ["prompt", "style", "persona"],               breadcrumb: "Models › Enhancement",                       parent: .models),

    // ─── Hands-free cards (5) ───
    .init(id: "card.handsFree.activation", icon: "ear.fill",                   title: "Hands-free Mode",        aliases: ["hotkey", "toggle", "activate"],             breadcrumb: "Hands-free › Activation",                    parent: .handsFree),
    .init(id: "card.handsFree.threshold",  icon: "waveform.badge.mic",         title: "Voice Activity Threshold", aliases: ["vad", "threshold", "sensitivity"],        breadcrumb: "Hands-free › Threshold",                     parent: .handsFree),
    .init(id: "card.handsFree.silence",    icon: "timer",                      title: "Silence Duration",       aliases: ["pause", "gap", "timeout"],                  breadcrumb: "Hands-free › Silence",                       parent: .handsFree),
    .init(id: "card.handsFree.triggers",   icon: "text.bubble",                title: "Voice Triggers",         aliases: ["trigger", "phrase", "enter"],               breadcrumb: "Hands-free › Triggers",                      parent: .handsFree),
    .init(id: "card.handsFree.session",    icon: "clock.fill",                 title: "Session Cap",            aliases: ["duration", "limit", "auto-stop"],           breadcrumb: "Hands-free › Session",                       parent: .handsFree),

    // ─── Settings cards (10) ───
    .init(id: "card.settings.shortcuts",            icon: "command",                  title: "Shortcuts",            aliases: ["hotkey", "recorder", "push-to-talk"],      breadcrumb: "Settings › Shortcuts",            parent: .settings),
    .init(id: "card.settings.additionalShortcuts",  icon: "keyboard",                 title: "Additional Shortcuts", aliases: ["paste", "retry", "command", "scratchpad"], breadcrumb: "Settings › Shortcuts",            parent: .settings),
    .init(id: "card.settings.recordingFeedback",    icon: "waveform",                 title: "Recording Feedback",   aliases: ["sound", "mute", "clipboard", "paste"],     breadcrumb: "Settings › Feedback",             parent: .settings),
    .init(id: "card.settings.powerModeToggle",      icon: "bolt.fill",                title: "Power Mode",           aliases: ["per-app", "context", "auto-enable"],       breadcrumb: "Settings › Power Mode",           parent: .settings),
    .init(id: "card.settings.interface",            icon: "rectangle.on.rectangle",   title: "Interface",            aliases: ["recorder style", "notch", "mini", "halo"], breadcrumb: "Settings › Interface",            parent: .settings),
    .init(id: "card.settings.experimental",         icon: "testtube.2",               title: "Experimental",         aliases: ["beta", "opt-in", "pause media"],           breadcrumb: "Settings › Experimental",         parent: .settings),
    .init(id: "card.settings.general",              icon: "gearshape.fill",           title: "General",              aliases: ["dock", "login", "updates", "announcements"], breadcrumb: "Settings › General",            parent: .settings),
    .init(id: "card.settings.privacy",               icon: "lock.fill",                title: "Privacy",              aliases: ["cleanup", "delete", "retention"],          breadcrumb: "Settings › Privacy",              parent: .settings),
    .init(id: "card.settings.backup",                icon: "tray.and.arrow.up",        title: "Backup",               aliases: ["export", "import", "settings file"],       breadcrumb: "Settings › Backup",               parent: .settings),
    .init(id: "card.settings.diagnostics",           icon: "stethoscope",              title: "Diagnostics",          aliases: ["logs", "crash", "export logs"],            breadcrumb: "Settings › Diagnostics",          parent: .settings),
]

/// Empty-query default surface — high-frequency Settings-window jumps,
/// curated explicitly (NOT derived from importance scoring). Skipped:
/// Transcribe Audio (file-drop tool, not a config jump), Power Mode (gated
/// by flag — would noisy-up the empty state when off), Dictionary /
/// Snippets (medium-frequency — bumped below the fold).
private let commandPaletteEmptyDefaults: [String] = [
    "sb.metrics",
    "sb.models",
    "sb.handsFree",
    "sb.permissions",
    "sb.audioInput",
    "sb.settings",
    "sb.history",
    "card.metrics.summary",
]

// MARK: - Match algorithm

private enum CommandPaletteRanker {
    /// Returns `nil` if the entry doesn't match `query`, otherwise a 0–3 rank
    /// (lower = better):
    ///   0 = title prefix
    ///   1 = title substring
    ///   2 = alias substring
    ///   3 = breadcrumb substring
    static func rank(_ entry: CommandPaletteEntry, query: String) -> Int? {
        let title = entry.title.foldedForSearch()
        if title.hasPrefix(query) { return 0 }
        if title.contains(query)  { return 1 }
        if entry.aliases.contains(where: { $0.foldedForSearch().contains(query) }) {
            return 2
        }
        if entry.breadcrumb.foldedForSearch().contains(query) { return 3 }
        return nil
    }

    static func results(for query: String, powerModeFlagOn: Bool) -> [CommandPaletteEntry] {
        let allEntries = commandPaletteEntries.filter { entry in
            entry.parent != .powerMode || powerModeFlagOn
        }

        let trimmed = query.foldedForSearch()
        if trimmed.isEmpty {
            return commandPaletteEmptyDefaults.compactMap { id in
                allEntries.first(where: { $0.id == id })
            }
        }

        let ranked = allEntries.enumerated().compactMap { (idx, entry) -> (rank: Int, idx: Int, entry: CommandPaletteEntry)? in
            guard let r = rank(entry, query: trimmed) else { return nil }
            return (r, idx, entry)
        }
        return ranked
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.idx < rhs.idx
            }
            .map { $0.entry }
    }
}

private extension String {
    /// Lowercased + diacritic-folded for substring matching.
    func foldedForSearch() -> String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

// MARK: - Sheet view

struct CommandPaletteSheet: View {
    let powerModeFlagOn: Bool
    let onSelect: (ViewType) -> Void
    let onDismiss: () -> Void

    @State private var query: String = ""
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool

    private var results: [CommandPaletteEntry] {
        CommandPaletteRanker.results(for: query, powerModeFlagOn: powerModeFlagOn)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            Divider().opacity(0.6)
            resultsList
            Divider().opacity(0.6)
            footerHint
        }
        .frame(width: 520, height: 420)
        .background(
            TacticalGlass(
                shape: Rectangle(),
                phase: .hidden
            )
        )
        .onAppear {
            // Defer focus to next runloop tick — `.focused` set in `body`
            // before the field is on-screen is dropped by SwiftUI on macOS.
            DispatchQueue.main.async { searchFocused = true }
            selectedID = results.first?.id
        }
        .onChange(of: query) { _, _ in
            // Persist selection across edits if the entry survives the
            // filter; else snap to the new top.
            if let sel = selectedID, results.contains(where: { $0.id == sel }) {
                return
            }
            selectedID = results.first?.id
        }
    }

    // MARK: Header (search field)

    private var searchHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)

            TextField("Search settings…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .focused($searchFocused)
                .onSubmit { activateSelection() }
                // W14D — `.onKeyPress` is the macOS 14+ idiom for capturing
                // arrow keys inside a focused TextField. If a future macOS
                // tweak makes arrow capture flaky, fall back to
                // `NSEvent.addLocalMonitorForEvents(.keyDown)` mounted in
                // `.onAppear` and torn down in `.onDisappear`.
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1)
                    return .handled
                }
                .onKeyPress(.escape) {
                    onDismiss()
                    return .handled
                }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (⎋)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: Results list

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            VStack {
                Spacer()
                Text("No matches")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { entry in
                            CommandPaletteRow(
                                entry: entry,
                                isSelected: entry.id == selectedID
                            )
                            .id(entry.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedID = entry.id
                                onSelect(entry.parent)
                            }
                            .onHover { hovering in
                                if hovering { selectedID = entry.id }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedID) { _, newValue in
                    guard let id = newValue else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footerHint: some View {
        HStack(spacing: 12) {
            footerHintItem(keys: "↑↓", label: "navigate")
            footerHintItem(keys: "↵", label: "open")
            footerHintItem(keys: "⎋", label: "close")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func footerHintItem(keys: String, label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
        }
    }

    // MARK: Selection / activation

    private func moveSelection(by delta: Int) {
        let r = results
        guard !r.isEmpty else { return }
        let currentIndex = r.firstIndex(where: { $0.id == selectedID }) ?? -1
        let next = ((currentIndex + delta) % r.count + r.count) % r.count
        selectedID = r[next].id
    }

    private func activateSelection() {
        guard let id = selectedID,
              let entry = results.first(where: { $0.id == id })
        else {
            // No selection? activate the first result if any.
            if let entry = results.first { onSelect(entry.parent) }
            return
        }
        onSelect(entry.parent)
    }
}

// MARK: - Row

private struct CommandPaletteRow: View {
    let entry: CommandPaletteEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isSelected ? Palette.brandAcid : .secondary)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(entry.breadcrumb)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Palette.brandAcid.opacity(0.14) : Color.clear)
                .padding(.horizontal, 6)
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Command Palette") {
    CommandPaletteSheet(
        powerModeFlagOn: true,
        onSelect: { _ in },
        onDismiss: { }
    )
}
#endif
