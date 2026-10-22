import XCTest

final class MangaTranslatorUITests: XCTestCase {
    @MainActor
    func testApplicationLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10)
                || app.wait(for: .runningBackground, timeout: 1),
            "The application must remain running after launch"
        )
    }

    @MainActor
    func testCopilotRetryTransitionsToLoading() {
        let app = XCUIApplication()
        app.launchEnvironment["MANGATRANSLATOR_UI_TEST_COPILOT_STATE"] = "failed"
        app.launch()
        app.typeKey(",", modifierFlags: .command)

        let retry = app.buttons["settings.copilot.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        retry.click()
        XCTAssertTrue(app.staticTexts["settings.copilot.loading"].waitForExistence(timeout: 5))
    }
}
