import SwiftUI
import SwiftData
import Sparkle
import AppKit
import OSLog
import AppIntents
import Combine
import FluidAudio

@main
struct VoiceInkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    let containerInitializationFailed: Bool
    // Stats are persisted in a SEPARATE local-only ModelContainer (stats.store)
    // so SessionMetric records survive transcript cleanup and never round-trip
    // through CloudKit (cloudKitDatabase: .none). Existing transcripts container
    // is unchanged.
    let statsContainer: ModelContainer

    @StateObject private var engine: VoiceInkEngine
    @StateObject private var whisperModelManager: WhisperModelManager
    @StateObject private var fluidAudioModelManager: FluidAudioModelManager
    @StateObject private var transcriptionModelManager: TranscriptionModelManager
    @StateObject private var recorderUIManager: RecorderUIManager
    @StateObject private var hotkeyManager: HotkeyManager
    @StateObject private var updaterViewModel: UpdaterViewModel
    @StateObject private var menuBarManager: MenuBarManager
    @StateObject private var aiService = AIService()
    @StateObject private var enhancementService: AIEnhancementService
    @StateObject private var failureRegistry: FailureRegistry
    @StateObject private var activeWindowService = ActiveWindowService.shared
    @AppStorage("enableAnnouncements") private var enableAnnouncements = true
    @AppStorage("legacyMLXDirPurged") private var legacyMLXDirPurged: Bool = false
    @State private var showMenuBarIcon = true

    // Audio cleanup manager for automatic deletion of old audio files
    private let audioCleanupManager = AudioCleanupManager.shared

    // Transcription auto-cleanup service for zero data retention
    private let transcriptionAutoCleanupService = TranscriptionAutoCleanupService.shared

    // Model prewarm service for optimizing model on wake from sleep
    @StateObject private var prewarmService: ModelPrewarmService

    init() {
        // Disable HTTP response caching — prevents API responses from being stored in Cache.db
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0)

        AppDefaults.registerDefaults()

        if UserDefaults.standard.object(forKey: "powerModeUIFlag") == nil {
            let hasEnabledPowerModes = PowerModeManager.shared.configurations.contains { $0.isEnabled }
            UserDefaults.standard.set(hasEnabledPowerModes, forKey: "powerModeUIFlag")
        }

        let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "Initialization")
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            Snippet.self,
            ScratchpadDocument.self,
            ScratchpadVersion.self
        ])
        var initializationFailed = false

        // Attempt 1: Try persistent storage
        if let persistentContainer = Self.createPersistentContainer(schema: schema, logger: logger) {
            container = persistentContainer
        }
        // Attempt 2: Try in-memory storage
        else if let memoryContainer = Self.createInMemoryContainer(schema: schema, logger: logger) {
            container = memoryContainer

            logger.warning("Using in-memory storage as fallback. Data will not persist between sessions.")

            // Show alert to user about storage issue
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Storage Warning"
                alert.informativeText = "VoiceInk couldn't access its storage location. Your transcriptions will not be saved between sessions."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
        // All attempts failed
        else {
            logger.critical("ModelContainer initialization failed")
            initializationFailed = true

            // Create minimal in-memory container to satisfy initialization
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = (try? ModelContainer(for: schema, configurations: [config])) ?? {
                preconditionFailure("Unable to create ModelContainer. SwiftData is unavailable.")
            }()
        }

        containerInitializationFailed = initializationFailed

        // Open the separate stats.store ModelContainer. Local-only by design —
        // CloudKit sync was producing duplicate/inconsistent SessionMetric
        // records across devices (upstream 60bc7a0), so cloudKitDatabase is
        // pinned to .none. Falls back to in-memory if persistent open fails;
        // a hard preconditionFailure is reserved for SwiftData being entirely
        // unavailable (mirrors the transcripts container fallback ladder).
        let statsSchema = Schema([SessionMetric.self])
        let resolvedStatsContainer: ModelContainer
        if let persistentStats = Self.createPersistentStatsContainer(schema: statsSchema, logger: logger) {
            resolvedStatsContainer = persistentStats
        } else if let memoryStats = Self.createInMemoryStatsContainer(schema: statsSchema, logger: logger) {
            logger.warning("Using in-memory stats storage as fallback. Session metrics will not persist between sessions.")
            resolvedStatsContainer = memoryStats
        } else {
            logger.critical("Stats ModelContainer initialization failed")
            let config = ModelConfiguration(schema: statsSchema, isStoredInMemoryOnly: true)
            resolvedStatsContainer = (try? ModelContainer(for: statsSchema, configurations: [config])) ?? {
                preconditionFailure("Unable to create stats ModelContainer. SwiftData is unavailable.")
            }()
        }
        statsContainer = resolvedStatsContainer

        // W12.E — expose the container to static call sites that can't take
        // it via injection (CursorPaster's paste-fallback branch). Plan
        // §Task 8.2.
        ScratchpadModelContainerProvider.shared.modelContainer = container

        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)

        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)

        // 1. Create modelsDirectory URL
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.prakashjoshipax.VoiceInk")
        let modelsDirectory = appSupportDirectory.appendingPathComponent("WhisperModels")

        // 2. Create model managers
        let whisperModelManager = WhisperModelManager(modelsDirectory: modelsDirectory)
        let fluidAudioModelManager = FluidAudioModelManager()
        let transcriptionModelManager = TranscriptionModelManager(
            whisperModelManager: whisperModelManager,
            fluidAudioModelManager: fluidAudioModelManager
        )

        // 3. Create UI manager
        let recorderUIManager = RecorderUIManager()

        // Failure registry remembers unresolved failures for the cluster +
        // menubar dot. Built before the engine so the engine can ack on
        // successful runs via its init-injected reference.
        let failureRegistry = FailureRegistry()

        // 4. Create engine
        let engine = VoiceInkEngine(
            modelContext: container.mainContext,
            whisperModelManager: whisperModelManager,
            transcriptionModelManager: transcriptionModelManager,
            enhancementService: enhancementService,
            failureRegistry: failureRegistry
        )

        // Engine is now constructed — wire the publisher subscription.
        failureRegistry.attach(to: engine.failurePublisher.eraseToAnyPublisher())
        _failureRegistry = StateObject(wrappedValue: failureRegistry)

        // 5. Configure circular deps
        recorderUIManager.configure(engine: engine, recorder: engine.recorder, failureRegistry: failureRegistry)
        engine.recorderUIManager = recorderUIManager

        // W12.B — Command Mode service singleton needs both the recorder UI
        // (to open the recorder on Caps+9) and the enhance service (to drive
        // the rewrite). Wired here once, after both are constructed.
        CommandModeService.shared.configure(
            recorderUIManager: recorderUIManager,
            enhancementService: enhancementService
        )

        // 6. Initialize model state
        // Migration and refreshAllAvailableModels must run before loadCurrentTranscriptionModel so renamed keys are remapped and imported models are present when restoring the saved selection.
        StreamingKeysMigration.run()
        whisperModelManager.createModelsDirectoryIfNeeded()
        whisperModelManager.loadAvailableModels()
        transcriptionModelManager.refreshAllAvailableModels()
        transcriptionModelManager.loadCurrentTranscriptionModel()

        _whisperModelManager = StateObject(wrappedValue: whisperModelManager)
        _fluidAudioModelManager = StateObject(wrappedValue: fluidAudioModelManager)
        _transcriptionModelManager = StateObject(wrappedValue: transcriptionModelManager)
        _recorderUIManager = StateObject(wrappedValue: recorderUIManager)
        _engine = StateObject(wrappedValue: engine)

        // 7. Create other services that depend on engine
        let hotkeyManager = HotkeyManager(engine: engine, recorderUIManager: recorderUIManager)
        _hotkeyManager = StateObject(wrappedValue: hotkeyManager)

        let menuBarManager = MenuBarManager()
        _menuBarManager = StateObject(wrappedValue: menuBarManager)
        menuBarManager.configure(modelContainer: container, engine: engine)

        let activeWindowService = ActiveWindowService.shared
        activeWindowService.configure(with: enhancementService)
        _activeWindowService = StateObject(wrappedValue: activeWindowService)

        let prewarmService = ModelPrewarmService(
            transcriptionModelManager: transcriptionModelManager,
            whisperModelManager: whisperModelManager,
            modelContext: container.mainContext,
            enhancementService: enhancementService
        )
        _prewarmService = StateObject(wrappedValue: prewarmService)

        appDelegate.menuBarManager = menuBarManager

        // Bind menu bar icon to engine state. Spec §3.11 / plan §P2.C —
        // animated icon reflects idle / recording / transcribing / enhancing
        // via Combine on `engine.$recordingState`.
        appDelegate.recordingStateObserver.bind(to: engine)
        appDelegate.recordingStateObserver.bind(toRegistry: failureRegistry)

        // One-time migration: reclaim the legacy `MLXModels/` cache from the
        // mlx-swift 2.x era. Sentinel-guarded so it only runs once per install.
        // `swift-huggingface` 0.9.0 lands snapshots under `~/Library/Caches/`
        // instead, leaving the legacy dir orphaned. Spec §5 row W6 + W6 plan.
        // Only flip the sentinel on success — failure path retries next launch
        // (idempotent + bounded by the helper's path sentinel guard).
        if !legacyMLXDirPurged {
            let succeeded = MLXModelRegistry.purgeLegacyApplicationSupportModelsIfPresent()
            if succeeded { legacyMLXDirPurged = true }
        }

        // Wipe stale `mlx_selected_model_id` for entries dropped from the W6
        // curated registry. Idempotent: once cleared, subsequent launches
        // see `nil` and the if-let fails. Independent of the dir purge above.
        let staleMLXIds: Set<String> = [
            "mlx-community/gemma-3-1b-it-qat-4bit",
            "mlx-community/Qwen3.6-27B-4bit"
        ]
        if let current = UserDefaults.standard.string(forKey: "mlx_selected_model_id"),
           staleMLXIds.contains(current) {
            UserDefaults.standard.removeObject(forKey: "mlx_selected_model_id")
        }

        // P3.F: warm up the AVAudioEngine that powers synthesized cues. Starts
        // the audio graph + schedules a silent pre-roll so the first user cue
        // (recording start) plays without ~50–100ms first-fire latency.
        SoundManager.shared.warmUp()

        // Ensure no lingering recording state from previous runs
        Task {
            await recorderUIManager.resetOnLaunch()
        }

        AppShortcuts.updateAppShortcutParameters()

        // Start cleanup service for the app's lifetime, not tied to window lifecycle
        TranscriptionAutoCleanupService.shared.startMonitoring(modelContext: container.mainContext)
    }

    // MARK: - Container Creation Helpers

    private static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Create app-specific Application Support directory URL
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)

            // Create the directory if it doesn't exist
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            // Define storage locations
            let defaultStoreURL = appSupportURL.appendingPathComponent("default.store")
            let dictionaryStoreURL = appSupportURL.appendingPathComponent("dictionary.store")

            // Transcript configuration
            // W12.E — ScratchpadDocument + ScratchpadVersion join the local
            // "default" store (NOT the CloudKit "dictionary" store). Single-
            // device only per master plan §3 W12.E. Lightweight migration on
            // first launch (net-new entities; SwiftData handles automatically).
            let transcriptSchema = Schema([
                Transcription.self,
                ScratchpadDocument.self,
                ScratchpadVersion.self
            ])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                url: defaultStoreURL,
                cloudKitDatabase: .none
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self, Snippet.self])
            #if LOCAL_BUILD
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .none
            #else
            let dictionaryCloudKit: ModelConfiguration.CloudKitDatabase = .private("iCloud.com.prakashjoshipax.VoiceInk")
            #endif
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                url: dictionaryStoreURL,
                cloudKitDatabase: dictionaryCloudKit
            )

            // Initialize container
            return try ModelContainer(
                for: schema,
                configurations: transcriptConfig, dictionaryConfig
            )
        } catch {
            logger.error("❌ Failed to create persistent ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Transcript configuration
            // W12.E — Scratchpad entities join the in-memory fallback too so
            // the first-launch fallback path keeps the API surface intact.
            let transcriptSchema = Schema([
                Transcription.self,
                ScratchpadDocument.self,
                ScratchpadVersion.self
            ])
            let transcriptConfig = ModelConfiguration(
                "default",
                schema: transcriptSchema,
                isStoredInMemoryOnly: true
            )

            // Dictionary configuration
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self, Snippet.self])
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                isStoredInMemoryOnly: true
            )

            return try ModelContainer(for: schema, configurations: transcriptConfig, dictionaryConfig)
        } catch {
            logger.error("❌ Failed to create in-memory ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Stats Container Creation Helpers

    private static func createPersistentStatsContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.prakashjoshipax.VoiceInk", isDirectory: true)
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)

            let statsStoreURL = appSupportURL.appendingPathComponent("stats.store")
            let statsConfig = ModelConfiguration(
                "stats",
                schema: schema,
                url: statsStoreURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: statsConfig)
        } catch {
            logger.error("❌ Failed to create persistent stats ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private static func createInMemoryStatsContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            let statsConfig = ModelConfiguration(
                "stats",
                schema: schema,
                isStoredInMemoryOnly: true
            )
            return try ModelContainer(for: schema, configurations: statsConfig)
        } catch {
            logger.error("❌ Failed to create in-memory stats ModelContainer: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .environmentObject(whisperModelManager)
                .environmentObject(fluidAudioModelManager)
                .environmentObject(transcriptionModelManager)
                .environmentObject(recorderUIManager)
                .environmentObject(hotkeyManager)
                .environmentObject(updaterViewModel)
                .environmentObject(menuBarManager)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
                .environmentObject(failureRegistry)
                .environmentObject(CommandModeService.shared)
                .modelContainer(container)
                .onAppear {
                        // Check if container initialization failed
                        if containerInitializationFailed {
                            let alert = NSAlert()
                            alert.messageText = "Critical Storage Error"
                            alert.informativeText = "VoiceInk cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: "Quit")
                            alert.runModal()

                            NSApplication.shared.terminate(nil)
                            return
                        }

                        updaterViewModel.silentlyCheckForUpdates()
                        if enableAnnouncements {
                            AnnouncementsService.shared.start()
                        }

                        // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                        if !UserDefaults.standard.bool(forKey: "IsTranscriptionCleanupEnabled") {
                            audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                        }

                        // Process any pending open-file request now that the main ContentView is ready.
                        if let pendingURL = appDelegate.pendingOpenFileURL {
                            NotificationCenter.default.post(name: .navigateToDestination, object: nil, userInfo: ["destination": "Transcribe Audio"])
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                NotificationCenter.default.post(name: .openFileForTranscription, object: nil, userInfo: ["url": pendingURL])
                            }
                            appDelegate.pendingOpenFileURL = nil
                        }
                    }
                    .background(WindowAccessor { window in
                        WindowManager.shared.configureWindow(window)
                    })
                    .onDisappear {
                        AnnouncementsService.shared.stop()
                        whisperModelManager.unloadModel()

                        // Stop the automatic audio cleanup process
                        audioCleanupManager.stopAutomaticCleanup()
                    }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 950, height: 730)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environmentObject(engine)
                .environmentObject(whisperModelManager)
                .environmentObject(fluidAudioModelManager)
                .environmentObject(transcriptionModelManager)
                .environmentObject(recorderUIManager)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .environmentObject(updaterViewModel)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
                .environmentObject(failureRegistry)
                .environmentObject(CommandModeService.shared)
        } label: {
            // SwiftUI `Image(nsImage:)` so MenuBarExtra renders a real glyph;
            // an `NSViewRepresentable` label rendered 0×0 here under
            // `.menuBarExtraStyle(.window)`. State-driven static swap via
            // `RecordingStateObserver` — see `MenuBarIcon`.
            MenuBarIcon(observer: appDelegate.recordingStateObserver)
        }
        // Native NSMenu-style dropdown — `MenuBarView` lays out flat
        // Button/Toggle/Menu/Divider items that SwiftUI projects onto
        // NSMenuItems. The earlier `.window` glass popover was deemed too
        // sparse (no recording action, no recents copy) — reverted per
        // user request.
        .menuBarExtraStyle(.menu)

        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Menu Bar Only") {
                menuBarManager.isMenuBarOnly.toggle()
            }
        }
        #endif
    }
}

class UpdaterViewModel: ObservableObject {
    @AppStorage("autoUpdateCheck") private var autoUpdateCheck = true

    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

        // Enable automatic update checking
        updaterController.updater.automaticallyChecksForUpdates = autoUpdateCheck
        updaterController.updater.updateCheckInterval = 24 * 60 * 60

        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func toggleAutoUpdates(_ value: Bool) {
        updaterController.updater.automaticallyChecksForUpdates = value
    }

    func checkForUpdates() {
        // This is for manual checks - will show UI
        updaterController.checkForUpdates(nil)
    }

    func silentlyCheckForUpdates() {
        // This checks for updates in the background without showing UI unless an update is found
        updaterController.updater.checkForUpdatesInBackground()
    }
}

struct CheckForUpdatesView: View {
    @ObservedObject var updaterViewModel: UpdaterViewModel

    var body: some View {
        Button("Check for Updates…", action: updaterViewModel.checkForUpdates)
            .disabled(!updaterViewModel.canCheckForUpdates)
    }
}

struct WindowAccessor: NSViewRepresentable {
    let callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                callback(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
