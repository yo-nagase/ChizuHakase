import Foundation
import Testing
@testable import ChizuHakase

@MainActor
struct RankingTests {
    private let board = RankingBoard(atlas: "japan", stage: 0, mode: .findOnMap, questionCount: 14)

    @Test func courseRanksDistinguishMissingRecordsAndFailures() async {
        let model = StageRankings()
        await model.reload(boards: [board], context: "one", participating: true, playerID: "one") { boards in
            [boards[0].id: .ranked(123)]
        }
        #expect(model.rank(for: board, context: "one", participating: true, playerID: "one") == .ranked(123))
        #expect(model.rank(for: board, context: "another-mode", participating: true, playerID: "one") == .loading)
        #expect(model.rank(for: board, context: "one", participating: false, playerID: "one") == .notParticipating)
        #expect(model.rank(for: board, context: "one", participating: true, playerID: nil) == .signedOut)
        await model.reload(boards: [board], context: "one", participating: true, playerID: "one") { boards in
            [boards[0].id: .noRecord]
        }
        #expect(model.rank(for: board, context: "one", participating: true, playerID: "one") == .noRecord)
        await model.reload(boards: [board], context: "one", participating: true, playerID: "one") { _ in [:] }
        #expect(model.rank(for: board, context: "one", participating: true, playerID: "one") == .unavailable)
        await model.reload(boards: [board], context: "one", participating: true, playerID: "one") { _ in
            throw GameCenterService.RankingError.notSignedIn
        }
        #expect(model.rank(for: board, context: "one", participating: true, playerID: "one") == .unavailable)
    }

    @Test func courseRanksDoNotLoadWithoutParticipationOrSignIn() async {
        let model = StageRankings()
        var called = false
        for (participating, player) in [(false, "one" as String?), (true, nil)] {
            await model.reload(boards: [board], context: "guest", participating: participating, playerID: player) { _ in
                called = true
                return [:]
            }
        }
        #expect(!called)
    }

    @Test func lateCourseRankResponseCannotOverwriteNewSelection() async {
        let model = StageRankings()
        var response: CheckedContinuation<[String: StageRank], Never>?
        let first = Task {
            await model.reload(boards: [board], context: "old", participating: true, playerID: "one") { _ in
                await withCheckedContinuation { response = $0 }
            }
        }
        while response == nil { await Task.yield() }
        await model.reload(boards: [board], context: "new", participating: true, playerID: "two") { boards in
            [boards[0].id: .ranked(7)]
        }
        response?.resume(returning: [board.id: .ranked(99)])
        await first.value
        #expect(model.rank(for: board, context: "new", participating: true, playerID: "two") == .ranked(7))
    }

    private func run(correct: Int = 10, ms: Int = 5_000, player: String? = "one",
                     completed: Bool = true, interrupted: Bool = false) -> RankingRun {
        RankingRun(id: UUID(), board: board, date: Date(), correct: correct,
                   milliseconds: ms, completed: completed, interrupted: interrupted, playerID: player)
    }

    @Test func accuracyAlwaysBeatsTimeAndEncodingRoundTrips() throws {
        let slow = run(correct: 11, ms: RankingRun.timeBase - 1)
        let fast = run(correct: 10, ms: 0)
        #expect(try #require(slow.packedScore) > #require(fast.packedScore))
        let original = run(ms: 12_345)
        let decoded = RankingRun.unpack(try #require(original.packedScore))
        #expect(decoded.correct == 10)
        #expect(decoded.milliseconds == 12_345)
        #expect(try #require(run(ms: 4_999).packedScore) > #require(run().packedScore))
        #expect(run(ms: RankingRun.timeBase).packedScore == nil)
        #expect(run(interrupted: true).packedScore == nil)
        #expect(run(completed: false).packedScore == nil)
    }

    @Test func clockExcludesCelebrationAndBackground() {
        var timer = RankingTimer()
        timer.start(at: 10)
        timer.start(at: 11)
        timer.pause(at: 12)
        #expect(timer.milliseconds(at: 30) == 2_000)
        timer.start(at: 30)
        timer.interrupt(at: 33)
        timer.start(at: 90)
        timer.pause(at: 91)
        #expect(timer.milliseconds(at: 100) == 6_000)
        #expect(timer.interrupted)
    }

    @Test func queuePersistsBestAndNeverTransfersAccounts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RankingStore(directory: directory)
        store.setParticipation(true)
        let best = run(correct: 12)
        store.record(run())
        store.record(best)
        store.record(run(correct: 14, player: nil))
        store.record(run(correct: 13, player: "two"))
        store.record(run(correct: 14, interrupted: true))
        store.record(run(correct: 14, completed: false))
        let loaded = RankingStore(directory: directory)
        #expect(loaded.pending(for: "one").map(\.id) == [best.id])
        #expect(loaded.pending(for: "two").count == 1)
        loaded.markSent(best)
        #expect(RankingStore(directory: directory).pending(for: "one").isEmpty)
        #expect(loaded.history(for: board).count == 5)
        loaded.setParticipation(false)
        #expect(loaded.pending(for: "two").isEmpty)
        #expect(loaded.errorMessage == nil)
    }

    @Test func snapshotUpdatesWithoutOverwritingFinishedRun() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RankingStore(directory: directory)
        let snapshot = run(completed: false, interrupted: true)
        let final = RankingRun(id: snapshot.id, board: board, date: snapshot.date,
                               correct: 12, milliseconds: 9_000, completed: true,
                               interrupted: true, playerID: "one")
        store.record(snapshot)
        store.record(final)
        store.record(snapshot)
        #expect(store.history(for: board) == [final])
        #expect(store.history(for: board, completed: false).isEmpty)
    }

    @Test func repeatQuestionsCountIndividuallyAndCelebrationIsExcluded() throws {
        var now: TimeInterval = 0
        let quiz = QuizViewModel(stage: Stage.all[0], mapData: MapDataTests.map,
                                 catalog: MapDataTests.catalog, drawPolicy: .random,
                                 askedInChallenge: [], rankingNow: { now })
        quiz.beginRanking(playerID: "one")
        var answered = 0
        while quiz.phase != .finished {
            let target = try #require(quiz.target)
            now += 2
            if answered == 0 { quiz.answer(-1) }
            quiz.answer(target.code)
            now += 100 // card celebration is not thinking time
            quiz.advance()
            answered += 1
        }
        let result = quiz.rankingRun(atlas: "japan")
        #expect(result.correct == quiz.questionCount - 1)
        #expect(result.milliseconds == quiz.questionCount * 2_000)
        #expect(result.packedScore != nil)
        #expect(result.playerID == "one")
    }

    @Test func allBoardsAreUniqueAndWorldChallengeStays47Questions() throws {
        let world = Atlas.world(from: try QuizModeTests.world.get())
        let japan = Atlas.japan(mapData: MapDataTests.map, cards: MapDataTests.catalog)
        let boards = [japan, world].flatMap { atlas in
            atlas.stages.flatMap { stage in
                QuizMode.allCases.map { mode in
                    RankingBoard(atlas: atlas.saveKey, stage: stage.index, mode: mode,
                                 questionCount: stage.questionCount)
                }
            }
        }
        #expect(boards.count == 52)
        #expect(Set(boards.map(\.id)).count == 52)
        #expect(world.stage(at: WorldStage.challengeIndex)?.questionCount == 47)
    }
}
