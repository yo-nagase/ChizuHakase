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
    var quizMode: QuizMode = .findOnMap
    var onFinish: (StageResult) -> Void

    @State private var quiz: QuizViewModel?
    @State private var advanceTask: Task<Void, Never>?
    /// Voice mode is a switch, not push-to-talk: once on it stays on until the
    /// button is pressed again. Each question still gets its own recognition
    /// session — the observers in `body` re-arm the microphone whenever
    /// whatever stopped it (an answer, an announcement) has passed.
    @State private var voiceModeOn = false
    @State private var rearmTask: Task<Void, Never>?
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var comboBurst: ComboBurst?
    @State private var burstCount = 0

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
            let model = QuizViewModel(stage: stage,
                                      mode: quizMode,
                                      mapData: app.mapData,
                                      catalog: app.cards,
                                      ownedCards: app.save.data.cards)
            quiz = model
            // The first question was the only one never read aloud: speech
            // fired on advancing to the *next* question, and the first question
            // is never advanced to. For a child who cannot read hiragana that
            // is the question they cannot start.
            announce(model)
        }
        // The microphone never simply runs: it is stopped around every answer
        // (for audible feedback and a fresh transcript) and around every
        // announcement (open during one, it hears the app say the answer's own
        // name). These two observers are what bring it back afterwards, so the
        // mode outlives each individual recognition session.
        .onChange(of: app.voice.isListening) { _, listening in
            guard !listening, let quiz else { return }
            scheduleVoiceRearm(quiz)
        }
        .onChange(of: SpeechService.shared.isSpeaking) { _, speaking in
            guard !speaking, let quiz else { return }
            rearmVoice(quiz)
        }
        .onDisappear {
            advanceTask?.cancel()
            rearmTask?.cancel()
            // Finishing a stage can leave the mode on with a session open;
            // the microphone must not follow onto the result screen.
            if app.voice.isListening { app.voice.stop() }
        }
    }

    // MARK: - Layout

    private func content(_ quiz: QuizViewModel) -> some View {
        VStack(spacing: 12) {
            header(quiz)
            question(quiz)
            Spacer(minLength: 0)
            map(quiz)
            Spacer(minLength: 0)
            if quiz.mode == .nameIt { choiceGrid(quiz) }
            footer(quiz)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
        .pageColumn()
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
                        prompt(quiz)
                        Spacer(minLength: 0)
                        speakButton(quiz)
                        micButton(quiz)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    questionName(quiz)
                    prompt(quiz)
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
            Text(quiz.mode == .nameIt ? mode.nameItQuestion
                                      : (quiz.target?.displayName(mode) ?? ""))
                .font(AppFont.rounded(31, relativeTo: .title))
                .foregroundStyle(Palette.ink)
                // Side by side with the prompt there is only room for one line,
                // so shrink slightly rather than wrap. In the stacked
                // accessibility layout the name owns the full width and may
                // wrap — what it must never do is truncate.
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
            // Kanji stays secondary: the reading is what a 5-year-old uses. Not
            // caption-sized though — kanji packs many more strokes into the same
            // em box than kana does, so 「宮城県」 set at the size that suits
            // 「みやぎけん」 is a grey smudge rather than characters a child can
            // start to recognise.
            Text(quiz.mode == .nameIt ? mode.nameItPrompt
                                      : (quiz.target?.secondaryName(mode) ?? ""))
                .font(AppFont.rounded(16, relativeTo: .subheadline))
                .foregroundStyle(Palette.ink.opacity(0.5))
        }
    }

    @ViewBuilder private func prompt(_ quiz: QuizViewModel) -> some View {
        if quiz.mode == .findOnMap { promptText }
    }

    private var promptText: some View {
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
            // Keyed to the mode, not to isListening: the session drops for a
            // beat between questions, and a button that flickered off there
            // would look like the mode had turned itself off.
            Button { toggleVoiceMode(quiz) } label: {
                Text(voiceModeOn ? "🎙️" : "🎤")
            }
            .buttonStyle(CircleIconButtonStyle(
                background: voiceModeOn ? Palette.teal : .white,
                diameter: 44))
            .accessibilityLabel(voiceModeOn ? mode.listening : mode.answerByVoice)
        }
    }

    /// Pinchable, so 全国チャレンジ is playable: 47 prefectures in one frame puts
    /// Kagawa and Osaka at a few points across, and a child who cannot see a
    /// shape cannot learn it. The tap allowance shrinks with the zoom so
    /// magnifying never turns into a wider net.
    private func map(_ quiz: QuizViewModel) -> some View {
        PrefectureMapView(
            mapData: app.mapData,
            codes: quiz.order,
            appearance: { appearance(for: $0, quiz: quiz) },
            interactiveCodes: quiz.mode == .nameIt ? [] : quiz.interactiveCodes,
            targetCode: quiz.target?.code,
            hintCode: quiz.hintCode,
            effect: quiz.effect,
            zoom: zoom,
            comboBurst: comboBurst,
            onTap: { handleTap($0, at: .point($1), quiz: quiz) })
        .aspectRatio(PrefectureGeometry.aspectRatio(
            of: app.mapData.prefectures(in: quiz.order)), contentMode: .fit)
        .zoomPan(scale: $zoom, offset: $pan, oneFingerZoom: true)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(Palette.seaGradient)
        .stickerCard(fill: .clear, cornerRadius: 26)
        .overlay(alignment: .topTrailing) { resetZoomButton }
        // Reaches wider than the rest of the column. The map is limited by the
        // screen's width, never its height, so every point of margin here is a
        // point off how big each prefecture is drawn — and this is the one
        // element on the screen the child has to aim at.
        .padding(.horizontal, -10)
        // Every question starts on the whole map. Staying zoomed would let a
        // child be asked about a prefecture that is off screen — and panning to
        // it automatically would point straight at the answer.
        .onChange(of: quiz.questionNumber) { _, _ in
            zoom = 1
            pan = .zero
            comboBurst = nil
        }
    }

    @ViewBuilder private var resetZoomButton: some View {
        if ZoomPan.isZoomed(zoom) {
            Button(mode.resetZoom) {
                let reset = { zoom = 1; pan = .zero }
                if reduceMotion { reset() } else { withAnimation(.spring(duration: 0.3), reset) }
            }
            .font(AppFont.rounded(13, relativeTo: .caption))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.92)))
            .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.12)))
            .padding(10)
        }
    }

    @ViewBuilder
    /// The four names.
    ///
    /// Two columns rather than four in a row: at 47 prefectures the names run
    /// long (「かごしまけん」), and a row of four would shrink them past reading
    /// size for the child who most needs to read them.
    private func choiceGrid(_ quiz: QuizViewModel) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                  spacing: 10) {
            ForEach(quiz.choices, id: \.self) { code in
                if let pref = app.mapData[code] {
                    ChoiceButton(
                        title: pref.displayName(mode),
                        isRuledOut: quiz.ruledOut.contains(code),
                        isAnswer: quiz.phase != .asking && quiz.target?.code == code,
                        reduceMotion: reduceMotion
                    ) {
                        handleTap(pref, at: .prefecture(code), quiz: quiz)
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy, value: quiz.ruledOut)
    }

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
        // 「なまえを あてる」 asks about the one that is lit, so it stays lit until
        // it is answered — including through a wrong guess, when the child needs
        // to look at it again rather than hunt for what the question was.
        if quiz.mode == .nameIt, quiz.phase == .asking, quiz.target?.code == pref.code {
            return .spotlit(for: pref.code)
        }
        // Answering does not colour a prefecture in.
        //
        // It used to: each correct answer stuck that prefecture down in full
        // colour, so by the last question of a seven-prefecture stage there was
        // exactly one pale shape left and the question answered itself. The
        // celebration is the pop and the card, both of which pass — what stays
        // on screen has to stay a question.
        let isCelebrating = quiz.effect?.code == pref.code && quiz.phase == .celebrating
        guard isCelebrating else { return .slot(for: pref.code) }
        return .stuck(for: pref.code, badge: quiz.lastDraw?.card.emoji)
    }

    // MARK: - Actions

    private func handleTap(_ prefecture: Prefecture?, at anchor: ComboBurst.Anchor,
                           quiz: QuizViewModel) {
        guard let prefecture else { return }
        // Whichever of finger or voice answered, an open session ends here:
        // while it holds the audio for recording the feedback sound is
        // inaudible, a lingering transcript pollutes the next match — and on a
        // correct answer the next question is about to be read aloud.
        if app.voice.isListening { app.voice.stop() }
        switch quiz.answer(prefecture.code) {
        case .correct:
            SoundService.shared.play(.correct, enabled: app.save.data.settings.soundEnabled)
            showComboBurst(quiz, at: anchor)
            scheduleAdvance(quiz)
        case .wrong:
            SoundService.shared.play(.wrong, enabled: app.save.data.settings.soundEnabled)
        case .ignored:
            break
        }
    }

    /// Calls out a run of first-try answers, where the finger landed.
    ///
    /// Nothing is shown for a streak of one, because every correct answer would
    /// then carry a badge and the badge would stop meaning anything.
    private func showComboBurst(_ quiz: QuizViewModel, at anchor: ComboBurst.Anchor) {
        let tier = GameRules.comboTier(quiz.combo)
        guard tier > 0 else { return comboBurst = nil }
        burstCount += 1
        comboBurst = ComboBurst(text: "\(quiz.combo) \(mode.combo)",
                                anchor: anchor, tier: tier, id: burstCount)
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
                announce(quiz)
                // When nothing was announced (「なまえを あてる」, or speech
                // switched off) the next question's session starts right here;
                // with an announcement, the isSpeaking observer starts it once
                // the reading ends.
                rearmVoice(quiz)
            }
        }
    }

    /// Voice answering is an alternative to tapping, never a replacement:
    /// the map stays live the whole time (CLAUDE.md §7).
    private func toggleVoiceMode(_ quiz: QuizViewModel) {
        guard app.isVoiceModeAvailable else { return }
        if voiceModeOn {
            voiceModeOn = false
            rearmTask?.cancel()
            app.voice.stop()
        } else {
            voiceModeOn = true
            // If a question is mid-announcement this does nothing, and the
            // isSpeaking observer arms the microphone when the reading ends —
            // opening it during one would let it hear the answer's name.
            rearmVoice(quiz)
        }
    }

    /// One recognition session, scoped to the current question.
    private func startListening(_ quiz: QuizViewModel) {
        // Only the names actually on offer: in 「なまえを あてる」 a child saying
        // a prefecture that is not one of the four has not answered the
        // question, and scoring it would be scoring the wrong thing.
        let codes = quiz.mode == .nameIt ? quiz.choices : Array(quiz.interactiveCodes)
        let candidates = app.mapData.prefectures(in: codes)
        app.voice.start { heard in
            guard let match = PrefectureNameMatcher.match(heard, among: candidates) else { return }
            // A spoken answer has no fingertip to aim at.
            handleTap(match, at: .prefecture(match.code), quiz: quiz)
        }
    }

    /// Bring the microphone back, if the mode is on and nothing is in its way.
    private func rearmVoice(_ quiz: QuizViewModel) {
        guard voiceModeOn, app.isVoiceModeAvailable,
              quiz.phase == .asking,
              !app.voice.isListening,
              !SpeechService.shared.isSpeaking else { return }
        startListening(quiz)
    }

    /// Re-arm after a beat rather than instantly. The pause lets the answer
    /// feedback play before the session takes the audio back, and it keeps a
    /// recogniser that gives up on silence from spinning in a restart loop.
    private func scheduleVoiceRearm(_ quiz: QuizViewModel) {
        guard voiceModeOn else { return }
        rearmTask?.cancel()
        rearmTask = Task {
            try? await Task.sleep(for: .seconds(0.6))
            guard !Task.isCancelled else { return }
            rearmVoice(quiz)
        }
    }

    /// Spoken by itself when a question appears.
    ///
    /// Only in 「ちずで さがす」, where the sentence carries the question: it
    /// names a different prefecture every time. 「なまえを あてる」 asks the same
    /// sentence every time and the answer is on the map, so reading anything
    /// automatically there is noise on a loop — and reading the four choices,
    /// which is what it used to do, is fourteen names a question that say
    /// nothing about which one is right.
    private func announce(_ quiz: QuizViewModel) {
        guard quiz.mode == .findOnMap else { return }
        speak(quiz)
    }

    /// The 🔊 button, which is always a deliberate press.
    ///
    /// In 「なまえを あてる」 it must never say the target's name — that *is* the
    /// answer — so it reads the instruction, which is what a child who cannot
    /// read the screen actually needs from it (CLAUDE.md §7).
    private func speak(_ quiz: QuizViewModel) {
        guard app.save.data.settings.speechEnabled else { return }
        // The microphone gives way to the announcement: holding the session
        // open would silence the reading — and in 「ちずで さがす」 the reading
        // names the answer, which an open microphone would hear and score.
        // The isSpeaking observer re-arms it afterwards if the mode is on.
        if app.voice.isListening { app.voice.stop() }
        if quiz.mode == .nameIt {
            // Two phrases, not one string: the question and the instruction are
            // separate things to hear.
            return SpeechService.shared.speak([mode.nameItQuestion, mode.nameItPrompt])
        }
        guard let target = quiz.target else { return }
        SpeechService.shared.speak("\(target.kana)は、どこかな?")
    }

    private func leave() {
        advanceTask?.cancel()
        rearmTask?.cancel()
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

    private var tier: CardTier { draw.tier }

    /// Crossing into silver or gold is the news; a star that lands inside a tier
    /// is still worth saying, and the stars underneath show how far it got.
    private var headline: String {
        switch draw {
        case .new: mode.cardWonNew
        case .duplicate: mode.cardWonDuplicate
        case .star:
            switch (draw.promoted, tier) {
            case (true, .gold): mode.cardWonGold
            case (true, .silver): mode.cardWonSilver
            default: mode.cardWonStar
            }
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // A card with a picture shows it here too, so the moment it is won
            // looks like what the card book will show afterwards.
            if tier.isSpecial, let art = draw.card.art {
                Image(art)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 44, height: 44)
            } else {
                Text(draw.card.emoji).font(.system(size: 30))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(AppFont.rounded(13, relativeTo: .caption))
                    .foregroundStyle(Palette.ink.opacity(0.65))
                HStack(spacing: 6) {
                    Text(draw.card.displayName(mode))
                        .font(AppFont.rounded(20, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                    // 「ほしが ふえた!」 says something changed; this says how far
                    // it got, which is the part worth watching climb.
                    Text(String(repeating: "★", count: draw.stars))
                        .font(AppFont.rounded(12, relativeTo: .caption2))
                        .foregroundStyle(tier == .gold ? Palette.gold
                                         : tier == .silver ? Palette.silverMark
                                         : Palette.ink.opacity(0.3))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .stickerCard(cornerRadius: 18, isHolographic: tier.isSpecial)
    }
}

/// One name in 「なまえを あてる」.
///
/// A ruled-out name stays on screen, dimmed and unpressable, rather than
/// disappearing. A choice that vanishes takes with it the memory of having
/// tried it, and a child who cannot see what they already ruled out will try it
/// again.
private struct ChoiceButton: View {
    let title: String
    let isRuledOut: Bool
    let isAnswer: Bool
    let reduceMotion: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AppFont.rounded(19, relativeTo: .headline))
                .foregroundStyle(isRuledOut ? Palette.ink.opacity(0.35) : Palette.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(fill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isAnswer ? Palette.gold : .clear, lineWidth: 3)
                )
        }
        .buttonStyle(ChoicePressStyle(reduceMotion: reduceMotion))
        .disabled(isRuledOut)
        .accessibilityLabel(title)
        .accessibilityHint(isRuledOut ? "ちがったよ" : "")
    }

    private var fill: Color {
        if isAnswer { return Palette.gold.opacity(0.35) }
        return isRuledOut ? Color(hex: 0xEDE7DA) : .white
    }
}

private struct ChoicePressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.spring(duration: 0.16), value: configuration.isPressed)
    }
}
