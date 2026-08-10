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
    @State private var opened: WonCard?

    /// A card this run won, at the star count it ended on.
    ///
    /// Carries its own stars rather than reading them back out of the save, so
    /// the card that opens agrees with the chip that was tapped even on the
    /// debug route, which reaches this screen with a result never persisted.
    private struct WonCard: Identifiable {
        let card: SpecialtyCard
        let stars: Int
        var id: String { card.id }
    }

    /// What this run moved, each card as it ended up.
    ///
    /// Deduped, keeping the highest: one stage can put two stars on the same
    /// card, and showing it twice would read as two cards. Draws that gained
    /// nothing are left out — the panel is for what changed.
    private var wonCards: [WonCard] {
        var best: [String: WonCard] = [:]
        for draw in result.cardDraws {
            if case .duplicate = draw { continue }
            if let existing = best[draw.card.id], existing.stars >= draw.stars { continue }
            best[draw.card.id] = WonCard(card: draw.card, stars: draw.stars)
        }
        // Walked in draw order, so the cards appear in the order they were won.
        return result.cardDraws.compactMap { best.removeValue(forKey: $0.card.id) }
    }

    /// The card's next goal, from the save — which the result has already been
    /// applied to, so the streak and any fresh rainbow are current. Stars come
    /// from the run so the caption agrees with the chip above it even on the
    /// debug route, which shows results that were never persisted.
    private func nextGoal(for won: WonCard) -> GameRules.NextGoal? {
        GameRules.nextGoal(stars: won.stars,
                           streak: app.save.data.streak(of: won.card.prefectureCode),
                           isRainbow: app.save.data.isRainbow(won.card.id))
    }

    /// Opens with the cover's own slide suppressed, on the same terms as the
    /// card book: a card is picked up out of depth, not pushed onto the desk
    /// from the bottom edge.
    private func open(_ won: WonCard) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { opened = won }
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
                    if !wonCards.isEmpty { cardPanel }

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
        // The card just won is the one a child most wants to look at, and this
        // is the only screen that names it. Opening it here is a layer over the
        // celebration, not a way out of it — closing comes back to the stars.
        .fullScreenCover(item: $opened) { won in
            CardDetailView(card: won.card,
                           prefecture: app.mapData[won.card.prefectureCode],
                           stars: won.stars,
                           rainbow: app.save.data.isRainbow(won.card.id),
                           streak: app.save.data.streak(of: won.card.prefectureCode))
                .environment(\.textMode, mode)
                .presentationBackground(.clear)
        }
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
                ForEach(wonCards) { won in
                    VStack(spacing: 5) {
                        CardChipView(card: won.card,
                                     prefecture: app.mapData[won.card.prefectureCode],
                                     stars: won.stars,
                                     rainbow: app.save.data.isRainbow(won.card.id),
                                     onOpen: { open(won) })
                        // 「あと◯」 — the reason to play this stage once more,
                        // said while the card is still in front of them.
                        if let goal = nextGoal(for: won) {
                            Text(mode.nextGoalLabel(goal))
                                .font(AppFont.rounded(11, relativeTo: .caption2))
                                .foregroundStyle(Palette.ink.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
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
