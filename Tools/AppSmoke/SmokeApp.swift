import SwiftUI

/// A separate simulator app exercises the shipping downloader against the live
/// catalog. It is never included in either InstaDict target or TestFlight.
@main struct DictionarySmokeApp: App {
    @State private var status = "Testing downloads…"
    var body: some Scene {
        WindowGroup {
            Text(status).padding().task {
                do {
                    let checks = try await runChecks()
                    status = "Passed \(checks.count) checks"
                    write(["passed": true, "checks": checks])
                } catch {
                    status = error.localizedDescription
                    write(["passed": false, "error": String(describing: error)])
                }
            }
        }
    }

    @MainActor private func runChecks() async throws -> [String] {
        let downloads = DictionaryDownloads.shared
        let sync = DictionarySync.shared
        sync.start()
        downloads.start()
        for _ in 0..<100 where downloads.isRestoring { try await Task.sleep(for: .milliseconds(100)) }
        try require(!downloads.isRestoring, "Background task restoration timed out")
        let mirror = "https://pub-d3dd17f1b84247f39bef689c3df0431d.r2.dev/manifest.json"
        if ProcessInfo.processInfo.arguments.contains("--relaunch") {
            try require(downloads.sourceURL.absoluteString == mirror, "Custom source did not survive relaunch")
            let result = try await DictionaryLibrary.shared.lookup("中文", in: .chineseEnglish)
            try require(result.entry?.pinyin == "zhōng wén", "Installed dictionary did not survive relaunch")
            return ["source persistence", "offline lookup after relaunch"]
        }

        try await downloads.changeSource(to: DictionaryCatalog.remoteURL.absoluteString)
        try require(downloads.packs.count == 3, "Default catalog failed")
        try await downloads.changeSource(to: mirror)
        let saved = downloads.sourceURL
        let savedPacks = downloads.packs
        do {
            try await downloads.changeSource(to: "https://instadict.marsinside.com/missing-catalog.json")
            throw CheckFailure(message: "Missing catalog unexpectedly succeeded")
        } catch is CheckFailure { throw CheckFailure(message: "Missing catalog unexpectedly succeeded") }
        catch {}
        try require(downloads.sourceURL == saved && downloads.packs == savedPacks, "Failed source replaced the working catalog")
        guard let pack = downloads.packs.first(where: { $0.id == .chineseEnglish }) else {
            throw CheckFailure(message: "No Chinese–English pack")
        }
        await downloads.download(pack)
        let deadline = Date().addingTimeInterval(240)
        while downloads.progress[pack.id] != nil || downloads.verifying.contains(pack.id) {
            try require(Date() < deadline, "Download/install timed out")
            try await Task.sleep(for: .milliseconds(200))
        }
        try require(downloads.errors[pack.id] == nil, downloads.errors[pack.id] ?? "Download failed")
        let snapshot = try await DictionaryLibrary.shared.snapshot()
        try require(snapshot.installed.contains { $0.pack.hasSameContent(as: pack) }, "Downloaded pack was not installed")
        let result = try await DictionaryLibrary.shared.lookup("中文", in: .chineseEnglish)
        try require(result.entry?.pinyin == "zhōng wén", "Downloaded dictionary lookup failed")
        #if os(watchOS)
        try require(snapshot.commands.contains { $0.pack == pack && snapshot.hasCompleted($0) }, "Direct Watch install was not acknowledged")
        #else
        try require(sync.transfers.isEmpty && sync.transferErrors.isEmpty, "iPhone download tried to send automatically")
        #endif
        return ["default HTTPS catalog", "custom HTTPS catalog", "failed source preserves saved catalog",
                "background URLSession download", "verified install", "Chinese lookup with tone marks"]
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure(message: message) }
    }

    private func write(_ result: [String: Any]) {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appending(path: "smoke.json"), options: .atomic)
    }
}

private struct CheckFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
