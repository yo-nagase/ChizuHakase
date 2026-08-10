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
    /// 4 stretched the stars to fifteen and added the prefecture streaks with
    /// their rainbow latch. 3 gave every card five stars instead of a
    /// plain/キラ pair. 2 split the stage records per quiz mode. Version 1 had
    /// one mode and wrote a flat `stages` dictionary.
    static let currentVersion = 4

    var version: Int = SaveData.currentVersion
    /// prefecture code -> 0...3.
    ///
    /// Deliberately *not* split by mode: both directions teach the same
    /// prefecture, and a child should not have two separate maps to fill in.
    var mastery: [Int: Int] = [:]
    /// card id -> stars, 0...15. Five is silver, fifteen is gold.
    var cards: [String: Int] = [:]
    /// Cards that were gold while their prefecture's streak stood at fifteen.
    ///
    /// Recorded rather than derived, because it cannot be derived: the streak
    /// resets on the next fumble, and the rainbow must not reset with it
    /// (CLAUDE.md §12).
    var rainbow: Set<String> = []
    /// prefecture code -> consecutive clean answers, running across sessions.
    var streaks: [Int: Int] = [:]
    /// quiz mode -> stage index -> best record.
    ///
    /// Stars and score *are* per mode: they measure a run, and the two modes
    /// are not the same run.
    var records: [String: [Int: StageRecord]] = [:]
    var settings: Settings = .init()

    private enum CodingKeys: String, CodingKey {
        case version, mastery, cards, rainbow, streaks, records, settings
        /// Version 1's flat records. Read, never written.
        case stages
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decoding *is* the migration — the legacy key is folded in below — so
        // what is in memory is the current shape whatever the file claimed. A
        // file from a future build keeps its own number, so running an older
        // build cannot relabel it and then write the older shape under it.
        let stored = try c.decodeIfPresent(Int.self, forKey: .version) ?? SaveData.currentVersion
        version = max(stored, SaveData.currentVersion)
        mastery = try c.decodeIfPresent([Int: Int].self, forKey: .mastery) ?? [:]
        cards = try c.decodeIfPresent([String: Int].self, forKey: .cards) ?? [:]
        if stored < 3 {
            // Two used to be the whole scale, and the second copy was キラ. A
            // card that had reached it arrives at the top of version 3's scale
            // (five) and the lift below carries it the rest of the way, so it
            // stays gold rather than being demoted to a two-star plain card.
            // Handing back a キラ that was already won is precisely what §12
            // rules out.
            cards = cards.mapValues { $0 >= 2 ? 5 : $0 }
        }
        if stored < 4 {
            cards = cards.mapValues(Self.liftV3Stars)
        }
        rainbow = try c.decodeIfPresent(Set<String>.self, forKey: .rainbow) ?? []
        streaks = try c.decodeIfPresent([Int: Int].self, forKey: .streaks) ?? [:]
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

    /// Version 3 → 4 stretched the star scale: silver moved from three to
    /// five, gold from five to fifteen. Counts move by their place on the old
    /// ladder — the tier is what the child sees, so it is the tier that must
    /// not demote (CLAUDE.md §12). An old three lands on the new silver floor,
    /// a four (second of two silver steps) lands mid-silver, gold stays gold.
    private static func liftV3Stars(_ stars: Int) -> Int {
        switch stars {
        case ..<3: max(0, stars)
        case 3: GameRules.silverStars
        case 4: 10
        default: GameRules.maxCardStars
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(mastery, forKey: .mastery)
        try c.encode(cards, forKey: .cards)
        try c.encode(rainbow, forKey: .rainbow)
        try c.encode(streaks, forKey: .streaks)
        try c.encode(records, forKey: .records)
        try c.encode(settings, forKey: .settings)
    }

    // MARK: - Derived reads

    func masteryLevel(of code: Int) -> Int {
        min(GameRules.maxMastery, max(0, mastery[code] ?? 0))
    }

    func stars(of cardID: String) -> Int {
        min(GameRules.maxCardStars, max(0, cards[cardID] ?? 0))
    }

    func owns(_ cardID: String) -> Bool { stars(of: cardID) > 0 }

    func isRainbow(_ cardID: String) -> Bool { rainbow.contains(cardID) }

    func tier(of cardID: String) -> CardTier {
        CardTier(stars: stars(of: cardID), rainbow: isRainbow(cardID))
    }

    func streak(of prefectureCode: Int) -> Int {
        max(0, streaks[prefectureCode] ?? 0)
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

    /// Silver and up — see `CardTier.isSpecial`.
    var specialCardCount: Int { cards.keys.filter { tier(of: $0).isSpecial }.count }

    /// Gold and rainbow: a card that went rainbow has not stopped being gold.
    var goldCardCount: Int { cards.keys.filter { tier(of: $0) >= .gold }.count }

    /// Prefectures at level 3 — the ones drawn with a gold border on the my-map.
    var sparklingPrefectureCount: Int {
        mastery.values.filter { $0 >= GameRules.maxMastery }.count
    }
}
