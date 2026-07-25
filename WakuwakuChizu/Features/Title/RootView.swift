import SwiftUI

/// Navigation shell. Owns the stack so the quiz can hand its result to the
/// result screen and unwind cleanly afterwards.
struct RootView: View {
    @Environment(AppState.self) private var app

    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [Route] = []
    @State private var showsUnlock = false
    @State private var showsSettings = false

    enum Route: Hashable {
        case stageSelect
        case quiz(stageIndex: Int)
        /// The finished result travels *in the path*, not alongside it.
        /// Keeping it in separate @State meant NavigationStack could resolve
        /// the destination before that state was visible to it, and finishing a
        /// real quiz pushed a blank screen. Data a destination needs belongs in
        /// the value that selects it.
        case result(StageResult, sparkles: [Int])
        case myMap
        case cardBook
    }

    var body: some View {
        NavigationStack(path: $path) {
            TitleView(onStart: { path.append(.stageSelect) },
                      onMyMap: { path.append(.myMap) },
                      onCardBook: { path.append(.cardBook) },
                      onSettings: { showsSettings = true })
                .navigationDestination(for: Route.self, destination: destination)
        }
        .tint(Palette.orange)
        .sheet(isPresented: $showsUnlock) { UnlockView() }
        .sheet(isPresented: $showsSettings) { SettingsView() }
        .task {
            applyDebugRoute()
            await app.purchases.load()
        }
        // A refund or a purchase made elsewhere should be reflected without the
        // app reaching out on its own (CLAUDE.md §8).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await app.refreshOnForeground() } }
        }
    }

    /// Jump straight to a screen via `-startAt <route>`, for capturing store
    /// screenshots and for poking at one screen without replaying to it.
    /// Debug builds only — it must not be reachable in a shipped app.
    private func applyDebugRoute() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-resetSave") { app.save.eraseAll() }
        guard let index = arguments.firstIndex(of: "-startAt"),
              index + 1 < arguments.count else { return }
        switch arguments[index + 1] {
        case "stageSelect": path = [.stageSelect]
        case "myMap": path = [.myMap]
        case "cardBook": path = [.cardBook]
        case let value where value.hasPrefix("quiz:"):
            if let i = Int(value.dropFirst(5)) { path = [.stageSelect, .quiz(stageIndex: i)] }
        case "result":
            // Synthetic 3-star clear so the celebration can be captured.
            let cards = Array(app.cards.all.prefix(3))
            let demo = StageResult(
                stageIndex: 1, score: 1120, stars: 3,
                firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                    Stage.all[1].codes.map { ($0, true) }),
                cardDraws: cards.enumerated().map { index, card in
                    index == 0 ? .shiny(card) : .new(card)
                })
            path = [.stageSelect, .result(demo, sparkles: [13, 14])]
        default: break
        }
        #endif
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .stageSelect:
            StageSelectView(onPlay: { path.append(.quiz(stageIndex: $0.index)) },
                            onLocked: { showsUnlock = true })

        case .quiz(let stageIndex):
            if let stage = Stage.stage(at: stageIndex) {
                QuizView(stage: stage) { result in
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

        case .cardBook:
            CardBookView()
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
        path = [.stageSelect, .quiz(stageIndex: stage.index)]
    }

    private func backToStageSelect() {
        path = [.stageSelect]
    }
}

#Preview {
    RootView().environment(AppState())
}
