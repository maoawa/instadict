import Foundation
import Observation

enum EnglishLookupDictionary: String, CaseIterable, Identifiable, Sendable {
    case englishEnglish = "english-english"
    case englishChinese = "english-chinese"
    var id: String { rawValue }
    var dictionaryID: DictionaryID { self == .englishEnglish ? .englishEnglish : .englishChinese }
    var title: String { dictionaryID.title }
    static func deviceDefault(preferredLanguages: [String]) -> Self {
        InterfaceLanguage.deviceDefault(preferredLanguages: preferredLanguages) == .simplifiedChinese
            ? .englishChinese : .englishEnglish
    }
}

@MainActor @Observable
final class LookupPreferences {
    static let shared = LookupPreferences()
    static let dictionaryKey = "defaultEnglishDictionary.v1"
    static let switchKey = "showDictionarySwitch.v1"
    @ObservationIgnored private let defaults: UserDefaults
    var englishDictionary: EnglishLookupDictionary {
        didSet { defaults.set(englishDictionary.rawValue, forKey: Self.dictionaryKey) }
    }
    var showsLanguageSwitch: Bool {
        didSet { defaults.set(showsLanguageSwitch, forKey: Self.switchKey) }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        englishDictionary = defaults.string(forKey: Self.dictionaryKey).flatMap(EnglishLookupDictionary.init(rawValue:))
            ?? .deviceDefault(preferredLanguages: preferredLanguages)
        showsLanguageSwitch = defaults.object(forKey: Self.switchKey) == nil ? true : defaults.bool(forKey: Self.switchKey)
        // Capture the device-language default once; future launches respect the saved choice.
        defaults.set(englishDictionary.rawValue, forKey: Self.dictionaryKey)
        defaults.set(showsLanguageSwitch, forKey: Self.switchKey)
    }
}
