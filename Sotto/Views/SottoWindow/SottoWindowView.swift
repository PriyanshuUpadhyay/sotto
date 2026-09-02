import SwiftUI

/// Every destination in the window's ONE flat sidebar. There is no second
/// navigation layer: the former Settings rail's pages are rows here, grouped
/// under a non-selectable SETTINGS header (macOS System Settings grammar).
enum SottoWindowTab: CaseIterable, Hashable {
    case history
    case dictionary
    case models
    case general
    case shortcuts
    case advanced

    var title: String {
        switch self {
        case .history:        return "History"
        case .dictionary:     return "Dictionary"
        case .models:         return "Models"
        case .general:        return "General"
        case .shortcuts:      return "Shortcuts"
        case .advanced:       return "Advanced"
        }
    }

    /// SF Symbol per destination — drives the labeled sidebar.
    var systemImage: String {
        switch self {
        case .history:        return "clock"
        case .dictionary:     return "character.book.closed"
        case .models:         return "cpu"
        case .general:        return "gearshape"
        case .shortcuts:      return "command"
        case .advanced:       return "slider.horizontal.3"
        }
    }

    /// Rows that sit under the SETTINGS group header; the rest stack above it.
    var isSettingsGroup: Bool {
        switch self {
        case .history, .dictionary:                  return false
        case .models, .general, .shortcuts, .advanced: return true
        }
    }

    /// The `SettingsTab` routing key this row answers to. Routing, the search
    /// index and the section-jump notifications still speak `SettingsTab`;
    /// nothing renders it as a second navigation layer.
    var settingsTab: SettingsTab? {
        switch self {
        case .history:    return nil
        case .dictionary: return .vocabulary
        case .models:     return .models
        case .general:    return .general
        case .shortcuts:  return .shortcuts
        case .advanced:   return .advanced
        }
    }

    /// The sidebar row a `SettingsTab` routing key targets.
    init(settingsTab: SettingsTab) {
        switch settingsTab {
        case .general:    self = .general
        case .shortcuts:  self = .shortcuts
        case .models:     self = .models
        case .vocabulary: self = .dictionary
        case .advanced:   self = .advanced
        }
    }
}

/// Shell state for the sidebar + content layout. Pure + `@MainActor` so the
/// active-destination logic is unit-testable without rendering.
@MainActor
final class TriptychModel: ObservableObject {
    /// The active sidebar destination.
    @Published var selectedTab: SottoWindowTab = .history

    /// Nonisolated so it can be the default argument of `SottoWindowView.init`
    /// (a synchronous, nonisolated context). Only sets stored defaults.
    nonisolated init() {}
}

struct SottoWindowView: View {
    @ObservedObject private var coordinator = SottoWindowCoordinator.shared
    // Accent changes re-render the whole window subtree, so every
    // `Palette.phosphor` / `Brand.tint` read below resolves the new choice.
    @ObservedObject private var accent = AccentStore.shared
    @StateObject private var model: TriptychModel

    @State private var query = ""
    // Identity of the latest section-jump request — a scheduled repost checks
    // it at fire time so a newer jump supersedes a pending one.
    @State private var sectionJumpRequest = 0

    init(model: TriptychModel = TriptychModel()) {
        _model = StateObject(wrappedValue: model)
    }

    static var renderedTabs: [SottoWindowTab] { SottoWindowTab.allCases }

    static func historyView() -> HistoryDestinationView {
        HistoryDestinationView()
    }

    private static let sidebarWidth: CGFloat = 200

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            content(for: model.selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.canvas)
        .tint(Brand.tint)
        .onAppear {
            consumePendingTab()
            consumeStagedTarget()
        }
        .onChange(of: coordinator.pendingTab) { consumePendingTab() }
        .onReceive(NotificationCenter.default.publisher(for: .selectSettingsTab)) { notification in
            coordinator.pendingSettingsTarget = nil
            guard let tab = Self.resolvedTab(from: notification) else { return }
            select(SottoWindowTab(settingsTab: tab))
            query = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectSettingsSection)) { notification in
            // Every section request supersedes any in-flight repost — bumped
            // BEFORE the same-row early return below, which otherwise leaves a
            // stale scheduled repost passing its guards and overriding this one.
            invalidateSectionJumps()
            coordinator.pendingSettingsTarget = nil
            guard let tab = notification.userInfo?["tab"] as? SettingsTab,
                  let label = notification.userInfo?["label"] as? String else { return }
            // Already on the target row → its own listener scrolls; switching
            // rows re-posts after a tick so the freshly-mounted destination
            // hears it (the guard above makes the re-post a no-op here — no loop).
            let row = SottoWindowTab(settingsTab: tab)
            guard model.selectedTab != row else { return }
            select(row)
            repostSectionJump(tab: tab, label: label)
        }
        // Teardown: the retained closure must not broadcast a stale jump to a
        // remounted window. Same storage box the closure reads — the fire-time
        // == check fails.
        .onDisappear { invalidateSectionJumps() }
    }

    // MARK: - Sidebar (200px, labeled, flat)

    private var sidebar: some View {
        let visible = SettingsSearch(query: query).filteredTabs()
        let topRows = visible.filter { !$0.isSettingsGroup }
        let settingsRows = visible.filter(\.isSettingsGroup)

        return VStack(alignment: .leading, spacing: 0) {
            wordmark
                .padding(.horizontal, 18)
                .padding(.bottom, 14)

            sidebarSearchField
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(topRows, id: \.self) { tab in
                        sidebarRow(tab)
                    }

                    if !settingsRows.isEmpty {
                        SidebarGroupHeader(title: "Settings")
                        ForEach(settingsRows, id: \.self) { tab in
                            sidebarRow(tab)
                        }
                    }

                    if visible.isEmpty {
                        Text("No matches for “\(query)”")
                            .font(.ui(12))
                            .foregroundStyle(Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)

            MicStatusChip()
                .padding(.horizontal, 10)
                .padding(.top, 12)
        }
        .padding(.vertical, 12)
        // Clear the traffic-light band (fullSizeContentView transparent titlebar).
        .padding(.top, 22)
        .frame(width: Self.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Theme.Material.chrome)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }

    private var wordmark: some View {
        HStack(spacing: 0) {
            Text("sotto")
                .font(.wordmark(15))
                .foregroundStyle(Palette.inkPrimary)
            Text(".")
                .font(.wordmark(15))
                .foregroundStyle(Palette.phosphor)
        }
        .accessibilityLabel("Sotto")
    }

    /// Matte search field over every destination: the settings sections with
    /// their control keywords, the Models page and the Dictionary sections.
    /// Stays a plain TextField — the SwiftUI search modifier hard-crashes this
    /// surface (its NSSearchField re-enters layout during the display cycle).
    private var sidebarSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.mono(13))
                .foregroundStyle(Palette.inkPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.selectedRow)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        )
    }

    private func sidebarRow(_ tab: SottoWindowTab) -> some View {
        SottoSidebarRow(tab: tab, isSelected: tab == model.selectedTab) {
            selectFromSidebar(tab)
        }
    }

    // MARK: - Selection + section jumps

    /// A sidebar click. With a query active the destination also scrolls to (and
    /// highlights) its first matching section, the way the old rail search did
    /// within Settings — now across every destination.
    private func selectFromSidebar(_ tab: SottoWindowTab) {
        select(tab)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let settingsTab = tab.settingsTab,
              let label = SettingsSearch(query: query).filter(query).first(where: { $0.tab == settingsTab })?.label
        else { return }
        // Shared guarded path — identity + lifecycle checks, not a bare post.
        repostSectionJump(tab: settingsTab, label: label)
    }

    /// Every selection change routes through here: navigating anywhere
    /// invalidates in-flight section reposts.
    private func select(_ tab: SottoWindowTab) {
        invalidateSectionJumps()
        model.selectedTab = tab
    }

    /// Invalidates every in-flight section repost (their fire-time == check fails).
    private func invalidateSectionJumps() {
        sectionJumpRequest += 1
    }

    /// Posts `.selectSettingsSection` on the next runloop tick so the target
    /// destination is mounted and listening. Both guards read current @State at
    /// fire time (storage-backed, not the captured copy): the request counter
    /// drops a jump superseded by a NEWER jump — including same-row
    /// (Privacy→Backup inside Advanced) — and the selection check drops one
    /// superseded by a plain sidebar navigation.
    private func repostSectionJump(tab: SettingsTab, label: String) {
        invalidateSectionJumps()
        let request = sectionJumpRequest
        let row = SottoWindowTab(settingsTab: tab)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard sectionJumpRequest == request, model.selectedTab == row else { return }
            NotificationCenter.default.post(
                name: .selectSettingsSection,
                object: nil,
                userInfo: ["tab": tab, "label": label]
            )
        }
    }

    private func consumePendingTab() {
        if let tab = coordinator.pendingTab {
            model.selectedTab = tab
            coordinator.pendingTab = nil
        }
    }

    /// Consume a target staged while this window wasn't mounted
    /// (`SottoWindowCoordinator.open(settingsTab:/settingsSection:)` — the
    /// notifications those also post are lossy pre-mount).
    private func consumeStagedTarget() {
        guard let staged = coordinator.pendingSettingsTarget else { return }
        coordinator.pendingSettingsTarget = nil
        select(SottoWindowTab(settingsTab: staged.tab))
        if case .section(let tab, let label) = staged {
            repostSectionJump(tab: tab, label: label)
        }
    }

    /// The `SettingsTab` a `.selectSettingsTab` notification names, or nil when
    /// it names none (selection is then left unchanged). Pure + static so the
    /// routing is unit-testable.
    static func resolvedTab(from notification: Notification) -> SettingsTab? {
        notification.userInfo?["tab"] as? SettingsTab
    }

    @ViewBuilder
    private func content(for tab: SottoWindowTab) -> some View {
        switch tab {
        case .history:
            Self.historyView()
        case .dictionary:
            DictionaryDestinationView()
        case .models:
            ModelsDestinationView()
        case .general:
            GeneralDestinationView()
        case .shortcuts:
            ShortcutsDestinationView()
        case .advanced:
            AdvancedDestinationView()
        }
    }
}

// MARK: - History destination

/// The History destination the window actually renders: the today-scoped stats
/// band stacked over the EXISTING InlineHistoryView (design-mockups/02). A named
/// type so `SottoWindowTests` can assert the real composition via `historyView()`.
struct HistoryDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            HistoryStatsBand()
            InlineHistoryView()
        }
    }
}

// MARK: - Sidebar row

/// One labeled destination in the sidebar. Selected = `selectedRow` fill +
/// accent-tinted icon/label + a small accent tick on the left edge; idle is
/// `inkSecondary`, hover lifts to a faint matte fill. The window's ONE selection
/// language — there is no second rail to disagree with.
struct SottoSidebarRow: View {
    let tab: SottoWindowTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(tab.title)
                    .font(.ui(13.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(labelColor)
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(rowFill)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Palette.phosphor)
                        .frame(width: 2, height: 16)
                        .padding(.leading, 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var labelColor: Color {
        if isSelected { return SottoSidebarRowStyle.selectedLabel }
        return isHovering ? SottoSidebarRowStyle.hoverLabel : SottoSidebarRowStyle.idleLabel
    }

    private var rowFill: Color {
        if isSelected { return SottoSidebarRowStyle.selectedFill }
        return isHovering ? SottoSidebarRowStyle.hoverFill : Color.clear
    }
}

/// Matte sidebar-row colors. Selection is a nested matte fill + a phosphor edge
/// tick and label — NOT an accent-filled row. Extracted so
/// `SettingsMatteSnapshotTests` can assert the matte selection without rendering.
enum SottoSidebarRowStyle {
    /// Selected row fill — nested matte surface (NOT the accent).
    static let selectedFill = Theme.selectedRow
    /// Selected label + glyph ink. Computed so it follows the user's accent
    /// choice (never frozen).
    static var selectedLabel: Color { Palette.phosphor }
    /// Idle (unselected) glyph + label ink.
    static let idleLabel = Palette.inkSecondary
    /// Hover ink on an unselected row.
    static let hoverLabel = Palette.inkPrimary
    /// Hover fill on an unselected row.
    static let hoverFill = Theme.panel
}

// MARK: - Sidebar group header

/// The non-selectable SETTINGS label above the settings rows — the sidebar's one
/// grouping affordance, in the microlabel voice the destination headers use.
private struct SidebarGroupHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.microlabel(11))
            .tracking(0.18 * 11)
            .foregroundStyle(Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 14)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Row press feedback

/// Pointer-down feedback for the hand-built navigation rows (the sidebar and the
/// accent swatch), mirroring `LimeFillButtonStyle`'s treatment: a slight dim on
/// press, released over 120ms. Without it these rows answer a click only after
/// the destination repaints.
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Mic status chip

/// Sidebar footer: the ACTIVE transcription model + a state dot — commit green
/// when a model is selected, fail amber when none is.
/// Reads the model from the existing manager the Models destination uses.
private struct MicStatusChip: View {
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager

    private var hasModel: Bool {
        transcriptionModelManager.currentTranscriptionModel != nil
    }

    private var modelName: String {
        transcriptionModelManager.currentTranscriptionModel?.displayName ?? "No model selected"
    }

    var body: some View {
        let tone = hasModel ? Palette.stateCommit : Palette.stateFail
        return HStack(spacing: 8) {
            Circle()
                .fill(tone)
                .frame(width: 6, height: 6)
                .shadow(color: tone.opacity(0.5), radius: 3)
            Text(modelName)
                .font(.mono(11, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Theme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                )
        )
        .accessibilityLabel(hasModel ? "Active model: \(modelName)" : "No model selected")
    }
}

// MARK: - Destination header

/// The pinned 24pt title every window destination opens with, so a destination
/// always states where you are. `trailing` carries the optional microlabel.
private struct DestinationHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.ui(24, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(Palette.inkPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.microlabel(11))
                    .tracking(0.18 * 11)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 4)
    }
}

// MARK: - Models destination

/// Models as a first-class window destination: a pinned header in the style of
/// the other destinations hosting the EXISTING ModelsTab content.
struct ModelsDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            DestinationHeader(title: "Models", trailing: "ON-DEVICE")
            ModelsTab()
        }
        .background(Theme.canvas)
    }
}

// MARK: - Dictionary destination

/// Dictionary as a first-class window destination — its ONE home, hosting the
/// EXISTING VocabularyTab content (dictionary words, replacements, filler words).
struct DictionaryDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            DestinationHeader(title: "Dictionary")
            VocabularyTab()
        }
        .background(Theme.canvas)
    }
}

// MARK: - Settings destinations

/// General as a sidebar row, hosting the EXISTING GeneralTab under the shared
/// destination header. The Settings rail it used to live behind is gone.
struct GeneralDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            DestinationHeader(title: "General")
            GeneralTab()
        }
        .background(Theme.canvas)
    }
}

/// Shortcuts as a sidebar row, hosting the EXISTING ShortcutsTab.
struct ShortcutsDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            DestinationHeader(title: "Shortcuts")
            ShortcutsTab()
        }
        .background(Theme.canvas)
    }
}

/// Advanced as a sidebar row, hosting the EXISTING AdvancedTab.
struct AdvancedDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            DestinationHeader(title: "Advanced")
            AdvancedTab()
        }
        .background(Theme.canvas)
    }
}
