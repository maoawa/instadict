import SwiftUI

struct InterfaceLanguagePicker: View {
    @Bindable private var settings = LanguageSettings.shared

    var body: some View {
        Picker("App language", selection: $settings.language) {
            ForEach(InterfaceLanguage.allCases) { language in
                Text(verbatim: language.nativeName).tag(language)
            }
        }
        .accessibilityIdentifier("interfaceLanguagePicker")
        Button("Use device language") { settings.useDeviceLanguage() }
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
