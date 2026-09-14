import Foundation

enum DictionarySchema {
    static let supported = 2...3
    static let maximumPayloadBytes = 2_000_000
}

enum DictionaryLanguage: String, Sendable {
    case english
    case chinese
}

struct DictionarySense: Decodable, Equatable, Sendable {
    let definition: String
    let examples: [String]
    let synonyms: [String]
}

struct DictionarySection: Decodable, Equatable, Sendable {
    let partOfSpeech: String
    let senses: [DictionarySense]
}

struct WordForm: Decodable, Equatable, Sendable {
    let label: String
    let word: String
}

struct DictionaryEntry: Decodable, Identifiable, Equatable, Sendable {
    let word: String
    let displayWord: String
    let britishIPA: String?
    let americanIPA: String?
    let pinyin: String?
    let english: [DictionarySection]
    let chinese: [DictionarySection]
    let forms: [WordForm]
    let lemma: String?

    var id: String { word }

    func sections(in language: DictionaryLanguage) -> [DictionarySection] {
        language == .english ? english : chinese
    }
}

struct LookupResult: Sendable {
    let query: String
    let entry: DictionaryEntry?
    let suggestions: [String]
}

enum LookupQuery {
    static func isChinese(_ input: String) -> Bool {
        input.unicodeScalars.contains {
            (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value)
                || (0x20000...0x323AF).contains($0.value)
        }
    }
    /// Watch text entry commonly appends a space. Normalize before *every* lookup,
    /// including retries, suggestions and word-form links. Keep phrase boundaries.
    static func normalize(_ input: String) -> String {
        input
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "‑", with: "-")
            .replacingOccurrences(of: "–", with: "-")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
