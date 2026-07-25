import SwiftUI

/// End-of-stage summary: stars, score, cards won and any prefecture that
/// reached mastery level 3 (CLAUDE.md §5).
///
/// Everything here is a gain. There is no "you lost" state to show.
struct ResultView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let stage: Stage
    let result: StageResult
    /// Prefectures that hit level 3 in this run, from `SaveStore`.
    let newlySparkling: [Int]
    var onReplay: () -> Void
    var onExit: () -> Void

    @State private var revealedStars = 0

    private var newCards: [SpecialtyCard] {
        result.cardDraws.compactMap { if case .new(let c) = $0 { c } else { nil } }
    }
    private var shinyCards: [SpecialtyCard] {
        result.cardDraws.compactMap { if case .shiny(let c) = $0 { c } else { nil } }
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Text(stage.name)
                        .font(AppFont.rounded(17, relativeTo: .headline))
                        .foregroundStyle(Palette.ink.opacity(0.6))

                    stars
                    scoreCard

                    if !newlySparkling.isEmpty { sparklePanel }
                    if !newCards.isEmpty || !shinyCards.isEmpty { cardPanel }

                    buttons
                }
                .padding(20)
            }
        }
        .navigationBarBackButtonHidden()
        .task { await revealStars() }
    }

    // MARK: - Pieces

    private var stars: some View {
        HStack(spacing: 10) {
            ForEach(1...3, id: \.self) { i in
                Text(i <= result.stars ? "⭐️" : "☆")
                    .font(.system(size: 54))
                    .opacity(i <= revealedStars ? 1 : (i <= result.stars ? 0 : 0.28))
                    .scaleEffect(i <= revealedStars ? 1 : 0.5)
                    .animation(reduceMotion ? nil : .spring(duration: 0.4), value: revealedStars)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("ほし \(result.stars) こ")
    }

    private var scoreCard: some View {
        VStack(spacing: 4) {
            Text("\(result.score)")
                .font(AppFont.rounded(44, relativeTo: .largeTitle))
                .foregroundStyle(Palette.orange)
            Text("てん")
                .font(AppFont.rounded(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink.opacity(0.6))

            if let best = app.save.data.record(forStage: stage.index), best.score > result.score {
                Text("さいこう \(best.score) てん")
                    .font(AppFont.rounded(12, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var sparklePanel: some View {
        VStack(spacing: 10) {
            Text("✨ キラキラに なった けん!")
                .font(AppFont.rounded(18, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            FlowRow(spacing: 8) {
                ForEach(newlySparkling, id: \.self) { code in
                    Text(app.mapData[code]?.kana ?? "")
                        .font(AppFont.rounded(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Palette.gold.opacity(0.28), in: Capsule())
                        .overlay { Capsule().strokeBorder(Palette.gold, lineWidth: 1.5) }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var cardPanel: some View {
        VStack(spacing: 10) {
            Text("とくさんひん カード")
                .font(AppFont.rounded(18, relativeTo: .headline))
                .foregroundStyle(Palette.ink)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                      spacing: 10) {
                ForEach(newCards) { card in
                    CardChipView(card: card, ownedCount: 1, showsDescription: false)
                }
                ForEach(shinyCards) { card in
                    CardChipView(card: card, ownedCount: 2, showsDescription: false)
                }
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button("もういちど") { onReplay() }
                .buttonStyle(.bouncy)
            Button("ステージを えらぶ") { onExit() }
                .buttonStyle(.bouncy(Palette.teal, fontSize: 18))
        }
        .padding(.top, 4)
    }

    /// Stars land one at a time so each one gets its moment.
    private func revealStars() async {
        guard !reduceMotion else { revealedStars = result.stars; return }
        for i in 1...max(1, result.stars) {
            try? await Task.sleep(for: .milliseconds(320))
            revealedStars = i
            SoundService.shared.play(.star, enabled: app.save.data.settings.soundEnabled)
        }
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
