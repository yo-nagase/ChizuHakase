import Foundation

/// A collectible specialty of one prefecture. 47 x 3 = 141 total.
nonisolated struct SpecialtyCard: Identifiable, Sendable, Hashable, Codable {
    enum Category: String, Sendable, Codable, CaseIterable {
        case food, landmark, nature, craft

        /// Label for the card book filter row.
        var kanaLabel: String {
            switch self {
            case .food: "たべもの"
            case .landmark: "めいしょ"
            case .nature: "しぜん"
            case .craft: "つくるもの"
            }
        }

        var emoji: String {
            switch self {
            case .food: "🍙"
            case .landmark: "🏯"
            case .nature: "🌲"
            case .craft: "🎨"
            }
        }
    }

    /// "{2-digit prefecture code}-{1...3}". Save-data key — never change it
    /// for a card that has shipped.
    let id: String
    let prefectureCode: Int
    let emoji: String
    let nameKana: String
    let nameKanji: String
    let category: Category
    let description: String
    /// Asset name of the painted card, for the ones that have been drawn.
    ///
    /// Only キラカード show it (CLAUDE.md §5): the plain card stays an emoji, so
    /// promoting one to キラ turns it into a picture. Optional while the full
    /// set of illustrations is produced in stages — a card without art simply
    /// stays an emoji rather than showing a placeholder.
    var art: String?
}

/// All cards, indexed for lookup by prefecture and by id.
nonisolated struct CardCatalog: Sendable {
    let all: [SpecialtyCard]
    private let byPrefecture: [Int: [SpecialtyCard]]
    private let byID: [String: SpecialtyCard]

    init(cards: [SpecialtyCard]) {
        self.all = cards
        self.byPrefecture = Dictionary(grouping: cards, by: \.prefectureCode)
        self.byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func cards(for prefectureCode: Int) -> [SpecialtyCard] {
        byPrefecture[prefectureCode] ?? []
    }

    subscript(id: String) -> SpecialtyCard? { byID[id] }

    var count: Int { all.count }

    static let empty = CardCatalog(cards: [])
}
