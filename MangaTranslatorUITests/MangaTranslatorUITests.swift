import XCTest

final class MangaTranslatorUITests: XCTestCase {
    @MainActor
    func testApplicationLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
