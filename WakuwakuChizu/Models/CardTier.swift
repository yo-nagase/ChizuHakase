import Foundation

/// What a card has grown into (CLAUDE.md §5).
///
/// One star per copy won. The first win puts the card in the book with one
/// star; every later win on the same card adds another, to five. Three make it
/// silver and five make it gold.
///
/// This replaced a plain/キラ pair, where the second copy was the end of the
/// line. Two states meant a prefecture whose three cards were collected had
/// exactly three wins left in it and then nothing.
nonisolated enum CardTier: Int, Comparable, Sendable, CaseIterable {
    /// Not collected yet.
    case none
    /// One or two stars.
    case plain
    case silver
    case gold

    init(stars: Int) {
        switch stars {
        case ..<1: self = .none
        case ..<GameRules.silverStars: self = .plain
        case ..<GameRules.maxCardStars: self = .silver
        default: self = .gold
        }
    }

    /// Silver and gold — the tiers worth calling out.
    ///
    /// The ✨ count on the title screen and the book's キラ filter both use this
    /// rather than gold alone. A child who has taken a card past plain has done
    /// the thing the tiers exist to reward, and a counter that stays on zero
    /// until the fifth copy of something is a counter that never moves.
    var isSpecial: Bool { self >= .silver }

    static func < (lhs: CardTier, rhs: CardTier) -> Bool { lhs.rawValue < rhs.rawValue }
}
