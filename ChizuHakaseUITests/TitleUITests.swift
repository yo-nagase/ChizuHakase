import XCTest

/// The title's two pages — the whole app's one japan/world branch (design doc
/// §2). What is pinned here: the world page is reachable through the visible
/// page-edge tab (not only by swipe), its あそぶ opens the *world's* stage
/// shelf, the open page survives a relaunch, and japan's page is still the
/// title it always was.
///
/// Both pages exist in the pager at once, so `exists` alone cannot say which
/// page is in front — every "on this page" assertion goes through `hittable`.
final class TitleUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// Waits until the element is actually on the glass, not merely present on
    /// the pager's other page.
    @discardableResult
    private func waitHittable(_ element: XCUIElement,
                              timeout: TimeInterval = 10) -> Bool {
        let onGlass = NSPredicate(format: "exists == true AND hittable == true")
        let wait = XCTNSPredicateExpectation(predicate: onGlass, object: element)
        return XCTWaiter().wait(for: [wait], timeout: timeout) == .completed
    }

    /// The fresh-save learned tally of each page, by its page-specific noun.
    /// けん/くに is the one wording difference between the two pages' tallies,
    /// which makes it the honest way to tell them apart.
    private var japanTally: XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "おぼえた けん")).firstMatch
    }
    private var worldTally: XCUIElement {
        app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "おぼえた くに")).firstMatch
    }

    /// The page-edge tab is the discoverable way in (design doc §2: swipe
    /// alone is not findable at five) — so the way in is what this exercises.
    func testTheEdgeTabTurnsToTheWorldPage() {
        app.launchArguments = ["-resetSave"]
        app.launch()

        XCTAssertTrue(waitHittable(japanTally), "the japan page never appeared")

        app.buttons["せかいの ちずへ"].tap()

        XCTAssertTrue(waitHittable(worldTally),
                      "the world page did not come on after the page-edge tab")
        XCTAssertTrue(app.buttons["にほんの ちずへ"].isHittable,
                      "the world page must carry the visible way back")
    }

    /// Swiping also turns the page (design doc §2: スワイプ併用) — the tab is
    /// the discoverable way in, the swipe is the natural one, and the world
    /// slot must build its content for either.
    func testSwipingAlsoTurnsThePage() {
        app.launchArguments = ["-resetSave"]
        app.launch()

        XCTAssertTrue(waitHittable(japanTally), "the japan page never appeared")
        app.swipeLeft()
        XCTAssertTrue(waitHittable(worldTally),
                      "a swipe should turn to the world page")
    }

    /// あそぶ pressed on the world page opens the world's shelf: the session
    /// atlas is set by the open page, and every screen below reads it.
    func testPlayFromTheWorldPageOpensTheWorldShelf() {
        app.launchArguments = ["-resetSave"]
        app.launch()

        XCTAssertTrue(waitHittable(app.buttons["せかいの ちずへ"]))
        app.buttons["せかいの ちずへ"].tap()

        let worldPlay = app.buttons["title-play-world"]
        XCTAssertTrue(waitHittable(worldPlay), "no あそぶ on the world page")
        worldPlay.tap()

        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "きた・ちゅうおうアメリカ"))
            .firstMatch.waitForExistence(timeout: 10),
            "あそぶ from the world page should land on the world's stage shelf")
    }

    /// The open page is remembered (settings.lastAtlas): a child who was in
    /// the world book comes back to the world book (design doc §2).
    func testTheOpenPageSurvivesARelaunch() {
        app.launchArguments = ["-resetSave"]
        app.launch()

        XCTAssertTrue(waitHittable(app.buttons["せかいの ちずへ"]))
        app.buttons["せかいの ちずへ"].tap()
        XCTAssertTrue(waitHittable(worldTally))

        app.terminate()
        // No -resetSave this time: the relaunch must read the remembered page.
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(waitHittable(worldTally),
                      "a relaunch should reopen the world page")
        XCTAssertFalse(japanTally.isHittable,
                       "japan's page should be the one waiting behind the turn")
    }

    /// Japan's page is still the title it always was: tallies, あそぶ, the
    /// attribution the footer owes (CLAUDE.md §3) — plus the new tab, on the
    /// edge, not in the way.
    func testTheJapanPageStillCarriesTheTitle() {
        app.launchArguments = ["-resetSave"]
        app.launch()

        XCTAssertTrue(waitHittable(japanTally), "the japan learned tally is gone")
        XCTAssertTrue(app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "もっている カード"))
            .firstMatch.isHittable, "the japan card tally is gone")
        XCTAssertTrue(app.buttons["title-play-japan"].isHittable,
                      "あそぶ is gone from the japan page")
        XCTAssertTrue(app.staticTexts["ちずデータ: Global Map Japan (国土地理院) をもとに簡略化"]
            .exists, "the map attribution left the title footer")
        XCTAssertTrue(app.buttons["せかいの ちずへ"].isHittable,
                      "the world's page-edge tab is missing from page one")
        XCTAssertFalse(app.buttons["title-play-world"].isHittable,
                       "the world's あそぶ must not be pressable from page one")
    }
}
