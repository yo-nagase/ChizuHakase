import XCTest

/// The card book's filters, and the one the title screen arrives on.
final class CardBookUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launch(at route: String, withCards: Bool = false) {
        app.launchArguments = ["-resetSave", "-startAt", route]
        if withCards { app.launchArguments.append("-grantCards") }
        app.launch()
    }

    private var detailIsOpen: Bool { app.buttons["とじる"].exists }

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

    // MARK: - Opening one card

    /// A card you own opens on its own, big enough to look at.
    func testTappingAnOwnedCardOpensIt() {
        launch(at: "cardBook", withCards: true)
        let card = app.buttons["かに"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the owned card is not in the book")
        XCTAssertFalse(detailIsOpen, "the card was open before anything was tapped")

        card.tap()
        XCTAssertTrue(app.buttons["とじる"].waitForExistence(timeout: 3),
                      "tapping a card did not open it")
        // The description travels with it: this is the screen for reading the
        // card, not just for seeing it larger.
        XCTAssertTrue(app.staticTexts["つめたい うみで そだつよ"].exists)
    }

    func testTheOpenedCardCloses() {
        launch(at: "cardBook", withCards: true)
        let card = app.buttons["かに"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let close = app.buttons["とじる"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2), "the card would not close")
    }

    /// An unowned slot must not open. There is nothing behind a 「？」, and a
    /// tap that produces an empty card is a small lie.
    func testAnUnownedSlotDoesNotOpen() {
        launch(at: "cardBook", withCards: true)
        let slot = app.buttons.matching(NSPredicate(format: "label == %@",
                                                    "まだ もっていない カード")).firstMatch
        XCTAssertFalse(slot.exists, "an unowned slot should not be a button at all")
        XCTAssertFalse(detailIsOpen)
    }
}
