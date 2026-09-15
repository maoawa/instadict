// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InstaDictCore",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.library(name: "InstaDictCore", targets: ["InstaDictCore"])],
    targets: [
        .target(
            name: "InstaDictCore",
            path: "Shared",
            exclude: ["Resources/DictionaryCatalog.json", "DictionarySync.swift", "DictionaryDownloads.swift", "DefinitionView.swift", "LanguagePicker.swift", "IntroductionView.swift", "ButtonStyles.swift", "FeedbackButton.swift"],
            sources: ["DictionaryEntry.swift", "DictionaryText.swift", "DictionaryStore.swift", "LookupModel.swift", "DictionaryPack.swift", "DictionaryLibrary.swift", "Localization.swift", "PronunciationPreference.swift", "LookupPreferences.swift"],
            resources: [.process("Resources/Localizations")],
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedLibrary("z")]
        ),
        .testTarget(name: "InstaDictCoreTests", dependencies: ["InstaDictCore"], path: "Tests")
    ]
)
