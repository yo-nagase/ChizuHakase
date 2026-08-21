import CoreGraphics
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

    // MARK: - Challenge stage

    /// The P7 redefinition (stored `isChallenge` instead of `codes.count == 47`)
    /// must not move japan an inch: stage 6 is the one challenge, still 47
    /// single-pass questions, and stages 0–5 still ask each prefecture twice.
    @Test func japansChallengeFlagAndLengthsAreUnchanged() {
        for stage in Stage.all {
            #expect(stage.isChallenge == (stage.index == 6), "stage \(stage.index)")
        }
        let challenge = Stage.all[6]
        #expect(!challenge.asksEachTwice)
        #expect(challenge.questionCount == 47)
        for stage in Stage.all where !stage.isChallenge {
            #expect(stage.asksEachTwice, "stage \(stage.index)")
            #expect(stage.questionCount == stage.codes.count * 2,
                    "stage \(stage.index)")
        }
    }

    /// The cap in both directions, on synthetic stages: a challenge over more
    /// codes than one sitting is cut to `challengeQuestionCount`, and one with
    /// fewer asks each code once. The world's 167-country challenge (a later
    /// task) is built on exactly this min.
    @Test func aChallengeSessionIsCappedAtTheChallengeQuestionCount() {
        #expect(GameRules.challengeQuestionCount == 47)
        let world = Stage(index: 99, name: "せかい", kanjiName: "世界",
                          codes: Array(1...167), isChallenge: true)
        #expect(!world.asksEachTwice)
        #expect(world.questionCount == GameRules.challengeQuestionCount)
        let small = Stage(index: 98, name: "ちいさい", kanjiName: "小さい",
                          codes: Array(1...10), isChallenge: true)
        #expect(!small.asksEachTwice)
        #expect(small.questionCount == 10)
    }

    // MARK: - Challenge draw (世界チャレンジの未出題優先 — 設計 §8)

    private func seededRNG(_ seed: UInt64 = 1) -> AnyRandomNumberGenerator {
        AnyRandomNumberGenerator(SeededGenerator(seed: seed))
    }

    /// 網羅を先に、ランダムはその中で: 未出題が 1 回ぶんに足りるあいだは
    /// 出題済みが 1 国も混ざらない。
    @Test func 未出題が足りるなら出題済みは選ばれない() {
        var rng = seededRNG()
        let asked = Set(1...100)
        let picked = GameRules.challengeSelection(
            codes: Array(1...167), asked: asked, count: 47, using: &rng)
        #expect(picked.count == 47)
        #expect(Set(picked).count == 47, "a code was drawn twice")
        #expect(Set(picked).isDisjoint(with: asked),
                "an already-asked code slipped into a full unasked pool")
    }

    /// 残りが 1 回ぶんに満たなくなったら、その残り全部が必ず入る —
    /// 一巡の最後の国が抽選運に取り残されない。不足分だけ出題済みで埋める。
    @Test func 未出題が足りないときは全未出題が必ず入る() {
        var rng = seededRNG()
        let asked = Set(1...140)
        let unasked = Set(141...167)
        let picked = GameRules.challengeSelection(
            codes: Array(1...167), asked: asked, count: 47, using: &rng)
        #expect(picked.count == 47)
        #expect(Set(picked).count == 47)
        #expect(unasked.isSubset(of: Set(picked)),
                "an unasked country was left behind: \(unasked.subtracting(picked).sorted())")
        #expect(Set(picked).subtracting(unasked).isSubset(of: asked))
    }

    /// 収録数が 1 回ぶんに満たない本では全収録を 1 回ずつ — min の側の釘。
    @Test func 収録がcountに満たなければ全部を1回ずつ() {
        var rng = seededRNG()
        let picked = GameRules.challengeSelection(
            codes: Array(1...10), asked: [3, 4], count: 47, using: &rng)
        #expect(Set(picked) == Set(1...10))
        #expect(picked.count == 10)
    }

    /// もう本に居ない国の履歴(将来の収録変更・手で触られたセーブ)は
    /// 静かに無視される — 歩くのは codes の上だけ。
    @Test func 本に無いコードの履歴は無視される() {
        var rng = seededRNG()
        let picked = GameRules.challengeSelection(
            codes: Array(1...5), asked: [3, 99, 100], count: 5, using: &rng)
        #expect(Set(picked) == Set(1...5))
    }

    /// シードが同じなら選抜も並びも同じ — テストと再現の土台。
    /// 継ぎ目消しの最終シャッフルもここで釘打つ: 未出題 27 + 補充 20 の回で、
    /// 先頭 27 が未出題そのものなら「未出題→補充」の境目が並びに残っている
    /// (両プールが個別にシャッフル済みでも起きる壊れ方なので、
    /// 「昇順のままでない」程度の釘では捕まらない)。
    @Test func 抽選はシードに対して決定的() {
        var a = seededRNG(42)
        var b = seededRNG(42)
        let first = GameRules.challengeSelection(
            codes: Array(1...167), asked: Set(1...140), count: 47, using: &a)
        let second = GameRules.challengeSelection(
            codes: Array(1...167), asked: Set(1...140), count: 47, using: &b)
        #expect(first == second)
        #expect(first != first.sorted(), "the sitting is not shuffled")
        #expect(Set(first.prefix(27)) != Set(141...167),
                "the pool seam survived into the asking order")
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
        let draw = GameRules.drawCard(from: Self.sample, owned: owned, policy: .random,
                                      using: &rng)
        #expect(draw == .new(Self.sample[2]), "should have drawn the only unowned card")
    }

    @Test func aCompleteSetStartsAddingStars() {
        var rng = SeededGenerator(seed: 7)
        let owned = ["01-1": 1, "01-2": 1, "01-3": 1]
        let draw = GameRules.drawCard(from: Self.sample, owned: owned, policy: .random,
                                      using: &rng)
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
            let draw = GameRules.drawCard(from: Self.sample, owned: owned,
                                          policy: .random, using: &rng)
            #expect(draw?.card.id == "01-3", "a full card was drawn while one was unfinished")
        }
    }

    @Test func aFullSetOfGoldCardsReportsDuplicate() {
        var rng = SeededGenerator(seed: 7)
        let owned = Dictionary(uniqueKeysWithValues:
            Self.sample.map { ($0.id, GameRules.maxCardStars) })
        let draw = GameRules.drawCard(from: Self.sample, owned: owned, policy: .random,
                                      using: &rng)
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
        #expect(GameRules.drawCard(from: [], owned: [:], policy: .random, using: &rng) == nil)
    }

    @Test func repeatedDrawsEventuallyCompleteTheSet() {
        var rng = SeededGenerator(seed: 99)
        var owned: [String: Int] = [:]
        for _ in 0..<80 {
            guard let draw = GameRules.drawCard(from: Self.sample, owned: owned,
                                                policy: .random, using: &rng)
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
            guard let draw = GameRules.drawCard(from: Self.sample, owned: owned,
                                                policy: .random, using: &rng)
            else { break }
            owned = GameRules.applyDraw(draw, to: owned)
            #expect(owned.values.allSatisfy { $0 <= GameRules.maxCardStars })
        }
    }

    // MARK: - 世界版の抽選(国旗先行・シルバー解放、設計 §5)

    /// 世界版の 1 国ぶん: 2 枚で、目録は国旗を先頭に置く。
    /// この並びが WorldCards.json の契約(Task 8)— ゲートは id を解析しない。
    private static let worldPair = [
        SpecialtyCard(id: "392-1", prefectureCode: 392, emoji: "🇯🇵",
                      nameKana: "にほんの こっき", nameKanji: "日本の国旗",
                      category: .landmark, description: "ひのまる"),
        SpecialtyCard(id: "392-2", prefectureCode: 392, emoji: "🗻",
                      nameKana: "ふじさん", nameKanji: "富士山",
                      category: .nature, description: "たかい やま"),
    ]

    /// 最初の 1 枚は必ず国旗。乱数がどう転んでもオリジナルから始まらない。
    @Test func 世界版は未所持なら国旗から渡す() {
        for seed in UInt64(1)...20 {
            var rng = SeededGenerator(seed: seed)
            let draw = GameRules.drawCard(from: Self.worldPair, owned: [:],
                                          policy: .flagFirstSilverGate, using: &rng)
            #expect(draw == .new(Self.worldPair[0]), "seed \(seed)")
        }
    }

    /// 国旗がシルバー未満のあいだ、正解はすべて国旗の星になる。
    /// オリジナルは「未所持優先」の対象にすら入らない。
    @Test func 世界版は国旗がシルバー未満のあいだオリジナルを出さない() {
        for stars in 1..<GameRules.silverStars {
            for seed in UInt64(1)...10 {
                var rng = SeededGenerator(seed: seed)
                let draw = GameRules.drawCard(from: Self.worldPair,
                                              owned: ["392-1": stars],
                                              policy: .flagFirstSilverGate, using: &rng)
                #expect(draw == .star(Self.worldPair[0], stars: stars + 1),
                        "国旗★\(stars) seed \(seed)")
            }
        }
    }

    /// 国旗が ★5 に触れた次の正解でオリジナル ★1(解放後は未所持優先が働く)。
    @Test func 世界版は国旗がシルバーに触れた次の正解でオリジナルが渡る() {
        for seed in UInt64(1)...10 {
            var rng = SeededGenerator(seed: seed)
            let draw = GameRules.drawCard(from: Self.worldPair,
                                          owned: ["392-1": GameRules.silverStars],
                                          policy: .flagFirstSilverGate, using: &rng)
            #expect(draw == .new(Self.worldPair[1]), "seed \(seed)")
        }
    }

    /// 両方を持った後は日本版と同じ「★10 未満からランダム」。
    /// シードを散らして、抽選が両方の札に実際に散ることまで確かめる。
    @Test func 世界版は両方持てば星10未満からランダムに積む() {
        var drawnIDs: Set<String> = []
        for seed in UInt64(1)...40 {
            var rng = SeededGenerator(seed: seed)
            let draw = GameRules.drawCard(from: Self.worldPair,
                                          owned: ["392-1": 6, "392-2": 1],
                                          policy: .flagFirstSilverGate, using: &rng)
            guard case .star(let card, _) = draw else {
                Issue.record("seed \(seed): expected a star, got \(String(describing: draw))")
                continue
            }
            drawnIDs.insert(card.id)
        }
        #expect(drawnIDs == ["392-1", "392-2"], "抽選が片方に固定されている: \(drawnIDs)")
    }

    /// 金の国旗はもう星を取れないので、未完成のオリジナルに積まれる
    /// (日本版の「★10 未満から引く」がそのまま働くこと)。
    @Test func 世界版は金の国旗を避けて未完成のオリジナルに星を積む() {
        for seed in UInt64(1)...10 {
            var rng = SeededGenerator(seed: seed)
            let draw = GameRules.drawCard(
                from: Self.worldPair,
                owned: ["392-1": GameRules.maxCardStars, "392-2": 7],
                policy: .flagFirstSilverGate, using: &rng)
            #expect(draw == .star(Self.worldPair[1], stars: 8), "seed \(seed)")
        }
    }

    @Test func 世界版も全部金ならもっているカードだね() {
        var rng = SeededGenerator(seed: 7)
        let owned = Dictionary(uniqueKeysWithValues:
            Self.worldPair.map { ($0.id, GameRules.maxCardStars) })
        let draw = GameRules.drawCard(from: Self.worldPair, owned: owned,
                                      policy: .flagFirstSilverGate, using: &rng)
        if case .duplicate = draw {} else {
            Issue.record("expected a duplicate, got \(String(describing: draw))")
        }
    }

    /// 通し: 何十回引いても、国旗が銀になる前にオリジナルが出た瞬間は無く、
    /// 最後は両方が星の上限に届く(解放が完成を妨げない)。
    @Test func 世界版の繰り返し抽選は銀の解放を守って両方を完成させる() {
        var rng = SeededGenerator(seed: 21)
        var owned: [String: Int] = [:]
        for _ in 0..<60 {
            guard let draw = GameRules.drawCard(from: Self.worldPair, owned: owned,
                                                policy: .flagFirstSilverGate, using: &rng)
            else { break }
            if draw.card.id == "392-2" {
                #expect((owned["392-1"] ?? 0) >= GameRules.silverStars,
                        "国旗★\(owned["392-1"] ?? 0) でオリジナルが出た")
            }
            owned = GameRules.applyDraw(draw, to: owned)
        }
        #expect(owned["392-1"] == GameRules.maxCardStars)
        #expect(owned["392-2"] == GameRules.maxCardStars)
    }

    // 「方針の既定値は .random と同一」という回帰テストはここにあったが、
    // 既定引数そのものを外した(P6 Task 6・引き継ぎ 7)ので前提ごと消えた:
    // 全呼び出しが方針を明示し、渡し忘れはコンパイルエラーが捕まえる。

    /// Task 8 が頼る契約の錨: 目録は 1 国のカードを収載順のまま返す。
    /// 世界のゲートは「先頭 = 国旗」というこの並びに乗り、id は解析しない。
    /// 3 枚の日本の県と 2 枚の世界の国が同じ目録機構で共存できることも兼ねる。
    @Test func 目録は国のカードを収載順のまま返す() {
        let catalog = CardCatalog(cards: Self.worldPair + Self.sample)
        #expect(catalog.cards(for: 392) == Self.worldPair)
        #expect(catalog.cards(for: 1) == Self.sample)
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

    // MARK: - Challenge flat zoom (世界チャレンジの平面ズーム上限)

    /// 上限は「チャレンジ枠と各ステージ枠の比」の最大値。比は軸ごとにとり、
    /// 大きい方を採る — 細長いステージは細い軸の側でしか追いつけない。
    @Test func 平面ズーム上限は最大のステージ枠比を選ぶ() {
        let zoom = GameRules.challengeFlatZoom(
            challengeSpan: CGSize(width: 100, height: 80),
            stageSpans: [CGSize(width: 50, height: 40),   // max(2, 2)  = 2
                         CGSize(width: 10, height: 40),   // max(10, 2) = 10
                         CGSize(width: 100, height: 5)])  // max(1, 16) = 16
        #expect(abs(zoom - 16) < 0.001)
    }

    /// どのステージも既定の 4 で足りるなら広げない — 日本の全国チャレンジが
    /// この枝で、挙動が 1 ピクセルも変わらないことの根拠。
    @Test func 枠比が既定を下回るなら既定のまま() {
        let zoom = GameRules.challengeFlatZoom(
            challengeSpan: CGSize(width: 100, height: 80),
            stageSpans: [CGSize(width: 100, height: 80),
                         CGSize(width: 50, height: 40)])
        #expect(zoom == GameRules.mapMaxZoom)
    }

    /// 空・退化した枠は無限大や NaN ではなく既定へ倒れる。
    @Test func 退化した枠は上限を壊さない() {
        #expect(GameRules.challengeFlatZoom(challengeSpan: CGSize(width: 100, height: 80),
                                            stageSpans: []) == GameRules.mapMaxZoom)
        #expect(GameRules.challengeFlatZoom(
            challengeSpan: CGSize(width: 100, height: 80),
            stageSpans: [.zero, CGSize(width: 50, height: 40)]) == GameRules.mapMaxZoom)
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
