import Foundation
import Observation

@MainActor @Observable
final class LookupModel {
    enum State {
        case awaitingInput
        case loading(String)
        case definition(DictionaryEntry, query: String)
        case notFound(String, suggestions: [String])
        case needsPack(DictionaryID)
        case failed(String)
    }

    private(set) var state: State = .awaitingInput
    private(set) var dictionary: DictionaryID = .englishEnglish
    private(set) var lastQuery = ""
    var language: DictionaryLanguage { dictionary == .englishChinese ? .chinese : .english }
    var canSwitchLanguage: Bool { !lastQuery.isEmpty && !LookupQuery.isChinese(lastQuery) }
    private let library: DictionaryLibrary
    private let preferences: LookupPreferences
    private let ratingTracker: RatingPromptTracker
    private let wordBook: WordBookStore
    private var lookupTask: Task<Void, Never>?
    private var requestID = UUID()

    init(library: DictionaryLibrary = .shared, preferences: LookupPreferences? = nil,
         ratingTracker: RatingPromptTracker? = nil, wordBook: WordBookStore? = nil) {
        self.library = library
        self.preferences = preferences ?? .shared
        self.ratingTracker = ratingTracker ?? .shared
        self.wordBook = wordBook ?? .shared
    }

    func lookUp(_ input: String) {
        let query = LookupQuery.normalize(input)
        guard !query.isEmpty else { return }
        search(query, in: LookupQuery.isChinese(query) ? .chineseEnglish : preferences.englishDictionary.dictionaryID,
               countsForRating: true)
    }

    func switchLanguage() {
        guard canSwitchLanguage else { return }
        search(lastQuery, in: dictionary == .englishChinese ? .englishEnglish : .englishChinese)
    }

    func reloadCurrent() {
        if !lastQuery.isEmpty { search(lastQuery, in: dictionary) }
    }

    private func search(_ query: String, in id: DictionaryID, countsForRating: Bool = false) {
        lookupTask?.cancel()
        let request = UUID()
        requestID = request
        lastQuery = query
        dictionary = id
        state = .loading(query)
        lookupTask = Task {
            do {
                let result = try await library.lookup(query, in: id)
                guard !Task.isCancelled, requestID == request else { return }
                if countsForRating {
                    ratingTracker.completedLookup()
                    if let entry = result.entry {
                        let rule = preferences.wordBookAutoAddRule
                        wordBook.recordLookup(entry.word, autoAddAfter: rule == .never ? nil : rule.rawValue)
                    }
                }
                if let entry = result.entry { state = .definition(entry, query: result.query) }
                else { state = .notFound(result.query, suggestions: result.suggestions) }
            } catch {
                guard !Task.isCancelled, requestID == request else { return }
                if case PackError.missing(let missing) = error { state = .needsPack(missing) }
                else { state = .failed(L10n.errorMessage(error)) }
            }
        }
    }
}
