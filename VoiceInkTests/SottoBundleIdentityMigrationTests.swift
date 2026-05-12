import Testing
import Foundation
@testable import VoiceInk

// Migration must be sentinel-gated AND interrupted-safe. Tests cover:
// - Happy-path: legacy → new copy + sentinel set.
// - Idempotency: sentinel-set leaves second run as no-op.
// - Codex 5.4: failure mid-copy leaves sentinel UNSET so next launch retries.
//   Same property required for keychain dual-list parsing and the app-support
//   directory rename — partial state must be detectable + safely re-runnable
//   (i.e. interrupted-safe).
@Suite(.serialized)
struct SottoBundleIdentityMigrationTests {

    // MARK: - Shared fixtures

    private static let testLegacySuite = "com.prakashjoshipax.VoiceInk.test-fixture"

    private func freshDefaultsPair() -> (defaults: UserDefaults, legacy: UserDefaults, defaultsSuite: String, legacySuite: String) {
        let defaultsSuite = "sotto-migration-test-\(UUID().uuidString)"
        let legacySuite = "legacy-fixture-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        let legacy = UserDefaults(suiteName: legacySuite)!
        return (defaults, legacy, defaultsSuite, legacySuite)
    }

    private func tearDown(_ ud: UserDefaults, suite: String) {
        ud.removePersistentDomain(forName: suite)
    }

    private func makeTempAppSupportRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sotto-migration-tests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - UserDefaults sub-shim

    @Test func test_userDefaults_copy_copies_legacy_to_standard_then_sets_sentinel() {
        let (defaults, legacy, defaultsSuite, legacySuite) = freshDefaultsPair()
        defer { tearDown(defaults, suite: defaultsSuite); tearDown(legacy, suite: legacySuite) }

        legacy.set("legacy_value", forKey: "TestKey_A")

        SottoBundleIdentityMigration.runUserDefaultsCopy(defaults: defaults, legacy: legacy)

        #expect(defaults.string(forKey: "TestKey_A") == "legacy_value")
        #expect(defaults.bool(forKey: SottoBundleIdentityMigration.userDefaultsSentinel))
    }

    @Test func test_userDefaults_copy_is_no_op_when_sentinel_set() {
        let (defaults, legacy, defaultsSuite, legacySuite) = freshDefaultsPair()
        defer { tearDown(defaults, suite: defaultsSuite); tearDown(legacy, suite: legacySuite) }

        defaults.set(true, forKey: SottoBundleIdentityMigration.userDefaultsSentinel)
        legacy.set("should_not_copy", forKey: "TestKey_B")

        SottoBundleIdentityMigration.runUserDefaultsCopy(defaults: defaults, legacy: legacy)

        #expect(defaults.object(forKey: "TestKey_B") == nil)
    }

    @Test func test_userDefaults_copy_failure_leaves_sentinel_unset() {
        // Codex 5.4: a setter that throws mid-loop must NOT mark the sentinel,
        // so the next launch retries. Verifies the sentinel is set AFTER (not
        // before) the copy completes.
        let (defaults, legacy, defaultsSuite, legacySuite) = freshDefaultsPair()
        defer { tearDown(defaults, suite: defaultsSuite); tearDown(legacy, suite: legacySuite) }

        legacy.set("v1", forKey: "K1")
        legacy.set("v2", forKey: "K2")
        legacy.set("v3", forKey: "K3")

        var writes = 0
        SottoBundleIdentityMigration.runUserDefaultsCopy(
            defaults: defaults,
            legacy: legacy,
            setter: { d, k, v in
                writes += 1
                if writes >= 2 {
                    throw NSError(domain: "SottoMigrationTest", code: -1)
                }
                d.set(v, forKey: k)
            }
        )

        #expect(!defaults.bool(forKey: SottoBundleIdentityMigration.userDefaultsSentinel),
                "sentinel must remain unset so next launch retries")
        #expect(writes >= 2, "setter should have been invoked at least twice before aborting")
    }

    // MARK: - SwiftData / app-support directory move

    @Test func test_appSupport_move_relocates_legacy_directory() throws {
        let root = try makeTempAppSupportRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let legacyURL = root.appendingPathComponent(SottoBundleIdentityMigration.legacyAppSupportDirName)
        let newURL = root.appendingPathComponent(SottoBundleIdentityMigration.newAppSupportDirName)
        try fm.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try "marker".write(to: legacyURL.appendingPathComponent("smoke.txt"), atomically: true, encoding: .utf8)

        SottoBundleIdentityMigration.runAppSupportDirectoryMove(appSupportRoot: root)

        #expect(!fm.fileExists(atPath: legacyURL.path))
        #expect(fm.fileExists(atPath: newURL.appendingPathComponent("smoke.txt").path))
    }

    @Test func test_appSupport_move_skips_when_new_already_exists() throws {
        let root = try makeTempAppSupportRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let legacyURL = root.appendingPathComponent(SottoBundleIdentityMigration.legacyAppSupportDirName)
        let newURL = root.appendingPathComponent(SottoBundleIdentityMigration.newAppSupportDirName)
        try fm.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: newURL, withIntermediateDirectories: true)

        SottoBundleIdentityMigration.runAppSupportDirectoryMove(appSupportRoot: root)

        // Both preserved: caller decides what to do with legacy remnants.
        #expect(fm.fileExists(atPath: legacyURL.path))
        #expect(fm.fileExists(atPath: newURL.path))
    }

    @Test func test_appSupport_move_interrupted_safe_to_retry() throws {
        // Codex 5.4: previous-run interrupted state — both legacy AND new dirs
        // present (move-then-delete pattern crashed between rename and cleanup,
        // OR operator restored legacy from backup). Re-running the move must
        // NOT clobber existing data in new, and must not crash. Calling twice
        // models a multi-launch retry; legacy stays put for operator inspection.
        let root = try makeTempAppSupportRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fm = FileManager.default
        let legacyURL = root.appendingPathComponent(SottoBundleIdentityMigration.legacyAppSupportDirName)
        let newURL = root.appendingPathComponent(SottoBundleIdentityMigration.newAppSupportDirName)
        try fm.createDirectory(at: legacyURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: newURL, withIntermediateDirectories: true)
        try "legacy-data".write(to: legacyURL.appendingPathComponent("legacy.txt"), atomically: true, encoding: .utf8)
        try "new-data".write(to: newURL.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)

        SottoBundleIdentityMigration.runAppSupportDirectoryMove(appSupportRoot: root)
        SottoBundleIdentityMigration.runAppSupportDirectoryMove(appSupportRoot: root)

        #expect(fm.fileExists(atPath: legacyURL.path), "legacy preserved across retries")
        #expect(fm.fileExists(atPath: newURL.path))
        let newPayload = try String(contentsOf: newURL.appendingPathComponent("new.txt"))
        #expect(newPayload == "new-data", "new dir data unchanged across retries")
        let legacyPayload = try String(contentsOf: legacyURL.appendingPathComponent("legacy.txt"))
        #expect(legacyPayload == "legacy-data")
    }

    // MARK: - Keychain

    @Test func test_keychain_copy_sets_sentinel_after_run() {
        let (defaults, _, defaultsSuite, _) = freshDefaultsPair()
        defer { tearDown(defaults, suite: defaultsSuite) }

        SottoBundleIdentityMigration.runKeychainGroupCopy(defaults: defaults)

        #expect(defaults.bool(forKey: SottoBundleIdentityMigration.keychainSentinel))
    }

    @Test func test_keychain_dual_list_partial_failure_safe_to_retry() throws {
        // Codex 5.4: signed-binary entitlement parsing must tolerate either
        // ordering of the keychain-access-groups array. Asserts both legacy
        // and new identifiers are present in VoiceInk.entitlements as a Set
        // (order-insensitive). A partial-failure rollback that drops one
        // group would lose access to in-flight keys on the next launch.
        let entitlementsURL = Self.entitlementsFileURL()
        let data = try Data(contentsOf: entitlementsURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        let groups = (plist?["keychain-access-groups"] as? [String]) ?? []

        let suffixes = Set(groups.map { String($0.split(separator: ")").last ?? Substring($0)) })
        #expect(suffixes.contains("com.sotto.Sotto"), "new bundle ID missing from keychain-access-groups (have \(suffixes))")
        #expect(suffixes.contains("com.prakashjoshipax.VoiceInk"), "legacy bundle ID missing from keychain-access-groups (have \(suffixes))")

        // Idempotency invariant: re-running the copy with an already-set sentinel
        // is a no-op (no SecItem* side effects). Models the retry-after-partial-
        // failure path where some items already migrated.
        let (defaults, _, defaultsSuite, _) = freshDefaultsPair()
        defer { tearDown(defaults, suite: defaultsSuite) }

        defaults.set(true, forKey: SottoBundleIdentityMigration.keychainSentinel)
        SottoBundleIdentityMigration.runKeychainGroupCopy(defaults: defaults)
        #expect(defaults.bool(forKey: SottoBundleIdentityMigration.keychainSentinel))
    }

    // MARK: - Helpers

    /// Derives the entitlements file URL from `#filePath` so the test reads the
    /// real source-tree file regardless of where DerivedData ends up.
    /// VoiceInkTests/SottoBundleIdentityMigrationTests.swift sits one dir
    /// below the worktree root, so the entitlements file resolves to
    /// `<worktree>/VoiceInk/VoiceInk.entitlements`.
    private static func entitlementsFileURL(callerFile: String = #filePath) -> URL {
        let testFile = URL(fileURLWithPath: callerFile)
        return testFile
            .deletingLastPathComponent()  // VoiceInkTests/
            .deletingLastPathComponent()  // worktree root
            .appendingPathComponent("VoiceInk/VoiceInk.entitlements")
    }
}
