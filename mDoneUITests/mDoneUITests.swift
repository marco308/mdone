import XCTest

final class mDoneUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunchesToSetupScreen() {
        let app = XCUIApplication()
        app.launch()

        // On first launch, should show the server setup screen
        XCTAssertTrue(app.staticTexts["mDone"].exists || app.textFields["https://vikunja.example.com"].exists)
    }
}
