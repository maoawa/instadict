import Testing
@testable import InstaDictCore

@Test func pronunciationPreferenceOrdersAvailableAccents() {
    let entry = DictionaryEntry(word: "test", displayWord: "test", britishIPA: " /test/ ", americanIPA: "/tɛst/",
                                pinyin: nil, english: [], chinese: [], forms: [], lemma: nil)
    #expect(PronunciationOrder.britishFirst.pronunciations(for: entry).map(\.region) == ["UK", "US"])
    #expect(PronunciationOrder.americanFirst.pronunciations(for: entry).map(\.region) == ["US", "UK"])
    #expect(PronunciationOrder.britishFirst.pronunciations(for: entry).first?.ipa == "/test/")
}

@Test func pronunciationPreferenceOmitsMissingAccents() {
    let entry = DictionaryEntry(word: "test", displayWord: "test", britishIPA: " \n", americanIPA: "/tɛst/",
                                pinyin: nil, english: [], chinese: [], forms: [], lemma: nil)
    for order in PronunciationOrder.allCases {
        #expect(order.pronunciations(for: entry).map(\.region) == ["US"])
    }
}
