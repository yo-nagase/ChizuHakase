import SwiftUI

/// The whole country coloured by how well each prefecture is known
/// (CLAUDE.md §5). Tapping a prefecture shows its detail; this screen also
/// owns the erase-everything control.
struct MyMapView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.textMode) private var mode

    @State private var selected: Prefecture?
    @State private var eraseStep = 0   // 0 = idle, 1 = asked once, 2 = confirming
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var save: SaveData { app.save.data }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                legend

                map

                summary
                eraseSection
            }
            .padding(16)
        }
        // While zoomed the map owns dragging, or the column would scroll away
        // underneath a child trying to move around Kyushu. The reset button is
        // always on screen, so the way back to scrolling is one tap.
        .scrollDisabled(ZoomPan.isZoomed(zoom))
        .background(AlbumPage())
        .navigationTitle(mode.myMap)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { PrefectureDetailSheet(prefecture: $0) }
    }

    /// Pinchable, and draggable once pinched. The zoom lives on the map itself
    /// rather than on the whole screen so the legend and the counts stay put —
    /// they are the key to what the colours mean, and scaling them away while
    /// looking closely at a prefecture would be backwards.
    private var map: some View {
        PrefectureMapView(
            mapData: app.mapData,
            codes: Array(1...47),
            appearance: appearance,
            interactiveCodes: Set(1...47),
            zoom: zoom,
            onTap: { prefecture, _ in selected = prefecture })
        .aspectRatio(PrefectureGeometry.aspectRatio(of: app.mapData.prefectures),
                     contentMode: .fit)
        .zoomPan(scale: $zoom, offset: $pan)
        // Clipped to its own card: a zoomed map must not spill over the legend
        // or the buttons underneath it.
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(Palette.seaGradient)
        .stickerCard(fill: .clear, cornerRadius: 26)
        .overlay(alignment: .topTrailing) { resetZoomButton }
        .accessibilityZoomAction { action in
            // VoiceOver cannot pinch, so it gets the same range through the
            // rotor-driven zoom action.
            zoom = ZoomPan.clamp(scale: action.direction == .zoomIn ? zoom * 1.5 : zoom / 1.5)
            if !ZoomPan.isZoomed(zoom) { pan = .zero }
        }
    }

    /// The way back out.
    ///
    /// A visible button rather than a double-tap: double tap would have to be
    /// disambiguated from the single tap that opens a prefecture, delaying
    /// every selection, and a five-year-old who has pinched into a corner
    /// needs an escape hatch they can see rather than one they must know about.
    @ViewBuilder private var resetZoomButton: some View {
        if ZoomPan.isZoomed(zoom) {
            Button(mode.resetZoom) {
                let reset = { zoom = 1; pan = .zero }
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
    /// cannot promise a colour the country does not use. The 「キラキラ」 chip is
    /// flat gold with no border, because that is exactly what a Lv3 prefecture
    /// now looks like.
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(0...GameRules.maxMastery, id: \.self) { level in
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

    private var summary: some View {
        HStack(spacing: 12) {
            stat("✨ \(mode.sparklingCount)", "\(save.sparklingPrefectureCount) / 47")
            stat("🗾 \(mode.learnedCount)", "\(save.mastery.values.filter { $0 > 0 }.count) / 47")
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
        .animation(.snappy, value: eraseStep)
    }
}

private struct PrefectureDetailSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.textMode) private var mode
    let prefecture: Prefecture

    var body: some View {
        let level = app.save.data.masteryLevel(of: prefecture.code)
        let cards = app.cards.cards(for: prefecture.code)

        ScrollView {
            VStack(spacing: 14) {
                Text(prefecture.displayName(mode))
                    .font(AppFont.rounded(33, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.ink)
                Text(prefecture.secondaryName(mode))
                    .font(AppFont.rounded(15, relativeTo: .subheadline))
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
                                     ownedCount: app.save.data.ownedCount(of: card.id))
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
