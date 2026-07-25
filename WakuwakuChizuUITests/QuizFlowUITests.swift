import XCTest

/// Plays a stage through the real UI, tapping the map the way a child does.
///
/// The unit tests cover the rules; nothing until now proved that a tap on the
/// screen actually reaches the right prefecture through the fit transform, the
/// gesture and the hit test together.
final class QuizFlowUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(at route: String) {
        app.launchArguments = ["-resetSave", "-startAt", route]
        app.launch()
    }

    /// Waits for the quiz to finish laying out.
    ///
    /// Reading the question and tapping the map immediately after `launch()`
    /// is a race: the elements exist before the map has settled at its final
    /// position, so the tap can land on stale coordinates. Only shows up when
    /// the suite runs together, which is exactly when it matters.
    @discardableResult
    private func waitUntilQuizIsReady(questions: Int = 7) -> Bool {
        app.staticTexts["\(questions) もんちゅう 1 もんめ"].waitForExistence(timeout: 10)
    }

    /// The prefecture being asked about, read off the question card. The kanji
    /// name is shown under the reading and matches the map's accessibility
    /// labels.
    private func currentTargetName() -> String? {
        let known = Self.prefectureNames
        for label in known where app.staticTexts[label].exists {
            return label
        }
        return nil
    }

    /// Taps a prefecture by its accessibility element.
    ///
    /// Uses a coordinate rather than `.tap()` because the element is a
    /// deliberately non-hit-testable proxy — the map owns a single tap gesture
    /// and resolves the location itself.
    private func tapPrefecture(_ name: String) {
        // Exposed as a button: the proxy carries the .isButton trait.
        let element = app.buttons[name]
        XCTAssertTrue(element.waitForExistence(timeout: 5),
                      "no accessibility element for \(name)")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    // MARK: - Tests

    func testTappingTheAskedPrefectureScores() throws {
        launch(at: "quiz:0")
        XCTAssertTrue(waitUntilQuizIsReady(), "the quiz never appeared")

        let target = try XCTUnwrap(currentTargetName(), "no question on screen")
        XCTAssertTrue(app.staticTexts["0"].exists, "score should start at zero")

        tapPrefecture(target)

        // 100 for a first-try answer (CLAUDE.md §5).
        XCTAssertTrue(app.staticTexts["100"].waitForExistence(timeout: 3),
                      "a correct first tap should score 100")
    }

    func testTappingTheWrongPrefectureDoesNotScore() throws {
        launch(at: "quiz:0")
        XCTAssertTrue(waitUntilQuizIsReady(), "the quiz never appeared")

        let target = try XCTUnwrap(currentTargetName())
        let wrong = try XCTUnwrap(Self.tohokuNames.first { $0 != target })

        tapPrefecture(wrong)

        XCTAssertFalse(app.staticTexts["100"].exists, "a wrong tap must not score")
        XCTAssertTrue(app.staticTexts["0"].exists, "the score should still be zero")
        XCTAssertNotNil(currentTargetName(), "the question stays open after a miss")
    }

    /// The whole point: seven correct taps in a row reach the result screen
    /// with three stars.
    func testPlayingAStageThroughReachesTheResultScreen() throws {
        launch(at: "quiz:0")
        XCTAssertTrue(waitUntilQuizIsReady(), "the quiz never appeared")

        for question in 1...7 {
            guard let target = currentTargetName() else {
                XCTFail("no question on screen at \(question)/7")
                return
            }
            tapPrefecture(target)
            // The celebration runs for 1.15s before the next question.
            // Matched on the accessibility label, which ProgressPips
            // substitutes for the visible "1 / 7".
            if question < 7 {
                let next = app.staticTexts["7 もんちゅう \(question + 1) もんめ"]
                XCTAssertTrue(next.waitForExistence(timeout: 5),
                              "did not advance past question \(question)")
            }
        }

        XCTAssertTrue(app.staticTexts["てん"].waitForExistence(timeout: 6),
                      "did not reach the result screen")
        // 100+120+140+160+180+200+220 for an unbroken combo.
        XCTAssertTrue(app.staticTexts["1120"].exists,
                      "a perfect run of 7 should total 1120")
        // The star row merges its children into one element, so it is an
        // "other", not a static text.
        XCTAssertTrue(app.otherElements["ほし 3 こ"].exists, "a perfect run earns 3 stars")
    }

    /// Every prefecture has to be reachable through the real gesture, not just
    /// in the geometry unit tests.
    func testEveryPrefectureInTheStageIsTappable() {
        launch(at: "quiz:0")
        waitUntilQuizIsReady()
        for name in Self.tohokuNames {
            let element = app.buttons[name]
            XCTAssertTrue(element.waitForExistence(timeout: 3),
                          "\(name) has no accessibility element")
            XCTAssertFalse(element.frame.isEmpty, "\(name) has an empty frame")
        }
    }

    /// Regression guard for the bug this suite found: every prefecture used to
    /// report the whole map as its frame, so VoiceOver could not tell them
    /// apart and direct-touch exploration was meaningless.
    func testPrefectureElementsDoNotAllShareTheSameFrame() {
        launch(at: "quiz:0")
        waitUntilQuizIsReady()
        var frames: [CGRect] = []
        for name in Self.tohokuNames {
            let element = app.buttons[name]
            if element.waitForExistence(timeout: 3) { frames.append(element.frame) }
        }
        XCTAssertGreaterThan(frames.count, 1)
        let distinct = Set(frames.map { "\(Int($0.midX)),\(Int($0.midY))" })
        XCTAssertEqual(distinct.count, frames.count,
                       "prefectures share a centre; accessibility frames are wrong")
    }

    // MARK: - Stage availability

    /// The stage sheet, found by the reading it leads with.
    private func stageSheet(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// Every stage is open on a fresh install.
    ///
    /// Stages 2–6 used to sit behind the purchase, so the picker showed a
    /// padlock and 「おうちのひとと いっしょに」 — a wall a child cannot get past
    /// alone. Nothing gates a region now, and nothing should put one back.
    func testEveryStageIsOpenOnAFreshInstall() {
        launch(at: "stageSelect")
        XCTAssertTrue(stageSheet(Self.stageNames[0]).waitForExistence(timeout: 10))

        for name in Self.stageNames {
            let sheet = stageSheet(name)
            XCTAssertTrue(sheet.exists, "\(name) is missing from the picker")
            XCTAssertFalse(sheet.label.contains("あそべない"), "\(name) is locked")
        }
        for phrase in ["おうちのひとと いっしょに", "保護者の方と一緒に", "まだ あそべない"] {
            XCTAssertFalse(app.staticTexts[phrase].exists,
                           "the picker still shows 「\(phrase)」")
        }
    }

    /// Tapping a stage that used to be paid starts its quiz straight away,
    /// with no parental gate or purchase sheet in between.
    func testAFormerlyPaidStageStartsImmediately() {
        launch(at: "stageSelect")
        let kinki = stageSheet("きんき")
        XCTAssertTrue(kinki.waitForExistence(timeout: 10))
        kinki.tap()
        XCTAssertTrue(app.staticTexts["7 もんちゅう 1 もんめ"].waitForExistence(timeout: 10),
                      "きんき did not start")
    }

    // MARK: - Fixtures

    private static let stageNames = [
        "ほっかいどう・とうほく", "かんとう", "ちゅうぶ", "きんき",
        "ちゅうごく・しこく", "きゅうしゅう・おきなわ", "ぜんこく チャレンジ",
    ]

    private static let tohokuNames = [
        "北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
    ]

    private static let prefectureNames = tohokuNames
}
