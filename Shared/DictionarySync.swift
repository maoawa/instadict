import Foundation
import Observation
import WatchConnectivity
#if os(watchOS)
import WatchKit
#endif

/// Owns WCSession on both devices. Receipts, rather than transport completion,
/// determine whether a dictionary is installed on the Watch.
@MainActor @Observable
final class DictionarySync: NSObject, WCSessionDelegate {
    static let shared = DictionarySync()
    private(set) var local = WatchLibraryStatus()
    private(set) var watch = WatchLibraryStatus()
    private(set) var connectionMessage = "Connecting to Apple Watch…"
    private(set) var transfers: [DictionaryID: Double] = [:]
    private(set) var transferErrors: [DictionaryID: String] = [:]
    private(set) var isActivated = false
    private(set) var busy: Set<DictionaryID> = []
    private(set) var isCheckingWatch = false
    private(set) var watchStatusMessage: String?
    @ObservationIgnored private let library = DictionaryLibrary.shared
    @ObservationIgnored private var started = false
    @ObservationIgnored private var observations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    @ObservationIgnored private var commands: [PackCommand] = []
    @ObservationIgnored private var statusRequest: UUID?
    @ObservationIgnored private var statusTimeout: Task<Void, Never>?
    @ObservationIgnored private var installingFiles: Set<URL> = []
    @ObservationIgnored private let session: WCSession? = WCSession.isSupported() ? .default : nil
    private static let commandsKey = "dictionarySyncCommands.v2"

    func start() {
        guard !started else { return }
        started = true
        if let data = UserDefaults.standard.data(forKey: Self.commandsKey) {
            commands = (try? JSONDecoder().decode([PackCommand].self, from: data)) ?? []
        }
        if let data = UserDefaults.standard.data(forKey: "lastWatchLibrary.v2") {
            watch = (try? JSONDecoder().decode(WatchLibraryStatus.self, from: data)) ?? .init()
        }
        Task { await refreshLocal() }
        guard let session else { connectionMessage = "Apple Watch syncing isn’t supported on this device."; return }
        session.delegate = self
        session.activate()
    }

    func refreshLocal() async {
        do { local = try await library.snapshot() }
        catch { connectionMessage = L10n.errorMessage(error) }
        #if os(watchOS)
        publishWatchStatus()
        #endif
    }

    #if os(iOS)
    /// Background application context is eventually delivered. Ask directly as
    /// well when both apps are reachable, including after a transfer finishes.
    func checkWatchStatus() {
        start()
        guard !isCheckingWatch else { return }
        guard let session, isActivated, session.isReachable else {
            watchStatusMessage = "Open InstaDict on your Watch and keep it near your iPhone, then check again."
            return
        }
        let request = UUID()
        statusRequest = request
        isCheckingWatch = true
        watchStatusMessage = nil
        statusTimeout = Task {
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, statusRequest == request else { return }
            finishStatusCheck(request, error: "The Watch hasn’t replied. Keep InstaDict open on both devices and check again.")
        }
        do {
            session.sendMessageData(try JSONEncoder().encode(commands), replyHandler: { data in
                Task { @MainActor in
                    guard self.statusRequest == request else { return }
                    do {
                        let reply = try JSONDecoder().decode(DictionaryStatusReply.self, from: data)
                        if let snapshot = reply.inventory {
                            self.receiveInventory(snapshot)
                            self.finishStatusCheck(request, error: reply.error)
                        } else {
                            self.finishStatusCheck(request, error: reply.error ?? "The Watch couldn’t read its dictionary library.")
                        }
                    } catch {
                        self.finishStatusCheck(request, error: "Update InstaDict on both iPhone and Watch, then check again.")
                    }
                }
            }, errorHandler: { error in
                let message = L10n.errorMessage(error)
                Task { @MainActor in
                    self.finishStatusCheck(request, error: "Couldn’t check the Watch: " + message)
                }
            })
        } catch { finishStatusCheck(request, error: L10n.errorMessage(error)) }
    }

    private func finishStatusCheck(_ request: UUID, error: String?) {
        guard statusRequest == request else { return }
        statusTimeout?.cancel()
        statusTimeout = nil
        statusRequest = nil
        isCheckingWatch = false
        watchStatusMessage = error
    }

    private func receiveInventory(_ snapshot: WatchLibraryStatus) {
        watch = snapshot
        commands = PackCommand.merging(commands, with: snapshot.commands)
        UserDefaults.standard.set(try? JSONEncoder().encode(commands), forKey: Self.commandsKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(snapshot), forKey: "lastWatchLibrary.v2")
    }

    func send(_ pack: DictionaryPack) async {
        guard !busy.contains(pack.id) else { return }
        busy.insert(pack.id)
        defer { busy.remove(pack.id) }
        transferErrors[pack.id] = nil
        guard let session, isActivated, session.isPaired, session.isWatchAppInstalled else {
            transferErrors[pack.id] = "Install InstaDict on your paired Apple Watch, then try again."
            return
        }
        do {
            cancelTransport(pack.id)
            guard let source = try await library.file(for: pack.id) else { throw PackError.missing(pack.id) }
            let outgoing = try await Task.detached {
                let folder = DictionaryLibrary.root.appending(path: "Outgoing")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let copy = folder.appending(path: UUID().uuidString + ".sqlite")
                try FileManager.default.copyItem(at: source, to: copy)
                return copy
            }.value
            let command = nextCommand(pack.id, pack: pack)
            transferErrors[pack.id] = nil
            do {
                try publishCommands()
                let transfer = session.transferFile(outgoing, metadata: ["command": try JSONEncoder().encode(command)])
                observe(transfer, id: pack.id)
            } catch {
                try? FileManager.default.removeItem(at: outgoing)
                throw error
            }
        } catch { transferErrors[pack.id] = L10n.errorMessage(error) }
    }

    func removeFromWatch(_ id: DictionaryID) {
        guard !busy.contains(id) else { return }
        transferErrors[id] = nil
        cancelTransport(id)
        _ = nextCommand(id, pack: nil)
        do { try publishCommands() }
        catch { transferErrors[id] = L10n.errorMessage(error) }
    }

    func removeFromPhone(_ id: DictionaryID) async {
        // Watch transfers use independent snapshots, so deleting the phone copy
        // does not corrupt a queued transfer or delete the Watch's copy.
        do { try await library.remove(id); await refreshLocal() }
        catch { transferErrors[id] = L10n.errorMessage(error) }
    }

    func status(for id: DictionaryID) -> String {
        if let error = transferErrors[id] { return error }
        if busy.contains(id) { return "Preparing transfer…" }
        let desired = commands.first { $0.id == id }
        let acknowledged = watch.commands.first { $0.id == id }
        if desired == acknowledged, let error = watch.errors[id.rawValue] { return error }
        if let desired, desired.pack == nil, desired != acknowledged { return "Removal queued for Watch" }
        if let progress = transfers[id] {
            return progress > 0 ? "Sending to Watch · \(Int(progress * 100))%" : "Queued for Watch"
        }
        if let desired, let pack = desired.pack,
           !watch.installed.contains(where: { $0.pack == pack }) || desired != acknowledged {
            return desired == acknowledged
                ? "Watch hasn’t installed this dictionary yet"
                : "Installation not confirmed · open InstaDict on Watch"
        }
        if watch.installed.contains(where: { $0.pack.id == id }) { return "Installed on Watch" }
        return "Not on Watch"
    }

    func hasPendingCommand(_ id: DictionaryID) -> Bool {
        guard let desired = commands.first(where: { $0.id == id }) else { return false }
        return !watch.hasCompleted(desired)
    }

    private func nextCommand(_ id: DictionaryID, pack: DictionaryPack?) -> PackCommand {
        let largest = (commands + watch.commands).map(\.revision).max() ?? 0
        let revision = max(Int64(Date().timeIntervalSince1970 * 1000), largest + 1)
        let command = PackCommand(id: id, revision: revision, pack: pack)
        commands.removeAll { $0.id == id }
        commands.append(command)
        UserDefaults.standard.set(try? JSONEncoder().encode(commands), forKey: Self.commandsKey)
        return command
    }

    private func publishCommands() throws {
        guard let session, session.activationState == .activated else { return }
        try session.updateApplicationContext(["commands": try JSONEncoder().encode(commands)])
    }

    private func observe(_ transfer: WCSessionFileTransfer, id: DictionaryID) {
        transfers[id] = transfer.progress.fractionCompleted
        let key = ObjectIdentifier(transfer)
        observations[key] = transfer.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            let fraction = progress.fractionCompleted
            guard let owner = self else { return }
            Task { @MainActor in
                guard owner.observations[key] != nil else { return }
                owner.transfers[id] = fraction
            }
        }
    }

    private func cancelTransport(_ id: DictionaryID) {
        for transfer in session?.outstandingFileTransfers ?? [] {
            guard Self.command(from: transfer.file.metadata)?.id == id else { continue }
            observations[ObjectIdentifier(transfer)] = nil
            transfer.cancel()
            try? FileManager.default.removeItem(at: transfer.file.fileURL)
        }
        transfers[id] = nil
    }
    #endif

    nonisolated private static func command(from metadata: [String: Any]?) -> PackCommand? {
        guard let data = metadata?["command"] as? Data else { return nil }
        return try? JSONDecoder().decode(PackCommand.self, from: data)
    }

    private func activated(_ error: Error?) {
        guard let session else { return }
        isActivated = session.activationState == .activated
        if let error { connectionMessage = L10n.errorMessage(error); return }
        #if os(iOS)
        connectionMessage = !session.isPaired ? "Pair an Apple Watch to sync dictionaries."
            : !session.isWatchAppInstalled ? "Install InstaDict on your Apple Watch to sync dictionaries."
            : session.isReachable ? "Apple Watch is connected" : "Apple Watch is paired · transfers can continue in the background."
        for transfer in session.outstandingFileTransfers {
            if let command = Self.command(from: transfer.file.metadata) { observe(transfer, id: command.id) }
        }
        try? publishCommands()
        checkWatchStatus()
        #else
        connectionMessage = "Download here or send dictionaries from iPhone."
        Task { await refreshLocal() }
        #endif
        receiveContext(session.receivedApplicationContext)
        #if os(watchOS)
        recoverInbox()
        #endif
    }

    private func receiveContext(_ context: [String: Any]) {
        #if os(iOS)
        if let data = context["inventory"] as? Data,
           let snapshot = try? JSONDecoder().decode(WatchLibraryStatus.self, from: data) {
            receiveInventory(snapshot)
        }
        #else
        if let data = context["commands"] as? Data,
           let commands = try? JSONDecoder().decode([PackCommand].self, from: data) {
            Task {
                do { try await library.apply(commands) }
                catch { connectionMessage = L10n.errorMessage(error) }
                await refreshLocal()
            }
        }
        #endif
    }

    #if os(watchOS)
    func finishBackgroundTransfer(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        start()
        Task {
            // Allow queued delegate events to enter the main actor before deciding
            // that a WatchConnectivity wake-up has finished its work.
            try? await Task.sleep(for: .seconds(1))
            for _ in 0..<50 {
                if isActivated, session?.hasContentPending == false, busy.isEmpty { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            await refreshLocal()
            task.setTaskCompletedWithSnapshot(false)
        }
    }

    private func publishWatchStatus() {
        guard let session, session.activationState == .activated,
              let data = try? JSONEncoder().encode(local) else { return }
        try? session.updateApplicationContext(["inventory": data])
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil, errorHandler: { _ in
                // The application context remains the background fallback.
            })
        }
    }

    private func recoverInbox() {
        let folder = DictionaryLibrary.root.appending(path: "Inbox")
        for url in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "sqlite" {
            let metadata = url.appendingPathExtension("json")
            if let data = try? Data(contentsOf: metadata), let command = try? JSONDecoder().decode(PackCommand.self, from: data) {
                installReceived(url, command: command)
            }
        }
    }

    private func installReceived(_ url: URL, command: PackCommand) {
        guard let pack = command.pack, installingFiles.insert(url).inserted else { return }
        busy.insert(pack.id)
        Task {
            defer {
                installingFiles.remove(url)
                busy.remove(pack.id)
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.removeItem(at: url.appendingPathExtension("json"))
            }
            do { try await library.install(url, pack: pack, command: command) }
            catch PackError.staleTransfer { /* A newer command already won. */ }
            catch { try? await library.recordError(L10n.errorMessage(error), for: pack.id, command: command) }
            await refreshLocal()
        }
    }
    #endif

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.activated(error) }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.activated(nil) }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        // Copy only the encoded payload across the actor boundary.
        let commands = applicationContext["commands"] as? Data
        let inventory = applicationContext["inventory"] as? Data
        Task { @MainActor in
            var context: [String: Any] = [:]
            context["commands"] = commands
            context["inventory"] = inventory
            self.receiveContext(context)
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        #if os(iOS)
        guard let snapshot = try? JSONDecoder().decode(WatchLibraryStatus.self, from: messageData) else { return }
        Task { @MainActor in self.receiveInventory(snapshot) }
        #endif
    }
    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                             replyHandler: @escaping (Data) -> Void) {
        #if os(watchOS)
        Task { @MainActor in
            let reply: DictionaryStatusReply
            do {
                let commands = try JSONDecoder().decode([PackCommand].self, from: messageData)
                try await self.library.apply(commands)
                await self.refreshLocal()
                reply = DictionaryStatusReply(inventory: try await self.library.snapshot())
            } catch { reply = DictionaryStatusReply(error: L10n.errorMessage(error)) }
            replyHandler((try? JSONEncoder().encode(reply)) ?? Data())
        }
        #else
        replyHandler(Data())
        #endif
    }
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if os(watchOS)
        guard let command = Self.command(from: file.metadata), command.pack != nil else { return }
        do {
            // WCSession deletes its temporary file when this delegate returns.
            let folder = DictionaryLibrary.root.appending(path: "Inbox")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let saved = folder.appending(path: UUID().uuidString + ".sqlite")
            try FileManager.default.copyItem(at: file.fileURL, to: saved)
            try JSONEncoder().encode(command).write(to: saved.appendingPathExtension("json"), options: .atomic)
            Task { @MainActor in self.installReceived(saved, command: command) }
        } catch {
            let message = L10n.errorMessage(error)
            Task { @MainActor in
                // File delivery can precede its application context. Associate
                // staging failures with the command so iPhone can display them.
                try? await self.library.apply([command])
                try? await self.library.recordError(message, for: command.id, command: command)
                await self.refreshLocal()
            }
        }
        #endif
    }
    #if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        Task { @MainActor in
            self.watch = .init()
            UserDefaults.standard.removeObject(forKey: "lastWatchLibrary.v2")
            session.activate()
        }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.activated(nil) }
    }
    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let command = Self.command(from: fileTransfer.file.metadata) else { return }
        Task { @MainActor in
            self.observations[ObjectIdentifier(fileTransfer)] = nil
            // Ignore completion of a canceled, superseded transfer.
            if self.commands.first(where: { $0.id == command.id }) == command {
                self.transfers[command.id] = nil
                if let error { self.transferErrors[command.id] = L10n.errorMessage(error) }
                self.checkWatchStatus()
            }
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        }
    }
    #endif
}
