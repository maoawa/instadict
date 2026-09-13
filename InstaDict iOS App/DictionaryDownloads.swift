import Foundation
import Observation

struct DictionaryDownloadRequest: Codable, Sendable {
    let token: UUID
    let pack: DictionaryPack
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
    @ObservationIgnored private var tasks: [DictionaryID: URLSessionDownloadTask] = [:]
    @ObservationIgnored private var requests: [DictionaryID: DictionaryDownloadRequest] = [:]
    @ObservationIgnored private var processing = 0
    @ObservationIgnored private var eventsFinished = false
    @ObservationIgnored private var backgroundCompletion: (() -> Void)?
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
    private static var cachedCatalog: URL { DictionaryLibrary.root.appending(path: "catalog.json") }

    func start() {
        guard !started else { return }
        started = true
        do {
            let catalog: DictionaryCatalog
            if let data = try? Data(contentsOf: Self.cachedCatalog), let cached = try? DictionaryCatalog.decode(data) { catalog = cached }
            else { catalog = try DictionaryCatalog.bundled() }
            packs = catalog.packs
        } catch { catalogMessage = error.localizedDescription }
        _ = session
        recoverDownloads()
        Task {
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
            var request = URLRequest(url: DictionaryCatalog.remoteURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw PackError.invalidCatalog }
            guard http.statusCode == 200 else { throw PackError.http(http.statusCode) }
            guard data.count <= 1_000_000 else { throw PackError.invalidCatalog }
            let catalog = try DictionaryCatalog.decode(data)
            try FileManager.default.createDirectory(at: DictionaryLibrary.root, withIntermediateDirectories: true)
            try data.write(to: Self.cachedCatalog, options: .atomic)
            packs = catalog.packs
            catalogMessage = nil
        } catch { catalogMessage = "Using the saved catalog. " + error.localizedDescription }
    }

    func download(_ pack: DictionaryPack) {
        guard tasks[pack.id] == nil, !verifying.contains(pack.id) else { return }
        do { try pack.validate() } catch { errors[pack.id] = error.localizedDescription; return }
        errors[pack.id] = nil
        let request = DictionaryDownloadRequest(token: UUID(), pack: pack)
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
        }
        requests[id] = nil
        tasks[id]?.cancel()
        tasks[id] = nil
        progress[id] = nil
    }

    func handleBackgroundEvents(_ completion: @escaping () -> Void) {
        backgroundCompletion = completion
        start()
        finishBackgroundEventsIfReady()
    }

    private func finishBackgroundEventsIfReady() {
        guard eventsFinished, processing == 0, let completion = backgroundCompletion else { return }
        backgroundCompletion = nil
        eventsFinished = false
        completion()
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
                try await DictionaryLibrary.shared.install(saved, pack: request.pack)
                await DictionarySync.shared.refreshLocal()
                await DictionarySync.shared.send(request.pack)
            } catch { errors[request.pack.id] = error.localizedDescription }
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
        guard status == 200 else {
            DispatchQueue.main.async { self.fail(request, message: PackError.http(status).localizedDescription) }
            return
        }
        do {
            let folder = DictionaryLibrary.root.appending(path: "Downloads")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let saved = folder.appending(path: request.token.uuidString + ".sqlite")
            try FileManager.default.moveItem(at: location, to: saved)
            try JSONEncoder().encode(request).write(to: saved.appendingPathExtension("json"), options: .atomic)
            DispatchQueue.main.async { self.processDownloaded(saved, request: request) }
        } catch {
            let message = error.localizedDescription
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
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let request = Self.request(for: task), (error as NSError).code != NSURLErrorCancelled else { return }
        let message = error.localizedDescription
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
        completionHandler(request.url?.scheme == "https" && request.url?.host == "fastcdn.candyrect.com" ? request : nil)
    }
}
