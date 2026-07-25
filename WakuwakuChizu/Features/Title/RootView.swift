import SwiftUI

/// Phase 1 placeholder: confirms the generated resources decoded on device.
/// Replaced by the real title screen once the map component lands.
struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            VStack(spacing: 14) {
                Text("わくわく ちずクイズ")
                    .font(AppFont.rounded(30, relativeTo: .largeTitle))
                    .foregroundStyle(Palette.ink)

                VStack(alignment: .leading, spacing: 6) {
                    row("けん", "\(app.mapData.prefectures.count) / 47")
                    row("カード", "\(app.cards.count) / 141")
                    row("ちずのおおきさ",
                        "\(Int(app.mapData.width)) x \(Int(app.mapData.height))")
                    row("ステージ", "\(app.stages.count)")
                }
                .font(AppFont.rounded(17, relativeTo: .body))
                .foregroundStyle(Palette.ink)
                .padding(18)
                .background(.white, in: RoundedRectangle(cornerRadius: 20))

                Text("ちずデータ: Global Map Japan (国土地理院) をもとに簡略化")
                    .font(AppFont.rounded(11, relativeTo: .caption2))
                    .foregroundStyle(Palette.ink.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .padding(24)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 20)
            Text(value).bold()
        }
        .frame(minWidth: 220, alignment: .leading)
    }
}

#Preview {
    RootView().environment(AppState())
}
