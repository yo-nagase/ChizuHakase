import GameKit
import Observation
import SwiftUI
import UIKit

@Observable
final class GameCenterService {
    struct SignIn: Identifiable {
        let id = UUID()
        let controller: UIViewController
    }
    struct Entry: Identifiable {
        let id: String
        let rank: Int
        let name: String
        let score: Int
    }
    var signIn: SignIn?
    private(set) var playerID: String?
    private(set) var alias = ""
    private(set) var message: String?
    private(set) var authenticating = false
    private var installedHandler = false
    private var submitting = false
    private let store: RankingStore

    init(store: RankingStore) { self.store = store }

    func authenticate() {
        guard store.participationEnabled, !installedHandler else { return }
        installedHandler = true
        authenticating = true
        GKLocalPlayer.local.authenticateHandler = { [weak self] controller, _ in
            Task { @MainActor in
                guard let self else { return }
                self.authenticating = false
                if let controller {
                    self.signIn = SignIn(controller: controller)
                    return
                }
                self.signIn = nil
                let local = GKLocalPlayer.local
                self.playerID = local.isAuthenticated ? local.gamePlayerID : nil
                self.alias = local.isAuthenticated ? local.alias : ""
                self.message = local.isAuthenticated ? nil
                    : "Game Centerに サインインすると さんかできます。せっていアプリの Game Centerを かくにんしてください。"
                if !local.isAuthenticated { self.installedHandler = false }
                await self.submitPending()
            }
        }
    }

    func signInDismissed() {
        if playerID == nil {
            installedHandler = false
            authenticating = false
            message = "Game Centerに サインインすると さんかできます。"
        }
    }

    func submitPending() async {
        guard !submitting, store.participationEnabled,
              GKLocalPlayer.local.isAuthenticated,
              let playerID, GKLocalPlayer.local.gamePlayerID == playerID else { return }
        submitting = true
        defer { submitting = false }
        for run in store.pending(for: playerID) {
            guard store.participationEnabled, GKLocalPlayer.local.isAuthenticated,
                  GKLocalPlayer.local.gamePlayerID == playerID,
                  let score = run.packedScore else { break }
            do {
                try await GKLeaderboard.submitScore(score, context: 0,
                    player: GKLocalPlayer.local, leaderboardIDs: [run.board.id])
                store.markSent(run)
                message = nil
            } catch {
                message = "そうしんを まっています。つぎに ランキングを ひらくと もういちど そうしんします。"
                break
            }
        }
    }

    func entries(for board: RankingBoard) async throws -> (local: Entry?, top: [Entry]) {
        guard GKLocalPlayer.local.isAuthenticated,
              GKLocalPlayer.local.gamePlayerID == playerID else { throw RankingError.notSignedIn }
        let boards = try await GKLeaderboard.loadLeaderboards(IDs: [board.id])
        guard let leaderboard = boards.first else { throw RankingError.notConfigured }
        let (local, entries, _) = try await leaderboard.loadEntries(
            for: .global, timeScope: .allTime, range: NSRange(location: 1, length: 100))
        func row(_ entry: GKLeaderboard.Entry) -> Entry {
            Entry(id: entry.player.gamePlayerID, rank: entry.rank,
                  name: entry.player.alias, score: entry.score)
        }
        return (local.map(row), entries.map(row))
    }

    /// Fetch only this player's entries; the course shelf does not need top 100 lists.
    func courseRanks(for boards: [RankingBoard]) async throws -> [String: StageRank] {
        guard store.participationEnabled, let playerID,
              GKLocalPlayer.local.isAuthenticated,
              GKLocalPlayer.local.gamePlayerID == playerID else { throw RankingError.notSignedIn }
        await submitPending()
        let leaderboards = try await GKLeaderboard.loadLeaderboards(IDs: boards.map(\.id))
        var result: [String: StageRank] = [:]
        for leaderboard in leaderboards {
            try Task.checkCancellation()
            guard store.participationEnabled, self.playerID == playerID,
                  GKLocalPlayer.local.isAuthenticated,
                  GKLocalPlayer.local.gamePlayerID == playerID else { throw RankingError.notSignedIn }
            let id = leaderboard.baseLeaderboardID
            do {
                let (local, _) = try await leaderboard.loadEntries(
                    for: [GKLocalPlayer.local], timeScope: .allTime)
                result[id] = local.flatMap { $0.rank > 0 ? .ranked($0.rank) : nil } ?? .noRecord
            } catch {
                result[id] = .unavailable
            }
        }
        return result
    }

    enum RankingError: Error { case notSignedIn, notConfigured }
}

struct GameCenterSignInView: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
