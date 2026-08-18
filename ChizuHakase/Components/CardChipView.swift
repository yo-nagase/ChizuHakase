import SwiftUI

/// One card in a grid: the card book, the my-map sheet and the result reveal.
///
/// The face itself is `CardFaceView` at chip density — this is only what makes a
/// grid cell out of it, so a card in a list and a card held up are the same
/// object drawn at two sizes rather than two designs to keep in step.
struct CardChipView: View {
    let card: SpecialtyCard
    /// Named on the card, so the same face works in the result screen where
    /// nothing else says which prefecture the card came from.
    var prefecture: Prefecture?
    /// 0 = not collected yet, then one per copy won, to fifteen.
    var stars: Int = 1
    /// From the save's rainbow latch — see `CardFaceView.rainbow`.
    var rainbow: Bool = false
    /// Set to open the card on its own. Nil leaves the chip inert, which is
    /// what the my-map sheet wants — it is already a presentation, and a card
    /// put up over it would be the third layer deep.
    var onOpen: (() -> Void)?

    @Environment(\.textMode) private var mode

    private var tier: CardTier { CardTier(stars: stars, rainbow: rainbow) }
    private var isOwned: Bool { tier != .none }

    var body: some View {
        CardFaceView(card: card, prefecture: prefecture, stars: stars,
                     rainbow: rainbow, metrics: .chip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            // Only a card you own opens: there is nothing to look at behind a
            // mystery illustration, and a slot that responds to a tap by
            // showing nothing is a small lie.
            .modifier(OpenOnTap(action: isOwned ? onOpen : nil))
    }

    /// The stars are read out too: they are the whole progression, and a
    /// VoiceOver user hearing only 「かに」 cannot tell a one-star card from one
    /// that is a single win away from gold.
    private var accessibilityText: String {
        guard isOwned else { return mode.notCollectedYet }
        let name = "\(card.displayName(mode))。\(mode.starCount(stars))"
        guard let tierName = mode.cardTierName(tier) else { return name }
        return "\(name)。\(tierName)"
    }
}

#Preview {
    let card = SpecialtyCard(id: "01-1", prefectureCode: 1, emoji: "🦀",
                             nameKana: "かに", nameKanji: "蟹", category: .food,
                             description: "つめたい うみで そだつよ")
    return HStack(spacing: 12) {
        CardChipView(card: card, stars: 0)
        CardChipView(card: card, stars: 1)
        CardChipView(card: card, stars: GameRules.silverStars)
        CardChipView(card: card, stars: GameRules.maxCardStars)
        CardChipView(card: card, stars: GameRules.maxCardStars, rainbow: true)
    }
    .padding()
    .background(Palette.background)
}


/// Makes a chip openable without turning it into a Button, which would inherit
/// button styling the chip already draws for itself.
private struct OpenOnTap: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}
