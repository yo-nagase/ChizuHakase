import SwiftUI

/// Phase 2 harness: exercises `PrefectureMapView` across stages and shows what
/// a tap resolved to. Replaced by the real title screen once the quiz lands.
struct RootView: View {
    @Environment(AppState.self) private var app

    @State private var stageIndex = 6
    @State private var tapped: Prefecture?
    @State private var answered: Set<Int> = []
    @State private var effect: MapEffect?
    @State private var effectCounter = 0

    private var stage: Stage { Stage.all[stageIndex] }
    private var target: Prefecture? {
        app.mapData.prefectures(in: stage.codes).first { !answered.contains($0.code) }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("すてーじ", selection: $stageIndex) {
                ForEach(Stage.all) { Text($0.name).tag($0.index) }
            }
            .pickerStyle(.menu)
            .tint(Palette.ink)

            Text(target.map { "\($0.kana) は どこかな?" } ?? "ぜんぶ こたえたよ!")
                .font(AppFont.rounded(20, relativeTo: .title3))
                .foregroundStyle(Palette.ink)

            PrefectureMapView(
                mapData: app.mapData,
                codes: stage.codes,
                appearance: appearance,
                interactiveCodes: Set(stage.codes).subtracting(answered),
                targetCode: target?.code,
                hintCode: nil,
                effect: effect,
                onTap: handleTap)
            .aspectRatio(PrefectureGeometry.aspectRatio(
                of: app.mapData.prefectures(in: stage.codes)), contentMode: .fit)
            .background(Palette.seaGradient)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Text(tapped.map { "タップ: \($0.name)" } ?? "タップ: うみ")
                .font(AppFont.rounded(15, relativeTo: .footnote))
                .foregroundStyle(Palette.ink.opacity(0.7))

            Button("もういちど") {
                answered = []
                tapped = nil
            }
            .font(AppFont.rounded(17, relativeTo: .body))
            .tint(Palette.orange)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background)
    }

    private func appearance(_ pref: Prefecture) -> PrefectureAppearance {
        if answered.contains(pref.code) {
            PrefectureAppearance(fill: Palette.fill(for: pref.code))
        } else {
            PrefectureAppearance(fill: Palette.unlearned)
        }
    }

    private func handleTap(_ pref: Prefecture?) {
        tapped = pref
        guard let pref else { return }
        effectCounter += 1
        if pref.code == target?.code {
            answered.insert(pref.code)
            effect = MapEffect(code: pref.code, kind: .pop, id: effectCounter)
        } else {
            effect = MapEffect(code: pref.code, kind: .shake, id: effectCounter)
        }
    }
}

#Preview {
    RootView().environment(AppState())
}
