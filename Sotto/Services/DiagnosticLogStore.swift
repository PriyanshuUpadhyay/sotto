import AppKit
import ApplicationServices
import Carbon
import Foundation
import OSLog

/// Keeps Sotto's own system-log entries in a capped file, so a user can share
/// logs from earlier runs too.
///
/// macOS lets a normal app read only the entries of its current process
/// (`OSLogStore(scope: .currentProcessIdentifier)`), so entries are copied to
/// the file at intervals. A crash loses the entries since the last copy.
final class DiagnosticLogStore {
    static let shared = DiagnosticLogStore(fileURL: FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent("sotto.log"))

    static let maxBytes = 5 * 1024 * 1024
    private static let flushInterval: TimeInterval = 60

    let fileURL: URL
    private let queue = DispatchQueue(label: "com.sotto.Sotto.diagnostic-log", qos: .utility)
    /// Date of the newest entry already in the file. Only touched on `queue`.
    private var lastCopied: Date?
    private var timer: DispatchSourceTimer?
    private var terminateObserver: NSObjectProtocol?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// Writes a launch marker and starts the periodic copy.
    func start() {
        queue.async { [self] in
            append("=== launch \(Self.timestamp(Date())) — \(Self.appVersion()) — macOS \(ProcessInfo.processInfo.operatingSystemVersionString) — pid \(getpid()) ===\n")
            lastCopied = Date()
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.flushInterval, repeating: Self.flushInterval)
        timer.setEventHandler { [weak self] in self?.copyNewEntries() }
        timer.resume()
        self.timer = timer
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.queue.sync { self?.copyNewEntries() }
        }
    }

    /// The text for "Export Logs…": a header with the current state, then the
    /// stored log. Blocks while it copies the newest entries.
    func exportText() -> String {
        queue.sync {
            copyNewEntries()
            let body = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            return Self.header() + "\n" + body
        }
    }

    // MARK: - Copy and cap (on `queue`)

    private func copyNewEntries() {
        guard let since = lastCopied,
              let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return }
        let predicate = NSPredicate(format: "subsystem BEGINSWITH %@", OSLogSubsystems.app)
        guard let entries = try? store.getEntries(at: store.position(date: since), matching: predicate) else { return }

        var text = ""
        var newest = since
        for case let entry as OSLogEntryLog in entries where entry.date > since {
            text += Self.format(date: entry.date, level: entry.level, category: entry.category, message: entry.composedMessage)
            newest = max(newest, entry.date)
        }
        lastCopied = newest
        if !text.isEmpty { append(text) }
    }

    private func append(_ text: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data(text.utf8))
        let size = (try? handle.offset()) ?? 0
        try? handle.close()

        if size > UInt64(Self.maxBytes), let data = try? Data(contentsOf: fileURL) {
            try? Self.trimmed(data, to: Self.maxBytes).write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Pure helpers

    /// Drops the oldest lines so the result is at most 80% of `maxBytes`. The
    /// slack means the file is not rewritten on every copy once it is full.
    static func trimmed(_ data: Data, to maxBytes: Int) -> Data {
        guard data.count > maxBytes else { return data }
        let keep = data.suffix(maxBytes * 4 / 5)
        guard let newline = keep.firstIndex(of: UInt8(ascii: "\n")) else { return Data(keep) }
        return Data(keep[keep.index(after: newline)...])
    }

    static func format(date: Date, level: OSLogEntryLog.Level, category: String, message: String) -> String {
        "\(timestamp(date)) \(levelName(level)) [\(category)] \(message)\n"
    }

    private static func levelName(_ level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        default: return "log"
        }
    }

    private static func timestamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }

    private static func appVersion() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Sotto \(short) (\(build))"
    }

    /// The state that most often explains a paste that does nothing.
    private static func header() -> String {
        let globe = GlobeKeyAction.current()
        return """
        \(appVersion())
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        exported \(timestamp(Date()))
        accessibility trusted: \(AXIsProcessTrusted())
        secure input on: \(IsSecureEventInputEnabled())
        shortcut 1: \(UserDefaults.standard.string(forKey: "selectedHotkey1") ?? "default")
        fn (globe) key action: \(globe.systemLabel ?? "not set")
        applescript paste: \(UserDefaults.standard.bool(forKey: "useAppleScriptPaste"))

        """
    }
}
