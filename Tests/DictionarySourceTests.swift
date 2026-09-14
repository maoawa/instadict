import Foundation
import Testing
@testable import InstaDictCore

@Test func sourceAcceptsHTTPSFoldersAndCatalogs() throws {
    #expect(try DictionaryDownloadSource.normalize(" https://example.com/dicts/ \n").absoluteString == "https://example.com/dicts/manifest.json")
    #expect(try DictionaryDownloadSource.normalize("https://example.com/dicts").absoluteString == "https://example.com/dicts/manifest.json")
    #expect(try DictionaryDownloadSource.normalize("example.com").absoluteString == "https://example.com/manifest.json")
    #expect(try DictionaryDownloadSource.normalize("fastcdn.candyrect.com/instadict").absoluteString == "https://fastcdn.candyrect.com/instadict/manifest.json")
    #expect(try DictionaryDownloadSource.normalize("https://example.com").absoluteString == "https://example.com/manifest.json")
    #expect(try DictionaryDownloadSource.normalize("https://example.com/catalog.json?release=2").absoluteString == "https://example.com/catalog.json?release=2")
}

@Test(arguments: ["", "/example.com", "https://example..com", "http://example.com/manifest.json", "file:///manifest.json",
                  "https://user:password@example.com/manifest.json", "https://example.com/#fragment",
                  "https://example.com/file.sqlite", "https://exa mple.com", "https:///manifest.json"])
func sourceRejectsInvalidAddresses(_ input: String) {
    #expect(throws: (any Error).self) { try DictionaryDownloadSource.normalize(input) }
}

private func sourceCatalog(_ location: String) throws -> Data {
    try JSONEncoder().encode(DictionaryCatalog(schemaVersion: 3, packs: DictionaryID.allCases.map { id in
        DictionaryPack(id: id, version: "2026.09.14", schemaVersion: 3, entryCount: 1, byteCount: 100,
                       sha256: String(repeating: "a", count: 64), url: URL(string: location)!)
    }))
}

@Test func catalogResolvesRelativeFilesAndAcceptsHTTPSMirrors() throws {
    let base = URL(string: "https://example.com/dicts/manifest.json")!
    let relative = try DictionaryCatalog.decode(sourceCatalog("pack.sqlite"), relativeTo: base)
    #expect(relative.packs.allSatisfy { $0.url.absoluteString == "https://example.com/dicts/pack.sqlite" })
    let mirror = try DictionaryCatalog.decode(sourceCatalog("https://mirror.example.org/pack.sqlite"), relativeTo: base)
    #expect(mirror.packs.first?.url.host == "mirror.example.org")
    #expect(throws: (any Error).self) { try DictionaryCatalog.decode(sourceCatalog("pack.sqlite")) }
    for location in ["http://example.com/pack.sqlite", "https://user@example.com/pack.sqlite", "https://example.com/pack.sqlite#part"] {
        #expect(throws: (any Error).self) { try DictionaryCatalog.decode(sourceCatalog(location), relativeTo: base) }
    }
}

@Test func savedSourceKeepsItsCatalogAcrossRelaunch() throws {
    let source = URL(string: "https://custom.example.com/manifest.json")!
    let catalog = try DictionaryCatalog.decode(sourceCatalog("pack.sqlite"), relativeTo: source)
    let saved = DictionaryCatalogSelection(source: source, catalog: catalog)
    let restored = try DictionaryCatalogSelection.decode(JSONEncoder().encode(saved))
    #expect(restored.source == source)
    #expect(restored.catalog.packs == catalog.packs)
    #expect(restored.catalog.packs.first?.url.host == "custom.example.com")
}

@Test func relativeDistributionWorksFromAnyFolder() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let bytes = try Data(contentsOf: root.appending(path: "Distribution/Dictionaries/manifest.json"))
    for base in [DictionaryCatalog.remoteURL, URL(string: "https://mirror.example.com/other/folder/manifest.json")!] {
        let catalog = try DictionaryCatalog.decode(bytes, relativeTo: base)
        for pack in catalog.packs {
            #expect(pack.url == base.deletingLastPathComponent().appending(path: "\(pack.id.rawValue)-\(pack.version).sqlite"))
        }
    }
}

@Test func formerDefaultMigratesWhileCustomSourcesPersist() throws {
    let catalog = try DictionaryCatalog.decode(sourceCatalog("https://example.com/pack.sqlite"))
    let legacy = DictionaryCatalogSelection(source: DictionaryCatalog.previousDefaultURL, catalog: catalog)
    let restored = try DictionaryCatalogSelection.decode(JSONEncoder().encode(legacy))
    #expect(restored.usesDefaultSource)
    #expect(restored.effectiveSource == DictionaryCatalog.remoteURL)
    let custom = DictionaryCatalogSelection(source: DictionaryCatalog.previousDefaultURL, catalog: catalog, isDefault: false)
    let restoredCustom = try DictionaryCatalogSelection.decode(JSONEncoder().encode(custom))
    #expect(!restoredCustom.usesDefaultSource)
    #expect(restoredCustom.effectiveSource == DictionaryCatalog.previousDefaultURL)
}

@Test func staleDefaultCatalogCannotDowngradeStorage() throws {
    let current = try DictionaryCatalog.decode(sourceCatalog("https://example.com/pack.sqlite"))
    let old = DictionaryCatalog(schemaVersion: 2, packs: current.packs)
    #expect(throws: SourceError.self) { try old.requiringCurrentFormat(minimum: current) }
    #expect(try current.requiringCurrentFormat(minimum: current).packs == current.packs)
}
