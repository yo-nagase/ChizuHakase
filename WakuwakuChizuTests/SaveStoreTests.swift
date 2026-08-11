import Foundation
import Testing

@testable import WakuwakuChizu

/// CLAUDE.md §6. The overriding requirement is that nothing here can crash the
/// app or silently destroy a child's progress.
@MainActor
struct SaveStoreTests {

    /// Fresh scratch directory per test so runs cannot interfere.
    private func makeScratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("wakuwaku-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func startsEmptyWhenNoFileExists() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        #expect(store.data.mastery.isEmpty)
        #expect(store.data.cards.isEmpty)
        #expect(store.data.records.isEmpty)
        #expect(store.data.version == SaveData.currentVersion)
        #expect(store.data.settings.soundEnabled)
        #expect(store.data.settings.speechEnabled)
        #expect(!store.data.settings.voiceInputEnabled)
    }

    @Test func roundTripsThroughDisk() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 730, stars: 3,
            firstTryByPrefecture: [1: true, 2: true, 3: false],
            cardDraws: []), catalog: .empty)

        let reloaded = SaveStore(directory: dir)
        #expect(reloaded.data.masteryLevel(of: 1) == 1)
        #expect(reloaded.data.masteryLevel(of: 3) == 0, "a missed prefecture gains nothing")
        #expect(reloaded.data.record(forStage: 0, mode: .findOnMap) == StageRecord(stars: 3, score: 730))
    }

    @Test func replayNeverLowersABestRecord() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 1, score: 800, stars: 3,
                                           firstTryByPrefecture: [:], cardDraws: []), catalog: .empty)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 1, score: 100, stars: 1,
                                           firstTryByPrefecture: [:], cardDraws: []), catalog: .empty)

        #expect(store.data.record(forStage: 1, mode: .findOnMap) == StageRecord(stars: 3, score: 800))
    }

    @Test func masteryAccumulatesAcrossPlaysAndCapsAtTheTop() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        for _ in 0..<(GameRules.maxMastery + 2) {
            store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 100, stars: 3,
                                               firstTryByPrefecture: [1: true],
                                               cardDraws: []), catalog: .empty)
        }
        #expect(store.data.masteryLevel(of: 1) == GameRules.maxMastery)
    }

    @Test func reachingTheTopIsReportedOnceOnly() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        var announcements: [[Int]] = []
        for _ in 0..<(GameRules.maxMastery + 1) {
            announcements.append(store.applyStageResult(
                StageResult(mode: .findOnMap, stageIndex: 0, score: 100, stars: 3,
                            firstTryByPrefecture: [5: true], cardDraws: []),
                catalog: .empty).sparklingPrefectures)
        }
        // Climbs quietly, announced once on reaching the top, then nothing.
        #expect(announcements == [[], [], [], [], [5], []])
    }

    @Test func wrongAnswersDoNotReduceStoredMastery() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 100, stars: 3,
                                           firstTryByPrefecture: [7: true], cardDraws: []), catalog: .empty)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 50, stars: 1,
                                           firstTryByPrefecture: [7: false], cardDraws: []), catalog: .empty)
        #expect(store.data.masteryLevel(of: 7) == 1)
    }

    @Test func cardDrawsPersistWithTheShinyCap() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let card = SpecialtyCard(id: "01-1", prefectureCode: 1, emoji: "🦀",
                                 nameKana: "かに", nameKanji: "蟹",
                                 category: .food, description: "うみ")
        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.new(card)]), catalog: .empty)
        #expect(store.data.stars(of: "01-1") == 1)
        #expect(store.data.owns("01-1"))
        #expect(store.data.tier(of: "01-1") == .plain)

        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.star(card, stars: GameRules.silverStars)]),
                               catalog: .empty)
        #expect(store.data.tier(of: "01-1") == .silver)

        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.star(card, stars: GameRules.maxCardStars),
                                                       .duplicate(card)]),
                               catalog: .empty)
        #expect(store.data.stars(of: "01-1") == GameRules.maxCardStars)
        #expect(store.data.tier(of: "01-1") == .gold)
    }

    @Test func settingsPersist() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        SaveStore(directory: dir).updateSettings { $0.soundEnabled = false }
        #expect(SaveStore(directory: dir).data.settings.soundEnabled == false)
    }

    /// A truncated or hand-edited file must not take the app down on launch.
    @Test func corruptFileFallsBackToAFreshSave() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data("{\"version\": 1, \"mastery\": ".utf8)
            .write(to: dir.appendingPathComponent("savedata.json"))

        let store = SaveStore(directory: dir)
        #expect(store.data.mastery.isEmpty)
        #expect(store.save(), "the store should recover and be able to write again")
    }

    /// Older builds wrote fewer keys; the missing ones must take defaults
    /// rather than fail the whole decode.
    @Test func partialFileKeepsWhatItCanAndDefaultsTheRest() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(#"{"version":1,"cards":{"01-1":2}}"#.utf8)
            .write(to: dir.appendingPathComponent("savedata.json"))

        let store = SaveStore(directory: dir)
        // A version 1 two — the old キラ — arrives as gold.
        #expect(store.data.stars(of: "01-1") == GameRules.maxCardStars)
        #expect(store.data.mastery.isEmpty)
        #expect(store.data.settings.speechEnabled, "missing settings take their defaults")
    }

    @Test func eraseAllClearsEverythingAndSurvivesReload() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 500, stars: 3,
                                           firstTryByPrefecture: [1: true, 2: true],
                                           cardDraws: []), catalog: .empty)
        store.eraseAll()

        #expect(store.data.mastery.isEmpty)
        #expect(store.data.records.isEmpty)
        #expect(SaveStore(directory: dir).data.mastery.isEmpty)
    }

    @Test func derivedCountsReflectStoredState() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
            firstTryByPrefecture: [:],
            cardDraws: [
                .new(card("01-1")), .new(card("01-2")),
                .star(card("02-1"), stars: GameRules.silverStars),
            ]), catalog: .empty)

        #expect(store.data.totalOwnedCards == 3)
        #expect(store.data.specialCardCount == 1)
        #expect(store.data.goldCardCount == 0)
        #expect(store.data.sparklingPrefectureCount == 0)
    }

    // MARK: - Streaks and rainbow

    private func result(outcomes: [Int: [Bool]],
                        draws: [GameRules.CardDraw] = []) -> StageResult {
        StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                    firstTryByPrefecture: [:], cardDraws: draws,
                    outcomesByPrefecture: outcomes)
    }

    @Test func cleanAnswersGrowThePrefectureStreakAcrossPlays() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(result(outcomes: [1: [true, true]]), catalog: .empty)
        #expect(store.data.streak(of: 1) == 2)

        store.applyStageResult(result(outcomes: [1: [true]]), catalog: .empty)
        #expect(store.data.streak(of: 1) == 3)
        #expect(SaveStore(directory: dir).data.streak(of: 1) == 3,
                "the streak must survive a reload")
    }

    /// The reset is silent bookkeeping: the counter goes back, nothing else
    /// moves, and nothing is said about it (CLAUDE.md §12).
    @Test func aFumbleResetsTheStreakAndOnlyTheStreak() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(result(outcomes: [1: [true, true]],
                                      draws: [.new(card("01-1"))]), catalog: .empty)
        store.applyStageResult(result(outcomes: [1: [false, true]]), catalog: .empty)

        #expect(store.data.streak(of: 1) == 1)
        #expect(store.data.stars(of: "01-1") == 1, "stars stand through a broken streak")
    }

    @Test func goldHeldThroughAFifteenStreakTurnsRainbow() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = CardCatalog(cards: [card("01-1"), card("01-2"), card("01-3")])

        let store = SaveStore(directory: dir)
        // Gold, but the streak is only fourteen: not yet.
        store.applyStageResult(
            result(outcomes: [1: Array(repeating: true, count: 14)],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars)]),
            catalog: catalog)
        #expect(store.data.tier(of: "01-1") == .gold)
        #expect(store.data.rainbow.isEmpty)

        // The fifteenth clean answer latches it.
        store.applyStageResult(result(outcomes: [1: [true]]), catalog: catalog)
        #expect(store.data.tier(of: "01-1") == .rainbow)
        #expect(store.data.tier(of: "01-2") == .none,
                "a card that is not gold has nothing to latch")
    }

    /// The other order: the streak is already there when the card reaches gold.
    @Test func aCardReachingGoldUnderALiveStreakLatchesImmediately() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = CardCatalog(cards: [card("01-1")])

        let store = SaveStore(directory: dir)
        store.applyStageResult(
            result(outcomes: [1: Array(repeating: true, count: 16)]), catalog: catalog)
        store.applyStageResult(
            result(outcomes: [1: [true]],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars)]),
            catalog: catalog)
        #expect(store.data.tier(of: "01-1") == .rainbow)
    }

    /// The latch has to say what it caught, or the rarest thing in the game
    /// happens in silence: the streak crossing fifteen promotes every gold card
    /// the prefecture holds, including ones this stage never drew, so the
    /// result screen cannot work it out from the draws.
    @Test func theLatchReportsEveryCardItCaughtIncludingUndrawnOnes() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = CardCatalog(cards: [card("01-1"), card("01-2"), card("01-3")])

        let store = SaveStore(directory: dir)
        // Two of the three at gold, then a fifteenth clean answer in a stage
        // that draws nothing at all.
        store.applyStageResult(
            result(outcomes: [1: Array(repeating: true, count: 14)],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars),
                           .star(card("01-2"), stars: GameRules.maxCardStars)]),
            catalog: catalog)

        let gains = store.applyStageResult(result(outcomes: [1: [true]]), catalog: catalog)
        #expect(gains.rainbowCards == ["01-1", "01-2"],
                "the latch caught cards the stage never drew and did not name them")
        #expect(store.data.tier(of: "01-3") == .none)
    }

    /// Said once. A card that was already rainbow is not news, and repeating it
    /// every stage would turn the peak of the game into wallpaper.
    @Test func aRainbowIsAnnouncedOnlyOnTheStageThatEarnsIt() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = CardCatalog(cards: [card("01-1")])

        let store = SaveStore(directory: dir)
        let earning = store.applyStageResult(
            result(outcomes: [1: Array(repeating: true, count: GameRules.rainbowStreak)],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars)]),
            catalog: catalog)
        #expect(earning.rainbowCards == ["01-1"])

        let after = store.applyStageResult(result(outcomes: [1: [true]]), catalog: catalog)
        #expect(after.rainbowCards.isEmpty, "the same rainbow was announced twice")
        #expect(store.data.tier(of: "01-1") == .rainbow)
    }

    /// Once rainbow, always rainbow. The streak breaking afterwards takes the
    /// counter back to zero and nothing else (CLAUDE.md §12).
    @Test func rainbowSurvivesTheStreakBreaking() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = CardCatalog(cards: [card("01-1")])

        let store = SaveStore(directory: dir)
        store.applyStageResult(
            result(outcomes: [1: Array(repeating: true, count: 15)],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars)]),
            catalog: catalog)
        #expect(store.data.tier(of: "01-1") == .rainbow)

        store.applyStageResult(result(outcomes: [1: [false]]), catalog: catalog)
        #expect(store.data.streak(of: 1) == 0)
        #expect(store.data.tier(of: "01-1") == .rainbow)
    }

    private func card(_ id: String) -> SpecialtyCard {
        SpecialtyCard(id: id, prefectureCode: Int(id.prefix(2)) ?? 1, emoji: "🍎",
                      nameKana: "てすと", nameKanji: "試験",
                      category: .food, description: "てすと")
    }
}

/// Version 1 → 2 split the stage records per quiz mode; 2 → 3 gave cards five
/// stars instead of a plain/キラ pair.
///
/// A migration is the one piece of code that can quietly destroy everything a
/// child has done, and it only ever runs on files this build did not write —
/// so it cannot be checked by playing the game.
@MainActor
struct SaveMigrationTests {

    private func load(_ json: String) throws -> SaveData {
        try JSONDecoder().decode(SaveData.self, from: Data(json.utf8))
    }

    /// Everything version 1 recorded was played by tapping the map.
    @Test func versionOneRecordsBecomeMapModeRecords() throws {
        let data = try load("""
        {"version":1,"mastery":{"1":3},"cards":{"01-1":2},
         "stages":{"0":{"stars":3,"score":730},"1":{"stars":2,"score":400}},
         "settings":{"soundEnabled":false}}
        """)

        #expect(data.record(forStage: 0, mode: .findOnMap) == StageRecord(stars: 3, score: 730))
        #expect(data.record(forStage: 1, mode: .findOnMap) == StageRecord(stars: 2, score: 400))
        #expect(data.record(forStage: 0, mode: .nameIt) == nil,
                "a mode that did not exist cannot have records")
        // The rest of the file has to survive the move. Mastery 3 was キラキラ
        // on the old ladder, so it arrives at the top of this one.
        #expect(data.masteryLevel(of: 1) == GameRules.maxMastery)
        // Two was the top of version 1's scale, so the card arrives at the top
        // of this one rather than as a two-star plain card.
        #expect(data.tier(of: "01-1") == .gold)
        #expect(data.settings.soundEnabled == false)
    }

    /// Two used to be the top of the scale. Anything that had reached it was a
    /// キラ, and キラ is now five stars — the child keeps what they earned rather
    /// than finding it demoted to a plain two-star card (CLAUDE.md §12).
    @Test func keepersOfAKiraCardKeepIt() throws {
        let data = try load("""
        {"version":2,"cards":{"01-1":2,"01-2":1,"01-3":0}}
        """)
        #expect(data.tier(of: "01-1") == .gold)
        #expect(data.stars(of: "01-1") == GameRules.maxCardStars)
        #expect(data.stars(of: "01-2") == 1)
        #expect(data.tier(of: "01-2") == .plain)
        #expect(!data.owns("01-3"))
    }

    /// 3 → 4 stretched the scale: silver moved from three stars to five, gold
    /// from five to fifteen. Counts move by their place on the old ladder so no
    /// card demotes — an old three lands on the new silver floor, a four lands
    /// mid-silver, an old gold stays gold.
    @Test func versionThreeStarsAreLiftedToTheNewScale() throws {
        let data = try load("""
        {"version":3,"cards":{"a":1,"b":2,"c":3,"d":4,"e":5}}
        """)
        #expect(data.stars(of: "a") == 1)
        #expect(data.stars(of: "b") == 2)
        #expect(data.stars(of: "c") == GameRules.silverStars)
        #expect(data.stars(of: "d") == 10)
        #expect(data.stars(of: "e") == GameRules.maxCardStars)
        #expect(data.tier(of: "c") == .silver)
        #expect(data.tier(of: "d") == .silver)
        #expect(data.tier(of: "e") == .gold)
    }

    /// The lift must not run twice: a version 4 file already speaks the new
    /// scale, and a five there is a five.
    @Test func aVersionFourFileKeepsItsStarCounts() throws {
        let data = try load("""
        {"version":4,"cards":{"a":2,"b":5,"c":14,"d":15}}
        """)
        #expect(data.stars(of: "a") == 2)
        #expect(data.tier(of: "a") == .plain)
        #expect(data.tier(of: "b") == .silver)
        #expect(data.tier(of: "c") == .silver)
        #expect(data.tier(of: "d") == .gold)
    }

    /// 4 → 5 stretched mastery: キラキラ moved from three clean answers to
    /// five. Levels move so that neither the colour on the map nor the distance
    /// to the next state gets worse: old 1 → 2 (light green, one step from
    /// deep), old 2 → 4 (deep green, one step from gold), キラキラ stays キラキラ.
    @Test func versionFourMasteryIsLiftedToTheNewLadder() throws {
        let data = try load("""
        {"version":4,"mastery":{"1":1,"2":2,"3":3,"4":0}}
        """)
        #expect(data.masteryLevel(of: 1) == 2)
        #expect(data.masteryLevel(of: 2) == 4)
        #expect(data.masteryLevel(of: 3) == GameRules.maxMastery)
        #expect(data.masteryLevel(of: 4) == 0)
    }

    /// The lift must not run twice: a version 5 file already speaks the new
    /// ladder, and a two there is a two.
    @Test func aVersionFiveFileKeepsItsMasteryLevels() throws {
        let data = try load("""
        {"version":5,"mastery":{"1":2,"2":4,"3":5}}
        """)
        #expect(data.masteryLevel(of: 1) == 2)
        #expect(data.masteryLevel(of: 2) == 4)
        #expect(data.masteryLevel(of: 3) == 5)
    }

    /// Migration lifts stars, never grants rainbow: rainbow is the streak's
    /// medal, and no streak has been walked yet on a file this old.
    @Test func migrationGrantsNoRainbowAndNoStreak() throws {
        let data = try load(#"{"version":3,"cards":{"a":5}}"#)
        #expect(data.rainbow.isEmpty)
        #expect(data.streaks.isEmpty)
        #expect(data.tier(of: "a") == .gold)
    }

    @Test func rainbowAndStreaksSurviveARoundTrip() throws {
        var data = SaveData()
        data.cards["01-1"] = GameRules.maxCardStars
        data.rainbow = ["01-1"]
        data.streaks = [1: 7]
        let reloaded = try JSONDecoder().decode(
            SaveData.self, from: JSONEncoder().encode(data))
        #expect(reloaded.rainbow == ["01-1"])
        #expect(reloaded.streaks[1] == 7)
        #expect(reloaded.tier(of: "01-1") == .rainbow)
    }

    /// Encoding a migrated file writes the new version, so reloading it cannot
    /// put the cards through the remap a second time.
    @Test func migratedCardsSurviveARoundTrip() throws {
        let migrated = try load(#"{"version":1,"cards":{"01-1":2}}"#)
        let reloaded = try JSONDecoder().decode(
            SaveData.self, from: JSONEncoder().encode(migrated))
        #expect(reloaded.stars(of: "01-1") == GameRules.maxCardStars)
    }

    @Test func aVersionTwoFileIsReadAsIs() throws {
        let data = try load("""
        {"version":2,"records":{"findOnMap":{"0":{"stars":1,"score":100}},
         "nameIt":{"0":{"stars":3,"score":900}}}}
        """)
        #expect(data.record(forStage: 0, mode: .findOnMap) == StageRecord(stars: 1, score: 100))
        #expect(data.record(forStage: 0, mode: .nameIt) == StageRecord(stars: 3, score: 900))
    }

    /// Re-reading a file that has both shapes must not let the old flat record
    /// overwrite a newer one — that would walk a best score backwards.
    @Test func legacyRecordsNeverBeatMigratedOnes() throws {
        let data = try load("""
        {"version":2,"stages":{"0":{"stars":1,"score":100}},
         "records":{"findOnMap":{"0":{"stars":3,"score":900}}}}
        """)
        #expect(data.record(forStage: 0, mode: .findOnMap) == StageRecord(stars: 3, score: 900))
    }

    @Test func migratedDataSurvivesARoundTrip() throws {
        let migrated = try load("""
        {"version":1,"stages":{"2":{"stars":2,"score":500}}}
        """)
        let reloaded = try JSONDecoder().decode(
            SaveData.self, from: JSONEncoder().encode(migrated))
        #expect(reloaded.record(forStage: 2, mode: .findOnMap) == StageRecord(stars: 2, score: 500))
        #expect(reloaded.version == SaveData.currentVersion)
    }

    /// The written file must not carry the old key forward, or every future
    /// read has two sources of truth to reconcile.
    @Test func theOldKeyIsNotWrittenBack() throws {
        var data = SaveData()
        data.records["findOnMap"] = [0: StageRecord(stars: 3, score: 1)]
        let json = try #require(String(data: try JSONEncoder().encode(data), encoding: .utf8))
        #expect(!json.contains("\"stages\""))
        #expect(json.contains("records"))
    }

    /// The best across modes, for the places that count a stage as cleared
    /// however it was played.
    @Test func theBestRecordLooksAcrossModes() throws {
        let data = try load("""
        {"version":2,"records":{"findOnMap":{"0":{"stars":1,"score":100}},
         "nameIt":{"0":{"stars":3,"score":900}}}}
        """)
        #expect(data.bestRecord(forStage: 0) == StageRecord(stars: 3, score: 900))
        #expect(data.bestRecord(forStage: 5) == nil)
    }

    @Test func anEmptyFileStillLoads() throws {
        let data = try load("{}")
        #expect(data.records.isEmpty)
        #expect(data.version == SaveData.currentVersion)
    }
}
