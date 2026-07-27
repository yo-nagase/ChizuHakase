import Foundation

/// Every tunable number from CLAUDE.md §5, plus the pure functions that use
/// them. Nothing here touches UI state, so all of it is directly testable.
nonisolated enum GameRules {

    // MARK: - Constants

    static let maxMastery = 3

    /// A card's stars: one per copy won. Three make it silver, five make it
    /// gold, and five is the cap (CLAUDE.md §5).
    static let maxCardStars = 5
    static let silverStars = 3

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
    static func stars(missedPrefectures: Int, questionCount: Int) -> Int {
        guard questionCount > 0 else { return 3 }
        if missedPrefectures <= 0 { return 3 }
        let twoStarLimit = Int((Double(questionCount) / 4).rounded(.up))
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

    // MARK: - Card draw

    enum CardDraw: Hashable, Sendable {
        /// First copy of a card the child did not have: one star.
        case new(SpecialtyCard)
        /// Another copy of a card they had. `stars` is the count afterwards.
        case star(SpecialtyCard, stars: Int)
        /// Already at five stars — nothing left to gain on this one.
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

    /// Draw one card for a correct answer.
    ///
    /// Unowned cards come first so the collection fills up quickly. After that
    /// the draw is among the cards that can still take a star, which is what
    /// keeps a cleared prefecture worth playing (CLAUDE.md §5) — drawing from
    /// all of them instead would spend wins on cards already at five while
    /// others sat at one.
    static func drawCard(
        from cards: [SpecialtyCard],
        owned: [String: Int],
        using generator: inout some RandomNumberGenerator
    ) -> CardDraw? {
        guard !cards.isEmpty else { return nil }

        let unowned = cards.filter { (owned[$0.id] ?? 0) <= 0 }
        if let pick = unowned.randomElement(using: &generator) {
            return .new(pick)
        }
        let unfinished = cards.filter { (owned[$0.id] ?? 0) < maxCardStars }
        if let pick = unfinished.randomElement(using: &generator) {
            return .star(pick, stars: (owned[pick.id] ?? 0) + 1)
        }
        guard let pick = cards.randomElement(using: &generator) else { return nil }
        return .duplicate(pick)
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
