import SwiftUI

/// Home screen. Three destinations and the map attribution required by
/// CLAUDE.md §3.
struct TitleView: View {
    @Environment(AppState.self) private var app
    @Environment(\.textMode) private var mode
    @Environment(\.horizontalSizeClass) private var hSize

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
                // The plaque-free logo floats over the sea and the top of the
                // country. Sharing this space gives the map the width and
                // height the old separate logo row used to consume.
                miniMap
                    // On iPad the −52 bleed would inflate the sea to 756pt
                    // and push the tallies onto the Okinawa inset; 680 keeps
                    // the composition. iPhone proposals never reach the cap.
                    .frame(maxWidth: 680)
                    .padding(.top, 64)
                    .overlay(alignment: .top) {
                        // Two ceilings, both set by the 1000px art, not by
                        // style: 320pt is 960px on a 3x phone, 420pt is
                        // 840px on a 2x iPad — each the widest that still
                        // renders sharp on its display.
                        Image("TitleLogoFloating")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: hSize == .regular ? 420 : 320)
                            .accessibilityLabel(
                                "\(mode.appTitleTop) \(mode.appTitleMain)"
                            )
                            .accessibilityAddTraits(.isHeader)
                    }
                    .layoutPriority(1)
                    // −52 goes past cancelling the column's 24pt margin: the
                    // frame runs 28pt off each screen edge, trading the art's
                    // transparent side margins for a visibly larger country.
                    .padding(.horizontal, -52)
                    .padding(.vertical, 2)
                    // The sea keeps its full painted height, but the layout
                    // hands part of it back, so the tallies and あそぶ sit on
                    // the water (drawn later in the VStack = drawn on top).
                    // Only ever water may go under them: at −170 the tallies
                    // covered the Okinawa inset frame, and hiding a real map
                    // element is where "the lower sea is margin" stops being
                    // true. −95/−100 clears the inset's bottom edge on each
                    // size class with water to spare.
                    .padding(.bottom, hSize == .regular ? -100 : -75)

                progressLine

                Spacer(minLength: 8)

                // あそぶ is the only labelled button left. The two tallies
                // above already open the my-map and the card book; a second,
                // smaller pair of doors to the same two rooms just competed
                // with the one door that matters.
                Button(action: onStart) {
                    Image(mode.isKids ? "TitlePlayButton" : "TitlePlayButtonAdult")
                        .resizable()
                        .scaledToFit()
                        .accessibilityHidden(true)
                }
                .buttonStyle(TitleArtworkButtonStyle())
                .accessibilityLabel(mode.play)
                .frame(maxWidth: 256)

                // Flexible again now that the map overlap keeps the leftover
                // small: on a phone there is almost nothing to distribute,
                // and on iPad splitting it above and below あそぶ reads as
                // album margins instead of one dead block over the footer.
                Spacer(minLength: 12)

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

            // Both discs live in the bottom corners, beside the footer: the
            // top band belongs to the logo, and these are parent-facing
            // controls — down by the small print is exactly their register.
            // A symbol on album paper, not the ⚙️ emoji: the emoji ships its
            // own steel greys on a stark white disc, the one square inch of
            // this screen that ignored the palette.
            Button { onSettings() } label: { Image(systemName: "gearshape.fill") }
                .buttonStyle(CircleIconButtonStyle(
                    background: Palette.page,
                    foreground: Palette.ink.opacity(0.62),
                    diameter: 40))
                .accessibilityLabel(mode.settings)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .bottomTrailing)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .pageColumn()

            // The theme's mute, on the corner the gear left free. It lives
            // here rather than only in settings because the moment someone
            // wants the song off is the moment it is playing — and it writes
            // through Settings.musicEnabled, so the choice survives relaunch
            // and the settings sheet shows the same state.
            Button {
                app.save.updateSettings { $0.musicEnabled.toggle() }
            } label: {
                Image(systemName: app.save.data.settings.musicEnabled
                      ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
                .buttonStyle(CircleIconButtonStyle(
                    background: Palette.page,
                    foreground: Palette.ink.opacity(0.62),
                    diameter: 40))
                // The label names the action a press performs, not the state,
                // so muting and unmuting read as different buttons.
                .accessibilityLabel(app.save.data.settings.musicEnabled
                                    ? mode.musicStop : mode.musicPlay)
                .frame(maxWidth: .infinity, maxHeight: .infinity,
                       alignment: .bottomLeading)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .pageColumn()
        }
    }

    /// The child's own progress, as the title art.
    private var miniMap: some View {
        GeometryReader { geo in
            ZStack {
                // The sea, waves, compass and sparkles are decorative artwork.
                // The country itself deliberately is not baked into this image,
                // so its 47 live fills can keep changing.
                Image("TitleMapBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                PrefectureMapView(
                    mapData: app.mapData,
                    codes: Array(1...47),
                    appearance: {
                        MasteryStyle.appearance(for: $0.code, save: app.save.data)
                    }
                )
                .aspectRatio(
                    PrefectureGeometry.aspectRatio(of: app.mapData.prefectures),
                    contentMode: .fit
                )
                .frame(width: geo.size.width * 0.93,
                       height: geo.size.height * 0.86)
                .position(x: geo.size.width * 0.50,
                          y: geo.size.height * 0.50)
                // A single die-cut edge and lift around the live country. The
                // fill colours remain untouched inside that silhouette.
                .compositingGroup()
                .shadow(color: .white.opacity(0.98), radius: 4)
                .shadow(color: Palette.ink.opacity(0.18), radius: 2, y: 3)
            }
        }
        // 0.8 = the backdrop's own 800×1000. Any other ratio means
        // scaledToFill crops the artwork — at 0.95 the top and bottom sixth
        // of the sea (and the blob's soft edge) were silently cut off.
        .aspectRatio(0.8, contentMode: .fit)
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
                  mode.learnedPrefectures, Palette.learned, hint: mode.myMap,
                  action: onMyMap)
            // Opens the book unfiltered now rather than straight onto the キラ
            // cards, which the third tile used to do. One tile cannot lead two
            // places, and the book's own ✨ chip is the first thing above the
            // grid — one tap further, in the room where the cards already are.
            tally("TitleCardsHUD", app.save.data.totalOwnedCards, max(app.cards.count, 1),
                  mode.ownedCards, Palette.collected,
                  note: TallyNote(emoji: "✨", label: mode.sparklingCards,
                                  count: app.save.data.specialCardCount),
                  hint: mode.viewCards) {
                onCardBook(.all)
            }
        }
        // Holds the row to its tallest tile instead of letting the flexible
        // heights above stretch it down the screen. 330 rather than 360 on a
        // phone: every point of tile height is a point taken from the map
        // above. The iPad's wider stage reads the same tiles as small print,
        // so it gets a wider row.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: hSize == .regular ? 380 : 330)
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
                       hint: String = "",
                       action: @escaping () -> Void) -> some View {
        Button(action: action) { tallyFace(artwork, have, total, label, tint, note) }
            .buttonStyle(TallyPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(note.map { "\(label) \(have) / \(total)。\($0.label) \($0.count)" }
                                ?? "\(label) \(have) / \(total)")
            // Since the labelled マイマップ/カードをみる buttons left the
            // screen, the hint is where VoiceOver learns each tile is also
            // the door to its collection.
            .accessibilityHint(hint)
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
