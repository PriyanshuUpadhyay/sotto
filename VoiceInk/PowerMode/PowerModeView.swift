import SwiftUI
import SwiftData

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .center,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

enum ConfigurationMode: Hashable {
    case add
    case edit(PowerModeConfig)

    var isAdding: Bool {
        if case .add = self { return true }
        return false
    }

    var title: String {
        switch self {
        case .add: return "Add Power Mode"
        case .edit: return "Edit Power Mode"
        }
    }

    func hash(into hasher: inout Hasher) {
        switch self {
        case .add:
            hasher.combine(0)
        case .edit(let config):
            hasher.combine(1)
            hasher.combine(config.id)
        }
    }

    static func == (lhs: ConfigurationMode, rhs: ConfigurationMode) -> Bool {
        switch (lhs, rhs) {
        case (.add, .add):
            return true
        case (.edit(let lhsConfig), .edit(let rhsConfig)):
            return lhsConfig.id == rhsConfig.id
        default:
            return false
        }
    }
}

enum ConfigurationType {
    case application
    case website
}

let commonEmojis = ["🏢", "🏠", "💼", "🎮", "📱", "📺", "🎵", "📚", "✏️", "🎨", "🧠", "⚙️", "💻", "🌐", "📝", "📊", "🔍", "💬", "📈", "🔧"]

// MARK: - PowerModeView (P2.H / spec §3.12)
//
// Settings → Power Modes container. Hosts the new horizontal `PowerModeStripView`
// in place of the v1 vertical-list / expandable-row scaffolding. Hero header
// uses the spec §3.3 typography (28pt rounded title + 14pt subtitle).
//
// The reorder side-panel (v1 affordance) is dropped — drag-to-reorder lives
// inline on the strip via `PowerModeDropDelegate`. Edit + add panels still
// open through the existing `slidingPanel` host so the rest of the app's
// navigation stays unchanged.
//
// Empty state — when there are no Power Modes yet — is a glass card hero
// instead of the v1 SF symbol stack.

struct PowerModeView: View {
    @StateObject private var powerModeManager = PowerModeManager.shared
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @EnvironmentObject private var aiService: AIService
    @State private var configurationMode: ConfigurationMode?
    @State private var isPanelOpen = false
    @State private var panelID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            heroHeader
            content
        }
        .background(Color(NSColor.controlBackgroundColor))
        .slidingPanel(isPresented: .init(
            get: { isPanelOpen },
            set: { if !$0 { closePanel() } }
        ), width: 480) {
            if let mode = configurationMode {
                ConfigurationView(mode: mode, powerModeManager: powerModeManager, onDismiss: closePanel)
                    .id(panelID)
            }
        }
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Power Modes")
                    .font(.system(size: 28, weight: .bold, design: .default))
                    .foregroundColor(.primary)

                InfoTip(
                    "Automatically apply custom configurations based on the app/website you are using.",
                    learnMoreURL: "https://tryvoiceink.com/docs/power-mode"
                )
            }

            Text("Switch context automatically based on the active app or website.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Content — strip or empty state

    @ViewBuilder
    private var content: some View {
        if powerModeManager.configurations.isEmpty {
            emptyState
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
        } else {
            PowerModeStripView(
                powerModeManager: powerModeManager,
                onEditConfig: { config in
                    openPanel(mode: .edit(config))
                },
                onAddConfig: {
                    openPanel(mode: .add)
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            GlassCard(cornerRadius: 18, padding: 28) {
                VStack(spacing: 14) {
                    Image(systemName: "bolt.circle.fill")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundColor(Palette.warn)

                    VStack(spacing: 4) {
                        Text("No Power Modes Yet")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Configure per-app behavior in Power Modes.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        openPanel(mode: .add)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Add Power Mode")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Palette.warn)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 360)
            Spacer()
        }
    }

    private func openPanel(mode: ConfigurationMode) {
        configurationMode = mode
        panelID = UUID()
        withAnimation(.smooth(duration: 0.3)) {
            isPanelOpen = true
        }
    }

    private func closePanel() {
        withAnimation(.smooth(duration: 0.3)) {
            isPanelOpen = false
            configurationMode = nil
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 16, weight: .bold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
    }
}
