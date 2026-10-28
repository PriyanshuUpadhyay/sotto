import SwiftUI
import SwiftData
import Sparkle
import AppKit
import OSLog
import Combine
import FluidAudio

@main
struct SottoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    let container: ModelContainer
    let containerInitializationFailed: Bool
    // Stats are persisted in a SEPARATE local-only ModelContainer (stats.store)
    // so SessionMetric records survive transcript cleanup and never round-trip
    // through CloudKit (cloudKitDatabase: .none). Existing transcripts container
    // is unchanged.
    let statsContainer: ModelContainer

    @StateObject private var engine: SottoEngine
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
    @StateObject private var appearance = AppearanceStore.shared
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

        ModelsViewTabDefaultMigration.run()

        let logger = Logger(subsystem: OSLogSubsystems.app, category: "Initialization")
        let schema = Schema([
            Transcription.self,
            VocabularyWord.self,
            WordReplacement.self,
            Snippet.self,
            ScratchpadDocument.self,
            ScratchpadVersion.self,
            EnhancementEditRecord.self
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
                alert.informativeText = "Sotto couldn't access its storage location. Your transcriptions will not be saved between sessions."
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

        // Expose the stats container to call sites that can't take it via
        // injection — the transcription pipeline (writes) + History/Metrics
        // views (reads). SessionMetric lives only in this store.
        StatsModelContainerProvider.shared.modelContainer = statsContainer

        // Initialize services with proper sharing of instances
        let aiService = AIService()
        _aiService = StateObject(wrappedValue: aiService)

        let updaterViewModel = UpdaterViewModel()
        _updaterViewModel = StateObject(wrappedValue: updaterViewModel)

        let enhancementService = AIEnhancementService(aiService: aiService, modelContext: container.mainContext)
        _enhancementService = StateObject(wrappedValue: enhancementService)

        // 1. Create modelsDirectory URL
        let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppSupport.directoryName)
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
        let engine = SottoEngine(
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

        let prewarmService = ModelPrewarmService(
            transcriptionModelManager: transcriptionModelManager,
            whisperModelManager: whisperModelManager,
            modelContext: container.mainContext,
            engine: engine,
            enhancementService: enhancementService
        )
        _prewarmService = StateObject(wrappedValue: prewarmService)

        appDelegate.menuBarManager = menuBarManager

        // Bind menu bar icon to engine state. Spec §3.11 / plan §P2.C —
        // animated icon reflects idle / recording / transcribing / enhancing
        // via Combine on `engine.$recordingState`.
        appDelegate.recordingStateObserver.bind(to: engine)
        appDelegate.recordingStateObserver.bind(toRegistry: failureRegistry)

        // P3.F: warm up the AVAudioEngine that powers synthesized cues. Starts
        // the audio graph + schedules a silent pre-roll so the first user cue
        // (recording start) plays without ~50–100ms first-fire latency.
        SoundManager.shared.warmUp()

        // Ensure no lingering recording state from previous runs
        Task {
            await recorderUIManager.resetOnLaunch()
        }

        // Kick off the SessionMetric back-fill BEFORE the transcript cleanup
        // service can prune historical recorder rows. The migration is
        // idempotent (UserDefaults sentinel + ID-set skip) and runs off the
        // main actor — launch is never blocked. Cleanup is chained onto the
        // migration's `Task.value` so post-migration deletions don't race
        // ahead of the back-fill. `mainContext` is captured locally to avoid
        // the escaping-`self` warning when the Task reads `container` from
        // the in-flight `init` (upstream e6236e3).
        let migrationTask = SessionMetricMigrationService.shared.runIfNeeded(
            transcriptContainer: container,
            statsContainer: statsContainer
        )
        let mainContext = container.mainContext
        Task {
            await migrationTask?.value
            TranscriptionAutoCleanupService.shared.startMonitoring(modelContext: mainContext)
        }

        // Seed default vocabulary ("Sotto") so the enhancement context can
        // correct ASR mis-hearings. Idempotent — no-op if already present.
        CustomVocabularyService.shared.seedDefaultVocabularyIfNeeded(context: mainContext)
    }

    var body: some Scene {
        WindowGroup(id: SottoWindowCoordinator.windowID) {
            SottoWindowView()
                .environmentObject(engine)
                .environmentObject(whisperModelManager)
                .environmentObject(fluidAudioModelManager)
                .environmentObject(transcriptionModelManager)
                .environmentObject(recorderUIManager)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
                .environmentObject(failureRegistry)
                .modelContainer(container)
                .onAppear {
                        // Headless test guard: skip launch-time UI/services —
                        // notably the container-error `runModal()` below, which
                        // would otherwise block the XCTest host indefinitely.
                        if AppRuntimeMode.isHeadlessTest { return }

                        // Check if container initialization failed
                        if containerInitializationFailed {
                            let alert = NSAlert()
                            alert.messageText = "Critical Storage Error"
                            alert.informativeText = "Sotto cannot initialize its storage system. The app cannot continue.\n\nPlease try reinstalling the app or contact support if the issue persists."
                            alert.alertStyle = .critical
                            alert.addButton(withTitle: "Quit")
                            alert.runModal()

                            NSApplication.shared.terminate(nil)
                            return
                        }

                        updaterViewModel.silentlyCheckForUpdates()

                        // Start the automatic audio cleanup process only if transcript cleanup is not enabled
                        if !UserDefaults.standard.bool(forKey: "IsTranscriptionCleanupEnabled") {
                            audioCleanupManager.startAutomaticCleanup(modelContext: container.mainContext)
                        }
                    }
                    .background(WindowAccessor { window in
                        WindowManager.shared.configureWindow(window)
                    })
                    .onDisappear {
                        whisperModelManager.unloadModel()

                        // Stop the automatic audio cleanup process
                        audioCleanupManager.stopAutomaticCleanup()
                    }
                    .onAppear {
                        if !AppRuntimeMode.isHeadlessTest, !OnboardingState.shared.completed {
                            OnboardingWindowController.shared.present()
                        }
                    }
                    .tint(Brand.tint)
                    .preferredColorScheme(appearance.choice.colorScheme)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 950, height: 730)
        .windowResizability(.contentSize)
        // The Sotto window is on-demand only: it must NOT auto-present at launch.
        // Sotto runs menu-bar-primary; the window opens via `openWindow(id:)` from
        // the menu bar ("Open Sotto…") or History routing.
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updaterViewModel: updaterViewModel)
            }
        }

        Settings {
            SettingsWindow()
                .environmentObject(engine)
                .environmentObject(whisperModelManager)
                .environmentObject(fluidAudioModelManager)
                .environmentObject(transcriptionModelManager)
                .environmentObject(recorderUIManager)
                .environmentObject(hotkeyManager)
                .environmentObject(menuBarManager)
                .environmentObject(aiService)
                .environmentObject(enhancementService)
                .environmentObject(failureRegistry)
                .modelContainer(container)
                .tint(Brand.tint)
                .preferredColorScheme(appearance.choice.colorScheme)
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            SottoMenuBarContent()
                .environmentObject(engine)
                .environmentObject(transcriptionModelManager)
                .environmentObject(menuBarManager)
                .environmentObject(enhancementService)
                .environmentObject(updaterViewModel)
                .modelContainer(container)
        } label: {
            // SwiftUI `Image(nsImage:)` so MenuBarExtra renders a real glyph;
            // an `NSViewRepresentable` label rendered 0×0 here under
            // `.menuBarExtraStyle(.window)`. State-driven static swap via
            // `RecordingStateObserver` — see `MenuBarIcon`.
            //
            // The menu-bar label is the one view that is always instantiated
            // (the menu content is only built when the menu opens), so it is the
            // host that captures `openWindow` for non-view callers (History
            // hotkey, MenuBarManager) via SottoWindowCoordinator.
            SottoMenuBarLabel(observer: appDelegate.recordingStateObserver)
        }
        // Native NSMenu-style dropdown — `SottoMenuBarContent` lays out flat
        // Button/Menu/Divider items that SwiftUI projects onto NSMenuItems.
        // The earlier `.window` glass popover was deemed too sparse (no
        // recording action, no recents copy) — reverted per user request.
        .menuBarExtraStyle(.menu)

        #if DEBUG
        WindowGroup("Debug") {
            Button("Toggle Menu Bar Only") {
                menuBarManager.isMenuBarOnly.toggle()
            }
            .preferredColorScheme(appearance.choice.colorScheme)
        }
        #endif
    }
}
