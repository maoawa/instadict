import Foundation
import Testing
@testable import InstaDictCore

@Test(arguments: [
    ("Zhong1 wen2", "zhōng wén"),
    ("huan2 jing4 bao3 hu4", "huán jìng bǎo hù"),
    ("ni3 hao3 ma5", "nǐ hǎo ma"),
    ("NÜ3 lu:4 lv4", "nǚ lǜ lǜ"),
    ("liu2 shui3 gui4 dou1", "liú shuǐ guì dōu"),
    ("Xi1'an1 / xi1 an1", "xī'ān / xī ān"),
    ("lüè / zhōng wén", "lüè / zhōng wén"),
    ("m2 ng3 r5 de0", "ḿ ňg r de")
])
func numberedPinyin(_ input: String, _ expected: String) {
    #expect(DictionaryText.pinyin(input) == expected)
}

@Test func bracketedPinyinPreservesSurroundingText() {
    let input = "abbr. for 環境保護|环境保护[huan2 jing4 bao3 hu4]; Chinese [Zhong1 wen2], 3 examples [ISO9001]"
    let expected = "abbr. for 環境保護|环境保护[huán jìng bǎo hù]; Chinese [zhōng wén], 3 examples [ISO9001]"
    #expect(DictionaryText.pinyinReferences(input) == expected)
    #expect(DictionaryText.pinyinReferences(expected) == expected)
}

@Test func oldPackEscapesAndInvalidPronunciations() throws {
    let data = Data(#"{"word":"test","displayWord":"test","britishIPA":"/p\\\\:s/","pinyin":"Zhong1 wen2","english":[{"partOfSpeech":"noun","senses":[{"definition":"first\\r\\nsecond\r\nthird","examples":[],"synonyms":[]},{"definition":"\\r","examples":[],"synonyms":[]}]}],"chinese":[],"forms":[]}"#.utf8)
    let entry = try JSONDecoder().decode(DictionaryEntry.self, from: data).formattedForDisplay
    #expect(entry.britishIPA == nil)
    #expect(entry.pinyin == "zhōng wén")
    #expect(entry.english[0].senses.map(\.definition) == ["first second third"])
    #expect(DictionaryText.pronunciation(" /ˈpɜːsənəlaɪz/ ") == "/ˈpɜːsənəlaɪz/")
    #expect(entry.formattedForDisplay == entry)
}

@Test func examplesMatchWholeWordsAndKnownForms() {
    let entry = DictionaryEntry(word: "roam", displayWord: "roam", britishIPA: nil, americanIPA: nil,
        pinyin: nil, english: [], chinese: [],
        forms: [WordForm(label: "past tense", word: "roamed"), WordForm(label: "present participle", word: "roaming")], lemma: nil)
    let question = "Did they ROAM, or had they roamed before roaming?"
    #expect(entry.exampleMatches(in: question, query: "roam").map { String(question[$0]) } == ["ROAM", "roamed", "roaming"])
    for text in ["roving vagabonds", "They wander.", "roamer", "microam", "roam2", "éRoam"] {
        #expect(entry.exampleMatches(in: text, query: "roam").isEmpty)
    }
    let phrase = DictionaryEntry(word: "ice cream", displayWord: "ice cream", britishIPA: nil, americanIPA: nil,
        pinyin: nil, english: [], chinese: [], forms: [], lemma: nil)
    #expect(phrase.exampleMatches(in: "Would you like ICE  CREAM?", query: "ice cream").count == 1)
}
