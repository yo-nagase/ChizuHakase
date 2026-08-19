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

    /// The world book's shelf: the same picker, fed the world atlas
    /// (`-atlas world`), lists all 18 continent stages under their continent
    /// headers (docs/plans/2026-08-18-world-stages.md, UI 決定 2026-08-20).
    /// The shelf is a plain VStack, so every board exists without scrolling.
    func testTheWorldShelfCarriesAllSignboardsUnderContinentHeaders() {
        app.launchArguments = ["-resetSave", "-atlas", "world",
                               "-startAt", "stageSelect"]
        app.launch()

        // First and last board by name — the shelf runs アメリカ → オセアニア.
        // Board labels start with the stage name and carry the question count
        // (「…。N もん。…」), which no other element on the screen does.
        let boards = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", " もん。"))
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "きた・ちゅうおうアメリカ"))
            .firstMatch.waitForExistence(timeout: 10),
            "the world's first signboard never appeared")
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "オセアニア")).firstMatch.exists,
            "the world's last signboard is missing")
        XCTAssertEqual(boards.count, 18, "the world shelf should hold 18 signboards")

        // A continent header stands between the boards. アフリカ is a header
        // only — every stage under it says きた/にし/…アフリカ, so an exact
        // match cannot be satisfied by a signboard.
        XCTAssertTrue(app.staticTexts["アフリカ"].exists,
                      "the アフリカ continent header is missing")
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
