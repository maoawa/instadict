import SwiftUI

struct DefinitionView: View {
    #if os(iOS)
    @ScaledMetric(relativeTo: .largeTitle) private var headwordSize = 38
    #else
    @ScaledMetric(relativeTo: .title3) private var headwordSize = 26
    #endif
    let entry: DictionaryEntry
    let query: String
    let language: DictionaryLanguage
    let onLookup: (String) -> Void
    @AppStorage(PronunciationOrder.preferenceKey) private var pronunciationOrder = PronunciationOrder.britishFirst

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                wordHeader
                if entry.sections(in: language).isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizedStringKey(language == .english ? "No English definition" : "No Chinese definition"))
                            .font(.headline)
                        Text(LocalizedStringKey(language == .english
                             ? "Try its Chinese meaning with the 中 button."
                             : "This word isn’t in the Chinese dictionary yet. Tap EN for its English definition."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                ForEach(Array(entry.sections(in: language).enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Text(L10n.grammaticalLabel(section.partOfSpeech))
                                .font(sectionFont.italic())
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
                                    Text(L10n.grammaticalLabel(form.label)).font(annotationFont).foregroundStyle(.secondary)
                                    Text(form.word).font(definitionFont).foregroundStyle(.tint)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.ui("%@: %@. Look up word.", L10n.grammaticalLabel(form.label), form.word))
                        }
                    }
                }

            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .accessibilityIdentifier("definitionPage")
    }

    private var horizontalPadding: CGFloat {
        #if os(iOS)
        24
        #else
        12
        #endif
    }

    private var wordHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(LookupQuery.isChinese(entry.word) ? "CHINESE → ENGLISH" : language == .english ? "ENGLISH" : "ENGLISH → CHINESE"))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.4).foregroundStyle(.secondary)
            Text(entry.displayWord)
                .font(.system(size: headwordSize, weight: .bold, design: .serif))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("headword")
            if query != entry.word {
                Text(verbatim: "\(query) → \(entry.displayWord)")
                    .font(annotationFont).foregroundStyle(.secondary)
            }
            if let pinyin = entry.pinyin, !pinyin.isEmpty {
                Text(pinyin).font(pronunciationFont).foregroundStyle(.secondary)
            }
            if !pronunciations.isEmpty {
                #if os(iOS)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 24) {
                        pronunciationRows
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 8) { pronunciationRows }
                }
                #else
                VStack(alignment: .leading, spacing: 5) { pronunciationRows }
                #endif
            }
        }
    }

    private var pronunciations: [Pronunciation] { pronunciationOrder.pronunciations(for: entry) }

    private var pronunciationRows: some View {
        ForEach(pronunciations) { pronunciation in
            pronunciationRow(pronunciation.region, ipa: pronunciation.ipa)
        }
    }

    private func pronunciationRow(_ region: String, ipa: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(LocalizedStringKey(region))
                .font(annotationFont.bold())
                .foregroundStyle(.tint)
                .fixedSize()
            Text(ipa)
                .font(pronunciationFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.ui(region == "UK" ? "British pronunciation: %@" : "American pronunciation: %@", ipa))
    }

    private func senseView(_ sense: DictionarySense, number: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(L10n.number(number))
                .font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                .frame(minWidth: 10, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text(sense.definition)
                    .font(definitionFont)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(sense.examples.filter {
                    !entry.exampleMatches(in: $0, query: query).isEmpty
                }.enumerated()), id: \.offset) { _, example in
                    Text(highlightedExample(example))
                        .font(exampleFont).foregroundStyle(.secondary)
                        .padding(.leading, 8)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Color.accentColor.opacity(0.45)).frame(width: 2)
                        }
                }
                if !sense.synonyms.isEmpty {
                    Text(L10n.ui("Also: %@", sense.synonyms.joined(separator: ", ")))
                        .font(annotationFont.italic()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(LocalizedStringKey(title)).font(sectionFont.weight(.semibold)).tracking(1).foregroundStyle(.tint)
                .fixedSize(horizontal: false, vertical: true)
            Rectangle().fill(Color.accentColor.opacity(0.3)).frame(height: 1)
        }
        .padding(.top, 12)
    }

    private func highlightedExample(_ example: String) -> AttributedString {
        let text = "“\(example)”"
        var result = AttributedString(text)
        for match in entry.exampleMatches(in: text, query: query) {
            if let range = Range(match, in: result) {
                result[range].font = exampleFont.bold()
            }
        }
        return result
    }

    private var definitionFont: Font {
        #if os(iOS)
        .title3
        #else
        .body
        #endif
    }
    private var exampleFont: Font {
        #if os(iOS)
        .body
        #else
        .footnote
        #endif
    }
    private var annotationFont: Font {
        #if os(iOS)
        .subheadline
        #else
        .caption2
        #endif
    }
    private var pronunciationFont: Font {
        #if os(iOS)
        .body
        #else
        .caption2
        #endif
    }
    private var sectionFont: Font {
        #if os(iOS)
        .system(.headline, design: .serif)
        #else
        .system(.footnote, design: .serif)
        #endif
    }
}
