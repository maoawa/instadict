import CryptoKit
import Foundation
import SQLite3
import Testing
import zlib
@testable import InstaDictCore

private let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
private let distribution = project.appending(path: "Distribution/Dictionaries")
private func catalog() throws -> DictionaryCatalog {
    try DictionaryCatalog.decode(Data(contentsOf: distribution.appending(path: "manifest.json")), relativeTo: DictionaryCatalog.remoteURL)
}
private func pack(_ id: DictionaryID) throws -> DictionaryPack { try #require(catalog().packs.first { $0.id == id }) }
private func file(_ id: DictionaryID) throws -> URL { try distribution.appending(path: pack(id).url.lastPathComponent) }

@Test func reportedDictionaryEntries() throws {
    let english = DictionaryStore(databaseURL: try file(.englishEnglish))
    let chinese = DictionaryStore(databaseURL: try file(.englishChinese))
    let reverse = DictionaryStore(databaseURL: try file(.chineseEnglish))
    #expect(try english.lookup("personalise").entry?.britishIPA == "/ˈpɜːsənəlaɪz/")
    #expect(try english.lookup("personalize").entry?.britishIPA != nil)
    let meter = try #require(english.lookup("multimeter").entry)
    #expect(meter.english.flatMap(\.senses).contains { $0.definition.contains("voltage") })
    #expect(meter.lemma == nil)
    #expect(meter.forms.contains { $0.word == "multimeters" })
    let plural = try #require(english.lookup("multimeters").entry)
    #expect(plural.lemma == "multimeter")
    #expect(try chinese.lookup("multimeter").entry?.chinese.isEmpty == false)
    // Unlike the corrected singular, this source entry still has no English
    // definition; its translation must qualify independently for the EC pack.
    #expect(try chinese.lookup("digital multimeter").entry?.chinese.flatMap(\.senses)
        .contains { $0.definition.contains("数字万用表") } == true)
    let corrected = try #require(english.lookup("hentai").entry)
    #expect(corrected.english.flatMap(\.senses).count == 1)
    #expect(!corrected.english.flatMap(\.senses).contains { $0.definition.contains("forever") || $0.definition.contains("\\") })
    #expect(try reverse.lookup("中文").entry?.pinyin == "zhōng wén")
    let environment = try #require(reverse.lookup("环保").entry)
    #expect(environment.english.flatMap(\.senses).contains { $0.definition.contains("[huán jìng bǎo hù]") })
    let roam = try #require(english.lookup("roam").entry)
    let examples = roam.english.flatMap(\.senses).flatMap(\.examples)
        .filter { !roam.exampleMatches(in: $0, query: "roam").isEmpty }
    #expect(examples.count == 2)
    #expect(examples.contains("The cattle roam across the prairie"))
}

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

@Test func receivingCommandIsNotInstallationConfirmation() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let library = DictionaryLibrary(root: fixture.root.appending(path: "library"))
    let command = PackCommand(id: fixture.pack.id, revision: 100, pack: fixture.pack)
    try await library.apply([command])
    #expect(try await !library.snapshot().hasCompleted(command))

    // A disk/staging error must survive encoding and reach the iPhone even
    // though the actual dictionary file was never installed.
    try await library.recordError("Not enough storage", for: command.id, command: command)
    let failedReply = DictionaryStatusReply(inventory: try await library.snapshot())
    let decoded = try JSONDecoder().decode(DictionaryStatusReply.self, from: JSONEncoder().encode(failedReply))
    #expect(decoded.inventory?.errors[command.id.rawValue] == "Not enough storage")
    #expect(decoded.inventory?.hasCompleted(command) == false)

    try await library.install(fixture.url, pack: fixture.pack, command: command)
    #expect(try await library.snapshot().hasCompleted(command))

    let retry = PackCommand(id: command.id, revision: 101, pack: fixture.pack)
    #expect(try await !library.snapshot().hasCompleted(retry))
    try await library.apply([retry])
    #expect(try await library.snapshot().hasCompleted(retry))

    let removal = PackCommand(id: command.id, revision: 102, pack: nil)
    #expect(try await !library.snapshot().hasCompleted(removal))
    try await library.apply([removal])
    #expect(try await library.snapshot().hasCompleted(removal))
    #expect(try await !library.snapshot().hasCompleted(command))
}

@Test func transferTimestampSurvives32BitWatchArchitecture() async throws {
    let fixture = try Fixture()
    defer { fixture.clean() }
    let revision: Int64 = 1_789_358_400_000
    #expect(revision > Int64(Int32.max))
    let command = PackCommand(id: fixture.pack.id, revision: revision, pack: fixture.pack)
    let encoded = try JSONEncoder().encode(command)
    let decoded = try JSONDecoder().decode(PackCommand.self, from: encoded)
    // Int64 argument above also makes this regression fail to compile if the
    // wire field is changed back to platform-sized Int on a 64-bit test host.
    #expect(decoded == command)
    let library = DictionaryLibrary(root: fixture.root.appending(path: "library"))
    try await library.install(fixture.url, pack: fixture.pack, command: decoded)
    let reply = DictionaryStatusReply(inventory: try await library.snapshot())
    let receipt = try JSONDecoder().decode(DictionaryStatusReply.self, from: JSONEncoder().encode(reply))
    #expect(receipt.inventory?.hasCompleted(command) == true)
    let removal = PackCommand(id: command.id, revision: revision + 1, pack: nil)
    try await library.apply([removal])
    await #expect(throws: PackError.self) {
        try await library.install(fixture.url, pack: fixture.pack, command: command)
    }
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
    let name = "InstaDict.LookupModelTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = LookupPreferences(defaults: defaults, preferredLanguages: ["en-GB"])
    let model = LookupModel(library: library, preferences: preferences)
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

@Test func directWatchDownloadCannotUndoLaterRemovalOrInstall() async throws {
    let old = try Fixture()
    let new = try Fixture(version: "test2")
    defer { old.clean(); new.clean() }
    let library = DictionaryLibrary(root: old.root.appending(path: "direct-watch"))
    let companion = PackCommand(id: old.pack.id, revision: 100, pack: old.pack)
    try await library.install(old.url, pack: old.pack, command: companion)
    let direct = try await library.beginLocalChange(new.pack.id, pack: new.pack)
    let removal = PackCommand(id: new.pack.id, revision: direct.revision + 1, pack: nil)
    try await library.apply([removal])
    await #expect(throws: PackError.self) { try await library.install(new.url, pack: new.pack, command: direct) }
    #expect(try await library.snapshot().installed.isEmpty)

    let retry = try await library.beginLocalChange(new.pack.id, pack: new.pack)
    try await library.install(new.url, pack: new.pack, command: retry)
    // A background transfer queued on iPhone before the direct download must
    // not replace its result, even if its file arrives much later.
    await #expect(throws: PackError.self) { try await library.install(old.url, pack: old.pack, command: companion) }
    #expect(try await library.snapshot().installed.first?.pack == new.pack)
    #expect(try await library.snapshot().hasCompleted(retry))
}

@Test func canceledDirectUpdateKeepsInstalledPackAndFencesLateFile() async throws {
    let old = try Fixture()
    let new = try Fixture(version: "test2")
    defer { old.clean(); new.clean() }
    let root = old.root.appending(path: "canceled-watch")
    let library = DictionaryLibrary(root: root)
    try await library.install(old.url, pack: old.pack)
    let direct = try await library.beginLocalChange(new.pack.id, pack: new.pack)
    try await library.cancelLocalChange(direct)
    let restored = DictionaryLibrary(root: root)
    #expect(try await restored.snapshot().installed.first?.pack == old.pack)
    await #expect(throws: PackError.self) { try await restored.install(new.url, pack: new.pack, command: direct) }
    let removal = try await restored.beginLocalChange(old.pack.id, pack: nil)
    try await restored.cancelLocalChange(direct)
    #expect(try await restored.snapshot().hasCompleted(removal))
}

@Test func phoneReconcilesWatchChangesWithoutOverwritingNewerPhoneIntent() throws {
    let pack = try pack(.englishEnglish)
    let phone = PackCommand(id: pack.id, revision: 100, pack: pack)
    let watchRemoval = PackCommand(id: pack.id, revision: 101, pack: nil)
    #expect(PackCommand.merging([phone], with: [watchRemoval]) == [watchRemoval])
    #expect(PackCommand.merging([watchRemoval], with: [phone]) == [watchRemoval])
    let newPhone = PackCommand(id: pack.id, revision: 102, pack: pack)
    #expect(PackCommand.merging([newPhone], with: [watchRemoval]) == [newPhone])
}

@Test func changingDownloadHostDoesNotMakeInstalledContentOutdated() throws {
    let original = try pack(.englishEnglish)
    let mirror = DictionaryPack(id: original.id, version: original.version, schemaVersion: original.schemaVersion,
                                entryCount: original.entryCount, byteCount: original.byteCount, sha256: original.sha256,
                                url: URL(string: "https://mirror.example.com/pack.sqlite")!)
    #expect(mirror != original)
    #expect(mirror.hasSameContent(as: original))
    let changed = DictionaryPack(id: original.id, version: original.version, schemaVersion: original.schemaVersion,
                                 entryCount: original.entryCount, byteCount: original.byteCount, sha256: String(repeating: "0", count: 64), url: mirror.url)
    #expect(!changed.hasSameContent(as: original))
}
