import Foundation

/// v1 fixes the question and scoring rules. New rules need new board IDs.
nonisolated struct RankingBoard: Codable, Hashable, Sendable {
    let atlas: String
    let stage: Int
    let mode: QuizMode
    let questionCount: Int

    var id: String { "chizuhakase.v1.\(atlas).s\(stage).\(mode.rawValue).q\(questionCount)" }
}

nonisolated struct RankingRun: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let board: RankingBoard
    let date: Date
    let correct: Int
    let milliseconds: Int
    let completed: Bool
    let interrupted: Bool
    /// Captured at the start; never attribute an old guest run to a later login.
    let playerID: String?

    // One accuracy point always outweighs the entire time component.
    // Runs beyond 24 hours remain local rather than clamping distinct times.
    static let timeBase = 86_400_000
    var packedScore: Int? {
        guard completed, !interrupted, board.questionCount > 0,
              (0...board.questionCount).contains(correct),
              (0..<Self.timeBase).contains(milliseconds) else { return nil }
        return correct * Self.timeBase + Self.timeBase - 1 - milliseconds
    }

    static func unpack(_ score: Int) -> (correct: Int, milliseconds: Int) {
        (score / timeBase, timeBase - 1 - score % timeBase)
    }

    static func precedes(_ lhs: Self, _ rhs: Self) -> Bool {
        if lhs.correct != rhs.correct { return lhs.correct > rhs.correct }
        if lhs.milliseconds != rhs.milliseconds { return lhs.milliseconds < rhs.milliseconds }
        return lhs.date < rhs.date
    }

    static func timeLabel(_ milliseconds: Int) -> String {
        String(format: "%.3f", Double(milliseconds) / 1_000) + " びょう"
    }
}

/// Monotonic timestamps make wall-clock changes irrelevant to rankings.
nonisolated struct RankingTimer {
    private var startedAt: TimeInterval?
    private var elapsed: TimeInterval = 0
    private(set) var interrupted = false

    mutating func start(at now: TimeInterval) {
        if startedAt == nil { startedAt = now }
    }
    mutating func pause(at now: TimeInterval) {
        if let start = startedAt { elapsed += max(0, now - start) }
        startedAt = nil
    }
    mutating func interrupt(at now: TimeInterval) {
        pause(at: now)
        interrupted = true
    }
    func milliseconds(at now: TimeInterval) -> Int {
        let total = elapsed + (startedAt.map { max(0, now - $0) } ?? 0)
        return Int((total * 1_000).rounded(.down))
    }
}
