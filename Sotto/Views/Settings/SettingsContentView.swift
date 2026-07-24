import SwiftUI

/// A Settings rail destination: one of the SettingsTab pages, or the local
/// Appearance page (not a SettingsTab — the tab enum + search index stay
/// untouched; Appearance is a rail-level extra owned by this view).
enum SettingsDestination: Hashable {
    case tab(SettingsTab)
    case appearance
}

struct SettingsContentView: View {
    /// True only for the Sotto-window-hosted instance (SottoWindowView
    /// .settingsView()): coordinator-staged targets are meant for that window,
    /// so only it may consume/clear them. The native Settings scene keeps
    /// live-notification behavior only — otherwise it races the stage away
    /// before the window's instance mounts.
    var consumesStagedTarget: Bool = false

    @State private var selection: SettingsDestination = .tab(.general)
    @State private var query = ""
    // Identity of the latest section-jump request — a scheduled repost checks
    // it at fire time so a newer same-tab jump supersedes a pending one.
    @State private var sectionJumpRequest = 0
    // Observed at this root so the standalone Settings scene re-renders on an
    // accent change too (the Sotto window root observes it separately).
    @ObservedObject private var accent = AccentStore.shared

    var body: some View {
        HStack(spacing: 0) {
            rail
            detail(for: selection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .tint(Brand.tint)
        .onAppear { consumeStagedTarget() }
        .onReceive(NotificationCenter.default.publisher(for: .selectSettingsTab)) { notification in
            // Delivered while the window's instance is mounted — its staged
            // copy must not re-apply later.
            if consumesStagedTarget {
                SottoWindowCoordinator.shared.pendingSettingsTarget = nil
            }
            switch Self.action(current: currentTab, notification: notification) {
            case .select(let tab):
                setSelection(.tab(tab))
            case .openModelsWindowTab:
                // Leaving this surface — kill in-flight reposts (no new
                // selection to set; the window swaps to the Models destination).
                invalidateSectionJumps()
                SottoWindowCoordinator.shared.open(tab: .models)
            }
            query = ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectSettingsSection)) { notification in
            // Every section request supersedes any in-flight repost — bumped
            // BEFORE the same-tab early return below, which otherwise leaves a
            // stale scheduled repost passing its guards and overriding this one.
            invalidateSectionJumps()
            if consumesStagedTarget {
                SottoWindowCoordinator.shared.pendingSettingsTarget = nil
            }
            guard let tab = notification.userInfo?["tab"] as? SettingsTab, tab != .models,
                  let label = notification.userInfo?["label"] as? String else { return }
            // Already on the target tab → its own listener scrolls; switching
            // tabs re-posts after a tick so the freshly-mounted tab hears it
            // (the guard above makes the re-post a no-op here — no loop).
            guard selection != .tab(tab) else { return }
            setSelection(.tab(tab))
            repostSectionJump(tab: tab, label: label)
        }
        // Teardown (e.g. window swaps to Models inside the 50ms window): the
        // retained closure must not broadcast a stale jump to a remounted or
        // other Settings surface. Same storage box the closure reads — the
        // fire-time == check fails.
        .onDisappear { invalidateSectionJumps() }
    }

    /// Invalidates every in-flight section repost (their fire-time == check fails).
    private func invalidateSectionJumps() {
        sectionJumpRequest += 1
    }

    /// Every selection change routes through here: navigating anywhere
    /// invalidates in-flight section reposts.
    private func setSelection(_ destination: SettingsDestination) {
        invalidateSectionJumps()
        selection = destination
    }

    /// Consume a Settings target staged while the window's instance wasn't
    /// mounted (SottoWindowCoordinator.open(settingsTab:/settingsSection:) —
    /// the notifications those also post are lossy pre-mount). In-window
    /// instance only; the native scene must not race the stage away.
    private func consumeStagedTarget() {
        guard consumesStagedTarget,
              let staged = SottoWindowCoordinator.shared.pendingSettingsTarget else { return }
        SottoWindowCoordinator.shared.pendingSettingsTarget = nil
        guard staged.tab != .models else { return }
        setSelection(.tab(staged.tab))
        if case .section(let tab, let label) = staged {
            repostSectionJump(tab: tab, label: label)
        }
    }

    /// Posts `.selectSettingsSection` on the next runloop tick so the target
    /// tab is mounted and listening (same pattern as `selectTab`). Both guards
    /// read current @State at fire time (storage-backed, not the captured
    /// copy): the request counter drops a jump superseded by a NEWER jump —
    /// including same-tab (Privacy→Backup inside the window) — and the
    /// selection check drops one superseded by a plain tab navigation.
    private func repostSectionJump(tab: SettingsTab, label: String) {
        invalidateSectionJumps()
        let request = sectionJumpRequest
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard sectionJumpRequest == request, selection == .tab(tab) else { return }
            NotificationCenter.default.post(
                name: .selectSettingsSection,
                object: nil,
                userInfo: ["tab": tab, "label": label]
            )
        }
    }

    /// What a `.selectSettingsTab` notification does. `.models` is remapped to
    /// the window-level Models destination (mirrors `SottoWindowCoordinator
    /// .route`) — it has no rail row here, so selecting it would render a
    /// hidden, unreachable page. Pure + static so the remap is unit-testable.
    enum TabNotificationAction: Equatable {
        case select(SettingsTab)
        case openModelsWindowTab
    }

    static func action(current: SettingsTab, notification: Notification) -> TabNotificationAction {
        let next = nextSelection(current: current, notification: notification)
        return next == .models ? .openModelsWindowTab : .select(next)
    }

    private var currentTab: SettingsTab {
        if case .tab(let tab) = selection { return tab }
        return .general
    }

    // MARK: - Rail

    /// Onyx vertical rail: search field on top, narrowed tab list below. The
    /// list is the EXISTING `SettingsSearch.filteredTabs()` — typing narrows it.
    /// Models is excluded: it graduated to a first-class window destination
    /// (2026-07 revamp) and must live in exactly one place.
    private var rail: some View {
        let tabs = SettingsSearch(query: query).filteredTabs().filter { $0 != .models }
        return VStack(spacing: 0) {
            railSearchField
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        SettingsRailRow(tab: tab, isSelected: selection == .tab(tab)) {
                            selectTab(tab)
                        }
                    }
                    if showsAppearanceRow {
                        SettingsRailRow(title: "Appearance", systemImage: "paintpalette", isSelected: selection == .appearance) {
                            setSelection(.appearance)
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(Theme.canvas)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.hairline).frame(width: 1)
        }
    }

    /// Matte search field: magnifyingglass + `.plain` mono TextField on a nested
    /// matte fill with a hairline edge (stays a plain TextField — the SwiftUI
    /// search modifier hard-crashes this surface).
    private var railSearchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.inkSecondary)
            TextField("Search settings", text: $query)
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

    /// Appearance isn't in the search index; it stays visible while the rail is
    /// unfiltered, or when the query names it.
    private var showsAppearanceRow: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || "Appearance".localizedCaseInsensitiveContains(trimmed)
    }

    /// Selects a tab. If a query is active, posts `.selectSettingsSection` (on
    /// the next runloop tick so the freshly-mounted detail tab is listening) so
    /// the destination tab scrolls to its first matching section.
    private func selectTab(_ tab: SettingsTab) {
        setSelection(.tab(tab))
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let label = SettingsSearch(query: query).filter(query).first(where: { $0.tab == tab })?.label else { return }
        // Shared guarded path — identity + lifecycle checks, not a bare post.
        repostSectionJump(tab: tab, label: label)
    }

    static func nextSelection(current: SettingsTab, notification: Notification) -> SettingsTab {
        resolvedTab(from: notification) ?? current
    }

    static func resolvedTab(from notification: Notification) -> SettingsTab? {
        notification.userInfo?["tab"] as? SettingsTab
    }

    @ViewBuilder
    private func detail(for destination: SettingsDestination) -> some View {
        switch destination {
        case .tab(.general): GeneralTab()
        case .tab(.shortcuts): ShortcutsTab()
        // Unreachable: the rail filters .models out and the .selectSettingsTab
        // reducer (action(current:notification:)) remaps it to the window-level
        // destination. Models renders in exactly one place — the window sidebar.
        case .tab(.models): EmptyView()
        case .tab(.vocabulary): VocabularyTab()
        case .tab(.advanced): AdvancedTab()
        case .appearance: AppearanceSettingsView()
        }
    }
}

// MARK: - Appearance

/// APPEARANCE settings: the 4-swatch accent picker + the static reduced-motion
/// row. Writes `AccentStore` (persisted to UserDefaults); window roots observe
/// the store so the accent updates live.
struct AppearanceSettingsView: View {
    @ObservedObject private var accent = AccentStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                SettingsCard(
                    iconSystemName: "paintpalette",
                    iconTint: Brand.tint,
                    title: "Appearance",
                    subtitle: "Accent color for selection, signals, and the recorder."
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 16) {
                            rowLabel("Accent")
                            HStack(spacing: 18) {
                                ForEach(AccentChoice.allCases) { choice in
                                    swatch(choice)
                                }
                            }
                        }
                        .padding(.vertical, 14)

                        Rectangle().fill(Theme.hairline).frame(height: 1)

                        HStack(spacing: 16) {
                            rowLabel("Reduced motion")
                            Text("FOLLOWS SYSTEM")
                                .font(.microlabel(11))
                                .tracking(0.18 * 11)
                                .foregroundStyle(Palette.inkSecondary)
                        }
                        .padding(.vertical, 14)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.microlabel(11))
            .tracking(0.18 * 11)
            .foregroundStyle(Palette.inkSecondary)
            .frame(width: 140, alignment: .leading)
    }

    /// 18pt dot in a ≥24pt hit target; selected = a ring in the swatch's own
    /// color, offset from the dot.
    private func swatch(_ choice: AccentChoice) -> some View {
        let isSelected = accent.choice == choice
        return VStack(spacing: 7) {
            Button {
                accent.choice = choice
            } label: {
                ZStack {
                    Circle()
                        .fill(choice.color)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1))
                    if isSelected {
                        Circle()
                            .strokeBorder(choice.color, lineWidth: 2)
                            .frame(width: 26, height: 26)
                    }
                }
                .frame(width: 28, height: 28)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(choice.title) accent")
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            Text(choice.title.uppercased())
                .font(.microlabel(10))
                .tracking(0.12 * 10)
                .foregroundStyle(Palette.inkSecondary)
        }
    }
}

// MARK: - Rail row

/// Matte rail-row colors (the dev-tool rail look). Selection is a `mtRaise2`
/// fill + inset hairline + phosphor glyph + primary-ink label — NOT the old
/// black-text-on-lime accent fill. Extracted so `SettingsMatteSnapshotTests`
/// can assert the matte selection without rendering.
enum SettingsRailRowStyle {
    /// Selected row fill — nested matte surface (NOT the accent).
    static let selectedFill = Palette.mtRaise2
    /// Selected glyph — the only place the accent signal enters the rail.
    /// Computed so it follows the user's accent choice (never frozen).
    static var selectedGlyph: Color { Palette.phosphor }
    /// Selected label ink.
    static let label = Palette.inkPrimary
    /// Idle (unselected) glyph + label ink.
    static let idleLabel = Palette.inkSecondary
    /// Hover fill on an unselected row.
    static let hoverFill = Palette.mtRaise
    /// Inset hairline drawn around the selected row.
    static let selectedHairline = Palette.mtLine2
}

/// One row in the Settings rail. Matte dev-tool selection: the selected row
/// fills `mtRaise2` with an inset hairline, a phosphor glyph, and a primary-ink
/// label; others read `inkSecondary`, hover → a faint matte fill.
struct SettingsRailRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    init(title: String, systemImage: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.action = action
    }

    init(tab: SettingsTab, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title: tab.title, systemImage: tab.systemImage, isSelected: isSelected, action: action)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? SettingsRailRowStyle.selectedGlyph : SettingsRailRowStyle.idleLabel)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? SettingsRailRowStyle.label : SettingsRailRowStyle.idleLabel)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(shape.fill(rowFill))
            .overlay {
                if isSelected {
                    shape.strokeBorder(SettingsRailRowStyle.selectedHairline, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }

    private var rowFill: Color {
        if isSelected { return SettingsRailRowStyle.selectedFill }
        return isHovering ? SettingsRailRowStyle.hoverFill : Color.clear
    }
}

// MARK: - Section scroll-to + highlight (shared by all five tabs)

extension View {
    /// A phosphor ring drawn around a section the search jumped to. Animated
    /// fade under normal motion; instant under reduceMotion.
    @ViewBuilder
    func settingsSectionHighlight(active: Bool, reduceMotion: Bool) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.phosphor, lineWidth: 2)
                .opacity(active ? 1 : 0)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: active)
                .allowsHitTesting(false)
        )
    }
}

/// Handles a `.selectSettingsSection` notification inside a tab: if the target
/// tab is this one, scroll its first section whose `searchLabel` matches, and
/// set a brief highlight. `sections`/`label` keep it generic over each tab's
/// own section enum.
@MainActor
func handleSettingsSectionJump<S: Hashable>(
    _ notification: Notification,
    thisTab: SettingsTab,
    sections: [S],
    label: (S) -> String,
    proxy: ScrollViewProxy,
    reduceMotion: Bool,
    highlight: Binding<S?>
) {
    guard notification.userInfo?["tab"] as? SettingsTab == thisTab,
          let targetLabel = notification.userInfo?["label"] as? String,
          let section = sections.first(where: { label($0) == targetLabel })
    else { return }

    if reduceMotion {
        proxy.scrollTo(section, anchor: .top)
    } else {
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(section, anchor: .top)
        }
    }

    highlight.wrappedValue = section
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        if highlight.wrappedValue == section {
            highlight.wrappedValue = nil
        }
    }
}
