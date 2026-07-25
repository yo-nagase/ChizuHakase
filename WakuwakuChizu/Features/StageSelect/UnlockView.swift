import SwiftUI

/// What the unlock buys, shown to the parent *after* the gate.
///
/// The gate comes first and the buy button only exists on the far side of it,
/// so a child tapping a locked stage never reaches a purchase control
/// (CLAUDE.md §8).
struct UnlockView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var passedGate = false

    var body: some View {
        Group {
            if passedGate {
                offer
            } else {
                ParentalGateView { passedGate = true }
            }
        }
    }

    private var offer: some View {
        ScrollView {
            VStack(spacing: 18) {
                Text("ぜんぶ あそべるように なります")
                    .font(AppFont.rounded(22, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    bullet("🗾", "ぜんぶの ステージ (7つ)")
                    bullet("🃏", "とくさんひんカード 141まい")
                    bullet("🌏", "これから ふえる せかいへんも")
                    bullet("🚫", "こうこくは ありません")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))

                if case .failed(let message) = app.purchases.state {
                    Text(message)
                        .font(AppFont.rounded(14, relativeTo: .footnote))
                        .foregroundStyle(Palette.red)
                }

                Button {
                    Task { await app.purchases.purchase(); closeIfUnlocked() }
                } label: {
                    Text(app.purchases.displayPrice.isEmpty
                         ? "かう"
                         : "かう  \(app.purchases.displayPrice)")
                }
                .buttonStyle(.bouncy)
                .disabled(app.purchases.state == .purchasing)

                Button("こうにゅうを ふくげんする") {
                    Task { await app.purchases.restore(); closeIfUnlocked() }
                }
                .font(AppFont.rounded(14, relativeTo: .footnote))
                .foregroundStyle(Palette.ink.opacity(0.6))

                Text("おうちのかたへ: 買い切り 1回のみ。定期購読ではありません。")
                    .font(AppFont.rounded(11, relativeTo: .caption2))
                    .foregroundStyle(Palette.ink.opacity(0.45))
                    .multilineTextAlignment(.center)

                Button("とじる") { dismiss() }
                    .font(AppFont.rounded(15, relativeTo: .footnote))
                    .foregroundStyle(Palette.ink.opacity(0.5))
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .background(Palette.background)
        .task { await app.purchases.load() }
    }

    private func bullet(_ emoji: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text(emoji).font(.system(size: 24))
            Text(text)
                .font(AppFont.rounded(16, relativeTo: .body))
                .foregroundStyle(Palette.ink)
        }
    }

    private func closeIfUnlocked() {
        if app.purchases.isUnlocked { dismiss() }
    }
}
