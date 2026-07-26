import XCTest

/// The card book's filters, and the one the title screen arrives on.
final class CardBookUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(at route: String) {
        app.launchArguments = ["-resetSave", "-startAt", route]
        app.launch()
    }

    /// Tapping the ✨ count has to land on those cards, not on a book of 141
    /// with the nine somewhere inside it.
    func testTheKiraCountOpensTheBookAlreadyFiltered() {
        launch(at: "cardBook:shiny")
        let chip = app.buttons["✨ キラキラ"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "no キラキラ filter in the book")
        XCTAssertTrue(chip.isSelected, "the book did not open on the キラキラ filter")
    }

    func testTheBookOpensUnfilteredByDefault() {
        launch(at: "cardBook")
        let all = app.buttons["ぜんぶ"]
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        XCTAssertTrue(all.isSelected, "the book should open showing everything")
    }

    /// A fresh save has no キラ cards, so the filter empties the book. That has
    /// to read as "none yet" rather than as a screen that failed to load.
    func testAnEmptyFilterSaysSoRatherThanShowingNothing() {
        launch(at: "cardBook:shiny")
        XCTAssertTrue(app.staticTexts["まだ もっていない カード"].waitForExistence(timeout: 10),
                      "an empty filter showed a blank page")
    }

    func testSwitchingBackToEverythingWorks() {
        launch(at: "cardBook:shiny")
        let all = app.buttons["ぜんぶ"]
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        all.tap()
        XCTAssertTrue(all.isSelected)
        // A prefecture heading, not a card name: on a fresh save every card is
        // unowned and shows 「？？？」 instead of what it is.
        XCTAssertTrue(app.staticTexts["ほっかいどう"].waitForExistence(timeout: 5),
                      "the full book did not come back")
    }
}
