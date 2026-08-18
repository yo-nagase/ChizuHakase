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
    /// The map's frame, measured for the region buttons' framing maths.
    @State private var mapSize: CGSize = .zero
    @State private var comboBurst: ComboBurst?
    @State private var burstCount = 0

    var body: some View {
        ZStack {
            StageAtlasBackground()
            if let quiz {
                content(quiz)
            }
        }
        .navigationBarBackButtonHidden()
        // The stage the child picked, in the same spot that read 「ステージ」
        // one screen earlier — the generic label hands over to the actual
        // destination. The header row below stays free for progress and score.
        .navigationTitle(stage.displayName(mode))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
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
            // Above the map for hit testing: scaleEffect magnifies the touch
            // region along with the drawing, so the zoomed map — a later
            // sibling — otherwise swallows the taps aimed at these rows, and
            // the back button died exactly while a child was zoomed in and
            // most lost. Later siblings (choices, footer) already win.
            header(quiz).zIndex(1)
            question(quiz).zIndex(1)
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

    /// Only in 「ちずで さがす」, where there is a question to re-hear — it
    /// carries a different prefecture name every time. In 「なまえを あてる」
    /// the button could only repeat the fixed instruction: it must not name
    /// the target (that is the answer) and reading the four choices says
    /// nothing about which one is right, so the mode has nothing worth a
    /// speaker button. The answering there is *reading*; a child who cannot
    /// read the choices answers by voice instead.
    @ViewBuilder
    private func speakButton(_ quiz: QuizViewModel) -> some View {
        if quiz.mode == .findOnMap {
            Button { speak(quiz) } label: { Text("🔊") }
                .buttonStyle(CircleIconButtonStyle(diameter: 44))
                .accessibilityLabel(mode.readAloud)
        }
    }

    @ViewBuilder
    private func micButton(_ quiz: QuizViewModel) -> some View {
        // なまえを あてる only. In ちずで さがす the question sentence already
        // says the prefecture's name — speaking that name back is not an
        // answer, so a microphone there has nothing it could listen for.
        if quiz.mode == .nameIt, app.isVoiceModeAvailable {
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
        Group {
            // Regional stages hug the country's own proportions. 全国チャレンジ
            // takes every point of height the column has spare instead: the
            // country cannot be drawn any bigger — the screen's width already
            // caps it — so all the spare height becomes sea, and a zoomed-in
            // child gets that much more viewport to move around in. A frame
            // rather than a taller fixed ratio, so a short screen simply
            // yields a shorter panel instead of shrinking the country to
            // honour a ratio it has no room for.
            if stage.isNationwide {
                mapView(quiz).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                mapView(quiz).aspectRatio(PrefectureGeometry.aspectRatio(
                    of: app.mapData.prefectures(in: quiz.order)), contentMode: .fit)
            }
        }
        .zoomPan(scale: $zoom, offset: $pan, oneFingerZoom: true)
        // The frame the region buttons aim their zoom at — the same size the
        // zoom-pan clamps against, so a framed region obeys the same limits.
        .background {
            GeometryReader { geo in
                Color.clear
                    .onAppear { mapSize = geo.size }
                    .onChange(of: geo.size) { _, new in mapSize = new }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(Palette.seaGradient)
        .stickerCard(fill: .clear, cornerRadius: 26)
        // In the same corner as the region buttons it swaps in for, so the way
        // back out appears exactly where the finger that zoomed just pressed.
        .overlay(alignment: .bottomTrailing) { resetZoomButton }
        // The same pill as my map, but only on 全国チャレンジ: that is the map
        // where Kagawa is a few points across and zooming is how the question
        // becomes answerable. On regional stages the prefectures are already
        // finger-sized, and a pill repeated on every question would be
        // furniture in front of the thing being aimed at. It sits on the
        // northern sea here — the southern edge belongs to the region buttons,
        // and to Okinawa's inset.
        .overlay(alignment: .top) {
            if stage.isNationwide { ZoomHintChip(zoom: zoom).padding(.top, 10) }
        }
        .overlay(alignment: .bottomTrailing) { regionZoomButtons }
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
        // Ahead of the surrounding Spacers, or the flexible nationwide panel
        // would be offered only an equal split of the leftover height and the
        // rest would sit in the margins it was meant to absorb.
        .layoutPriority(stage.isNationwide ? 1 : 0)
    }

    private func mapView(_ quiz: QuizViewModel) -> some View {
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
            onTap: { prefecture, point in
                // The clip hides everything outside the panel; the touch
                // region does not honour it (ZoomPan.isVisible). A tap that
                // landed where the child sees page, not map, must not answer
                // the question.
                guard ZoomPan.isVisible(point, scale: zoom, offset: pan,
                                        in: mapSize) else { return }
                handleTap(prefecture, at: .point(point), quiz: quiz)
            })
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

    /// One press to a third of the country, for the child the hold-and-slide
    /// is still too fiddly for — 全国チャレンジ only, where the whole point of
    /// zooming is that 47 prefectures in one frame leaves Kagawa unreachable.
    ///
    /// Only while at rest: once zoomed the stack gives way to
    /// 「もとの おおきさ」 in this same corner, and a "zoom somewhere else"
    /// button on top of a zoomed map would teleport the child instead of
    /// letting them look. Stacked down the
    /// south-eastern corner in the country's own order — east at the top,
    /// west at the bottom, the way the archipelago runs diagonally above. That
    /// corner is open Pacific on every layout, however short the panel gets;
    /// a row along the foot reached far enough left to cover Okinawa's inset
    /// on the smallest phones, and a button must never sit on a prefecture a
    /// tap might be aiming for.
    @ViewBuilder private var regionZoomButtons: some View {
        if stage.isNationwide, !ZoomPan.isZoomed(zoom) {
            VStack(alignment: .trailing, spacing: 6) {
                regionButton(mode.eastJapan, codes: Stage.eastJapanCodes)
                regionButton(mode.middleJapan, codes: Stage.middleJapanCodes)
                regionButton(mode.westJapan, codes: Stage.westJapanCodes)
            }
            .padding(10)
        }
    }

    private func regionButton(_ title: String, codes: [Int]) -> some View {
        Button(title) { zoomToRegion(codes) }
            .font(AppFont.rounded(13, relativeTo: .caption))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(.white.opacity(0.92)))
            .overlay(Capsule().strokeBorder(Palette.ink.opacity(0.12)))
    }

    private func zoomToRegion(_ codes: [Int]) {
        guard mapSize.width > 0, mapSize.height > 0 else { return }
        // The same fit the map itself draws with, so the framed rect is the
        // region exactly as it sits on screen.
        let transform = PrefectureGeometry.fitTransform(
            bounds: PrefectureGeometry.boundingBox(
                of: app.mapData.prefectures(in: stage.codes)),
            into: mapSize)
        let region = PrefectureGeometry.boundingBox(
            of: app.mapData.prefectures(in: codes)).applying(transform)
        let (scale, offset) = ZoomPan.framing(region, in: mapSize)
        let apply = { zoom = scale; pan = offset }
        if reduceMotion { apply() } else { withAnimation(.spring(duration: 0.35), apply) }
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
        // 「なまえを あてる」 asks about the ringed one, so the ring stays until
        // it is answered — including through a wrong guess, when the child needs
        // to look at it again rather than hunt for what the question was.
        if quiz.mode == .nameIt, quiz.phase == .asking, quiz.target?.code == pref.code {
            return .asked(for: pref.code)
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
        // Gold, not the sticker-white die-cut: white against the washed slots
        // barely registered, and gold is already the app's reward colour.
        return .stuck(for: pref.code, stroke: Palette.gold,
                      badge: quiz.lastDraw?.card.emoji)
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
            // The cue climbs one scale step per clean answer in the run —
            // answer() has already updated the combo, so this reads the run
            // this answer just extended (or, after a fumble, restarted).
            SoundService.shared.play(
                .correct, enabled: app.save.data.settings.soundEnabled,
                semitonesUp: SoundService.semitoneRise(forCombo: quiz.combo))
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
        guard app.isVoiceModeAvailable, quiz.mode == .nameIt else { return }
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
        // Only the names actually on offer: a child saying a prefecture that
        // is not one of the four choices has not answered the question, and
        // scoring it would be scoring the wrong thing.
        let candidates = app.mapData.prefectures(in: quiz.choices)
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

    /// The 🔊 button's press, and the auto-announcement — 「ちずで さがす」
    /// only, where the sentence carries the question (CLAUDE.md §7). It must
    /// never run in 「なまえを あてる」: the only true thing it could say there
    /// is the target's name, which is the answer.
    private func speak(_ quiz: QuizViewModel) {
        guard app.save.data.settings.speechEnabled else { return }
        // The microphone gives way to the announcement: holding the session
        // open would silence the reading, and what the app says out loud is
        // not something it should be listening to. The isSpeaking observer
        // re-arms it afterwards if the mode is on.
        if app.voice.isListening { app.voice.stop() }
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

    /// The panel in the tier's own stock — the foil's lit stop, so silver
    /// news arrives on silver and gold news on gold. Rainbow keeps the white
    /// base its holographic wash needs.
    private var stock: Color {
        switch tier {
        case .silver: Palette.silverStock
        case .gold: Palette.goldStock
        default: .white
        }
    }

    /// The edge in the tier's foil ramp — the same metal the card face wears.
    private var foil: AnyShapeStyle? {
        let ramp: [Gradient.Stop]? = switch tier {
        case .silver: Palette.silverRamp
        case .gold: Palette.foilRamp
        case .rainbow: Palette.rainbowRamp
        default: nil
        }
        return ramp.map {
            AnyShapeStyle(LinearGradient(stops: $0,
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
        }
    }

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
        // The banner wears the tier it announces — silver stock and silver
        // foil for a silver card, gold for gold, the rainbow wash for
        // rainbow. It used to give every special tier the same gold edge,
        // which dressed a card as gold at the exact moment the text was
        // saying it went silver.
        .stickerCard(fill: stock, cornerRadius: 18, edgeStyle: foil,
                     isHolographic: tier == .rainbow)
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
