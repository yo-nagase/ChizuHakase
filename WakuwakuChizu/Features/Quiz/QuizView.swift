import SwiftUI

/// The play screen: question, map, score. All rules live in `QuizViewModel`;
/// this drives presentation and the timing of the advance.
struct QuizView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.textMode) private var mode

    let stage: Stage
    var onFinish: (StageResult) -> Void

    @State private var quiz: QuizViewModel?
    @State private var advanceTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AlbumPage()
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
            Spacer(minLength: 0)
            map(quiz)
            Spacer(minLength: 0)
            footer(quiz)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func header(_ quiz: QuizViewModel) -> some View {
        HStack(spacing: 12) {
            Button { leave() } label: { Text("←") }
                .buttonStyle(CircleIconButtonStyle(diameter: 42))
                .accessibilityLabel(mode.quit)

            ProgressPips(current: quiz.questionNumber, total: quiz.questionCount)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text(verbatim: "\(quiz.score)")
                    .font(AppFont.rounded(20, relativeTo: .title3))
                    .monospacedDigit()
                    .stickerPill()
                    .contentTransition(.numericText())
                if quiz.combo >= 2 {
                    Text("\(quiz.combo) \(mode.combo)")
                        .font(AppFont.rounded(12, relativeTo: .caption))
                        .foregroundStyle(Palette.orange)
                }
            }
            .animation(.snappy, value: quiz.score)
        }
    }

    /// The question is the one thing on screen that must always be fully
    /// readable, so at accessibility sizes it gets its own line rather than
    /// competing with the prompt and the buttons for horizontal space.
    /// It previously truncated to 「とうき…」, which hides the entire question.
    private func question(_ quiz: QuizViewModel) -> some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    questionName(quiz)
                    HStack(spacing: 10) {
                        prompt
                        Spacer(minLength: 0)
                        speakButton(quiz)
                        micButton(quiz)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    questionName(quiz)
                    prompt
                    speakButton(quiz)
                    micButton(quiz)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .stickerCard()
    }

    private func questionName(_ quiz: QuizViewModel) -> some View {
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .center, spacing: 1) {
            Text(quiz.target?.displayName(mode) ?? "")
                .font(AppFont.rounded(31, relativeTo: .title))
                .foregroundStyle(Palette.ink)
                // Side by side with the prompt there is only room for one line,
                // so shrink slightly rather than wrap. In the stacked
                // accessibility layout the name owns the full width and may
                // wrap — what it must never do is truncate.
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            // Kanji stays secondary: the reading is what a 5-year-old uses.
            Text(quiz.target?.secondaryName(mode) ?? "")
                .font(AppFont.rounded(13, relativeTo: .caption))
                .foregroundStyle(Palette.ink.opacity(0.5))
        }
    }

    private var prompt: some View {
        Text(mode.questionSuffix)
            .font(AppFont.rounded(19, relativeTo: .title3))
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func speakButton(_ quiz: QuizViewModel) -> some View {
        Button { speak(quiz) } label: { Text("🔊") }
            .buttonStyle(CircleIconButtonStyle(diameter: 44))
            .accessibilityLabel(mode.readAloud)
    }

    @ViewBuilder
    private func micButton(_ quiz: QuizViewModel) -> some View {
        if app.isVoiceModeAvailable {
            Button { toggleListening(quiz) } label: {
                Text(app.voice.isListening ? "🎙️" : "🎤")
            }
            .buttonStyle(CircleIconButtonStyle(
                background: app.voice.isListening ? Palette.teal : .white,
                diameter: 44))
            .accessibilityLabel(app.voice.isListening ? mode.listening : mode.answerByVoice)
        }
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
        .stickerCard(fill: .clear, cornerRadius: 26)
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
                Text(mode.hintNudge)
                    .font(AppFont.rounded(16, relativeTo: .body))
                    .foregroundStyle(Palette.ink.opacity(0.75))
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.35), value: quiz.lastDraw)
    }

    // MARK: - Appearance

    private func appearance(for pref: Prefecture, quiz: QuizViewModel) -> PrefectureAppearance {
        guard quiz.answeredCodes.contains(pref.code) else {
            // Pre-printed slot, not a grey blank: the map should look like a
            // sticker album waiting to be filled from the very first question.
            return .slot(for: pref.code)
        }
        // The emoji rises only on the prefecture just won, and only while its
        // celebration is on screen.
        let isCelebrating = quiz.effect?.code == pref.code && quiz.phase == .celebrating
        return .stuck(for: pref.code,
                      badge: isCelebrating ? quiz.lastDraw?.card.emoji : nil)
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
    @Environment(\.textMode) private var mode
    let current: Int
    let total: Int

    var body: some View {
        Text("\(current) / \(total)")
            .font(AppFont.rounded(15, relativeTo: .subheadline))
            .foregroundStyle(Palette.ink.opacity(0.6))
            .monospacedDigit()
            .accessibilityLabel(mode.questionCounter(current, total))
    }
}

private struct CardWinBanner: View {
    @Environment(\.textMode) private var mode
    let draw: GameRules.CardDraw

    private var isShiny: Bool {
        if case .shiny = draw { return true }
        return false
    }

    private var headline: String {
        switch draw {
        case .new: mode.cardWonNew
        case .shiny: mode.cardWonShiny
        case .duplicate: mode.cardWonDuplicate
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(draw.card.emoji).font(.system(size: 30))
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(AppFont.rounded(13, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                Text(draw.card.displayName(mode))
                    .font(AppFont.rounded(20, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .stickerCard(cornerRadius: 18, isHolographic: isShiny)
    }
}
