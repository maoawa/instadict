import CryptoKit
import Foundation
import SQLite3
import Testing
import zlib
@testable import InstaDictCore

private struct BlockFixture {
    let root: URL
    let url: URL
    let schema: Int
    init(schema: Int = 3, mutation: String = "") throws {
        self.schema = schema
        root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        url = root.appending(path: "block.sqlite")
        let words = ["alpha", "苹果"]
        let entries = words.map { word in Data("""
            {"word":"\(word)","displayWord":"\(word)","english":[{"partOfSpeech":"noun","senses":[{"definition":"\(word) definition 中文","examples":[],"synonyms":[]}]}],"chinese":[],"forms":[]}
            """.utf8) }
        func compressedHex(_ data: Data) -> String {
            var compressed = Data(count: Int(compressBound(uLong(data.count))))
            var size = uLongf(compressed.count)
            let status = compressed.withUnsafeMutableBytes { output in
                data.withUnsafeBytes { input in
                    compress2(output.bindMemory(to: Bytef.self).baseAddress, &size,
                              input.bindMemory(to: Bytef.self).baseAddress, uLong(data.count), Z_BEST_COMPRESSION)
                }
            }
            #expect(status == Z_OK)
            return compressed.prefix(Int(size)).map { String(format: "%02x", $0) }.joined()
        }
        var database: OpaquePointer?
        #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var sql = """
            PRAGMA user_version=\(schema);
            CREATE TABLE aliases(alias TEXT,word TEXT);
            CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);
            INSERT INTO metadata VALUES('pack_id','english-english'),('version','test');
            INSERT INTO aliases VALUES('蘋果','苹果');
            """
        if schema == 3 {
            let combined = entries.reduce(Data(), +)
            sql += """
                CREATE TABLE entries(word TEXT PRIMARY KEY,rank INTEGER,block_id INTEGER,byte_offset INTEGER,payload_size INTEGER);
                CREATE TABLE blocks(id INTEGER PRIMARY KEY,payload BLOB,payload_size INTEGER);
                INSERT INTO blocks VALUES(0,x'\(compressedHex(combined))',\(combined.count));
                INSERT INTO entries VALUES('alpha',1,0,0,\(entries[0].count));
                INSERT INTO entries VALUES('苹果',2,0,\(entries[0].count),\(entries[1].count));
                """
        } else {
            sql += "CREATE TABLE entries(word TEXT PRIMARY KEY,rank INTEGER,payload BLOB,payload_size INTEGER);"
            for (word, entry) in zip(words, entries) {
                sql += "INSERT INTO entries VALUES('\(word)',1,x'\(compressedHex(entry))',\(entry.count));"
            }
        }
        #expect(sqlite3_exec(database, sql + mutation, nil, nil, nil) == SQLITE_OK)
    }
    func pack(schema override: Int? = nil) throws -> DictionaryPack {
        let data = try Data(contentsOf: url)
        return DictionaryPack(id: .englishEnglish, version: "test", schemaVersion: override ?? schema, entryCount: 2,
            byteCount: Int64(data.count), sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            url: URL(string: "https://fastcdn.candyrect.com/instadict/block.sqlite")!)
    }
    func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func blockLookupMatchesLegacyIncludingUnicodeOffsetsAndAliases() throws {
    let old = try BlockFixture(schema: 2)
    let new = try BlockFixture()
    defer { old.clean(); new.clean() }
    try DictionaryLibrary.validate(old.url, pack: old.pack())
    try DictionaryLibrary.validate(new.url, pack: new.pack())
    let legacy = DictionaryStore(databaseURL: old.url)
    let blocks = DictionaryStore(databaseURL: new.url)
    for query in [" alpha ", "苹果", "蘋果", "alph", "missing"] {
        let before = try legacy.lookup(query), after = try blocks.lookup(query)
        #expect(before.query == after.query)
        #expect(before.entry == after.entry)
        #expect(before.suggestions == after.suggestions)
    }
}

@Test func compressedInstallStaysCompressedAndReplacesSameVersionLegacy() async throws {
    let old = try BlockFixture(schema: 2)
    let new = try BlockFixture()
    defer { old.clean(); new.clean() }
    let library = DictionaryLibrary(root: new.root.appending(path: "library"))
    try await library.install(old.url, pack: old.pack())
    let previous = try #require(await library.file(for: .englishEnglish))
    try await library.install(new.url, pack: new.pack())
    let installed = try #require(await library.file(for: .englishEnglish))
    #expect(installed != previous)
    #expect(!FileManager.default.fileExists(atPath: previous.path))
    #expect(try Data(contentsOf: installed) == Data(contentsOf: new.url))
    #expect(try await library.lookup("蘋果", in: .englishEnglish).entry?.word == "苹果")
}

@Test(arguments: [
    "UPDATE entries SET byte_offset=-1 WHERE word='alpha';",
    "UPDATE entries SET byte_offset=4294967296 WHERE word='alpha';",
    "UPDATE entries SET byte_offset=9223372036854775807,payload_size=9223372036854775807 WHERE word='alpha';",
    "UPDATE entries SET byte_offset=NULL WHERE word='alpha';",
    "UPDATE entries SET payload_size=0 WHERE word='alpha';",
    "UPDATE entries SET payload_size=999999 WHERE word='alpha';",
    "UPDATE entries SET block_id=99 WHERE word='alpha';",
    "UPDATE blocks SET payload_size=4294967296;",
    "UPDATE blocks SET payload_size=1;",
    "UPDATE blocks SET payload=x'00';",
    "UPDATE blocks SET payload=NULL;",
    "UPDATE entries SET byte_offset=(SELECT byte_offset FROM entries WHERE word='苹果'),payload_size=(SELECT payload_size FROM entries WHERE word='苹果') WHERE word='alpha';"
])
func malformedBlocksFailWithoutReturningAnotherEntry(_ mutation: String) throws {
    let fixture = try BlockFixture(mutation: mutation)
    defer { fixture.clean() }
    // Recomputed checksum ensures we exercise structural/decompression checks,
    // not just the outer download hash check.
    #expect(throws: PackError.self) { try DictionaryLibrary.validate(fixture.url, pack: fixture.pack()) }
    #expect(throws: DictionaryStore.StoreError.self) { try DictionaryStore(databaseURL: fixture.url).lookup("alpha") }
}

@Test func mismatchedAndFutureSchemasAreRejected() throws {
    let fixture = try BlockFixture()
    defer { fixture.clean() }
    #expect(throws: PackError.self) { try DictionaryLibrary.validate(fixture.url, pack: fixture.pack(schema: 2)) }
    #expect(throws: PackError.self) { try fixture.pack(schema: 4).validate() }
    let data = try JSONEncoder().encode(DictionaryCatalog(schemaVersion: 4, packs: []))
    #expect(throws: PackError.self) { try DictionaryCatalog.decode(data) }
}

@Test func bundledSchemaUpgradeReplacesAnOlderCachedCatalog() {
    let legacy = DictionaryCatalog(schemaVersion: 2, packs: [])
    let current = DictionaryCatalog(schemaVersion: 3, packs: [])
    #expect(current.preferringCached(legacy).schemaVersion == 3)
    #expect(legacy.preferringCached(current).schemaVersion == 3)
    #expect(current.preferringCached(nil).schemaVersion == 3)
}
