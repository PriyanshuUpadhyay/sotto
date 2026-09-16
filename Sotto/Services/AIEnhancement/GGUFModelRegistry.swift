import Foundation

struct GGUFModelEntry: Identifiable, Hashable {
    let slug: String
    let displayName: String
    let huggingFaceRepo: String
    let fileName: String
    let downloadURL: URL
    let byteSize: Int64
    let licenseNote: String

    var id: String { slug }

    var diskSize: String {
        ByteCountFormatter.string(fromByteCount: byteSize, countStyle: .file)
    }
}

enum GGUFModelRegistry {
    static let curated: [GGUFModelEntry] = [
        .init(
            slug: "s1-mini",
            displayName: "S1-mini (Superwhisper, 0.6B)",
            huggingFaceRepo: "superwhisper/s1-mini-GGUF",
            fileName: "s1-mini-q4_k_m.gguf",
            downloadURL: URL(string: "https://huggingface.co/superwhisper/s1-mini-GGUF/resolve/main/s1-mini-q4_k_m.gguf")!,
            byteSize: 483_000_000,
            licenseNote: "Apache 2.0 with naming clause"
        ),
        .init(
            slug: "speakoflow-mini",
            displayName: "SpeakoFlow-Mini (0.8B)",
            huggingFaceRepo: "SpeakoFlow/speakoflow-mini",
            fileName: "SpeakoFlow-Mini-0.8B-Q8_0.gguf",
            downloadURL: URL(string: "https://huggingface.co/SpeakoFlow/speakoflow-mini/resolve/main/SpeakoFlow-Mini-0.8B-Q8_0.gguf")!,
            byteSize: 833_000_000,
            licenseNote: "Apache 2.0"
        ),
    ]

    static var selectedSlug: String {
        get {
            let stored = UserDefaults.standard.string(forKey: "EnhancementGGUFModelSlug") ?? ""
            return curated.contains { $0.slug == stored } ? stored : curated[0].slug
        }
        set {
            guard curated.contains(where: { $0.slug == newValue }) else { return }
            UserDefaults.standard.set(newValue, forKey: "EnhancementGGUFModelSlug")
        }
    }

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
            .appendingPathComponent("GGUFModels", isDirectory: true)
    }

    static func entry(slug: String) -> GGUFModelEntry? {
        curated.first { $0.slug == slug }
    }

    static func fileURL(slug: String) -> URL? {
        entry(slug: slug).map { modelsDirectory.appendingPathComponent($0.fileName) }
    }

    static func isDownloaded(_ slug: String) -> Bool {
        guard let url = fileURL(slug: slug) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func deleteModel(_ slug: String) throws {
        guard let finalURL = fileURL(slug: slug) else { return }
        let partURL = finalURL.appendingPathExtension("part")
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }
        if fileManager.fileExists(atPath: partURL.path) {
            try? fileManager.removeItem(at: partURL)
        }
        if selectedSlug == slug {
            UserDefaults.standard.set(AIProvider.foundationModels.rawValue, forKey: "EnhancementProvider")
        }
    }
}

@MainActor
final class GGUFDownloadManager: ObservableObject {
    static let shared = GGUFDownloadManager()

    enum State: Equatable {
        case idle
        case downloading
        case paused
        case failed(String)
    }

    @Published var states: [String: State] = [:]
    @Published var progress: [String: Double] = [:]

    private var tasks: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]
    private var session: URLSession!

    private init() {
        let delegate = GGUFDownloadDelegate(manager: self)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "com.sotto.gguf-download"
        self.session = URLSession(configuration: .default, delegate: delegate, delegateQueue: queue)
    }

    func state(for slug: String) -> State {
        states[slug] ?? .idle
    }

    func progress(for slug: String) -> Double {
        progress[slug] ?? 0.0
    }

    func start(_ slug: String) {
        guard let entry = GGUFModelRegistry.entry(slug: slug) else { return }
        cancel(slug)

        let task = session.downloadTask(with: entry.downloadURL)
        task.taskDescription = slug
        tasks[slug] = task
        states[slug] = .downloading
        progress[slug] = 0.0
        task.resume()
    }

    func pause(_ slug: String) {
        guard let task = tasks[slug] else { return }
        states[slug] = .paused
        tasks.removeValue(forKey: slug)
        task.cancel { [weak self] data in
            Task { @MainActor in
                if let data {
                    self?.resumeData[slug] = data
                }
            }
        }
    }

    func resume(_ slug: String) {
        guard states[slug] == .paused else { return }
        if let data = resumeData.removeValue(forKey: slug) {
            let task = session.downloadTask(withResumeData: data)
            task.taskDescription = slug
            tasks[slug] = task
            states[slug] = .downloading
            task.resume()
        } else {
            start(slug)
        }
    }

    func cancel(_ slug: String) {
        if let task = tasks.removeValue(forKey: slug) {
            task.cancel()
        }
        resumeData.removeValue(forKey: slug)
        states[slug] = .idle
        progress.removeValue(forKey: slug)
        if let finalURL = GGUFModelRegistry.fileURL(slug: slug) {
            let partURL = finalURL.appendingPathExtension("part")
            try? FileManager.default.removeItem(at: partURL)
        }
    }

    fileprivate func updateProgress(slug: String, fraction: Double) {
        progress[slug] = fraction
    }

    fileprivate func didFinish(slug: String) {
        tasks.removeValue(forKey: slug)
        resumeData.removeValue(forKey: slug)
        progress.removeValue(forKey: slug)
        states[slug] = .idle
        NotificationCenter.default.post(name: .AppSettingsDidChange, object: nil)
    }

    fileprivate func didFail(slug: String, error: String) {
        tasks.removeValue(forKey: slug)
        resumeData.removeValue(forKey: slug)
        progress.removeValue(forKey: slug)
        states[slug] = .failed(error)
        if let finalURL = GGUFModelRegistry.fileURL(slug: slug) {
            let partURL = finalURL.appendingPathExtension("part")
            try? FileManager.default.removeItem(at: partURL)
        }
    }

    fileprivate func setResumeData(_ data: Data, for slug: String) {
        resumeData[slug] = data
    }
}

private final class GGUFDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var manager: GGUFDownloadManager?
    private var lastUpdateTime: [String: Date] = [:]

    init(manager: GGUFDownloadManager) {
        self.manager = manager
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let slug = downloadTask.taskDescription else { return }
        let now = Date()
        let last = lastUpdateTime[slug] ?? .distantPast
        if now.timeIntervalSince(last) < 0.1 && totalBytesWritten < totalBytesExpectedToWrite {
            return
        }
        lastUpdateTime[slug] = now

        let expected: Int64
        if totalBytesExpectedToWrite > 0 {
            expected = totalBytesExpectedToWrite
        } else if let entry = GGUFModelRegistry.entry(slug: slug) {
            expected = entry.byteSize
        } else {
            expected = totalBytesWritten
        }
        let frac = min(1.0, max(0.0, Double(totalBytesWritten) / Double(expected)))
        Task { @MainActor in
            self.manager?.updateProgress(slug: slug, fraction: frac)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let slug = downloadTask.taskDescription,
              let finalURL = GGUFModelRegistry.fileURL(slug: slug) else { return }

        let fileManager = FileManager.default
        let partURL = finalURL.appendingPathExtension("part")

        do {
            try fileManager.createDirectory(
                at: GGUFModelRegistry.modelsDirectory,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: partURL.path) {
                try fileManager.removeItem(at: partURL)
            }
            try fileManager.moveItem(at: location, to: partURL)

            // Keep the partial name next to the final model until the move is complete.
            if fileManager.fileExists(atPath: finalURL.path) {
                try fileManager.removeItem(at: finalURL)
            }
            try fileManager.moveItem(at: partURL, to: finalURL)

            Task { @MainActor in
                self.manager?.didFinish(slug: slug)
            }
        } catch {
            try? fileManager.removeItem(at: partURL)
            Task { @MainActor in
                self.manager?.didFail(slug: slug, error: error.localizedDescription)
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let slug = task.taskDescription else { return }
        if let error = error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                    Task { @MainActor in
                        self.manager?.setResumeData(resumeData, for: slug)
                    }
                }
                return
            }
            Task { @MainActor in
                self.manager?.didFail(slug: slug, error: error.localizedDescription)
            }
        }
    }
}


