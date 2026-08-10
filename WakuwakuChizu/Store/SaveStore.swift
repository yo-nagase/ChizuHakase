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

    /// Schema moves that need more than decoding can do.
    ///
    /// Version 1 → 2 (records split per quiz mode) is handled inside
    /// `SaveData.init(from:)`, because it is a rename of a key rather than a
    /// transformation across fields — doing it there means a decode always
    /// yields the current shape, with no window where a half-migrated value
    /// could be written back out. This stays as the hook for the migration that
    /// eventually cannot be expressed that way.
    private static func migrate(_ input: SaveData) -> SaveData {
        input
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

    /// Apply one finished stage: best-of record, mastery gains, cards won,
    /// streaks moved and any rainbow latched. Returns what crossed a threshold
    /// this run, so the result screen can call each one out individually.
    ///
    /// The catalog is how a streak finds the rest of its prefecture's cards —
    /// without it gold can never turn rainbow, so only tests that are not
    /// about cards pass `.empty`.
    @discardableResult
    func applyStageResult(_ result: StageResult, catalog: CardCatalog) -> StageGains {
        var newlySparkling: [Int] = []
        var newlyRainbow: [String] = []

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

        for (code, outcomes) in result.outcomesByPrefecture {
            data.streaks[code] = GameRules.nextStreak(current: data.streak(of: code),
                                                      outcomes: outcomes)
        }

        // The rainbow latch, checked after stars and streaks have both moved so
        // either order of arrival — gold first or streak first — catches here.
        // Only prefectures this stage touched can have changed.
        for code in result.outcomesByPrefecture.keys {
            let streak = data.streak(of: code)
            for card in catalog.cards(for: code)
            where GameRules.qualifiesForRainbow(stars: data.stars(of: card.id),
                                                streak: streak) {
                // Only the cards the latch actually caught this time. A card
                // that was already rainbow is not news, and re-announcing it
                // every stage would turn the rarest thing in the game into
                // wallpaper.
                if data.rainbow.insert(card.id).inserted { newlyRainbow.append(card.id) }
            }
        }

        // Stars and score are kept per mode; mastery and cards above are not,
        // because they measure the prefecture rather than the run.
        let record = StageRecord(stars: result.stars, score: result.score)
        data.records[result.mode.rawValue, default: [:]][result.stageIndex] =
            GameRules.bestRecord(
                existing: data.record(forStage: result.stageIndex, mode: result.mode),
                new: record)

        save()
        // Both sorted: the loops above walk dictionary keys, and a celebration
        // that lists the same two prefectures in a different order each run
        // reads as two different events.
        return StageGains(sparklingPrefectures: newlySparkling.sorted(),
                          rainbowCards: newlyRainbow.sorted())
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

/// What one finished stage pushed over a line, for the result screen to make
/// a fuss about.
///
/// Everything here is a *promotion*, not a standing total: what the child did
/// not have before this run and has now. The screen already shows the totals,
/// and a celebration that fires for something the child earned last week is
/// not a celebration.
nonisolated struct StageGains: Sendable, Hashable {
    /// Prefecture codes that reached mastery level 3.
    var sparklingPrefectures: [Int] = []
    /// Card IDs the rainbow latch caught. Can name cards this run never drew:
    /// crossing a fifteen-streak promotes every gold card the prefecture has
    /// at once, which is the whole point of it being the streak's medal.
    var rainbowCards: [String] = []
}

/// The finished stage, handed from the quiz to the store and the result screen,
/// so the scoring rules stay out of the persistence layer.
nonisolated struct StageResult: Sendable, Hashable {
    let mode: QuizMode
    let stageIndex: Int
    let score: Int
    let stars: Int
    /// prefecture code -> answered correctly on the first attempt
    let firstTryByPrefecture: [Int: Bool]
    let cardDraws: [GameRules.CardDraw]
    /// prefecture code -> each asking's clean flag, in the order asked.
    ///
    /// Not derivable from `firstTryByPrefecture`: the streak needs to know that
    /// a prefecture fumbled first and clean second *ended* on a run of one,
    /// which the collapsed flag has already thrown away.
    var outcomesByPrefecture: [Int: [Bool]] = [:]

    var missedPrefectureCount: Int {
        firstTryByPrefecture.values.filter { !$0 }.count
    }
}
