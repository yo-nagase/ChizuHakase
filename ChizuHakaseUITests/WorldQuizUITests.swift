import XCTest

/// The world atlas played through the real UI the way QuizFlowUITests plays
/// Japan, reached by the `-atlas world` debug route (the direct entrance kept
/// for tests and screenshots; the child's road is the title's second page).
///
/// Alongside the quiz itself, this suite smokes the three screens P6 Task 3
/// threaded the atlas through — result, my-map, card book — and pins the trap
/// that motivated the threading: seven card IDs collide as strings across the
/// books (world "12-1" is アルジェリア's flag, japan's is 千葉の らっかせい),
/// so a japan card name showing up on a world screen means the wrong catalog
/// answered.
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

    /// A whole world stage played to the result screen (引き継ぎ 6 — the japan
    /// fixation in ResultView stayed green precisely because no test ever got
    /// this far). きたアフリカ (stage 7) is chosen on purpose: it contains
    /// アルジェリア, ISO code 12, whose flag card ID "12-1" collides with
    /// japan's 千葉 card — if the result screen resolved cards through japan's
    /// catalog, らっかせい would appear where こっき belongs.
    func testPlayingAWorldStageThroughReachesTheResultScreen() throws {
        app.launchArguments = ["-resetSave", "-atlas", "world", "-startAt", "quiz:7"]
        app.launch()
        XCTAssertTrue(app.staticTexts["12 もんちゅう 1 もんめ"].waitForExistence(timeout: 10),
                      "the world quiz never appeared")
        XCTAssertTrue(app.staticTexts["きたアフリカ"].exists,
                      "quiz:7 did not resolve against the world's stages")

        let questions = 12
        for question in 1...questions {
            guard let target = Self.northAfricaNames.first(where: {
                app.staticTexts[$0].exists
            }) else {
                XCTFail("no country question on screen at \(question)/\(questions)")
                return
            }
            let element = app.buttons[target]
            XCTAssertTrue(element.waitForExistence(timeout: 5),
                          "no accessibility element for \(target)")
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            if question < questions {
                let next = app.staticTexts["12 もんちゅう \(question + 1) もんめ"]
                XCTAssertTrue(next.waitForExistence(timeout: 8),
                              "did not advance past question \(question)")
            }
        }

        XCTAssertTrue(app.staticTexts["てん"].waitForExistence(timeout: 6),
                      "did not reach the world result screen")
        // 12 × 100 plus 20 for each step of an unbroken combo.
        XCTAssertTrue(app.staticTexts["2520"].exists,
                      "a perfect run of 12 should total 2520")
        XCTAssertTrue(app.otherElements["ほし 3 こ"].exists, "a perfect run earns 3 stars")

        // The cards this run won are the world's flags…
        XCTAssertTrue(chip(named: "こっき").waitForExistence(timeout: 3),
                      "no flag card in the world result's card panel")
        // …and never japan's colliding card. アルジェリア (12) was answered
        // twice above, so its "12-1" was certainly drawn — the leak this
        // guards against is exactly that ID resolving to 千葉の らっかせい.
        XCTAssertFalse(anythingNamed("らっかせい"),
                       "japan's 12-1 leaked into the world result screen")
    }

    /// The world my-map: the world's own countries, the world's own tally.
    func testWorldMyMapShowsTheWorldBook() {
        app.launchArguments = ["-resetSave", "-atlas", "world", "-startAt", "myMap"]
        app.launch()
        // A fresh save has learned none of the 167 countries.
        XCTAssertTrue(app.staticTexts["0 / 167"].waitForExistence(timeout: 10),
                      "the learned tally is not counting the world's countries")
        XCTAssertTrue(app.buttons["オーストラリア"].waitForExistence(timeout: 5),
                      "no tappable country on the world my-map")
        XCTAssertFalse(app.buttons["北海道"].exists,
                       "japan's prefectures leaked onto the world my-map")
    }

    /// The eraser under the world map erases the whole app, and the second
    /// confirmation must say so in both books' names before anything goes.
    func testTheEraseConfirmationNamesBothBooks() {
        app.launchArguments = ["-resetSave", "-atlas", "world", "-startAt", "myMap"]
        app.launch()
        let erase = app.buttons["きろくを ぜんぶ けす"]
        XCTAssertTrue(erase.waitForExistence(timeout: 10))
        erase.tap()
        XCTAssertTrue(app.staticTexts["ほんとうに けしても いい?"].waitForExistence(timeout: 3))
        app.buttons["つぎへ"].tap()
        XCTAssertTrue(app.staticTexts["にほんも せかいも けすと もどせないよ。いい?"]
                        .waitForExistence(timeout: 3),
                      "the second confirmation does not name both books")
        // Walk back out — this test is about the words, not the wipe.
        app.buttons["やめる"].tap()
    }

    /// The world card book: flag cards from the world's catalog, and only the
    /// categories the world actually deals (こっき — no japan chips).
    func testWorldCardBookShowsFlagsFromTheWorldBook() {
        app.launchArguments = ["-resetSave", "-atlas", "world", "-grantCards",
                               "-startAt", "cardBook"]
        app.launch()
        XCTAssertTrue(app.buttons["🚩 こっき"].waitForExistence(timeout: 10),
                      "the world book has no flag category chip")
        XCTAssertFalse(app.buttons["🍙 たべもの"].exists,
                       "a japan-only category chip showed in the world book")
        // -grantCards deals three world cards; the denominator is the world's.
        XCTAssertTrue(app.staticTexts["3 / 167"].exists,
                      "the owned count is not reading the world's slice")

        // Open the first owned flag — アルジェリア's, the colliding "12-1".
        // Its description proves which catalog answered: japan's 12-1 talks
        // about peanuts, the world's about アルジェリア's flag.
        let card = chip(named: "こっき")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no owned flag card in the book")
        card.tap()
        XCTAssertTrue(app.buttons["とじる"].waitForExistence(timeout: 3),
                      "tapping a flag card did not open it")
        XCTAssertTrue(app.staticTexts["あるじぇりあの こっきだよ"].exists,
                      "the opened card is not the world's 12-1")
        XCTAssertFalse(anythingNamed("らっかせい"),
                       "japan's 12-1 leaked into the world card book")
    }

    // MARK: - Helpers

    /// A card chip, matched on the leading name the way ResultUITests does —
    /// the label goes on to carry stars and tier.
    private func chip(named name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    /// Whether any element on screen mentions `name` — chips are buttons and
    /// captions are static texts, and a leak through either is a leak.
    private func anythingNamed(_ name: String) -> Bool {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name))
            .firstMatch.exists
            || app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", name))
                .firstMatch.exists
    }

    /// The six written names of ひがしアジア, as WorldShapes.json carries them.
    private static let eastAsiaNames = [
        "中華人民共和国", "台湾", "日本", "北朝鮮", "大韓民国", "モンゴル国",
    ]

    /// きたアフリカ's six, same written form as the map's accessibility labels.
    private static let northAfricaNames = [
        "アルジェリア", "リビア", "モロッコ", "スーダン", "チュニジア", "エジプト",
    ]
}
