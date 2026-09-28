import SwiftUI

/// watchOS's automatic Picker presentation does not expose its close button.
/// Present an inline native Picker in a sheet with our shared toolbar styling.
struct SettingsPicker<Selection: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Selection
    let selectedValue: Text
    let options: Options
    @State private var isPresented = false

    init(_ title: String, selection: Binding<Selection>, selectedValue: Text,
         @ViewBuilder content: () -> Options) {
        self.title = title
        _selection = selection
        self.selectedValue = selectedValue
        options = content()
    }

    var body: some View {
        #if os(watchOS)
        Button {
            isPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                selectedValue.foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Form {
                    Picker(LocalizedStringKey(title), selection: $selection) { options }
                        .pickerStyle(.inline)
                        .labelsHidden()
                }
                .navigationTitle(LocalizedStringKey(title))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { isPresented = false }
                            .labelStyle(.iconOnly)
                            .instaDictCircleButton()
                    }
                }
            }
        }
        #else
        Picker(LocalizedStringKey(title), selection: $selection) { options }
        #endif
    }
}

struct InterfaceLanguagePicker: View {
    @Bindable private var settings = LanguageSettings.shared

    var body: some View {
        SettingsPicker("App language", selection: $settings.selection,
                       selectedValue: settings.selection.language.map { Text(verbatim: $0.nativeName) } ?? Text("System")) {
            Text("System").tag(InterfaceLanguageSelection.system)
            ForEach(InterfaceLanguage.allCases) { language in
                Text(verbatim: language.nativeName).tag(InterfaceLanguageSelection(rawValue: language.rawValue)!)
            }
        }
        .accessibilityIdentifier("interfaceLanguagePicker")
    }
}

struct PronunciationOrderPicker: View {
    @AppStorage(PronunciationOrder.preferenceKey) private var order = PronunciationOrder.britishFirst
    var body: some View {
        SettingsPicker("Pronunciation order", selection: $order,
                       selectedValue: Text(LocalizedStringKey(order.title))) {
            ForEach(PronunciationOrder.allCases) { order in
                Text(LocalizedStringKey(order.title)).tag(order)
            }
        }
    }
}

struct LookupPreferencesPicker: View {
    @Bindable private var preferences = LookupPreferences.shared
    var body: some View {
        SettingsPicker("Default English dictionary", selection: $preferences.englishDictionary,
                       selectedValue: Text(LocalizedStringKey(preferences.englishDictionary.title))) {
            ForEach(EnglishLookupDictionary.allCases) { dictionary in
                Text(LocalizedStringKey(dictionary.title)).tag(dictionary)
            }
        }
        Toggle("Show dictionary switch", isOn: $preferences.showsLanguageSwitch)
    }
}

struct WordBookSettingsSection: View {
    let onSelectWord: (String) -> Void
    @Bindable private var preferences = LookupPreferences.shared

    var body: some View {
        Section {
            NavigationLink {
                WordBookView(onSelectWord: onSelectWord)
            } label: {
                Label("Word Book", systemImage: "book.closed")
            }
            SettingsPicker("Auto-add to Word Book", selection: $preferences.wordBookAutoAddRule,
                           selectedValue: Text(LocalizedStringKey(preferences.wordBookAutoAddRule.title))) {
                ForEach(WordBookAutoAddRule.allCases) { rule in
                    Text(LocalizedStringKey(rule.title)).tag(rule)
                }
            }
            .onChange(of: preferences.wordBookAutoAddRule) { _, rule in
                WordBookStore.shared.addEligibleWords(after: rule.rawValue)
            }
        }
    }
}

struct WordBookView: View {
    let onSelectWord: (String) -> Void
    @State private var wordBook = WordBookStore.shared
    @State private var preferences = LookupPreferences.shared
    @State private var showingClearConfirmation = false

    var body: some View {
        Group {
            if wordBook.words.isEmpty {
                ContentUnavailableView(
                    "No words in your Word Book",
                    systemImage: "book.closed",
                    description: Text("Add words here, or choose when automatic adding should begin.")
                )
            } else {
                List {
                    ForEach(wordBook.words) { word in
                        Button {
                            onSelectWord(word.word)
                        } label: {
                            HStack {
                                Text(word.word)
                                    .font(.body.weight(.medium))
                                Spacer()
                                Text(L10n.ui("%@ lookups", L10n.number(word.count)))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.automatic)
                        .accessibilityElement(children: .combine)
                    }
                    .onDelete { offsets in
                        for index in offsets { wordBook.remove(wordBook.words[index]) }
                    }
                }
            }
        }
        .navigationTitle("Word Book")
        .instaDictBackButton()
        .toolbar {
            if !wordBook.words.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear", systemImage: "trash", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .labelStyle(.iconOnly)
                    #if os(watchOS)
                    .instaDictCircleButton()
                    #endif
                }
            }
        }
        .confirmationDialog("Clear all Word Book words?", isPresented: $showingClearConfirmation,
                            titleVisibility: .visible) {
            Button("Clear", role: .destructive) { wordBook.clear() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            wordBook.addEligibleWords(after: preferences.wordBookAutoAddRule.rawValue)
        }
    }
}

typealias ReviewWordsView = WordBookView
