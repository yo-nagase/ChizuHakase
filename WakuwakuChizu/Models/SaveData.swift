import Foundation

nonisolated struct StageRecord: Codable, Sendable, Equatable {
    var stars: Int
    var score: Int
}

nonisolated struct Settings: Codable, Sendable, Equatable {
    var soundEnabled = true
    var speechEnabled = true
    var voiceInputEnabled = false
    /// Child mode is the product; adult mode is the accommodation.
    var textMode: TextMode = .kids

    // Explicit decoding so a save file written by an older build (missing a
    // key) keeps the default instead of failing the whole decode and wiping
    // the child's progress.
    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        speechEnabled = try c.decodeIfPresent(Bool.self, forKey: .speechEnabled) ?? true
        voiceInputEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceInputEnabled) ?? false
        // A save written before this setting existed is a child's save.
        textMode = try c.decodeIfPresent(TextMode.self, forKey: .textMode) ?? .kids
    }
}

nonisolated struct SaveData: Codable, Sendable, Equatable {
    /// 2 split the stage records per quiz mode. Version 1 had one mode and
    /// wrote a flat `stages` dictionary.
    static let currentVersion = 2

    var version: Int = SaveData.currentVersion
    /// prefecture code -> 0...3.
    ///
    /// Deliberately *not* split by mode: both directions teach the same
    /// prefecture, and a child should not have two separate maps to fill in.
    var mastery: [Int: Int] = [:]
    /// card id -> owned count, 0...2 (2 means the shiny copy is owned)
    var cards: [String: Int] = [:]
    /// quiz mode -> stage index -> best record.
    ///
    /// Stars and score *are* per mode: they measure a run, and the two modes
    /// are not the same run.
    var records: [String: [Int: StageRecord]] = [:]
    var settings: Settings = .init()

    private enum CodingKeys: String, CodingKey {
        case version, mastery, cards, records, settings
        /// Version 1's flat records. Read, never written.
        case stages
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? SaveData.currentVersion
        mastery = try c.decodeIfPresent([Int: Int].self, forKey: .mastery) ?? [:]
        cards = try c.decodeIfPresent([String: Int].self, forKey: .cards) ?? [:]
        records = try c.decodeIfPresent([String: [Int: StageRecord]].self,
                                        forKey: .records) ?? [:]
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? .init()

        // Everything version 1 recorded was played by tapping the map, so that
        // is where it belongs. Merged rather than assigned, and losing to
        // anything already in `records`, so re-reading a migrated file cannot
        // walk a newer best score backwards.
        if let legacy = try c.decodeIfPresent([Int: StageRecord].self, forKey: .stages),
           !legacy.isEmpty {
            records[QuizMode.findOnMap.rawValue, default: [:]]
                .merge(legacy) { current, _ in current }
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(mastery, forKey: .mastery)
        try c.encode(cards, forKey: .cards)
        try c.encode(records, forKey: .records)
        try c.encode(settings, forKey: .settings)
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

    func record(forStage index: Int, mode: QuizMode) -> StageRecord? {
        records[mode.rawValue]?[index]
    }

    /// The best a stage has ever gone, whichever way it was played. Used where
    /// the mode is not the point — the stage picker shows the mode you are in,
    /// but the title screen counts a stage as cleared either way.
    func bestRecord(forStage index: Int) -> StageRecord? {
        QuizMode.allCases
            .compactMap { record(forStage: index, mode: $0) }
            .max { $0.score < $1.score }
    }

    var totalOwnedCards: Int { cards.values.filter { $0 > 0 }.count }

    var shinyCardCount: Int { cards.values.filter { $0 >= GameRules.maxCardCopies }.count }

    /// Prefectures at level 3 — the ones drawn with a gold border on the my-map.
    var sparklingPrefectureCount: Int {
        mastery.values.filter { $0 >= GameRules.maxMastery }.count
    }
}
