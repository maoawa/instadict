import Foundation
import Observation

enum InterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }
    var nativeName: String {
        switch self {
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    static func deviceDefault(preferredLanguages: [String]) -> Self {
        // Use the primary device language, not the first supported language
        // somewhere farther down its preferred-language list.
        guard let identifier = preferredLanguages.first else { return .english }
        let language = Locale.Language(identifier: identifier.replacingOccurrences(of: "_", with: "-"))
        guard language.languageCode?.identifier == "zh" else { return .english }
        return .simplifiedChinese
    }
}

enum InterfaceLanguageSelection: String, CaseIterable, Identifiable, Sendable {
    case system, english = "en", simplifiedChinese = "zh-Hans"
    var id: String { rawValue }
    var language: InterfaceLanguage? { InterfaceLanguage(rawValue: rawValue) }
}

@MainActor @Observable
final class LanguageSettings {
    static let shared = LanguageSettings()
    static let preferenceKey = "interfaceLanguage.v1"
    static let selectionKey = "interfaceLanguageSelection.v2"
    @ObservationIgnored private let defaults: UserDefaults
    private var deviceLanguage: InterfaceLanguage
    var selection: InterfaceLanguageSelection {
        didSet { persist() }
    }
    var language: InterfaceLanguage {
        get { selection.language ?? deviceLanguage }
        set { selection = InterfaceLanguageSelection(rawValue: newValue.rawValue)! }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        deviceLanguage = .deviceDefault(preferredLanguages: preferredLanguages)
        // Preserve existing explicit choices when upgrading from the old picker.
        selection = defaults.string(forKey: Self.selectionKey).flatMap(InterfaceLanguageSelection.init(rawValue:))
            ?? defaults.string(forKey: Self.preferenceKey).flatMap(InterfaceLanguageSelection.init(rawValue:))
            ?? .system
        persist()
    }

    func refreshDeviceLanguage(preferredLanguages: [String] = Locale.preferredLanguages) {
        deviceLanguage = .deviceDefault(preferredLanguages: preferredLanguages)
        persist()
    }

    func useDeviceLanguage() {
        refreshDeviceLanguage()
        selection = .system
    }

    private func persist() {
        defaults.set(selection.rawValue, forKey: Self.selectionKey)
        defaults.set(language.rawValue, forKey: Self.preferenceKey)
    }
}

enum L10n {
    static func errorMessage(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost:
                return "No internet connection. Connect to the internet and try again."
            case NSURLErrorTimedOut:
                return "The request timed out. Please try again."
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed, NSURLErrorCannotConnectToHost:
                return "Couldn’t connect to the download server. Check the source address and try again."
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot:
                return "Couldn’t establish a secure connection to the download server."
            case NSURLErrorCancelled: return "This transfer was replaced or canceled."
            default: break
            }
        }
        if error.domain == NSCocoaErrorDomain, error.code == CocoaError.fileWriteOutOfSpace.rawValue {
            return "Not enough storage. Free up some space and try again."
        }
        return error.localizedDescription
    }

    static var resources: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    static func text(_ key: String, language: InterfaceLanguage) -> String {
        guard let path = resources.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, language: InterfaceLanguage, _ arguments: CVarArg...) -> String {
        String(format: text(key, language: language), locale: language.locale, arguments: arguments)
    }

    // Reading the observable language here also refreshes dynamic SwiftUI text
    // immediately, without replacing the navigation stack or dismissing Settings.
    @MainActor static func ui(_ key: String) -> String { text(key, language: LanguageSettings.shared.language) }
    @MainActor static func ui(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: ui(key), locale: LanguageSettings.shared.language.locale, arguments: arguments)
    }

    @MainActor static func number(_ value: Int) -> String {
        value.formatted(.number.locale(LanguageSettings.shared.language.locale))
    }

    @MainActor static func fileSize(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file).locale(LanguageSettings.shared.language.locale))
    }

    /// Status/error strings are kept in canonical English on disk and over
    /// WatchConnectivity, so two devices can display the same receipt in different
    /// languages, including after the user changes language while it is visible.
    static func message(_ value: String, language: InterfaceLanguage) -> String {
        let translated = text(value, language: language)
        if translated != value { return translated }
        for (prefix, template) in [
            ("Using the saved catalog. ", "Using the saved catalog. %@"),
            ("Couldn’t check the Watch: ", "Couldn’t check the Watch: %@")
        ] where value.hasPrefix(prefix) {
            return format(template, language: language, message(String(value.dropFirst(prefix.count)), language: language))
        }
        for (prefix, suffix, template) in [
            ("Sending to Watch · ", "%", "Sending to Watch · %@%%"),
            ("The download server returned an error (", "). Please try again.", "The download server returned an error (%@). Please try again.")
        ] where value.hasPrefix(prefix) && value.hasSuffix(suffix) {
            return format(template, language: language, String(value.dropFirst(prefix.count).dropLast(suffix.count)))
        }
        for id in DictionaryID.allCases {
            if value == "Download \(id.title) in Settings." || value == "Send \(id.title) from InstaDict on your iPhone." {
                return format("Download %@ in Settings.", language: language, text(id.title, language: language))
            }
        }
        // OS-provided diagnostics and unknown source labels remain readable.
        return value
    }

    @MainActor static func message(_ value: String) -> String {
        message(value, language: LanguageSettings.shared.language)
    }

    static func grammaticalLabel(_ value: String, language: InterfaceLanguage) -> String {
        // Normalize upstream aliases only for presentation. Never modify the pack.
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let aliases = ["n.": "noun", "n": "noun", "v.": "verb", "v": "verb",
                       "vt.": "transitive verb", "vi.": "intransitive verb",
                       "a.": "adjective", "adj.": "adjective", "adj": "adjective",
                       "adjective satellite": "adjective", "r": "adverb", "adv.": "adverb",
                       "pron.": "pronoun", "prep.": "preposition", "conj.": "conjunction",
                       "interj.": "interjection", "int.": "interjection", "art.": "article",
                       "num.": "numeral", "aux.": "auxiliary verb", "det.": "determiner"]
        let key = aliases[normalized] ?? normalized
        let translated = text(key, language: language)
        return translated == key ? value : translated
    }

    @MainActor static func grammaticalLabel(_ value: String) -> String {
        grammaticalLabel(value, language: LanguageSettings.shared.language)
    }
}
