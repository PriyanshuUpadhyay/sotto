import Testing
import Foundation
@testable import Sotto

// m05/f02 — the W14F `ModelsViewSelectedTab` segmented-control AppStorage key
// and the "ACTIVE PROVIDER" / "Other providers" accordion are removed. A
// pre-existing persisted value must be migrated (read + handled), not silently
// orphaned in defaults. Tests run against a named suite — never `.standard`.
@Suite(.serialized)
struct ModelsAppStorageMigrationTests {

    private func freshSuite() -> (defaults: UserDefaults, suite: String) {
        let suite = "models-tab-migration-test-\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func tearDown(_ ud: UserDefaults, suite: String) {
        ud.removePersistentDomain(forName: suite)
    }

    // Positive anchor: a pre-existing value is migrated (observable to the
    // migration) AND removed from defaults — not silently discarded.
    @Test func test_run_reads_and_removes_seeded_legacy_value() {
        let (defaults, suite) = freshSuite()
        defer { tearDown(defaults, suite: suite) }

        defaults.set("Transcriber", forKey: ModelsViewTabDefaultMigration.legacyKey)

        let migrated = ModelsViewTabDefaultMigration.run(defaults: defaults)

        #expect(migrated == "Transcriber")
        #expect(defaults.object(forKey: ModelsViewTabDefaultMigration.legacyKey) == nil)
    }

    // Idempotent: absent key → no-op, no value observed, key stays absent
    // across repeated runs.
    @Test func test_run_is_idempotent_when_key_absent() {
        let (defaults, suite) = freshSuite()
        defer { tearDown(defaults, suite: suite) }

        #expect(ModelsViewTabDefaultMigration.run(defaults: defaults) == nil)
        #expect(ModelsViewTabDefaultMigration.run(defaults: defaults) == nil)
        #expect(defaults.object(forKey: ModelsViewTabDefaultMigration.legacyKey) == nil)
    }

    // After migration the key is gone, so a second run observes nothing —
    // confirms the read+remove is a one-shot, not a repeat-migrating loop.
    @Test func test_run_after_migration_observes_nothing() {
        let (defaults, suite) = freshSuite()
        defer { tearDown(defaults, suite: suite) }

        defaults.set("Enhancement", forKey: ModelsViewTabDefaultMigration.legacyKey)

        #expect(ModelsViewTabDefaultMigration.run(defaults: defaults) == "Enhancement")
        #expect(ModelsViewTabDefaultMigration.run(defaults: defaults) == nil)
    }
}
