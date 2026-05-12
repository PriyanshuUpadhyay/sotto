import SwiftUI
import SwiftData
import KeyboardShortcuts
import OSLog

// ViewType enum with all cases
//
// W14E — `.models` is the unified Models pane (transcription + LLM
// enhancement provider). The legacy `.enhancement` case was retired and
// its destination collapsed into `.models`. Sidebar row count drops by one.
enum ViewType: String, CaseIterable, Identifiable {
    case metrics = "Dashboard"
    case transcribeAudio = "Transcribe Audio"
    case history = "History"
    case models = "Models"
    case handsFree = "Hands-free"  // W12.D
    case powerMode = "Power Mode"
    case permissions = "Permissions"
    case audioInput = "Audio Input"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .metrics: return "gauge.medium"
        case .transcribeAudio: return "waveform.circle.fill"
        case .history: return "doc.text.fill"
        case .models: return "brain.head.profile"
        case .handsFree: return "ear.fill"  // W12.D
        case .powerMode: return "sparkles.square.fill.on.square"
        case .permissions: return "shield.fill"
        case .audioInput: return "mic.fill"
        case .dictionary: return "character.book.closed.fill"
        case .snippets: return "text.cursor"
        case .settings: return "gearshape.fill"
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

struct ContentView: View {
    private let logger = Logger(subsystem: OSLogSubsystems.app, category: "ContentView")
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var engine: VoiceInkEngine
    @EnvironmentObject private var whisperModelManager: WhisperModelManager
    @EnvironmentObject private var transcriptionModelManager: TranscriptionModelManager
    @EnvironmentObject private var hotkeyManager: HotkeyManager
    @EnvironmentObject private var enhancementService: AIEnhancementService
    @AppStorage("powerModeUIFlag") private var powerModeUIFlag = false
    @State private var selectedView: ViewType? = .metrics
    /// W14D — ⌘K command-palette sheet. Window-scoped (SwiftUI binding only,
    /// no global `KeyboardShortcuts.Name` registration), so opening Settings
    /// is a precondition for activation.
    @State private var paletteOpen = false
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"

    // W14C — sidebar dot badges. Read-only state queries; no writes to W11/
    // W14A/W14B layers. Cheap Bool diffs per row, ≤11 rows total.
    @ObservedObject private var audioDeviceManager = AudioDeviceManager.shared
    @ObservedObject private var powerModeManager = PowerModeManager.shared
    @Query private var snippets: [Snippet]
    @Query private var vocabularyWords: [VocabularyWord]
    @Query private var wordReplacements: [WordReplacement]

    private var visibleViewTypes: [ViewType] {
        ViewType.allCases.filter { viewType in
            if viewType == .powerMode {
                return powerModeUIFlag
            }
            return true
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedView) {
                Section {
                    // App Header
                    HStack(spacing: 6) {
                        if let appIcon = NSImage(named: "AppIcon") {
                            Image(nsImage: appIcon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .cornerRadius(8)
                        }

                        Text("VoiceInk")
                            .font(.system(size: 14, weight: .semibold))

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                ForEach(visibleViewTypes) { viewType in
                    Section {
                        NavigationLink(value: viewType) {
                            SidebarItemView(
                                viewType: viewType,
                                isConfigured: isConfigured(viewType)
                            )
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.sidebar)
            .tint(Palette.accent)
            .navigationTitle("VoiceInk")
            .navigationSplitViewColumnWidth(210)
        } detail: {
            if let selectedView = selectedView {
                detailView(for: selectedView)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle(selectedView.rawValue)
            } else {
                Text("Select a view")
                    .foregroundColor(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        // W8 backstop — every detail pane applies its own
        // `.adaptiveGlassBackground()`, but if a future pane forgets, this
        // ensures the gap area still glasses correctly. The sidebar's own
        // `.listStyle(.sidebar)` chrome takes precedence on its column;
        // detail-pane backgrounds cover the detail column. Plan W8.
        .adaptiveGlassBackground()
        .frame(width: 950)
        .frame(minHeight: 730)
        // W14D — ⌘K palette activation. Hidden Button captures the binding
        // so the shortcut is window-scoped: only fires when the Settings
        // window is key. We don't register through `KeyboardShortcuts.Name`
        // (that's for globally-active hotkeys); SwiftUI's binding is the
        // right idiom for in-window navigation aids.
        .background(
            Button("Open command palette") {
                paletteOpen = true
            }
            .keyboardShortcut("k", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        )
        .sheet(isPresented: $paletteOpen) {
            CommandPaletteSheet(
                powerModeFlagOn: powerModeUIFlag,
                onSelect: { viewType in
                    selectedView = viewType
                    paletteOpen = false
                },
                onDismiss: { paletteOpen = false }
            )
        }
        .onAppear {
            logger.notice("ContentView appeared")
        }
        .onDisappear {
            logger.notice("ContentView disappeared")
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToDestination)) { notification in
            if let destination = notification.userInfo?["destination"] as? String {
                logger.notice("navigateToDestination received: \(destination, privacy: .public)")
                switch destination {
                case "Settings":
                    selectedView = .settings
                // W14E — Models pane is unified. Both legacy destinations
                // ("AI Models" from MetricsSetupView, "Enhancement" from
                // ImportExportService) and the new alias ("Models") route
                // here. No deep-link callers need updating.
                case "Models", "AI Models", "Enhancement":
                    selectedView = .models
                case "History":
                    selectedView = .history
                case "Permissions":
                    selectedView = .permissions
                case "Transcribe Audio":
                    selectedView = .transcribeAudio
                case "Power Mode":
                    selectedView = .powerMode
                default:
                    break
                }
            }
        }
    }
    
    // W14C — per-ViewType "is this customized vs default?" predicate. Read-
    // only against existing state. Returns nil (no badge) for panes where
    // there's no honest "configured vs default" signal — Dashboard, Transcribe
    // Audio, History, Permissions, Settings (composite catch-all).
    private func isConfigured(_ viewType: ViewType) -> Bool {
        switch viewType {
        case .metrics, .transcribeAudio, .history, .permissions, .settings:
            return false
        case .models:
            // LLM provider connected = user has set up something.
            // Default install has no API keys / no MLX model / AFM only if
            // macOS 26+ — `connectedProviders` correctly reflects all paths.
            return !enhancementService.aiService.connectedProviders.isEmpty
        case .handsFree:
            // Hotkey bound is the primary signal; trigger phrases edited
            // also counts so power users tuning triggers without binding the
            // hotkey still get the dot. Cheap one-liner.
            let hotkeySet = KeyboardShortcuts.getShortcut(for: .handsFreeToggle) != nil
            return hotkeySet || !HandsFreeMode.current().triggerPhrases.isEmpty
        case .powerMode:
            return !powerModeManager.enabledConfigurations.isEmpty
        case .audioInput:
            return audioDeviceManager.inputMode != .systemDefault
        case .dictionary:
            return !vocabularyWords.isEmpty || !wordReplacements.isEmpty
        case .snippets:
            return !snippets.isEmpty
        }
    }

    @ViewBuilder
    private func detailView(for viewType: ViewType) -> some View {
        switch viewType {
        case .metrics:
            MetricsView()
        case .models:
            ModelsView()
        case .handsFree:
            HandsFreeSettingsView()
        case .transcribeAudio:
            AudioTranscribeView()
        case .history:
            InlineHistoryView()
        case .audioInput:
            AudioInputSettingsView()
        case .dictionary:
            DictionarySettingsView(whisperPrompt: whisperModelManager.whisperPrompt)
        case .snippets:
            SnippetsSettingsView()
        case .powerMode:
            PowerModeView()
        case .settings:
            SettingsView()
        case .permissions:
            PermissionsView()
        }
    }
}

private struct SidebarItemView: View {
    let viewType: ViewType
    /// W14C — true when the user has customized this pane (non-default state).
    /// Renders a small accent dot next to the trailing edge as at-a-glance
    /// signal without restructuring the IA. Subtle, low-saturation; no new
    /// colors. Skipped panes pass `false` so the dot is hidden.
    let isConfigured: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: viewType.icon)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 24, height: 24)

            Text(viewType.rawValue)
                .font(.system(size: 14, weight: .medium))

            Spacer()

            if isConfigured {
                Circle()
                    .fill(Palette.accent.opacity(0.85))
                    .frame(width: 6, height: 6)
                    .accessibilityLabel("Configured")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
    }
}

