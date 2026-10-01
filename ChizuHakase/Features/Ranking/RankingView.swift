import SwiftUI

struct RankingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.textMode) private var text
    let atlas: Atlas
    @State var stageIndex: Int
    @State var quizMode: QuizMode
    @State private var global = false
    @State private var entries: [GameCenterService.Entry] = []
    @State private var localEntry: GameCenterService.Entry?
    @State private var loading = false
    @State private var loadError: String?

    private var board: RankingBoard? {
        atlas.stage(at: stageIndex).map {
            RankingBoard(atlas: atlas.saveKey, stage: $0.index,
                         mode: quizMode, questionCount: $0.questionCount)
        }
    }
    private var requestID: String {
        "\(board?.id ?? "")|\(global)|\(app.gameCenter.playerID ?? "")|\(app.rankings.participationEnabled)"
    }

    var body: some View {
        List {
            Section {
                Picker("ステージ", selection: $stageIndex) {
                    ForEach(atlas.stages, id: \.index) { stage in
                        Text(stage.displayName(text)).tag(stage.index)
                    }
                }
                .accessibilityIdentifier("rankingStagePicker")
                Picker("クイズ", selection: $quizMode) {
                    ForEach(QuizMode.allCases) { mode in
                        Text(mode.title(text)).tag(mode)
                    }
                }
                Picker("ランキング", selection: $global) {
                    Text("じぶんの きろく").tag(false)
                    Text("みんな").tag(true)
                }.pickerStyle(.segmented)
            } footer: {
                Text("いっかいで せいかいした かず → はやさ の じゅん。きかんは すべて。")
            }

            if let error = app.rankings.errorMessage { Text(error) }
            if let board {
                if global { globalSection(board) }
                else { historySection(board) }
            }
        }
        .navigationTitle("ランキング")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: requestID) { await reload() }
        .refreshable { await reload() }
    }

    @ViewBuilder
    private func historySection(_ board: RankingBoard) -> some View {
        let history = app.rankings.history(for: board)
        Section("じぶんの きろく") {
            if history.isEmpty { Text("あそぶと ここに きろくが のこるよ。") }
            ForEach(Array(history.enumerated()), id: \.element.id) { index, run in
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(index + 1).  \(run.correct) / \(board.questionCount) もん　\(RankingRun.timeLabel(run.milliseconds))")
                        .monospacedDigit()
                    Text(run.date, style: .date).font(.caption).foregroundStyle(.secondary)
                    if run.interrupted { Text("ちゅうだんあり・じぶんの きろくだけ").font(.caption) }
                }
            }
        }
        let unfinished = app.rankings.history(for: board, completed: false)
        if !unfinished.isEmpty {
            Section("とちゅうまでの きろく") {
                ForEach(unfinished) { run in
                    Text("\(run.correct) もん　\(RankingRun.timeLabel(run.milliseconds))")
                }
            }
        }
    }

    @ViewBuilder
    private func globalSection(_ board: RankingBoard) -> some View {
        Section {
            if !app.rankings.participationEnabled {
                Text("Game Centerの ニックネームと きろくが みんなに みえるように なります。さんかした あとの あたらしい きろくを のせます。")
                Button("Game Centerで さんかする") {
                    app.rankings.setParticipation(true)
                    app.gameCenter.authenticate()
                }
            } else if app.gameCenter.playerID == nil {
                Text(app.gameCenter.message ?? "Game Centerに サインインしてね。")
                Button("サインイン") { app.gameCenter.authenticate() }
                    .disabled(app.gameCenter.authenticating)
            } else {
                if let message = app.gameCenter.message { Text(message).font(.caption) }
                if loading { ProgressView("よみこみちゅう") }
                if let loadError {
                    Text(loadError)
                    Button("もういちど よみこむ") { Task { await reload() } }
                } else if !loading {
                    if entries.isEmpty { Text("まだ きろくが ありません。") }
                    ForEach(entries) { entry in entryRow(entry, board: board) }
                }
            }
            if app.rankings.participationEnabled {
                Button("きろくの そうしんを とめる") {
                    app.rankings.setParticipation(false)
                }
                .font(.caption)
            }
        } header: { Text("みんなの ランキング・トップ100") }
          footer: { Text("サインインして はじめから おわりまで あそんだ きろくが のります。そうしんを とめても、すでに のせた きろくは のこります。") }

        if app.rankings.participationEnabled, app.gameCenter.playerID != nil,
           !loading, loadError == nil, let localEntry,
           !entries.contains(where: { $0.id == localEntry.id }) {
            Section("じぶんの じゅんい") {
                entryRow(localEntry, board: board)
            }
        }
    }

    private func entryRow(_ entry: GameCenterService.Entry, board: RankingBoard) -> some View {
        let score = RankingRun.unpack(entry.score)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(entry.rank). \(entry.name)").font(.headline)
                if entry.id == app.gameCenter.playerID {
                    Text("じぶん")
                        .font(.caption.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .fixedSize()
                }
            }
            Text("\(score.correct) / \(board.questionCount) もん　\(RankingRun.timeLabel(score.milliseconds))")
                .font(.subheadline).monospacedDigit()
        }
    }

    private func reload() async {
        entries = []
        localEntry = nil
        loadError = nil
        guard global, app.rankings.participationEnabled,
              app.gameCenter.playerID != nil, let board else { loading = false; return }
        let requested = requestID
        loading = true
        await app.gameCenter.submitPending()
        do {
            let result = try await app.gameCenter.entries(for: board)
            guard !Task.isCancelled, requestID == requested else { return }
            entries = result.top
            localEntry = result.local
        } catch {
            guard !Task.isCancelled, requestID == requested else { return }
            if case GameCenterService.RankingError.notConfigured = error {
                loadError = "みんなの ランキングは じゅんびちゅうです。じぶんの きろくは つかえます。"
            } else {
                loadError = "ランキングを よみこめませんでした。つうしんを かくにんしてね。"
            }
        }
        loading = false
    }
}
