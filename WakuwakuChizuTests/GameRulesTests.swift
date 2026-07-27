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

    // MARK: - Streak call-out

    /// Nothing is said for a streak of one: every correct answer would carry a
    /// badge and the badge would stop meaning anything.
    @Test func aSingleCorrectAnswerIsNotAStreak() {
        #expect(GameRules.comboTier(0) == 0)
        #expect(GameRules.comboTier(1) == 0)
        #expect(GameRules.comboTier(2) > 0)
    }

    /// The whole point is that the fourth in a row feels different from the
    /// second, so the tier has to actually climb.
    @Test func theCallOutGetsLouderAsTheRunGrows() {
        let tiers = (2...12).map(GameRules.comboTier)
        #expect(tiers == tiers.sorted(), "tiers go down somewhere: \(tiers)")
        #expect(Set(tiers).count >= 3, "the celebration never changes")
        #expect(GameRules.comboTier(2) < GameRules.comboTier(5))
        #expect(GameRules.comboTier(5) < GameRules.comboTier(9))
    }

    /// It has to stop climbing, or a long run would ask for a font size the
    /// screen does not have.
    @Test func theCallOutStopsAtTheTop() {
        #expect(GameRules.comboTier(9) == GameRules.comboTier(47))
        #expect(GameRules.comboTier(47) == 3)
    }

    // MARK: - Earning a card

    /// Only a clean answer earns one. A card marks having known it outright.
    @Test func onlyAnUnfumbledAnswerEarnsACard() {
        #expect(GameRules.earnsCard(afterMisses: 0))
        #expect(!GameRules.earnsCard(afterMisses: 1))
        #expect(!GameRules.earnsCard(afterMisses: GameRules.missesBeforeHint))
        #expect(!GameRules.earnsCard(afterMisses: 9))
    }

    // MARK: - Question order

    @Test func oneRepeatIsJustAShuffle() {
        var rng = AnyRandomNumberGenerator(SeededGenerator(seed: 3))
        let order = GameRules.questionOrder(codes: [1, 2, 3], repeats: 1, using: &rng)
        #expect(Set(order) == [1, 2, 3])
        #expect(order.count == 3)
    }

    @Test func twoRepeatsAskEverythingTwice() {
        var rng = AnyRandomNumberGenerator(SeededGenerator(seed: 4))
        let order = GameRules.questionOrder(codes: Array(1...7), repeats: 2, using: &rng)
        #expect(order.count == 14)
        for code in 1...7 {
            #expect(order.filter { $0 == code }.count == 2)
        }
    }

    /// The seam between the two passes is the only place a repeat can land back
    /// to back, so it is the only place worth checking hard.
    @Test func noPrefectureIsAskedTwiceInARow() {
        for seed in UInt64(1)...50 {
            var rng = AnyRandomNumberGenerator(SeededGenerator(seed: seed))
            let order = GameRules.questionOrder(codes: Array(1...7), repeats: 2, using: &rng)
            for (a, b) in zip(order, order.dropFirst()) {
                #expect(a != b, "seed \(seed): \(a) repeats immediately")
            }
        }
    }

    /// A single prefecture has nowhere else to go, so it does repeat back to
    /// back — but it must still be asked twice rather than dropped.
    @Test func aSinglePrefectureIsStillAskedTwice() {
        var rng = AnyRandomNumberGenerator(SeededGenerator(seed: 5))
        let order = GameRules.questionOrder(codes: [9], repeats: 2, using: &rng)
        #expect(order == [9, 9])
    }

    /// The card is the only thing withheld. Points and the mastery credit are
    /// untouched, so nothing a child already has is taken back (CLAUDE.md §12).
    @Test func theHintDoesNotCostPointsOrMastery() {
        #expect(GameRules.score(firstTry: false, combo: 1) == 50)
        #expect(GameRules.nextMastery(current: 2, firstTry: false) == 2)
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

    @Test func aCompleteSetStartsAddingStars() {
        var rng = SeededGenerator(seed: 7)
        let owned = ["01-1": 1, "01-2": 1, "01-3": 1]
        let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
        guard case .star(_, let stars) = draw else {
            Issue.record("expected a star, got \(String(describing: draw))")
            return
        }
        #expect(stars == 2)
    }

    /// Wins go to a card that can still use one. Drawing across all of them
    /// would spend a correct answer on a card already at five while another sat
    /// at one, which is a complete answer earning less than the last one did.
    @Test func starsGoToACardThatCanStillTakeOne() {
        var rng = SeededGenerator(seed: 11)
        let owned = ["01-1": GameRules.maxCardStars, "01-2": GameRules.maxCardStars,
                     "01-3": 2]
        for _ in 0..<20 {
            let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
            #expect(draw?.card.id == "01-3", "a full card was drawn while one was unfinished")
        }
    }

    @Test func aFullSetOfGoldCardsReportsDuplicate() {
        var rng = SeededGenerator(seed: 7)
        let owned = Dictionary(uniqueKeysWithValues:
            Self.sample.map { ($0.id, GameRules.maxCardStars) })
        let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
        if case .duplicate = draw {} else {
            Issue.record("expected a duplicate, got \(String(describing: draw))")
        }
    }

    /// Three stars is silver, five is gold, and the tier only counts as a
    /// promotion on the draw that crossed into it.
    @Test func tiersFollowTheStarCount() {
        #expect(CardTier(stars: 0) == .none)
        #expect(CardTier(stars: 1) == .plain)
        #expect(CardTier(stars: 2) == .plain)
        #expect(CardTier(stars: 3) == .silver)
        #expect(CardTier(stars: 4) == .silver)
        #expect(CardTier(stars: 5) == .gold)
        #expect(CardTier(stars: 99) == .gold)

        let card = Self.sample[0]
        #expect(GameRules.CardDraw.star(card, stars: 3).promoted)
        #expect(GameRules.CardDraw.star(card, stars: 5).promoted)
        #expect(!GameRules.CardDraw.star(card, stars: 4).promoted)
        #expect(!GameRules.CardDraw.star(card, stars: 2).promoted)
        #expect(!GameRules.CardDraw.new(card).promoted)
    }

    /// Applying the same draw twice is what happens when a stage result is
    /// replayed onto the save, and it must not add a star each time.
    @Test func applyingADrawTwiceCountsItOnce() {
        let card = Self.sample[0]
        var owned = GameRules.applyDraw(.star(card, stars: 3), to: ["01-1": 2])
        owned = GameRules.applyDraw(.star(card, stars: 3), to: owned)
        #expect(owned["01-1"] == 3)
    }

    @Test func drawingFromNoCardsIsNilNotACrash() {
        var rng = SeededGenerator(seed: 1)
        #expect(GameRules.drawCard(from: [], owned: [:], using: &rng) == nil)
    }

    @Test func repeatedDrawsEventuallyCompleteTheSet() {
        var rng = SeededGenerator(seed: 99)
        var owned: [String: Int] = [:]
        for _ in 0..<80 {
            guard let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
            else { break }
            owned = GameRules.applyDraw(draw, to: owned)
        }
        #expect(owned.count == 3, "every card should be owned after enough draws")
        #expect(owned.values.allSatisfy { $0 == GameRules.maxCardStars },
                "every card should have reached five stars")
    }

    @Test func starsNeverExceedTheCap() {
        var rng = SeededGenerator(seed: 3)
        var owned: [String: Int] = [:]
        for _ in 0..<100 {
            guard let draw = GameRules.drawCard(from: Self.sample, owned: owned, using: &rng)
            else { break }
            owned = GameRules.applyDraw(draw, to: owned)
            #expect(owned.values.allSatisfy { $0 <= GameRules.maxCardStars })
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
