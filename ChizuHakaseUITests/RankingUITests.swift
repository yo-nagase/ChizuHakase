import XCTest

final class RankingUITests: XCTestCase {
    @MainActor
    func testCompletedQuizIsSavedAndVisibleAfterRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-resetSave", "-startAt", "quiz:0"]
        app.launch()
        XCTAssertTrue(app.staticTexts["14 もんちゅう 1 もんめ"].waitForExistence(timeout: 15))
        let names = ["北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県"]
        for question in 1...14 {
            let target = try XCTUnwrap(names.first { app.staticTexts[$0].exists })
            app.buttons[target].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if question < 14 {
                XCTAssertTrue(app.staticTexts["14 もんちゅう \(question + 1) もんめ"].waitForExistence(timeout: 5))
            }
        }
        XCTAssertTrue(app.staticTexts["いっかいで せいかい：14 / 14 もん"].waitForExistence(timeout: 8))
        let open = app.buttons["openRankings"]
        if !open.isHittable { app.swipeUp() }
        open.tap()
        let record = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "1.  14 / 14 もん")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-startAt", "quiz:0"]
        app.launch()
        XCTAssertTrue(app.staticTexts["14 もんちゅう 1 もんめ"].waitForExistence(timeout: 15))
        // Returning to the picker is enough to verify the independent history file survived launch.
        app.buttons["やめる"].firstMatch.tap()
        XCTAssertTrue(app.buttons["openRankings"].waitForExistence(timeout: 5))
        app.buttons["openRankings"].tap()
        // The picker defaults to the national challenge; choose the saved region.
        app.buttons["rankingStagePicker"].tap()
        app.buttons["ほっかいどう・とうほく"].tap()
        XCTAssertTrue(record.waitForExistence(timeout: 5))
    }

    @MainActor
    func testGuestCanOpenPersonalAndGlobalRankingsForBothAtlases() {
        continueAfterFailure = false
        for atlas in ["japan", "world"] {
            let app = XCUIApplication()
            app.launchArguments = ["-resetSave", "-atlas", atlas, "-startAt", "stageSelect"]
            app.launch()
            let link = app.buttons["openRankings"]
            XCTAssertTrue(link.waitForExistence(timeout: 15))
            link.tap()
            XCTAssertTrue(app.staticTexts["あそぶと ここに きろくが のこるよ。"].waitForExistence(timeout: 5))
            app.buttons["みんな"].tap()
            XCTAssertTrue(app.buttons["Game Centerで さんかする"].waitForExistence(timeout: 5))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "\(atlas)-ranking-guest"
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
