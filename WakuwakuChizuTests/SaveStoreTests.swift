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
            cardDraws: []))

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
                                           firstTryByPrefecture: [:], cardDraws: []))
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 1, score: 100, stars: 1,
                                           firstTryByPrefecture: [:], cardDraws: []))

        #expect(store.data.record(forStage: 1, mode: .findOnMap) == StageRecord(stars: 3, score: 800))
    }

    @Test func masteryAccumulatesAcrossPlaysAndCapsAtThree() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        for _ in 0..<5 {
            store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 100, stars: 3,
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
                StageResult(mode: .findOnMap, stageIndex: 0, score: 100, stars: 3,
                            firstTryByPrefecture: [5: true], cardDraws: [])))
        }
        // Levels 1, 2, then 3 (announced), then nothing further.
        #expect(announcements == [[], [], [5], []])
    }

    @Test func wrongAnswersDoNotReduceStoredMastery() throws {
        let dir = try makeScratch()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SaveStore(directory: dir)
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 100, stars: 3,
                                           firstTryByPrefecture: [7: true], cardDraws: []))
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 50, stars: 1,
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
        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.new(card)]))
        #expect(store.data.stars(of: "01-1") == 1)
        #expect(store.data.owns("01-1"))
        #expect(store.data.tier(of: "01-1") == .plain)

        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.star(card, stars: 3)]))
        #expect(store.data.tier(of: "01-1") == .silver)

        store.applyStageResult(StageResult(mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                                           firstTryByPrefecture: [:],
                                           cardDraws: [.star(card, stars: 5), .duplicate(card)]))
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
                                           cardDraws: []))
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
            ]))

        #expect(store.data.totalOwnedCards == 3)
        #expect(store.data.specialCardCount == 1)
        #expect(store.data.goldCardCount == 0)
        #expect(store.data.sparklingPrefectureCount == 0)
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
        // The rest of the file has to survive the move.
        #expect(data.masteryLevel(of: 1) == 3)
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

    /// The remap must not run twice: a version 3 file already speaks in stars,
    /// and a two there is a two.
    @Test func aVersionThreeFileKeepsItsStarCounts() throws {
        let data = try load("""
        {"version":3,"cards":{"01-1":2,"01-2":3,"01-3":5}}
        """)
        #expect(data.stars(of: "01-1") == 2)
        #expect(data.tier(of: "01-1") == .plain)
        #expect(data.tier(of: "01-2") == .silver)
        #expect(data.tier(of: "01-3") == .gold)
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
