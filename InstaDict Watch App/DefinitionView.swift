import SwiftUI

struct DefinitionView: View {
    @ScaledMetric(relativeTo: .title3) private var headwordSize = 26
    let entry: DictionaryEntry
    let query: String
    let language: DictionaryLanguage
    let onLookup: (String) -> Void
    let onNewWord: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                wordHeader
                if entry.sections(in: language).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(language == .english ? "No English definition" : "暂无中文释义")
                            .font(.headline)
                        Text(language == .english
                             ? "Try its Chinese meaning with the 中 button."
                             : "This word isn’t in the Chinese dictionary yet. Tap EN for its English definition.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(entry.sections(in: language).enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text(section.partOfSpeech)
                                .font(.system(.footnote, design: .serif).italic())
                                .foregroundStyle(.tint)
                            Rectangle().fill(Color.accentColor.opacity(0.3)).frame(height: 1)
                        }
                        ForEach(Array(section.senses.enumerated()), id: \.offset) { index, sense in
                            senseView(sense, number: index + 1)
                        }
                    }
                }
                if let lemma = entry.lemma, lemma != entry.word {
                    VStack(alignment: .leading, spacing: 6) {
                        sectionLabel("BASE FORM")
                        Button(lemma) { onLookup(lemma) }.tint(.accentColor)
                    }
                }
                if !entry.forms.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("WORD FORMS")
                        ForEach(Array(entry.forms.enumerated()), id: \.offset) { _, form in
                            Button { onLookup(form.word) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(form.label).font(.caption2).foregroundStyle(.secondary)
                                    Text(form.word).font(.body).foregroundStyle(.tint)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(form.label): \(form.word). Look up word.")
                        }
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 64)
        }
        .overlay(alignment: .bottomTrailing) {
            NewWordButton(action: onNewWord)
                .padding(.bottom, 8)
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .accessibilityIdentifier("definitionPage")
    }

    private var wordHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LookupQuery.isChinese(entry.word) ? "中文 → ENGLISH" : language == .english ? "ENGLISH" : "ENGLISH → 简体中文")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.4).foregroundStyle(.secondary)
            Text(entry.displayWord)
                .font(.system(size: headwordSize, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("headword")
            if query != entry.word {
                Text("\(query) → \(entry.displayWord)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let pinyin = entry.pinyin, !pinyin.isEmpty {
                Text(pinyin).font(.caption2).foregroundStyle(.secondary)
            }
            if !pronunciations.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(pronunciations, id: \.region) { pronunciation in
                        pronunciationRow(pronunciation.region, ipa: pronunciation.ipa)
                    }
                }
            }
        }
    }

    private var pronunciations: [(region: String, ipa: String)] {
        [("UK", entry.britishIPA), ("US", entry.americanIPA)].compactMap { region, value in
            guard let ipa = value?.trimmingCharacters(in: .whitespacesAndNewlines), !ipa.isEmpty else { return nil }
            return (region, ipa)
        }
    }

    private func pronunciationRow(_ region: String, ipa: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(region)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .frame(width: 22, alignment: .leading)
            Text(ipa)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(region == "UK" ? "British" : "American") pronunciation: \(ipa)")
    }

    private func senseView(_ sense: DictionarySense, number: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(String(number))
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                .frame(minWidth: 10, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(sense.definition)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(sense.examples.enumerated()), id: \.offset) { _, example in
                    Text("“\(example)”")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.accentColor.opacity(0.45)).frame(width: 2)
                        }
                }
                if !sense.synonyms.isEmpty {
                    Text("Also: " + sense.synonyms.joined(separator: ", "))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
    }
}

struct NewWordButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 20, weight: .medium))
                .frame(width: 46, height: 46)
                .foregroundStyle(.black)
                .background(Color.accentColor, in: Circle())
        }
        .buttonStyle(.plain)
        .padding(.trailing, 6)
        .padding(.top, 4)
        .accessibilityLabel("Look up a new word")
        .accessibilityIdentifier("newWord")
    }
}

