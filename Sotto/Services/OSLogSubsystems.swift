import Foundation

/// Centralised OSLog subsystem identifiers.
///
/// Subsystem strings drive Console.app filtering + `log stream --predicate`
/// queries; they MUST match the app's bundle identifier so log attribution
/// in Console.app aligns with the installed app identity. Pre-rename, 51
/// `Logger(subsystem:)` call sites referenced 5 inconsistent strings; this
/// type consolidates them at rename time. The `no-inline-logger-literals`
/// success criterion grep-enforces that no other Swift file embeds the
/// `Logger(subsystem: "com....")` literal pattern.
enum OSLogSubsystems {
    /// Primary subsystem — matches `CFBundleIdentifier = com.sotto.Sotto`.
    static let app = "com.sotto.Sotto"

    /// FluidAudio streaming + model-manager subsystem. Distinct from `app`
    /// so power-user Console filters can isolate FluidAudio noise.
    static let fluidAudio = "com.sotto.Sotto.fluidaudio"
}
