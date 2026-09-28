import Foundation
import Observation

/// A locally stored Word Book entry. Lookup counts are retained only to support
/// the optional automatic-add rule; no lookup history or query list is uploaded.
struct WordBookEntry: Codable, Identifiable, Equatable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case word, count, lastLookup, isInBook, lastModified
    }
    let word: String
    var count: Int
    var lastLookup: Date
    var isInBook: Bool
    var lastModified: Date

    var id: String { word }

    init(word: String, count: Int, lastLookup: Date, isInBook: Bool = false, lastModified: Date? = nil) {
        self.word = word
        self.count = count
        self.lastLookup = lastLookup
        self.isInBook = isInBook
        self.lastModified = lastModified ?? lastLookup
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        word = try values.decode(String.self, forKey: .word)
        count = try values.decode(Int.self, forKey: .count)
        lastLookup = try values.decode(Date.self, forKey: .lastLookup)
        // Old ReviewStore records did not have this field. They were only
        // persisted after reaching two lookups, so migrate them into the book.
        let savedFlag: Bool? = try values.decodeIfPresent(Bool.self, forKey: CodingKeys.isInBook)
        isInBook = savedFlag ?? (count >= 2)
        lastModified = try values.decodeIfPresent(Date.self, forKey: .lastModified) ?? lastLookup
    }
}

@MainActor @Observable
final class WordBookStore {
    static let shared = WordBookStore()
    static let storageKey = "wordBook.entries.v1"
    static let didChangeNotification = Notification.Name("InstaDict.WordBookStore.didChange")
    private static let legacyStorageKey = "review.words.v1"
    static let automaticAddCount = 2

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var records: [WordBookEntry]

    var words: [WordBookEntry] {
        records
            .filter(\.isInBook)
            .sorted {
                if $0.lastLookup != $1.lastLookup { return $0.lastLookup > $1.lastLookup }
                return $0.word.localizedCaseInsensitiveCompare($1.word) == .orderedAscending
            }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let data = defaults.data(forKey: Self.storageKey) ?? defaults.data(forKey: Self.legacyStorageKey)
        records = data.flatMap { try? JSONDecoder().decode([WordBookEntry].self, from: $0) } ?? []
        if defaults.data(forKey: Self.storageKey) == nil, let data {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    /// Records every successful lookup and optionally adds the word once it
    /// reaches the selected lookup threshold. Existing book entries remain in
    /// the book when automatic adding is disabled.
    func recordLookup(_ word: String, at date: Date = .now, autoAddAfter threshold: Int? = 2) {
        let normalized = LookupQuery.normalize(word)
        guard !normalized.isEmpty else { return }
        if let index = records.firstIndex(where: { $0.word == normalized }) {
            records[index].count += 1
            records[index].lastLookup = date
            records[index].lastModified = date
            if let threshold, threshold > 0, records[index].count >= threshold {
                records[index].isInBook = true
            }
        } else {
            records.append(WordBookEntry(word: normalized, count: 1, lastLookup: date, lastModified: date))
        }
        save()
    }

    @available(*, deprecated, message: "Use recordLookup(_:at:autoAddAfter:) instead")
    func recordLookup(_ word: String, at date: Date = .now, autoAdd: Bool) {
        recordLookup(word, at: date, autoAddAfter: autoAdd ? 2 : nil)
    }

    func add(_ word: String, at date: Date = .now) {
        let normalized = LookupQuery.normalize(word)
        guard !normalized.isEmpty else { return }
        if let index = records.firstIndex(where: { $0.word == normalized }) {
            records[index].isInBook = true
            records[index].lastLookup = date
            records[index].lastModified = date
        } else {
            records.append(WordBookEntry(word: normalized, count: 0, lastLookup: date, isInBook: true, lastModified: date))
        }
        save()
    }

    func contains(_ word: String) -> Bool {
        let normalized = LookupQuery.normalize(word)
        return records.contains { $0.word == normalized && $0.isInBook }
    }

    func addEligibleWords(after threshold: Int = 2) {
        guard threshold > 0 else { return }
        var changed = false
        for index in records.indices where records[index].count >= threshold && !records[index].isInBook {
            records[index].isInBook = true
            records[index].lastModified = .now
            changed = true
        }
        if changed { save() }
    }

    func remove(_ word: WordBookEntry) {
        guard let index = records.firstIndex(where: { $0.id == word.id }) else { return }
        records[index].isInBook = false
        records[index].lastModified = .now
        save()
    }

    func clear() {
        guard !records.isEmpty else { return }
        let now = Date.now
        for index in records.indices {
            records[index].isInBook = false
            records[index].lastModified = now
        }
        save()
    }

    /// Encodes the complete local state for WatchConnectivity. Hidden records
    /// are included so removals and clears remain removals after reconnection.
    func syncData() -> Data? {
        try? JSONEncoder().encode(records)
    }

    /// Merges a companion snapshot using per-word last-write-wins metadata.
    /// Counts use the larger value so a lookup recorded on either device is kept.
    @discardableResult
    func mergeSyncData(_ data: Data) -> Bool {
        guard let incoming = try? JSONDecoder().decode([WordBookEntry].self, from: data) else { return false }
        var changed = false
        for entry in incoming {
            guard let index = records.firstIndex(where: { $0.id == entry.id }) else {
                records.append(entry)
                changed = true
                continue
            }
            let local = records[index]
            let newer = entry.lastModified > local.lastModified
            let merged = WordBookEntry(
                word: entry.word,
                count: max(local.count, entry.count),
                lastLookup: max(local.lastLookup, entry.lastLookup),
                isInBook: newer ? entry.isInBook : local.isInBook,
                lastModified: max(local.lastModified, entry.lastModified)
            )
            if merged != local {
                records[index] = merged
                changed = true
            }
        }
        if changed { save(notify: false) }
        return changed
    }

    private func save(notify: Bool = true) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults.set(data, forKey: Self.storageKey)
        if notify {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
    }
}

// Source compatibility for the previous internal ReviewStore names and data.
typealias ReviewWord = WordBookEntry
typealias ReviewStore = WordBookStore
