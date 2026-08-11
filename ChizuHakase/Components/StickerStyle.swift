import SwiftUI

/// The app's one visual idea: everything the child earns is a **die-cut
/// sticker** on an album page.
///
/// It is not decoration bolted on top — the mechanics already work this way.
/// Mastery 0…3 is an empty slot filling in, level 3 is described in CLAUDE.md §5
/// as a gold-edged shape that shimmers, and the collectibles are already called
/// キラカード. Naming that out loud and drawing it consistently is what makes
/// the screens feel like one object instead of five.
///
/// Three treatments, used everywhere and nowhere else:
///   - `stickerText`  fattened, outlined lettering
///   - `stickerCard`  a panel with a white die-cut edge and a lifted shadow
///   - `holographic`  the キラ sheen
nonisolated enum Sticker {
    static let cornerRadius: CGFloat = 22
    static let lift: CGFloat = 3
}

// MARK: - Lettering

/// Hiragino Maru Gothic ships in exactly one weight (W4), so CLAUDE.md §9's
/// "Bold 以上" cannot be satisfied by asking for a heavier face — there isn't
/// one. Outlining the round face fattens it and makes it read as cut-out
/// lettering.
///
/// Two rings, not one. A white-only outline is invisible against the cream
/// page and all it contributes is a grey smear from its own shadow; the ink
/// keyline outside the white is what defines the letter and lets the treatment
/// work on paper, on a colour chip or over the map.
///
/// Used sparingly — the wordmark and a couple of headings. Body copy stays
/// plain, because outlined text at reading size is harder to read, not easier.
struct StickerTextModifier: ViewModifier {
    var size: CGFloat
    var relativeTo: Font.TextStyle
    var color: Color
    var outline: Color
    var outlineWidth: CGFloat
    var keyline: Color

    func body(content: Content) -> some View {
        content
            .font(AppFont.rounded(size, relativeTo: relativeTo))
            .foregroundStyle(color)
            .background { ring(color: outline, width: outlineWidth, content: content) }
            .background { ring(color: keyline, width: outlineWidth + 1.4, content: content) }
    }

    private func ring(color: Color, width: CGFloat, content: Content) -> some View {
        ZStack {
            ForEach(Array(Self.offsets.enumerated()), id: \.offset) { _, unit in
                content
                    .font(AppFont.rounded(size, relativeTo: relativeTo))
                    .foregroundStyle(color)
                    .offset(x: unit.x * width, y: unit.y * width)
            }
        }
    }

    /// Twelve copies: eight leaves visible flat spots on round kana at the
    /// widths this is used at.
    private static let offsets: [CGPoint] = (0..<12).map { i in
        let angle = Double(i) / 12 * 2 * .pi
        return CGPoint(x: cos(angle), y: sin(angle))
    }
}

extension View {
    /// Cut-out lettering. Reserve for the wordmark and stage names — body copy
    /// stays plain so it remains readable.
    func stickerText(_ size: CGFloat,
                     relativeTo: Font.TextStyle = .body,
                     color: Color = Palette.ink,
                     outline: Color = .white,
                     outlineWidth: CGFloat = 3,
                     keyline: Color = Palette.ink.opacity(0.16)) -> some View {
        modifier(StickerTextModifier(size: size, relativeTo: relativeTo, color: color,
                                     outline: outline, outlineWidth: outlineWidth,
                                     keyline: keyline))
    }

    /// A number or short label on its own coloured chip. This is where scores
    /// and counts go — a filled sticker is legible where outlined text on the
    /// page is not.
    func stickerPill(_ tint: Color = Palette.orange) -> some View {
        self
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
            .overlay { Capsule().strokeBorder(.white, lineWidth: 2.5) }
            .shadow(color: Palette.stickerShadow, radius: 0, y: 2)
    }

    /// A panel cut out of the album page: white edge, lifted off the paper.
    func stickerCard(fill: Color = .white,
                     cornerRadius: CGFloat = Sticker.cornerRadius,
                     edge: CGFloat = Palette.stickerEdgeWidth,
                     isHolographic: Bool = false) -> some View {
        modifier(StickerCardModifier(fill: fill, cornerRadius: cornerRadius,
                                     edge: edge, isHolographic: isHolographic))
    }
}

struct StickerCardModifier: ViewModifier {
    var fill: Color
    var cornerRadius: CGFloat
    var edge: CGFloat
    var isHolographic: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
                    .overlay {
                        if isHolographic {
                            // Normal blend, not plusLighter: over a pale card
                            // plusLighter just drives everything to white and
                            // the colour bands that make it read as holographic
                            // disappear.
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .fill(Palette.holographic)
                                .opacity(0.30)
                        }
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isHolographic ? Palette.gold : Palette.dieCut,
                                  lineWidth: isHolographic ? edge : edge)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Palette.stickerShadow, radius: 0, y: Sticker.lift)
            .shadow(color: Palette.stickerShadow.opacity(0.4), radius: 6, y: 4)
    }
}

// MARK: - Text mode

private struct TextModeKey: EnvironmentKey {
    static let defaultValue: TextMode = .kids
}

extension EnvironmentValues {
    /// Child or adult wording. Injected once at the root from the save store.
    var textMode: TextMode {
        get { self[TextModeKey.self] }
        set { self[TextModeKey.self] = newValue }
    }
}

// MARK: - Layout helpers

nonisolated extension DynamicTypeSize {
    /// Card grids drop to two columns at accessibility sizes; three columns of
    /// wrapped kana is unreadable once the text is that large.
    var cardColumns: Int { isAccessibilitySize ? 2 : 3 }
}

// MARK: - The page

/// The album paper every screen sits on.
///
/// A faint dot grid, nothing more. It has to read as paper at a glance and then
/// get out of the way — the stickers are the subject, and a louder texture
/// would fight the map for attention.
struct AlbumPage: View {
    var body: some View {
        Palette.page
            .overlay {
                Canvas { context, size in
                    let spacing: CGFloat = 22
                    let dot = CGSize(width: 2.4, height: 2.4)
                    let colour = GraphicsContext.Shading.color(Palette.ink.opacity(0.055))
                    var y: CGFloat = spacing / 2
                    while y < size.height {
                        var x: CGFloat = spacing / 2
                        while x < size.width {
                            context.fill(Path(ellipseIn: CGRect(origin: CGPoint(x: x, y: y),
                                                                size: dot)), with: colour)
                            x += spacing
                        }
                        y += spacing
                    }
                }
            }
            .ignoresSafeArea()
    }
}

// MARK: - Confetti

/// Paper confetti for a cleared stage (CLAUDE.md §9 names 紙吹雪 among the
/// effects Reduce Motion must switch off, so it belongs in the app).
///
/// Drawn in a single `Canvas` rather than as N views: one draw call keeps the
/// result screen smooth while the stars are also animating.
struct ConfettiView: View {
    var pieceCount = 44
    var duration: Double = 2.6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Piece {
        let x: Double, delay: Double, drift: Double, spin: Double
        let size: Double, hue: Color, wobble: Double
    }

    private let pieces: [Piece]

    init(pieceCount: Int = 44, duration: Double = 2.6, seed: UInt64 = 20_260_725) {
        self.pieceCount = pieceCount
        self.duration = duration
        var rng = SeededSequence(seed: seed)
        self.pieces = (0..<pieceCount).map { _ in
            Piece(x: rng.next01(),
                  delay: rng.next01() * 0.5,
                  drift: rng.next01() * 0.24 - 0.12,
                  spin: rng.next01() * 6 - 3,
                  size: 7 + rng.next01() * 7,
                  hue: Palette.prefectureFills[Int(rng.next01() * 7.99)],
                  wobble: rng.next01() * 2 * .pi)
        }
    }

    var body: some View {
        if reduceMotion {
            // Motion is the whole effect; there is no static version worth
            // showing, so it simply does not appear.
            Color.clear.frame(height: 0)
        } else {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let start = Self.epoch
                    let elapsed = now - start
                    for piece in pieces {
                        let t = (elapsed - piece.delay) / duration
                        guard t > 0, t < 1 else { continue }
                        let y = t * (size.height + 60) - 30
                        let x = piece.x * size.width
                            + sin(t * 6 + piece.wobble) * 22
                            + piece.drift * size.width * t
                        let rect = CGRect(x: -piece.size / 2, y: -piece.size / 3,
                                          width: piece.size, height: piece.size * 0.66)
                        var copy = context
                        copy.translateBy(x: x, y: y)
                        copy.rotate(by: .radians(t * piece.spin * .pi * 2))
                        copy.opacity = t > 0.82 ? (1 - t) / 0.18 : 1
                        copy.fill(Path(roundedRect: rect, cornerRadius: 1.5),
                                  with: .color(piece.hue))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }

    /// Fixed origin so every piece shares one clock.
    private static let epoch = Date.timeIntervalSinceReferenceDate
}

/// Tiny deterministic sequence so confetti layout is identical run to run —
/// keeps screenshots reproducible without pulling in a generator protocol.
private struct SeededSequence {
    private var state: UInt64
    init(seed: UInt64) { state = seed | 1 }
    mutating func next01() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((state >> 11) & 0xFFFFF) / Double(0xFFFFF)
    }
}

#Preview("sticker vocabulary") {
    ZStack {
        Palette.page.ignoresSafeArea()
        VStack(spacing: 26) {
            Text("めざせ! ちずはかせ").stickerText(30, relativeTo: .largeTitle)
            Text("1120").stickerText(46, relativeTo: .largeTitle, color: Palette.orange)
            HStack(spacing: 14) {
                Text("ふつう").padding(20).stickerCard()
                Text("キラ").padding(20).stickerCard(isHolographic: true)
            }
        }
        ConfettiView()
    }
}
