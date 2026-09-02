import SwiftUI

enum SottoWindowTab: CaseIterable, Hashable {
    case history
    case models
    case dictionary
    case settings

    var title: String {
        switch self {
        case .history:        return "History"
        case .models:         return "Models"
        case .dictionary:     return "Dictionary"
        case .settings:       return "Settings"
        }
    }

    /// SF Symbol per destination — drives the labeled sidebar.
    var systemImage: String {
        switch self {
        case .history:        return "clock"
        case .models:         return "cpu"
        case .dictionary:     return "character.book.closed"
        case .settings:       return "gearshape"
        }
    }

    /// Settings anchors to the bottom of the sidebar (the conventional macOS
    /// utility placement); everything else stacks from the top.
    var isBottomAnchored: Bool { self == .settings }
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

    init(model: TriptychModel = TriptychModel()) {
        _model = StateObject(wrappedValue: model)
    }

    static var renderedTabs: [SottoWindowTab] { SottoWindowTab.allCases }

    static func historyView() -> HistoryDestinationView {
        HistoryDestinationView()
    }

    static func settingsView() -> SettingsContentView {
        // Only the window-hosted instance consumes coordinator-staged Settings
        // targets — they're staged for this window's mount.
        SettingsContentView(consumesStagedTarget: true)
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
        .onAppear { consumePendingTab() }
        .onChange(of: coordinator.pendingTab) { consumePendingTab() }
    }

    // MARK: - Sidebar (200px, labeled)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
                .padding(.horizontal, 18)
                .padding(.bottom, 16)

            VStack(spacing: 2) {
                ForEach(Self.renderedTabs.filter { !$0.isBottomAnchored }, id: \.self) { tab in
                    sidebarRow(tab)
                }

                Spacer(minLength: 0)

                ForEach(Self.renderedTabs.filter { $0.isBottomAnchored }, id: \.self) { tab in
                    sidebarRow(tab)
                }
            }
            .padding(.horizontal, 10)

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

    private func sidebarRow(_ tab: SottoWindowTab) -> some View {
        SottoSidebarRow(tab: tab, isSelected: tab == model.selectedTab) {
            model.selectedTab = tab
        }
    }

    private func consumePendingTab() {
        if let tab = coordinator.pendingTab {
            model.selectedTab = tab
            coordinator.pendingTab = nil
        }
    }

    @ViewBuilder
    private func content(for tab: SottoWindowTab) -> some View {
        switch tab {
        case .history:
            Self.historyView()
        case .models:
            ModelsDestinationView()
        case .dictionary:
            DictionaryDestinationView()
        case .settings:
            SettingsDestinationView()
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
/// `inkSecondary`, hover lifts to a faint matte fill.
private struct SottoSidebarRow: View {
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
        if isSelected { return Palette.phosphor }
        return isHovering ? Palette.inkPrimary : Palette.inkSecondary
    }

    private var rowFill: Color {
        if isSelected { return Theme.selectedRow }
        return isHovering ? Theme.panel : Color.clear
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

/// Dictionary as a first-class window destination — its ONE home. The rail row
/// under Settings is gone, so the EXISTING VocabularyTab content (dictionary
/// words, replacements, filler words) is reachable from exactly one place.
struct DictionaryDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            DestinationHeader(title: "Dictionary")
            VocabularyTab()
        }
        .background(Theme.canvas)
        .onAppear { consumeStagedSection() }
        // A live jump means the staged copy has been delivered; it must not
        // re-apply on a later manual visit.
        .onReceive(NotificationCenter.default.publisher(for: .selectSettingsSection)) { _ in
            SottoWindowCoordinator.shared.pendingDictionarySection = nil
        }
    }

    /// Consume a section jump staged while this destination wasn't mounted
    /// (`SottoWindowCoordinator.open(dictionarySection:)` — the notification it
    /// also posts is lossy pre-mount). Reposted on the next runloop tick so the
    /// freshly-mounted VocabularyTab is listening.
    private func consumeStagedSection() {
        guard let label = SottoWindowCoordinator.shared.pendingDictionarySection else { return }
        SottoWindowCoordinator.shared.pendingDictionarySection = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: .selectSettingsSection,
                object: nil,
                userInfo: ["tab": SettingsTab.vocabulary, "label": label]
            )
        }
    }
}

// MARK: - Settings destination

/// Settings with the same pinned title its siblings carry, over the EXISTING
/// in-window SettingsContentView.
struct SettingsDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            DestinationHeader(title: "Settings")
            SottoWindowView.settingsView()
        }
        .background(Theme.canvas)
    }
}
