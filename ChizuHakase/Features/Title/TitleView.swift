import SwiftUI

/// Home screen. Three destinations and the map attribution required by
/// CLAUDE.md §3.
struct TitleView: View {
    @Environment(AppState.self) private var app
    @Environment(\.textMode) private var mode

    var onStart: () -> Void
    var onMyMap: () -> Void
    var onCardBook: (CardFilter) -> Void
    var onSettings: () -> Void

    /// MARKETING_VERSION from project.yml, read through the generated
    /// Info.plist — never hardcoded here, or the footer and the App Store
    /// would drift apart on the first release that forgets one of them.
    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var body: some View {
        ZStack {
            AlbumPage()
            VStack(spacing: 0) {
                // The brand mark is artwork, shared by both text modes;
                // VoiceOver still gets words, not a picture, via TextMode.
                Image("TitleLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 300)
                    .padding(.top, 4)
                    .accessibilityLabel("\(mode.appTitleTop) \(mode.appTitleMain)")
                    .accessibilityAddTraits(.isHeader)

                miniMap
                    .frame(maxHeight: 380)
                    .layoutPriority(1)
                    .padding(.vertical, 8)

                progressLine

                Spacer(minLength: 12)

                VStack(spacing: 10) {
                    Button(action: onStart) {
                        Image(mode.isKids ? "TitlePlayButton" : "TitlePlayButtonAdult")
                            .resizable()
                            .scaledToFit()
                            .accessibilityHidden(true)
                    }
                    .buttonStyle(TitleArtworkButtonStyle())
                    .accessibilityLabel(mode.play)
                    .frame(maxWidth: 256)

                    HStack(spacing: 10) {
                        Button(action: onMyMap) {
                            Image("TitleMapButton")
                                .resizable()
                                .scaledToFit()
                                .accessibilityHidden(true)
                        }
                        .buttonStyle(TitleArtworkButtonStyle())
                        .accessibilityLabel(mode.myMap)

                        Button(action: { onCardBook(.all) }) {
                            Image(mode.isKids ? "TitleCardButton" : "TitleCardButtonAdult")
                                .resizable()
                                .scaledToFit()
                                .accessibilityHidden(true)
                        }
                        .buttonStyle(TitleArtworkButtonStyle())
                        .accessibilityLabel(mode.viewCards)
                    }
                }
                .frame(maxWidth: 320)

                Spacer(minLength: 16)

                VStack(spacing: 2) {
                    Text("ちずデータ: Global Map Japan (国土地理院) をもとに簡略化")
                        .font(AppFont.rounded(10, relativeTo: .caption2))
                        .foregroundStyle(Palette.ink.opacity(0.42))
                        .multilineTextAlignment(.center)
                    if let version {
                        // For the parent writing a support mail, not for the
                        // child: the one string that says which build this is.
                        Text(verbatim: "v\(version)")
                            .font(AppFont.rounded(9, relativeTo: .caption2))
                            .foregroundStyle(Palette.ink.opacity(0.32))
                            .accessibilityLabel("バージョン \(version)")
                    }
                }
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 24)
            .pageColumn()

            // The gear floats over the page corner instead of owning a row of
            // the column — that row's 44pt was the map's missing headroom. The
            // logo underneath keeps its transparent corner there, so the two
            // never visually collide.
            Button { onSettings() } label: { Text("⚙️") }
                .buttonStyle(CircleIconButtonStyle(diameter: 40))
                .accessibilityLabel(mode.settings)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .topTrailing)
                .padding(.horizontal, 24)
                .pageColumn()
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
    /// Two tallies, because there are two collections: the country and the
    /// cards.
    ///
    /// The silver-and-up count used to be a third tile of its own, and out of
    /// three tiles it was the one nobody could place. It shares a denominator
    /// with the card count and is a *subset* of it, but sitting side by side at
    /// equal weight the two read as unrelated collections — and 「5/141」 next
    /// to 「38/141」 gives a child no way to see that the five are among the
    /// thirty-eight. Inside the card tile the nesting is the layout.
    private var progressLine: some View {
        HStack(spacing: 10) {
            // 「おぼえた」 is claimed at the top of the mastery ladder, not on
            // the first clean answer — counting first answers filled the bar
            // to 47/47 while the map was still mostly green, and a full meter
            // over an unfinished map called the child done when they were not.
            tally("TitleLearnedHUD", app.save.data.sparklingPrefectureCount, 47,
                  mode.learnedPrefectures, Palette.learned, action: onMyMap)
            // Opens the book unfiltered now rather than straight onto the キラ
            // cards, which the third tile used to do. One tile cannot lead two
            // places, and the book's own ✨ chip is the first thing above the
            // grid — one tap further, in the room where the cards already are.
            tally("TitleCardsHUD", app.save.data.totalOwnedCards, max(app.cards.count, 1),
                  mode.ownedCards, Palette.collected,
                  note: TallyNote(emoji: "✨", label: mode.sparklingCards,
                                  count: app.save.data.specialCardCount)) {
                onCardBook(.all)
            }
        }
        // Holds the row to its tallest tile instead of letting the flexible
        // heights above stretch it down the screen.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 360)
    }

    /// A second count that belongs *inside* the first.
    ///
    /// Only for genuine subsets — drawn under the meter, in the tile whose
    /// number it is part of. Anything that is not a subset gets its own tile.
    private struct TallyNote {
        let emoji: String
        let label: String
        let count: Int

        var text: String { "\(emoji) \(label) \(count)" }
    }

    /// Each count opens the place its things live: the two prefecture counts go
    /// to the map, the card count to the book. A number a child is proud of
    /// should lead somewhere — and every one of these was already the answer to
    /// "where can I see them?".
    private func tally(_ artwork: String, _ have: Int, _ total: Int,
                       _ label: String, _ tint: Color,
                       note: TallyNote? = nil,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) { tallyFace(artwork, have, total, label, tint, note) }
            .buttonStyle(TallyPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(note.map { "\(label) \(have) / \(total)。\($0.label) \($0.count)" }
                                ?? "\(label) \(have) / \(total)")
            .accessibilityAddTraits(.isButton)
    }

    private func tallyFace(_ artwork: String, _ have: Int, _ total: Int,
                           _ label: String, _ tint: Color,
                           _ note: TallyNote?) -> some View {
        GeometryReader { geo in
            ZStack {
                // The frame, corner ornaments and collection icon are artwork;
                // every value laid over it remains live SwiftUI content.
                Image(artwork)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        // Verbatim: SwiftUI's localised interpolation groups
                        // integers, and a child reading 「1,120」 has to parse a
                        // comma first.
                        Text(verbatim: "\(have)")
                            .font(AppFont.rounded(23, relativeTo: .title3))
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: "/\(total)")
                            .font(AppFont.rounded(11, relativeTo: .caption2))
                            .foregroundStyle(Palette.ink.opacity(0.48))
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    Text(label)
                        .font(AppFont.rounded(11, relativeTo: .caption2))
                        .foregroundStyle(Palette.ink.opacity(0.78))
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                }
                .frame(width: geo.size.width * 0.53)
                .position(x: geo.size.width * 0.67,
                          y: geo.size.height * 0.34)

                ProgressMeter(
                    fraction: total > 0 ? Double(have) / Double(total) : 0,
                    tint: tint
                )
                .frame(width: geo.size.width * 0.80,
                       height: max(8, geo.size.height * 0.085))
                .position(x: geo.size.width * 0.52,
                          y: geo.size.height * 0.69)

                // One Text rather than an HStack of three, so the note remains
                // one readable phrase while its count changes.
                if let note {
                    Text(verbatim: note.text)
                        .font(AppFont.rounded(10, relativeTo: .caption2))
                        .foregroundStyle(Palette.ink.opacity(0.72))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                        .frame(width: geo.size.width * 0.72)
                        .position(x: geo.size.width * 0.57,
                                  y: geo.size.height * 0.84)
                }
            }
        }
        .aspectRatio(800 / 483, contentMode: .fit)
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
                Capsule()
                    .fill(.white.opacity(0.75))
                    .overlay {
                        Capsule().stroke(Palette.ink.opacity(0.25), lineWidth: 1)
                    }
                Capsule()
                    .fill(tint)
                    .overlay {
                        Capsule().stroke(.white.opacity(0.45), lineWidth: 1)
                    }
                    .frame(width: width)
                    .padding(2)
            }
        }
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
    /// Four visual states for a five-level ladder: grey, light green (1–2),
    /// deep green (3–4), gold. Six swatches a child must tell apart is not a
    /// legend, and greens 14% of white apart are not tellable on a map — the
    /// extra levels slow the climb, they do not need their own colours.
    ///
    /// CLAUDE.md §5 originally asked for 33% / 73% / solid. On the real map 33%
    /// sat close enough to the unlearned grey that a child could not tell at a
    /// glance which prefectures they had answered.
    static func fill(level: Int) -> Color {
        switch level {
        case ..<1: Palette.unlearned
        case 1...2: Color(hex: Palette.learnedHex, mixedWithWhite: 0.42)
        case 3...4: Color(hex: Palette.learnedHex, mixedWithWhite: 0.18)
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
        case 1...2: "すこし おぼえた"
        case 3...4: "おぼえてきた"
        default: "おぼえた"
        }
    }
}
