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

    /// The album page a sticker is stuck onto.
    static let page = Color(hex: 0xFFFBF2)
    /// Outline of a slot no sticker has been earned for yet.
    static let emptySlot = Color(hex: 0xD8D2C4)
    /// Die-cut border. Every sticker in the app shares this white edge.
    static let dieCut = Color.white

    static let stickerEdgeWidth: CGFloat = 3.5
    static let stickerShadow = Color(hex: 0x6B5B4A).opacity(0.28)

    /// Holographic sheen for キラ stickers and キラカード. The same eight
    /// prefecture colours the map already uses, so the shine reads as "these
    /// are your stickers", not as a generic rainbow.
    static var holographic: AngularGradient {
        AngularGradient(colors: prefectureFills + [prefectureFills[0]],
                        center: .center)
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
}
