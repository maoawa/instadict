import CryptoKit
import Foundation
import SQLite3
import Testing
import zlib
@testable import InstaDictCore

private let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let distribution = project.appending(path: "Distribution/Dictionaries")
private func catalog() throws -> DictionaryCatalog {
    try DictionaryCatalog.decode(Data(contentsOf: distribution.appending(path: "manifest.json")))
}
private func pack(_ id: DictionaryID) throws -> DictionaryPack { try #require(catalog().packs.first { $0.id == id }) }
private func file(_ id: DictionaryID) throws -> URL { try distribution.appending(path: pack(id).url.lastPathComponent) }

@Test(arguments: ["hello", "hello ", "hello   ", " HELLO ", "\nHello\t", "hello\u{00a0}", "hello\u{3000}"])
func watchKeyboardWhitespace(_ input: String) throws {
    let result = try DictionaryStore(databaseURL: file(.englishEnglish)).lookup(input)
    #expect(result.query == "hello")
    #expect(result.entry?.word == "hello")
    #expect(result.entry?.english.isEmpty == false)
    #expect(result.entry?.chinese.isEmpty == true)
    #expect(result.entry?.britishIPA != nil)
    #expect(result.entry?.americanIPA != nil)
}

@Test func independentPacks() throws {
    let english = try DictionaryStore(databaseURL: file(.englishEnglish)).lookup("run")
    let entry = try #require(english.entry)
    #expect(entry.english.contains { $0.partOfSpeech == "noun" })
    #expect(entry.english.contains { $0.partOfSpeech == "verb" })
    #expect(entry.english.flatMap(\.senses).contains { !$0.examples.isEmpty })
    #expect(entry.forms.contains { $0.word == "ran" })
    #expect(entry.chinese.isEmpty)
    let chinese = try #require(DictionaryStore(databaseURL: file(.englishChinese)).lookup("hello ").entry)
    #expect(chinese.english.isEmpty)
    #expect(!chinese.chinese.isEmpty)
    let reverse = try #require(DictionaryStore(databaseURL: file(.chineseEnglish)).lookup(" 蘋果 ").entry)
    #expect(reverse.word == "苹果")
    #expect(reverse.english.flatMap(\.senses).contains { $0.definition.contains("apple") })
    #expect(reverse.pinyin?.isEmpty == false)
    #expect(LookupQuery.isChinese("蘋果 "))
}

@Test func phrasesSuggestionsAndSQLBinding() throws {
    let store = try DictionaryStore(databaseURL: file(.englishEnglish))
    #expect(LookupQuery.normalize(" don’t ") == "don't")
    #expect(try store.lookup("  ICE   CREAM  ").entry?.word == "ice cream")
    #expect(try store.lookup("helo ").suggestions.contains("hello"))
    #expect(try store.lookup("dictionray").suggestions.contains("dictionary"))
    #expect(try store.lookup("zzzzzzzzzzzzzzzz").entry == nil)
    #expect(try store.lookup("'; DROP TABLE entries; --").entry == nil)
    #expect(try store.lookup("hello").entry != nil)
    #expect(try DictionaryStore(databaseURL: nil).lookup(" \t\n").query.isEmpty)
}

@Test(arguments: DictionaryID.allCases)
func everyUploadMatchesItsManifest(_ id: DictionaryID) throws {
    try DictionaryLibrary.validate(file(id), pack: pack(id))
}

@Test func catalogRejectsUntrustedOrIncompletePacks() throws {
    let original = try pack(.englishEnglish)
    let bad = DictionaryPack(id: original.id, version: "../escape", schemaVersion: 2, entryCount: 1,
        byteCount: 100, sha256: original.sha256, url: URL(string: "http://untrusted.example/dictionary.sqlite")!)
    #expect(throws: PackError.self) { try bad.validate() }
    let data = try JSONEncoder().encode(DictionaryCatalog(schemaVersion: 2, packs: [original, original, original]))
    #expect(throws: PackError.self) { try DictionaryCatalog.decode(data) }
}

// Small SQLite fixtures exercise installation races and integrity failures without
// duplicating the production packs for every state-transition test.
private struct Fixture {
    let root: URL
    let url: URL
    let pack: DictionaryPack
    init(_ id: DictionaryID = .englishEnglish, version: String = "test1") throws {
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        url = root.appending(path: "fixture.sqlite")
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        let payload = Data("""
        {"word":"test","displayWord":"test","english":[{"partOfSpeech":"noun","senses":[{"definition":"a test","examples":[],"synonyms":[]}]}],"chinese":[],"forms":[]}
        """.utf8)
        var compressed = Data(count: Int(compressBound(uLong(payload.count))))
        var compressedSize = uLongf(compressed.count)
        let result = compressed.withUnsafeMutableBytes { output in
            payload.withUnsafeBytes { input in
                compress2(output.bindMemory(to: Bytef.self).baseAddress, &compressedSize,
                          input.bindMemory(to: Bytef.self).baseAddress, uLong(payload.count), Z_BEST_COMPRESSION)
            }
        }
        #expect(result == Z_OK)
        let hex = compressed.prefix(Int(compressedSize)).map { String(format: "%02x", $0) }.joined()
        let sql = """
        PRAGMA user_version=2;
        CREATE TABLE entries(word TEXT PRIMARY KEY,rank INTEGER,payload BLOB,payload_size INTEGER);
        CREATE TABLE aliases(alias TEXT,word TEXT);
        CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);
        INSERT INTO metadata VALUES('pack_id','\(id.rawValue)'),('version','\(version)');
        INSERT INTO entries VALUES('test',1,x'\(hex)',\(payload.count));
        """
        #expect(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
        let data = try Data(contentsOf: url)
        pack = DictionaryPack(id: id, version: version, schemaVersion: 2, entryCount: 1,
            byteCount: Int64(data.count), sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            url: URL(string: "https://fastcdn.candyrect.com/instadict/fixture.sqlite")!)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func installSurvivesRelaunchAndDeletionRejectsLateTransfer() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let root = fixture.root.appending(path: "library")
    let library = DictionaryLibrary(root: root)
    let install = PackCommand(id: fixture.pack.id, revision: 100, pack: fixture.pack)
    try await library.install(fixture.url, pack: fixture.pack, command: install)
    #expect(try await library.snapshot().installed.count == 1)
    let reopened = DictionaryLibrary(root: root)
    #expect(try await reopened.snapshot().installed.first?.pack == fixture.pack)
    let removal = PackCommand(id: fixture.pack.id, revision: 101, pack: nil)
    try await reopened.apply([removal])
    #expect(try await reopened.file(for: fixture.pack.id) == nil)
    await #expect(throws: PackError.self) {
        try await reopened.install(fixture.url, pack: fixture.pack, command: install)
    }
    try await reopened.apply([install])
    #expect(try await reopened.snapshot().commands.first == removal)
    #expect(try await reopened.snapshot().installed.isEmpty)
}

@Test func failedUpdateKeepsPreviousDictionary() async throws {
    let old = try Fixture()
    let new = try Fixture(version: "test2")
    defer { old.clean(); new.clean() }
    let library = DictionaryLibrary(root: old.root.appending(path: "library"))
    try await library.install(old.url, pack: old.pack)
    let handle = try FileHandle(forWritingTo: new.url)
    try handle.seek(toOffset: 100)
    try handle.write(contentsOf: Data([0xFF]))
    try handle.close()
    await #expect(throws: PackError.self) { try await library.install(new.url, pack: new.pack) }
    #expect(try await library.snapshot().installed.first?.pack == old.pack)
    #expect(try await library.file(for: old.pack.id) != nil)
}

@Test func rejectsWrongDictionaryIdentity() throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let wrong = DictionaryPack(id: .chineseEnglish, version: fixture.pack.version, schemaVersion: 2,
        entryCount: fixture.pack.entryCount, byteCount: fixture.pack.byteCount, sha256: fixture.pack.sha256, url: fixture.pack.url)
    #expect(throws: PackError.self) { try DictionaryLibrary.validate(fixture.url, pack: wrong) }
}

@Test @MainActor func languageSwitchMissingPackAndLatestLookup() async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let library = DictionaryLibrary(root: root)
    try await library.install(file(.englishEnglish), pack: pack(.englishEnglish))
    let model = LookupModel(library: library)
    model.lookUp("hello ")
    try await waitForDefinition(model, word: "hello")
    model.switchLanguage()
    for _ in 0..<200 {
        if case .needsPack(.englishChinese) = model.state { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    if case .needsPack(.englishChinese) = model.state {} else { Issue.record("Missing EC pack was not explained") }
    try await library.install(file(.englishChinese), pack: pack(.englishChinese))
    model.reloadCurrent()
    try await waitForDefinition(model, word: "hello")
    #expect(model.language == .chinese)
    model.lookUp(" \n")
    #expect(model.language == .chinese)
    model.lookUp("dictionray")
    model.lookUp("apple ")
    #expect(model.language == .english)
    try await waitForDefinition(model, word: "apple")
    model.lookUp("苹果")
    #expect(model.dictionary == .chineseEnglish)
    #expect(!model.canSwitchLanguage)
}

@MainActor private func waitForDefinition(_ model: LookupModel, word: String) async throws {
    for _ in 0..<200 {
        if case .definition(let entry, _) = model.state, entry.word == word { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Lookup failed to resolve \(word) within two seconds")
}
