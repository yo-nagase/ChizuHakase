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

    enum Route: Hashable {
        case stageSelect
        case quiz(stageIndex: Int, mode: QuizMode)
        /// The finished result travels *in the path*, not alongside it.
        /// Keeping it in separate @State meant NavigationStack could resolve
        /// the destination before that state was visible to it, and finishing a
        /// real quiz pushed a blank screen. Data a destination needs belongs in
        /// the value that selects it.
        case result(StageResult, sparkles: [Int])
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
        .task { applyDebugRoute() }
    }

    /// Jump straight to a screen via `-startAt <route>`, for capturing store
    /// screenshots and for poking at one screen without replaying to it.
    /// Debug builds only — it must not be reachable in a shipped app.
    private func applyDebugRoute() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetSave") { app.save.eraseAll() }
        // Enough of a collection to exercise the book: one plain card and one
        // キラ. Owning nothing hides every name behind 「？」, which is correct
        // but leaves nothing to open.
        if arguments.contains("-grantCards") {
            app.save.applyStageResult(StageResult(
                mode: .findOnMap, stageIndex: 0, score: 0, stars: 3,
                firstTryByPrefecture: [:],
                // Parenthesised: ?? binds looser than +, so without these the
                // second array was swallowed and only one card was ever granted.
                cardDraws: (app.cards["01-1"].map { [GameRules.CardDraw.new($0)] } ?? [])
                    + (app.cards["04-2"].map { [GameRules.CardDraw.shiny($0)] } ?? [])))
        }
        guard let index = arguments.firstIndex(of: "-startAt"),
              index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "stageSelect": path = [.stageSelect]
        case "myMap": path = [.myMap]
        case "cardBook": path = [.cardBook(filter: .all)]
        case "cardBook:shiny": path = [.cardBook(filter: .shiny)]
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
            // The キラ slot deliberately takes an illustrated card: picking the
            // first card in the catalog gave a shiny with no art, so the one
            // state worth looking at never appeared in a screenshot.
            let illustrated = app.cards.all.first { $0.art != nil }
            let plain = app.cards.all.filter { $0.id != illustrated?.id }.prefix(2)
            let demo = StageResult(
                mode: .findOnMap, stageIndex: 1, score: 1120, stars: 3,
                firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                    Stage.all[1].codes.map { ($0, true) }),
                cardDraws: plain.map { .new($0) }
                    + (illustrated.map { [GameRules.CardDraw.shiny($0)] } ?? []))
            path = [.stageSelect, .result(demo, sparkles: [13, 14])]
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
            if let stage = Stage.stage(at: stageIndex) {
                QuizView(stage: stage, quizMode: mode) { result in
                    finish(result, stage: stage)
                }
            }

        case .result(let result, let sparkles):
            if let stage = Stage.stage(at: result.stageIndex) {
                ResultView(stage: stage,
                           result: result,
                           newlySparkling: sparkles,
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
    private func finish(_ result: StageResult, stage: Stage) {
        let sparkles = app.save.applyStageResult(result)
        path = [.stageSelect, .result(result, sparkles: sparkles)]
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
