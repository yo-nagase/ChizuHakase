import XCTest

/// The settings sheet, and specifically the voice-answer switch.
///
/// Turning that switch on is the only place the app asks the system for
/// permission, and the reply arrives on a queue the app does not own. Getting
/// the isolation wrong there crashes the process rather than failing softly, so
/// this checks the app is still alive afterwards.
final class SettingsUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func openSettings() {
        app.launchArguments = ["-resetSave"]
        app.launch()
        let gear = app.buttons["せってい"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "no settings button on the title screen")
        gear.tap()
        XCTAssertTrue(app.switches["こうかおん"].waitForExistence(timeout: 5),
                      "settings did not open")
    }

    func testTurningOnVoiceModeDoesNotCrash() throws {
        openSettings()

        let voice = app.switches["こえで こたえる"]
        guard voice.waitForExistence(timeout: 3) else {
            // On-device Japanese recognition is missing here, so the mode is
            // hidden by design (CLAUDE.md §7). Nothing to exercise.
            throw XCTSkip("device cannot do on-device Japanese recognition")
        }

        voice.tap()
        // A system permission alert may be on screen; either way the app must
        // still be running. A crash in the authorisation callback shows up
        // here as .notRunning.
        Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(app.state, .runningForeground,
                       "the app died asking for speech permission")
    }

    /// Sound and speech have no permission behind them and must simply toggle.
    func testSoundAndSpeechToggleCleanly() {
        openSettings()

        for label in ["こうかおん", "よみあげ"] {
            let toggle = app.switches[label]
            XCTAssertTrue(toggle.exists, "\(label) is missing")
            let before = toggle.value as? String

            // The row spans the whole width and its centre is the label, which
            // is not the control. Aim at the switch itself.
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()

            let changed = expectation(for: NSPredicate(format: "value != %@", before ?? ""),
                                      evaluatedWith: toggle)
            XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: 3), .completed,
                           "\(label) did not change")
            XCTAssertEqual(app.state, .runningForeground)
        }
    }
}
