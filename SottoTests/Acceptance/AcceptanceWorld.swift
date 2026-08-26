import Foundation
@testable import Sotto

/// Mutable state carried across the steps of one scenario. Each generated test
/// method gets a fresh world, so scenarios cannot leak into one another.
@MainActor
final class AcceptanceWorld {
    let manifest: AcceptanceManifest

    /// An isolated defaults domain, so a scenario that flips a hidden
    /// preference never touches the developer's real settings.
    let defaults: UserDefaults
    private let suiteName: String

    // Settings composition
    var settingsTab: String?

    // Filler words
    var fillerRemovalEnabled = false
    var fillerWords: [String] = FillerWordManager.defaultFillerWords
    var spokenTranscript: String?
    var deliveredTranscript: String?

    // Platform
    var documentedMinimumMacOS: String?
    var hostVersion: OperatingSystemVersion?
    var launchOutcome: PlatformSupport.LaunchOutcome?
    var focusedControl: String?
    var systemAppearance: String?
    var appearancePreference: String?
    var renderedAppearance: String?

    // Enhancement
    var enhancementProvider: AIProvider?
    var instructionPrompt: String?
    var enhancementInput: String?

    init(manifest: AcceptanceManifest) {
        self.manifest = manifest
        self.suiteName = "SottoAcceptance.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName)!
    }

    func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }
}
