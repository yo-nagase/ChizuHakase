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
        case result(stageIndex: Int)
        case myMap
        case cardBook
    }

    /// Held outside `Route` because `StageResult` is not Hashable and there is
    /// only ever one result in flight.
    @State private var pendingResult: StageResult?
    @State private var pendingSparkles: [Int] = []

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
            pendingResult = StageResult(
                stageIndex: 1, score: 1120, stars: 3,
                firstTryByPrefecture: Dictionary(uniqueKeysWithValues:
                    Stage.all[1].codes.map { ($0, true) }),
                cardDraws: cards.enumerated().map { index, card in
                    index == 0 ? .shiny(card) : .new(card)
                })
            pendingSparkles = [13, 14]
            path = [.stageSelect, .result(stageIndex: 1)]
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

        case .result(let stageIndex):
            if let stage = Stage.stage(at: stageIndex), let result = pendingResult {
                ResultView(stage: stage,
                           result: result,
                           newlySparkling: pendingSparkles,
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

    /// Persist once, at stage end (CLAUDE.md §6), then show the result.
    private func finish(_ result: StageResult, stage: Stage) {
        pendingSparkles = app.save.applyStageResult(result)
        pendingResult = result
        path.removeLast()                       // drop the quiz
        path.append(.result(stageIndex: stage.index))
    }

    private func replay(_ stage: Stage) {
        pendingResult = nil
        pendingSparkles = []
        path.removeLast()
        path.append(.quiz(stageIndex: stage.index))
    }

    private func backToStageSelect() {
        pendingResult = nil
        pendingSparkles = []
        path.removeLast()
    }
}

#Preview {
    RootView().environment(AppState())
}
