import SwiftUI

/// The whole country coloured by how well each prefecture is known
/// (CLAUDE.md §5). Tapping a prefecture shows its detail; this screen also
/// owns the erase-everything control.
struct MyMapView: View {
    @Environment(AppState.self) private var app

    @State private var selected: Prefecture?
    @State private var eraseStep = 0   // 0 = idle, 1 = asked once, 2 = confirming

    private var save: SaveData { app.save.data }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                legend

                PrefectureMapView(
                    mapData: app.mapData,
                    codes: Array(1...47),
                    appearance: appearance,
                    interactiveCodes: Set(1...47),
                    onTap: { selected = $0 })
                .aspectRatio(PrefectureGeometry.aspectRatio(of: app.mapData.prefectures),
                             contentMode: .fit)
                .background(Palette.seaGradient)
                .clipShape(RoundedRectangle(cornerRadius: 22))

                summary
                eraseSection
            }
            .padding(16)
        }
        .background(Palette.background)
        .navigationTitle("マイマップ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { PrefectureDetailSheet(prefecture: $0) }
    }

    private func appearance(_ pref: Prefecture) -> PrefectureAppearance {
        let level = save.masteryLevel(of: pref.code)
        return PrefectureAppearance(fill: MasteryStyle.fill(level: level, code: pref.code),
                                    isSparkling: level >= GameRules.maxMastery)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(0...3, id: \.self) { level in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(MasteryStyle.fill(level: level, code: 3))
                        .frame(width: 16, height: 16)
                        .overlay {
                            if level == 3 {
                                RoundedRectangle(cornerRadius: 4)
                                    .strokeBorder(Palette.gold, lineWidth: 2)
                            }
                        }
                    Text(MasteryStyle.label(level: level))
                        .font(AppFont.rounded(10, relativeTo: .caption2))
                        .foregroundStyle(Palette.ink.opacity(0.6))
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            stat("✨ キラキラ", "\(save.sparklingPrefectureCount) / 47")
            stat("🗾 おぼえた", "\(save.mastery.values.filter { $0 > 0 }.count) / 47")
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(AppFont.rounded(12, relativeTo: .caption))
                .foregroundStyle(Palette.ink.opacity(0.6))
            Text(value)
                .font(AppFont.rounded(21, relativeTo: .title3))
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    /// Two deliberate steps before anything is destroyed (CLAUDE.md §6).
    private var eraseSection: some View {
        VStack(spacing: 10) {
            switch eraseStep {
            case 0:
                Button("きろくを ぜんぶ けす") { eraseStep = 1 }
                    .font(AppFont.rounded(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink.opacity(0.45))
            case 1:
                Text("ほんとうに けしても いい?")
                    .font(AppFont.rounded(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink)
                HStack(spacing: 12) {
                    Button("やめる") { eraseStep = 0 }
                        .buttonStyle(.bouncy(Palette.teal, fontSize: 15))
                    Button("つぎへ") { eraseStep = 2 }
                        .buttonStyle(.bouncy(Palette.ink.opacity(0.5), fontSize: 15))
                }
            default:
                Text("けすと もどせないよ。いい?")
                    .font(AppFont.rounded(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.red)
                HStack(spacing: 12) {
                    Button("やめる") { eraseStep = 0 }
                        .buttonStyle(.bouncy(Palette.teal, fontSize: 15))
                    Button("けす") {
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
    let prefecture: Prefecture

    var body: some View {
        let level = app.save.data.masteryLevel(of: prefecture.code)
        let cards = app.cards.cards(for: prefecture.code)

        ScrollView {
            VStack(spacing: 14) {
                Text(prefecture.kana)
                    .font(AppFont.rounded(30, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.ink)
                Text(prefecture.name)
                    .font(AppFont.rounded(15, relativeTo: .subheadline))
                    .foregroundStyle(Palette.ink.opacity(0.5))

                HStack(spacing: 4) {
                    ForEach(1...GameRules.maxMastery, id: \.self) { i in
                        Text(i <= level ? "⭐️" : "☆").font(.system(size: 22))
                    }
                }
                Text(MasteryStyle.label(level: level))
                    .font(AppFont.rounded(14, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink.opacity(0.6))

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                         count: 3), spacing: 10) {
                    ForEach(cards) { card in
                        CardChipView(card: card,
                                     ownedCount: app.save.data.ownedCount(of: card.id))
                    }
                }
                .padding(.top, 4)

                Button("🔊 よみあげる") {
                    SpeechService.shared.speak(prefecture.kana)
                }
                .buttonStyle(.bouncy(Palette.teal, fontSize: 16))
                .padding(.top, 6)
            }
            .padding(20)
        }
        .background(Palette.background)
        .presentationDetents([.medium, .large])
    }
}
