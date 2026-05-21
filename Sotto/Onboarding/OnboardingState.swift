import Foundation
import Combine

@MainActor
final class OnboardingState: ObservableObject {
    static let shared = OnboardingState(defaults: .standard)

    enum Key {
        static let completed = "onboardingCompleted_v1"
        static let skipped = "onboardingSkipped_v1"
        static let skippedPermissions = "onboardingSkippedPermissions_v1"
        static let hotkeyReminderShown = "hotkeyReminderShown_v1"
        static let firstInvocationDidFire = "firstInvocationDidFire_v1"
    }

    private let defaults: UserDefaults

    @Published private(set) var completed: Bool
    @Published private(set) var skipped: Bool
    @Published private(set) var skippedPermissions: Bool
    @Published private(set) var hotkeyReminderShown: Bool
    @Published private(set) var firstInvocationDidFire: Bool

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.completed = defaults.bool(forKey: Key.completed)
        self.skipped = defaults.bool(forKey: Key.skipped)
        self.skippedPermissions = defaults.bool(forKey: Key.skippedPermissions)
        self.hotkeyReminderShown = defaults.bool(forKey: Key.hotkeyReminderShown)
        self.firstInvocationDidFire = defaults.bool(forKey: Key.firstInvocationDidFire)
    }

    func markCompleted() {
        defaults.set(true, forKey: Key.completed)
        completed = true
    }

    func markSkipped() {
        defaults.set(true, forKey: Key.skipped)
        defaults.set(true, forKey: Key.completed)
        skipped = true
        completed = true
    }

    func markSkippedPermissions() {
        defaults.set(true, forKey: Key.skippedPermissions)
        skippedPermissions = true
    }

    func markHotkeyReminderShown() {
        defaults.set(true, forKey: Key.hotkeyReminderShown)
        hotkeyReminderShown = true
    }

    func markFirstInvocation() {
        guard !firstInvocationDidFire else { return }
        defaults.set(true, forKey: Key.firstInvocationDidFire)
        firstInvocationDidFire = true
    }
}
