import XCTest

/// The iPad has to work sideways.
///
/// Not a preference: an iPad app that declares fewer than four orientations
/// fails App Store validation, and `UIRequiresFullScreen` — the key that used
/// to buy an exemption — is deprecated in iPadOS 26. Landscape is a state the
/// layout must survive, so it needs a test that plays in it rather than a
/// promise that nobody rotates.
///
/// Skipped on iPhone, which stays portrait-only and cannot rotate.
final class LandscapeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
    }

    private func launchSideways(at route: String) throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "iPhone is portrait-only by design")
        app.launchArguments = ["-resetSave", "-startAt", route]
        app.launch()
        // Rotated after launch, not before: set on a device with no app in the
        // foreground the orientation does not stick, and the screenshots came
        // back portrait-shaped while the assertions still passed.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }

    /// Landscape means wider than tall. Checked because the rotation silently
    /// failing is exactly the way this suite would go on passing while testing
    /// nothing.
    private func assertIsSideways() {
        let frame = app.windows.firstMatch.frame
        XCTAssertGreaterThan(frame.width, frame.height,
                             "the app did not rotate; this test proved nothing")
    }

    /// Attached rather than asserted: no assertion can tell whether a layout
    /// looks right, and this is the only way to see the wide one at all.
    private func record(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    /// The whole country is the stage that needs the room most, and the one
    /// where a squeezed map makes Kagawa untappable.
    func testTheNationalQuizIsPlayableSideways() throws {
        try launchSideways(at: "quiz:6")

        XCTAssertTrue(app.staticTexts["は どこかな?"].waitForExistence(timeout: 10),
                      "the quiz did not lay out in landscape")
        assertIsSideways()

        // A prefecture has to be reachable, not merely present: a map squeezed
        // out of the safe area still reports frames.
        let kagawa = app.buttons["香川県"]
        XCTAssertTrue(kagawa.waitForExistence(timeout: 5), "no 香川県 on the sideways map")
        XCTAssertTrue(kagawa.isHittable, "香川県 is on screen but cannot be touched")

        record("quiz-landscape")
    }

    /// The screens with no interaction to assert on, walked for their
    /// screenshots: layout regressions here are visual, and the attachments
    /// are how a wide layout gets reviewed at all.
    func testTheRemainingScreensLayOutSideways() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad,
                          "iPhone is portrait-only by design")

        app.launchArguments = ["-resetSave", "-grantCards"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["あそぶ"].waitForExistence(timeout: 10))
        assertIsSideways()
        record("title-landscape")

        let book = XCUIApplication()
        book.launchArguments = ["-resetSave", "-grantCards", "-startAt", "cardBook"]
        book.launch()
        XCTAssertTrue(book.staticTexts["ほっかいどう"].waitForExistence(timeout: 10))
        record("book-landscape")

        let result = XCUIApplication()
        result.launchArguments = ["-resetSave", "-startAt", "result"]
        result.launch()
        XCTAssertTrue(result.buttons["もういちど"].waitForExistence(timeout: 10))
        record("result-landscape")
    }

    func testTheTitleScreenLaysOutSideways() throws {
        try launchSideways(at: "stageSelect")

        XCTAssertTrue(app.buttons["ほっかいどう・とうほく"].waitForExistence(timeout: 10)
                      || app.staticTexts["ほっかいどう・とうほく"].waitForExistence(timeout: 5),
                      "the stage shelf did not lay out in landscape")
        assertIsSideways()

        // The column holds its portrait width instead of stretching: a stage
        // card as wide as the sideways screen is a ribbon with a thumbnail
        // lost at one end of it (`pageColumn()`).
        let sheet = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "ほっかいどう・とうほく")).firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(sheet.frame.width, 700,
                                 "the stage card stretched across the sideways screen")

        record("stages-landscape")
    }
}
