import Foundation
import Testing

@testable import ChizuHakase

/// 「なまえを あてる」: the same stages and scoring, asked the other way round.
@MainActor
struct QuizModeTests {

    private func makeQuiz(_ mode: QuizMode, stageIndex: Int = 0,
                          seed: UInt64 = 7) -> QuizViewModel {
        QuizViewModel(stage: Stage.all[stageIndex],
                      mode: mode,
                      mapData: MapDataTests.map,
                      catalog: MapDataTests.catalog,
                      generator: AnyRandomNumberGenerator(SeededGenerator(seed: seed)))
    }

    // MARK: - Choices

    @Test func theMapModeOffersNoChoices() {
        #expect(makeQuiz(.findOnMap).choices.isEmpty)
    }

    @Test func everyQuestionOffersFourNamesIncludingTheAnswer() throws {
        let quiz = makeQuiz(.nameIt)
        while quiz.phase != .finished {
            let target = try #require(quiz.target)
            #expect(quiz.choices.count == GameRules.nameChoiceCount)
            #expect(quiz.choices.contains(target.code),
                    "\(target.name) was not among its own choices")
            #expect(Set(quiz.choices).count == quiz.choices.count, "a name is repeated")
            quiz.answer(target.code)
            quiz.advance()
        }
    }

    /// Decoys from the whole country would be free marks — the shape on screen
    /// already rules out anything from another region.
    @Test func decoysComeFromTheSameStage() {
        let quiz = makeQuiz(.nameIt, stageIndex: 1)
        #expect(Set(quiz.choices).isSubset(of: Set(Stage.all[1].codes)))
    }

    /// A stage smaller than the choice count must still be playable rather than
    /// crashing or padding with prefectures that are not in it.
    @Test func aTinyPoolOffersWhatItHas() {
        var rng = AnyRandomNumberGenerator(SeededGenerator(seed: 1))
        let choices = GameRules.nameChoices(answer: 3, from: [3, 4], using: &rng)
        #expect(Set(choices) == [3, 4])
    }

    @Test func theChoicesDoNotReshuffleWithinAQuestion() {
        let quiz = makeQuiz(.nameIt)
        let first = quiz.choices
        _ = quiz.choices
        #expect(quiz.choices == first)
    }

    @Test func choicesAreDealtAfreshOnTheNextQuestion() throws {
        let quiz = makeQuiz(.nameIt)
        let target = try #require(quiz.target)
        let before = quiz.choices
        quiz.answer(target.code)
        quiz.advance()
        #expect(quiz.choices != before || quiz.phase == .finished)
    }

    // MARK: - Ruling out

    @Test func awrongNameIsRuledOutAndTheRestStay() throws {
        let quiz = makeQuiz(.nameIt)
        let target = try #require(quiz.target)
        let wrong = try #require(quiz.choices.first { $0 != target.code })

        #expect(quiz.ruledOut.isEmpty)
        quiz.answer(wrong)
        #expect(quiz.ruledOut == [wrong])
        #expect(quiz.choices.count == GameRules.nameChoiceCount,
                "a wrong name was removed instead of dimmed")
    }

    @Test func ruledOutClearsForTheNextQuestion() throws {
        let quiz = makeQuiz(.nameIt)
        let target = try #require(quiz.target)
        quiz.answer(try #require(quiz.choices.first { $0 != target.code }))
        quiz.answer(target.code)
        quiz.advance()
        #expect(quiz.ruledOut.isEmpty)
    }

    // MARK: - Shared rules

    /// Both modes are the same game. Scoring, combo and mastery are §5's, and
    /// splitting them by mode would mean two ledgers for one child.
    @Test func scoringIsIdenticalInBothModes() throws {
        for mode in QuizMode.allCases {
            let quiz = makeQuiz(mode)
            let target = try #require(quiz.target)
            quiz.answer(target.code)
            #expect(quiz.score == GameRules.firstTryBaseScore, "\(mode) scored differently")
            #expect(quiz.combo == 1)
        }
    }

    @Test func theResultCarriesTheModeItWasPlayedIn() {
        for mode in QuizMode.allCases {
            let quiz = makeQuiz(mode)
            while quiz.phase != .finished {
                guard let target = quiz.target else { break }
                quiz.answer(target.code)
                quiz.advance()
            }
            #expect(quiz.makeResult().mode == mode)
        }
    }
}
