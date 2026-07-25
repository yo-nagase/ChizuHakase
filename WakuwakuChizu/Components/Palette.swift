import SwiftUI

/// Design tokens from CLAUDE.md §9.
enum Palette {
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
    static let prefectureFills = [
        Color(hex: 0xFF8A80), Color(hex: 0xFFCC80), Color(hex: 0xFFF176), Color(hex: 0xA5D6A7),
        Color(hex: 0x81D4FA), Color(hex: 0xCE93D8), Color(hex: 0xF48FB1), Color(hex: 0x80CBC4),
    ]

    static func fill(for prefectureCode: Int) -> Color {
        prefectureFills[((prefectureCode % prefectureFills.count) + prefectureFills.count)
                        % prefectureFills.count]
    }

    static var seaGradient: LinearGradient {
        LinearGradient(colors: sea, startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Rounded gothic. Hiragino Maru Gothic is the only rounded Japanese face
/// present on every iOS device, so it is used directly rather than via a
/// system font descriptor that would fall back to a non-rounded face.
enum AppFont {
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
