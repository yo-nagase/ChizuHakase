import SwiftUI

/// End-of-stage summary: stars, score, cards won and any prefecture that
/// reached mastery level 3 (CLAUDE.md §5).
///
/// Everything here is a gain. There is no "you lost" state to show.
struct ResultView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.textMode) private var mode

    let stage: Stage
    let result: StageResult
    /// Prefectures that hit level 3 in this run, from `SaveStore`.
    let newlySparkling: [Int]
    var onReplay: () -> Void
    var onExit: () -> Void

    @State private var revealedStars = 0
    @State private var celebrating = false

    private var newCards: [SpecialtyCard] {
        result.cardDraws.compactMap { if case .new(let c) = $0 { c } else { nil } }
    }
    private var shinyCards: [SpecialtyCard] {
        result.cardDraws.compactMap { if case .shiny(let c) = $0 { c } else { nil } }
    }

    var body: some View {
        ZStack {
            AlbumPage()
            ScrollView {
                VStack(spacing: 18) {
                    Text(stage.displayName(mode))
                        .font(AppFont.rounded(18, relativeTo: .headline))
                        .foregroundStyle(Palette.ink.opacity(0.65))

                    stars
                    scoreCard

                    if !newlySparkling.isEmpty { sparklePanel }
                    if !newCards.isEmpty || !shinyCards.isEmpty { cardPanel }

                    buttons
                }
                .padding(20)
            }
            if celebrating {
                ConfettiView()
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .navigationBarBackButtonHidden()
        .task { await revealStars() }
    }

    // MARK: - Pieces

    private var stars: some View {
        HStack(spacing: 12) {
            ForEach(1...3, id: \.self) { i in
                StarBadge(filled: i <= revealedStars, size: 54)
                    // Each star lands slightly crooked, the way a child presses
                    // a sticker down. Same tilt every time so it reads as
                    // placement, not as jitter.
                    .rotationEffect(.degrees(i <= revealedStars ? Double(i - 2) * 6 : 0))
                    .scaleEffect(i <= revealedStars ? 1 : 0.55)
                    .opacity(i <= result.stars ? 1 : 0.3)
                    .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.45),
                               value: revealedStars)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.starCount(result.stars))
    }

    private var scoreCard: some View {
        VStack(spacing: 4) {
            Text(verbatim: "\(result.score)")
                .font(AppFont.rounded(46, relativeTo: .largeTitle))
                .monospacedDigit()
                .stickerPill()
            Text(mode.points)
                .font(AppFont.rounded(15, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink.opacity(0.6))

            if let best = app.save.data.record(forStage: stage.index, mode: result.mode),
               best.score > result.score {
                Text(verbatim: "\(mode.bestScore) \(best.score) \(mode.points)")
                    .font(AppFont.rounded(12, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .stickerCard(cornerRadius: 24)
    }

    private var sparklePanel: some View {
        VStack(spacing: 10) {
            Text(mode.becameSparkling)
                .font(AppFont.rounded(19, relativeTo: .headline))
                .foregroundStyle(Palette.ink)
            FlowRow(spacing: 8) {
                ForEach(newlySparkling, id: \.self) { code in
                    Text(app.mapData[code]?.displayName(mode) ?? "")
                        .font(AppFont.rounded(15, relativeTo: .subheadline))
                        .foregroundStyle(Palette.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Palette.gold.opacity(0.3), in: Capsule())
                        .overlay { Capsule().strokeBorder(Palette.gold, lineWidth: 2) }
                        .shadow(color: Palette.stickerShadow, radius: 0, y: 2)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .stickerCard(cornerRadius: 24, isHolographic: true)
    }

    private var cardPanel: some View {
        VStack(spacing: 10) {
            Text(mode.specialtyCards)
                .font(AppFont.rounded(19, relativeTo: .headline))
                .foregroundStyle(Palette.ink)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: typeSize.cardColumns), spacing: 10) {
                ForEach(newCards) { card in
                    CardChipView(card: card, prefecture: app.mapData[card.prefectureCode],
                                 ownedCount: 1)
                }
                ForEach(shinyCards) { card in
                    CardChipView(card: card, prefecture: app.mapData[card.prefectureCode],
                                 ownedCount: 2)
                }
            }
        }
        .padding(16)
        .stickerCard(cornerRadius: 24)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            Button(mode.playAgain) { onReplay() }
                .buttonStyle(.bouncy)
            Button(mode.chooseStage) { onExit() }
                .buttonStyle(.bouncy(Palette.teal, fontSize: 18))
        }
        .padding(.top, 4)
    }

    /// Stars press on one at a time so each one gets its moment, then the
    /// confetti falls.
    private func revealStars() async {
        guard !reduceMotion else {
            revealedStars = result.stars
            return
        }
        for i in 1...max(1, result.stars) {
            try? await Task.sleep(for: .milliseconds(340))
            revealedStars = i
            SoundService.shared.play(.star, enabled: app.save.data.settings.soundEnabled)
        }
        celebrating = true
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
