import Foundation

nonisolated struct StageRecord: Codable, Sendable, Equatable {
    var stars: Int
    var score: Int
}

nonisolated struct Settings: Codable, Sendable, Equatable {
    var soundEnabled = true
    var speechEnabled = true
    /// The title theme. Off is a choice someone made at the mute button, so it
    /// survives relaunch — a mute that un-mutes itself taught the child that
    /// buttons lie.
    var musicEnabled = true
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
        // A save from before the theme song existed has expressed no opinion
        // about it, so it gets the default, not silence.
        musicEnabled = try c.decodeIfPresent(Bool.self, forKey: .musicEnabled) ?? true
        voiceInputEnabled = try c.decodeIfPresent(Bool.self, forKey: .voiceInputEnabled) ?? false
        // A save written before this setting existed is a child's save.
        textMode = try c.decodeIfPresent(TextMode.self, forKey: .textMode) ?? .kids
    }
}

/// One atlas's (ちずちょう's) worth of progress.
///
/// Japan and world get the same shape even where a field is one-sided
/// (`askedInChallenge`): a uniform shape beats a special case per atlas, and
/// an empty dictionary is harmless.
nonisolated struct AtlasSave: Codable, Sendable, Equatable {
    /// region code -> 0...5.
    ///
    /// Deliberately *not* split by quiz mode: both directions teach the same
    /// place, and a child should not have two separate maps to fill in.
    var mastery: [Int: Int] = [:]
    /// card id -> stars, 0...10. Five is silver, ten is gold.
    var cards: [String: Int] = [:]
    /// Cards that were gold while their region's clean streak reached the
    /// rainbow line.
    ///
    /// Recorded rather than derived, because it cannot be derived: the streak
    /// resets on the next fumble, and the rainbow must not reset with it
    /// (CLAUDE.md §12).
    var rainbow: Set<String> = []
    /// region code -> consecutive clean answers, running across sessions.
    var streaks: [Int: Int] = [:]
    /// quiz mode -> stage index -> best record.
    ///
    /// Stars and score *are* per mode: they measure a run, and the two modes
    /// are not the same run.
    var records: [String: [Int: StageRecord]] = [:]
    /// quiz mode -> country codes already asked in the world challenge, which
    /// draws unasked countries first (design doc §8). Not derivable from
    /// mastery — mastery is shared across modes and also moves in the
    /// continent stages, so it cannot say what the *challenge* has asked.
    ///
    /// Japan has no rotating challenge (ぜんこく asks all 47 every run), so on
    /// the japan atlas this stays empty and unread — it exists there because a
    /// uniform shape beats a special case, and empty is harmless.
    var askedInChallenge: [String: Set<Int>] = [:]

    init() {}

    // Explicit decoding for the same reason as `Settings`: a key missing from
    // an older or partial entry takes its default instead of failing the whole
    // decode and wiping the child's progress.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mastery = try c.decodeIfPresent([Int: Int].self, forKey: .mastery) ?? [:]
        cards = try c.decodeIfPresent([String: Int].self, forKey: .cards) ?? [:]
        rainbow = try c.decodeIfPresent(Set<String>.self, forKey: .rainbow) ?? []
        streaks = try c.decodeIfPresent([Int: Int].self, forKey: .streaks) ?? [:]
        records = try c.decodeIfPresent([String: [Int: StageRecord]].self,
                                        forKey: .records) ?? [:]
        askedInChallenge = try c.decodeIfPresent([String: Set<Int>].self,
                                                 forKey: .askedInChallenge) ?? [:]
    }

    // MARK: - Derived reads
    //
    // The one implementation of every clamp, for both atlases: SaveData's
    // japan-facing reads delegate here, and `SaveStore.applyStageResult`
    // reads whichever atlas it was handed. Two copies would drift.

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
}

nonisolated struct SaveData: Codable, Sendable, Equatable {
    /// 7 moved the per-atlas fields under `atlases` so the world map can save
    /// beside Japan. 6 folded the card stars down to a ten-star ladder —
    /// fifteen put the first gold about eighteen clean runs of a stage away,
    /// which no child ever reached. 5 stretched mastery to five clean answers.
    /// 4 stretched the stars to fifteen and added the prefecture streaks with
    /// their rainbow latch. 3 gave every card five stars instead of a plain/キラ
    /// pair. 2 split the stage records per quiz mode. Version 1 had one mode
    /// and wrote a flat `stages` dictionary.
    static let currentVersion = 7

    /// Canonical `atlases` keys. Once written into save files they are as
    /// frozen as card IDs — never rename.
    static let japanAtlas = "japan"
    static let worldAtlas = "world"

    var version: Int = SaveData.currentVersion

    /// Progress per atlas, keyed `japanAtlas` / `worldAtlas`.
    ///
    /// The namespace exists because *two* axes collide across atlases, not
    /// one: region codes — prefecture codes 1–47 overlap ISO 3166-1 numeric
    /// (44 is 大分県 and also バハマ) — and stage indexes, the key of
    /// `records` (index 3 is きんき in Japan and きたヨーロッパ in the world).
    /// Either is unique only inside one atlas, so mastery/streaks (codes) and
    /// records (indexes) all live under the atlas that gave them meaning.
    ///
    /// An atlas nobody has visited is absent, not stored empty.
    var atlases: [String: AtlasSave] = [:]

    var settings: Settings = .init()

    // MARK: - Japan forwards

    // 日本版の既存呼び出し口。世界版はここを通らない —
    // 読みは `atlas(SaveData.worldAtlas)`、書き込みは
    // `SaveStore.applyStageResult(_:catalog:atlas:)` が名前空間ごと書く。
    // Thin get/set forwards onto `atlases["japan"]`, so the views, SaveStore
    // and GameRules paths that predate the namespace keep compiling and
    // behaving identically. Every write through them is a get-copy, mutate,
    // set-back of one atlas entry — fine at this scale (a few hundred entries
    // at most, written at stage end, never per question).

    var mastery: [Int: Int] {
        get { atlases[Self.japanAtlas]?.mastery ?? [:] }
        set { atlases[Self.japanAtlas, default: .init()].mastery = newValue }
    }

    var cards: [String: Int] {
        get { atlases[Self.japanAtlas]?.cards ?? [:] }
        set { atlases[Self.japanAtlas, default: .init()].cards = newValue }
    }

    var rainbow: Set<String> {
        get { atlases[Self.japanAtlas]?.rainbow ?? [] }
        set { atlases[Self.japanAtlas, default: .init()].rainbow = newValue }
    }

    var streaks: [Int: Int] {
        get { atlases[Self.japanAtlas]?.streaks ?? [:] }
        set { atlases[Self.japanAtlas, default: .init()].streaks = newValue }
    }

    var records: [String: [Int: StageRecord]] {
        get { atlases[Self.japanAtlas]?.records ?? [:] }
        set { atlases[Self.japanAtlas, default: .init()].records = newValue }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case version, atlases, settings
        /// Version ≤ 6's flat per-atlas fields. Read, never written — writing
        /// both shapes would leave every future read two sources of truth.
        case mastery, cards, rainbow, streaks, records
        /// Version 1's flat records. Read, never written.
        case stages
    }

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Decoding *is* the migration — the legacy keys are folded in below —
        // so what is in memory is the current shape whatever the file claimed.
        // A file from a future build keeps its own number, so running an older
        // build cannot relabel it and then write the older shape under it.
        let stored = try c.decodeIfPresent(Int.self, forKey: .version) ?? SaveData.currentVersion
        version = max(stored, SaveData.currentVersion)
        atlases = try c.decodeIfPresent([String: AtlasSave].self, forKey: .atlases) ?? [:]
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? .init()

        // Everything below is the flat shape versions ≤ 6 wrote. It is read
        // whenever present rather than only when the number says so: a shipped
        // version 6 build that opens a version 7 file keeps the number (that
        // rule shipped with it) but saves its own flat fields under it, and
        // play recorded that way must not be dropped on the next upgrade.
        var legacyMastery = try c.decodeIfPresent([Int: Int].self, forKey: .mastery) ?? [:]
        var legacyCards = try c.decodeIfPresent([String: Int].self, forKey: .cards) ?? [:]
        if stored < 3 {
            // Two used to be the whole scale, and the second copy was キラ. A
            // card that had reached it arrives at the top of version 3's scale
            // (five) and the lift below carries it the rest of the way, so it
            // stays gold rather than being demoted to a two-star plain card.
            // Handing back a キラ that was already won is precisely what §12
            // rules out.
            legacyCards = legacyCards.mapValues { $0 >= 2 ? 5 : $0 }
        }
        if stored < 4 {
            legacyCards = legacyCards.mapValues(Self.liftV3Stars)
        }
        if stored < 5 {
            legacyMastery = legacyMastery.mapValues(Self.liftV4Mastery)
        }
        if stored < 6 {
            // Version 6 folded the star ladder from fifteen down to ten.
            // Counts past the new top fold onto it, so a tier can only rise —
            // an eleven-star silver arrives as gold, gold stays gold — and
            // nothing at or below ten moves at all.
            legacyCards = legacyCards.mapValues { min(GameRules.maxCardStars, $0) }
        }
        let legacyRainbow = try c.decodeIfPresent(Set<String>.self, forKey: .rainbow) ?? []
        let legacyStreaks = try c.decodeIfPresent([Int: Int].self, forKey: .streaks) ?? [:]
        var legacyRecords = try c.decodeIfPresent([String: [Int: StageRecord]].self,
                                                  forKey: .records) ?? [:]

        // Everything version 1 recorded was played by tapping the map, so that
        // is where it belongs. Merged rather than assigned, and losing to
        // anything already in the records, so re-reading a migrated file cannot
        // walk a newer best score backwards.
        if let flat = try c.decodeIfPresent([Int: StageRecord].self, forKey: .stages),
           !flat.isEmpty {
            legacyRecords[QuizMode.findOnMap.rawValue, default: [:]]
                .merge(flat) { current, _ in current }
        }

        // Version 7: everything the flat shape ever recorded was earned on the
        // Japan map, so all of it lands under the japan atlas. Merged losing
        // to anything already namespaced — the same one-way street as `stages`
        // above — so a file carrying both shapes cannot walk progress
        // backwards. World is not created here: no one has visited it.
        if !legacyMastery.isEmpty || !legacyCards.isEmpty || !legacyRainbow.isEmpty
            || !legacyStreaks.isEmpty || !legacyRecords.isEmpty {
            var japan = atlases[Self.japanAtlas] ?? AtlasSave()
            japan.mastery.merge(legacyMastery) { current, _ in current }
            japan.cards.merge(legacyCards) { current, _ in current }
            japan.rainbow.formUnion(legacyRainbow)
            japan.streaks.merge(legacyStreaks) { current, _ in current }
            for (mode, recs) in legacyRecords {
                japan.records[mode, default: [:]].merge(recs) { current, _ in current }
            }
            atlases[Self.japanAtlas] = japan
        }

        // Content lifts from version 8 on belong HERE, running on `atlases`
        // values. The flat fields above only ever carry ≤6-shaped japan data,
        // so a new `if stored < 8` in the lift block up there could never
        // reach what a v7-native file stored — and would pass the whole test
        // suite while missing it.
    }

    /// Version 3's five-step ladder lands by place on the current one. Counts
    /// move by their place, not their number — the tier is what the child
    /// sees, so it is the tier that must not demote (CLAUDE.md §12). An old
    /// three lands on the silver floor, a four (second of two silver steps)
    /// lands mid-silver, gold stays gold. Written against the current ladder
    /// directly rather than replaying version 4's stretch to fifteen, so the
    /// fold below has nothing to undo here.
    private static func liftV3Stars(_ stars: Int) -> Int {
        switch stars {
        case ..<3: max(0, stars)
        case 3: GameRules.silverStars
        case 4: 7
        default: GameRules.maxCardStars
        }
    }

    /// Version 4 → 5 stretched mastery: キラキラ moved from three clean answers
    /// to five. The map draws four visual states (grey, light green, deep
    /// green, gold), and a level moves so that neither its colour nor its
    /// distance to the next state gets worse (CLAUDE.md §12): old 1 → 2 (light,
    /// one step from deep), old 2 → 4 (deep, one step from gold), and a
    /// キラキラ that was earned stays キラキラ.
    private static func liftV4Mastery(_ level: Int) -> Int {
        switch level {
        case ..<1: 0
        case 1: 2
        case 2: 4
        default: GameRules.maxMastery
        }
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(atlases, forKey: .atlases)
        try c.encode(settings, forKey: .settings)
    }

    // MARK: - Derived reads

    /// One atlas's slice of the save. Reading an unvisited atlas is an empty
    /// slice, never an invention — nothing is written until a stage is played
    /// there. This is the world atlas's read path (the properties above stay
    /// japan's); `Atlas.saveKey` supplies the key.
    func atlas(_ key: String) -> AtlasSave {
        atlases[key] ?? AtlasSave()
    }

    // The japan-facing reads every existing screen calls. Delegated to the
    // japan slice so the clamping rules live once, in `AtlasSave`.

    func masteryLevel(of code: Int) -> Int {
        atlas(Self.japanAtlas).masteryLevel(of: code)
    }

    func stars(of cardID: String) -> Int {
        atlas(Self.japanAtlas).stars(of: cardID)
    }

    func owns(_ cardID: String) -> Bool { stars(of: cardID) > 0 }

    func isRainbow(_ cardID: String) -> Bool {
        atlas(Self.japanAtlas).isRainbow(cardID)
    }

    func tier(of cardID: String) -> CardTier {
        atlas(Self.japanAtlas).tier(of: cardID)
    }

    func streak(of prefectureCode: Int) -> Int {
        atlas(Self.japanAtlas).streak(of: prefectureCode)
    }

    func record(forStage index: Int, mode: QuizMode) -> StageRecord? {
        atlas(Self.japanAtlas).record(forStage: index, mode: mode)
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

    /// Cards currently sitting on one exact rung of the visible card ladder.
    ///
    /// Exact matters for a breakdown: a rainbow card grew out of a gold card,
    /// but showing it in both columns would make the three displayed counts
    /// add up to more cards than the child actually owns.
    func cardCount(ofTier tier: CardTier) -> Int {
        cards.keys.filter { self.tier(of: $0) == tier }.count
    }

    /// Silver and up — see `CardTier.isSpecial`.
    var specialCardCount: Int { cards.keys.filter { tier(of: $0).isSpecial }.count }

    /// Gold and rainbow: a card that went rainbow has not stopped being gold.
    var goldCardCount: Int { cards.keys.filter { tier(of: $0) >= .gold }.count }

    /// Prefectures at level 3 — the ones drawn with a gold border on the my-map.
    var sparklingPrefectureCount: Int {
        mastery.values.filter { $0 >= GameRules.maxMastery }.count
    }
}
