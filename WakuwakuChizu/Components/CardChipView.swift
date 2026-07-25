import SwiftUI

/// One specialty card. Used in the card book grid and in the win reveal.
struct CardChipView: View {
    let card: SpecialtyCard
    /// 0 = not collected yet, 1 = owned, 2 = shiny.
    var ownedCount: Int = 1
    var showsDescription = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOwned: Bool { ownedCount > 0 }
    private var isShiny: Bool { ownedCount >= GameRules.maxCardCopies }

    var body: some View {
        VStack(spacing: 6) {
            Text(isOwned ? card.emoji : "❓")
                .font(.system(size: 40))
                .frame(height: 46)

            Text(isOwned ? card.nameKana : "？？？")
                .font(AppFont.rounded(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if showsDescription, isOwned {
                Text(card.description)
                    .font(AppFont.rounded(11, relativeTo: .caption2))
                    .foregroundStyle(Palette.ink.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .stickerCard(fill: chipFill, cornerRadius: 18,
                     edge: isOwned ? 3 : 1.5, isHolographic: isShiny)
        .overlay(alignment: .topTrailing) {
            if isShiny {
                Text("✨")
                    .font(.system(size: 17))
                    .padding(6)
                    .modifier(ShinyTwinkle(enabled: !reduceMotion))
            }
        }
        // Uncollected slots sit flat on the page; earned ones are stuck on.
        .opacity(isOwned ? 1 : 0.72)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var chipFill: Color {
        if isShiny { return Color(hex: 0xFFF6DC) }
        return isOwned ? .white : Color(hex: 0xF1ECE0)
    }

    private var accessibilityText: String {
        guard isOwned else { return "まだ もっていない カード" }
        return isShiny ? "\(card.nameKana) キラカード" : card.nameKana
    }
}

private struct ShinyTwinkle: ViewModifier {
    let enabled: Bool
    @State private var bright = false

    func body(content: Content) -> some View {
        if enabled {
            content
                .opacity(bright ? 1 : 0.45)
                .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                           value: bright)
                .onAppear { bright = true }
        } else {
            content
        }
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
