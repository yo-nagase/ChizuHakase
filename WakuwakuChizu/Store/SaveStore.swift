import Foundation
import OSLog

/// Reads and writes `SaveData` as JSON in Application Support.
///
/// Deliberately not SwiftData: the shape is a handful of dictionaries, and
/// owning the migration path outright is safer than inheriting a schema
/// migration engine for this (CLAUDE.md §6).
@Observable
final class SaveStore {

    private static let log = Logger(subsystem: "com.wakuwaku.chizu", category: "SaveStore")
    private static let fileName = "savedata.json"

    private(set) var data: SaveData

    /// nil when no writable location could be resolved — the app still runs,
    /// it just cannot persist. Better than refusing to launch.
    private let fileURL: URL?

    // MARK: - Init

    /// - Parameter directory: overridable so tests get a scratch directory
    ///   instead of the real Application Support.
    init(directory: URL? = nil) {
        let dir = directory ?? Self.defaultDirectory()
        if let dir {
            self.fileURL = dir.appendingPathComponent(Self.fileName)
        } else {
            self.fileURL = nil
            Self.log.error("no writable directory; progress will not persist")
        }
        self.data = Self.read(from: fileURL) ?? SaveData()
    }

    private static func defaultDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        } catch {
            log.error("could not create Application Support: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Reading

    private static func read(from url: URL?) -> SaveData? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let decoded = try JSONDecoder().decode(SaveData.self, from: Data(contentsOf: url))
            return migrate(decoded)
        } catch {
            // A damaged file must not take the app down. Falling back to a
            // fresh save loses progress, which is sad but recoverable; a launch
            // crash is not.
            log.error("save unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Version 1 is the only shipped schema. Newer-than-known files are left
    /// alone rather than rewritten, so a downgrade cannot silently destroy data.
    private static func migrate(_ input: SaveData) -> SaveData {
        var data = input
        if data.version < SaveData.currentVersion {
            data.version = SaveData.currentVersion
        }
        return data
    }

    // MARK: - Writing

    /// Persist. Called at stage end only — never per question (CLAUDE.md §6).
    @discardableResult
    func save() -> Bool {
        guard let fileURL else { return false }
        do {
            let encoded = try JSONEncoder().encode(data)
            // Atomic: a crash mid-write leaves the previous save intact rather
            // than a truncated file.
            try encoded.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            Self.log.error("save failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Mutations

    /// Apply one finished stage: best-of record, mastery gains, cards won.
    /// Returns the prefectures that reached level 3 so the result screen can
    /// call them out individually.
    @discardableResult
    func applyStageResult(_ result: StageResult) -> [Int] {
        var newlySparkling: [Int] = []

        for (code, firstTry) in result.firstTryByPrefecture {
            let before = data.masteryLevel(of: code)
            let after = GameRules.nextMastery(current: before, firstTry: firstTry)
            data.mastery[code] = after
            if after == GameRules.maxMastery && before < GameRules.maxMastery {
                newlySparkling.append(code)
            }
        }

        for draw in result.cardDraws {
            data.cards = GameRules.applyDraw(draw, to: data.cards)
        }

        // Stars and score are kept per mode; mastery and cards above are not,
        // because they measure the prefecture rather than the run.
        let record = StageRecord(stars: result.stars, score: result.score)
        data.records[result.mode.rawValue, default: [:]][result.stageIndex] =
            GameRules.bestRecord(
                existing: data.record(forStage: result.stageIndex, mode: result.mode),
                new: record)

        save()
        return newlySparkling.sorted()
    }

    func updateSettings(_ transform: (inout Settings) -> Void) {
        transform(&data.settings)
        save()
    }

    /// Wipe everything. The two-step confirmation lives in the my-map screen
    /// (CLAUDE.md §6) — this is the mechanism, not the guard.
    func eraseAll() {
        data = SaveData()
        if let fileURL {
            try? FileManager.default.removeItem(at: fileURL)
        }
        save()
    }
}

/// What one finished stage produced. Built by the quiz, consumed by the store,
/// so the scoring rules stay out of the persistence layer.
nonisolated struct StageResult: Sendable, Hashable {
    let mode: QuizMode
    let stageIndex: Int
    let score: Int
    let stars: Int
    /// prefecture code -> answered correctly on the first attempt
    let firstTryByPrefecture: [Int: Bool]
    let cardDraws: [GameRules.CardDraw]

    var missedPrefectureCount: Int {
        firstTryByPrefecture.values.filter { !$0 }.count
    }
}
