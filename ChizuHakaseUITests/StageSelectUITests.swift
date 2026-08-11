import XCTest

/// The stage list's progress line.
final class StageSelectUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(learned: Bool) {
        app.launchArguments = ["-resetSave", "-startAt", "stageSelect"]
        if learned { app.launchArguments.append("-learnFirstStage") }
        app.launch()
    }

    /// A covered regional stage has to read as covered.
    ///
    /// The count is prefectures, and a regional stage asks each of its seven
    /// twice. Measured against the question count it could never pass half, so
    /// a child who had just cleared every prefecture in 「ほっかいどう・とうほく」
    /// was shown 「7 / 14」 — told they were halfway through something they had
    /// finished (CLAUDE.md §12).
    func testAFullyCoveredStageReadsAsFull() {
        launch(learned: true)
        XCTAssertTrue(app.staticTexts["シール 7 / 7"].waitForExistence(timeout: 10),
                      "a stage with every prefecture covered did not show as full")
        XCTAssertFalse(app.staticTexts["シール 7 / 14"].exists,
                       "the denominator is counting questions again")
    }

    /// The national stage is the one place the two counts coincide, so it can
    /// never catch the bug above on its own.
    func testTheNationalStageCountsAllFortySeven() {
        launch(learned: false)
        XCTAssertTrue(app.staticTexts["シール 0 / 47"].waitForExistence(timeout: 10),
                      "the national stage should count every prefecture in the country")
    }
}
