import XCTest

/// The stage list's progress line.
///
/// This used to pin a coverage chip (「answered at least once」 out of the
/// stage's prefectures). That chip is gone — it mostly measured having
/// pressed play — so what is pinned now is that the one tally that remains
/// is the earned one: the 「おぼえた」 count.
final class StageSelectUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// The demo save has 関東 fully learned, so its sheet must carry the
    /// learned count.
    func testTheLearnedCountSurfacesOnTheSheet() {
        app.launchArguments = ["-demoSave", "-startAt", "stageSelect"]
        app.launch()
        XCTAssertTrue(app.staticTexts["✨ おぼえた 7"].waitForExistence(timeout: 10),
                      "a fully learned stage does not show its learned count")
    }

    /// A stage that has only been *covered* — every prefecture answered once,
    /// nothing learned to the top — shows no count at all. A number that
    /// rewards showing up would cheapen the one that doesn't.
    func testMereCoverageShowsNoCount() {
        app.launchArguments = ["-resetSave", "-startAt", "stageSelect", "-learnFirstStage"]
        app.launch()
        XCTAssertTrue(app.staticTexts["ステージ"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "できた けん")).firstMatch.exists,
                       "the coverage chip is back")
    }
}
