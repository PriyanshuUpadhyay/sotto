import Foundation

enum AppSupport {
    /// Name of the app's Application Support subdirectory. Matches the bundle
    /// identifier so all on-disk data (SwiftData stores, Recordings, Logs,
    /// custom sounds) lives under one namespace.
    static let directoryName = "com.sotto.Sotto"
}
