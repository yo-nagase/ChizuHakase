import Foundation

/// Every tunable number from CLAUDE.md §5, plus the pure functions that use
/// them. Nothing here touches UI state, so all of it is directly testable.
nonisolated enum GameRules {

    // MARK: - Constants

    /// Clean answers to キラキラ. Five, up from three: 「おぼえた」 is claimed
    /// only at the top of this ladder now, and three lucky taps spread over a
    /// week is not having learned a prefecture (CLAUDE.md §5).
    static let maxMastery = 5

    /// A card's stars: one per copy won. Five make it silver, ten make it
    /// gold, and ten is the cap (CLAUDE.md §5). Down from fifteen: with the
    /// draw spreading stars across a prefecture's three cards, the first gold
    /// sat about eighteen clean runs of one stage away, and a top tier no
    /// child ever reaches is not a goal, it is a ceiling.
    static let maxCardStars = 10
    static let silverStars = 5
    /// Consecutive clean answers *after* a card reaches gold before it turns
    /// rainbow. Five — down from seven, originally fifteen — and the run only
    /// opens once the gold exists: finishing the stars resets the count, so
    /// the rainbow is always earned on top of the completed card, never
    /// alongside it (CLAUDE.md §5).
    static let rainbowStreak = 5

    static let firstTryBaseScore = 100
    static let comboBonus = 20
    static let retryScore = 50

    /// Correct-answer celebration, then advance.
    static let correctAdvanceDelay: TimeInterval = 1.15
    static let popDuration: TimeInterval = 0.55
    static let shakeDuration: TimeInterval = 0.45
    static let hintBlinkPeriod: TimeInterval = 0.9
    /// Wrong attempts on the current question before the answer starts blinking.
    ///
    /// Three, not two: two came up often enough that a child who was thinking
    /// rather than guessing kept getting the answer handed to them, and being
    /// helped before you have finished trying is its own small insult.
    static let missesBeforeHint = 3

    /// How many names 「なまえを あてる」 offers at once.
    static let nameChoiceCount = 4

    /// How loudly a streak should be celebrated. 0 means say nothing.
    ///
    /// A streak that always shouts the same way stops being news by the third
    /// one. Growing the celebration is the only part of a run a child can feel
    /// before the score screen, and it costs nothing when it breaks — combos
    /// reset silently (CLAUDE.md §12).
    static func comboTier(_ combo: Int) -> Int {
        switch combo {
        case ..<2: 0
        case 2...3: 1
        case 4...6: 2
        default: 3
        }
    }

    /// The names offered for one question: the answer plus decoys.
    ///
    /// Decoys come from the same stage, never the whole country. 「あいちけん」
    /// against three neighbours asks whether the child knows Aichi; against
    /// 北海道, 沖縄 and 青森 it asks nothing, because the shape on screen
    /// already rules those out.
    ///
    /// Order is shuffled — always putting the answer first would be learnable
    /// in about three questions.
    static func nameChoices(answer: Int,
                            from pool: [Int],
                            count: Int = nameChoiceCount,
                            using rng: inout AnyRandomNumberGenerator) -> [Int] {
        var chosen = [answer]
        let decoys = pool.filter { $0 != answer }.shuffled(using: &rng)
        chosen.append(contentsOf: decoys.prefix(max(0, count - 1)))
        return chosen.shuffled(using: &rng)
    }

    /// Whether a correct answer still earns a card.
    ///
    /// A single wrong tap is enough to lose it. Getting there in the end is
    /// still worth points and still counts toward the stage; the card is what
    /// marks having known it outright, and handing one out after a fumble makes
    /// it mean nothing.
    ///
    /// Points and mastery are untouched either way — this withholds a prize, it
    /// never takes one away (CLAUDE.md §12).
    static func earnsCard(afterMisses misses: Int) -> Bool {
        misses == 0
    }

    /// The order questions are asked in.
    ///
    /// `repeats` passes over the same prefectures, shuffled separately, and no
    /// prefecture is asked twice in a row — an immediate repeat tests what is
    /// still under the child's finger rather than what they know.
    static func questionOrder(codes: [Int], repeats: Int,
                              using rng: inout AnyRandomNumberGenerator) -> [Int] {
        guard repeats > 1 else { return codes.shuffled(using: &rng) }
        var order: [Int] = []
        for _ in 0..<repeats {
            var pass = codes.shuffled(using: &rng)
            // Swap the head away if it repeats the previous pass's tail. With
            // two or more prefectures there is always somewhere to put it.
            if let last = order.last, pass.first == last,
               let swap = pass.indices.dropFirst().first(where: { pass[$0] != last }) {
                pass.swapAt(0, swap)
            }
            order.append(contentsOf: pass)
        }
        return order
    }

    /// Breathing room added around the fitted map, as a fraction of its own
    /// size on each side, plus a flat inset so coastal prefectures never touch
    /// the bezel.
    ///
    /// CLAUDE.md §3 asked for 9%, which is 18% of the width spent on empty sea.
    /// On 全国チャレンジ the whole country is scaled to fit a phone's width, so
    /// that margin came straight out of how big Kagawa is drawn.
    static let mapPaddingRatio: CGFloat = 0.045
    static let mapPaddingPoints: CGFloat = 6

    /// Screen-space slack for taps that miss every prefecture (CLAUDE.md §3).
    static let tapTolerancePoints: CGFloat = 22
    /// Head start the prefecture being asked about gets when a tap falls
    /// between two of them. Smaller than the tolerance so it can tip a genuinely
    /// close call without overriding a tap that clearly landed elsewhere.
    static let tapTargetBiasPoints: CGFloat = 10

    // MARK: - Score

    /// Points for a correct answer.
    /// - Parameter combo: the combo count *after* this answer, 1-based.
    ///   Ignored unless `firstTry`.
    static func score(firstTry: Bool, combo: Int) -> Int {
        guard firstTry else { return retryScore }
        return firstTryBaseScore + max(0, combo - 1) * comboBonus
    }

    /// The combo after an answer. Only an unaided correct answer extends it.
    static func nextCombo(current: Int, correct: Bool, firstTry: Bool) -> Int {
        guard correct else { return 0 }
        return firstTry ? current + 1 : current
    }

    // MARK: - Stars

    /// Stars for a finished stage, judged on how many *prefectures* were
    /// missed — not how many wrong taps happened. Repeatedly fumbling one
    /// prefecture should not cost more than getting one wrong.
    ///
    /// Both sides of the comparison are prefectures. A regional stage asks each
    /// one twice, so measuring the band against the question count instead
    /// would quietly double the allowance there while leaving the national
    /// stage — where the two counts are equal — looking correct.
    static func stars(missedPrefectures: Int, prefectureCount: Int) -> Int {
        guard prefectureCount > 0 else { return 3 }
        if missedPrefectures <= 0 { return 3 }
        let twoStarLimit = Int((Double(prefectureCount) / 4).rounded(.up))
        return missedPrefectures <= twoStarLimit ? 2 : 1
    }

    // MARK: - Mastery

    /// Mastery only ever rises, and only on an unaided correct answer.
    /// Decay was considered and rejected: taking progress away from a child is
    /// exactly the anxiety this app is built to avoid (CLAUDE.md §5, §12).
    static func nextMastery(current: Int, firstTry: Bool) -> Int {
        let clamped = min(maxMastery, max(0, current))
        guard firstTry else { return clamped }
        return min(maxMastery, clamped + 1)
    }

    // MARK: - Prefecture streak

    /// The prefecture's consecutive-clean count after a stage asked about it,
    /// and every rainbow that run latched on the way.
    ///
    /// `outcomes` are this stage's questions on the prefecture in the order
    /// asked; `draws` are the same stage's card draws for this prefecture,
    /// which pair one-to-one with the clean outcomes (a draw happens exactly
    /// on a first-try answer) — that pairing is how the walk knows *when* a
    /// card finished its gold. A fumble puts the count back to zero, and so
    /// does a promotion to gold: the rainbow run opens only once the gold
    /// exists, so the answer that completed it does not also start the count.
    /// The count is the only thing either reset touches — stars and tiers
    /// stand — and neither reset is ever announced (CLAUDE.md §12).
    ///
    /// The moment the count touches `rainbowStreak`, every card that is gold
    /// *at that moment* latches. Checked mid-walk rather than on the final
    /// count: a fumble on the stage's second asking must not swallow a
    /// rainbow the first asking had already earned. And any promotion resets
    /// the count, so a qualifying run is always entirely later than every
    /// gold in the set — a card promoted after the crossing starts its own.
    static func nextStreak(
        current: Int, outcomes: [Bool],
        draws: [CardDraw] = [], goldCardIDs: Set<String> = []
    ) -> (streak: Int, latched: Set<String>) {
        var gold = goldCardIDs
        var streak = max(0, current)
        var latched: Set<String> = []
        // A count already over the line latches on arrival: saves written
        // under an older, higher threshold can hold a qualified streak that
        // never met a check at the current line.
        if streak >= rainbowStreak { latched.formUnion(gold) }
        var drawIndex = 0
        for clean in outcomes {
            guard clean else { streak = 0; continue }
            let draw = drawIndex < draws.count ? draws[drawIndex] : nil
            drawIndex += 1
            if let draw, draw.stars >= maxCardStars, !gold.contains(draw.card.id) {
                gold.insert(draw.card.id)
                streak = 0
            } else {
                streak += 1
                if streak >= rainbowStreak { latched.formUnion(gold) }
            }
        }
        return (streak, latched)
    }

    // MARK: - Next goal

    /// What the 「あと◯」 line under a card counts down to.
    enum NextGoal: Equatable, Sendable {
        /// So many more wins to the named tier.
        case wins(Int, to: CardTier)
        /// So many more consecutive clean answers to rainbow.
        case streak(Int)
        /// Rainbow — nothing above it left to count toward.
        case done

        /// How far along the current rung is, 0...1 — the little bar under the
        /// 「あと◯」 line. Derived from the same goal as the label so the two
        /// cannot disagree. Each rung starts empty: progress toward silver does
        /// not carry into the gold rung, or the bar would spend most of the
        /// game nearly full and stop meaning anything.
        var fraction: Double {
            switch self {
            case .wins(let remaining, let tier):
                let span = tier == .gold ? maxCardStars - silverStars : silverStars
                return Double(max(0, span - remaining)) / Double(span)
            case .streak(let remaining):
                return Double(max(0, rainbowStreak - remaining)) / Double(rainbowStreak)
            case .done:
                return 1
            }
        }
    }

    /// The next thing this card can become. Nil for a card not yet owned:
    /// the empty slot already says what the first goal is.
    static func nextGoal(stars: Int, streak: Int, isRainbow: Bool) -> NextGoal? {
        guard stars > 0 else { return nil }
        if isRainbow { return .done }
        if stars < silverStars { return .wins(silverStars - stars, to: .silver) }
        if stars < maxCardStars { return .wins(maxCardStars - stars, to: .gold) }
        // Gold whose latch has not caught yet. Never 「あと0」: with the streak
        // already there, the next clean answer on the prefecture sets it.
        return .streak(max(1, rainbowStreak - streak))
    }

    // MARK: - Card draw

    enum CardDraw: Hashable, Sendable {
        /// First copy of a card the child did not have: one star.
        case new(SpecialtyCard)
        /// Another copy of a card they had. `stars` is the count afterwards.
        case star(SpecialtyCard, stars: Int)
        /// Already at the star cap — nothing left to gain on this one.
        case duplicate(SpecialtyCard)

        var card: SpecialtyCard {
            switch self {
            case .new(let c), .star(let c, _), .duplicate(let c): c
            }
        }

        /// What the card is worth after this draw.
        var stars: Int {
            switch self {
            case .new: 1
            case .star(_, let stars): min(maxCardStars, stars)
            case .duplicate: maxCardStars
            }
        }

        var tier: CardTier { CardTier(stars: stars) }

        /// True when this draw is what took the card up a tier, which is the
        /// only moment worth announcing as more than a star.
        var promoted: Bool { tier.isSpecial && CardTier(stars: stars - 1) != tier }
    }

    /// How one prefecture's (or country's) cards enter the draw. The one rule
    /// that differs between atlases (world design §5 「規則の差分」): star
    /// growth, tiers and rainbow sit above the pool and are shared. `Atlas`
    /// carries the value so the branch lives in data — views never see it.
    enum DrawPolicy: Sendable {
        /// 日本版: every card of the prefecture is in the pool from the start.
        case random
        /// 世界版: the first-listed card (the flag) is dealt alone until it
        /// reaches silver; only then do the others join the pool. Learning
        /// order — first the flag, then what is behind it — made a draw rule.
        ///
        /// "First-listed" is a contract on the catalog, not on the id: the
        /// country's entry lists the flag card first (WorldCards.json, Task 8).
        /// Parsing "-1" out of ids here would hide that dependency instead of
        /// naming it.
        case flagFirstSilverGate
    }

    /// Draw one card for a correct answer.
    ///
    /// Unowned cards come first so the collection fills up quickly. After that
    /// the draw is among the cards that can still take a star, which is what
    /// keeps a cleared prefecture worth playing (CLAUDE.md §5) — drawing from
    /// all of them instead would spend wins on cards already at the cap while
    /// others sat at one. `policy` narrows the pool before any of that, and it
    /// has no default: the policy is the atlas's one rule difference, and a
    /// call site that forgets to pass it would silently deal japan's way.
    static func drawCard(
        from cards: [SpecialtyCard],
        owned: [String: Int],
        policy: DrawPolicy,
        using generator: inout some RandomNumberGenerator
    ) -> CardDraw? {
        let pool = drawPool(cards, owned: owned, policy: policy)
        guard !pool.isEmpty else { return nil }

        let unowned = pool.filter { (owned[$0.id] ?? 0) <= 0 }
        if let pick = unowned.randomElement(using: &generator) {
            return .new(pick)
        }
        let unfinished = pool.filter { (owned[$0.id] ?? 0) < maxCardStars }
        if let pick = unfinished.randomElement(using: &generator) {
            return .star(pick, stars: (owned[pick.id] ?? 0) + 1)
        }
        guard let pick = pool.randomElement(using: &generator) else { return nil }
        return .duplicate(pick)
    }

    /// The cards this answer can land on. Under the gate, every win goes to
    /// the flag until it is silver — so the original is never the "unowned"
    /// pick, and the win after the flag touches silver hands it over.
    private static func drawPool(
        _ cards: [SpecialtyCard], owned: [String: Int], policy: DrawPolicy
    ) -> [SpecialtyCard] {
        switch policy {
        case .random:
            return cards
        case .flagFirstSilverGate:
            guard let flag = cards.first, (owned[flag.id] ?? 0) < silverStars
            else { return cards }
            return [flag]
        }
    }

    /// Stars after a draw, capped at `maxCardStars`.
    ///
    /// Takes the higher of what is already recorded and what the draw is worth,
    /// so replaying a stage's draws onto the save — which is exactly what
    /// happens when a result is applied — can never walk a count backwards.
    static func applyDraw(_ draw: CardDraw, to owned: [String: Int]) -> [String: Int] {
        var next = owned
        next[draw.card.id] = min(maxCardStars, max(next[draw.card.id] ?? 0, draw.stars))
        return next
    }

    // MARK: - Records

    /// Best-of merge: a replay never lowers what the child already earned.
    static func bestRecord(existing: StageRecord?, new: StageRecord) -> StageRecord {
        guard let existing else { return new }
        return StageRecord(stars: max(existing.stars, new.stars),
                           score: max(existing.score, new.score))
    }
}

/// Type-erased RNG so the quiz can hold one as a stored property and tests can
/// swap in a seeded generator to make shuffles and card draws reproducible.
nonisolated struct AnyRandomNumberGenerator: RandomNumberGenerator {
    private var base: any RandomNumberGenerator

    init(_ base: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.base = base
    }

    mutating func next() -> UInt64 { base.next() }
}
