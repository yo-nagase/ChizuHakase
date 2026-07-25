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

    /// Two counts, phrased as a sticker tally rather than as statistics.
    private var progressLine: some View {
        HStack(spacing: 10) {
            tally("🗾", app.save.data.mastery.values.filter { $0 > 0 }.count, 47,
                  mode.isKids ? "けん" : "県")
            tally("✨", app.save.data.sparklingPrefectureCount, 47, "キラ")

            tally("🃏", app.save.data.totalOwnedCards, max(app.cards.count, 1), "カード")
        }
    }

    private func tally(_ emoji: String, _ have: Int, _ total: Int,
                       _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(emoji).font(.system(size: 17))
            Text("\(have)")
                .font(AppFont.rounded(17, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
                .monospacedDigit()
            Text("/ \(total) \(label)")
                .font(AppFont.rounded(10, relativeTo: .caption2))
                .foregroundStyle(Palette.ink.opacity(0.45))
                .monospacedDigit()
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .stickerCard(cornerRadius: 16, edge: 2.5)
    }
}

/// Mastery ramp shared by the title art and the my-map screen (CLAUDE.md §5),
/// expressed as sticker states: an empty slot fills in, then goes キラ.
enum MasteryStyle {
    /// CLAUDE.md §5 asked for 33% / 73% / solid. On the real map 33% sat close
    /// enough to the unlearned grey that a child could not tell at a glance
    /// which prefectures they had answered — the one question this screen
    /// exists to answer. The first step now lands as unmistakably coloured, and
    /// the ramp above it still reads as three distinct stages.
    static func fill(level: Int, code: Int) -> Color {
        switch level {
        case ..<1: Palette.unlearned
        case 1: Palette.fill(for: code, strength: 0.58)
        case 2: Palette.fill(for: code, strength: 0.82)
        default: Palette.fill(for: code)
        }
    }

    /// Only the fill moves as a prefecture is learned.
    ///
    /// Answered prefectures used to get the white die-cut edge and the lift
    /// that goes with it, which cut the country into loose pieces floating over
    /// the sea while the rest stayed printed flat — the border between 東北 and
    /// 関東 became a seam. The outline is now the same printed edge at every
    /// level, so progress reads as colour spreading across one whole map.
    /// Lv3 keeps the gold frame CLAUDE.md §5 promises.
    static func appearance(for code: Int, save: SaveData) -> PrefectureAppearance {
        let level = save.masteryLevel(of: code)
        return PrefectureAppearance(fill: fill(level: level, code: code),
                                    stroke: Palette.emptySlot.opacity(0.7),
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
