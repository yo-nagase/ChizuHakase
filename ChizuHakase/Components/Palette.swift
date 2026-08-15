import SwiftUI

/// Design tokens from CLAUDE.md §9.
/// nonisolated so value types like PrefectureAppearance can use these as
/// default property values.
nonisolated enum Palette {
    static let background = Color(hex: 0xFFF7E8)
    static let ink        = Color(hex: 0x3D3A4B)
    static let orange     = Color(hex: 0xFF9F1C)   // primary CTA
    static let teal       = Color(hex: 0x2EC4B6)   // secondary action
    static let red        = Color(hex: 0xFF5D5D)   // correct-answer flourish / hint
    static let gold       = Color(hex: 0xFFC53D)   // sparkle / shiny card
    static let sea        = [Color(hex: 0xCDEFFB), Color(hex: 0xA9DFF2)]

    /// Level 0 prefectures on the my-map.
    static let unlearned  = Color(hex: 0xE7ECEF)

    /// Prefecture fills, cycled by `code % 8` so neighbours rarely collide.
    /// Kept as raw hex so tints can be mixed numerically — Color.mix(with:by:)
    /// is iOS 18 and this app targets 17.
    static let prefectureHexes: [UInt32] = [
        0xFF8A80, 0xFFCC80, 0xFFF176, 0xA5D6A7,
        0x81D4FA, 0xCE93D8, 0xF48FB1, 0x80CBC4,
    ]

    static let prefectureFills = prefectureHexes.map { Color(hex: $0) }

    static func hex(for prefectureCode: Int) -> UInt32 {
        let count = prefectureHexes.count
        return prefectureHexes[((prefectureCode % count) + count) % count]
    }

    static func fill(for prefectureCode: Int) -> Color {
        Color(hex: hex(for: prefectureCode))
    }

    /// Prefecture colour mixed toward white. `strength` 1 is the full colour,
    /// 0 is white.
    static func fill(for prefectureCode: Int, strength: Double) -> Color {
        Color(hex: hex(for: prefectureCode), mixedWithWhite: 1 - strength)
    }

    static var seaGradient: LinearGradient {
        LinearGradient(colors: sea, startPoint: .top, endPoint: .bottom)
    }

    // MARK: - Sticker album

    /// The album page a sticker is stuck onto. A deeper cream than the old
    /// near-white (0xFFFBF2): white next to the artwork read as a bare
    /// screen, this reads as paper.
    static let page = Color(hex: 0xF9F1DE)
    /// Outline of a slot no sticker has been earned for yet, and the stock of a
    /// card not collected yet.
    static let emptySlotHex: UInt32 = 0xD8D2C4
    static let emptySlot = Color(hex: emptySlotHex)
    /// A blank card's stock, lighter than the slot outline it comes from: on a
    /// fresh save 139 of the 141 are blank, and at full strength the book was a
    /// wall of grey with the two earned cards lost in it.
    static let emptyBoard = Color(hex: emptySlotHex, mixedWithWhite: 0.5)
    static let emptyBoardDeep = Color(hex: emptySlotHex, mixedWithWhite: 0.12)
    /// The mat and the name plate of an uncollected card: the same grey the
    /// stock uses, thinned, so a blank card is one colour rather than three.
    static let emptyMat = Color(hex: emptySlotHex, mixedWithWhite: 0.72)
    static let emptyPlate = Color(hex: emptySlotHex, mixedWithWhite: 0.42)

    /// The prefecture boundary. Darker than the slot grey it used to borrow, so
    /// a hairline still reads as a border rather than as a smudge — the line
    /// got thin enough that a pale colour simply disappeared.
    static let boundary = Color(hex: 0x9B9384)

    /// The two progress hues that are not already tokens, both taken from the
    /// §9 prefecture palette so the title screen introduces no new colours.
    /// Green is the same one the mastery ramp climbs through, so a filling bar
    /// and a filling map are visibly the same measurement.
    static let learnedHex: UInt32 = 0xA5D6A7
    static let learned = Color(hex: learnedHex)
    static let collected = Color(hex: 0xCE93D8)
    /// Die-cut border. Every sticker in the app shares this white edge.
    static let dieCut = Color.white

    // MARK: - Card stock

    /// A plain card's board, and the deeper shade at its bottom edge.
    ///
    /// Cool on purpose. キラ is gold foil, and the warm half of the §9
    /// prefecture palette (0xFFCC80, 0xFFF176) passes for gold at card size —
    /// a plain 北海道 card sat beside a キラ and read as the same thing. Taken
    /// from the sea the map already floats in, so no new hue enters the app.
    static let cardBoard     = Color(hex: 0x8AC8E0)
    static let cardBoardDeep = Color(hex: 0x5F9DBE)

    /// Gold foil, as metal rather than as a yellow rectangle: dark where the
    /// stock turns away from the light, blown out where it faces it. Every stop
    /// is opaque — the ramp used to end on a translucent gold and the black
    /// backdrop showed through, which is what made the bottom of a キラ card
    /// look brown instead of bright.
    /// The dark stops stay amber rather than going to true shadow: at 11pt of
    /// border a stop near 0x8A5A10 landed as one brown corner, and brown is not
    /// a shade of gold to a six-year-old.
    static let foilRamp: [Gradient.Stop] = [
        .init(color: Color(hex: 0xA97318), location: 0.00),
        .init(color: Color(hex: 0xF2CE63), location: 0.16),
        .init(color: Color(hex: 0xFFF6D2), location: 0.30),
        .init(color: Color(hex: 0xD9A32B), location: 0.48),
        .init(color: Color(hex: 0xFFEDB0), location: 0.68),
        .init(color: Color(hex: 0xC8871B), location: 0.86),
        .init(color: Color(hex: 0x996612), location: 1.00),
    ]

    /// Silver foil, on the same ramp shape as the gold so the two read as the
    /// same material in two metals — three stars and five stars, not two
    /// unrelated cards.
    static let silverRamp: [Gradient.Stop] = [
        .init(color: Color(hex: 0x8E979F), location: 0.00),
        .init(color: Color(hex: 0xD8DFE5), location: 0.16),
        .init(color: Color(hex: 0xF7FAFC), location: 0.30),
        .init(color: Color(hex: 0xAEB8C0), location: 0.48),
        .init(color: Color(hex: 0xEDF2F6), location: 0.68),
        .init(color: Color(hex: 0xA3ADB5), location: 0.86),
        .init(color: Color(hex: 0x828C94), location: 1.00),
    ]

    /// Rainbow foil, on the same ramp shape as the metals so a rainbow card is
    /// the same material again — one more finish, not a new kind of object.
    /// The hues walk the spectrum while the values keep the foil's dark/bright
    /// alternation; every stop opaque for the same reason as the gold's.
    static let rainbowRamp: [Gradient.Stop] = [
        .init(color: Color(hex: 0xB4557E), location: 0.00),
        .init(color: Color(hex: 0xF6A6C4), location: 0.16),
        .init(color: Color(hex: 0xFFF3C9), location: 0.30),
        .init(color: Color(hex: 0x7FC9A8), location: 0.48),
        .init(color: Color(hex: 0xA8D8F0), location: 0.68),
        .init(color: Color(hex: 0x9A7FD0), location: 0.86),
        .init(color: Color(hex: 0x6B5AA0), location: 1.00),
    ]

    /// Gold as *text*. The token gold is a surface colour — as lettering on
    /// white it washes out, and on the pale-yellow card stock it disappears
    /// outright — so counts that mean gold write in this darker cut of the
    /// same hue, borrowed from the foil ramp's shadow stop.
    static let goldInk = Color(hex: 0xA97318)

    /// The lit edge of cut foil.
    static let foilEdge = Color(hex: 0xFFF6D2)
    static let silverEdge = Color(hex: 0xF7FAFC)
    static let rainbowEdge = Color(hex: 0xEFE3FF)
    /// Light cuts of the two metals, for a surface that carries a tier
    /// without being a full card face — the quiz's card-win banner. Taken
    /// from each ramp's lit stop so the panel reads as the same foil,
    /// caught by the light, rather than as a new colour.
    static let silverStock = Color(hex: 0xEDF2F6)
    static let goldStock = Color(hex: 0xFFEDB0)

    /// Stars on a silver card. Darker than the metal: they sit on the white
    /// panel, where the metal's own tone would disappear.
    static let silverMark = Color(hex: 0x8A939B)
    /// Stars on a rainbow card, on the same terms as the silver mark.
    static let rainbowMark = Color(hex: 0x8A6FC8)

    /// The cut edge of the card — its thickness, seen when it is turned.
    ///
    /// Paper, not stock: what is printed on the face does not run through the
    /// board, and a cut edge shows the core. One colour for all three stocks for
    /// the same reason. It reads as thickness where a darker shade of the stock
    /// itself only read as a shadow.
    static let cardCore = Color(hex: 0xE3D9C6)

    static let stickerEdgeWidth: CGFloat = 3.5
    static let stickerShadow = Color(hex: 0x6B5B4A).opacity(0.28)

    /// Holographic sheen for キラ stickers and キラカード. The same eight
    /// prefecture colours the map already uses, so the shine reads as "these
    /// are your stickers", not as a generic rainbow.
    static var holographic: AngularGradient {
        AngularGradient(colors: prefectureFills + [prefectureFills[0]],
                        center: .center)
    }

    /// The same shine as a straight band, for a surface that tilts: an angular
    /// gradient pinned to the centre would spin rather than slide, which is not
    /// how light moves across a card.
    static var holographicBand: [Color] {
        [.clear] + prefectureFills.map { $0.opacity(0.9) } + [.clear]
    }
}

nonisolated extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// Mixes toward white by `amount` (0 = untouched, 1 = white). Done on the
    /// components rather than with opacity so the result stays opaque and does
    /// not let the sea show through a prefecture.
    init(hex: UInt32, mixedWithWhite amount: Double) {
        let t = min(max(amount, 0), 1)
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value + (1 - value) * t
        }
        self.init(.sRGB, red: channel(16), green: channel(8), blue: channel(0), opacity: 1)
    }
}

/// Rounded gothic. Hiragino Maru Gothic is the only rounded Japanese face
/// present on every iOS device, so it is used directly rather than via a
/// system font descriptor that would fall back to a non-rounded face.
nonisolated enum AppFont {
    static let familyName = "HiraMaruProN-W4"

    static func rounded(_ size: CGFloat) -> Font {
        .custom(familyName, size: size)
    }

    /// Follows Dynamic Type, capped so the quiz chrome cannot push the map off
    /// screen at the largest accessibility sizes.
    static func rounded(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(familyName, size: size, relativeTo: style)
    }

    /// Heavy gothic, for the one place that wants to look printed rather than
    /// hand-drawn: the prefecture band on a card. Hiragino Sans W6 ships on
    /// every iOS device, and the rounded face has no bold weight to reach for.
    /// Everything else stays 丸ゴシック per CLAUDE.md §9.
    static let headingFamilyName = "HiraginoSans-W6"

    static func heading(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(headingFamilyName, size: size, relativeTo: style)
    }
}
