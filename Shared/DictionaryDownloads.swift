import Foundation
import Observation

struct DictionaryDownloadRequest: Codable, Sendable {
    let token: UUID
    let pack: DictionaryPack
    let command: PackCommand?
    let sendToWatch: Bool?
}

@MainActor @Observable
final class DictionaryDownloads: NSObject, URLSessionDownloadDelegate {
    static let shared = DictionaryDownloads()
    static let sessionIdentifier = "com.candyrect.instadict.dictionary-downloads"
    private(set) var packs: [DictionaryPack] = []
    private(set) var progress: [DictionaryID: Double] = [:]
    private(set) var verifying: Set<DictionaryID> = []
    private(set) var errors: [DictionaryID: String] = [:]
    private(set) var catalogMessage: String?
    private(set) var isRefreshing = false
    private(set) var sourceURL = DictionaryCatalog.remoteURL
    var isDefaultSource: Bool { sourceURL == DictionaryCatalog.remoteURL }
    var sourceDisplayName: String { isDefaultSource ? L10n.ui("Default source") : sourceURL.absoluteString }
    var editableSourceAddress: String { isDefaultSource ? "" : (sourceURL.lastPathComponent == "manifest.json" ? sourceURL.deletingLastPathComponent().absoluteString : sourceURL.absoluteString) }
    private(set) var isRestoring = true
    var canChangeSource: Bool { !isRefreshing && !isRestoring && tasks.isEmpty && verifying.isEmpty }
    @ObservationIgnored private var tasks: [DictionaryID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var requests: [DictionaryID: DictionaryDownloadRequest] = [:]
    @ObservationIgnored private var processing = 0
    @ObservationIgnored private var eventsFinished = false
    @ObservationIgnored private var backgroundCompletions: [() -> Void] = []
    @ObservationIgnored private var started = false
    private static let latestKey = "latestDictionaryDownloadTokens.v2"
    private static let canceledKey = "canceledDictionaryDownloads.v2"
    @ObservationIgnored private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        configuration.waitsForConnectivity = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }()
    private static var cachedCatalog: URL { DictionaryLibrary.root.appending(path: "catalog-selection.json") }

    func start() {
        guard !started else { return }
        started = true
        do {
            let saved = (try? Data(contentsOf: Self.cachedCatalog)).flatMap { try? DictionaryCatalogSelection.decode($0) }
            if let saved {
                sourceURL = saved.effectiveSource
                if saved.usesDefaultSource {
                    let bundled = try DictionaryCatalog.bundled()
                    // A former built-in host migrates to the new bundled source;
                    // a deliberately saved custom source keeps its own URLs.
                    packs = bundled.preferringCached(saved.source == sourceURL ? saved.catalog : nil).packs
                } else { packs = saved.catalog.packs }
            } else {
                packs = try DictionaryCatalog.bundled().packs
            }
        } catch { catalogMessage = L10n.errorMessage(error) }
        _ = session
        recoverDownloads()
        Task {
            defer { isRestoring = false }
            for task in await session.allTasks {
                if let download = task as? URLSessionDownloadTask, let request = Self.request(for: task) {
                    if !accepts(request) || (requests[request.pack.id] != nil && requests[request.pack.id]?.token != request.token) {
                        download.cancel()
                        continue
                    }
                    guard !verifying.contains(request.pack.id) else { continue }
                    tasks[request.pack.id] = download
                    requests[request.pack.id] = request
                    progress[request.pack.id] = task.countOfBytesExpectedToReceive > 0
                        ? Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive) : 0
                }
            }
        }
    }

    func refreshCatalog() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let catalog = try await fetchCatalog(at: sourceURL)
            try save(catalog, source: sourceURL)
        } catch { catalogMessage = "Using the saved catalog. " + L10n.errorMessage(error) }
    }

    func changeSource(to input: String) async throws {
        guard canChangeSource else { throw SourceError.busy }
        let source = try DictionaryDownloadSource.normalize(input)
        isRefreshing = true
        defer { isRefreshing = false }
        let catalog = try await fetchCatalog(at: source)
        try save(catalog, source: source)
        errors = [:]
    }

    private func fetchCatalog(at source: URL) async throws -> DictionaryCatalog {
        let client = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        defer { client.invalidateAndCancel() }
        var request = URLRequest(url: source)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30
        let (bytes, response) = try await client.bytes(for: request)
        guard let http = response as? HTTPURLResponse, let finalURL = response.url,
              DictionaryDownloadSource.isSecureURL(finalURL) else { throw PackError.invalidCatalog }
        guard http.statusCode == 200 else { throw PackError.http(http.statusCode) }
        guard response.expectedContentLength <= 1_000_000 else { throw PackError.invalidCatalog }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_000_000 else { throw PackError.invalidCatalog }
            data.append(byte)
        }
        let catalog = try DictionaryCatalog.decode(data, relativeTo: finalURL)
        return source == DictionaryCatalog.remoteURL
            ? try catalog.requiringCurrentFormat(minimum: DictionaryCatalog.bundled()) : catalog
    }

    private func save(_ catalog: DictionaryCatalog, source: URL) throws {
        let selection = DictionaryCatalogSelection(source: source, catalog: catalog, isDefault: source == DictionaryCatalog.remoteURL)
        try FileManager.default.createDirectory(at: DictionaryLibrary.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(selection).write(to: Self.cachedCatalog, options: .atomic)
        sourceURL = source
        packs = catalog.packs
        catalogMessage = nil
    }

    func download(_ pack: DictionaryPack) async {
        guard !isRefreshing, !isRestoring, packs.contains(pack), tasks[pack.id] == nil,
              !verifying.contains(pack.id) else { return }
        do { try pack.validate() } catch { errors[pack.id] = L10n.errorMessage(error); return }
        errors[pack.id] = nil
        var command: PackCommand?
        #if os(watchOS)
        verifying.insert(pack.id)
        do {
            command = try await DictionaryLibrary.shared.beginLocalChange(pack.id, pack: pack)
            await DictionarySync.shared.refreshLocal()
        } catch {
            verifying.remove(pack.id)
            errors[pack.id] = L10n.errorMessage(error)
            return
        }
        verifying.remove(pack.id)
        #endif
        let request = DictionaryDownloadRequest(token: UUID(), pack: pack, command: command, sendToWatch: false)
        var latest = UserDefaults.standard.dictionary(forKey: Self.latestKey) as? [String: String] ?? [:]
        latest[pack.id.rawValue] = request.token.uuidString
        UserDefaults.standard.set(latest, forKey: Self.latestKey)
        let task = session.downloadTask(with: pack.url)
        task.taskDescription = try? String(data: JSONEncoder().encode(request), encoding: .utf8)
        requests[pack.id] = request
        tasks[pack.id] = task
        progress[pack.id] = 0
        task.resume()
    }

    func cancel(_ id: DictionaryID) {
        if let request = requests[id] {
            var canceled = UserDefaults.standard.stringArray(forKey: Self.canceledKey) ?? []
            canceled.append(request.token.uuidString)
            UserDefaults.standard.set(Array(canceled.suffix(100)), forKey: Self.canceledKey)
            if let command = request.command {
                Task {
                    try? await DictionaryLibrary.shared.cancelLocalChange(command)
                    await DictionarySync.shared.refreshLocal()
                }
            }
        }
        requests[id] = nil
        tasks[id]?.cancel()
        tasks[id] = nil
        progress[id] = nil
    }

    func handleBackgroundEvents(_ completion: @escaping () -> Void) {
        backgroundCompletions.append(completion)
        start()
        finishBackgroundEventsIfReady()
    }

    private func finishBackgroundEventsIfReady() {
        guard eventsFinished, processing == 0, !backgroundCompletions.isEmpty else { return }
        let completions = backgroundCompletions
        backgroundCompletions = []
        eventsFinished = false
        completions.forEach { $0() }
    }

    nonisolated private static func request(for task: URLSessionTask) -> DictionaryDownloadRequest? {
        guard let data = task.taskDescription?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DictionaryDownloadRequest.self, from: data)
    }

    private func accepts(_ request: DictionaryDownloadRequest) -> Bool {
        let canceled = UserDefaults.standard.stringArray(forKey: Self.canceledKey) ?? []
        let latest = UserDefaults.standard.dictionary(forKey: Self.latestKey) as? [String: String] ?? [:]
        return !canceled.contains(request.token.uuidString) && (latest[request.pack.id.rawValue] == nil || latest[request.pack.id.rawValue] == request.token.uuidString)
    }

    private func recoverDownloads() {
        let folder = DictionaryLibrary.root.appending(path: "Downloads")
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where file.pathExtension == "sqlite" {
            if let data = try? Data(contentsOf: file.appendingPathExtension("json")),
               let request = try? JSONDecoder().decode(DictionaryDownloadRequest.self, from: data) {
                processDownloaded(file, request: request)
            } else { try? FileManager.default.removeItem(at: file) }
        }
    }

    private func processDownloaded(_ saved: URL, request: DictionaryDownloadRequest) {
        guard accepts(request), requests[request.pack.id] == nil || requests[request.pack.id]?.token == request.token else {
            try? FileManager.default.removeItem(at: saved)
            try? FileManager.default.removeItem(at: saved.appendingPathExtension("json"))
            return
        }
        guard !verifying.contains(request.pack.id) else { return }
        requests[request.pack.id] = request
        processing += 1
        verifying.insert(request.pack.id)
        progress[request.pack.id] = nil
        Task {
            defer {
                verifying.remove(request.pack.id)
                tasks[request.pack.id] = nil
                requests[request.pack.id] = nil
                try? FileManager.default.removeItem(at: saved)
                try? FileManager.default.removeItem(at: saved.appendingPathExtension("json"))
                processing -= 1
                finishBackgroundEventsIfReady()
            }
            do {
                try await DictionaryLibrary.shared.install(saved, pack: request.pack, command: request.command)
                await DictionarySync.shared.refreshLocal()
                #if os(iOS)
                // Restore the old download-and-send behavior for tasks created
                // before iPhone gained standalone dictionary lookup.
                if request.sendToWatch != false { await DictionarySync.shared.send(request.pack) }
                #endif
            } catch {
                errors[request.pack.id] = L10n.errorMessage(error)
                if let command = request.command {
                    try? await DictionaryLibrary.shared.recordError(L10n.errorMessage(error), for: request.pack.id, command: command)
                    await DictionarySync.shared.refreshLocal()
                }
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                               didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let request = Self.request(for: downloadTask) else { return }
        let fraction = min(1, Double(totalBytesWritten) / Double(request.pack.byteCount))
        DispatchQueue.main.async {
            guard self.requests[request.pack.id]?.token == request.token else { return }
            self.progress[request.pack.id] = fraction
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let request = Self.request(for: downloadTask) else { return }
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: location.path)
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            try request.pack.validateDownload(statusCode: status, fileByteCount: size)
            let folder = DictionaryLibrary.root.appending(path: "Downloads")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let saved = folder.appending(path: request.token.uuidString + ".sqlite")
            try FileManager.default.moveItem(at: location, to: saved)
            try JSONEncoder().encode(request).write(to: saved.appendingPathExtension("json"), options: .atomic)
            DispatchQueue.main.async { self.processDownloaded(saved, request: request) }
        } catch {
            let message = L10n.errorMessage(error)
            DispatchQueue.main.async { self.fail(request, message: message) }
        }
    }

    private func fail(_ request: DictionaryDownloadRequest, message: String) {
        guard accepts(request) else { return }
        guard requests[request.pack.id]?.token == request.token || requests[request.pack.id] == nil else { return }
        errors[request.pack.id] = message
        progress[request.pack.id] = nil
        tasks[request.pack.id] = nil
        requests[request.pack.id] = nil
        if let command = request.command {
            Task {
                try? await DictionaryLibrary.shared.recordError(message, for: request.pack.id, command: command)
                await DictionarySync.shared.refreshLocal()
            }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let request = Self.request(for: task), (error as NSError).code != NSURLErrorCancelled else { return }
        let message = L10n.errorMessage(error)
        DispatchQueue.main.async { self.fail(request, message: message) }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        // The delegate queue is serial; these main-queue blocks preserve ordering
        // with pending verification work before invoking the system completion.
        DispatchQueue.main.async {
            self.eventsFinished = true
            self.finishBackgroundEventsIfReady()
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                               willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                               completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(DictionaryDownloadSource.isSecureURL) == true ? request : nil)
    }
}
