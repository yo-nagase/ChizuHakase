import SwiftUI

/// A card, at whatever size it is being shown.
///
/// One design, two densities. The book, the my-map sheet and the result screen
/// used to show a sticker chip — a square of art with a caption under it — while
/// tapping one opened a printed card with stock, a matted window and a name
/// plate. Two objects for one thing, and the wall of stickers gave no hint that
/// what it was collecting was cards.
///
/// Structure, colours and rules are shared. The densities differ only in type
/// size and in whether the small print appears at all: at chip size a
/// description would render around 5pt, which is texture rather than text.
struct CardFaceView: View {
    let card: SpecialtyCard
    /// Printed across the top when given.
    ///
    /// Nil where the screen already says it: the book groups by prefecture and
    /// the my-map sheet is about one, so naming it on the card would put the
    /// same word three times in a row under a heading that already carries it.
    /// The result screen and the enlarged card do name it — there, nothing else
    /// does.
    let prefecture: Prefecture?
    /// 0 = not collected yet, then one per copy won, to fifteen.
    let stars: Int
    /// Latched on the save when the card was gold through a fifteen-streak.
    /// Display-only here — the face never decides it.
    var rainbow: Bool = false
    var metrics: Metrics = .full
    /// Live yaw in degrees, which the foil highlight follows. Only the enlarged
    /// card has a gesture behind it; every other caller leaves this at zero.
    var tilt: CGSize = .zero

    @Environment(\.textMode) private var mode

    /// How far the enlarged card leans. Lives here because the highlight and the
    /// visible edge are both positioned from it, so the angle, the reflection and
    /// the thickness cannot drift apart.
    ///
    /// 26° is steep enough to look at the card side-on. It was 14°, which kept
    /// the face undistorted but also kept it looking like a printed rectangle
    /// rather than an object being turned over.
    static let maxTilt: CGFloat = 26

    /// Trading-card proportions, at every size.
    static let aspectRatio: CGFloat = 0.7

    private var tier: CardTier { CardTier(stars: stars, rainbow: rainbow) }
    private var isOwned: Bool { tier != .none }
    /// Silver, gold and rainbow are foil; plain board and an empty slot are not.
    private var isMetal: Bool { tier.isSpecial }

    /// Every owned card shows its painted subject; rarity is communicated by
    /// the board, edge, stars and foil rather than by hiding the illustration.
    /// An unowned slot uses one shared hand-painted question mark, and missing
    /// owned art falls back to the card's emoji.
    private var shownArt: String? {
        Self.artNameToDisplay(for: card, stars: stars, rainbow: rainbow)
    }

    static func artNameToDisplay(for card: SpecialtyCard, stars: Int,
                                 rainbow: Bool = false) -> String? {
        CardTier(stars: stars, rainbow: rainbow) == .none ? nil : card.art
    }

    /// A real illustration rather than the system's rendered question-mark
    /// emoji. Shared because an uncollected card must not reveal its subject.
    static let uncollectedArtName = "card-uncollected"

    struct Metrics {
        /// How much stock shows around the panel — the border, in other words.
        var border: CGFloat
        var outerRadius: CGFloat
        var panelRadius: CGFloat
        var panelPadding: CGFloat
        var spacing: CGFloat
        /// The category mark. Held at a readable size rather than scaled with the
        /// rest: at chip density it is the only thing in the top-left corner, and
        /// a 9pt emoji there reads as a smudge.
        var categorySize: CGFloat
        var prefectureSize: CGFloat
        var nameSize: CGFloat
        var emojiSize: CGFloat
        var windowRadius: CGFloat
        var plateVerticalPadding: CGFloat
        /// How thick the card is, in points. Still more than scale — a real
        /// trading card at 300pt wide would be under 2pt, which reads as paper
        /// rather than as an object you can turn over — but only just enough to
        /// show an edge. It was three times this and the card turned into a
        /// slab: past a certain depth what it stops looking like is a card.
        /// Zero on a chip: a card lying on the album page shows its thickness
        /// as the sticker shadow already.
        var thickness: CGFloat
        /// The description and the collector number.
        var showsSmallPrint: Bool
        var shadowColor: Color
        var shadowRadius: CGFloat
        var shadowY: CGFloat

        /// Held up on its own.
        static let full = Metrics(
            border: 11, outerRadius: 12, panelRadius: 7, panelPadding: 12,
            spacing: 8, categorySize: 15, prefectureSize: 16, nameSize: 21,
            emojiSize: 88, windowRadius: 5, plateVerticalPadding: 7, thickness: 3,
            showsSmallPrint: true,
            shadowColor: .black.opacity(0.35), shadowRadius: 20, shadowY: 12)

        /// One of three across a grid. Keeps the app's solid sticker shadow
        /// rather than the enlarged card's soft one: a card lying on the page is
        /// not a card being held up in front of it.
        static let chip = Metrics(
            border: 5, outerRadius: 9, panelRadius: 5, panelPadding: 6,
            spacing: 3, categorySize: 12, prefectureSize: 10, nameSize: 14,
            emojiSize: 40, windowRadius: 3, plateVerticalPadding: 4, thickness: 0,
            showsSmallPrint: false,
            shadowColor: Palette.stickerShadow, shadowRadius: 0, shadowY: 2)
    }

    var body: some View {
        ZStack {
            stock
            VStack(spacing: metrics.spacing) {
                topRow
                artWindow
                namePlate
                if metrics.showsSmallPrint, isOwned {
                    Text(card.description)
                        .font(AppFont.rounded(13, relativeTo: .caption))
                        .foregroundStyle(Palette.ink.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                    footer
                }
            }
            .padding(metrics.panelPadding)
            .background(
                RoundedRectangle(cornerRadius: metrics.panelRadius, style: .continuous)
                    .fill(Palette.page)
            )
            // The inset is what turns the outer colour into a border rather
            // than a background.
            .padding(metrics.border)
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: metrics.outerRadius, style: .continuous))
        .overlay {
            // Cut foil is lit along its whole edge. Printed board is not, so
            // only the metals get the rim.
            if isMetal {
                RoundedRectangle(cornerRadius: metrics.outerRadius, style: .continuous)
                    .strokeBorder(rimColour, lineWidth: 1)
            }
        }
        .background { edge }
        .shadow(color: metrics.shadowColor, radius: metrics.shadowRadius, y: metrics.shadowY)
    }

    // MARK: - Thickness

    /// The card as a slab rather than a plane.
    ///
    /// One shape behind the face rather than a stack of layers: the face covers
    /// all of it except the strip along whichever side has turned away, and that
    /// strip is what an edge is. The offset is `tan` of the angle, not `sin`,
    /// because it is applied in the card's own plane — the rotation the caller
    /// applies then foreshortens it back to the right width on screen.
    @ViewBuilder private var edge: some View {
        if metrics.thickness > 0 {
            RoundedRectangle(cornerRadius: metrics.outerRadius, style: .continuous)
                .fill(Palette.cardCore)
                .offset(edgeOffset)
        }
    }

    private var edgeOffset: CGSize {
        let t = metrics.thickness
        func lean(_ degrees: CGFloat) -> CGFloat { tan(degrees * .pi / 180) * t }
        // Even at rest a little of the bottom edge shows, the way it does on a
        // card lying face up on a table. Without it the card is a plane until
        // someone thinks to turn it.
        return CGSize(width: -lean(tilt.width), height: lean(tilt.height) + t * 0.3)
    }

    // MARK: - Stock

    /// The border the panel sits on, and the one place the difference between a
    /// plain card and a キラ has to be obvious at a glance.
    ///
    /// Silver and gold are foil: an opaque metal ramp with a highlight that
    /// slides across as the card turns. Plain cards are matte board, and nothing
    /// on them moves.
    ///
    /// Both halves had to change together. The plain stock used to be the
    /// prefecture's own colour, and the warm end of that palette is gold enough
    /// to blur the distinction however bright the foil gets. The prefecture's
    /// colour is still on the mat and the name plate inside, where it is
    /// identifying the card rather than competing with its rarity.
    @ViewBuilder private var stock: some View {
        if isMetal {
            LinearGradient(stops: foilRamp,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay { glint }
        } else if isOwned {
            LinearGradient(colors: [Palette.cardBoard, Palette.cardBoardDeep],
                           startPoint: .top, endPoint: .bottom)
        } else {
            LinearGradient(colors: [Palette.emptyBoard, Palette.emptyBoardDeep],
                           startPoint: .top, endPoint: .bottom)
        }
    }

    private var foilRamp: [Gradient.Stop] {
        switch tier {
        case .rainbow: Palette.rainbowRamp
        case .gold: Palette.foilRamp
        default: Palette.silverRamp
        }
    }

    private var rimColour: Color {
        switch tier {
        case .rainbow: Palette.rainbowEdge
        case .gold: Palette.foilEdge
        default: Palette.silverEdge
        }
    }

    /// The specular streak on foil.
    ///
    /// Bound to the yaw rather than animating on its own: a card that shines by
    /// itself is a screen effect, while one that shines when it is turned is a
    /// surface. It also means Reduce Motion needs no special case — the tilt
    /// never leaves zero there, so the highlight simply sits still.
    private var glint: some View {
        // Clamped away from the edges so the band always has room for its full
        // width, and the streak never degenerates into a hard line at a corner.
        let centre = min(max(0.5 + tilt.width / Self.maxTilt * 0.4, 0.16), 0.84)
        return LinearGradient(
            // Not brighter: plusLighter over the ramp's own light stops clips to
            // white, and a white streak on gold is chrome, not gold.
            stops: [.init(color: .clear, location: centre - 0.16),
                    .init(color: .white.opacity(0.45), location: centre),
                    .init(color: .clear, location: centre + 0.16)],
            startPoint: .topTrailing, endPoint: .bottomLeading)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
    }

    // MARK: - Panel

    private var topRow: some View {
        HStack(spacing: metrics.spacing * 0.75) {
            Text(card.category.emoji)
                .font(.system(size: metrics.categorySize))
            // A world flag already carries the country as its title plate.
            // Original cards need it here because the world book is one
            // acquisition-order grid with no country section headings.
            if let prefecture, card.category != .flag {
                Text(prefecture.displayName(mode))
                    .font(AppFont.heading(metrics.prefectureSize, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .tracking(0.5)
            }
            Spacer(minLength: 0)
            // Rarity, in the corner where a card keeps it: one star per copy
            // won. A slot with nothing in it has none to state yet.
            if isOwned {
                // One star and a count, not a row of glyphs: the scale runs to
                // fifteen now, and fifteen stars beside a six-character
                // prefecture name is not a top row, it is a fence.
                Text(verbatim: "★\(stars)")
                    .font(AppFont.rounded(metrics.prefectureSize * 0.68,
                                          relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(starColour)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var starColour: Color {
        switch tier {
        case .rainbow: Palette.rainbowMark
        case .gold: Palette.gold
        case .silver: Palette.silverMark
        default: Palette.ink.opacity(0.28)
        }
    }

    /// The picture, matted and ruled like a window cut in the card.
    private var artWindow: some View {
        ZStack {
            isOwned ? Palette.fill(for: card.prefectureCode, strength: 0.14)
                    : Palette.emptyMat
            if let shownArt {
                Image(shownArt).resizable().scaledToFit().padding(4)
            } else if !isOwned {
                Image(Self.uncollectedArtName)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    // A full book can show more than a hundred of these at
                    // once. Keep the painting visible without letting the
                    // repeated mystery parcel outshine cards already earned.
                    .saturation(0.52)
                    .opacity(0.82)
            } else {
                Text(card.emoji)
                    .font(.system(size: metrics.emojiSize))
                    .minimumScaleFactor(0.5)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .overlay { sheen }
        .clipShape(RoundedRectangle(cornerRadius: metrics.windowRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.windowRadius, style: .continuous)
                .strokeBorder(Palette.ink.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 2)
    }

    /// The name, on a plate rather than loose on the panel — it is the card's
    /// title, and a title on a card sits on something.
    private var namePlate: some View {
        Text(nameLine)
            .font(AppFont.rounded(metrics.nameSize, relativeTo: .title3))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, metrics.plateVerticalPadding)
            .background(
                RoundedRectangle(cornerRadius: metrics.windowRadius, style: .continuous)
                    .fill(isOwned ? Palette.fill(for: card.prefectureCode, strength: 0.34)
                                  : Palette.emptyPlate)
            )
    }

    /// An illustrated card always gets the reading, never the kanji. The
    /// painting titles itself — but in kanji (「乳製品」「江戸前寿司」「飛騨牛」),
    /// which is unreadable to the five-year-olds this app is for, so the plate is
    /// the only place they can find out what they just won. It repeats the
    /// picture for an adult; that is the cheaper mistake.
    private var nameLine: String {
        guard isOwned else { return "？？？" }
        return shownArt == nil ? card.displayName(mode) : card.nameKana
    }

    private var footer: some View {
        HStack {
            Text(card.category.label(mode))
                .font(AppFont.rounded(10, relativeTo: .caption2))
                .foregroundStyle(Palette.ink.opacity(0.45))
            Spacer(minLength: 0)
            // A collector number. It means nothing mechanically and that is
            // fine — it is one of the things that makes a card feel like a card.
            Text(verbatim: "No.\(card.id)")
                .font(AppFont.rounded(10, relativeTo: .caption2))
                .foregroundStyle(Palette.ink.opacity(0.35))
                .monospacedDigit()
        }
    }

    /// The shine over the picture, and the reason tilting is worth doing at all.
    ///
    /// It slides across as the card turns, so the highlight belongs to the angle
    /// rather than being a decal printed on the face.
    ///
    /// Foil only. A plain card used to carry a faint white version of this on
    /// the theory that glass catches light too, but the cards then differed by
    /// how much they shone rather than by whether they shone — and "less shiny"
    /// is a comparison a child can only make with both cards side by side.
    ///
    /// Gold refracts a rainbow; silver returns white — that is what the two
    /// metals do, and it keeps the tiers apart at a glance even where the stock
    /// itself is hidden behind the picture. Rainbow returns white too: its
    /// stock already carries every colour, and a rainbow shine on a rainbow
    /// card just reads as noise.
    @ViewBuilder private var sheen: some View {
        if isMetal {
            let shift = tilt.width / Self.maxTilt
            LinearGradient(
                colors: tier == .gold
                    ? Palette.holographicBand
                    : [.clear, .white.opacity(0.9), .clear],
                startPoint: UnitPoint(x: 0.1 + shift * 0.5, y: 0),
                endPoint: UnitPoint(x: 0.9 + shift * 0.5, y: 1))
            // Enough to read as foil while it slides, not so much that the
            // illustration underneath changes colour at rest.
            .opacity(0.24)
            .blendMode(.plusLighter)
            .allowsHitTesting(false)
        }
    }
}

#Preview {
    let card = SpecialtyCard(id: "01-1", prefectureCode: 1, emoji: "🦀",
                             nameKana: "かに", nameKanji: "蟹", category: .food,
                             description: "つめたい うみで そだつよ")
    return VStack(spacing: 16) {
        // Empty slot, one star, silver, gold, rainbow.
        HStack(spacing: 10) {
            ForEach([0, 1, GameRules.silverStars, GameRules.maxCardStars], id: \.self) { stars in
                CardFaceView(card: card, prefecture: nil, stars: stars, metrics: .chip)
            }
            CardFaceView(card: card, prefecture: nil, stars: GameRules.maxCardStars,
                         rainbow: true, metrics: .chip)
        }
        CardFaceView(card: card, prefecture: nil, stars: GameRules.maxCardStars,
                     rainbow: true)
            .frame(maxWidth: 240)
    }
    .padding()
    .background(Palette.background)
}
