import SwiftUI

/// Navigation shell. Owns the stack so the quiz can hand its result to the
/// result screen and unwind cleanly afterwards.
struct RootView: View {
    @Environment(AppState.self) private var app

    @State private var path: [Route] = []
    @State private var showsSettings = false
    /// Which way the questions run. Chosen on the stage picker and kept for
    /// the session, so a child does not have to re-pick it every stage.
    @State private var quizMode: QuizMode = .findOnMap
    /// Which map book (ちずちょう) the session is playing out of — session
    /// state shaped like `quizMode`. The one place the japan/world branch will
    /// live is the title's two pages (design doc §2, P6); until that page
    /// exists, only the debug launch argument `-atlas world` moves this, so
    /// there is deliberately no user-visible way into the world yet.
    @State private var atlasKey = SaveData.japanAtlas

    private var atlas: Atlas {
        atlasKey == SaveData.worldAtlas ? app.world : app.japan
    }

    enum Route: Hashable {
        case stageSelect
        case quiz(stageIndex: Int, mode: QuizMode)
        /// The finished result travels *in the path*, not alongside it.
        /// Keeping it in separate @State meant NavigationStack could resolve
        /// the destination before that state was visible to it, and finishing a
        /// real quiz pushed a blank screen. Data a destination needs belongs in
        /// the value that selects it.
        case result(StageResult, gains: StageGains)
        case myMap
        case cardBook(filter: CardFilter)
    }

    var body: some View {
        NavigationStack(path: $path) {
            TitleView(onStart: { path.append(.stageSelect) },
                      onMyMap: { path.append(.myMap) },
                      onCardBook: { path.append(.cardBook(filter: $0)) },
                      onSettings: { showsSettings = true })
                .navigationDestination(for: Route.self, destination: destination)
        }
        .tint(Palette.orange)
        // One injection point: every screen reads the mode from the environment
        // rather than reaching into the save store itself.
        .environment(\.textMode, app.save.data.settings.textMode)
        // The sheet is presented outside the stack, so the mode is handed to
        // it explicitly rather than inherited.
        .sheet(isPresented: $showsSettings) {
            SettingsView().environment(\.textMode, app.save.data.settings.textMode)
        }
        // One sound for every way back — the system chevron, the quiz's ←,
        // a result screen unwinding. They all shrink this stack, so listening
        // here means no screen has to remember to play it. Pushes stay silent:
        // the forward taps that want a sound (the stage sheets) play their
        // own decide.
        .onChange(of: path.count) { before, after in
            if after < before {
                SoundService.shared.play(.cancel,
                                         enabled: app.save.data.settings.soundEnabled)
            }
        }
        // The theme belongs to the title alone. It fades out under the push
        // animation rather than cutting off, and every path back to the title
        // starts it again — playTitleTheme is idempotent, so the paths need
        // not coordinate.
        .onChange(of: path.isEmpty) { _, atTitle in
            if atTitle { playThemeIfWanted() } else { app.music.stop(fadeOut: 0.6) }
        }
        // Written by the title's mute button and by the settings sheet alike;
        // reacting to the flag here means both controls behave identically.
        .onChange(of: app.save.data.settings.musicEnabled) { _, enabled in
            // A mute should feel like a hand on the speaker — near-instant,
            // but not a click.
            if enabled { playThemeIfWanted() } else { app.music.stop(fadeOut: 0.2) }
        }
        // After the debug route, not before: a session launched straight into
        // another screen has no title to sing over.
        .task {
            applyDebugRoute()
            playThemeIfWanted()
            // After the first frame, before the first tap: the engine spin-up
            // this hides would otherwise run inside that tap's button action
            // and read as the app hesitating.
            SoundService.shared.warmUp()
        }
    }

    /// The one gate for starting the theme: only on the title, only if the
    /// mute has not been chosen.
    private func playThemeIfWanted() {
        guard path.isEmpty, app.save.data.settings.musicEnabled else { return }
        app.music.playTitleTheme()
    }

    /// Jump straight to a screen via `-startAt <route>`, for capturing store
    /// screenshots and for poking at one screen without replaying to it.
    /// Debug builds only — it must not be reachable in a shipped app.
    private func applyDebugRoute() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetSave") { app.save.eraseAll() }
        // A mid-journey collection for store screenshots: every mastery colour
        // on the map at once, all four card tiers in the book, records on some
        // stages and none on others. Built through the real rules — like
        // -grantCards below — so it keeps looking right after a rule changes.
        if arguments.contains("-demoSave") {
            app.save.eraseAll()
            func visit(stage index: Int, times: Int, score: Int, stars: Int) {
                guard let stage = Stage.stage(at: index) else { return }
                for _ in 0..<times {
                    app.save.applyStageResult(StageResult(
                        mode: .findOnMap, stageIndex: index, score: score,
                        stars: stars,
                        firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                            stage.codes.map { ($0, true) }),
                        cardDraws: []), catalog: app.cards)
                }
            }
            // Learning radiates out from 関東: gold there, deep green next
            // door, light green further out, and 九州 untouched — grey
            // prefectures and an empty record slot are part of an honest
            // mid-journey.
            visit(stage: 0, times: 2, score: 890, stars: 2)
            visit(stage: 1, times: 5, score: 1460, stars: 3)
            visit(stage: 2, times: 4, score: 1310, stars: 3)
            visit(stage: 3, times: 3, score: 1050, stars: 2)
            visit(stage: 4, times: 1, score: 620, stars: 1)
            // Every owned card is illustrated; the higher tiers are still the
            // ones worth showing off for their foil. 13-2 goes rainbow through
            // the real latch: gold stars here, and below, one answer that
            // finishes the gold plus the clean run that must follow it.
            let collection: [(String, Int)] = [
                ("01-2", 7), ("02-1", 5), ("08-1", 6), ("14-2", 9),
                ("23-1", 5), ("26-2", 8), ("40-1", 5),
                ("04-2", 10), ("27-1", 10), ("13-2", 10),
                ("03-1", 3), ("05-1", 2), ("07-1", 4), ("10-1", 1),
                ("12-1", 2), ("15-1", 1), ("19-3", 1), ("22-1", 3),
                ("28-3", 2), ("34-1", 1), ("43-3", 2), ("47-2", 4),
            ]
            app.save.applyStageResult(StageResult(
                mode: .findOnMap, stageIndex: 1, score: 1460, stars: 3,
                firstTryByPrefecture: [:],
                cardDraws: collection.compactMap { id, stars in
                    app.cards[id].map { card -> GameRules.CardDraw in
                        stars == 1 ? .new(card) : .star(card, stars: stars)
                    }
                },
                outcomesByPrefecture: [13: Array(repeating: true,
                                                 count: GameRules.rainbowStreak + 1)]),
                catalog: app.cards)
            // One nameIt record so the stage list shows the per-mode split.
            app.save.applyStageResult(StageResult(
                mode: .nameIt, stageIndex: 1, score: 1180, stars: 2,
                firstTryByPrefecture: [:], cardDraws: []), catalog: app.cards)
        }
        // Enough of a collection to exercise the book: one plain card, one gold
        // and one rainbow. Owning nothing hides every name behind 「？」, which
        // is correct but leaves nothing to open.
        if arguments.contains("-grantCards") {
            app.save.applyStageResult(StageResult(
                mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                firstTryByPrefecture: [:],
                // Parenthesised: ?? binds looser than +, so without these the
                // second array was swallowed and only one card was ever granted.
                cardDraws: (app.cards["01-1"].map { [GameRules.CardDraw.new($0)] } ?? [])
                    + (app.cards["04-2"].map {
                        [GameRules.CardDraw.star($0, stars: GameRules.maxCardStars)]
                    } ?? [])
                    + (app.cards["13-2"].map {
                        [GameRules.CardDraw.star($0, stars: GameRules.maxCardStars)]
                    } ?? []),
                // The gold-finishing answer plus a clean run on Tokyo, so 13-2
                // comes out of the real latch rather than being written in as
                // rainbow — a debug state that stages itself keeps looking
                // right after the rule breaks. 13-2 gives the dense sushi
                // painting a rainbow-foil stress case while keeping the state
                // representative of real data.
                outcomesByPrefecture: [13: Array(repeating: true,
                                                 count: GameRules.rainbowStreak + 1)]),
                catalog: app.cards)
        }
        // Every prefecture of one regional stage answered cleanly, which is the
        // state the stage list's 「おぼえた ◯ / ◯」 has to show as full. Its own
        // flag rather than a rider on -grantCards: that one is about the book,
        // and a test asking about progress should say so.
        if arguments.contains("-learnFirstStage"), let stage = Stage.all.first {
            app.save.applyStageResult(StageResult(
                mode: .findOnMap, stageIndex: stage.index, score: 0, stars: 3,
                firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                    stage.codes.map { ($0, true) }),
                cardDraws: []), catalog: app.cards)
        }
        // Before -startAt, so `-atlas world -startAt quiz:15` resolves the
        // stage index against the world's stages.
        if let i = arguments.firstIndex(of: "-atlas"), i + 1 < arguments.count,
           arguments[i + 1] == "world" {
            atlasKey = SaveData.worldAtlas
        }
        guard let index = arguments.firstIndex(of: "-startAt"),
              index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "stageSelect": path = [.stageSelect]
        case "myMap": path = [.myMap]
        case "cardBook": path = [.cardBook(filter: .all)]
        case "cardBook:silver": path = [.cardBook(filter: .tier(.silver))]
        case "cardBook:gold": path = [.cardBook(filter: .tier(.gold))]
        case "cardBook:rainbow": path = [.cardBook(filter: .tier(.rainbow))]
        // Opens straight onto one card, so the detail view can be looked
        // at without tapping through the book to reach it.
        case let value where value.hasPrefix("card:"):
            path = [.cardBook(filter: .card(String(value.dropFirst(5))))]
        case let value where value.hasPrefix("quiz:"):
            if let i = Int(value.dropFirst(5)) {
                let mode: QuizMode = arguments.contains("-nameIt") ? .nameIt : .findOnMap
                path = [.stageSelect, .quiz(stageIndex: i, mode: mode)]
            }
        case "result":
            // Synthetic 3-star clear so the celebration can be captured.
            //
            // Keep the キラ slot explicit so this route always exercises the
            // silver treatment in addition to the two newly won cards.
            let illustrated = app.cards.all.first { $0.art != nil }
            let plain = app.cards.all.filter { $0.id != illustrated?.id }.prefix(2)
            let demo = StageResult(
                mode: .findOnMap, stageIndex: 1, score: 1120, stars: 3,
                firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                    Stage.all[1].codes.map { ($0, true) }),
                cardDraws: plain.map { .new($0) }
                    + (illustrated.map {
                        [GameRules.CardDraw.star($0, stars: GameRules.silverStars)]
                    } ?? []))
            // Every panel at once, which no single honest run produces — that
            // is the point of the route. The rainbow slot takes a card from a
            // prefecture the sparkle list already names, so the screen reads
            // as one stage's worth of luck rather than as a sampler.
            let gains = StageGains(
                sparklingPrefectures: [13, 14],
                rainbowCards: app.cards.cards(for: 13).first.map { [$0.id] } ?? [])
            path = [.stageSelect, .result(demo, gains: gains)]
        default: break
        }
        #endif
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .stageSelect:
            StageSelectView(quizMode: $quizMode,
                            onPlay: { path.append(.quiz(stageIndex: $0.index,
                                                        mode: quizMode)) })

        case .quiz(let stageIndex, let mode):
            // Resolved against the session's atlas: index 3 is きんき in one
            // book and きたヨーロッパ in the other, and the route carries only
            // the index (it is the save key, same as `records`).
            if let stage = atlas.stage(at: stageIndex) {
                QuizView(stage: stage, quizMode: mode, atlas: atlas) { result in
                    finish(result, stage: stage)
                }
            }

        case .result(let result, let gains):
            if let stage = atlas.stage(at: result.stageIndex) {
                ResultView(stage: stage,
                           result: result,
                           gains: gains,
                           onReplay: { replay(stage) },
                           onExit: { backToStageSelect() })
            }

        case .myMap:
            MyMapView()

        case .cardBook(let filter):
            CardBookView(initialFilter: filter)
        }
    }

    // MARK: - Flow

    // Each of these assigns the whole path rather than removing and appending.
    //
    // remove-then-append leaves the stack the same length, and NavigationStack
    // resolved the destination before the swap had settled: finishing a real
    // quiz pushed a *blank* result screen. Replacing the array outright gives
    // SwiftUI one unambiguous change to apply. Caught by the UI test, which is
    // the only thing that exercises this path — the debug route happened to
    // assign the array and so never reproduced it.

    /// Persist once, at stage end (CLAUDE.md §6), then show the result.
    /// The atlas key routes the write into the book that was played — a world
    /// result written without it would land ISO codes in japan's namespace.
    private func finish(_ result: StageResult, stage: Stage) {
        let gains = app.save.applyStageResult(result, catalog: atlas.cards,
                                              atlas: atlasKey)
        path = [.stageSelect, .result(result, gains: gains)]
    }

    private func replay(_ stage: Stage) {
        path = [.stageSelect, .quiz(stageIndex: stage.index, mode: quizMode)]
    }

    private func backToStageSelect() {
        path = [.stageSelect]
    }
}

#Preview {
    RootView().environment(AppState())
}
