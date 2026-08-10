import Foundation

/// What a card has grown into (CLAUDE.md §5).
///
/// One star per copy won. The first win puts the card in the book with one
/// star; every later win on the same card adds another, to fifteen. Five make
/// it silver and fifteen make it gold. Above gold sits rainbow, which is not a
/// star count at all: gold held while its prefecture's clean streak stood at
/// fifteen, recorded on the save and never washed off.
///
/// This replaced a plain/キラ pair, where the second copy was the end of the
/// line. Two states meant a prefecture whose three cards were collected had
/// exactly three wins left in it and then nothing.
nonisolated enum CardTier: Int, Comparable, Sendable, CaseIterable {
    /// Not collected yet.
    case none
    /// One to four stars.
    case plain
    case silver
    case gold
    case rainbow

    init(stars: Int, rainbow: Bool = false) {
        // A card the child does not hold cannot be shown as anything, flag or
        // no flag.
        guard stars >= 1 else {
            self = .none
            return
        }
        // The flag outranks the count. It was only ever set on a gold card, so
        // a mismatch is a damaged save — and trusting the flag is the reading
        // that does not take anything away (CLAUDE.md §12).
        if rainbow {
            self = .rainbow
            return
        }
        switch stars {
        case ..<GameRules.silverStars: self = .plain
        case ..<GameRules.maxCardStars: self = .silver
        default: self = .gold
        }
    }

    /// Silver and up — the tiers worth calling out.
    ///
    /// The ✨ count on the title screen and the book's キラ filter both use this
    /// rather than gold alone. A child who has taken a card past plain has done
    /// the thing the tiers exist to reward, and a counter that stays on zero
    /// until the fifth copy of something is a counter that never moves.
    var isSpecial: Bool { self >= .silver }

    static func < (lhs: CardTier, rhs: CardTier) -> Bool { lhs.rawValue < rhs.rawValue }
}
