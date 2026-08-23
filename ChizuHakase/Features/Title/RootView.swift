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
    /// state shaped like `quizMode`. The whole app's one japan/world branch is
    /// the title's two pages (design doc §2): TitleView binds its pager to
    /// this key, so the page in front of the child and the book every screen
    /// below reads are the same fact. Starts on whichever page was open last
    /// time (`Settings.lastAtlas`, handed in by ChizuHakaseApp); the debug
    /// launch argument `-atlas` overrides that in `applyDebugRoute`.
    ///
    /// Invariant: only the title writes this key (the pager binding, plus the
    /// debug route before anything is pushed). The destinations below read it
    /// live — through the computed `atlas` — and that is safe precisely
    /// because pushes only ever start from the title, so the key cannot turn
    /// under an open screen.
    @State private var atlasKey: String

    private var atlas: Atlas {
        atlasKey == SaveData.worldAtlas ? app.world : app.japan
    }

    /// - Parameter initialAtlasKey: the page to open on — the caller passes
    ///   the remembered `Settings.lastAtlas` (design doc §2: 前回開いていた
    ///   ページから始める). Set at init rather than in `.task` so the first
    ///   frame already shows the right page instead of flashing japan first.
    init(initialAtlasKey: String = SaveData.japanAtlas) {
        _atlasKey = State(initialValue: initialAtlasKey)
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
            // The doors do not carry an atlas: whichever page they are pressed
            // on has already set `atlasKey` through the pager binding, and the
            // destinations below read the session atlas from it.
            TitleView(atlasKey: $atlasKey,
                      onStart: { path.append(.stageSelect) },
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
        // The page turn's side effects, in one place so they run once per
        // change rather than once per body evaluation (P6 引き継ぎ 4・5):
        // the vocabulary follows the open book, and `lastAtlas` is written so
        // the next launch opens on this page (design doc §2) — a settings
        // write, like the mute button's.
        .onChange(of: atlasKey) { _, key in
            syncVoiceVocabulary(for: key)
            app.save.updateSettings { $0.lastAtlas = key }
        }
        // After the debug route, not before: a session launched straight into
        // another screen has no title to sing over.
        .task {
            await applyDebugRoute()
            // A launch that starts off japan's page — lastAtlas restored, or
            // `-atlas` above — arrives with AppState's japan vocabulary still
            // in the voice service, and onChange only fires on *changes*. Say
            // it once here so the open book and the vocabulary agree from the
            // first question (引き継ぎ 4).
            if atlasKey != SaveData.japanAtlas {
                syncVoiceVocabulary(for: atlasKey)
            }
            playThemeIfWanted()
            // After the first frame, before the first tap: the engine spin-up
            // this hides would otherwise run inside that tap's button action
            // and read as the app hesitating.
            SoundService.shared.warmUp()
        }
    }

    /// Points the voice input at the open book's vocabulary (P6 引き継ぎ 4) —
    /// left alone, 「あめりか」 would be matched against 47 prefecture names.
    /// Derives the atlas from the key it is handed rather than reading the
    /// `atlas` property, so the call is self-contained wherever it runs.
    /// Resolving `app.world` here is also the world's first access on a turn
    /// to that page, so the synchronous WorldShapes load (引き継ぎ 5) is spent
    /// inside the page flip, not inside the first あそぶ tap.
    private func syncVoiceVocabulary(for key: String) {
        let book = key == SaveData.worldAtlas ? app.world : app.japan
        app.voice.configure(vocabulary: book.voiceVocabulary)
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
    ///
    /// Async because the `-startAt` push at the bottom must land on a later
    /// frame than the staging above it: `-atlas world` moves the title pager's
    /// selection and `-grantCards` moves the save store, and a `path` write
    /// sharing that frame is dropped by NavigationStack (console: "Update
    /// NavigationAuthority bound path tried to update multiple times per
    /// frame" — seen as `-atlas world -grantCards -startAt …` landing on the
    /// title). Debug-only sequencing; the shipping app never runs this.
    private func applyDebugRoute() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetSave") {
            app.save.eraseAll()
            // The page restore read lastAtlas *before* this erase (at init).
            // A reset run must not inherit whichever page the previous run
            // left open — the japan suite launches with -resetSave and no
            // -atlas, and its stage indexes must resolve against japan.
            atlasKey = app.save.data.settings.lastAtlas
        }
        // A mid-journey collection for store screenshots: every mastery colour
        // on the map at once, all four card tiers in the book, records on some
        // stages and none on others. Built through the real rules — like
        // -grantCards below — so it keeps looking right after a rule changes.
        if arguments.contains("-demoSave") {
            app.save.eraseAll()
            // Same page reset as -resetSave: the demo stages japan's book.
            atlasKey = app.save.data.settings.lastAtlas
            func visit(stage index: Int, times: Int, score: Int, stars: Int) {
                guard let stage = Stage.stage(at: index) else { return }
                for _ in 0..<times {
                    app.save.applyStageResult(StageResult(
                        mode: .findOnMap, stageIndex: index, score: score,
                        stars: stars,
                        firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                            stage.codes.map { ($0, true) }),
                        cardDraws: []),
                        catalog: app.cards, atlas: SaveData.japanAtlas)
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
                catalog: app.cards, atlas: SaveData.japanAtlas)
            // One nameIt record so the stage list shows the per-mode split.
            app.save.applyStageResult(StageResult(
                mode: .nameIt, stageIndex: 1, score: 1180, stars: 2,
                firstTryByPrefecture: [:], cardDraws: []),
                catalog: app.cards, atlas: SaveData.japanAtlas)
        }
        // Parsed before the grant flags and -startAt, so both the granted book
        // and `-atlas world -startAt quiz:15` resolve against the world's
        // stages. Explicit in both directions, and it wins over the remembered
        // lastAtlas the launch started from: tests and screenshots need runs
        // that do not inherit whichever page the previous run happened to
        // leave open.
        if let i = arguments.firstIndex(of: "-atlas"), i + 1 < arguments.count {
            switch arguments[i + 1] {
            case "world": atlasKey = SaveData.worldAtlas
            case "japan": atlasKey = SaveData.japanAtlas
            default: break
            }
        }
        // Enough of a collection to exercise the book: one plain card, one gold
        // and one rainbow. Owning nothing hides every name behind 「？」, which
        // is correct but leaves nothing to open.
        if arguments.contains("-grantCards") {
            // Per book, because IDs only mean anything inside one catalog —
            // fourteen even collide as strings across the books (引き継ぎ 2). The
            // world's gold is deliberately "12-1", the collision id itself:
            // opening it must say アルジェリア, never 千葉の らっかせい.
            let ids = atlasKey == SaveData.worldAtlas
                ? (new: "36-1", gold: "12-1", rainbow: "392-1")
                : (new: "01-1", gold: "04-2", rainbow: "13-2")
            let catalog = atlas.cards
            let originalDraws: [GameRules.CardDraw]
            if atlasKey == SaveData.worldAtlas, let original = catalog["36-2"] {
                originalDraws = [.new(original)]
            } else {
                originalDraws = []
            }
            app.save.applyStageResult(StageResult(
                mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                firstTryByPrefecture: [:],
                // Parenthesised: ?? binds looser than +, so without these the
                // second array was swallowed and only one card was ever granted.
                cardDraws: (catalog[ids.new].map { [GameRules.CardDraw.new($0)] } ?? [])
                    + (catalog[ids.gold].map {
                        [GameRules.CardDraw.star($0, stars: GameRules.maxCardStars)]
                    } ?? [])
                    + (catalog[ids.rainbow].map {
                        [GameRules.CardDraw.star($0, stars: GameRules.maxCardStars)]
                    } ?? [])
                    // The world book has no country headings, so keep one
                    // original in its debug collection to catch a missing
                    // country label on the card itself.
                    + originalDraws,
                // The gold-finishing answer plus a clean run on its region, so
                // the rainbow card comes out of the real latch rather than
                // being written in as rainbow — a debug state that stages
                // itself keeps looking right after the rule breaks. Japan's
                // 13-2 gives the dense sushi painting a rainbow-foil stress
                // case while keeping the state representative of real data.
                outcomesByPrefecture: catalog[ids.rainbow].map {
                    [$0.prefectureCode: Array(repeating: true,
                                              count: GameRules.rainbowStreak + 1)]
                } ?? [:]),
                catalog: catalog, atlas: atlas.saveKey)
        }
        // Every prefecture of one regional stage answered cleanly, which is the
        // state the stage list's 「おぼえた ◯ / ◯」 has to show as full. Its own
        // flag rather than a rider on -grantCards: that one is about the book,
        // and a test asking about progress should say so.
        // Atlas-aware like `-grantCards`: the session book's first stage, so
        // `-atlas world -learnFirstStage` colours the world's own countries
        // (the my-map globe screenshots need mastery somewhere on the sphere).
        // Launched without `-atlas` it reads japan's shelf when `-resetSave`
        // rides along (the reset rewinds the remembered page; without it the
        // flag stages whichever book the previous run left open) — which is
        // exactly the pair its original UI test (StageSelectUITests) launches.
        // Each launch applies one clean visit, so repeated launches walk the
        // mastery ladder the same way repeated plays do.
        if arguments.contains("-learnFirstStage"), let stage = atlas.stage(at: 0) {
            app.save.applyStageResult(StageResult(
                mode: .findOnMap, stageIndex: stage.index, score: 0, stars: 3,
                firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                    stage.codes.map { ($0, true) }),
                cardDraws: []),
                catalog: atlas.cards, atlas: atlas.saveKey)
        }
        guard let index = arguments.firstIndex(of: "-startAt"),
              index + 1 < arguments.count else { return }
        // One beat between staging and navigating — see the function comment.
        // A yield alone is not reliably a frame, so this waits one out.
        try? await Task.sleep(for: .milliseconds(50))
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
            // Synthetic 3-star clear so the celebration can be captured —
            // staged from the session atlas, so `-atlas world -startAt result`
            // shows the world's own cards and countries.
            //
            // Keep the キラ slot explicit so this route always exercises the
            // silver treatment in addition to the two newly won cards. (The
            // world's catalog has no illustrated card yet, so there the silver
            // slot simply stays empty — two new flags is still a result.)
            if let stage = atlas.stage(at: 1) {
                let illustrated = atlas.cards.all.first { $0.art != nil }
                let plain = atlas.cards.all.filter { $0.id != illustrated?.id }.prefix(2)
                let demo = StageResult(
                    mode: .findOnMap, stageIndex: stage.index, score: 1120, stars: 3,
                    firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                        stage.codes.map { ($0, true) }),
                    cardDraws: plain.map { .new($0) }
                        + (illustrated.map {
                            [GameRules.CardDraw.star($0, stars: GameRules.silverStars)]
                        } ?? []))
                // Every panel at once, which no single honest run produces —
                // that is the point of the route. The sparkle and rainbow slots
                // both take regions from the staged stage itself, so the screen
                // reads as one stage's worth of luck rather than as a sampler.
                let sparkling = Array(stage.codes.prefix(2))
                let gains = StageGains(
                    sparklingPrefectures: sparkling,
                    rainbowCards: sparkling.first
                        .flatMap { atlas.cards.cards(for: $0).first.map { [$0.id] } } ?? [])
                path = [.stageSelect, .result(demo, gains: gains)]
            }
        default: break
        }
        #endif
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .stageSelect:
            // Fed the session atlas, so the list, the records and the taps all
            // read one book. (Its predecessor listed japan's stages while taps
            // resolved against the session atlas below — backing out of a world
            // quiz made かんとう launch カリブかい, both index 1 in their books.)
            StageSelectView(atlas: atlas,
                            quizMode: $quizMode,
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
                ResultView(atlas: atlas,
                           stage: stage,
                           result: result,
                           gains: gains,
                           onReplay: { replay(stage) },
                           onExit: { backToStageSelect() })
            }

        // The two collection rooms read the session atlas like every other
        // destination, so the title page's tallies open the book they counted.

        case .myMap:
            MyMapView(atlas: atlas)

        case .cardBook(let filter):
            CardBookView(atlas: atlas, initialFilter: filter)
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
    /// Taken from the atlas value itself (`saveKey` is the single carrier of
    /// book-played + record-destination), not from the session state next to it.
    private func finish(_ result: StageResult, stage: Stage) {
        let gains = app.save.applyStageResult(result, catalog: atlas.cards,
                                              atlas: atlas.saveKey)
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
