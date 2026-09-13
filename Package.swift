// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InstaDictCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "InstaDictCore", targets: ["InstaDictCore"])],
    targets: [
        .target(
            name: "InstaDictCore",
            path: "Shared",
            exclude: ["Resources", "DictionarySync.swift"],
            sources: ["DictionaryEntry.swift", "DictionaryStore.swift", "LookupModel.swift", "DictionaryPack.swift", "DictionaryLibrary.swift"],
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedLibrary("z")]
        ),
        .testTarget(name: "InstaDictCoreTests", dependencies: ["InstaDictCore"], path: "Tests")
    ]
)
