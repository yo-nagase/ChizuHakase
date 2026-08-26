import SwiftUI

/// The open book's whole map coloured by how well each region is known
/// (CLAUDE.md §5). Tapping a region shows its detail; this screen also owns
/// the erase-everything control — which erases the *whole app*, both books,
/// whichever page it was opened from (design doc: one record, one eraser).
struct MyMapView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.textMode) private var mode

    /// The book this map shows. Regions, mastery and the tallies all come off
    /// this one value and its save slice, so japan's greens can never colour
    /// the world's countries (their codes collide — 44 is 大分県 and バハマ).
    let atlas: Atlas

    @State private var selected: Prefecture?
    @State private var eraseStep = 0   // 0 = idle, 1 = asked once, 2 = confirming
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    /// The map's frame, for dropping taps the zoom pushed off the glass.
    @State private var mapSize: CGSize = .zero
    /// The globe's camera, when this book carries one. Opens facing
    /// `GlobeCenter.home`; the zoom is a separate axis from the flat map's
    /// `zoom` because it lives in the disk's radius, not in a scaleEffect.
    @State private var globeCenter = GlobeCenter.home
    @State private var globeZoom: CGFloat = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var save: AtlasSave { app.save.data.atlas(atlas.saveKey) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                legend

                map

                summary
                eraseSection
            }
            .padding(16)
            .pageColumn()
        }
        // While zoomed the flat map owns dragging, or the column would scroll
        // away underneath a child trying to move around Kyushu. The reset
        // button is always on screen, so the way back to scrolling is one tap.
        // The globe never trips this (`zoom` is the flat map's camera): it
        // rotates at *every* zoom, so instead of a scroll switch its drag is
        // a high-priority gesture (see `GlobeSurface`) — the page scrolls
        // from the legend, the tallies and the margins, never off the planet.
        .scrollDisabled(ZoomPan.isZoomed(zoom))
        .background(AlbumPage())
        .navigationTitle(mode.myMap)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { PrefectureDetailSheet(atlas: atlas, prefecture: $0) }
    }

    /// Which panel the book gets is decided by data, never by which book it
    /// is: a book that carries globe rings is shown as a globe (design doc §7 —
    /// turning the sphere to find your own green is itself the reward), and
    /// japan, which carries none, keeps the flat map it has always had.
    @ViewBuilder private var map: some View {
        if let globe = atlas.globe {
            globePanel(globe)
        } else {
            flatMap
        }
    }

    /// The world coloured by mastery, as a sphere the child can turn.
    ///
    /// Square, unlike the flat panel's derived ratio: the disk is sized by the
    /// panel's short side, so any extra width or height is only ever empty
    /// corner — a square wastes the least page on a round earth. Tap targets,
    /// hints and effects are quiz furniture; here a tap just opens the same
    /// detail sheet the flat map opens.
    private func globePanel(_ globe: GlobeData) -> some View {
        GlobeMapView(
            globe: globe,
            // The same function the legend and the flat map read (§5), so a
            // country can only wear a colour the swatches explain.
            appearance: { MasteryStyle.appearance(for: $0, save: save) },
            interactiveCodes: Set(globe.shapes.map(\.code)),
            center: $globeCenter,
            zoom: $globeZoom,
            // The reading, not the written name — same reasoning as the quiz
            // globe: kanji country names are exactly where VoiceOver guesses
            // wrong, and the reading is the form being taught.
            accessibilityName: { atlas.mapData[$0]?.kana ?? "" },
            onTap: { code, _ in
                // No visibility gate (unlike the flat map's): the globe's
                // magnification lives in its radius, so the touch region
                // never outgrows the clipped panel the child sees.
                if let code { selected = atlas.mapData[code] }
            })
            .aspectRatio(1.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            // The globe carries its own sea inside the disk; more sea around
            // a sea-rimmed planet would swallow its edge (same call as the
            // quiz panel), so behind it the panel stays album paper.
            .background(Palette.background)
            .stickerCard(fill: .clear, cornerRadius: 26)
            // Zoom needs the same visible way back as the flat map. Rotation
            // does not: no orientation is "lost" on a sphere that always
            // shows half of itself, and home is one drag away.
            .overlay(alignment: .topTrailing) {
                resetZoomButton(isZoomed: ZoomPan.isZoomed(globeZoom)) {
                    globeZoom = 1
                }
            }
            // No ZoomHintChip: the chip teaches ZoomPan's press-and-slide,
            // a gesture the globe does not run — there, a drag rotates.
            .accessibilityZoomAction { globeZoom = zoomedForAccessibility(globeZoom, $0) }
    }

    /// Pinchable, and draggable once pinched. The zoom lives on the map itself
    /// rather than on the whole screen so the legend and the counts stay put —
    /// they are the key to what the colours mean, and scaling them away while
    /// looking closely at a prefecture would be backwards.
    private var flatMap: some View {
        PrefectureMapView(
            mapData: atlas.mapData,
            codes: atlas.mapData.prefectures.map(\.code),
            appearance: appearance,
            interactiveCodes: Set(atlas.mapData.prefectures.map(\.code)),
            // Inset frames and background coastlines are data-driven — the map
            // draws whatever `mapData` declares, so nothing is passed here.
            zoom: zoom,
            onTap: { prefecture, point in
                // The touch region outgrows the clipped panel while zoomed
                // (ZoomPan.isVisible); a tap on the legend must not open a
                // prefecture the child cannot see.
                guard ZoomPan.isVisible(point, scale: zoom, offset: pan,
                                        in: mapSize) else { return }
                selected = prefecture
            })
        // A quarter more height than the map itself needs: the extra becomes
        // sea above and below, and a zoomed-in child gets that much more
        // viewport to move around in. Derived from the map's own proportions
        // rather than fixed at japan's 0.8, so the world's wide band earns the
        // same margin of sea instead of floating in a tall empty panel.
        .aspectRatio(0.8 * PrefectureGeometry.aspectRatio(of: atlas.mapData.prefectures),
                     contentMode: .fit)
        // Same gesture as the quiz map: a child who learns it on one country
        // should not find it missing on the other.
        .zoomPan(scale: $zoom, offset: $pan, oneFingerZoom: true, panInertia: true)
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { mapSize = geo.size }
                    .onChange(of: geo.size) { _, new in mapSize = new }
            }
        }
        // Clipped to its own card: a zoomed map must not spill over the legend
        // or the buttons underneath it.
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(Palette.seaGradient)
        .stickerCard(fill: .clear, cornerRadius: 26)
        .overlay(alignment: .topTrailing) {
            resetZoomButton(isZoomed: ZoomPan.isZoomed(zoom)) {
                zoom = 1
                pan = .zero
            }
        }
        .overlay(alignment: .bottom) { ZoomHintChip(zoom: zoom).padding(.bottom, 12) }
        .accessibilityZoomAction { action in
            zoom = zoomedForAccessibility(zoom, action)
            if !ZoomPan.isZoomed(zoom) { pan = .zero }
        }
    }

    /// VoiceOver cannot pinch, so each camera gets the same 1...4 range
    /// through the rotor-driven zoom action instead, stepping by half again
    /// per gesture. One function for both panels — the flat map additionally
    /// re-centres its pan on the way out (a globe has no pan to re-centre).
    private func zoomedForAccessibility(_ zoom: CGFloat,
                                        _ action: AccessibilityZoomGestureAction) -> CGFloat {
        ZoomPan.clamp(scale: action.direction == .zoomIn ? zoom * 1.5 : zoom / 1.5)
    }

    /// The way back out — shared by both cameras (the flat map's zoom+pan,
    /// the globe's radius), because a child who learns the escape hatch on
    /// one panel must find it in the same corner of the other.
    ///
    /// A visible button rather than a double-tap: double tap would have to be
    /// disambiguated from the single tap that opens a prefecture, delaying
    /// every selection, and a five-year-old who has pinched into a corner
    /// needs an escape hatch they can see rather than one they must know about.
    @ViewBuilder private func resetZoomButton(isZoomed: Bool,
                                              reset: @escaping () -> Void) -> some View {
        if isZoomed {
            Button(mode.resetZoom) {
                if reduceMotion { reset() } else { withAnimation(.spring(duration: 0.3), reset) }
            }
            .font(AppFont.rounded(13, relativeTo: .caption))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.92)))
            .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.12)))
            .padding(10)
        }
    }

    private func appearance(_ pref: Prefecture) -> PrefectureAppearance {
        MasteryStyle.appearance(for: pref.code, save: save)
    }

    /// Reads its colours from the same function the map does, so a swatch
    /// cannot promise a colour the country does not use. The 「おぼえた」 chip
    /// is flat gold with no border, because that is exactly what a top-level
    /// prefecture looks like.
    private var legend: some View {
        HStack(spacing: 10) {
            // One swatch per visual *state*, not per level: 2 shares 1's colour
            // and 4 shares 3's, so listing all six would show the same swatch
            // twice with the same word under it.
            ForEach([0, 1, 3, GameRules.maxMastery], id: \.self) { level in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MasteryStyle.fill(level: level))
                        .frame(width: 16, height: 16)
                    Text(mode.masteryLabel(level))
                        .font(AppFont.rounded(10, relativeTo: .caption2))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }
            }
        }
    }

    /// One stat, not two: 「おぼえた」 *means* reaching the top of the ladder
    /// now, so a second count beside this one was the same number wearing
    /// another name. The word matches the legend's gold swatch and the title's
    /// tally tile — one measurement, one name, wherever it appears. The
    /// denominator is whatever the open book holds (47 or 167), never a
    /// literal.
    private var summary: some View {
        HStack(spacing: 12) {
            stat("✨ \(mode.learnedCount)",
                 "\(save.sparklingRegionCount) / \(atlas.mapData.prefectures.count)")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(AppFont.rounded(12, relativeTo: .caption))
                .foregroundStyle(Palette.ink.opacity(0.6))
            Text(value)
                .font(AppFont.rounded(23, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .stickerCard(cornerRadius: 20)
    }

    /// Two deliberate steps before anything is destroyed (CLAUDE.md §6).
    ///
    /// Whole-app on purpose, whichever book's map sits above it: `eraseAll`
    /// clears both books (design-doc recommendation — one record, one eraser),
    /// and the second confirmation names both so nobody erases 「the world's
    /// records」 and loses japan's. See `SaveStore.eraseAll` for the lastAtlas
    /// side effect.
    private var eraseSection: some View {
        VStack(spacing: 10) {
            switch eraseStep {
            case 0:
                Button(mode.eraseEverything) { eraseStep = 1 }
                    .font(AppFont.rounded(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink.opacity(0.45))
            case 1:
                Text(mode.eraseConfirm1)
                    .font(AppFont.rounded(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 12) {
                    Button(mode.eraseCancel) { eraseStep = 0 }
                        .buttonStyle(.bouncy(Palette.teal, fontSize: 15))
                    Button(mode.eraseNext) { eraseStep = 2 }
                        .buttonStyle(.bouncy(Palette.ink.opacity(0.5), fontSize: 15))
                }
            default:
                Text(mode.eraseConfirm2)
                    .font(AppFont.rounded(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.red)
                HStack(spacing: 12) {
                    Button(mode.eraseCancel) { eraseStep = 0 }
                        .buttonStyle(.bouncy(Palette.teal, fontSize: 15))
                    Button(mode.eraseConfirmAction) {
                        app.save.eraseAll()
                        eraseStep = 0
                    }
                    .buttonStyle(.bouncy(Palette.red, fontSize: 15))
                }
            }
        }
        .padding(.top, 8)
        .animation(reduceMotion ? nil : .snappy, value: eraseStep)
    }
}

private struct PrefectureDetailSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.textMode) private var mode
    /// The book the tapped region lives in — its catalog and its save slice,
    /// because the region's code only means anything inside that book.
    let atlas: Atlas
    let prefecture: Prefecture

    private var save: AtlasSave { app.save.data.atlas(atlas.saveKey) }

    var body: some View {
        let level = save.masteryLevel(of: prefecture.code)
        let cards = atlas.cards.cards(for: prefecture.code)

        ScrollView {
            VStack(spacing: 14) {
                Text(prefecture.displayName(mode))
                    .font(AppFont.rounded(33, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.ink)
                Text(prefecture.secondaryName(mode))
                    // Sized to the quiz's second line, for the same reason: the
                    // kanji is there to be looked at, not just acknowledged.
                    .font(AppFont.rounded(17, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink.opacity(0.5))

                HStack(spacing: 4) {
                    ForEach(1...GameRules.maxMastery, id: \.self) { i in
                        StarBadge(filled: i <= level, size: 24)
                    }
                }
                Text(mode.masteryLabel(level))
                    .font(AppFont.rounded(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink.opacity(0.6))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                         count: typeSize.cardColumns), spacing: 10) {
                    ForEach(cards) { card in
                        CardChipView(card: card,
                                     stars: save.stars(of: card.id),
                                     rainbow: save.isRainbow(card.id))
                    }
                }
                .padding(.top, 4)

                Button("🔊 \(mode.speech)") {
                    SpeechService.shared.speak(prefecture.kana)
                }
                .buttonStyle(.bouncy(Palette.teal, fontSize: 16))
                .padding(.top, 6)
            }
            .padding(20)
        }
        .background(AlbumPage())
        .presentationDetents([.medium, .large])
    }
}
