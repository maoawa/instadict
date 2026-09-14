import Foundation
import Testing
@testable import InstaDictCore

@Test(arguments: ["en", "en-US", "en-GB", "en-SG", "en-AU", "EN-gb", "en_US"])
func englishDeviceVariants(_ identifier: String) {
    #expect(InterfaceLanguage.deviceDefault(preferredLanguages: [identifier]) == .english)
}

@Test(arguments: ["zh", "zh-CN", "zh-SG", "zh-TW", "zh-HK", "zh-MO", "zh-Hans", "zh-Hant",
                  "zh-Hant-TW", "zh-Hant-HK", "zh-Hans-SG", "zh_TW", "ZH-hk"])
func allChineseDeviceVariantsUseSimplifiedChinese(_ identifier: String) {
    #expect(InterfaceLanguage.deviceDefault(preferredLanguages: [identifier]) == .simplifiedChinese)
}

@Test func unsupportedPrimaryDeviceLanguageFallsBackToEnglish() {
    for preferred in [[], ["fr-FR"], ["ja-JP", "zh-CN"], ["de-DE", "en-GB"], ["ar", "zh-Hant"], ["zhx"], [""]] {
        #expect(InterfaceLanguage.deviceDefault(preferredLanguages: preferred) == .english)
    }
    #expect(InterfaceLanguage.allCases.map(\.rawValue) == ["en", "zh-Hans"])
}

@Test @MainActor func interfaceLanguageIsInitializedOnceAndPersistsExplicitChoices() throws {
    let name = "InstaDict.LocalizationTests." + UUID().uuidString
    let defaults = try #require(UserDefaults(suiteName: name))
    defer { defaults.removePersistentDomain(forName: name) }
    let first = LanguageSettings(defaults: defaults, preferredLanguages: ["zh-HK"])
    #expect(first.language == .simplifiedChinese)
    #expect(defaults.string(forKey: LanguageSettings.preferenceKey) == "zh-Hans")
    let reopened = LanguageSettings(defaults: defaults, preferredLanguages: ["en-SG"])
    #expect(reopened.language == .simplifiedChinese)
    reopened.language = .english
    #expect(LanguageSettings(defaults: defaults, preferredLanguages: ["zh-TW"]).language == .english)
    defaults.set("invalid", forKey: LanguageSettings.preferenceKey)
    #expect(LanguageSettings(defaults: defaults, preferredLanguages: ["fr-FR"]).language == .english)
}

@Test func localizedGrammarRegionsAndDynamicMessages() {
    let chinese = InterfaceLanguage.simplifiedChinese
    #expect(L10n.text("US", language: chinese) == "美")
    #expect(L10n.text("UK", language: chinese) == "英")
    for (source, expected) in [("past tense", "过去式"), ("past participle", "过去分词"),
                               ("present participle", "现在分词"), ("third person", "第三人称单数"),
                               ("verb", "v. 动词"), ("pronoun", "pron. 代词"), ("noun", "n. 名词"),
                               ("adj.", "adj. 形容词"), ("VT.", "vt. 及物动词")] {
        #expect(L10n.grammaticalLabel(source, language: chinese) == expected)
        #expect(L10n.grammaticalLabel(source, language: .english) == source)
    }
    #expect(L10n.grammaticalLabel("unknown upstream label", language: chinese) == "unknown upstream label")
    #expect(L10n.message("Sending to Watch · 25%", language: chinese) == "正在发送到手表 · 25%")
    #expect(L10n.message("The download server returned an error (503). Please try again.", language: chinese)
            == "下载服务器返回错误（503），请重试。")
    let saved = "Using the saved catalog. This transfer was replaced or canceled."
    #expect(L10n.message(saved, language: chinese) == "正在使用已保存的目录。此传输已被替换或取消。")
    #expect(L10n.message(saved, language: .english) == saved)
    #expect(L10n.message("Send English–English from InstaDict on your iPhone.", language: chinese) == "请在设置中下载英英词典。")
    #expect(L10n.format("Also: %@", language: chinese, "roam, wander") == "近义词：roam, wander")
}

@Test func networkDiagnosticsAreLocalizedUsingTheAppLanguage() {
    // The OS may already have localized the NSError in a different language.
    let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                          userInfo: [NSLocalizedDescriptionKey: "设备语言中的系统错误"])
    let canonical = L10n.errorMessage(offline)
    #expect(canonical == "No internet connection. Connect to the internet and try again.")
    #expect(L10n.message(canonical, language: .simplifiedChinese) == "无互联网连接。请联网后重试。")
    #expect(L10n.message(canonical, language: .english) == canonical)
}

@Test func bothTranslationTablesHaveIdenticalKeysAndFormatArguments() throws {
    func table(_ language: String) throws -> [String: String] {
        let path = try #require(L10n.resources.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language))
        return try #require(PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: path)), format: nil) as? [String: String])
    }
    let english = try table("en")
    let chinese = try table("zh-Hans")
    #expect(Set(english.keys) == Set(chinese.keys))
    #expect(english.count >= 160)
    let placeholder = try NSRegularExpression(pattern: #"%(?:\d+\$)?(?:@|lld|d|%)"#)
    func arguments(_ value: String) -> [String] {
        placeholder.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
            String(value[Range($0.range, in: value)!])
        }
    }
    for (key, translated) in chinese {
        #expect(!translated.isEmpty)
        #expect(arguments(key) == arguments(translated), "Format arguments differ for \(key)")
        #expect(L10n.text(key, language: .simplifiedChinese) == translated)
    }
}
