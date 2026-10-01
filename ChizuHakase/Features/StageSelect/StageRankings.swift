import Foundation
import Observation

enum StageRank: Equatable {
    case loading, notParticipating, signedOut, noRecord, unavailable
    case ranked(Int)

    func label(_ mode: TextMode) -> String {
        switch self {
        case .loading: mode.isKids ? "じゅんいを よみこみちゅう" : "順位を読み込み中"
        case .notParticipating: mode.isKids ? "ランキングに さんかしてね" : "ランキングに参加すると表示"
        case .signedOut: mode.isKids ? "サインインしてね" : "サインインすると順位を表示"
        case .noRecord: mode.isKids ? "じゅんい：まだ きろくなし" : "順位：まだ記録なし"
        case .unavailable: mode.isKids ? "じゅんい：いまは みられません" : "順位：取得できませんでした"
        case .ranked(let rank): mode.isKids ? "じぶんの じゅんい：\(rank)い" : "自分の順位：\(rank)位"
        }
    }
}

@Observable
final class StageRankings {
    private var values: [String: StageRank] = [:]
    private var context = ""
    private var generation = UUID()

    func rank(for board: RankingBoard, context: String,
              participating: Bool, playerID: String?) -> StageRank {
        guard participating else { return .notParticipating }
        guard playerID != nil else { return .signedOut }
        guard self.context == context else { return .loading }
        return values[board.id] ?? .loading
    }

    func reload(boards: [RankingBoard], context: String, participating: Bool,
                playerID: String?, load: ([RankingBoard]) async throws -> [String: StageRank]) async {
        let request = UUID()
        generation = request
        self.context = context
        values = [:]
        guard participating, playerID != nil else { return }
        do {
            let loaded = try await load(boards)
            guard !Task.isCancelled, generation == request else { return }
            values = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, loaded[$0.id] ?? .unavailable) })
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            values = Dictionary(uniqueKeysWithValues: boards.map { ($0.id, .unavailable) })
        }
    }
}
