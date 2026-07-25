import Foundation
import Testing

@testable import WakuwakuChizu

/// CLAUDE.md §5. These are the rules a child experiences as fairness, so they
/// are pinned exactly.
struct GameRulesTests {

    // MARK: - Stage availability

    /// Nothing in the app is withheld until an adult intervenes. Pinned as a
    /// test because a gate is easy to reintroduce and impossible for a child to
    /// work around: `Stage` carries no availability flag, and the picker has no
    /// locked branch to fall into.
    @Test func everyStageIsPlayableOnAFreshInstall() {
        #expect(Stage.all.count == 7)
        for stage in Stage.all {
            #expect(Stage.stage(at: stage.index) == stage,
                    "\(stage.name) is not reachable by index")
            #expect(!stage.codes.isEmpty)
        }
    }

    @Test func stagesCoverAllFortySevenPrefectures() {
        let regional = Stage.all.dropLast().flatMap(\.codes)
        #expect(Set(regional) == Set(1...47))
        #expect(regional.count == 47, "a prefecture appears in two regional stages")
    }

    // MARK: - Score

    @Test func firstTryScoreStartsAt100() {
        #expect(GameRules.score(firstTry: true, combo: 1) == 100)
    }

    @Test(arguments: [(1, 100), (2, 120), (3, 140), (5, 180), (10, 280)])
    func comboAddsTwentyEach(combo: Int, expected: Int) {
        #expect(GameRules.score(firstTry: true, combo: combo) == expected)
    }

    @Test func retryScoreIsFlatFiftyRegardlessOfCombo() {
        #expect(GameRules.score(firstTry: false, combo: 1) == 50)
        #expect(GameRules.score(firstTry: false, combo: 9) == 50)
    }

    // MARK: - Combo

    @Test func comboOnlyGrowsOnUnaidedCorrectAnswers() {
        #expect(GameRules.nextCombo(current: 3, correct: true, firstTry: true) == 4)
        // Correct, but only after a miss: the streak holds, it does not grow.
        #expect(GameRules.nextCombo(current: 3, correct: true, firstTry: false) == 3)
        #expect(GameRules.nextCombo(current: 3, correct: false, firstTry: false) == 0)
    }

    // MARK: - Stars

    @Test func perfectRunEarnsThreeStars() {
        #expect(GameRules.stars(missedPrefectures: 0, questionCount: 7) == 3)
        #expect(GameRules.stars(missedPrefectures: 0, questionCount: 47) == 3)
    }

    /// Two-star band is ceil(questions / 4).
    @Test(arguments: [
        (7, 2, 2), (7, 1, 2), (7, 3, 1),      // ceil(7/4) = 2
        (47, 12, 2), (47, 13, 1),             // ceil(47/4) = 12
        (8, 2, 2), (8, 3, 1),                 // ceil(8/4) = 2
        (9, 3, 2), (9, 4, 1),                 // ceil(9/4) = 3
    ])
    func starBands(questions: Int, missed: Int, expected: Int) {
        #expect(GameRules.stars(missedPrefectures: missed, questionCount: questions) == expected,
                "\(missed) missed of \(questions) should be \(expected) stars")
    }

    @Test func emptyStageDoesNotDivideByZero() {
        #expect(GameRules.stars(missedPrefectures: 0, questionCount: 0) == 3)
    }

    // MARK: - Mastery

    @Test func masteryRisesOnlyOnFirstTryCorrect() {
        #expect(GameRules.nextMastery(current: 0, firstTry: true) == 1)
        #expect(GameRules.nextMastery(current: 2, firstTry: true) == 3)
    }

    @Test func masteryCapsAtThree() {
        #expect(GameRules.nextMastery(current: 3, firstTry: true) == 3)
        #expect(GameRules.nextMastery(current: 99, firstTry: true) == 3)
    }

    /// The explicit product decision in CLAUDE.md §5: getting it wrong never
    /// takes progress away.
    @Test func masteryNeverDecreases() {
        for level in 0...3 {
            #expect(GameRules.nextMastery(current: level, firstTry: false) == level)
            #expect(GameRules.nextMastery(current: level, firstTry: true) >= level)
        }
    }

    // MARK: - Card draw

    private static let sample = (1...3).map {
        SpecialtyCard(id: "01-\($0)", prefectureCode: 1, emoji: "🦀",
                      nameKana: "かに", nameKanji: "蟹", category: .food,
                      description: "つめたい うみ")
    }

    @Test func unownedCardsAreDrawnFirst() {
        var rng = SeededGenerator(seed: 42)
        let owned = ["01-1": 1, "01-2": 1]
        let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
        #expect(draw == .new(Self.sample[2]), "should have drawn the only unowned card")
    }

    @Test func fullSetPromotesToShiny() {
        var rng = SeededGenerator(seed: 7)
        let owned = ["01-1": 1, "01-2": 1, "01-3": 1]
        let draw = try? #require(GameRules.drawCard(from: Self.sample, owned: owned, using: &rng))
        if case .shiny = draw {} else {
            Issue.record("expected a shiny promotion, got \(String(describing: draw))")
        }
    }

    @Test func alreadyShinyReportsDuplicate() {
        var rng = SeededGenerator(seed: 7)
        let owned = ["01-1": 2, "01-2": 2, "01-3": 2]
        let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
        if case .duplicate = draw {} else {
            Issue.record("expected a duplicate, got \(String(describing: draw))")
        }
    }

    @Test func drawingFromNoCardsIsNilNotACrash() {
        var rng = SeededGenerator(seed: 1)
        #expect(GameRules.drawCard(from: [], owned: [:], using: &rng) == nil)
    }

    @Test func repeatedDrawsEventuallyCompleteTheSet() {
        var rng = SeededGenerator(seed: 99)
        var owned: [String: Int] = [:]
        for _ in 0..<40 {
            guard let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
            else { break }
            owned = GameRules.applyDraw(draw, to: owned)
        }
        #expect(owned.count == 3, "every card should be owned after enough draws")
        #expect(owned.values.allSatisfy { $0 == GameRules.maxCardCopies },
                "every card should have reached the shiny cap")
    }

    @Test func ownedCountNeverExceedsTheCap() {
        var rng = SeededGenerator(seed: 3)
        var owned: [String: Int] = [:]
        for _ in 0..<100 {
            guard let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
            else { break }
            owned = GameRules.applyDraw(draw, to: owned)
            #expect(owned.values.allSatisfy { $0 <= GameRules.maxCardCopies })
        }
    }

    // MARK: - Records

    @Test func bestRecordKeepsTheHighestOfEachField() {
        let existing = StageRecord(stars: 3, score: 400)
        let worse = StageRecord(stars: 1, score: 900)
        let merged = GameRules.bestRecord(existing: existing, new: worse)
        // Stars and score are tracked independently so a sloppy high-scoring
        // replay cannot erase an earned 3-star.
        #expect(merged == StageRecord(stars: 3, score: 900))
    }

    @Test func firstRecordIsTakenAsIs() {
        let new = StageRecord(stars: 2, score: 120)
        #expect(GameRules.bestRecord(existing: nil, new: new) == new)
    }
}

/// Deterministic RNG so card-draw tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
