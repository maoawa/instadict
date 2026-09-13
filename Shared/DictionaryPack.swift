import Foundation

enum DictionaryID: String, Codable, CaseIterable, Identifiable, Sendable {
    case englishEnglish = "english-english"
    case englishChinese = "english-chinese"
    case chineseEnglish = "chinese-english"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .englishEnglish: "English–English"
        case .englishChinese: "English–Chinese"
        case .chineseEnglish: "Chinese–English"
        }
    }
    var subtitle: String {
        switch self {
        case .englishEnglish: "Definitions, examples and word forms"
        case .englishChinese: "English words with Chinese meanings"
        case .chineseEnglish: "Chinese words, pinyin and English meanings"
        }
    }
    var sourceSummary: String {
        switch self {
        case .englishEnglish: "WordNet · ECDICT · ipa-dict"
        case .englishChinese: "ECDICT · ipa-dict"
        case .chineseEnglish: "CC-CEDICT · MDBG"
        }
    }
}

struct DictionaryPack: Codable, Identifiable, Equatable, Sendable {
    let id: DictionaryID
    let version: String
    let schemaVersion: Int
    let entryCount: Int
    let byteCount: Int64
    let sha256: String
    let url: URL

    func validate() throws {
        guard schemaVersion == 2, (1...500_000_000).contains(byteCount),
              entryCount > 0, entryCount <= 2_000_000,
              !version.isEmpty, version.count <= 40,
              version.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              sha256.count == 64, sha256.allSatisfy(\.isHexDigit),
              url.scheme == "https", url.host == "fastcdn.candyrect.com",
              url.path.hasPrefix("/instadict/"), url.pathExtension == "sqlite",
              url.user == nil, url.password == nil else { throw PackError.invalidCatalog }
    }
}

struct DictionaryCatalog: Codable, Sendable {
    static let remoteURL = URL(string: "https://fastcdn.candyrect.com/instadict/manifest.json")!
    let schemaVersion: Int
    let packs: [DictionaryPack]

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "DictionaryCatalog", withExtension: "json") else {
            throw PackError.invalidCatalog
        }
        return try decode(Data(contentsOf: url))
    }

    static func decode(_ data: Data) throws -> Self {
        let catalog = try JSONDecoder().decode(Self.self, from: data)
        guard catalog.schemaVersion == 2, catalog.packs.count == 3,
              Set(catalog.packs.map(\.id)) == Set(DictionaryID.allCases) else { throw PackError.invalidCatalog }
        try catalog.packs.forEach { try $0.validate() }
        return catalog
    }
}

struct InstalledPack: Codable, Equatable, Sendable {
    let pack: DictionaryPack
    let filename: String
}

struct PackCommand: Codable, Equatable, Sendable {
    let id: DictionaryID
    let revision: Int
    let pack: DictionaryPack? // nil means remove from Watch
}

struct WatchLibraryStatus: Codable, Equatable, Sendable {
    var installed: [InstalledPack] = []
    var commands: [PackCommand] = []
    var errors: [String: String] = [:]
}

enum PackError: Error, LocalizedError {
    case invalidCatalog, sizeMismatch, checksumMismatch, invalidDatabase, staleTransfer
    case missing(DictionaryID)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidCatalog: "The dictionary catalog isn’t compatible with this version of InstaDict."
        case .sizeMismatch: "The download is incomplete. Please download the dictionary again."
        case .checksumMismatch: "The dictionary didn’t pass verification. Please download it again."
        case .invalidDatabase: "The dictionary file is damaged or incompatible. Please download it again."
        case .staleTransfer: "This transfer was replaced or canceled."
        case .missing(let id): "Send \(id.title) from InstaDict on your iPhone."
        case .http(404): "This dictionary hasn’t been published on the download server yet. Try again later."
        case .http(let code): "The download server returned an error (\(code)). Please try again."
        }
    }
}
