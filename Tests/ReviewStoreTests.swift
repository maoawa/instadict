import Foundation
import Testing
@testable import InstaDictCore

@Test @MainActor func reviewStoreAddsWordsOnTheSecondLookupAndPersists() throws {
    let name = "InstaDict.ReviewStoreTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ReviewStore(defaults: defaults)
    let first = Date(timeIntervalSince1970: 2_000_000_000)

    store.recordLookup(" Hello  ", at: first)
    #expect(store.words.isEmpty)
    store.recordLookup("hello", at: first.addingTimeInterval(10))
    #expect(store.words.map(\.word) == ["hello"])
    #expect(store.words[0].count == 2)

    let reopened = ReviewStore(defaults: defaults)
    #expect(reopened.words == store.words)
}

@Test @MainActor func reviewStoreCanRemoveAndClearWords() throws {
    let name = "InstaDict.ReviewStoreTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = ReviewStore(defaults: defaults)
    for _ in 0..<2 { store.recordLookup("one") }
    for _ in 0..<2 { store.recordLookup("two") }
    #expect(store.words.count == 2)
    store.remove(store.words[0])
    #expect(store.words.count == 1)
    store.clear()
    #expect(store.words.isEmpty)
}

@Test @MainActor func wordBookTracksLookupsWithoutAutomaticAddingAndSupportsManualAdd() throws {
    let name = "InstaDict.WordBookTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = WordBookStore(defaults: defaults)
    let first = Date(timeIntervalSince1970: 2_000_000_000)

    store.recordLookup("hello", at: first, autoAddAfter: nil)
    store.recordLookup("hello", at: first.addingTimeInterval(1), autoAddAfter: nil)
    #expect(store.words.isEmpty)
    store.add("hello")
    #expect(store.contains("hello"))

    store.recordLookup("world", at: first, autoAddAfter: nil)
    store.recordLookup("world", at: first.addingTimeInterval(1), autoAddAfter: nil)
    store.addEligibleWords()
    #expect(store.contains("world"))
}

@Test @MainActor func wordBookSupportsConfigurableAutomaticAddThresholds() throws {
    let name = "InstaDict.WordBookThresholdTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let store = WordBookStore(defaults: defaults)
    let first = Date(timeIntervalSince1970: 2_000_000_000)

    for count in 1...3 {
        store.recordLookup("three", at: first.addingTimeInterval(Double(count)), autoAddAfter: 3)
        #expect(store.contains("three") == (count == 3))
    }
    for count in 1...4 {
        store.recordLookup("four", at: first.addingTimeInterval(Double(count)), autoAddAfter: 4)
        #expect(store.contains("four") == (count == 4))
    }
    store.recordLookup("never", at: first, autoAddAfter: nil)
    store.recordLookup("never", at: first.addingTimeInterval(1), autoAddAfter: nil)
    #expect(!store.contains("never"))
}

@Test @MainActor func wordBookMergesCompanionSnapshotsAndKeepsRemovals() throws {
    let firstName = "InstaDict.WordBookSyncSource." + UUID().uuidString
    let secondName = "InstaDict.WordBookSyncDestination." + UUID().uuidString
    let firstDefaults = try #require(UserDefaults(suiteName: firstName))
    let secondDefaults = try #require(UserDefaults(suiteName: secondName))
    defer {
        firstDefaults.removePersistentDomain(forName: firstName)
        secondDefaults.removePersistentDomain(forName: secondName)
    }

    let source = WordBookStore(defaults: firstDefaults)
    let destination = WordBookStore(defaults: secondDefaults)
    let start = Date.now.addingTimeInterval(-10)
    source.recordLookup("hello", at: start)
    source.recordLookup("hello", at: start.addingTimeInterval(1))
    #expect(destination.mergeSyncData(try #require(source.syncData())))
    #expect(destination.contains("hello"))

    destination.remove(destination.words[0])
    #expect(source.mergeSyncData(try #require(destination.syncData())))
    #expect(!source.contains("hello"))
}
