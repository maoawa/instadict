import Foundation

enum PronunciationOrder: String, CaseIterable, Identifiable, Sendable {
    case britishFirst, americanFirst
    static let preferenceKey = "pronunciationOrder.v1"
    var id: String { rawValue }
    var title: String { self == .britishFirst ? "British first" : "American first" }

    func pronunciations(for entry: DictionaryEntry) -> [Pronunciation] {
        let all = [Pronunciation(region: "UK", ipa: entry.britishIPA ?? ""),
                   Pronunciation(region: "US", ipa: entry.americanIPA ?? "")]
        return (self == .britishFirst ? all : Array(all.reversed())).compactMap { item in
            let ipa = item.ipa.trimmingCharacters(in: .whitespacesAndNewlines)
            return ipa.isEmpty ? nil : Pronunciation(region: item.region, ipa: ipa)
        }
    }
}

struct Pronunciation: Identifiable {
    let region: String
    let ipa: String
    var id: String { region }
}
