import Foundation
import Testing
@testable import InstaDictCore

@Test(arguments: ["en", "en-US", "en-GB", "en-SG", "fr-FR", "ja-JP", "zhx", ""])
func englishLookupDefaultsForEnglishAndUnsupportedLanguages(_ identifier: String) {
    #expect(EnglishLookupDictionary.deviceDefault(preferredLanguages: [identifier]) == .englishEnglish)
}

@Test(arguments: ["zh", "zh-CN", "zh-TW", "zh-HK", "zh-Hant-HK", "zh_SG", "ZH-hk"])
func englishLookupDefaultsForChineseVariants(_ identifier: String) {
    #expect(EnglishLookupDictionary.deviceDefault(preferredLanguages: [identifier]) == .englishChinese)
}

@Test @MainActor func lookupDefaultsAreCapturedOnceAndUserChoicesPersist() throws {
    let name = "InstaDict.LookupPreferencesTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let initial = LookupPreferences(defaults: defaults, preferredLanguages: ["zh-TW"])
    #expect(initial.englishDictionary == .englishChinese)
    #expect(initial.showsLanguageSwitch)
    let reopened = LookupPreferences(defaults: defaults, preferredLanguages: ["en-GB"])
    #expect(reopened.englishDictionary == .englishChinese)
    reopened.englishDictionary = .englishEnglish
    reopened.showsLanguageSwitch = false
    let changed = LookupPreferences(defaults: defaults, preferredLanguages: ["zh-HK"])
    #expect(changed.englishDictionary == .englishEnglish)
    #expect(!changed.showsLanguageSwitch)
    #expect(EnglishLookupDictionary.deviceDefault(preferredLanguages: []) == .englishEnglish)
    #expect(EnglishLookupDictionary.deviceDefault(preferredLanguages: ["ja-JP", "zh-CN"]) == .englishEnglish)
}

@Test @MainActor func lookupUsesPreferenceWhileSwitchingOnlyAffectsCurrentWord() throws {
    let name = "InstaDict.LookupSelectionTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let preferences = LookupPreferences(defaults: defaults, preferredLanguages: ["zh-HK"])
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let model = LookupModel(library: DictionaryLibrary(root: root), preferences: preferences)
    model.lookUp("hello")
    #expect(model.dictionary == .englishChinese)
    model.switchLanguage()
    #expect(model.dictionary == .englishEnglish)
    model.reloadCurrent()
    #expect(model.dictionary == .englishEnglish)
    #expect(preferences.englishDictionary == .englishChinese)
    model.lookUp("apple")
    #expect(model.dictionary == .englishChinese)
    preferences.englishDictionary = .englishEnglish
    model.lookUp("pear")
    #expect(model.dictionary == .englishEnglish)
    model.lookUp("中文")
    #expect(model.dictionary == .chineseEnglish)
    #expect(!model.canSwitchLanguage)
}
