import CryptoKit
import Foundation
import SQLite3

/// Owns installed files, receipts and Watch commands. Validation and disk work
/// are serialized here, so a late transfer cannot resurrect a removed pack.
actor DictionaryLibrary {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "InstaDict", directoryHint: .isDirectory)
    static let shared = DictionaryLibrary(root: root)

    private let root: URL
    private var loaded = false
    private var state = WatchLibraryStatus()

    init(root: URL) { self.root = root }

    func snapshot() throws -> WatchLibraryStatus {
        try load()
        return state
    }

    func file(for id: DictionaryID) throws -> URL? {
        try load()
        return state.installed.first(where: { $0.pack.id == id }).map { root.appending(path: $0.filename) }
    }

    func lookup(_ query: String, in id: DictionaryID) throws -> LookupResult {
        guard let url = try file(for: id) else { throw PackError.missing(id) }
        // SQLite opens its own read-only connection. Installed filenames are immutable.
        return try DictionaryStore(databaseURL: url).lookup(query)
    }

    func apply(_ commands: [PackCommand]) throws {
        try load()
        for command in commands {
            guard command.revision > 0, command.pack == nil || command.pack?.id == command.id else {
                throw PackError.invalidCatalog
            }
            try command.pack?.validate()
            let previous = state.commands.first { $0.id == command.id }
            if let previous, previous.revision >= command.revision { continue }
            let before = state
            state.commands.removeAll { $0.id == command.id }
            state.commands.append(command)
            state.errors[command.id.rawValue] = nil
            if command.pack == nil { state.installed.removeAll { $0.pack.id == command.id } }
            do { try persist() } catch { state = before; throw error }
            if command.pack == nil {
                for old in before.installed where old.pack.id == command.id {
                    try? FileManager.default.removeItem(at: root.appending(path: old.filename))
                }
            }
        }
    }

    @discardableResult
    func install(_ source: URL, pack: DictionaryPack, command: PackCommand? = nil) throws -> InstalledPack {
        try load()
        try pack.validate()
        if let command {
            guard command.pack == pack, command.id == pack.id else { throw PackError.invalidCatalog }
            try apply([command])
            guard state.commands.first(where: { $0.id == pack.id }) == command else { throw PackError.staleTransfer }
        }
        try Self.validate(source, pack: pack)
        let filename = "\(pack.id.rawValue)-\(pack.version)-\(pack.sha256.prefix(12)).sqlite"
        let destination = root.appending(path: filename)
        let staging = root.appending(path: UUID().uuidString + ".incoming")
        let previous = state
        do {
            if !FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.copyItem(at: source, to: staging)
                try FileManager.default.moveItem(at: staging, to: destination)
            }
            let receipt = InstalledPack(pack: pack, filename: filename)
            state.installed.removeAll { $0.pack.id == pack.id }
            state.installed.append(receipt)
            state.errors[pack.id.rawValue] = nil
            try persist() // Atomic receipt replacement makes the new file visible.
            for old in previous.installed where old.pack.id == pack.id && old.filename != filename {
                try? FileManager.default.removeItem(at: root.appending(path: old.filename))
            }
            return receipt
        } catch {
            state = previous
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    func remove(_ id: DictionaryID) throws {
        try load()
        let previous = state
        state.installed.removeAll { $0.pack.id == id }
        state.errors[id.rawValue] = nil
        do { try persist() } catch { state = previous; throw error }
        for old in previous.installed where old.pack.id == id {
            try? FileManager.default.removeItem(at: root.appending(path: old.filename))
        }
    }

    func recordError(_ error: String, for id: DictionaryID, command: PackCommand? = nil) throws {
        try load()
        if let command, state.commands.first(where: { $0.id == id }) != command { return }
        state.errors[id.rawValue] = error
        try persist()
    }

    private func load() throws {
        guard !loaded else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var folder = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        let index = root.appending(path: "library.json")
        if FileManager.default.fileExists(atPath: index.path) {
            state = try JSONDecoder().decode(WatchLibraryStatus.self, from: Data(contentsOf: index))
            // Never trust a receipt to escape the library directory.
            state.installed = state.installed.filter {
                $0.filename == URL(fileURLWithPath: $0.filename).lastPathComponent &&
                FileManager.default.fileExists(atPath: root.appending(path: $0.filename).path)
            }
        }
        loaded = true
    }

    private func persist() throws {
        try JSONEncoder().encode(state).write(to: root.appending(path: "library.json"), options: .atomic)
    }

    static func validate(_ url: URL, pack: DictionaryPack) throws {
        try pack.validate()
        let actualSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        guard actualSize?.int64Value == pack.byteCount else { throw PackError.sizeMismatch }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == pack.sha256.lowercased() else {
            throw PackError.checksumMismatch
        }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw PackError.invalidDatabase
        }
        defer { sqlite3_close(database) }
        func scalar(_ sql: String) throws -> String {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw PackError.invalidDatabase
            }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else {
                throw PackError.invalidDatabase
            }
            return String(cString: text)
        }
        guard try scalar("PRAGMA quick_check") == "ok",
              try scalar("PRAGMA user_version") == "2",
              try scalar("SELECT value FROM metadata WHERE key='pack_id'") == pack.id.rawValue,
              try scalar("SELECT value FROM metadata WHERE key='version'") == pack.version,
              try scalar("SELECT count(*) FROM entries") == String(pack.entryCount),
              try scalar("SELECT count(*) FROM aliases") != "" else { throw PackError.invalidDatabase }
        guard try scalar("SELECT count(*) FROM entries WHERE payload_size < 1 OR payload_size > 2000000 OR length(payload) < 1") == "0" else {
            throw PackError.invalidDatabase
        }
        let firstWord = try scalar("SELECT word FROM entries ORDER BY word LIMIT 1")
        guard let entry = try? DictionaryStore(databaseURL: url).lookup(firstWord).entry,
              entry.word == firstWord, !entry.english.isEmpty || !entry.chinese.isEmpty else { throw PackError.invalidDatabase }
    }
}
