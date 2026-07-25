import Foundation
import Testing

@testable import WakuwakuChizu

/// CLAUDE.md §5: the question loop.
@MainActor
struct QuizViewModelTests {

    private func makeQuiz(stageIndex: Int = 0,
                          owned: [String: Int] = [:],
                          seed: UInt64 = 1) -> QuizViewModel {
        QuizViewModel(stage: Stage.all[stageIndex],
                      mapData: MapDataTests.map,
                      catalog: MapDataTests.catalog,
                      ownedCards: owned,
                      generator: AnyRandomNumberGenerator(SeededGenerator(seed: seed)))
    }

    /// Answer every question correctly on the first try.
    private func playPerfectly(_ quiz: QuizViewModel) {
        while quiz.phase != .finished {
            guard let target = quiz.target else { break }
            quiz.answer(target.code)
            quiz.advance()
        }
    }

    // MARK: - Setup

    @Test func asksEveryPrefectureInTheStageExactlyOnce() {
        let quiz = makeQuiz(stageIndex: 0)
        #expect(quiz.questionCount == 7)
        #expect(Set(quiz.order) == Set(Stage.all[0].codes))
        #expect(quiz.order.count == Set(quiz.order).count, "no prefecture repeats")
    }

    @Test func questionOrderIsShuffled() {
        // Different seeds should not agree on the 47-question stage; if they do
        // the shuffle is not being applied.
        let a = makeQuiz(stageIndex: 6, seed: 1).order
        let b = makeQuiz(stageIndex: 6, seed: 999).order
        #expect(a != b)
        #expect(Set(a) == Set(b))
    }

    @Test func startsInAskingWithACleanSlate() {
        let quiz = makeQuiz()
        #expect(quiz.phase == .asking)
        #expect(quiz.score == 0)
        #expect(quiz.combo == 0)
        #expect(quiz.attempts == 0)
        #expect(quiz.target != nil)
        #expect(quiz.hintCode == nil)
    }

    // MARK: - Judging

    @Test func correctAnswerScoresAndCelebrates() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        let answer = quiz.answer(target.code)

        guard case .correct(let firstTry, let points, _) = answer else {
            Issue.record("expected .correct, got \(answer)"); return
        }
        #expect(firstTry)
        #expect(points == 100)
        #expect(quiz.score == 100)
        #expect(quiz.combo == 1)
        #expect(quiz.phase == .celebrating)
        #expect(quiz.effect?.kind == .pop)
        #expect(quiz.effect?.code == target.code)
    }

    @Test func wrongAnswerShakesAndBreaksTheCombo() throws {
        let quiz = makeQuiz()
        // Build a combo first.
        let first = try #require(quiz.target)
        quiz.answer(first.code)
        quiz.advance()
        #expect(quiz.combo == 1)

        let target = try #require(quiz.target)
        let wrong = try #require(quiz.order.first { $0 != target.code })
        let answer = quiz.answer(wrong)

        #expect(answer == .wrong(code: wrong))
        #expect(quiz.combo == 0)
        #expect(quiz.attempts == 1)
        #expect(quiz.phase == .asking, "a miss keeps the question open")
        #expect(quiz.effect?.kind == .shake)
        #expect(quiz.effect?.code == wrong)
    }

    @Test func comboRaisesTheScoreOnConsecutiveFirstTryAnswers() {
        let quiz = makeQuiz(stageIndex: 0)
        playPerfectly(quiz)
        // 7 questions: 100 + 120 + 140 + 160 + 180 + 200 + 220
        #expect(quiz.score == 1120)
        #expect(quiz.combo == 7)
    }

    @Test func answeringAfterAMissScoresTheFlatFifty() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        let wrong = try #require(quiz.order.first { $0 != target.code })

        quiz.answer(wrong)
        let answer = quiz.answer(target.code)

        guard case .correct(let firstTry, let points, _) = answer else {
            Issue.record("expected .correct, got \(answer)"); return
        }
        #expect(!firstTry)
        #expect(points == 50)
        #expect(quiz.combo == 0, "a recovered answer does not restart the combo")
    }

    @Test func tapsDuringTheCelebrationAreIgnored() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        quiz.answer(target.code)
        #expect(quiz.answer(target.code) == .ignored)
        #expect(quiz.score == 100, "a double tap must not score twice")
    }

    // MARK: - Hint

    @Test func hintAppearsOnlyAfterTwoMisses() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        let others = quiz.order.filter { $0 != target.code }

        #expect(quiz.hintCode == nil)
        quiz.answer(others[0])
        #expect(quiz.hintCode == nil, "one miss is not enough to give it away")
        quiz.answer(others[1])
        #expect(quiz.hintCode == target.code)
    }

    @Test func hintClearsOnTheNextQuestion() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        let others = quiz.order.filter { $0 != target.code }
        quiz.answer(others[0])
        quiz.answer(others[1])
        quiz.answer(target.code)
        quiz.advance()
        #expect(quiz.hintCode == nil)
        #expect(quiz.attempts == 0)
    }

    // MARK: - Interactivity

    @Test func answeredPrefecturesStopBeingTappable() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        #expect(quiz.interactiveCodes.contains(target.code))
        quiz.answer(target.code)
        quiz.advance()
        #expect(!quiz.interactiveCodes.contains(target.code))
    }

    @Test func nothingIsTappableWhileCelebrating() throws {
        let quiz = makeQuiz()
        quiz.answer(try #require(quiz.target).code)
        #expect(quiz.interactiveCodes.isEmpty)
    }

    // MARK: - Cards

    @Test func everyCorrectAnswerAwardsACard() {
        let quiz = makeQuiz(stageIndex: 0)
        var drawCount = 0
        while quiz.phase != .finished {
            guard let target = quiz.target else { break }
            if case .correct(_, _, let draw) = quiz.answer(target.code), draw != nil {
                drawCount += 1
            }
            quiz.advance()
        }
        #expect(drawCount == 7)
        #expect(quiz.makeResult().cardDraws.count == 7)
    }

    @Test func oneStageNeverAwardsTheSameUnownedCardTwice() {
        // Stage 6 asks all 47, so each prefecture is still only asked once;
        // replay the same stage repeatedly to accumulate instead.
        var owned: [String: Int] = [:]
        for _ in 0..<3 {
            let quiz = makeQuiz(stageIndex: 0, owned: owned, seed: 5)
            playPerfectly(quiz)
            for draw in quiz.makeResult().cardDraws {
                owned = GameRules.applyDraw(draw, to: owned)
            }
        }
        #expect(owned.values.allSatisfy { $0 <= GameRules.maxCardCopies })
    }

    @Test func alreadyOwnedCardsAreNotDrawnAgainWhileNewOnesRemain() throws {
        let quiz = makeQuiz(stageIndex: 0)
        let target = try #require(quiz.target)
        guard case .correct(_, _, let draw) = quiz.answer(target.code),
              let draw else {
            Issue.record("expected a card"); return
        }
        #expect(draw.card.prefectureCode == target.code,
                "the card must come from the prefecture just answered")
        if case .new = draw {} else {
            Issue.record("first win on a fresh save should be a new card, got \(draw)")
        }
    }

    // MARK: - Finishing

    @Test func perfectRunFinishesWithThreeStars() {
        let quiz = makeQuiz(stageIndex: 0)
        playPerfectly(quiz)
        #expect(quiz.phase == .finished)
        #expect(quiz.stars == 3)
        #expect(quiz.missedPrefectureCount == 0)
    }

    @Test func resultCarriesEveryPrefectureAndItsFirstTryFlag() throws {
        let quiz = makeQuiz(stageIndex: 0)
        // Fumble exactly one prefecture.
        var fumbled: Int?
        while quiz.phase != .finished {
            guard let target = quiz.target else { break }
            if fumbled == nil, let wrong = quiz.order.first(where: { $0 != target.code }) {
                quiz.answer(wrong)
                fumbled = target.code
            }
            quiz.answer(target.code)
            quiz.advance()
        }
        let result = quiz.makeResult()
        let missed = try #require(fumbled)

        #expect(result.firstTryByPrefecture.count == 7)
        #expect(result.firstTryByPrefecture[missed] == false)
        #expect(result.missedPrefectureCount == 1)
        #expect(result.stars == 2, "1 of 7 missed is within ceil(7/4)")
        #expect(result.stageIndex == 0)
    }

    @Test func advancingPastTheEndIsSafe() {
        let quiz = makeQuiz(stageIndex: 0)
        playPerfectly(quiz)
        quiz.advance()
        quiz.advance()
        #expect(quiz.phase == .finished)
        #expect(quiz.answer(1) == .ignored)
    }

    @Test func allJapanStageRunsAll47() {
        let quiz = makeQuiz(stageIndex: 6)
        #expect(quiz.questionCount == 47)
        playPerfectly(quiz)
        #expect(quiz.phase == .finished)
        #expect(quiz.makeResult().firstTryByPrefecture.count == 47)
        #expect(quiz.stars == 3)
    }
}
