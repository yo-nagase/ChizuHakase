import Foundation

nonisolated struct StageRecord: Codable, Sendable, Equatable {
    var stars: Int
    var score: Int
}

nonisolated struct Settings: Codable, Sendable, Equatable {
    var soundEnabled = true
    var speechEnabled = true
    var voiceInputEnabled = false

    // Explicit decoding so a save file written by an older build (missing a
    // key) keeps the default instead of failing the whole decode and wiping
    // the child's progress.
    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        speechEnabled = try c.decodeIfPresent(Bool.self, forKey: .speechEnabled) ?? true
        voiceInputEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceInputEnabled) ?? false
    }
}

nonisolated struct SaveData: Codable, Sendable, Equatable {
    static let currentVersion = 1

    var version: Int = SaveData.currentVersion
    /// prefecture code -> 0...3
    var mastery: [Int: Int] = [:]
    /// card id -> owned count, 0...2 (2 means the shiny copy is owned)
    var cards: [String: Int] = [:]
    /// stage index -> best record
    var stages: [Int: StageRecord] = [:]
    var settings: Settings = .init()

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? SaveData.currentVersion
        mastery = try c.decodeIfPresent([Int: Int].self, forKey: .mastery) ?? [:]
        cards = try c.decodeIfPresent([String: Int].self, forKey: .cards) ?? [:]
        stages = try c.decodeIfPresent([Int: StageRecord].self, forKey: .stages) ?? [:]
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? .init()
    }

    // MARK: - Derived reads

    func masteryLevel(of code: Int) -> Int {
        min(GameRules.maxMastery, max(0, mastery[code] ?? 0))
    }

    func ownedCount(of cardID: String) -> Int {
        min(GameRules.maxCardCopies, max(0, cards[cardID] ?? 0))
    }

    func owns(_ cardID: String) -> Bool { ownedCount(of: cardID) > 0 }

    func isShiny(_ cardID: String) -> Bool {
        ownedCount(of: cardID) >= GameRules.maxCardCopies
    }

    func record(forStage index: Int) -> StageRecord? { stages[index] }

    var totalOwnedCards: Int { cards.values.filter { $0 > 0 }.count }

    var shinyCardCount: Int { cards.values.filter { $0 >= GameRules.maxCardCopies }.count }

    /// Prefectures at level 3 — the ones drawn with a gold border on the my-map.
    var sparklingPrefectureCount: Int {
        mastery.values.filter { $0 >= GameRules.maxMastery }.count
    }
}
