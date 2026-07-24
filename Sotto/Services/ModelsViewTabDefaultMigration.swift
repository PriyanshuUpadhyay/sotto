import Foundation
import OSLog

/// One-shot cleanup for the retired `ModelsViewSelectedTab` AppStorage key.
/// The W14F top-of-page segmented control that persisted it was removed in
/// m05/f02, so a pre-existing value is read (returned to the caller so it is
/// not silently dropped) and then removed from defaults rather than left
/// orphaned. Idempotent: once the key is absent, `run` observes nothing and
/// makes no writes. `defaults` is injected so it can be exercised against a
/// named suite instead of `.standard`.
enum ModelsViewTabDefaultMigration {

    static let legacyKey = "ModelsViewSelectedTab"

    private static let logger = Logger(subsystem: OSLogSubsystems.app, category: "ModelsViewTabMigration")

    @discardableResult
    static func run(defaults: UserDefaults = .standard) -> String? {
        guard let legacyValue = defaults.object(forKey: legacyKey) as? String else {
            return nil
        }
        defaults.removeObject(forKey: legacyKey)
        logger.info("Removed orphaned ModelsViewSelectedTab default.")
        return legacyValue
    }
}
