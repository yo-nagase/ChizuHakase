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

    /// A chip's label carries its stars and tier as well as its name, so it is
    /// matched on the name rather than pinned to a whole string that changes
    /// every time the card goes up a star.
    private func chip(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// Tapping the ✨ count has to land on those cards, not on a book of 141
    /// with the nine somewhere inside it.
    func testTheKiraCountOpensTheBookAlreadyFiltered() {
        launch(at: "cardBook:special")
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
        launch(at: "cardBook:special")
        XCTAssertTrue(app.staticTexts["まだ もっていない カード"].waitForExistence(timeout: 10),
                      "an empty filter showed a blank page")
    }

    func testSwitchingBackToEverythingWorks() {
        launch(at: "cardBook:special")
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
        let card = chip(named: "かに")
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
        let card = chip(named: "かに")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let close = app.buttons["とじる"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2), "the card would not close")
    }

    /// Pinching the open card makes it bigger, and the tilt gesture attached
    /// alongside it must not swallow the pinch.
    func testTheOpenCardCanBePinchedLarger() {
        launch(at: "cardBook", withCards: true)
        let card = chip(named: "かに")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let caption = app.staticTexts["かに"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 3))
        let before = caption.frame.width

        // scaleEffect changes the reported frame, so this reads the actual
        // rendered size rather than trusting that the gesture fired. Two
        // attempts: a synthesised pinch occasionally lands before the view has
        // settled and is simply ignored, and one dropped gesture is not a
        // regression worth failing a suite over.
        var grew = false
        for _ in 0..<2 where !grew {
            app.pinch(withScale: 2.2, velocity: 2)
            for _ in 0..<15 where !grew {
                grew = app.staticTexts["かに"].firstMatch.frame.width > before * 1.2
                if !grew { Thread.sleep(forTimeInterval: 0.2) }
            }
        }
        XCTAssertTrue(grew, "pinching did not enlarge the card")
    }

    /// Zoomed in, a drag moves the card instead of turning it. Having asked to
    /// look closer, the next thing a child says is *at what* — and the turn
    /// gesture is the same one finger, so only one of them can be live.
    func testTheZoomedCardCanBeMoved() {
        launch(at: "cardBook", withCards: true)
        let card = chip(named: "かに")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let caption = app.staticTexts["かに"].firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 3))
        let before = caption.frame.width

        // The pan is deliberately not attached at rest, so it can only be
        // exercised after the zoom has actually taken.
        var zoomed = false
        for _ in 0..<2 where !zoomed {
            app.pinch(withScale: 2.5, velocity: 2)
            for _ in 0..<15 where !zoomed {
                zoomed = app.staticTexts["かに"].firstMatch.frame.width > before * 1.2
                if !zoomed { Thread.sleep(forTimeInterval: 0.2) }
            }
        }
        XCTAssertTrue(zoomed, "could not zoom in, so the pan cannot be tested")

        let start = app.staticTexts["かに"].firstMatch.frame.midY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22)))

        var moved = false
        for _ in 0..<15 where !moved {
            moved = abs(app.staticTexts["かに"].firstMatch.frame.midY - start) > 40
            if !moved { Thread.sleep(forTimeInterval: 0.2) }
        }
        XCTAssertTrue(moved, "dragging the zoomed card did not move it")
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
