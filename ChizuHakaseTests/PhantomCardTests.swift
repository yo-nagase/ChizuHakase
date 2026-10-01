import Foundation
import Testing

@testable import ChizuHakase

@MainActor
struct PhantomCardTests {
    private var japanAtlas: Atlas {
        Atlas.japan(mapData: AtlasTests.japanMap, cards: AtlasTests.japanCards)
    }

    private func worldAtlas() throws -> Atlas {
        Atlas.world(from: try AtlasTests.world.get(), cards: AtlasTests.worldCards)
    }

    @Test func availableCatalogFollowsBuildFlag() throws {
        #if DEBUG
        #expect(FeatureFlags.phantomCardsEnabled)
        #else
        #expect(!FeatureFlags.phantomCardsEnabled)
        #endif
        for atlas in [japanAtlas, try worldAtlas()] {
            let available = PhantomCard.availableCatalog(for: atlas)
            #expect(available == (FeatureFlags.phantomCardsEnabled
                                  ? PhantomCard.catalog(for: atlas) : []))
        }
    }

    @Test func reconciliationHonorsFlagAndPreservesExistingOwnership() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-flag-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var data = SaveData()
        var slice = AtlasSave()
        slice.phantomCards = ["phantom-japan-perfect"]
        for code in 1...47 { slice.mastery[code] = GameRules.maxMastery }
        data.atlases[SaveData.japanAtlas] = slice
        try JSONEncoder().encode(data).write(to: directory.appendingPathComponent("savedata.json"))
        let store = SaveStore(directory: directory)
        let gained = store.reconcilePhantomCards(PhantomCard.catalog(for: japanAtlas),
                                                atlas: SaveData.japanAtlas)
        let expected: Set<String> = FeatureFlags.phantomCardsEnabled
            ? ["phantom-japan-sky", "phantom-japan-earth", "phantom-japan-sea"] : []
        #expect(Set(gained) == expected)
        let reloaded = SaveStore(directory: directory)
        #expect(reloaded.data.atlas(SaveData.japanAtlas).phantomCards
                == expected.union(["phantom-japan-perfect"]))
    }

    @Test func eachAtlasHasThePromisedNumberOfPhantomCards() throws {
        let japan = PhantomCard.catalog(for: japanAtlas)
        let world = PhantomCard.catalog(for: try worldAtlas())

        #expect(japan.count == 4)
        #expect(japan.map(\.setIndex) == [1, 2, 3, 4])
        #expect(japan.allSatisfy { $0.setCount == 4 })
        #expect(world.count == 7)
        #expect(world.map(\.setIndex) == Array(1...7))
        #expect(world.allSatisfy { $0.setCount == 7 })
        #expect(Set((japan + world).map(\.id)).count == 11)
    }

    @Test func masteringEveryEastJapanLocationUnlocksOnlySky() {
        let atlas = japanAtlas
        var save = AtlasSave()
        for code in 1...14 { save.mastery[code] = GameRules.maxMastery }

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas),
            save: save)

        #expect(unlocked == ["phantom-japan-sky"])
    }

    @Test func oneLocationBelowMaximumKeepsTheRewardHidden() {
        let atlas = japanAtlas
        var save = AtlasSave()
        for code in 1...14 { save.mastery[code] = GameRules.maxMastery }
        save.mastery[14] = GameRules.maxMastery - 1

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas),
            save: save)

        #expect(unlocked.isEmpty)
    }

    @Test func owningEveryOrdinaryCardDoesNotReplaceMastery() {
        let atlas = japanAtlas
        var save = AtlasSave()
        for card in atlas.cards.all { save.cards[card.id] = 1 }

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas), save: save)

        #expect(unlocked.isEmpty)
    }

    @Test func allSixWorldRegionsUnlockAntarcticaInTheSamePass() throws {
        let atlas = try worldAtlas()
        var save = AtlasSave()
        for code in Set(atlas.stages.flatMap(\.codes)) {
            save.mastery[code] = GameRules.maxMastery
        }

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas),
            save: save)

        #expect(unlocked.count == 7)
        #expect(unlocked.contains("phantom-world-antarctica"))
    }

    @Test func existingOwnershipIsNeverAnnouncedAgain() {
        let atlas = japanAtlas
        var save = AtlasSave()
        for code in 1...14 { save.mastery[code] = GameRules.maxMastery }
        save.phantomCards.insert("phantom-japan-sky")

        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: atlas),
            save: save)

        #expect(unlocked.isEmpty)
    }

    @Test func versionEightSaveDefaultsPhantomOwnershipToEmpty() throws {
        let json = Data(#"{"version":8,"atlases":{"japan":{"cards":{"01-1":1}}}}"#.utf8)
        let data = try JSONDecoder().decode(SaveData.self, from: json)

        #expect(data.version == SaveData.currentVersion)
        #expect(data.atlas(SaveData.japanAtlas).phantomCards.isEmpty)
        #expect(data.atlas(SaveData.japanAtlas).cards["01-1"] == 1)
    }
    private func challengeResult(mode: QuizMode = .findOnMap, stage: Int = 6,
                                 answers: [Int: Bool]? = nil) -> StageResult {
        StageResult(mode: mode, stageIndex: stage, score: 0, stars: 3,
                    firstTryByPrefecture: answers ?? Dictionary(
                        uniqueKeysWithValues: (1...47).map { ($0, true) }),
                    cardDraws: [])
    }

    @Test func perfectNationwideRunUnlocksJapanInEitherMode() {
        for mode in QuizMode.allCases {
            let unlocked = PhantomCard.newlyUnlocked(
                from: PhantomCard.catalog(for: japanAtlas), save: AtlasSave(),
                result: challengeResult(mode: mode), atlasKey: SaveData.japanAtlas)
            #expect(unlocked == ["phantom-japan-perfect"])
        }
    }

    @Test func missedOrIncompleteRunCannotUnlockJapan() {
        var missed = challengeResult().firstTryByPrefecture
        missed[47] = false
        var incomplete = challengeResult().firstTryByPrefecture
        incomplete.removeValue(forKey: 47)
        for answers in [missed, incomplete, [:]] {
            let unlocked = PhantomCard.newlyUnlocked(
                from: PhantomCard.catalog(for: japanAtlas), save: AtlasSave(),
                result: challengeResult(answers: answers), atlasKey: SaveData.japanAtlas)
            #expect(unlocked.isEmpty)
        }
    }

    @Test func regionalOrWorldRunCannotUnlockJapan() {
        let cards = PhantomCard.catalog(for: japanAtlas)
        #expect(PhantomCard.newlyUnlocked(
            from: cards, save: AtlasSave(), result: challengeResult(stage: 0),
            atlasKey: SaveData.japanAtlas).isEmpty)
        #expect(PhantomCard.newlyUnlocked(
            from: cards, save: AtlasSave(), result: challengeResult(),
            atlasKey: SaveData.worldAtlas).isEmpty)
    }

    @Test func cumulativeMasteryDoesNotUnlockJapan() {
        var save = AtlasSave()
        for code in 1...47 { save.mastery[code] = GameRules.maxMastery }
        let unlocked = PhantomCard.newlyUnlocked(
            from: PhantomCard.catalog(for: japanAtlas), save: save)
        #expect(unlocked == ["phantom-japan-sky", "phantom-japan-earth", "phantom-japan-sea"])
    }

    @Test func perfectJapanRewardIsSavedAndOnlyAnnouncedOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phantom-perfect-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SaveStore(directory: directory)
        let cards = PhantomCard.catalog(for: japanAtlas)
        let first = store.applyStageResult(challengeResult(), catalog: .empty,
                                          atlas: SaveData.japanAtlas, phantomCards: cards)
        #expect(first.phantomCards == (FeatureFlags.phantomCardsEnabled
                                     ? ["phantom-japan-perfect"] : []))
        let reloaded = SaveStore(directory: directory)
        #expect(reloaded.data.atlas(SaveData.japanAtlas).phantomCards
            .contains("phantom-japan-perfect") == FeatureFlags.phantomCardsEnabled)
        let again = reloaded.applyStageResult(challengeResult(), catalog: .empty,
                                             atlas: SaveData.japanAtlas, phantomCards: cards)
        #expect(again.phantomCards.isEmpty)
        #expect(reloaded.data.atlas(SaveData.worldAtlas).phantomCards.isEmpty)
    }

    @Test func completeQuizPreservesOneMistakeAndRequiresAll47Answers() throws {
        let atlas = japanAtlas
        for shouldMiss in [false, true] {
            let quiz = QuizViewModel(stage: try #require(atlas.stage(at: 6)),
                                     mapData: atlas.mapData, catalog: atlas.cards,
                                     drawPolicy: atlas.drawPolicy, askedInChallenge: [])
            if shouldMiss {
                let target = try #require(quiz.target)
                quiz.answer(target.code == 1 ? 2 : 1)
            }
            let cards = PhantomCard.catalog(for: atlas)
            #expect(PhantomCard.newlyUnlocked(
                from: cards, save: AtlasSave(), result: quiz.makeResult(),
                atlasKey: atlas.saveKey).isEmpty)
            while quiz.phase != .finished {
                let target = try #require(quiz.target)
                quiz.answer(target.code)
                quiz.advance()
            }
            let result = quiz.makeResult()
            #expect(result.firstTryByPrefecture.count == 47)
            let unlocked = PhantomCard.newlyUnlocked(
                from: cards, save: AtlasSave(), result: result, atlasKey: atlas.saveKey)
            #expect(unlocked.contains("phantom-japan-perfect") == !shouldMiss)
        }
    }

}
