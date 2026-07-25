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
        #expect(store.data.stages.isEmpty)
        #expect(store.data.version == SaveData.currentVersion)
        #expect(store.data.settings.soundEnabled)
        #expect(store.data.settings.speechEnabled)
        #expect(!store.data.settings.voiceInputEnabled)
    }

    @Test func roundTripsThroughDisk() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(
            stageIndex: 0, score: 730, stars: 3,
            firstTryByPrefecture: [1: true, 2: true, 3: false],
            cardDraws: []))

        let reloaded = SaveStore(directory: dir)
        #expect(reloaded.data.masteryLevel(of: 1) == 1)
        #expect(reloaded.data.masteryLevel(of: 3) == 0, "a missed prefecture gains nothing")
        #expect(reloaded.data.record(forStage: 0) == StageRecord(stars: 3, score: 730))
    }

    @Test func replayNeverLowersABestRecord() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(stageIndex: 1, score: 800, stars: 3,
                                           firstTryByPrefecture: [:], cardDraws: []))
        store.applyStageResult(StageResult(stageIndex: 1, score: 100, stars: 1,
                                           firstTryByPrefecture: [:], cardDraws: []))

        #expect(store.data.record(forStage: 1) == StageRecord(stars: 3, score: 800))
    }

    @Test func masteryAccumulatesAcrossPlaysAndCapsAtThree() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        for _ in 0..<5 {
            store.applyStageResult(StageResult(stageIndex: 0, score: 100, stars: 3,
                                               firstTryByPrefecture: [1: true],
                                               cardDraws: []))
        }
        #expect(store.data.masteryLevel(of: 1) == GameRules.maxMastery)
    }

    @Test func reachingLevelThreeIsReportedOnceOnly() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        var announcements: [[Int]] = []
        for _ in 0..<4 {
            announcements.append(store.applyStageResult(
                StageResult(stageIndex: 0, score: 100, stars: 3,
                            firstTryByPrefecture: [5: true], cardDraws: [])))
        }
        // Levels 1, 2, then 3 (announced), then nothing further.
        #expect(announcements == [[], [], [5], []])
    }

    @Test func wrongAnswersDoNotReduceStoredMastery() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(stageIndex: 0, score: 100, stars: 3,
                                           firstTryByPrefecture: [7: true], cardDraws: []))
        store.applyStageResult(StageResult(stageIndex: 0, score: 50, stars: 1,
                                           firstTryByPrefecture: [7: false], cardDraws: []))
        #expect(store.data.masteryLevel(of: 7) == 1)
    }

    @Test func cardDrawsPersistWithTheShinyCap() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let card = SpecialtyCard(id: "01-1", prefectureCode: 1, emoji: "🦀",
                                 nameKana: "かに", nameKanji: "蟹",
                                 category: .food, description: "うみ")
        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.new(card)]))
        #expect(store.data.ownedCount(of: "01-1") == 1)
        #expect(store.data.owns("01-1"))
        #expect(!store.data.isShiny("01-1"))

        store.applyStageResult(StageResult(stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.shiny(card), .duplicate(card)]))
        #expect(store.data.ownedCount(of: "01-1") == GameRules.maxCardCopies)
        #expect(store.data.isShiny("01-1"))
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
        #expect(store.data.ownedCount(of: "01-1") == 2)
        #expect(store.data.mastery.isEmpty)
        #expect(store.data.settings.speechEnabled, "missing settings take their defaults")
    }

    @Test func eraseAllClearsEverythingAndSurvivesReload() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(stageIndex: 0, score: 500, stars: 3,
                                           firstTryByPrefecture: [1: true, 2: true],
                                           cardDraws: []))
        store.eraseAll()

        #expect(store.data.mastery.isEmpty)
        #expect(store.data.stages.isEmpty)
        #expect(SaveStore(directory: dir).data.mastery.isEmpty)
    }

    @Test func derivedCountsReflectStoredState() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(
            stageIndex: 0, score: 0, stars: 3,
            firstTryByPrefecture: [:],
            cardDraws: [
                .new(card("01-1")), .new(card("01-2")), .shiny(card("02-1")),
            ]))

        #expect(store.data.totalOwnedCards == 3)
        #expect(store.data.shinyCardCount == 1)
        #expect(store.data.sparklingPrefectureCount == 0)
    }

    private func card(_ id: String) -> SpecialtyCard {
        SpecialtyCard(id: id, prefectureCode: Int(id.prefix(2)) ?? 1, emoji: "🍎",
                      nameKana: "てすと", nameKanji: "試験",
                      category: .food, description: "てすと")
    }
}
