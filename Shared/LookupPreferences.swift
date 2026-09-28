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

enum WordBookAutoAddRule: Int, CaseIterable, Identifiable, Sendable {
    case never = 0
    case afterTwo = 2
    case afterThree = 3
    case afterFour = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .never: "No"
        case .afterTwo: "After 2 lookups"
        case .afterThree: "After 3 lookups"
        case .afterFour: "After 4 lookups"
        }
    }
}

@MainActor @Observable
final class LookupPreferences {
    static let shared = LookupPreferences()
    static let dictionaryKey = "defaultEnglishDictionary.v1"
    static let switchKey = "showDictionarySwitch.v1"
    static let wordBookAutoAddKey = "wordBookAutoAddCount.v2"
    private static let legacyWordBookAutoAddKey = "wordBookAutoAdd.v1"
    private static let legacyReviewKey = "reviewEnabled.v1"
    @ObservationIgnored private let defaults: UserDefaults
    var englishDictionary: EnglishLookupDictionary {
        didSet { defaults.set(englishDictionary.rawValue, forKey: Self.dictionaryKey) }
    }
    var showsLanguageSwitch: Bool {
        didSet { defaults.set(showsLanguageSwitch, forKey: Self.switchKey) }
    }
    var wordBookAutoAddRule: WordBookAutoAddRule {
        didSet { defaults.set(wordBookAutoAddRule.rawValue, forKey: Self.wordBookAutoAddKey) }
    }
    @available(*, deprecated, renamed: "wordBookAutoAddRule")
    var reviewEnabled: Bool {
        get { wordBookAutoAddRule != .never }
        set { wordBookAutoAddRule = newValue ? .afterTwo : .never }
    }
    @available(*, deprecated, message: "Use wordBookAutoAddRule instead")
    var wordBookAutoAdd: Bool {
        get { wordBookAutoAddRule != .never }
        set { wordBookAutoAddRule = newValue ? .afterTwo : .never }
    }

    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        englishDictionary = defaults.string(forKey: Self.dictionaryKey).flatMap(EnglishLookupDictionary.init(rawValue:))
            ?? .deviceDefault(preferredLanguages: preferredLanguages)
        showsLanguageSwitch = defaults.object(forKey: Self.switchKey) == nil ? true : defaults.bool(forKey: Self.switchKey)
        if let savedCount = defaults.object(forKey: Self.wordBookAutoAddKey) as? NSNumber,
           let rule = WordBookAutoAddRule(rawValue: savedCount.intValue) {
            wordBookAutoAddRule = rule
        } else if let legacyValue = defaults.object(forKey: Self.legacyWordBookAutoAddKey) as? Bool {
            wordBookAutoAddRule = legacyValue ? .afterTwo : .never
        } else if let legacyValue = defaults.object(forKey: Self.legacyReviewKey) as? Bool {
            wordBookAutoAddRule = legacyValue ? .afterTwo : .never
        } else {
            wordBookAutoAddRule = .afterTwo
        }
        // Capture the device-language default once; future launches respect the saved choice.
        defaults.set(englishDictionary.rawValue, forKey: Self.dictionaryKey)
        defaults.set(showsLanguageSwitch, forKey: Self.switchKey)
        defaults.set(wordBookAutoAddRule.rawValue, forKey: Self.wordBookAutoAddKey)
    }
}
