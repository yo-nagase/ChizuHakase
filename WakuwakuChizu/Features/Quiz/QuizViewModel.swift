import Foundation
import Observation

/// Runs one stage: question order, judging, score, combo and hints
/// (CLAUDE.md §5).
///
/// Holds no timers and no view code — the view decides when to call `advance()`
/// so the celebration can play out, which keeps every rule here testable.
@Observable
final class QuizViewModel {

    enum Phase: Equatable {
        /// Waiting for a tap.
        case asking
        /// Correct; the pop and card reveal are playing.
        case celebrating
        case finished
    }

    /// What a tap produced, for the view to turn into sound and animation.
    enum Answer: Equatable {
        case correct(firstTry: Bool, points: Int, draw: GameRules.CardDraw?)
        case wrong(code: Int)
        /// Tap landed on sea, or arrived while the celebration was still running.
        case ignored
    }

    let stage: Stage
    private let mapData: MapData
    private let catalog: CardCatalog
    private var rng: AnyRandomNumberGenerator

    private(set) var order: [Int] = []
    private(set) var index = 0
    /// Wrong taps on the current question.
    private(set) var attempts = 0
    private(set) var score = 0
    private(set) var combo = 0
    private(set) var phase: Phase = .asking
    private(set) var answeredCodes: Set<Int> = []
    private(set) var effect: MapEffect?
    private(set) var lastDraw: GameRules.CardDraw?

    private var firstTryByPrefecture: [Int: Bool] = [:]
    private var draws: [GameRules.CardDraw] = []
    /// Save-data card counts plus whatever this stage has already awarded, so a
    /// single run cannot hand out the same unowned card twice.
    private var ownedCards: [String: Int]
    private var effectCounter = 0

    init(stage: Stage,
         mapData: MapData,
         catalog: CardCatalog,
         ownedCards: [String: Int] = [:],
         generator: AnyRandomNumberGenerator = AnyRandomNumberGenerator()) {
        self.stage = stage
        self.mapData = mapData
        self.catalog = catalog
        self.ownedCards = ownedCards
        self.rng = generator
        // Only prefectures that actually have shapes become questions, so a
        // truncated resource shortens the stage instead of asking the
        // impossible.
        self.order = mapData.prefectures(in: stage.codes).map(\.code)
            .shuffled(using: &self.rng)
        if order.isEmpty { phase = .finished }
    }

    // MARK: - Derived state

    var target: Prefecture? {
        guard order.indices.contains(index) else { return nil }
        return mapData[order[index]]
    }

    var questionNumber: Int { min(index + 1, order.count) }
    var questionCount: Int { order.count }

    /// Prefectures still tappable: in-stage and not yet answered (CLAUDE.md §5).
    var interactiveCodes: Set<Int> {
        phase == .asking ? Set(order).subtracting(answeredCodes) : []
    }

    /// After two misses the answer's outline starts blinking.
    var hintCode: Int? {
        guard phase == .asking, attempts >= GameRules.missesBeforeHint else { return nil }
        return target?.code
    }

    var missedPrefectureCount: Int {
        firstTryByPrefecture.values.filter { !$0 }.count
    }

    var stars: Int {
        GameRules.stars(missedPrefectures: missedPrefectureCount, questionCount: order.count)
    }

    // MARK: - Playing

    @discardableResult
    func answer(_ code: Int) -> Answer {
        guard phase == .asking, let target else { return .ignored }
        guard code == target.code else { return recordMiss(code) }
        return recordHit(target)
    }

    private func recordHit(_ target: Prefecture) -> Answer {
        let firstTry = attempts == 0
        combo = GameRules.nextCombo(current: combo, correct: true, firstTry: firstTry)
        let points = GameRules.score(firstTry: firstTry, combo: combo)
        score += points

        // A prefecture answered cleanly on a replay must not lose the credit it
        // earned earlier in this same stage; first write wins is not a concern
        // because each code is asked once per stage.
        firstTryByPrefecture[target.code] = firstTry
        answeredCodes.insert(target.code)

        let draw = GameRules.drawCard(from: catalog.cards(for: target.code),
                                      owned: ownedCards, using: &rng)
        if let draw {
            ownedCards = GameRules.applyDraw(draw, to: ownedCards)
            draws.append(draw)
        }
        lastDraw = draw

        phase = .celebrating
        fire(.pop, on: target.code)
        return .correct(firstTry: firstTry, points: points, draw: draw)
    }

    private func recordMiss(_ code: Int) -> Answer {
        attempts += 1
        combo = 0
        // Recorded as missed the moment it is first fumbled; getting it right
        // later still counts for the stage, just not for mastery.
        firstTryByPrefecture[target?.code ?? code] = false
        fire(.shake, on: code)
        return .wrong(code: code)
    }

    /// Move to the next question. Called by the view once the celebration for
    /// the current one has finished.
    func advance() {
        guard phase != .finished else { return }
        index += 1
        attempts = 0
        lastDraw = nil
        effect = nil
        phase = index >= order.count ? .finished : .asking
    }

    private func fire(_ kind: MapEffect.Kind, on code: Int) {
        effectCounter += 1
        effect = MapEffect(code: code, kind: kind, id: effectCounter)
    }

    // MARK: - Output

    func makeResult() -> StageResult {
        StageResult(stageIndex: stage.index,
                    score: score,
                    stars: stars,
                    firstTryByPrefecture: firstTryByPrefecture,
                    cardDraws: draws)
    }
}
