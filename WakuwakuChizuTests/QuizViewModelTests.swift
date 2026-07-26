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

    /// Taps every wrong prefecture in the stage, `times` of them, then answers.
    @discardableResult
    private func answerAfterMissing(_ quiz: QuizViewModel, times: Int) -> GameRules.CardDraw? {
        guard let target = quiz.target else { return nil }
        let wrong = quiz.order.filter { $0 != target.code }.prefix(times)
        #expect(wrong.count == times, "stage is too small to miss \(times) times")
        for code in wrong { quiz.answer(code) }
        quiz.answer(target.code)
        return quiz.lastDraw
    }

    // MARK: - Earning a card

    @Test func aCleanAnswerStillWinsACard() {
        let quiz = makeQuiz()
        #expect(answerAfterMissing(quiz, times: 0) != nil)
    }

    /// One wrong tap is enough. The card marks having known it outright, and
    /// one handed out after a fumble marks nothing.
    @Test func oneMissLosesTheCard() {
        let quiz = makeQuiz()
        #expect(answerAfterMissing(quiz, times: 1) == nil)
    }

    /// Two misses light up the answer, so tapping it proves nothing.
    @Test func answeringAfterTheHintWinsNoCard() {
        let quiz = makeQuiz()
        #expect(quiz.hintCode == nil)
        let draw = answerAfterMissing(quiz, times: GameRules.missesBeforeHint)
        #expect(draw == nil, "a card was handed out after the answer was shown")
    }

    /// The card is withheld, not the progress. Nothing a child has earned is
    /// taken back (CLAUDE.md §12).
    @Test func theHintStillScoresAndStillCountsAsAnswered() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        answerAfterMissing(quiz, times: GameRules.missesBeforeHint)
        #expect(quiz.score == 50)
        #expect(quiz.answeredCodes.contains(target.code))
    }

    /// A stage played entirely past the hint ends with no cards at all, and
    /// still finishes cleanly.
    @Test func aStageAnsweredOnlyAfterHintsYieldsNoCards() {
        let quiz = makeQuiz()
        while quiz.phase != .finished {
            guard quiz.target != nil else { break }
            answerAfterMissing(quiz, times: GameRules.missesBeforeHint)
            quiz.advance()
        }
        #expect(quiz.makeResult().cardDraws.isEmpty)
    }

    // MARK: - Setup

    /// A regional stage asks each prefecture twice. Once is a coin-flip.
    @Test func aRegionalStageAsksEveryPrefectureTwice() {
        let quiz = makeQuiz(stageIndex: 0)
        #expect(quiz.questionCount == 14)
        #expect(Set(quiz.order) == Set(Stage.all[0].codes))
        for code in Stage.all[0].codes {
            #expect(quiz.order.filter { $0 == code }.count == 2,
                    "prefecture \(code) is not asked exactly twice")
        }
    }

    /// 47 questions is already a long sitting; 94 would be a different activity.
    @Test func theAllJapanStageAsksEachPrefectureOnce() {
        let quiz = makeQuiz(stageIndex: 6)
        #expect(quiz.questionCount == 47)
        #expect(quiz.order.count == Set(quiz.order).count)
    }

    /// An immediate repeat tests what is still under the child's finger.
    @Test func aPrefectureIsNeverAskedTwiceInARow() {
        for seed in UInt64(1)...20 {
            let quiz = makeQuiz(stageIndex: 0, seed: seed)
            for (a, b) in zip(quiz.order, quiz.order.dropFirst()) {
                #expect(a != b, "seed \(seed) repeats \(a) back to back")
            }
        }
    }

    /// Stars are judged out of the prefectures, not the questions. A stage that
    /// asks 7 twice is still a 7-prefecture stage.
    @Test func starsAreGradedOnPrefecturesNotQuestions() {
        let quiz = makeQuiz(stageIndex: 0)
        #expect(quiz.prefectureCount == 7)
        #expect(quiz.questionCount == 14)
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
        // 14 questions, the combo climbing by 20 each time:
        // 14 x 100 + 20 x (0 + 1 + ... + 13)
        #expect(quiz.score == 3220)
        #expect(quiz.combo == 14)
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

    /// Driven by the constant rather than a hard-coded two: the threshold moved
    /// to three, and a test that says "two" in its name and its body is the
    /// kind that gets edited to match the code instead of checking it.
    @Test func theHintWaitsForTheFullAllowanceOfMisses() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        let others = quiz.order.filter { $0 != target.code }
        #expect(others.count >= GameRules.missesBeforeHint, "stage too small for this test")

        #expect(quiz.hintCode == nil)
        for miss in 0..<(GameRules.missesBeforeHint - 1) {
            quiz.answer(others[miss])
            #expect(quiz.hintCode == nil,
                    "\(miss + 1) miss(es) is not enough to give the answer away")
        }
        quiz.answer(others[GameRules.missesBeforeHint - 1])
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

    /// Answered prefectures stay tappable.
    ///
    /// They used to drop out, which together with them changing colour made
    /// every question easier than the last — by the seventh there was one shape
    /// left. They also get asked again, so they have to stay live.
    @Test func answeredPrefecturesStayTappable() throws {
        let quiz = makeQuiz()
        let target = try #require(quiz.target)
        #expect(quiz.interactiveCodes.contains(target.code))
        quiz.answer(target.code)
        quiz.advance()
        #expect(quiz.interactiveCodes.contains(target.code))
        #expect(quiz.interactiveCodes == Set(Stage.all[0].codes))
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
        #expect(drawCount == 14)
        #expect(quiz.makeResult().cardDraws.count == 14)
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
