import XCTest

/// The world atlas's debug route (`-atlas world -startAt quiz:N`), played
/// through the real UI the way QuizFlowUITests plays Japan.
///
/// There is deliberately no user-visible way into the world yet (design doc
/// §2 — the branch belongs to the title's two pages, which is P6), so this
/// launch argument is the only road, and this test is what keeps it passable:
/// the stage resolves against the world's stages, the tap reaches the right
/// country through the projection, and the score moves.
final class WorldQuizUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    /// ひがしアジア (world stage 15) asks 6 countries twice: 12 questions.
    func testTappingTheAskedCountryScores() throws {
        app.launchArguments = ["-resetSave", "-atlas", "world", "-startAt", "quiz:15"]
        app.launch()
        XCTAssertTrue(app.staticTexts["12 もんちゅう 1 もんめ"].waitForExistence(timeout: 10),
                      "the world quiz never appeared")
        XCTAssertTrue(app.staticTexts["ひがしアジア"].exists,
                      "quiz:15 did not resolve against the world's stages")

        // The asked country, read off the question card's secondary line —
        // the same written form the map's accessibility labels carry.
        let target = try XCTUnwrap(
            Self.eastAsiaNames.first { app.staticTexts[$0].exists },
            "no country question on screen")
        XCTAssertTrue(app.staticTexts["0"].exists, "score should start at zero")

        // Tapping the element's centre lands on the country's centroid (the
        // pipeline guarantees it is inside the shape), through the map's own
        // single tap gesture — same mechanics as the Japan flow test.
        let element = app.buttons[target]
        XCTAssertTrue(element.waitForExistence(timeout: 5),
                      "no accessibility element for \(target)")
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // 100 for a first-try answer — the rules are shared, only the data
        // changed books (CLAUDE.md §5).
        XCTAssertTrue(app.staticTexts["100"].waitForExistence(timeout: 3),
                      "a correct first tap on \(target) should score 100")
    }

    /// The six written names of ひがしアジア, as WorldShapes.json carries them.
    private static let eastAsiaNames = [
        "中華人民共和国", "台湾", "日本", "北朝鮮", "大韓民国", "モンゴル国",
    ]
}
