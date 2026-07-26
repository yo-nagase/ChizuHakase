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
    /// 0 = not collected yet, 1 = owned, 2 = shiny.
    var ownedCount: Int = 1
    /// Set to open the card on its own. Nil leaves the chip inert, which is
    /// what the result screen wants — nothing there should lead away from the
    /// celebration mid-flow.
    var onOpen: (() -> Void)?

    @Environment(\.textMode) private var mode

    private var isOwned: Bool { ownedCount > 0 }
    private var isShiny: Bool { ownedCount >= GameRules.maxCardCopies }

    var body: some View {
        CardFaceView(card: card, prefecture: prefecture, ownedCount: ownedCount,
                     metrics: .chip)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            // Only a card you own opens: there is nothing to look at behind a
            // 「？」, and a slot that responds to a tap by showing nothing is a
            // small lie.
            .modifier(OpenOnTap(action: isOwned ? onOpen : nil))
    }

    private var accessibilityText: String {
        guard isOwned else { return mode.notCollectedYet }
        let name = card.displayName(mode)
        return isShiny ? "\(name) キラカード" : name
    }
}

#Preview {
    let card = SpecialtyCard(id: "01-1", prefectureCode: 1, emoji: "🦀",
                             nameKana: "かに", nameKanji: "蟹", category: .food,
                             description: "つめたい うみで そだつよ")
    return HStack(spacing: 12) {
        CardChipView(card: card, ownedCount: 0)
        CardChipView(card: card, ownedCount: 1)
        CardChipView(card: card, ownedCount: 2)
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
