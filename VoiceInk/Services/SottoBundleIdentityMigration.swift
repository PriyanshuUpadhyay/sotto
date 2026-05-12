import Foundation
import OSLog

/// One-shot migration that lifts user data from the legacy
/// `com.prakashjoshipax.VoiceInk` bundle namespace into the renamed
/// `com.sotto.Sotto` namespace. Sentinel-guarded and idempotent across
/// crash/relaunch: each sub-step writes its sentinel ONLY after a
/// successful copy, so a mid-copy failure leaves the sentinel unset and
/// the next launch retries (codex 5.4). Spec §7.1.UserDefaults /
/// §7.1.SwiftData / §7.1.Keychain.
///
/// Modelled on `StreamingKeysMigration.run()` (sentinel pattern + UserDefaults
/// scope). Kept as a separate type so the whole module can be retired in a
/// future release once the legacy transition window has elapsed.
enum SottoBundleIdentityMigration {

    // MARK: - Constants

    static let legacyBundleID = "com.prakashjoshipax.VoiceInk"
    static let legacyAppSupportDirName = "com.prakashjoshipax.VoiceInk"
    static let newAppSupportDirName = "com.sotto.Sotto"

    /// UserDefaults sentinel — set only after a successful copy.
    static let userDefaultsSentinel = "__sotto_identity_migrated_v1"

    /// Keychain sentinel — distinct sentinel so partial keychain failures
    /// can re-run without re-copying UserDefaults.
    static let keychainSentinel = "__sotto_keychain_migrated_v1"

    static let legacyKeychainService = "com.prakashjoshipax.VoiceInk"
    static let newKeychainService = "com.sotto.Sotto"

    private static let logger = Logger(subsystem: OSLogSubsystems.app, category: "BundleIdentityMigration")

    // MARK: - Entry point

    /// Top-level entry — runs all three sub-migrations sequentially.
    /// Safe to call on every launch; each sub-step is sentinel-gated.
    static func run() {
        runUserDefaultsCopy()
        runAppSupportDirectoryMove()
        runKeychainGroupCopy()
    }

    // MARK: - UserDefaults (§7.1.UserDefaults)

    /// Lifts every key from the legacy bundle's UserDefaults suite into
    /// `defaults`, skipping keys the new namespace has already set (so
    /// `AppDefaults.registerDefaults()` wins for fresh installs).
    ///
    /// The `setter` parameter is dependency-injected so tests can simulate
    /// partial failure. The sentinel is set strictly AFTER the loop completes
    /// without throwing — if the setter throws partway, the sentinel stays
    /// unset and the next launch retries (codex 5.4).
    static func runUserDefaultsCopy(
        defaults: UserDefaults = .standard,
        legacy: UserDefaults? = UserDefaults(suiteName: legacyBundleID),
        setter: (UserDefaults, String, Any) throws -> Void = { d, k, v in d.set(v, forKey: k) }
    ) {
        guard !defaults.bool(forKey: userDefaultsSentinel) else { return }
        guard let legacy = legacy else {
            // No legacy suite reachable (fresh install). Mark migrated so we
            // don't re-probe every launch.
            defaults.set(true, forKey: userDefaultsSentinel)
            return
        }

        let snapshot = legacy.dictionaryRepresentation()
        do {
            for (key, value) in snapshot {
                guard defaults.object(forKey: key) == nil else { continue }
                try setter(defaults, key, value)
            }
            defaults.set(true, forKey: userDefaultsSentinel)
            logger.info("UserDefaults copy: \(snapshot.count, privacy: .public) keys probed from legacy suite; sentinel set.")
        } catch {
            // Sentinel intentionally left unset — next launch retries from
            // scratch. The keys we did copy survive (idempotent on re-run
            // because the `defaults.object(forKey:) == nil` guard skips them).
            logger.error("UserDefaults copy aborted: \(error.localizedDescription, privacy: .public); sentinel left unset for retry.")
        }
    }

    // MARK: - SwiftData app-support directory (§7.1.SwiftData)

    /// Relocates the legacy `~/Library/Application Support/com.prakashjoshipax.VoiceInk`
    /// directory to `com.sotto.Sotto`. Uses `moveItem(at:to:)`, which is an
    /// atomic rename(2) on the same volume — there's no partial-state window
    /// for an interrupted move. If the new directory already exists, we
    /// preserve both: operator decides whether to remove legacy remnants.
    /// Retrying after partial state (both dirs present) is a no-op (codex 5.4).
    static func runAppSupportDirectoryMove(
        fileManager: FileManager = .default,
        appSupportRoot: URL? = nil
    ) {
        let fm = fileManager
        let root = appSupportRoot ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyURL = root.appendingPathComponent(legacyAppSupportDirName, isDirectory: true)
        let newURL = root.appendingPathComponent(newAppSupportDirName, isDirectory: true)

        // Order matters: check new-exists first to make the retry-after-
        // interrupted-move path a safe no-op (both dirs present).
        guard !fm.fileExists(atPath: newURL.path) else {
            logger.notice("AppSupport move skipped: \(newURL.lastPathComponent, privacy: .public) already exists; legacy left for operator inspection.")
            return
        }
        guard fm.fileExists(atPath: legacyURL.path) else {
            logger.debug("AppSupport move skipped: no legacy directory at \(legacyURL.path, privacy: .public).")
            return
        }

        do {
            try fm.moveItem(at: legacyURL, to: newURL)
            logger.info("AppSupport move: \(legacyURL.lastPathComponent, privacy: .public) → \(newURL.lastPathComponent, privacy: .public)")
        } catch {
            logger.error("AppSupport move failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Keychain (§7.1.Keychain)

    /// Enumerates legacy generic-password items and re-adds them under the
    /// new service. The dual-list entitlement (legacy + new keychain access
    /// groups) must already be in place so the signed binary owns both during
    /// the transition window. Retrying after partial failure is safe because
    /// each add does a SecItemDelete on the new-service entry first; the
    /// sentinel is set only after the loop completes (codex 5.4).
    static func runKeychainGroupCopy(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: keychainSentinel) else { return }

        #if LOCAL_BUILD
        // Local builds use UserDefaults-backed pseudo-keychain (see
        // KeychainService LOCAL_BUILD path). Nothing to migrate; just mark.
        defaults.set(true, forKey: keychainSentinel)
        return
        #else
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let items = result as? [[String: Any]] else {
            // No legacy items (or keychain unreachable) — mark migrated.
            logger.info("Keychain copy: no legacy items found (status=\(status, privacy: .public)).")
            defaults.set(true, forKey: keychainSentinel)
            return
        }

        var copied = 0
        var anyFailure = false
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String,
                  let data = item[kSecValueData as String] as? Data else { continue }
            let synchronizable = (item[kSecAttrSynchronizable as String] as? Bool) ?? false

            var addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: newKeychainService,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
                kSecUseDataProtectionKeychain as String: true,
            ]
            if synchronizable { addQuery[kSecAttrSynchronizable as String] = kCFBooleanTrue }

            // Pre-delete to keep the per-item operation idempotent on retry.
            SecItemDelete(addQuery as CFDictionary)
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            if addStatus == errSecSuccess {
                copied += 1
            } else {
                anyFailure = true
                logger.error("Keychain copy: SecItemAdd failed for account \(account, privacy: .public), status=\(addStatus, privacy: .public)")
            }
        }

        if anyFailure {
            // Sentinel left unset — next launch retries. Pre-delete + re-add
            // keeps the partial state safe for retry.
            logger.error("Keychain copy partial: \(copied, privacy: .public)/\(items.count, privacy: .public) succeeded; sentinel left unset for retry.")
        } else {
            defaults.set(true, forKey: keychainSentinel)
            logger.info("Keychain copy: \(copied, privacy: .public) items copied to \(newKeychainService, privacy: .public).")
        }
        #endif
    }
}
