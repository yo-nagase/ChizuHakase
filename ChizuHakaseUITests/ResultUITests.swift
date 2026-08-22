import XCTest

/// The result screen's card panel.
///
/// The cards a run just won are named here and nowhere else in the flow, so
/// this is where a child will try to touch one.
final class ResultUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetSave", "-startAt", "result"]
        app.launch()
    }

    /// A chip's label carries the region it came from as well as its stars and
    /// tier — 「ほっかいどう。かに。…」 — because a run's prizes arrive with no
    /// section heading to say which prefecture they belong to, and VoiceOver
    /// reads what the card already shows. So the card's own name is matched
    /// inside the label rather than from the start of it.
    private func chip(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "。\(name)。"))
            .firstMatch
    }

    func testTappingAWonCardOpensIt() {
        let card = chip(named: "かに")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the won card is not on the result screen")
        XCTAssertFalse(app.buttons["とじる"].exists, "the card was open before anything was tapped")

        card.tap()
        XCTAssertTrue(app.buttons["とじる"].waitForExistence(timeout: 3),
                      "tapping a won card did not open it")
        // The description travels with it, the same as in the book: this is the
        // screen for reading the card, not just for seeing it larger.
        XCTAssertTrue(app.staticTexts["つめたい うみで そだつよ"].exists)
    }

    /// Closing comes back to the celebration rather than unwinding out of it —
    /// the card is a layer over the result, not a way off it.
    func testClosingTheCardReturnsToTheResult() {
        let card = chip(named: "かに")
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        let close = app.buttons["とじる"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2), "the card would not close")
        XCTAssertTrue(app.buttons["もういちど"].exists, "closing left the result screen")
    }

    /// A rainbow can latch onto a card the stage never drew, so it cannot ride
    /// in on the card tally — it needs its own panel or it happens in silence.
    func testTheRainbowPanelNamesWhatTurnedRainbow() {
        XCTAssertTrue(app.staticTexts["🌈 にじいろに なった カード!"].waitForExistence(timeout: 10),
                      "a card turned rainbow and the result screen said nothing")
    }

    /// And it opens, the same as any other card here — the foil is the reward,
    /// and a chip is too small to be the whole of it.
    func testARainbowCardOpensFromItsPanel() {
        let panel = app.staticTexts["🌈 にじいろに なった カード!"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))

        let card = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "にじいろカード")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3), "no rainbow card in the panel")
        card.tap()
        XCTAssertTrue(app.buttons["とじる"].waitForExistence(timeout: 3),
                      "the rainbow card would not open")
        XCTAssertTrue(app.staticTexts["さいこうの カード!"].exists,
                      "the top of the ladder did not say so")
    }

    /// The stars have to travel with the tap rather than be read back out of
    /// the save. A card opened at zero stars draws as an unowned slot — 「？？？」
    /// where its name goes — which is what a run's own prize must never become.
    func testAWonCardOpensAsOwnedRatherThanAsAnEmptySlot() {
        let card = chip(named: "にゅうせいひん")
        XCTAssertTrue(card.waitForExistence(timeout: 10), "the won card is not on the result screen")

        card.tap()
        XCTAssertTrue(app.buttons["とじる"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["にゅうせいひん"].exists,
                      "the opened card did not know it had been won")
    }
}
