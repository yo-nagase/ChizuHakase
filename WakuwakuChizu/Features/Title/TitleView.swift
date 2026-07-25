import SwiftUI

/// Home screen. Three destinations and the map attribution required by
/// CLAUDE.md §3.
struct TitleView: View {
    @Environment(AppState.self) private var app

    var onStart: () -> Void
    var onMyMap: () -> Void
    var onCardBook: () -> Void

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 12)

                Text("わくわく")
                    .font(AppFont.rounded(34, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.orange)
                Text("ちずクイズ")
                    .font(AppFont.rounded(44, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.ink)

                miniMap
                    .frame(maxHeight: 260)
                    .padding(.vertical, 10)

                progressLine

                Spacer(minLength: 12)

                VStack(spacing: 14) {
                    Button("あそぶ") { onStart() }
                        .buttonStyle(BouncyButtonStyle(horizontalPadding: 52,
                                                       verticalPadding: 16,
                                                       fontSize: 24))
                    HStack(spacing: 12) {
                        Button("マイマップ") { onMyMap() }
                            .buttonStyle(.bouncy(Palette.teal, fontSize: 17))
                        Button("ずかん") { onCardBook() }
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
            appearance: { pref in
                let level = app.save.data.masteryLevel(of: pref.code)
                return PrefectureAppearance(fill: MasteryStyle.fill(level: level,
                                                                    code: pref.code),
                                            isSparkling: level >= GameRules.maxMastery)
            })
        .aspectRatio(PrefectureGeometry.aspectRatio(of: app.mapData.prefectures),
                     contentMode: .fit)
        .allowsHitTesting(false)
    }

    private var progressLine: some View {
        HStack(spacing: 16) {
            Label("\(app.save.data.sparklingPrefectureCount) / 47",
                  systemImage: "sparkles")
            Label("\(app.save.data.totalOwnedCards) / \(max(app.cards.count, 1))",
                  systemImage: "square.grid.2x2.fill")
        }
        .font(AppFont.rounded(13, relativeTo: .caption))
        .foregroundStyle(Palette.ink.opacity(0.55))
    }
}

/// Mastery colour ramp shared by the title art and the my-map screen
/// (CLAUDE.md §5).
enum MasteryStyle {
    static func fill(level: Int, code: Int) -> Color {
        switch level {
        case ..<1: Palette.unlearned
        case 1: Palette.fill(for: code).opacity(0.33)
        case 2: Palette.fill(for: code).opacity(0.73)
        default: Palette.fill(for: code)
        }
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
