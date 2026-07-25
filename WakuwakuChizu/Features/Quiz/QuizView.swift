import SwiftUI

/// The play screen: question, map, score. All rules live in `QuizViewModel`;
/// this drives presentation and the timing of the advance.
struct QuizView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let stage: Stage
    var onFinish: (StageResult) -> Void

    @State private var quiz: QuizViewModel?
    @State private var advanceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            if let quiz {
                content(quiz)
            }
        }
        .navigationBarBackButtonHidden()
        .task {
            guard quiz == nil else { return }
            quiz = QuizViewModel(stage: stage,
                                 mapData: app.mapData,
                                 catalog: app.cards,
                                 ownedCards: app.save.data.cards)
        }
        .onDisappear { advanceTask?.cancel() }
    }

    // MARK: - Layout

    private func content(_ quiz: QuizViewModel) -> some View {
        VStack(spacing: 12) {
            header(quiz)
            question(quiz)
            map(quiz)
            footer(quiz)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func header(_ quiz: QuizViewModel) -> some View {
        HStack(spacing: 12) {
            Button { leave() } label: { Text("←") }
                .buttonStyle(CircleIconButtonStyle(diameter: 42))
                .accessibilityLabel("やめる")

            ProgressPips(current: quiz.questionNumber, total: quiz.questionCount)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(quiz.score)")
                    .font(AppFont.rounded(22, relativeTo: .title3))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                if quiz.combo >= 2 {
                    Text("\(quiz.combo) れんぞく!")
                        .font(AppFont.rounded(12, relativeTo: .caption))
                        .foregroundStyle(Palette.orange)
                }
            }
            .animation(.snappy, value: quiz.score)
        }
    }

    private func question(_ quiz: QuizViewModel) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 1) {
                Text(quiz.target?.kana ?? "")
                    .font(AppFont.rounded(28, relativeTo: .title))
                    .foregroundStyle(Palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                // Kanji stays secondary: the reading is what a 5-year-old uses.
                Text(quiz.target?.name ?? "")
                    .font(AppFont.rounded(13, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.5))
            }
            Text("は どこかな?")
                .font(AppFont.rounded(19, relativeTo: .title3))
                .foregroundStyle(Palette.ink)

            Button { speak(quiz) } label: { Text("🔊") }
                .buttonStyle(CircleIconButtonStyle(diameter: 44))
                .accessibilityLabel("もんだいを よむ")

            if app.isVoiceModeAvailable {
                Button { toggleListening(quiz) } label: {
                    Text(app.voice.isListening ? "🎙️" : "🎤")
                }
                .buttonStyle(CircleIconButtonStyle(
                    background: app.voice.isListening ? Palette.teal : .white,
                    diameter: 44))
                .accessibilityLabel(app.voice.isListening ? "きいています" : "こえで こたえる")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
    }

    private func map(_ quiz: QuizViewModel) -> some View {
        PrefectureMapView(
            mapData: app.mapData,
            codes: quiz.order,
            appearance: { appearance(for: $0, quiz: quiz) },
            interactiveCodes: quiz.interactiveCodes,
            targetCode: quiz.target?.code,
            hintCode: quiz.hintCode,
            effect: quiz.effect,
            onTap: { handleTap($0, quiz: quiz) })
        .aspectRatio(PrefectureGeometry.aspectRatio(
            of: app.mapData.prefectures(in: quiz.order)), contentMode: .fit)
        .background(Palette.seaGradient)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func footer(_ quiz: QuizViewModel) -> some View {
        ZStack {
            // Reserved height so the map does not jump when the card appears.
            Color.clear.frame(height: 74)
            if let draw = quiz.lastDraw {
                CardWinBanner(draw: draw)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else if quiz.attempts >= GameRules.missesBeforeHint {
                Text("ひかっている ところだよ")
                    .font(AppFont.rounded(16, relativeTo: .body))
                    .foregroundStyle(Palette.ink.opacity(0.75))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: quiz.lastDraw)
    }

    // MARK: - Appearance

    private func appearance(for pref: Prefecture, quiz: QuizViewModel) -> PrefectureAppearance {
        let answered = quiz.answeredCodes.contains(pref.code)
        return PrefectureAppearance(
            fill: answered ? Palette.fill(for: pref.code) : Palette.unlearned,
            stroke: .white,
            lineWidth: 1.2,
            // The emoji rises only on the prefecture just won, and only while
            // its celebration is on screen.
            badge: answered && quiz.effect?.code == pref.code && quiz.phase == .celebrating
                ? quiz.lastDraw?.card.emoji : nil)
    }

    // MARK: - Actions

    private func handleTap(_ prefecture: Prefecture?, quiz: QuizViewModel) {
        guard let prefecture else { return }
        switch quiz.answer(prefecture.code) {
        case .correct:
            SoundService.shared.play(.correct, enabled: app.save.data.settings.soundEnabled)
            scheduleAdvance(quiz)
        case .wrong:
            SoundService.shared.play(.wrong, enabled: app.save.data.settings.soundEnabled)
        case .ignored:
            break
        }
    }

    /// Let the pop and the card land before moving on (CLAUDE.md §5).
    private func scheduleAdvance(_ quiz: QuizViewModel) {
        advanceTask?.cancel()
        advanceTask = Task {
            try? await Task.sleep(for: .seconds(GameRules.correctAdvanceDelay))
            guard !Task.isCancelled else { return }
            quiz.advance()
            if quiz.phase == .finished {
                onFinish(quiz.makeResult())
            } else {
                speak(quiz)
            }
        }
    }

    /// Voice answering is an alternative to tapping, never a replacement:
    /// the map stays live the whole time (CLAUDE.md §7).
    private func toggleListening(_ quiz: QuizViewModel) {
        guard app.isVoiceModeAvailable else { return }
        if app.voice.isListening {
            app.voice.stop()
            return
        }
        let candidates = app.mapData.prefectures(in: Array(quiz.interactiveCodes))
        app.voice.start { heard in
            guard let match = PrefectureNameMatcher.match(heard, among: candidates) else { return }
            app.voice.stop()
            handleTap(match, quiz: quiz)
        }
    }

    private func speak(_ quiz: QuizViewModel) {
        guard app.save.data.settings.speechEnabled, let target = quiz.target else { return }
        SpeechService.shared.speak("\(target.kana)は、どこかな?")
    }

    private func leave() {
        advanceTask?.cancel()
        SpeechService.shared.stop()
        app.voice.stop()
        dismiss()
    }
}

// MARK: - Pieces

private struct ProgressPips: View {
    let current: Int
    let total: Int

    var body: some View {
        Text("\(current) / \(total)")
            .font(AppFont.rounded(15, relativeTo: .subheadline))
            .foregroundStyle(Palette.ink.opacity(0.6))
            .monospacedDigit()
            .accessibilityLabel("\(total) もんちゅう \(current) もんめ")
    }
}

private struct CardWinBanner: View {
    let draw: GameRules.CardDraw

    private var headline: String {
        switch draw {
        case .new: "カードを もらったよ!"
        case .shiny: "キラカードに なった!"
        case .duplicate: "もっている カードだね"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(draw.card.emoji).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(AppFont.rounded(13, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                Text(draw.card.nameKana)
                    .font(AppFont.rounded(19, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.white, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            if case .shiny = draw {
                RoundedRectangle(cornerRadius: 18).strokeBorder(Palette.gold, lineWidth: 2.5)
            }
        }
    }
}
