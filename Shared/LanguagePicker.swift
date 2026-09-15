import SwiftUI

struct InterfaceLanguagePicker: View {
    @Bindable private var settings = LanguageSettings.shared

    var body: some View {
        Picker("App language", selection: $settings.selection) {
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
        Picker("Pronunciation order", selection: $order) {
            ForEach(PronunciationOrder.allCases) { order in
                Text(LocalizedStringKey(order.title)).tag(order)
            }
        }
    }
}

struct LookupPreferencesPicker: View {
    @Bindable private var preferences = LookupPreferences.shared
    var body: some View {
        Picker("Default English dictionary", selection: $preferences.englishDictionary) {
            ForEach(EnglishLookupDictionary.allCases) { dictionary in
                Text(LocalizedStringKey(dictionary.title)).tag(dictionary)
            }
        }
        Toggle("Show dictionary switch", isOn: $preferences.showsLanguageSwitch)
    }
}
