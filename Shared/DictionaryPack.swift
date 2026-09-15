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

    /// Hosting can change without making the installed bytes obsolete.
    func hasSameContent(as other: Self) -> Bool {
        id == other.id && version == other.version && schemaVersion == other.schemaVersion &&
            byteCount == other.byteCount && entryCount == other.entryCount &&
            sha256.lowercased() == other.sha256.lowercased()
    }

    func validate() throws {
        guard DictionarySchema.supported.contains(schemaVersion), (1...500_000_000).contains(byteCount),
              entryCount > 0, entryCount <= 2_000_000,
              !version.isEmpty, version.count <= 40,
              version.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }),
              sha256.count == 64, sha256.allSatisfy(\.isHexDigit),
              DictionaryDownloadSource.isSecureURL(url),
              url.pathExtension == "sqlite" else { throw PackError.invalidCatalog }
    }

    /// URLSession reassembles resumed range downloads before delivering the file.
    /// A 206 is successful only when that delivered file has the full catalog size;
    /// installation still verifies its SHA-256 and SQLite contents.
    func validateDownload(statusCode: Int, fileByteCount: Int64) throws {
        guard statusCode == 200 || statusCode == 206 else { throw PackError.http(statusCode) }
        guard fileByteCount == byteCount else { throw PackError.sizeMismatch }
    }

    func resolvingURL(relativeTo base: URL) -> Self {
        Self(id: id, version: version, schemaVersion: schemaVersion, entryCount: entryCount,
             byteCount: byteCount, sha256: sha256,
             url: URL(string: url.relativeString, relativeTo: base)?.absoluteURL ?? url)
    }
}

struct DictionaryCatalog: Codable, Sendable {
    static let remoteURL = URL(string: "https://fastcdn.candyrect.com/instadict/manifest.json")!
    static let previousDefaultURL = URL(string: "https://instadict.marsinside.com/manifest.json")!

    /// A temporarily stale default CDN must not replace the current storage format.
    func requiringCurrentFormat(minimum: Self) throws -> Self {
        guard schemaVersion >= minimum.schemaVersion,
              packs.allSatisfy({ pack in
                  pack.schemaVersion >= (minimum.packs.first { $0.id == pack.id }?.schemaVersion ?? 0)
              }) else { throw SourceError.outdatedCatalog }
        return self
    }
    let schemaVersion: Int
    let packs: [DictionaryPack]

    /// An app update can introduce a new storage schema while an older catalog
    /// remains cached on iPhone. Prefer the bundled schema upgrade in that case.
    func preferringCached(_ cached: Self?) -> Self {
        guard let cached, cached.schemaVersion >= schemaVersion else { return self }
        return cached
    }

    static func bundled() throws -> Self {
        guard let url = Bundle.main.url(forResource: "DictionaryCatalog", withExtension: "json") else {
            throw PackError.invalidCatalog
        }
        return try decode(Data(contentsOf: url), relativeTo: remoteURL)
    }

    static func decode(_ data: Data, relativeTo base: URL? = nil) throws -> Self {
        let decoded = try JSONDecoder().decode(Self.self, from: data)
        let catalog = Self(schemaVersion: decoded.schemaVersion,
                           packs: decoded.packs.map { pack in base.map { pack.resolvingURL(relativeTo: $0) } ?? pack })
        guard DictionarySchema.supported.contains(catalog.schemaVersion), catalog.packs.count == 3,
              Set(catalog.packs.map(\.id)) == Set(DictionaryID.allCases) else { throw PackError.invalidCatalog }
        try catalog.packs.forEach { try $0.validate() }
        return catalog
    }
}

enum DictionaryDownloadSource {
    static func isSecureURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && !(url.host ?? "").isEmpty &&
            url.user == nil && url.password == nil && url.fragment == nil
    }

    /// Accept a manifest URL or a folder containing manifest.json.
    static func normalize(_ input: String) throws -> URL {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace), !text.hasPrefix("/") else {
            throw SourceError.invalidURL
        }
        let address = text.contains("://") ? text : "https://" + text
        guard var url = URL(string: address), isSecureURL(url),
              let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix("."),
              !host.contains("..") else { throw SourceError.invalidURL }
        if url.pathExtension.isEmpty { url = url.appending(path: "manifest.json") }
        guard url.pathExtension.lowercased() == "json" else { throw SourceError.invalidURL }
        return url
    }
}

/// Persist source and catalog together so a failed switch cannot mix two servers.
struct DictionaryCatalogSelection: Codable {
    let source: URL
    let catalog: DictionaryCatalog
    var isDefault: Bool? = nil

    var usesDefaultSource: Bool {
        isDefault ?? (source == DictionaryCatalog.remoteURL || source == DictionaryCatalog.previousDefaultURL)
    }
    var effectiveSource: URL { usesDefaultSource ? DictionaryCatalog.remoteURL : source }

    static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard try DictionaryDownloadSource.normalize(value.source.absoluteString) == value.source else {
            throw SourceError.invalidURL
        }
        _ = try DictionaryCatalog.decode(JSONEncoder().encode(value.catalog))
        return value
    }
}

enum SourceError: Error, LocalizedError {
    case invalidURL, busy, outdatedCatalog
    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a website address or HTTPS catalog URL, without a username, password or fragment."
        case .outdatedCatalog: "The default source has an older dictionary format. Try refreshing later."
        case .busy: "Wait for downloads and catalog updates to finish before changing the source."
        }
    }
}

struct InstalledPack: Codable, Equatable, Sendable {
    let pack: DictionaryPack
    let filename: String
}

struct PackCommand: Codable, Equatable, Sendable {
    let id: DictionaryID
    // arm64_32 watches have 32-bit Int; epoch milliseconds require 64 bits.
    let revision: Int64
    let pack: DictionaryPack? // nil means remove from Watch

    static func merging(_ current: [Self], with incoming: [Self]) -> [Self] {
        var result = current
        for command in incoming where command.revision > 0 {
            if let previous = result.first(where: { $0.id == command.id }), previous.revision >= command.revision { continue }
            result.removeAll { $0.id == command.id }
            result.append(command)
        }
        return result
    }
}

struct WatchLibraryStatus: Codable, Equatable, Sendable {
    var installed: [InstalledPack] = []
    var commands: [PackCommand] = []
    var errors: [String: String] = [:]

    func hasCompleted(_ command: PackCommand) -> Bool {
        guard commands.first(where: { $0.id == command.id }) == command,
              errors[command.id.rawValue] == nil else { return false }
        if let pack = command.pack { return installed.contains { $0.pack == pack } }
        return !installed.contains { $0.pack.id == command.id }
    }
}

struct DictionaryStatusReply: Codable, Sendable {
    var inventory: WatchLibraryStatus?
    var error: String?
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
        case .missing(let id): "Download \(id.title) in Settings."
        case .http(404): "This dictionary hasn’t been published on the download server yet. Try again later."
        case .http(let code): "The download server returned an error (\(code)). Please try again."
        }
    }
}
