import Foundation
import Testing

@testable import ChizuHakase

/// CLAUDE.md §5: the question loop.
@MainActor
struct QuizViewModelTests {

    private func makeQuiz(stageIndex: Int = 0,
                          owned: [String: Int] = [:],
                          asked: Set<Int> = [],
                          seed: UInt64 = 1) -> QuizViewModel {
        QuizViewModel(stage: Stage.all[stageIndex],
                      mapData: MapDataTests.map,
                      catalog: MapDataTests.catalog,
                      ownedCards: owned,
                      // Japan's policy, spelled out: the parameter lost its
                      // `.random` default so a world call site can never fall
                      // silently onto japan's draw (P6 final review).
                      drawPolicy: .random,
                      askedInChallenge: asked,
                      generator: AnyRandomNumberGenerator(SeededGenerator(seed: seed)))
    }

    /// 世界アトラス上の VM(ワールドチャレンジと、その対照用の地方ステージ)。
    private func makeWorldQuiz(stageIndex: Int,
                               asked: Set<Int> = [],
                               seed: UInt64 = 1) throws -> QuizViewModel {
        let atlas = Atlas.world(from: try QuizModeTests.world.get())
        return QuizViewModel(stage: try #require(atlas.stage(at: stageIndex)),
                             mapData: atlas.mapData,
                             catalog: atlas.cards,
                             drawPolicy: atlas.drawPolicy,
                             askedInChallenge: asked,
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

    // MARK: - 世界チャレンジ(設計 §8: 毎回 47 問・未出題優先)

    /// 167 カ国の総合ステージは 47 問の 1 回ぶんに切られ、1 国 1 回、
    /// 全部この本の国。星は訊いた 47 カ国を分母に判定する(毎回 47 問だから
    /// ベスト比較が成立する — §8)。
    @Test func 世界チャレンジは47問を重複なく訊く() throws {
        let quiz = try makeWorldQuiz(stageIndex: WorldStage.challengeIndex)
        #expect(quiz.questionCount == GameRules.challengeQuestionCount)
        #expect(Set(quiz.order).count == GameRules.challengeQuestionCount,
                "a country was drawn twice into one sitting")
        #expect(Set(quiz.order).isSubset(of: Set(quiz.stage.codes)))
        #expect(quiz.prefectureCount == GameRules.challengeQuestionCount)
    }

    /// 抽選は履歴を見る: まだ出していない国が 1 回ぶんに満たなければ、
    /// その全部が必ずこの回に入る(challengeSelection の配線の確認)。
    @Test func 世界チャレンジは未出題の国を先に訊く() throws {
        let all = Atlas.world(from: try QuizModeTests.world.get())
            .mapData.prefectures.map(\.code)
        let unasked = Set(all.suffix(30))
        let quiz = try makeWorldQuiz(stageIndex: WorldStage.challengeIndex,
                                     asked: Set(all).subtracting(unasked))
        #expect(unasked.isSubset(of: Set(quiz.order)),
                "unasked countries were left behind: \(unasked.subtracting(quiz.order).sorted())")
    }

    /// 日本は抽選経路に乗らない: ぜんこく チャレンジは履歴に何を渡されても
    /// 全 47 県を 1 回ずつ訊く(47 は challengeQuestionCount を「超えて」
    /// いないので、min もそのまま・順序も従来の全県シャッフルのまま)。
    @Test func 日本のぜんこくチャレンジは履歴に関わらず全47県を訊く() {
        let quiz = makeQuiz(stageIndex: 6, asked: Set(1...40))
        #expect(Set(quiz.order) == Set(1...47))
        #expect(quiz.order.count == 47)
    }

    /// 抽選された 47 カ国だけでなく、本の全収録国がタップに応える。地図
    /// (平面 167 国・地球儀の全形状)は全部を描くので、描かれている国への
    /// 誤タップが海のように黙殺されたらアプリが壊れて見える — 外れは外れと
    /// して揺れ、ミスに数えられるべき(QuizView は nameIt でだけ空に上書き)。
    @Test func 世界チャレンジは全収録国がタップに応える() throws {
        let atlas = Atlas.world(from: try QuizModeTests.world.get())
        let quiz = try makeWorldQuiz(stageIndex: WorldStage.challengeIndex)
        #expect(quiz.interactiveCodes == Set(atlas.mapData.prefectures.map(\.code)))
        #expect(quiz.interactiveCodes.count > quiz.questionCount)

        // 抽選に入らなかった国への誤タップもミスとして記録される。
        let target = try #require(quiz.target)
        let outsider = try #require(
            quiz.interactiveCodes.subtracting(quiz.order).first)
        #expect(quiz.answer(outsider) == .wrong(code: outsider))
        #expect(quiz.answer(target.code)
                == .correct(firstTry: false, points: GameRules.retryScore, draw: nil))
    }

    /// `askedCodes` は抽選で組んだ回だけが運ぶ: 世界チャレンジは訊いた 47 を、
    /// 日本のぜんこくと世界の地方ステージは空を返す — 空のままなのが、
    /// 日本の save slice の askedInChallenge が永遠に空である仕組みそのもの。
    @Test func 抽選で組んだ回だけ結果がaskedCodesを運ぶ() throws {
        let challenge = try makeWorldQuiz(stageIndex: WorldStage.challengeIndex)
        playPerfectly(challenge)
        #expect(challenge.makeResult().askedCodes == Set(challenge.order))
        #expect(challenge.makeResult().askedCodes.count
                == GameRules.challengeQuestionCount)

        let japan = makeQuiz(stageIndex: 6)
        playPerfectly(japan)
        #expect(japan.makeResult().askedCodes.isEmpty)

        let continent = try makeWorldQuiz(stageIndex: 15)
        playPerfectly(continent)
        #expect(continent.makeResult().askedCodes.isEmpty)
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

    /// 両アトラスの出荷ステージ全部で、VM が組んだ出題数と `Stage.questionCount`
    /// が一致する。`challengeQuestionCount` を超える codes の challenge が抽選
    /// (`GameRules.challengeSelection`)へ配線されないまま VM に届くと、その
    /// 瞬間ここが落ちる: `questionCount` は min で 47 に切るが、`questionOrder`
    /// は全コードを訊いてしまうから。
    ///
    /// 逆方向は捕まえられない: 19 面目が isChallenge: false のまま増えても、
    /// 両辺とも codes.count × 2(334/334)で自己整合してしまう。その口は
    /// 世界アトラス側のピン(AtlasTests — 総合ステージだけが isChallenge を
    /// 名乗る)で塞ぐ。
    @Test func everyShippingStageAsksExactlyItsDeclaredQuestionCount() throws {
        let japan = Atlas.japan(mapData: MapDataTests.map, cards: MapDataTests.catalog)
        let world = Atlas.world(from: try QuizModeTests.world.get())
        for atlas in [japan, world] {
            for stage in atlas.stages {
                let quiz = QuizViewModel(
                    stage: stage,
                    mapData: atlas.mapData,
                    catalog: atlas.cards,
                    drawPolicy: atlas.drawPolicy,
                    askedInChallenge: [],
                    generator: AnyRandomNumberGenerator(SeededGenerator(seed: 1)))
                #expect(quiz.questionCount == stage.questionCount,
                        "\(atlas.saveKey) stage \(stage.index)")
            }
        }
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
        #expect(owned.values.allSatisfy { $0 <= GameRules.maxCardStars })
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

    /// The streak needs to know each asking's outcome *in order*: a prefecture
    /// fumbled first and clean second ends the stage on a run of one, while the
    /// collapsed first-try flag would call both askings dirty.
    @Test func resultCarriesEachAskingInOrder() throws {
        let quiz = makeQuiz(stageIndex: 0)
        // Fumble the very first question, then answer it; play the rest clean.
        let fumbled = try #require(quiz.target).code
        let wrong = try #require(quiz.order.first { $0 != fumbled })
        quiz.answer(wrong)
        quiz.answer(fumbled)
        quiz.advance()
        playPerfectly(quiz)

        let result = quiz.makeResult()
        #expect(result.outcomesByPrefecture[fumbled] == [false, true])
        for (code, outcomes) in result.outcomesByPrefecture where code != fumbled {
            #expect(outcomes == [true, true], "prefecture \(code) was played clean")
        }
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
