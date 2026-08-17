import Foundation
import Testing

@testable import ChizuHakase

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
        #expect(GameRules.stars(missedPrefectures: 0, prefectureCount: 7) == 3)
        #expect(GameRules.stars(missedPrefectures: 0, prefectureCount: 47) == 3)
    }

    /// Two-star band is ceil(prefectures / 4). Counted in prefectures on both
    /// sides — the numbers below are stage sizes, not question counts, and a
    /// regional stage asks each of its prefectures twice.
    @Test(arguments: [
        (7, 2, 2), (7, 1, 2), (7, 3, 1),      // ceil(7/4) = 2
        (47, 12, 2), (47, 13, 1),             // ceil(47/4) = 12
        (8, 2, 2), (8, 3, 1),                 // ceil(8/4) = 2
        (9, 3, 2), (9, 4, 1),                 // ceil(9/4) = 3
    ])
    func starBands(prefectures: Int, missed: Int, expected: Int) {
        #expect(GameRules.stars(missedPrefectures: missed,
                                prefectureCount: prefectures) == expected,
                "\(missed) missed of \(prefectures) should be \(expected) stars")
    }

    /// The band a real regional stage lands on, pinned because it is the one
    /// the naming got wrong: 「ほっかいどう・とうほく」 is seven prefectures asked
    /// fourteen times, and the allowance follows the seven.
    @Test func aRegionalStageIsBandedOnItsPrefecturesNotItsQuestions() {
        let stage = Stage.all[0]
        #expect(stage.questionCount == 14)
        #expect(GameRules.stars(missedPrefectures: 3,
                                prefectureCount: stage.codes.count) == 1,
                "three of seven prefectures missed is a one-star run, not two")
    }

    @Test func emptyStageDoesNotDivideByZero() {
        #expect(GameRules.stars(missedPrefectures: 0, prefectureCount: 0) == 3)
    }

    // MARK: - Mastery

    @Test func masteryRisesOnlyOnFirstTryCorrect() {
        #expect(GameRules.nextMastery(current: 0, firstTry: true) == 1)
        #expect(GameRules.nextMastery(current: 2, firstTry: true) == 3)
    }

    /// キラキラ takes five clean answers — 「おぼえた」 has to mean something,
    /// and one lucky tap is not it (CLAUDE.md §5).
    @Test func masteryTopsOutAtFiveCleanAnswers() {
        #expect(GameRules.maxMastery == 5)
        #expect(GameRules.nextMastery(current: GameRules.maxMastery, firstTry: true)
                == GameRules.maxMastery)
        #expect(GameRules.nextMastery(current: 99, firstTry: true) == GameRules.maxMastery)
    }

    /// The explicit product decision in CLAUDE.md §5: getting it wrong never
    /// takes progress away.
    @Test func masteryNeverDecreases() {
        for level in 0...GameRules.maxMastery {
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

    /// Five stars is silver, ten is gold, and the tier only counts as a
    /// promotion on the draw that crossed into it.
    @Test func tiersFollowTheStarCount() {
        #expect(CardTier(stars: 0) == .none)
        #expect(CardTier(stars: 1) == .plain)
        #expect(CardTier(stars: 4) == .plain)
        #expect(CardTier(stars: 5) == .silver)
        #expect(CardTier(stars: 9) == .silver)
        #expect(CardTier(stars: 10) == .gold)
        #expect(CardTier(stars: 99) == .gold)

        let card = Self.sample[0]
        #expect(GameRules.CardDraw.star(card, stars: 5).promoted)
        #expect(GameRules.CardDraw.star(card, stars: 10).promoted)
        #expect(!GameRules.CardDraw.star(card, stars: 4).promoted)
        #expect(!GameRules.CardDraw.star(card, stars: 6).promoted)
        #expect(!GameRules.CardDraw.star(card, stars: 9).promoted)
        #expect(!GameRules.CardDraw.new(card).promoted)
    }

    /// Rainbow is never a star count. It is a fact recorded about the card —
    /// gold, held while the prefecture's streak stood at fifteen — and once
    /// recorded it does not wash off.
    @Test func rainbowSitsAboveGoldAndNeedsTheFlag() {
        #expect(CardTier(stars: 10, rainbow: true) == .rainbow)
        #expect(CardTier(stars: 10, rainbow: false) == .gold)
        #expect(CardTier.rainbow > .gold)
        #expect(CardTier.rainbow.isSpecial)
        // A card the child does not hold cannot be shown as anything.
        #expect(CardTier(stars: 0, rainbow: true) == .none)
    }

    // MARK: - Prefecture streak

    @Test func aCleanPassExtendsTheStreak() {
        #expect(GameRules.nextStreak(current: 3, outcomes: [true, true]).streak == 5)
        #expect(GameRules.nextStreak(current: 0, outcomes: [true]).streak == 1)
    }

    /// A fumble resets the count, but only the count: what comes after the
    /// fumble starts a fresh run within the same stage.
    @Test func aFumbleResetsTheStreakToWhatFollowedIt() {
        #expect(GameRules.nextStreak(current: 9, outcomes: [false, true]).streak == 1)
        #expect(GameRules.nextStreak(current: 9, outcomes: [true, false]).streak == 0)
        #expect(GameRules.nextStreak(current: 9, outcomes: []).streak == 9)
    }

    // MARK: - Rainbow

    /// The run toward rainbow opens only after the gold exists: the draw that
    /// finishes a card's stars resets the count, so the answer that completed
    /// the gold is not also the first step past it, and nothing built before
    /// it carries over.
    @Test func finishingAGoldSpendsTheRun() {
        let walked = GameRules.nextStreak(
            current: 9, outcomes: [true, true],
            draws: [.star(Self.sample[0], stars: GameRules.maxCardStars)],
            goldCardIDs: [])
        #expect(walked.streak == 1, "only the answer after the promotion counts")
        #expect(walked.latched.isEmpty, "a streak built before gold must not latch")
    }

    @Test func aCleanRunAfterGoldLatchesAtTheLine() {
        let gold: Set = [Self.sample[0].id]
        let below = GameRules.nextStreak(
            current: GameRules.rainbowStreak - 2, outcomes: [true],
            draws: [.star(Self.sample[1], stars: 2)], goldCardIDs: gold)
        #expect(below.latched.isEmpty)

        let crossing = GameRules.nextStreak(
            current: GameRules.rainbowStreak - 1, outcomes: [true],
            draws: [.star(Self.sample[1], stars: 2)], goldCardIDs: gold)
        #expect(crossing.latched == gold)
    }

    /// Latched mid-walk, not on the final count: the crossing on a stage's
    /// first asking stands even when the second asking fumbles.
    @Test func aFumbleAfterTheCrossingDoesNotSwallowTheRainbow() {
        let gold: Set = [Self.sample[0].id]
        let walked = GameRules.nextStreak(
            current: GameRules.rainbowStreak - 1, outcomes: [true, false],
            draws: [.star(Self.sample[1], stars: 2)], goldCardIDs: gold)
        #expect(walked.streak == 0)
        #expect(walked.latched == gold)
    }

    /// A card that finishes its gold after the count crossed does not ride
    /// the same run — its promotion resets the count, so its seven start
    /// from there.
    @Test func aLateGoldStartsItsOwnRun() {
        let walked = GameRules.nextStreak(
            current: GameRules.rainbowStreak - 1, outcomes: [true, true],
            draws: [.star(Self.sample[1], stars: 2),
                    .star(Self.sample[2], stars: GameRules.maxCardStars)],
            goldCardIDs: [Self.sample[0].id])
        #expect(walked.latched == [Self.sample[0].id])
        #expect(walked.streak == 0, "the late promotion spends the count again")
    }

    /// Saves written while the threshold was fifteen can arrive already past
    /// the new line; they latch the moment the prefecture is next walked,
    /// before any answer this stage gives.
    @Test func anAlreadyQualifiedStreakLatchesOnArrival() {
        let gold: Set = [Self.sample[0].id]
        let walked = GameRules.nextStreak(
            current: 12, outcomes: [false], draws: [], goldCardIDs: gold)
        #expect(walked.latched == gold)
        #expect(walked.streak == 0)
    }

    // MARK: - Next goal

    /// The 「あと◯」 line: wins to silver, wins to gold, then streak to
    /// rainbow, then nothing left to ask for. Unowned cards say nothing —
    /// the first draw is the goal, and the slot already shows that.
    @Test func nextGoalWalksTheLadder() {
        #expect(GameRules.nextGoal(stars: 0, streak: 0, isRainbow: false) == nil)
        #expect(GameRules.nextGoal(stars: 1, streak: 0, isRainbow: false) == .wins(4, to: .silver))
        #expect(GameRules.nextGoal(stars: 4, streak: 0, isRainbow: false) == .wins(1, to: .silver))
        #expect(GameRules.nextGoal(stars: 5, streak: 0, isRainbow: false) == .wins(5, to: .gold))
        #expect(GameRules.nextGoal(stars: 9, streak: 0, isRainbow: false) == .wins(1, to: .gold))
        #expect(GameRules.nextGoal(stars: 10, streak: 0, isRainbow: false) == .streak(5))
        #expect(GameRules.nextGoal(stars: 10, streak: 3, isRainbow: false) == .streak(2))
        #expect(GameRules.nextGoal(stars: 10, streak: 40, isRainbow: false) == .streak(1),
                "a still-gold card never shows 「あと0」 — the latch just has not caught yet")
        #expect(GameRules.nextGoal(stars: 10, streak: 0, isRainbow: true) == .done)
    }

    /// The little bar under the 「あと◯」 line: how far along the *current rung*
    /// is, derived from the same goal as the label so the two cannot disagree.
    /// Each rung starts empty — progress toward silver does not carry into the
    /// gold rung, or the bar would spend the whole game nearly full.
    @Test func theGoalBarFillsTheCurrentRung() {
        func fraction(stars: Int, streak: Int = 0, rainbow: Bool = false) -> Double? {
            GameRules.nextGoal(stars: stars, streak: streak, isRainbow: rainbow)?.fraction
        }
        #expect(fraction(stars: 0) == nil)
        #expect(fraction(stars: 1) == 0.2)
        #expect(fraction(stars: 4) == 0.8)
        #expect(fraction(stars: 5) == 0, "a fresh rung starts empty")
        #expect(fraction(stars: 9) == 0.8)
        #expect(fraction(stars: 10) == 0)
        #expect(fraction(stars: 10, streak: 3) == 3.0 / 5.0)
        #expect(fraction(stars: 10, streak: 40) == 4.0 / 5.0,
                "the bar never reads full while the latch has not caught")
        #expect(fraction(stars: 10, rainbow: true) == 1)
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
                "every card should have reached the star cap")
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
