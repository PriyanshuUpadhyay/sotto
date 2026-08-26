import Foundation
import SwiftUI
@testable import Sotto

enum StepError: Error, CustomStringConvertible {
    case failed(String)
    case skipped(String)
    case undefined(String)

    var description: String {
        switch self {
        case .failed(let why):    return why
        case .skipped(let why):   return "skipped: \(why)"
        case .undefined(let text): return "no step handler matches: \(text)"
        }
    }
}

/// Unwraps something an earlier step was supposed to produce. Its absence is a
/// defect in the scenario's step order, so it fails.
private func required<T>(_ value: T?, orFail why: String) throws -> T {
    guard let value else { throw StepError.failed(why) }
    return value
}

/// Unwraps a manifest fact the probes may not have been able to gather. Its
/// absence is missing evidence, so it skips rather than passing.
private func required<T>(_ value: T?, orSkip why: String) throws -> T {
    guard let value else { throw StepError.skipped(why) }
    return value
}

/// Fails the scenario with `why` unless the asserted condition holds.
private func expect(_ condition: Bool, orFail why: String) throws {
    guard condition else { throw StepError.failed(why) }
}

/// Project step handlers.
///
/// Parameter extraction is regex based: one handler covers every step that
/// varies only by example value, and a literal handler exists only where the
/// wording marks genuinely different behavior.
@MainActor
enum AcceptanceSteps {

    typealias Handler = (_ args: [String], _ world: AcceptanceWorld) throws -> Void

    static let registry: [(pattern: String, handler: Handler)] = [

        // MARK: Ambient context
        //
        // Preconditions that describe the environment the whole feature runs
        // in. They carry no assertion of their own; the steps that follow read
        // the manifest that recorded that environment.
        ("^(?:a release build of Sotto(?: on Apple Silicon)?|the app is (?:not )?running|VoiceOver is running|no recording is active|no transcription model download is in progress)$",
         { _, _ in }),

        // MARK: Settings composition

        ("^I open the (.+) settings tab$", { args, world in
            world.settingsTab = args[0]
        }),

        ("^the tab shows the control (.+)$", { args, world in
            let tab = try required(world.settingsTab, orFail: "no settings tab was opened")
            try expect(try tabShowsControl(tab: tab, control: args[0]),
                       orFail: "the \(tab) tab does not show \(args[0])")
        }),

        // MARK: Filler words

        ("^filler word removal is turned (on|off)$", { args, world in
            world.fillerRemovalEnabled = (args[0] == "on")
        }),

        ("^the dictated audio contains the word (.+)$", { args, world in
            world.spokenTranscript = "so \(args[0]) this is the plan"
        }),

        ("^I remove (.+) from the filler word list$", { args, world in
            world.fillerWords.removeAll { $0.caseInsensitiveCompare(args[0]) == .orderedSame }
        }),

        ("^the transcript is delivered$", { _, world in
            let spoken = try required(world.spokenTranscript, orFail: "no dictated audio was set up")
            world.deliveredTranscript = TranscriptionOutputFilter.removingFillerWords(
                spoken,
                enabled: world.fillerRemovalEnabled,
                fillerWords: world.fillerWords
            )
        }),

        ("^the transcript (omits|keeps) the word (.+)$", { args, world in
            let delivered = try required(world.deliveredTranscript, orFail: "no transcript was delivered")
            let present = delivered.range(of: "\\b\(NSRegularExpression.escapedPattern(for: args[1]))\\b",
                                          options: [.regularExpression, .caseInsensitive]) != nil
            try expect(present == (args[0] == "keeps"),
                       orFail: "expected the transcript to \(args[0]) \"\(args[1])\"; got \"\(delivered)\"")
        }),

        // MARK: Documented platform

        ("^I read the documented minimum macOS version$", { _, world in
            let documented = world.manifest.documentedMinimumMacOS
            try expect(documented.count == 1,
                       orFail: "the docs must state exactly one minimum macOS version; found \(documented)")
            world.documentedMinimumMacOS = documented.first
        }),

        ("^it equals the build setting MACOSX_DEPLOYMENT_TARGET$", { _, world in
            let documented = try required(world.documentedMinimumMacOS, orFail: unreadDocumentedVersion)
            let target = try required(world.manifest.deploymentTarget,
                                      orSkip: "xcodebuild did not report MACOSX_DEPLOYMENT_TARGET")
            try expect(documented == target,
                       orFail: "docs say \(documented) but MACOSX_DEPLOYMENT_TARGET is \(target)")
        }),

        ("^it equals (.+)$", { args, world in
            let documented = try required(world.documentedMinimumMacOS, orFail: unreadDocumentedVersion)
            try expect(documented == args[0], orFail: "docs say \(documented), expected \(args[0])")
        }),

        // MARK: Launch gate

        ("^the host runs macOS (.+)$", { args, world in
            world.hostVersion = try parseVersion(args[0])
        }),

        // Shared by the platform gate (which states a host version) and the
        // launch budget (which does not, and so means this machine).
        ("^I launch the app$", { _, world in
            let host = world.hostVersion ?? ProcessInfo.processInfo.operatingSystemVersion
            world.launchOutcome = PlatformSupport.launchOutcome(hostVersion: host)
        }),

        ("^the launch result is (.+)$", { args, world in
            let actual = try required(world.launchOutcome, orFail: "the app was not launched")
            let expected = try launchOutcome(named: args[0])
            try expect(actual == expected, orFail: "expected \(args[0]); got \(actual)")
        }),

        // MARK: VoiceOver

        ("^I move VoiceOver focus to the control (.+)$", { args, world in
            world.focusedControl = args[0]
        }),

        ("^VoiceOver announces a non-empty label for that control$", { _, world in
            let control = try required(world.focusedControl, orFail: "no control was focused")
            let label = try required(
                voiceOverLabel(forControl: control),
                orFail: "\"\(control)\" is not a reachable control in this app, so VoiceOver has nothing to announce"
            )
            try expect(!label.isEmpty, orFail: "\"\(control)\" announces an empty label")
        }),

        // MARK: Appearance

        ("^the system appearance is (.+)$", { args, world in
            world.systemAppearance = args[0]
        }),

        ("^the app appearance preference is (.+)$", { args, world in
            world.appearancePreference = args[0]
        }),

        ("^I open the Sotto window$", { _, world in
            let system = try required(world.systemAppearance, orFail: missingAppearanceInputs)
            let preference = try required(world.appearancePreference, orFail: missingAppearanceInputs)
            let choice = try appearanceChoice(named: preference)
            world.renderedAppearance = choice.colorScheme.map { $0 == .dark ? "dark" : "light" } ?? system
        }),

        ("^the window renders in (.+)$", { args, world in
            let rendered = try required(world.renderedAppearance, orFail: "the window was not opened")
            try expect(rendered == args[0], orFail: "expected \(args[0]); rendered \(rendered)")
        }),

        // MARK: Build artifacts

        ("^the build completes$", { _, world in
            _ = try required(world.manifest.appBundlePath, orSkip: "no built app bundle to inspect")
        }),

        ("^no Swift source file declares the type (.+)$", { args, world in
            try expect(!world.manifest.declaredSwiftTypes.contains(args[0]),
                       orFail: "\(args[0]) is still declared in the Swift sources")
        }),

        ("^the shipped binary exports no symbol for (.+)$", { args, world in
            let symbols = try required(world.manifest.binarySymbols, orSkip: "no shipped binary to inspect")
            try expect(!symbols.contains(where: { $0.contains(args[0]) }),
                       orFail: "the binary still carries a symbol for \(args[0])")
        }),

        ("^the app bundle contains no resource named (.+)$", { args, world in
            let resources = try required(world.manifest.bundleResources, orSkip: "no app bundle to inspect")
            try expect(!resources.contains(args[0]),
                       orFail: "the app bundle still ships \(args[0])")
        }),

        ("^the build resolves no package dependency named (.+)$", { args, world in
            let packages = try required(world.manifest.resolvedPackages,
                                        orSkip: "no resolved package list to inspect")
            try expect(!packages.contains(where: { $0.caseInsensitiveCompare(args[0]) == .orderedSame }),
                       orFail: "the build still resolves \(args[0])")
        }),

        // MARK: Enhancement provider

        ("^I enable the hidden preference (.+)$", { args, world in
            world.defaults.set(true, forKey: args[0])
        }),

        ("^I enhance a transcript$", { _, world in
            world.enhancementProvider = AIProvider.resolved(defaults: world.defaults)
        }),

        ("^the enhancement runs on the (.+) provider$", { args, world in
            let provider = try required(world.enhancementProvider, orFail: "no transcript was enhanced")
            let expected = try providerNamed(args[0])
            try expect(provider == expected, orFail: "expected \(args[0]); ran on \(provider)")
        }),

        // MARK: Runtime budgets

        ("^the installed app bundle is smaller than (\\d+) megabytes$", { args, world in
            let sizeMB = try required(world.manifest.appBundleSizeMB, orSkip: "no app bundle to measure")
            let budget = try required(Int(args[0]), orFail: "unreadable budget \(args[0])")
            try expect(sizeMB < budget, orFail: "app bundle is \(sizeMB) MB, budget is \(budget) MB")
        }),

        // Live-process budgets. Measuring these means launching the app,
        // sampling it, and driving a real dictation through a transcription
        // engine — none of which this headless suite can do. They report a
        // skip with the reason instead of a pass on no evidence.
        ("^(?:the menu bar item responds within \\d+ milliseconds|I sample the process for \\d+ seconds|average CPU stays below \\d+ percent|idle resident memory stays below \\d+ megabytes|I record for \\d+ seconds with the .+ engine|peak resident memory stays below \\d+ megabytes|the first transcript word appears within \\d+ milliseconds|a recording ends and the transcript is delivered|resident memory returns below \\d+ megabytes within \\d+ seconds)$",
         { _, _ in
            throw StepError.skipped("needs a live app process and a real dictation; not measurable in the headless suite")
         }),
    ]

    // MARK: - Step-order failure reasons
    //
    // Named because more than one step reports the same missing precondition.

    private static let unreadDocumentedVersion = "the documented minimum macOS version was not read"
    private static let missingAppearanceInputs = "appearance inputs were not set up"

    // MARK: - Lookups

    private static func tabShowsControl(tab: String, control: String) throws -> Bool {
        switch (tab, control) {
        case ("Vocabulary", "remove filler words toggle"),
             ("Vocabulary", "filler word list"):
            return VocabularyTab.renderedSections.contains(.fillerWords)
        case ("Vocabulary", "dictionary word list"):
            return VocabularyTab.renderedSections.contains(.dictionary)
        case ("Vocabulary", "word replacement list"):
            return VocabularyTab.renderedSections.contains(.wordReplacements)
        case ("General", "device priority list"):
            return GeneralTab.renderedSections.contains(.audioInput)
        default:
            throw StepError.undefined("unknown control \"\(control)\" for the \(tab) tab")
        }
    }

    private static func voiceOverLabel(forControl control: String) -> String? {
        switch control {
        case "menu bar item":         return MenuBarIconRenderer.accessibilityLabel(for: .idle)
        case "dictionary add button": return VocabularyView.addButtonLabel
        case "review undo button":    return ReviewTray.undoButtonLabel
        case "review copy button":    return ReviewTray.copyButtonLabel
        default:                      return nil
        }
    }

    private static func parseVersion(_ text: String) throws -> OperatingSystemVersion {
        let parts = text.split(separator: ".").map { Int($0) ?? -1 }
        guard let major = parts.first, major >= 0 else {
            throw StepError.failed("unreadable macOS version \(text)")
        }
        return OperatingSystemVersion(
            majorVersion: major,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
    }

    private static func launchOutcome(named text: String) throws -> PlatformSupport.LaunchOutcome {
        switch text {
        case "opens its menu bar item":          return .opensMenuBarItem
        case "reports an unsupported macOS version": return .unsupportedMacOSVersion
        default: throw StepError.undefined("unknown launch result \"\(text)\"")
        }
    }

    private static func appearanceChoice(named text: String) throws -> AppearanceChoice {
        switch text {
        case "follow system": return .system
        case "light":         return .light
        case "dark":          return .dark
        default: throw StepError.undefined("unknown appearance preference \"\(text)\"")
        }
    }

    private static func providerNamed(_ text: String) throws -> AIProvider {
        switch text {
        case "AppleFoundation": return .foundationModels
        default: throw StepError.undefined("unknown provider \"\(text)\"")
        }
    }
}
