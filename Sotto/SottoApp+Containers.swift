import SwiftData
import OSLog

extension SottoApp {
    // MARK: - Container Creation Helpers

    static func createPersistentContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            // Create app-specific Application Support directory URL
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(AppSupport.directoryName, isDirectory: true)

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

            // Dictionary configuration. Local-only — CloudKit mirroring is
            // disabled (no iCloud container is configured for this app).
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self, Snippet.self, EnhancementEditRecord.self])
            let dictionaryConfig = ModelConfiguration(
                "dictionary",
                schema: dictionarySchema,
                url: dictionaryStoreURL,
                cloudKitDatabase: .none
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

    static func createInMemoryContainer(schema: Schema, logger: Logger) -> ModelContainer? {
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
            let dictionarySchema = Schema([VocabularyWord.self, WordReplacement.self, Snippet.self, EnhancementEditRecord.self])
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

    static func createPersistentStatsContainer(schema: Schema, logger: Logger) -> ModelContainer? {
        do {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
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

    static func createInMemoryStatsContainer(schema: Schema, logger: Logger) -> ModelContainer? {
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
}
