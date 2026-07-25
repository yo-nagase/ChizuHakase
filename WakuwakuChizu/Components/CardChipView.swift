import SwiftUI

/// One specialty card. Used in the card book grid and in the win reveal.
struct CardChipView: View {
    let card: SpecialtyCard
    /// 0 = not collected yet, 1 = owned, 2 = shiny.
    var ownedCount: Int = 1
    var showsDescription = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textMode) private var mode

    private var isOwned: Bool { ownedCount > 0 }
    private var isShiny: Bool { ownedCount >= GameRules.maxCardCopies }

    /// The painted card, shown only once this one has gone キラ.
    ///
    /// Holding the picture back until then is what makes a duplicate draw feel
    /// like a win instead of a consolation: the emoji card the child already
    /// has turns into the real thing. Cards without art keep the emoji.
    private var shinyArt: String? { isShiny ? card.art : nil }

    var body: some View {
        VStack(spacing: 6) {
            face

            Text(nameLine)
                .font(AppFont.rounded(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            if showsDescription, isOwned {
                Text(card.description)
                    .font(AppFont.rounded(11, relativeTo: .caption2))
                    .foregroundStyle(Palette.ink.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        // Fills the row height the grid hands out, so a painted card and an
        // emoji card sitting side by side are the same size.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    /// The caption under the face.
    ///
    /// An illustrated card always gets the reading, never the kanji. The
    /// painting titles itself — but in kanji (「乳製品」「江戸前寿司」「飛騨牛」),
    /// which is unreadable to the five-year-olds this app is for, so the line
    /// underneath is the only place they can find out what they just won. It
    /// repeats the picture for an adult; that is the cheaper mistake.
    private var nameLine: String {
        guard isOwned else { return "？？？" }
        return shinyArt == nil ? card.displayName(mode) : card.nameKana
    }

    /// Same square for every chip whether it holds a painting or an emoji, so
    /// one キラ card in a row does not shove its neighbours out of line.
    private var face: some View {
        // The square comes from a clear spacer rather than from the content:
        // an Image grows to fill a proposal but a Text does not, so putting
        // aspectRatio on the content left emoji chips short and painted ones
        // tall, and every mixed row went ragged.
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let shinyArt {
                    Image(shinyArt)
                        .resizable()
                        .scaledToFit()
                } else {
                    Text(isOwned ? card.emoji : "❓")
                        .font(.system(size: 40))
                }
            }
    }

    private var chipFill: Color {
        if isShiny { return Color(hex: 0xFFF6DC) }
        return isOwned ? .white : Color(hex: 0xF1ECE0)
    }

    private var accessibilityText: String {
        guard isOwned else { return mode.notCollectedYet }
        let name = card.displayName(mode)
        return isShiny ? "\(name) キラカード" : name
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
