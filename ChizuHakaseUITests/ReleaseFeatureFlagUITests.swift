import XCTest

/// Exercise the shipping UI without DEBUG launch routes or feature overrides.
final class ReleaseFeatureFlagUITests: XCTestCase {
    @MainActor
    func testReleaseHidesPhantomCardsAcrossTheUserFlow() throws {
        #if DEBUG
        throw XCTSkip("Run this verification with the Release configuration")
        #else
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["title-play-japan"].waitForExistence(timeout: 15))

        func verifyHidden(_ screen: String) {
            let forbidden = NSPredicate(format: "label CONTAINS %@ OR label CONTAINS %@", "まぼろし", "幻カード")
            XCTAssertFalse(app.descendants(matching: .any).matching(forbidden).firstMatch.exists, screen)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Release-\(screen)"
            shot.lifetime = .keepAlways
            add(shot)
        }

        for atlas in ["japan", "world"] {
            XCTAssertTrue(app.buttons["title-play-\(atlas)"].waitForExistence(timeout: 10))
            verifyHidden("\(atlas)-home")
            let cards = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "もっている カード")).firstMatch
            XCTAssertTrue(cards.waitForExistence(timeout: 5))
            cards.tap()
            XCTAssertTrue(app.buttons["ぜんぶ"].waitForExistence(timeout: 5))
            verifyHidden("\(atlas)-cards")
            XCTAssertTrue(app.buttons["🥈 シルバー"].exists)
            XCTAssertTrue(app.buttons["🥇 ゴールド"].exists)
            XCTAssertTrue(app.buttons["🌈 にじいろ"].exists)
            app.navigationBars.buttons.firstMatch.tap()
            let turn = app.buttons[atlas == "japan" ? "せかいの ちずへ" : "にほんの ちずへ"]
            XCTAssertTrue(turn.waitForExistence(timeout: 5))
            turn.tap()
        }

        app.buttons["title-play-japan"].tap()
        let stage = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ほっかいどう・とうほく。")).firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 5))
        stage.tap()
        XCTAssertTrue(app.staticTexts["14 もんちゅう 1 もんめ"].waitForExistence(timeout: 10))
        let names = ["北海道", "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県"]
        for question in 1...14 {
            let target = try XCTUnwrap(names.first { app.staticTexts[$0].exists })
            app.buttons[target].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if question < 14 {
                XCTAssertTrue(app.staticTexts["14 もんちゅう \(question + 1) もんめ"].waitForExistence(timeout: 5))
            }
        }
        XCTAssertTrue(app.staticTexts["てん"].waitForExistence(timeout: 8))
        verifyHidden("japan-result")
        app.swipeUp()
        verifyHidden("japan-result-bottom")
        app.terminate()
        #endif
    }
}
