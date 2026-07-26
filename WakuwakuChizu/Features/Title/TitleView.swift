import SwiftUI

/// Home screen. Three destinations and the map attribution required by
/// CLAUDE.md §3.
struct TitleView: View {
    @Environment(AppState.self) private var app
    @Environment(\.textMode) private var mode

    var onStart: () -> Void
    var onMyMap: () -> Void
    var onCardBook: () -> Void
    var onSettings: () -> Void

    var body: some View {
        ZStack {
            AlbumPage()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button { onSettings() } label: { Text("⚙️") }
                        .buttonStyle(CircleIconButtonStyle(diameter: 40))
                        .accessibilityLabel(mode.settings)
                }
                Spacer(minLength: 4)

                Text(mode.appTitleTop)
                    .stickerText(32, relativeTo: .largeTitle, color: Palette.orange,
                                 outlineWidth: 3.5)
                    .rotationEffect(.degrees(-4))
                Text(mode.appTitleMain)
                    .stickerText(46, relativeTo: .largeTitle, outlineWidth: 4)
                    .rotationEffect(.degrees(1.5))

                miniMap
                    .frame(maxHeight: 260)
                    .padding(.vertical, 10)

                progressLine

                Spacer(minLength: 12)

                VStack(spacing: 14) {
                    Button(mode.play) { onStart() }
                        .buttonStyle(BouncyButtonStyle(horizontalPadding: 52,
                                                       verticalPadding: 16,
                                                       fontSize: 24))
                    HStack(spacing: 12) {
                        Button(mode.myMap) { onMyMap() }
                            .buttonStyle(.bouncy(Palette.teal, fontSize: 17))
                        Button(mode.cardBook) { onCardBook() }
                            .buttonStyle(.bouncy(Palette.teal, fontSize: 17))
                    }
                }

                Spacer(minLength: 16)

                Text("ちずデータ: Global Map Japan (国土地理院) をもとに簡略化")
                    .font(AppFont.rounded(10, relativeTo: .caption2))
                    .foregroundStyle(Palette.ink.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
            }
            .padding(.horizontal, 24)
        }
    }

    /// The child's own progress, as the title art.
    private var miniMap: some View {
        PrefectureMapView(
            mapData: app.mapData,
            codes: Array(1...47),
            appearance: { MasteryStyle.appearance(for: $0.code, save: app.save.data) })
        .aspectRatio(PrefectureGeometry.aspectRatio(of: app.mapData.prefectures),
                     contentMode: .fit)
        .allowsHitTesting(false)
    }

    /// Three counts, each with how far along it is.
    ///
    /// A bare number answers "how many" but not "how close am I", which is the
    /// question a collection actually raises. The bar carries that.
    ///
    /// These looked pressable long before they were, which was the original
    /// complaint. The answer turned out not to be making them look inert but
    /// making them do the obvious thing: each one now opens the screen where
    /// the things it counts can be looked at.
    private var progressLine: some View {
        HStack(spacing: 10) {
            tally("🗾", app.save.data.mastery.values.filter { $0 > 0 }.count, 47,
                  mode.isKids ? "けん" : "県", Palette.learned, onMyMap)
            // Shiny *cards*, not キラキラ prefectures. Both were called キラ and
            // the map already counts the prefectures on its own screen; here,
            // between a prefecture count and a card count, out of 141 says
            // plainly which one this is.
            tally("✨", app.save.data.shinyCardCount, max(app.cards.count, 1), "キラ",
                  Palette.gold, onCardBook)
            tally("🃏", app.save.data.totalOwnedCards, max(app.cards.count, 1), "カード",
                  Palette.collected, onCardBook)
        }
    }

    /// Each count opens the place its things live: the two prefecture counts go
    /// to the map, the card count to the book. A number a child is proud of
    /// should lead somewhere — and every one of these was already the answer to
    /// "where can I see them?".
    private func tally(_ emoji: String, _ have: Int, _ total: Int,
                       _ label: String, _ tint: Color,
                       _ action: @escaping () -> Void) -> some View {
        Button(action: action) { tallyFace(emoji, have, total, label, tint) }
            .buttonStyle(TallyPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(label) \(have) / \(total)")
            .accessibilityAddTraits(.isButton)
    }

    private func tallyFace(_ emoji: String, _ have: Int, _ total: Int,
                           _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 5) {
            Text(emoji)
                .font(.system(size: 15))
                .frame(width: 28, height: 28)
                .background(Circle().fill(tint.opacity(0.28)))

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                // Verbatim: SwiftUI's localised interpolation groups integers,
                // and a child reading 「1,120」 has to parse a comma first.
                Text(verbatim: "\(have)")
                    .font(AppFont.rounded(21, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .monospacedDigit()
                Text(verbatim: "/\(total)")
                    .font(AppFont.rounded(11, relativeTo: .caption2))
                    .foregroundStyle(Palette.ink.opacity(0.4))
                    .monospacedDigit()
            }

            Text(label)
                .font(AppFont.rounded(11, relativeTo: .caption2))
                .foregroundStyle(Palette.ink.opacity(0.55))

            ProgressMeter(fraction: total > 0 ? Double(have) / Double(total) : 0, tint: tint)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white)
                // A soft ambient shadow, not the solid offset one the buttons
                // use. The difference is what says "sitting on the page" rather
                // than "waiting to be pushed".
                .shadow(color: Palette.ink.opacity(0.06), radius: 5, y: 2)
        )
    }
}

/// Presses the card into the page, the same way the stage sheets do.
private struct TallyPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(duration: 0.18), value: configuration.isPressed)
    }
}

/// How far along one count is.
///
/// Rounded rather than square, and it keeps a visible sliver at zero: an empty
/// track reads as broken, while a sliver reads as "not started yet", which is
/// the honest and kinder version of the same fact (CLAUDE.md §12).
private struct ProgressMeter: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geo in
            let clamped = min(max(fraction, 0), 1)
            let width = max(geo.size.width * clamped, 6)
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.ink.opacity(0.08))
                Capsule().fill(tint).frame(width: width)
            }
        }
        .frame(height: 6)
    }
}

/// Mastery ramp shared by the title art and the my-map screen (CLAUDE.md §5),
/// expressed as sticker states: an empty slot fills in, then goes キラ.
enum MasteryStyle {
    /// One ramp, not 47.
    ///
    /// This used to tint each prefecture with its own hue from the §9 palette,
    /// which made the legend a lie: it showed four greens while the map showed
    /// a rainbow, and no swatch could stand for eight hues at once. Colour here
    /// answers "how well do I know this one", so it carries exactly that and
    /// nothing else. Prefecture identity is still colour-coded in the quiz and
    /// on the stage thumbnails, where telling neighbours apart is the job.
    ///
    /// The legend draws from this same function, so the two cannot drift again.
    ///
    /// CLAUDE.md §5 asked for 33% / 73% / solid. On the real map 33% sat close
    /// enough to the unlearned grey that a child could not tell at a glance
    /// which prefectures they had answered.
    static func fill(level: Int) -> Color {
        switch level {
        case ..<1: Palette.unlearned
        case 1: Color(hex: Palette.learnedHex, mixedWithWhite: 0.42)
        case 2: Color(hex: Palette.learnedHex, mixedWithWhite: 0.18)
        default: Palette.gold
        }
    }

    /// Only the fill moves as a prefecture is learned.
    ///
    /// Answered prefectures used to get the white die-cut edge and the lift
    /// that goes with it, which cut the country into loose pieces floating over
    /// the sea while the rest stayed printed flat — the border between 東北 and
    /// 関東 became a seam. The outline is now the same printed edge at every
    /// level, so progress reads as colour spreading across one whole map.
    static func appearance(for code: Int, save: SaveData) -> PrefectureAppearance {
        let level = save.masteryLevel(of: code)
        return PrefectureAppearance(fill: fill(level: level),
                                    stroke: Palette.boundary,
                                    isSparkling: level >= GameRules.maxMastery,
                                    isStuck: false)
    }

    static func label(level: Int) -> String {
        switch level {
        case ..<1: "まだ"
        case 1: "すこし おぼえた"
        case 2: "おぼえてきた"
        default: "キラキラ"
        }
    }
}
