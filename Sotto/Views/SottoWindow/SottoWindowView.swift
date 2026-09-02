import SwiftUI

enum SottoWindowTab: CaseIterable, Hashable {
    case history
    case models
    case settings

    var title: String {
        switch self {
        case .history:        return "History"
        case .models:         return "Models"
        case .settings:       return "Settings"
        }
    }

    /// SF Symbol per destination — drives the labeled sidebar.
    var systemImage: String {
        switch self {
        case .history:        return "clock"
        case .models:         return "cpu"
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
        case .settings:
            Self.settingsView()
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
                    .font(.system(size: 13.5, weight: .medium))
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

// MARK: - Models destination

/// Models as a first-class window destination: a pinned header in the style of
/// the other destinations hosting the EXISTING ModelsTab content.
struct ModelsDestinationView: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Models")
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(Palette.inkPrimary)
                Spacer()
                Text("ON-DEVICE")
                    .font(.microlabel(11))
                    .tracking(0.18 * 11)
                    .foregroundStyle(Palette.inkSecondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 30)
            .padding(.bottom, 4)

            ModelsTab()
        }
        .background(Theme.canvas)
    }
}
