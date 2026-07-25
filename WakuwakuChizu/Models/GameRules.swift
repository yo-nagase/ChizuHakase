import Foundation

/// Every tunable number from CLAUDE.md §5, plus the pure functions that use
/// them. Nothing here touches UI state, so all of it is directly testable.
nonisolated enum GameRules {

    // MARK: - Constants

    static let maxMastery = 3
    static let maxCardCopies = 2

    static let firstTryBaseScore = 100
    static let comboBonus = 20
    static let retryScore = 50

    /// Correct-answer celebration, then advance.
    static let correctAdvanceDelay: TimeInterval = 1.15
    static let popDuration: TimeInterval = 0.55
    static let shakeDuration: TimeInterval = 0.45
    static let hintBlinkPeriod: TimeInterval = 0.9
    /// Wrong attempts on the current question before the answer starts blinking.
    static let missesBeforeHint = 2

    /// Fraction of the fitted map added as breathing room, plus a flat inset so
    /// coastal prefectures never touch the bezel.
    static let mapPaddingRatio: CGFloat = 0.09
    static let mapPaddingPoints: CGFloat = 8

    /// Screen-space slack for taps that miss every prefecture (CLAUDE.md §3).
    static let tapTolerancePoints: CGFloat = 22

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

    enum CardDraw: Equatable, Sendable {
        /// First copy of a card the child did not have.
        case new(SpecialtyCard)
        /// Promoted to the shiny copy (owned count 2).
        case shiny(SpecialtyCard)
        /// Already shiny — nothing left to gain on this one.
        case duplicate(SpecialtyCard)

        var card: SpecialtyCard {
            switch self {
            case .new(let c), .shiny(let c), .duplicate(let c): c
            }
        }
    }

    /// Draw one card for a correct answer.
    ///
    /// Unowned cards come first so the collection fills up quickly; once a
    /// prefecture is complete, further wins roll for the shiny upgrade, which
    /// is what keeps cleared stages worth replaying (CLAUDE.md §5).
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
        guard let pick = cards.randomElement(using: &generator) else { return nil }
        return (owned[pick.id] ?? 0) >= maxCardCopies ? .duplicate(pick) : .shiny(pick)
    }

    /// Owned count after a draw, capped at `maxCardCopies`.
    static func applyDraw(_ draw: CardDraw, to owned: [String: Int]) -> [String: Int] {
        var next = owned
        let id = draw.card.id
        switch draw {
        case .new:
            next[id] = max(1, next[id] ?? 0)
        case .shiny:
            next[id] = maxCardCopies
        case .duplicate:
            next[id] = maxCardCopies
        }
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
