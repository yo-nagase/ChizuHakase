import Foundation
import Observation

@Observable
final class RankingStore {
    private struct Archive: Codable {
        var runs: [RankingRun] = []
        var sent: [String: Int] = [:]
        var participationEnabled = false
    }
    private var archive: Archive
    private let url: URL
    private(set) var errorMessage: String?

    init(directory: URL? = nil) {
        let base = directory ?? URL.applicationSupportDirectory
        url = base.appendingPathComponent("rankings-v1.json")
        archive = Archive()
        if FileManager.default.fileExists(atPath: url.path) {
            do { archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url)) }
            catch { errorMessage = "きろくを よみこめませんでした。" }
        }
    }

    var participationEnabled: Bool { archive.participationEnabled }
    func setParticipation(_ enabled: Bool) {
        archive.participationEnabled = enabled
        persist()
    }

    func record(_ run: RankingRun) {
        if let index = archive.runs.firstIndex(where: { $0.id == run.id }) {
            // A disappearing quiz must never overwrite its completed result.
            guard !archive.runs[index].completed else { return }
            archive.runs[index] = run
        } else { archive.runs.append(run) }
        persist()
    }

    func history(for board: RankingBoard, completed: Bool = true) -> [RankingRun] {
        archive.runs.filter { $0.board == board && $0.completed == completed }
            .sorted(by: RankingRun.precedes)
    }

    private func submissionKey(_ run: RankingRun) -> String {
        "\(run.playerID ?? "guest")|\(run.board.id)"
    }

    func pending(for playerID: String) -> [RankingRun] {
        guard participationEnabled else { return [] }
        var best: [String: RankingRun] = [:]
        for run in archive.runs where run.playerID == playerID {
            guard let score = run.packedScore else { continue }
            let key = submissionKey(run)
            guard score > (archive.sent[key] ?? -1),
                  score > (best[key]?.packedScore ?? -1) else { continue }
            best[key] = run
        }
        return Array(best.values)
    }

    func markSent(_ run: RankingRun) {
        guard let score = run.packedScore else { return }
        let key = submissionKey(run)
        archive.sent[key] = max(archive.sent[key] ?? -1, score)
        persist()
    }

    func erase() {
        archive = Archive()
        persist()
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(archive).write(to: url, options: .atomic)
            errorMessage = nil
        } catch { errorMessage = "きろくを ほぞんできませんでした。" }
    }
}
