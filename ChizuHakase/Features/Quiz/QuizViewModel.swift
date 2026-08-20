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
    let mode: QuizMode
    private let mapData: MapData
    private let catalog: CardCatalog
    /// How the asked region's cards enter the draw — the atlas's one rule
    /// difference, handed in as data so no view branches on which book this is.
    private let drawPolicy: GameRules.DrawPolicy
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
    /// Prefecture codes offered for the current question in 「なまえを あてる」.
    /// Empty in the map mode.
    private(set) var choices: [Int] = []
    /// Names already ruled out on this question. They stay on screen greyed
    /// out rather than vanishing: a choice that disappears takes the memory of
    /// having tried it with it.
    private(set) var ruledOut: Set<Int> = []

    private var firstTryByPrefecture: [Int: Bool] = [:]
    /// Each asking's clean flag in the order asked, per prefecture — what the
    /// streak is fed from. Recorded once per question, when it is answered.
    private var outcomesByPrefecture: [Int: [Bool]] = [:]
    private var draws: [GameRules.CardDraw] = []
    /// Save-data card counts plus whatever this stage has already awarded, so a
    /// single run cannot hand out the same unowned card twice.
    private var ownedCards: [String: Int]
    /// Whether this sitting was *drawn* (a sampling challenge) rather than a
    /// pass over every code — the flag `makeResult` uses to decide whether
    /// `askedCodes` has anything to say.
    private let drewBySelection: Bool
    private var effectCounter = 0

    /// `askedInChallenge` is the unasked-first memory of a sampling challenge
    /// (world design §8): the codes this mode's challenge has already asked,
    /// off the played book's save slice. It has no default on purpose, the
    /// same reasoning that is removing `drawPolicy`'s: a call site that forgot
    /// it would still compile, and the challenge would quietly lose its
    /// coverage guarantee — every sitting a fresh uniform draw — with every
    /// test still green. For stages that never sample (all of japan's, the
    /// world's continents) the value is read by nothing; passing the slice's
    /// `[]` there is the truth, not a placeholder.
    init(stage: Stage,
         mode: QuizMode = .findOnMap,
         mapData: MapData,
         catalog: CardCatalog,
         ownedCards: [String: Int] = [:],
         drawPolicy: GameRules.DrawPolicy = .random,
         askedInChallenge: Set<Int>,
         generator: AnyRandomNumberGenerator = AnyRandomNumberGenerator()) {
        self.stage = stage
        self.mode = mode
        self.mapData = mapData
        self.catalog = catalog
        self.ownedCards = ownedCards
        self.drawPolicy = drawPolicy
        self.rng = generator
        // Only prefectures that actually have shapes become questions, so a
        // truncated resource shortens the stage instead of asking the
        // impossible.
        let codes = mapData.prefectures(in: stage.codes).map(\.code)
        self.tappableCodes = Set(codes)
        if stage.isChallenge && codes.count > GameRules.challengeQuestionCount {
            // A challenge over more codes than one sitting: draw 47, unasked
            // first (world design §8), each exactly once. Japan's ぜんこく
            // never takes this branch — its 47 codes are not *more than* 47 —
            // so its order stays the full-country shuffle it has always been.
            self.drewBySelection = true
            self.order = GameRules.challengeSelection(
                codes: codes,
                asked: askedInChallenge,
                count: GameRules.challengeQuestionCount,
                using: &self.rng)
        } else {
            self.drewBySelection = false
            self.order = GameRules.questionOrder(
                codes: codes,
                repeats: stage.asksEachTwice ? 2 : 1,
                using: &self.rng)
        }
        if order.isEmpty { phase = .finished }
        dealChoices()
    }

    /// Fresh names for the current question. Called once per question so the
    /// four buttons do not reshuffle under a finger mid-answer.
    private func dealChoices() {
        ruledOut = []
        guard mode == .nameIt, let target else { return choices = [] }
        // Distinct codes, not `order`: a regional stage lists every prefecture
        // twice, and drawing decoys from that offered the same name twice.
        choices = GameRules.nameChoices(answer: target.code,
                                        from: Array(Set(order)).sorted(),
                                        using: &rng)
    }

    // MARK: - Derived state

    var target: Prefecture? {
        guard order.indices.contains(index) else { return nil }
        return mapData[order[index]]
    }

    var questionNumber: Int { min(index + 1, order.count) }
    var questionCount: Int { order.count }

    /// Every prefecture in the stage stays tappable for the whole run.
    ///
    /// Answered ones used to drop out, which paired with them changing colour
    /// to make each question easier than the last — by the seventh there was
    /// one shape left and no question worth asking. They also get asked again,
    /// so they have to stay live.
    ///
    /// The stage's codes, not `order`'s: on a sampling challenge the sitting
    /// asks 47 of the book's countries but the map shows all of them, and a
    /// wrong tap on one that was not drawn has to shake as a miss — a tap the
    /// map swallows in silence reads as the app being broken. Everywhere else
    /// the two sets are equal.
    var interactiveCodes: Set<Int> {
        phase == .asking ? tappableCodes : []
    }

    /// `Set` of every code in the stage that has a shape (see
    /// `interactiveCodes`). Fixed at init alongside `order`.
    private let tappableCodes: Set<Int>

    /// Distinct prefectures asked, which is what stars are judged against.
    /// Not `order.count`: a stage that asks 7 prefectures twice is still a
    /// 7-prefecture stage, and scoring it out of 14 would quietly grade it on
    /// a curve.
    var prefectureCount: Int { Set(order).count }

    /// After two misses the answer's outline starts blinking.
    var hintCode: Int? {
        guard phase == .asking, attempts >= GameRules.missesBeforeHint else { return nil }
        return target?.code
    }

    var missedPrefectureCount: Int {
        firstTryByPrefecture.values.filter { !$0 }.count
    }

    var stars: Int {
        GameRules.stars(missedPrefectures: missedPrefectureCount,
                        prefectureCount: prefectureCount)
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

        // A prefecture asked twice counts as clean only if it was clean both
        // times. Overwriting would let the second pass erase a fumble on the
        // first, which is the opposite of what asking twice is for.
        firstTryByPrefecture[target.code] =
            (firstTryByPrefecture[target.code] ?? true) && firstTry
        outcomesByPrefecture[target.code, default: []].append(firstTry)
        answeredCodes.insert(target.code)

        let draw = GameRules.earnsCard(afterMisses: attempts)
            ? GameRules.drawCard(from: catalog.cards(for: target.code),
                                 owned: ownedCards, policy: drawPolicy, using: &rng)
            : nil
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
        ruledOut.insert(code)
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
        dealChoices()
    }

    private func fire(_ kind: MapEffect.Kind, on code: Int) {
        effectCounter += 1
        effect = MapEffect(code: code, kind: kind, id: effectCounter)
    }

    // MARK: - Output

    func makeResult() -> StageResult {
        StageResult(mode: mode,
                    stageIndex: stage.index,
                    score: score,
                    stars: stars,
                    firstTryByPrefecture: firstTryByPrefecture,
                    cardDraws: draws,
                    outcomesByPrefecture: outcomesByPrefecture,
                    // Only a drawn sitting has challenge history to report —
                    // japan's ぜんこく (and every regional stage) writes
                    // nothing, which is what keeps its save slice's
                    // askedInChallenge empty forever.
                    askedCodes: drewBySelection ? Set(order) : [])
    }
}
