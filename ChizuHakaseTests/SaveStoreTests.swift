import Foundation
import Testing

@testable import ChizuHakase

/// CLAUDE.md §6. The overriding requirement is that nothing here can crash the
/// app or silently destroy a child's progress.
@MainActor
struct SaveStoreTests {

    /// Fresh scratch directory per test so runs cannot interfere.
    private func makeScratch() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("chizuhakase-tests-\(UUID().uuidString)")
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
        #expect(store.data.settings.musicEnabled)
        #expect(!store.data.settings.voiceInputEnabled)
    }

    @Test func roundTripsThroughDisk() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 730, stars: 3,
            firstTryByPrefecture: [1: true, 2: true, 3: false],
            cardDraws: []), catalog: .empty, atlas: SaveData.japanAtlas)

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
                                           firstTryByPrefecture: [:], cardDraws: []), catalog: .empty, atlas: SaveData.japanAtlas)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 1, score: 100, stars: 1,
                                           firstTryByPrefecture: [:], cardDraws: []), catalog: .empty, atlas: SaveData.japanAtlas)

        #expect(store.data.record(forStage: 1, mode: .findOnMap) == StageRecord(stars: 3, score: 800))
    }

    @Test func masteryAccumulatesAcrossPlaysAndCapsAtTheTop() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        for _ in 0..<(GameRules.maxMastery + 2) {
            store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 100, stars: 3,
                                               firstTryByPrefecture: [1: true],
                                               cardDraws: []), catalog: .empty, atlas: SaveData.japanAtlas)
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
                catalog: .empty, atlas: SaveData.japanAtlas).sparklingPrefectures)
        }
        // Climbs quietly, announced once on reaching the top, then nothing.
        #expect(announcements == [[], [], [], [], [5], []])
    }

    @Test func wrongAnswersDoNotReduceStoredMastery() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 100, stars: 3,
                                           firstTryByPrefecture: [7: true], cardDraws: []), catalog: .empty, atlas: SaveData.japanAtlas)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 50, stars: 1,
                                           firstTryByPrefecture: [7: false], cardDraws: []), catalog: .empty, atlas: SaveData.japanAtlas)
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
                                           cardDraws: [.new(card)]), catalog: .empty, atlas: SaveData.japanAtlas)
        #expect(store.data.stars(of: "01-1") == 1)
        #expect(store.data.owns("01-1"))
        #expect(store.data.tier(of: "01-1") == .plain)

        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.star(card, stars: GameRules.silverStars)]),
                               catalog: .empty, atlas: SaveData.japanAtlas)
        #expect(store.data.tier(of: "01-1") == .silver)

        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.star(card, stars: GameRules.maxCardStars),
                                                       .duplicate(card)]),
                               catalog: .empty, atlas: SaveData.japanAtlas)
        #expect(store.data.stars(of: "01-1") == GameRules.maxCardStars)
        #expect(store.data.tier(of: "01-1") == .gold)
    }

    @Test func settingsPersist() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        SaveStore(directory: dir).updateSettings { $0.soundEnabled = false }
        #expect(SaveStore(directory: dir).data.settings.soundEnabled == false)
    }

    /// The title-screen mute writes through this flag; off has to survive a
    /// relaunch, or the song comes back on the next cold start and the mute
    /// button taught the child that buttons lie.
    @Test func musicStaysOffOnceMuted() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        SaveStore(directory: dir).updateSettings { $0.musicEnabled = false }
        #expect(SaveStore(directory: dir).data.settings.musicEnabled == false)
    }

    /// A fresh save opens the japan page: the world is something the child
    /// turns to, never something they wake up lost in.
    @Test func lastAtlasDefaultsToJapan() {
        #expect(Settings().lastAtlas == SaveData.japanAtlas)
    }

    /// The title writes this on every page turn; the next launch reads it back
    /// (design doc §2: 前回開いていたページを記憶).
    @Test func lastAtlasSurvivesARelaunch() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        SaveStore(directory: dir).updateSettings { $0.lastAtlas = SaveData.worldAtlas }
        #expect(SaveStore(directory: dir).data.settings.lastAtlas == SaveData.worldAtlas)
    }

    /// A page this build does not know (a future book, a hand-edited file)
    /// folds to japan — the selection must always name a page that exists.
    @Test func unknownLastAtlasFallsBackToJapan() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(#"{"version":7,"settings":{"lastAtlas":"mars"}}"#.utf8)
            .write(to: dir.appendingPathComponent("savedata.json"))
        #expect(SaveStore(directory: dir).data.settings.lastAtlas == SaveData.japanAtlas)
    }

    /// Saves from before the world existed have no opinion; they open on japan.
    @Test func missingLastAtlasDefaultsToJapan() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(#"{"version":7,"settings":{"soundEnabled":false}}"#.utf8)
            .write(to: dir.appendingPathComponent("savedata.json"))
        #expect(SaveStore(directory: dir).data.settings.lastAtlas == SaveData.japanAtlas)
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
                                           cardDraws: []), catalog: .empty, atlas: SaveData.japanAtlas)
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
            ]), catalog: .empty, atlas: SaveData.japanAtlas)

        #expect(store.data.totalOwnedCards == 3)
        #expect(store.data.specialCardCount == 1)
        #expect(store.data.goldCardCount == 0)
        #expect(store.data.sparklingPrefectureCount == 0)
    }

    @Test func exactTierCountsDoNotCountRainbowAsGoldTwice() {
        var data = SaveData()
        data.cards = [
            "plain": 1,
            "silver": GameRules.silverStars,
            "gold": GameRules.maxCardStars,
            "rainbow": GameRules.maxCardStars,
        ]
        data.rainbow = ["rainbow"]

        #expect(data.cardCount(ofTier: .silver) == 1)
        #expect(data.cardCount(ofTier: .gold) == 1)
        #expect(data.cardCount(ofTier: .rainbow) == 1)
        #expect(data.specialCardCount == 3)
        #expect(data.goldCardCount == 2)
    }

    /// The tallies the title's two pages draw come off each page's own slice —
    /// a world card must never inflate japan's numbers, nor the reverse.
    @Test func perAtlasTalliesReadOnlyTheirOwnBook() {
        var data = SaveData()
        var world = AtlasSave()
        world.cards = ["840-1": 1, "392-1": GameRules.silverStars]
        world.mastery = [840: GameRules.maxMastery, 392: 1]
        data.atlases[SaveData.worldAtlas] = world
        data.cards = ["01-1": GameRules.maxCardStars]
        data.mastery = [13: GameRules.maxMastery]

        let worldSlice = data.atlas(SaveData.worldAtlas)
        #expect(worldSlice.totalOwnedCards == 2)
        #expect(worldSlice.cardCount(ofTier: .silver) == 1)
        #expect(worldSlice.cardCount(ofTier: .gold) == 0)
        #expect(worldSlice.sparklingRegionCount == 1)

        // The japan-facing reads delegate to japan's slice and see none of it.
        #expect(data.totalOwnedCards == 1)
        #expect(data.cardCount(ofTier: .gold) == 1)
        #expect(data.sparklingPrefectureCount == 1)
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
        store.applyStageResult(result(outcomes: [1: [true, true]]), catalog: .empty, atlas: SaveData.japanAtlas)
        #expect(store.data.streak(of: 1) == 2)

        store.applyStageResult(result(outcomes: [1: [true]]), catalog: .empty, atlas: SaveData.japanAtlas)
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
                                      draws: [.new(card("01-1"))]), catalog: .empty, atlas: SaveData.japanAtlas)
        store.applyStageResult(result(outcomes: [1: [false, true]]), catalog: .empty, atlas: SaveData.japanAtlas)

        #expect(store.data.streak(of: 1) == 1)
        #expect(store.data.stars(of: "01-1") == 1, "stars stand through a broken streak")
    }

    @Test func aCleanRunOfSevenAfterGoldTurnsRainbow() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = CardCatalog(cards: [card("01-1"), card("01-2"), card("01-3")])

        let store = SaveStore(directory: dir)
        // The answer that finishes the gold opens the count at zero…
        store.applyStageResult(
            result(outcomes: [1: [true]],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars)]),
            catalog: catalog, atlas: SaveData.japanAtlas)
        #expect(store.data.tier(of: "01-1") == .gold)
        #expect(store.data.streak(of: 1) == 0,
                "the promoting answer must not start the run")

        // …six clean answers are not yet seven…
        store.applyStageResult(
            result(outcomes: [1: Array(repeating: true,
                                       count: GameRules.rainbowStreak - 1)]),
            catalog: catalog, atlas: SaveData.japanAtlas)
        #expect(store.data.rainbow.isEmpty)

        // …the seventh latches it.
        store.applyStageResult(result(outcomes: [1: [true]]), catalog: catalog, atlas: SaveData.japanAtlas)
        #expect(store.data.tier(of: "01-1") == .rainbow)
        #expect(store.data.tier(of: "01-2") == .none,
                "a card that is not gold has nothing to latch")
    }

    /// The other order no longer counts: a streak built before the card
    /// reached gold is spent by the promotion, and the run toward rainbow
    /// starts from the gold.
    @Test func aStreakBuiltBeforeGoldDoesNotCount() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = CardCatalog(cards: [card("01-1")])

        let store = SaveStore(directory: dir)
        store.applyStageResult(
            result(outcomes: [1: Array(repeating: true, count: 16)]), catalog: catalog, atlas: SaveData.japanAtlas)
        store.applyStageResult(
            result(outcomes: [1: [true]],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars)]),
            catalog: catalog, atlas: SaveData.japanAtlas)
        #expect(store.data.tier(of: "01-1") == .gold)
        #expect(store.data.rainbow.isEmpty)
        #expect(store.data.streak(of: 1) == 0, "the promotion spends the run")
    }

    /// The latch has to say what it caught, or the rarest thing in the game
    /// happens in silence: the streak crossing its line promotes every card
    /// whose gold predates the run, including ones this stage never drew, so
    /// the result screen cannot work it out from the draws.
    @Test func theLatchReportsEveryCardItCaughtIncludingUndrawnOnes() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = CardCatalog(cards: [card("01-1"), card("01-2"), card("01-3")])

        let store = SaveStore(directory: dir)
        // Two of the three finish gold — each promotion spends the count —
        // then a clean run of seven, ending in a stage that draws nothing
        // at all.
        store.applyStageResult(
            result(outcomes: [1: [true, true]],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars),
                           .star(card("01-2"), stars: GameRules.maxCardStars)]),
            catalog: catalog, atlas: SaveData.japanAtlas)
        store.applyStageResult(
            result(outcomes: [1: Array(repeating: true,
                                       count: GameRules.rainbowStreak - 1)]),
            catalog: catalog, atlas: SaveData.japanAtlas)

        let gains = store.applyStageResult(result(outcomes: [1: [true]]), catalog: catalog, atlas: SaveData.japanAtlas)
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
        // The promoting answer plus the seven that must follow it.
        let earning = store.applyStageResult(
            result(outcomes: [1: Array(repeating: true,
                                       count: GameRules.rainbowStreak + 1)],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars)]),
            catalog: catalog, atlas: SaveData.japanAtlas)
        #expect(earning.rainbowCards == ["01-1"])

        let after = store.applyStageResult(result(outcomes: [1: [true]]), catalog: catalog, atlas: SaveData.japanAtlas)
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
            result(outcomes: [1: Array(repeating: true,
                                       count: GameRules.rainbowStreak + 1)],
                   draws: [.star(card("01-1"), stars: GameRules.maxCardStars)]),
            catalog: catalog, atlas: SaveData.japanAtlas)
        #expect(store.data.tier(of: "01-1") == .rainbow)

        store.applyStageResult(result(outcomes: [1: [false]]), catalog: catalog, atlas: SaveData.japanAtlas)
        #expect(store.data.streak(of: 1) == 0)
        #expect(store.data.tier(of: "01-1") == .rainbow)
    }

    // MARK: - Atlas namespaces (world write path)

    /// The same integers mean different places in different books (44 is
    /// 大分県 and バハマ; stage 3 is きんき and きたヨーロッパ), so a world
    /// result must land in `atlases["world"]` and nowhere else.
    @Test func aWorldStageResultLandsOnlyInTheWorldAtlas() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let flag = SpecialtyCard(id: "392-1", prefectureCode: 392, emoji: "🇯🇵",
                                 nameKana: "こっき", nameKanji: "国旗",
                                 category: .flag, description: "にほんの こっきだよ")

        let store = SaveStore(directory: dir)
        store.applyStageResult(
            StageResult(mode: .findOnMap, stageIndex: 15, score: 640, stars: 3,
                        firstTryByPrefecture: [392: true, 156: true],
                        cardDraws: [.new(flag)],
                        outcomesByPrefecture: [392: [true, true]]),
            catalog: CardCatalog(cards: [flag]),
            atlas: SaveData.worldAtlas)

        let world = store.data.atlas(SaveData.worldAtlas)
        #expect(world.mastery == [392: 1, 156: 1])
        #expect(world.cards == ["392-1": 1])
        #expect(world.streaks == [392: 2])
        #expect(world.record(forStage: 15, mode: .findOnMap) == StageRecord(stars: 3, score: 640))
        // Japan stays exactly untouched — absent, not merely empty.
        #expect(store.data.atlases[SaveData.japanAtlas] == nil)
        #expect(store.data.mastery.isEmpty)
        #expect(store.data.records.isEmpty)
        // And the write survives a reload in its namespace.
        #expect(SaveStore(directory: dir).data.atlas(SaveData.worldAtlas).mastery[392] == 1)
    }

    /// The other direction: the default (japan) call sites must not leak into
    /// the world, and colliding codes stay independent per book.
    @Test func japanAndWorldWritesDoNotCross() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        // 44 is 大分県 in one book and バハマ in the other.
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 5, score: 100, stars: 1,
                                           firstTryByPrefecture: [44: true],
                                           cardDraws: []), catalog: .empty, atlas: SaveData.japanAtlas)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 5, score: 900, stars: 3,
                                           firstTryByPrefecture: [44: true],
                                           cardDraws: []), catalog: .empty,
                               atlas: SaveData.worldAtlas)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 5, score: 900, stars: 3,
                                           firstTryByPrefecture: [44: true],
                                           cardDraws: []), catalog: .empty,
                               atlas: SaveData.worldAtlas)

        #expect(store.data.masteryLevel(of: 44) == 1, "japan's 大分県 gained a world answer")
        #expect(store.data.atlas(SaveData.worldAtlas).masteryLevel(of: 44) == 2)
        #expect(store.data.record(forStage: 5, mode: .findOnMap) == StageRecord(stars: 1, score: 100),
                "japan's best record took the world's score")
        #expect(store.data.atlas(SaveData.worldAtlas)
            .record(forStage: 5, mode: .findOnMap) == StageRecord(stars: 3, score: 900))
    }

    /// Owned cards read per atlas: the quiz seeds its draw from the book it
    /// is playing, and "1-1"-shaped world ids must not shadow japan's "01-1".
    @Test func ownedCardsAreReadPerAtlas() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let flag = SpecialtyCard(id: "44-1", prefectureCode: 44, emoji: "🇧🇸",
                                 nameKana: "こっき", nameKanji: "国旗",
                                 category: .flag, description: "ばはまの こっきだよ")

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.new(card("44-1"))]), catalog: .empty, atlas: SaveData.japanAtlas)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 1, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.star(flag, stars: GameRules.silverStars)]),
                               catalog: .empty, atlas: SaveData.worldAtlas)

        #expect(store.data.atlas(SaveData.japanAtlas).cards == ["44-1": 1])
        #expect(store.data.atlas(SaveData.worldAtlas).cards == ["44-1": GameRules.silverStars])
        #expect(store.data.atlas(SaveData.worldAtlas).stars(of: "44-1") == GameRules.silverStars)
        #expect(store.data.stars(of: "44-1") == 1, "the japan-facing read moved")
    }

    private func card(_ id: String) -> SpecialtyCard {
        SpecialtyCard(id: id, prefectureCode: Int(id.prefix(2)) ?? 1, emoji: "🍎",
                      nameKana: "てすと", nameKanji: "試験",
                      category: .food, description: "てすと")
    }

    // MARK: - チャレンジの出題履歴(設計 §8: 未出題優先の記憶)

    /// 抽選チャレンジの結果だけが運ぶ askedCodes(星・スコアは従来どおり)。
    private func challengeResult(mode: QuizMode = .findOnMap,
                                 asked: Set<Int>) -> StageResult {
        StageResult(mode: mode, stageIndex: 18, score: 100, stars: 1,
                    firstTryByPrefecture: [:], cardDraws: [], askedCodes: asked)
    }

    /// 一巡判定の分母になる「全収録国」— applyStageResult は目録から引くので、
    /// テストの世界も国コードごとに 1 枚の札を持つ目録として与える。
    private func universeCatalog(_ codes: some Sequence<Int>) -> CardCatalog {
        CardCatalog(cards: codes.map {
            SpecialtyCard(id: "\($0)-1", prefectureCode: $0, emoji: "🚩",
                          nameKana: "こっき", nameKanji: "国旗",
                          category: .flag, description: "てすと")
        })
    }

    /// 履歴はプレイをまたいで合流し、モードごとに別々の回転を持つ
    /// (records と同じ分け方 — 別の回だから)。
    @Test func チャレンジの出題履歴はモードごとに合流していく() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let catalog = universeCatalog(1...200)

        let store = SaveStore(directory: dir)
        store.applyStageResult(challengeResult(asked: [1, 2, 3]),
                               catalog: catalog, atlas: SaveData.worldAtlas)
        store.applyStageResult(challengeResult(asked: [3, 4]),
                               catalog: catalog, atlas: SaveData.worldAtlas)
        store.applyStageResult(challengeResult(mode: .nameIt, asked: [9]),
                               catalog: catalog, atlas: SaveData.worldAtlas)

        let world = store.data.atlas(SaveData.worldAtlas)
        #expect(world.askedInChallenge[QuizMode.findOnMap.rawValue] == [1, 2, 3, 4])
        #expect(world.askedInChallenge[QuizMode.nameIt.rawValue] == [9])
        #expect(SaveStore(directory: dir).data.atlas(SaveData.worldAtlas)
            .askedInChallenge[QuizMode.findOnMap.rawValue] == [1, 2, 3, 4],
                "the history must survive a reload")
    }

    /// 実寸の一巡: 47 問 × 4 プレイで 167 カ国を覆い、覆った瞬間に履歴が
    /// 空へ戻る(§8 の 2 周目)。星・スコアは従来の records[mode][18] に載る。
    @Test func 全収録国を覆ったら履歴は空に戻る() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }
        let universe = Array(1...167)
        let catalog = universeCatalog(universe)

        let store = SaveStore(directory: dir)
        // 未出題優先の抽選が現実に組む形: 3 回で 141、4 回目は残り 26 +
        // 出題済みからの補充 21。
        let sittings: [Set<Int>] = [
            Set(universe[0..<47]),
            Set(universe[47..<94]),
            Set(universe[94..<141]),
            Set(universe[141..<167]).union(universe[0..<21]),
        ]
        for (index, sitting) in sittings.enumerated() {
            store.applyStageResult(challengeResult(asked: sitting),
                                   catalog: catalog, atlas: SaveData.worldAtlas)
            let stored = store.data.atlas(SaveData.worldAtlas)
                .askedInChallenge[QuizMode.findOnMap.rawValue] ?? []
            if index < sittings.count - 1 {
                #expect(stored.count == 47 * (index + 1),
                        "play \(index + 1): history = \(stored.count)")
            } else {
                #expect(stored.isEmpty, "full coverage must reset the lap")
            }
        }
        #expect(store.data.atlas(SaveData.worldAtlas)
            .record(forStage: 18, mode: .findOnMap) == StageRecord(stars: 1, score: 100),
                "the challenge's record rides the ordinary records path")
    }

    /// 空の目録は分母を知らないので一巡判定はしない — 履歴は立ったまま。
    /// (目録が空へ倒れた本ではカード自体が配れず、回転が止まらないことは
    /// その障害のいちばん無害な症状に留める、というガードの凍結。)
    @Test func 目録が空なら一巡判定はしない() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(challengeResult(asked: Set(1...167)),
                               catalog: .empty, atlas: SaveData.worldAtlas)
        #expect(store.data.atlas(SaveData.worldAtlas)
            .askedInChallenge[QuizMode.findOnMap.rawValue] == Set(1...167))
    }

    /// 日本のチャレンジ結果は askedCodes が空(VM が抽選を使わないため)で、
    /// 履歴には何も書かない — 計画の不変条件「日本の askedInChallenge が
    /// 空のまま」の SaveStore 側の釘。記録は従来どおり載る。
    @Test func 日本のチャレンジ結果は出題履歴を書かない() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(
            StageResult(mode: .findOnMap, stageIndex: 6, score: 4700, stars: 3,
                        firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                            (1...47).map { ($0, true) }),
                        cardDraws: []),
            catalog: .empty, atlas: SaveData.japanAtlas)

        #expect(store.data.atlas(SaveData.japanAtlas).askedInChallenge.isEmpty)
        #expect(store.data.record(forStage: 6, mode: .findOnMap)
                == StageRecord(stars: 3, score: 4700))
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

    /// Version 3 counts land by their place on the current ladder, so no card
    /// demotes — an old three lands on the silver floor, a four (second of two
    /// silver steps) lands mid-silver, an old gold stays gold.
    @Test func versionThreeStarsAreLiftedToTheNewScale() throws {
        let data = try load("""
        {"version":3,"cards":{"a":1,"b":2,"c":3,"d":4,"e":5}}
        """)
        #expect(data.stars(of: "a") == 1)
        #expect(data.stars(of: "b") == 2)
        #expect(data.stars(of: "c") == GameRules.silverStars)
        #expect(data.stars(of: "d") == 7)
        #expect(data.stars(of: "e") == GameRules.maxCardStars)
        #expect(data.tier(of: "c") == .silver)
        #expect(data.tier(of: "d") == .silver)
        #expect(data.tier(of: "e") == .gold)
    }

    /// Version 4 spoke the fifteen-star scale; 6 folds everything past ten
    /// down onto the new top. A tier can only rise — the fourteen-star silver
    /// arrives as gold — and counts at or below ten do not move.
    @Test func aVersionFourFileFoldsOntoTheTenStarLadder() throws {
        let data = try load("""
        {"version":4,"cards":{"a":2,"b":5,"c":14,"d":15}}
        """)
        #expect(data.stars(of: "a") == 2)
        #expect(data.tier(of: "a") == .plain)
        #expect(data.tier(of: "b") == .silver)
        #expect(data.stars(of: "c") == GameRules.maxCardStars)
        #expect(data.tier(of: "c") == .gold, "a folded count may only promote")
        #expect(data.tier(of: "d") == .gold)
    }

    /// 5 → 6 folded the ladder from fifteen stars down to ten. The stored
    /// counts themselves are asserted, not the clamped read: decoding is the
    /// migration, and what sits in memory must already be the current shape.
    @Test func versionFiveStarsFoldOntoTheTenStarLadder() throws {
        let data = try load("""
        {"version":5,"cards":{"a":15,"b":12,"c":10,"d":7,"e":1}}
        """)
        #expect(data.cards["a"] == GameRules.maxCardStars)
        #expect(data.cards["b"] == GameRules.maxCardStars)
        #expect(data.tier(of: "b") == .gold, "a folded count may only promote")
        #expect(data.cards["c"] == GameRules.maxCardStars)
        #expect(data.cards["d"] == 7)
        #expect(data.tier(of: "d") == .silver)
        #expect(data.cards["e"] == 1)
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

    /// A save written before the theme song existed plays it: music defaults
    /// on, and only an explicit mute turns it off. The keys around it must
    /// keep their stored values rather than being dragged to defaults.
    @Test func savesWrittenBeforeTheMusicSettingPlayMusic() throws {
        let data = try load(#"{"version":5,"settings":{"soundEnabled":false}}"#)
        #expect(data.settings.musicEnabled)
        #expect(data.settings.soundEnabled == false)
    }

    // MARK: - Version 7: the atlas namespace

    /// 6 → 7 moves the five per-atlas fields under `atlases["japan"]`.
    /// Everything a version 6 file recorded was earned on the Japan map, so
    /// that is where all of it lands — values untouched, world not invented.
    @Test func aVersionSixFileLandsIntactInTheJapanAtlas() throws {
        let data = try load("""
        {"version":6,
         "mastery":{"1":5,"13":2},
         "cards":{"01-1":10,"13-2":3},
         "rainbow":["01-1"],
         "streaks":{"1":4},
         "records":{"findOnMap":{"0":{"stars":3,"score":730}},
                    "nameIt":{"3":{"stars":2,"score":400}}},
         "settings":{"soundEnabled":false}}
        """)
        #expect(data.version == SaveData.currentVersion)
        let japan = try #require(data.atlases[SaveData.japanAtlas])
        #expect(japan.mastery == [1: 5, 13: 2])
        #expect(japan.cards == ["01-1": 10, "13-2": 3])
        #expect(japan.rainbow == ["01-1"])
        #expect(japan.streaks == [1: 4])
        #expect(japan.records[QuizMode.findOnMap.rawValue]?[0] == StageRecord(stars: 3, score: 730))
        #expect(japan.records[QuizMode.nameIt.rawValue]?[3] == StageRecord(stars: 2, score: 400))
        #expect(japan.askedInChallenge.isEmpty,
                "a challenge history cannot predate the world atlas")
        #expect(data.atlases[SaveData.worldAtlas] == nil,
                "a world nobody has visited is absent, not fabricated")
        #expect(data.settings.soundEnabled == false)
    }

    /// Chain integrity: a version 1 file must still walk every lift — キラ to
    /// gold, flat stages to map-mode records, mastery to the stretched ladder —
    /// and the result of that walk is what lands in the japan namespace.
    @Test func aVersionOneFileWalksTheWholeChainIntoTheJapanAtlas() throws {
        let data = try load("""
        {"version":1,"mastery":{"1":3},"cards":{"01-1":2},
         "stages":{"0":{"stars":3,"score":730}}}
        """)
        let japan = try #require(data.atlases[SaveData.japanAtlas])
        #expect(japan.mastery[1] == GameRules.maxMastery)
        #expect(japan.cards["01-1"] == GameRules.maxCardStars)
        #expect(japan.records[QuizMode.findOnMap.rawValue]?[0] == StageRecord(stars: 3, score: 730))
        #expect(data.version == SaveData.currentVersion)
    }

    /// A version 7 file is already the current shape: encode → decode must be
    /// the identity, including a world atlas with a challenge history.
    @Test func aVersionSevenFileRoundTripsIdentically() throws {
        var data = SaveData()
        data.mastery = [1: 3]
        data.cards = ["01-1": 5]
        var world = AtlasSave()
        world.mastery = [840: 2]
        world.cards = ["840-1": 1]
        world.askedInChallenge = [QuizMode.findOnMap.rawValue: [840, 392]]
        data.atlases[SaveData.worldAtlas] = world

        let reloaded = try JSONDecoder().decode(
            SaveData.self, from: JSONEncoder().encode(data))
        #expect(reloaded == data)
        #expect(reloaded.atlases[SaveData.worldAtlas]?
            .askedInChallenge[QuizMode.findOnMap.rawValue] == [840, 392])
    }

    /// A file from a future build keeps its own number and its own content —
    /// this build must not relabel it or invent anything into it.
    @Test func aFutureFileKeepsItsNumberAndItsContent() throws {
        let data = try load("""
        {"version":99,
         "atlases":{"japan":{"mastery":{"1":5}},
                    "world":{"cards":{"840-1":1}}},
         "settings":{"soundEnabled":false}}
        """)
        #expect(data.version == 99)
        #expect(data.atlases[SaveData.japanAtlas]?.mastery == [1: 5])
        #expect(data.atlases[SaveData.worldAtlas]?.cards == ["840-1": 1])

        let reloaded = try JSONDecoder().decode(
            SaveData.self, from: JSONEncoder().encode(data))
        #expect(reloaded.version == 99, "writing it back must not lower the number")
        #expect(reloaded.atlases[SaveData.worldAtlas]?.cards == ["840-1": 1])
    }

    /// A shipped version 6 build that opened a version 7 file keeps the number
    /// (that rule shipped with it) but writes its own flat shape under it. What
    /// it recorded there is real play, so a later read folds it into japan
    /// rather than ignoring keys the current shape no longer writes.
    @Test func aLegacyShapeWrittenUnderAFutureNumberStillLandsInJapan() throws {
        let data = try load(#"{"version":7,"mastery":{"1":5},"cards":{"01-1":10}}"#)
        #expect(data.atlases[SaveData.japanAtlas]?.mastery == [1: 5])
        #expect(data.atlases[SaveData.japanAtlas]?.cards == ["01-1": 10])
    }

    /// A file carrying both shapes — a populated japan namespace AND stale
    /// flat fields — keeps the namespaced value wherever the two collide, and
    /// still rescues entries only the flat shape knows. This pins the merge
    /// direction of every fold: flipping any `{ current, _ in current }` to
    /// last-wins would pass the rest of the suite while walking a child's
    /// namespaced progress backwards.
    @Test func namespacedValuesBeatStaleFlatFieldsOnEveryFold() throws {
        let data = try load("""
        {"version":7,
         "atlases":{"japan":{
            "mastery":{"1":5},
            "cards":{"01-1":10},
            "rainbow":["01-1"],
            "streaks":{"1":6},
            "records":{"findOnMap":{"0":{"stars":3,"score":900}}}}},
         "mastery":{"1":2,"13":4},
         "cards":{"01-1":3,"13-2":1},
         "rainbow":["13-2"],
         "streaks":{"1":1,"13":2},
         "records":{"findOnMap":{"0":{"stars":1,"score":100},
                                 "1":{"stars":2,"score":400}}}}
        """)
        let japan = try #require(data.atlases[SaveData.japanAtlas])
        #expect(japan.mastery == [1: 5, 13: 4])
        #expect(japan.cards == ["01-1": 10, "13-2": 1])
        #expect(japan.rainbow == ["01-1", "13-2"],
                "rainbow is a one-way latch: a union, so both survive")
        #expect(japan.streaks == [1: 6, 13: 2])
        #expect(japan.records[QuizMode.findOnMap.rawValue]?[0] == StageRecord(stars: 3, score: 900),
                "a colliding record keeps the namespaced best")
        #expect(japan.records[QuizMode.findOnMap.rawValue]?[1] == StageRecord(stars: 2, score: 400),
                "a record only the flat shape knows is rescued")
    }

    /// The written file carries the namespaced form only. Writing the legacy
    /// top-level fields too would leave every future read two sources of truth
    /// to reconcile — the same reason `stages` is read but never written.
    @Test func versionSevenWritesOnlyTheNamespacedForm() throws {
        var data = SaveData()
        data.mastery = [1: 2]
        data.records[QuizMode.findOnMap.rawValue] = [0: StageRecord(stars: 1, score: 1)]
        let object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(data))
        let top = try #require(object as? [String: Any])
        #expect(Set(top.keys) == ["version", "atlases", "settings"])
    }

    /// The five legacy properties are thin forwards onto `atlases["japan"]`:
    /// a write through either side must be visible from the other, and must
    /// not leak into the world atlas.
    @Test func theJapanForwardsReadAndWriteTheJapanAtlas() throws {
        var data = SaveData()
        #expect(data.atlases[SaveData.japanAtlas] == nil)

        data.mastery[13] = 4
        #expect(data.atlases[SaveData.japanAtlas]?.mastery == [13: 4])

        data.atlases[SaveData.japanAtlas]?.mastery[13] = 5
        #expect(data.mastery == [13: 5])
        #expect(data.masteryLevel(of: 13) == 5)

        data.cards["01-1"] = 3
        data.rainbow.insert("01-1")
        data.streaks[13] = 2
        data.records[QuizMode.findOnMap.rawValue, default: [:]][0] = StageRecord(stars: 3, score: 100)
        let japan = try #require(data.atlases[SaveData.japanAtlas])
        #expect(japan.cards == ["01-1": 3])
        #expect(japan.rainbow == ["01-1"])
        #expect(japan.streaks == [13: 2])
        #expect(japan.records[QuizMode.findOnMap.rawValue]?[0] == StageRecord(stars: 3, score: 100))
        #expect(data.atlases[SaveData.worldAtlas] == nil,
                "japan writes must not leak into the world atlas")
    }
}
