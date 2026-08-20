import SwiftUI

/// Home screen — the album's two pages (にほん ⇄ せかい), and the map
/// attribution required by CLAUDE.md §3.
///
/// The whole app's one japan/world branch lives here (design doc §2): the page
/// open in front of the child IS the book every door below opens into, which
/// is why the pager binds straight to RootView's session `atlasKey` instead of
/// keeping a page state of its own to sync.
struct TitleView: View {
    @Environment(AppState.self) private var app
    @Environment(\.textMode) private var mode
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.verticalSizeClass) private var vSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The open ちずちょう — `SaveData.japanAtlas` / `worldAtlas`, owned by
    /// RootView (it is session state shaped like `quizMode`).
    @Binding var atlasKey: String

    var onStart: () -> Void
    var onMyMap: () -> Void
    var onCardBook: (CardFilter) -> Void
    var onSettings: () -> Void

    /// Whether the world page has ever been on (or dragged onto) the glass.
    /// Building the world page is what first reads `app.world` — a synchronous
    /// WorldShapes decode AppState defers on purpose — so until this flips the
    /// slot holds a blank sheet and a japan-only launch never pays for the
    /// second book (P6 引き継ぎ 5).
    @State private var worldPageTouched = false

    /// MARKETING_VERSION from project.yml, read through the generated
    /// Info.plist — never hardcoded here, or the footer and the App Store
    /// would drift apart on the first release that forgets one of them.
    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// iPad must support landscape. Keeping the portrait map width there
    /// makes its 5:4 painted sea taller than the entire safe area, so the CTA
    /// falls below the screen. The wide-short presentation keeps the same
    /// single-column hierarchy, just at a compact scale.
    private var isShort: Bool { vSize == .compact }

    var body: some View {
        ZStack {
            AlbumPage()

            // The two pages turn by swipe *and* by the page-edge tabs — swipe
            // alone is undiscoverable at five (design doc §2). No page dots:
            // the tabs already say, in words, that there is another page and
            // what is on it.
            TabView(selection: $atlasKey) {
                albumPage(for: app.japan,
                          learnedLabel: mode.learnedPrefectures,
                          turn: PageTurn(target: SaveData.worldAtlas,
                                         label: mode.toWorldAtlas,
                                         onTrailingEdge: true))
                    .tag(SaveData.japanAtlas)

                worldPage
                    .tag(SaveData.worldAtlas)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Both discs live in the bottom corners, beside the footer: the
            // top band belongs to the logo, and these are parent-facing
            // controls — down by the small print is exactly their register.
            // They sit *outside* the pager because they are whole-album
            // controls (design doc §2: 設定・音はページに属さない) — turning
            // the page must not move them.
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

    // MARK: - Pages

    /// The world page's slot. Its real content is built only once the page is
    /// visible or being pulled on — a launch that stays on にほん never
    /// triggers the world decode (P6 引き継ぎ 5; verified by instrumenting
    /// `Atlas.loadWorld`: the pager lays both slots out at launch, so building
    /// eagerly here would put the load back on every start).
    ///
    /// The tab's flip moves `atlasKey` first, so a tap builds the page as the
    /// turn begins, and a launch restored onto this page builds it in its
    /// first frame. A swipe is caught by watching the slot's global x — not
    /// `onAppear`, which the pager can fire for slots that are laid out but
    /// offscreen: at rest this slot sits exactly one screen to the side and
    /// its x never moves (verified over repeated launches), so the first
    /// drag frame is a signal appearance cannot give. Should a drag ever slip
    /// past unreported, the swipe's landing still commits the selection and
    /// builds the page — the gate can only delay the build, never lose it.
    @ViewBuilder
    private var worldPage: some View {
        if worldPageTouched || atlasKey == SaveData.worldAtlas {
            albumPage(for: app.world,
                      learnedLabel: mode.learnedCountries,
                      turn: PageTurn(target: SaveData.japanAtlas,
                                     label: mode.toJapanAtlas,
                                     onTrailingEdge: false))
                // Latched so a return to にほん does not tear the page down
                // just to rebuild it on the next turn.
                .onAppear { worldPageTouched = true }
        } else {
            GeometryReader { geo in
                let x = geo.frame(in: .global).minX
                Color.clear
                    .onChange(of: x) { oldX, newX in
                        // Toward the centre only: a resize (iPad rotation)
                        // can also move the slot, and loading on one of
                        // those is merely early, never wrong. "Toward" means
                        // x decreasing because the world slot rests one
                        // screen to the trailing side — an LTR assumption,
                        // fine for a Japanese-only UI that never mirrors.
                        if newX < oldX { worldPageTouched = true }
                    }
            }
        }
    }

    /// One album page. The two pages are this one structure fed different
    /// books — the world gets no layout of its own, only world data and world
    /// wording, so the flip reads as the same album continuing (design doc §2).
    private func albumPage(for atlas: Atlas, learnedLabel: String,
                           turn: PageTurn) -> some View {
        // The page's one read of its book. Every number below comes off this
        // slice, so the two pages cannot mix their tallies.
        let slice = app.save.data.atlas(atlas.saveKey)

        return ZStack {
            VStack(spacing: 0) {
                // The plaque-free logo floats over the sea and the top of the
                // country. Sharing this space gives the map the width and
                // height the old separate logo row used to consume.
                miniMap(for: atlas, slice: slice)
                    // On a portrait iPad the −52 bleed would inflate the sea
                    // to 756pt; 680 keeps the composition. A short landscape
                    // safe area gets the smaller ceiling below.
                    .frame(maxWidth: isShort ? 450 : 680)
                    // Keep a calm band below the status area, but do not let
                    // it become a second header. The old 64pt inset made the
                    // whole composition sit low, especially on tall phones.
                    .padding(.top, isShort ? 8 : (hSize == .regular ? 42 : 44))
                    .overlay(alignment: .top) {
                        // The artwork has deliberate transparent breathing
                        // room, so its painted width is about 85% of this
                        // frame. These ceilings make the visible wordmark line
                        // up with the tally row instead of looking pinched
                        // above it. The overlay still consumes no map space.
                        Image("TitleLogoFloating")
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: isShort ? 390
                                                    : (hSize == .regular ? 500 : 405))
                            .accessibilityLabel(
                                "\(mode.appTitleTop) \(mode.appTitleMain)"
                            )
                            .accessibilityAddTraits(.isHeader)
                    }
                    // In a short landscape safe area the controls win any
                    // final compression contest; the map is illustration,
                    // while the CTA must remain visible and tappable.
                    .layoutPriority(isShort ? 0 : 1)
                    // −52 goes past cancelling the column's 20pt margin: the
                    // frame runs 32pt off each screen edge, trading the art's
                    // transparent side margins for a visibly larger country.
                    .padding(.horizontal, -52)
                    .padding(.vertical, 2)
                    // The sea keeps its full painted height, but the layout
                    // hands part of it back, so the tallies and あそぶ sit on
                    // the water (drawn later in the VStack = drawn on top).
                    // Only ever water may go under them: at −170 the tallies
                    // covered the Okinawa inset frame, and hiding a real map
                    // element is where "the lower sea is margin" stops being
                    // true. These per-presentation overlaps all clear the
                    // inset's bottom edge with water to spare.
                    .padding(.bottom, isShort ? -92
                                             : (hSize == .regular ? -104 : -78))

                progressLine(for: atlas, slice: slice, learnedLabel: learnedLabel)

                Spacer(minLength: isShort ? 4 : 8)

                // あそぶ is the only labelled button left. The two tallies
                // above already open the my-map and the card book; a second,
                // smaller pair of doors to the same two rooms just competed
                // with the one door that matters.
                Button {
                    SoundService.shared.play(
                        .decide, enabled: app.save.data.settings.soundEnabled)
                    onStart()
                } label: {
                    Image(mode.isKids ? "TitlePlayButton" : "TitlePlayButtonAdult")
                        .resizable()
                        .scaledToFit()
                        .accessibilityHidden(true)
                }
                .buttonStyle(TitleArtworkButtonStyle())
                .accessibilityLabel(mode.play)
                // Both pages carry an あそぶ with the same spoken label; the
                // identifier is how a UI test says *which page's* door it
                // means without polluting what VoiceOver reads.
                .accessibilityIdentifier("title-play-\(atlas.saveKey)")
                // Slightly broader than before so the three main horizontal
                // masses step down cleanly: logo, tallies, then primary CTA.
                .frame(maxWidth: isShort ? 248
                                         : (hSize == .regular ? 284 : 264))

                // Flexible again now that the map overlap keeps the leftover
                // small: on a phone there is almost nothing to distribute,
                // and on iPad splitting it above and below あそぶ reads as
                // album margins instead of one dead block over the footer.
                Spacer(minLength: isShort ? 8 : 12)

                footer
            }
            // The painted tally frames want to sit a little closer to the
            // page edge than ordinary text. This also gives the logo and the
            // two-card row the same optical left/right margins on phones.
            .padding(.horizontal, 20)
            .pageColumn()

            pageTurnTab(turn)
        }
    }

    /// Identical on both pages: the attribution is a title-screen duty
    /// (CLAUDE.md §3) and both pages are the title.
    ///
    /// TODO(P6 Task 6 / リリース前): 世界地図の出典 (Natural Earth) を追記する。
    /// パブリックドメインで法的義務はないが、国土地理院と同じ誠実さで書く —
    /// 文言はストア準備と一緒に決める(P6 では保留)。
    private var footer: some View {
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

    // MARK: - Page turn

    /// One page-edge tab: which book it opens, what it says, which edge of the
    /// page it sits on. The tab names its far side, so the pair also tells the
    /// child which page they are on without a header saying so.
    private struct PageTurn {
        let target: String
        let label: String
        /// The forward tab (にほん → せかい) sits on the trailing edge and
        /// points right; the way back mirrors it.
        let onTrailingEdge: Bool
    }

    /// The visible way to the other page (design doc §2). Vertically centred
    /// on the page edge — mid-height is open sea on both maps, and an edge tab
    /// halfway down a page is where a thumb finds a real album's tabs.
    private func pageTurnTab(_ turn: PageTurn) -> some View {
        Button {
            SoundService.shared.play(
                .decide, enabled: app.save.data.settings.soundEnabled)
            turnPage(to: turn.target)
        } label: {
            HStack(spacing: 5) {
                if !turn.onTrailingEdge {
                    Image(systemName: "chevron.left")
                }
                Text(turn.label)
                if turn.onTrailingEdge {
                    Image(systemName: "chevron.right")
                }
            }
        }
        .buttonStyle(BouncyButtonStyle(background: Palette.teal,
                                       horizontalPadding: 14,
                                       verticalPadding: 8,
                                       fontSize: 14))
        .accessibilityLabel(turn.label)
        .frame(maxWidth: .infinity, maxHeight: .infinity,
               alignment: turn.onTrailingEdge ? .trailing : .leading)
        .padding(.horizontal, 8)
    }

    private func turnPage(to target: String) {
        // Reduce Motion lands on the page instead of sliding to it
        // (CLAUDE.md §9). The swipe stays animated either way — it is the
        // finger doing the moving there.
        if reduceMotion {
            atlasKey = target
        } else {
            withAnimation(.easeInOut(duration: 0.32)) { atlasKey = target }
        }
    }

    // MARK: - Page content

    /// The child's own progress, as the title art — whichever book's progress
    /// this page shows. Flipping to a mostly-grey world next to a greening
    /// japan is the design's whole pitch: 「こっちの本はまだ白い」.
    private func miniMap(for atlas: Atlas, slice: AtlasSave) -> some View {
        GeometryReader { geo in
            ZStack {
                // The sea, waves, compass and sparkles are decorative artwork.
                // The country itself deliberately is not baked into this image,
                // so its live fills can keep changing. Both pages share the
                // one backdrop: the world map is wider than japan's, so it
                // simply sits as a broader band in the same painted sea.
                Image("TitleMapBackdrop")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                PrefectureMapView(
                    mapData: atlas.mapData,
                    codes: atlas.mapData.prefectures.map(\.code),
                    appearance: {
                        MasteryStyle.appearance(for: $0.code, save: slice)
                    }
                    // Inset frames and background coastlines are data-driven:
                    // the map draws whatever `mapData` declares. The world
                    // page gains its grey unrecorded coastlines for free —
                    // the silhouette a child recognises as "the world".
                )
                .aspectRatio(
                    PrefectureGeometry.aspectRatio(of: atlas.mapData.prefectures),
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

    /// Two counts, each with how far along it is.
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
    /// Denominators come off the atlas, never a literal: japan's 47 and the
    /// world's country and card counts are all whatever the loaded book says,
    /// so new world cards move the total by themselves.
    ///
    /// The foil-card counts live inside the card tile because they are a
    /// breakdown of that collection, not a third destination. Gold, silver
    /// and rainbow are exclusive here: a rainbow card is no longer repeated
    /// under gold, so the three numbers remain an honest inventory.
    private func progressLine(for atlas: Atlas, slice: AtlasSave,
                              learnedLabel: String) -> some View {
        HStack(spacing: 10) {
            // 「おぼえた」 is claimed at the top of the mastery ladder, not on
            // the first clean answer — counting first answers filled the bar
            // to 47/47 while the map was still mostly green, and a full meter
            // over an unfinished map called the child done when they were not.
            tally("TitleLearnedHUD", slice.sparklingRegionCount,
                  max(atlas.mapData.prefectures.count, 1),
                  learnedLabel, Palette.learned, hint: mode.myMap,
                  action: onMyMap)
            // Opens the book unfiltered now rather than straight onto the キラ
            // cards, which the third tile used to do. One tile cannot lead two
            // places, and the book's own ✨ chip is the first thing above the
            // grid — one tap further, in the room where the cards already are.
            tally("TitleCardsHUD", slice.totalOwnedCards, max(atlas.cards.count, 1),
                  mode.ownedCards, Palette.collected,
                  breakdown: TallyBreakdown(items: [
                    .init(tier: .silver,
                          name: mode.cardTierName(.silver) ?? "シルバーカード",
                          count: slice.cardCount(ofTier: .silver),
                          countTint: Palette.silverMark),
                    .init(tier: .gold,
                          name: mode.cardTierName(.gold) ?? "ゴールドカード",
                          count: slice.cardCount(ofTier: .gold),
                          countTint: Palette.goldInk),
                    .init(tier: .rainbow,
                          name: mode.cardTierName(.rainbow) ?? "にじいろカード",
                          count: slice.cardCount(ofTier: .rainbow),
                          countTint: Palette.rainbowMark),
                  ]),
                  hint: mode.viewCards) {
                onCardBook(.all)
            }
        }
        // Holds the row to its tallest tile instead of letting the flexible
        // heights above stretch it down the screen. The three tier counts need
        // a little more breathing room than the old one-phrase note, while the
        // row still fits inside the phone column without touching its edges.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: isShort ? 390
                                 : (hSize == .regular ? 440 : 382))
    }

    /// The exclusive rungs inside the owned-card total.
    private struct TallyBreakdown {
        struct Item: Identifiable {
            let tier: CardTier
            let name: String
            let count: Int
            let countTint: Color

            var id: String { name }
            var accessibilityText: String { "\(name) \(count)まい" }
        }

        let items: [Item]

        var accessibilityText: String {
            items.map(\.accessibilityText).joined(separator: "、")
        }
    }

    /// Each count opens the place its things live: the two prefecture counts go
    /// to the map, the card count to the book. A number a child is proud of
    /// should lead somewhere — and every one of these was already the answer to
    /// "where can I see them?".
    private func tally(_ artwork: String, _ have: Int, _ total: Int,
                       _ label: String, _ tint: Color,
                       breakdown: TallyBreakdown? = nil,
                       hint: String = "",
                       action: @escaping () -> Void) -> some View {
        Button {
            // Forward taps play their own decide (RootView listens only for
            // the way back) — and these tiles are doors as much as あそぶ is.
            SoundService.shared.play(
                .decide, enabled: app.save.data.settings.soundEnabled)
            action()
        } label: {
            tallyFace(artwork, have, total, label, tint, breakdown)
        }
            .buttonStyle(TallyPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                breakdown.map {
                    "\(label) \(have) / \(total)。\($0.accessibilityText)"
                } ?? "\(label) \(have) / \(total)"
            )
            // Since the labelled マイマップ/カードをみる buttons left the
            // screen, the hint is where VoiceOver learns each tile is also
            // the door to its collection.
            .accessibilityHint(hint)
            .accessibilityAddTraits(.isButton)
    }

    private func tallyFace(_ artwork: String, _ have: Int, _ total: Int,
                           _ label: String, _ tint: Color,
                           _ breakdown: TallyBreakdown?) -> some View {
        GeometryReader { geo in
            ZStack {
                // The frame, corner ornaments and collection icon are artwork;
                // every value laid over it remains live SwiftUI content.
                Image(artwork)
                    .resizable()
                    .scaledToFit()
                    .accessibilityHidden(true)

                // Set in the heading face, not the round one: these run small
                // over painted artwork, and the round family ships a single
                // light weight — W6 is the bold this HUD can actually render.
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        // Verbatim: SwiftUI's localised interpolation groups
                        // integers, and a child reading 「1,120」 has to parse a
                        // comma first.
                        Text(verbatim: "\(have)")
                            .font(AppFont.heading(25, relativeTo: .title3))
                            .foregroundStyle(Palette.ink)
                        Text(verbatim: "/\(total)")
                            .font(AppFont.heading(12, relativeTo: .caption2))
                            .foregroundStyle(Palette.ink.opacity(0.55))
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    Text(label)
                        .font(AppFont.heading(12, relativeTo: .caption2))
                        .foregroundStyle(Palette.ink.opacity(0.88))
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

                if let breakdown {
                    HStack(spacing: 5) {
                        ForEach(breakdown.items) { item in
                            HStack(spacing: 2) {
                                TierCardMark(tier: item.tier)
                                Text(verbatim: "\(item.count)")
                                    .foregroundStyle(item.countTint)
                            }
                        }
                    }
                        .font(AppFont.heading(11, relativeTo: .caption2))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(width: geo.size.width * 0.82)
                        .position(x: geo.size.width * 0.52,
                                  y: geo.size.height * 0.84)
                }
            }
        }
        .aspectRatio(800 / 483, contentMode: .fit)
    }

    /// A tiny piece of the actual card finish, rather than a kanji abbreviation.
    /// The order and the material now match the ladder in the card book:
    /// silver, gold, then rainbow.
    private struct TierCardMark: View {
        let tier: CardTier

        private var stops: [Gradient.Stop] {
            switch tier {
            case .silver: Palette.silverRamp
            case .gold: Palette.foilRamp
            case .rainbow: Palette.rainbowRamp
            case .none, .plain: []
            }
        }

        private var edge: Color {
            switch tier {
            case .silver: Palette.silverEdge
            case .gold: Palette.foilEdge
            case .rainbow: Palette.rainbowEdge
            case .none, .plain: .white
            }
        }

        var body: some View {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(LinearGradient(stops: stops,
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(edge, lineWidth: 1)
                }
                .overlay {
                    Image(systemName: tier == .rainbow ? "sparkles" : "star.fill")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                }
                .frame(width: 12, height: 15)
                .rotationEffect(.degrees(-5))
                .shadow(color: Palette.ink.opacity(0.16), radius: 0.7, y: 1)
                .accessibilityHidden(true)
        }
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
    ///
    /// Takes one atlas's slice, never the whole save: every caller names the
    /// book it is colouring for (a SaveData convenience that silently meant
    /// "japan's slice" let a world screen compile while lying).
    static func appearance(for code: Int, save: AtlasSave) -> PrefectureAppearance {
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
