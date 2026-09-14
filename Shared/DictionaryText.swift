import Foundation

/// Presentation cleanup also applies to packs downloaded before these fixes.
enum DictionaryText {
    static func clean(_ text: String) -> String {
        text.replacingOccurrences(of: #"\\+[rn]"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\\+t"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func pronunciation(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Lost IPA glyphs cannot be recovered by simply removing backslashes.
        return value.isEmpty || value.contains("\\") ? nil : value
    }

    private static let syllable = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}:])([a-züêv:]+)([0-5])(?![\p{L}\p{N}])"#,
        options: .caseInsensitive)
    private static let reference = try! NSRegularExpression(pattern: #"\[[^\[\]\n]+\]"#)

    static func pinyin(_ text: String) -> String {
        toneMarks(text.lowercased())
    }

    /// CC-CEDICT embeds numbered pronunciations in square-bracket references.
    /// Leave English prose, capitalization and unrelated numbers alone.
    static func pinyinReferences(_ text: String) -> String {
        var result = text
        for match in reference.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: toneMarks(String(result[range])))
        }
        return result
    }

    private static func toneMarks(_ text: String) -> String {
        var result = text
        for match in syllable.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result),
                  let letters = Range(match.range(at: 1), in: text),
                  let number = Range(match.range(at: 2), in: text),
                  let tone = Int(text[number]) else { continue }
            var base = String(text[letters]).lowercased()
                .replacingOccurrences(of: "u:", with: "ü")
                .replacingOccurrences(of: "v", with: "ü")
            let vowels = "aeiouüê"
            let index = base.firstIndex(of: "a") ?? base.firstIndex(of: "e")
                ?? base.range(of: "ou")?.lowerBound ?? base.lastIndex(where: { vowels.contains($0) })
                ?? (["m", "n", "ng"].contains(base) ? base.startIndex : nil)
            guard let index else {
                if base == "r", tone == 0 || tone == 5 { result.replaceSubrange(range, with: base) }
                continue
            }
            if (1...4).contains(tone) {
                let accents = ["\u{0304}", "\u{0301}", "\u{030C}", "\u{0300}"]
                base.insert(contentsOf: accents[tone - 1], at: base.index(after: index))
            }
            result.replaceSubrange(range, with: base.precomposedStringWithCanonicalMapping)
        }
        return result
    }
}

extension DictionaryEntry {
    var formattedForDisplay: DictionaryEntry {
        func sections(_ values: [DictionarySection]) -> [DictionarySection] {
            values.compactMap { section in
                let senses = section.senses.compactMap { sense -> DictionarySense? in
                    let definition = DictionaryText.pinyinReferences(DictionaryText.clean(sense.definition))
                    guard !definition.isEmpty else { return nil }
                    return DictionarySense(definition: definition,
                        examples: sense.examples.map(DictionaryText.clean).filter { !$0.isEmpty },
                        synonyms: sense.synonyms)
                }
                return senses.isEmpty ? nil : DictionarySection(partOfSpeech: section.partOfSpeech, senses: senses)
            }
        }
        return DictionaryEntry(word: word, displayWord: displayWord,
            britishIPA: DictionaryText.pronunciation(britishIPA),
            americanIPA: DictionaryText.pronunciation(americanIPA),
            pinyin: pinyin.map(DictionaryText.pinyin), english: sections(english), chinese: sections(chinese),
            forms: forms, lemma: lemma)
    }

    /// Match known forms as whole words. For "roam", "roamed" qualifies but the
    /// synonym "wander" does not; "cat" must not match "cattle".
    func exampleMatches(in text: String, query: String) -> [Range<String.Index>] {
        let words = Set(([word, displayWord, query] + forms.map(\.word) + [lemma].compactMap { $0 })
            .map(LookupQuery.normalize).filter { !$0.isEmpty })
        let alternatives = words.sorted { $0.count > $1.count }.map {
            NSRegularExpression.escapedPattern(for: $0)
                .replacingOccurrences(of: " ", with: #"\s+"#)
                .replacingOccurrences(of: "'", with: "['’‘]")
        }.joined(separator: "|")
        guard !alternatives.isEmpty,
              let regex = try? NSRegularExpression(
                pattern: #"(?<![\p{L}\p{M}\p{N}_])(?:"# + alternatives + #")(?![\p{L}\p{M}\p{N}_])"#,
                options: .caseInsensitive) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap { Range($0.range, in: text) }
    }
}
