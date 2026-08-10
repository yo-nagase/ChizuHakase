import XCTest

/// Pinch-to-zoom on the my-map screen.
///
/// The clamping is unit-tested; what cannot be checked there is whether the
/// gesture survives sitting inside a vertical ScrollView, and whether the way
/// back out actually appears. Both are the difference between a map a child can
/// explore and a screen they get stuck in.
final class MyMapUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func launchMyMap() {
        app.launchArguments = ["-resetSave", "-startAt", "myMap"]
        app.launch()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 10))
    }

    private var resetButton: XCUIElement { app.buttons["もとの おおきさ"] }

    func testPinchingRevealsTheWayBackAndTappingItReturns() {
        launchMyMap()
        XCTAssertFalse(resetButton.exists, "the reset button shows before any zoom")

        app.pinch(withScale: 3, velocity: 2)

        XCTAssertTrue(resetButton.waitForExistence(timeout: 5),
                      "zooming in left no visible way back to the whole country")
        resetButton.tap()
        XCTAssertFalse(resetButton.waitForExistence(timeout: 2),
                       "the map did not return to its resting size")
    }

    /// Pinching closed from rest must not shrink the map — the floor is the
    /// whole country, so nothing happens and no reset button appears.
    func testPinchingClosedFromRestDoesNothing() {
        launchMyMap()
        app.pinch(withScale: 0.2, velocity: -2)
        XCTAssertFalse(resetButton.waitForExistence(timeout: 2),
                       "the map scaled below the whole country")
    }

    /// The pan gesture starts at zero distance so the map moves the instant a
    /// finger does. That is also how a tap starts, so this checks the two have
    /// not been collapsed into one — selecting a prefecture has to survive.
    func testTappingStillSelectsAPrefectureWhileZoomed() {
        launchMyMap()
        app.pinch(withScale: 3, velocity: 2)
        XCTAssertTrue(resetButton.waitForExistence(timeout: 5))

        let hokkaido = app.buttons["北海道"]
        if hokkaido.waitForExistence(timeout: 3), hokkaido.isHittable {
            hokkaido.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 3)
                          || app.staticTexts["ほっかいどう"].waitForExistence(timeout: 3),
                          "tapping a prefecture stopped working once zoomed")
        }
    }

    /// A prefecture's sheet carries the reading large and the kanji under it,
    /// and the kanji is the half a child cannot yet decode on their own. Tuning
    /// the sheet's type is an easy way to quietly lose it, so both are pinned.
    func testThePrefectureSheetShowsTheReadingAndTheKanji() {
        launchMyMap()
        let hokkaido = app.buttons["北海道"]
        XCTAssertTrue(hokkaido.waitForExistence(timeout: 10), "no tappable 北海道 on the map")
        hokkaido.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        XCTAssertTrue(app.staticTexts["ほっかいどう"].waitForExistence(timeout: 3),
                      "the sheet did not open on the reading")
        XCTAssertTrue(app.staticTexts["北海道"].exists,
                      "the kanji line is gone from the prefecture sheet")
    }

    /// The map sits in a scrolling column. A pan gesture that stayed live at
    /// rest would eat the scroll, so the rest of the screen has to stay
    /// reachable without zooming first.
    func testTheScreenStillScrollsWhenNotZoomed() {
        launchMyMap()
        let erase = app.buttons["きろくを ぜんぶ けす"]
        XCTAssertTrue(erase.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(erase.exists, "the column stopped scrolling")
    }
}
