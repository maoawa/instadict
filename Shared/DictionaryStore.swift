import Foundation
import SQLite3
import zlib

/// Called on DictionaryLibrary's actor; each lookup owns a read-only connection.
struct DictionaryStore: Sendable {
    enum StoreError: Error, LocalizedError {
        case missingDatabase
        case unreadableDatabase
        case invalidEntry
        case queryTooLong

        var errorDescription: String? {
            switch self {
            case .missingDatabase, .unreadableDatabase, .invalidEntry:
                "The offline dictionary couldn’t be opened. Try again, or reinstall InstaDict."
            case .queryTooLong:
                "Enter a word or a short phrase of up to 128 characters."
            }
        }
    }

    private let databaseURL: URL?

    init(databaseURL: URL?) {
        self.databaseURL = databaseURL
    }

    func lookup(_ input: String) throws -> LookupResult {
        let query = LookupQuery.normalize(input)
        guard !query.isEmpty else { return LookupResult(query: query, entry: nil, suggestions: []) }
        guard query.count <= 128 else { throw StoreError.queryTooLong }
        guard let databaseURL else { throw StoreError.missingDatabase }

        var database: OpaquePointer?
        let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw StoreError.unreadableDatabase
        }
        defer { sqlite3_close(database) }
        sqlite3_exec(database, "PRAGMA cache_size = -256", nil, nil, nil)

        if let entry = try readEntry(query, database: database) {
            return LookupResult(query: query, entry: entry, suggestions: [])
        }
        let base = try withStatement("SELECT word FROM aliases WHERE alias = ? LIMIT 1", [query], database: database) { statement in
            try step(statement) ? string(statement, 0) : nil
        }
        if let base, let entry = try readEntry(base, database: database) {
            return LookupResult(query: query, entry: entry, suggestions: [])
        }
        return LookupResult(query: query, entry: nil, suggestions: try suggestions(for: query, database: database))
    }

    private func readEntry(_ word: String, database: OpaquePointer) throws -> DictionaryEntry? {
        try withStatement("SELECT payload, payload_size FROM entries WHERE word = ?", [word], database: database) { statement in
            guard try step(statement) else { return nil }
            let size = Int(sqlite3_column_int(statement, 1))
            // Validate lengths before allocation, even though the pack is read-only.
            guard (1...2_000_000).contains(size), let source = sqlite3_column_blob(statement, 0) else {
                throw StoreError.invalidEntry
            }
            var data = Data(count: size)
            var outputSize = uLongf(size)
            let status = data.withUnsafeMutableBytes { destination in
                uncompress(destination.bindMemory(to: Bytef.self).baseAddress, &outputSize,
                           source.assumingMemoryBound(to: Bytef.self), uLong(sqlite3_column_bytes(statement, 0)))
            }
            guard status == Z_OK, outputSize == size,
                  let entry = try? JSONDecoder().decode(DictionaryEntry.self, from: data) else {
                throw StoreError.invalidEntry
            }
            return entry
        }
    }

    private func suggestions(for query: String, database: OpaquePointer) throws -> [String] {
        var candidates: [String: Int] = [:]
        let letters = Array(query)
        // Bound the work for long phrases; indexed exact variants correct common
        // missing letters, substitutions and transpositions without scanning the pack.
        if (2...24).contains(letters.count), letters.allSatisfy({ $0.isASCII && $0.isLetter }) {
            let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
            var variants = Set<String>()
            for index in letters.indices {
                var deleted = letters
                deleted.remove(at: index)
                variants.insert(String(deleted))
                for letter in alphabet {
                    var replaced = letters
                    replaced[index] = letter
                    variants.insert(String(replaced))
                }
                if index + 1 < letters.count {
                    var swapped = letters
                    swapped.swapAt(index, index + 1)
                    variants.insert(String(swapped))
                }
            }
            for index in 0...letters.count {
                for letter in alphabet {
                    var inserted = letters
                    inserted.insert(letter, at: index)
                    variants.insert(String(inserted))
                }
            }
            let words = variants.sorted()
            for start in stride(from: 0, to: words.count, by: 400) {
                let batch = Array(words[start..<min(start + 400, words.count)])
                let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
                try withStatement("SELECT word, rank FROM entries WHERE word IN (\(placeholders))", batch, database: database) { statement in
                    while try step(statement) {
                        if let word = string(statement, 0) { candidates[word] = Int(sqlite3_column_int(statement, 1)) }
                    }
                }
            }
        }
        var matches = candidates.keys.sorted { (candidates[$0]!, $0) < (candidates[$1]!, $1) }
        if matches.count < 5, query.count >= 2 {
            try withStatement(
                "SELECT word FROM entries WHERE word >= ? AND word < ? ORDER BY rank, word LIMIT 5",
                [query, query + "\u{10FFFF}"], database: database
            ) { statement in
                while try step(statement) {
                    if let word = string(statement, 0), !matches.contains(word) { matches.append(word) }
                }
            }
        }
        return Array(matches.prefix(5))
    }

    private func withStatement<T>(_ sql: String, _ values: [String], database: OpaquePointer,
                                  body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StoreError.unreadableDatabase
        }
        defer { sqlite3_finalize(statement) }
        for (index, value) in values.enumerated() {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                throw StoreError.unreadableDatabase
            }
        }
        return try body(statement)
    }

    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw StoreError.unreadableDatabase
        }
    }

    private func string(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: bytes)
    }
}
