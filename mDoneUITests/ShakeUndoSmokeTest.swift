import XCTest

/// Deep end-to-end tests for issue #82's shake-to-undo.
///
/// Drives the flow via launch defaults (set by the harness before each test):
/// the app auto-toggles the named task and posts a synthetic shake
/// notification (CoreMotion can't fire on the simulator).
///
/// Requires:
/// - `MDONE_SERVER_URL` / `MDONE_TOKEN` already in UserDefaults
/// - Task `ShakeUndoSmokeTest` (id 21) existing on the Vikunja test server
///   with `done: false`
final class ShakeUndoSmokeTest: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testUndoBringsCompletedTaskBackIntoTheActiveList() {
        let app = XCUIApplication()
        app.launch()

        let alert = app.alerts["Undo Mark Complete"]
        XCTAssertTrue(
            alert.waitForExistence(timeout: 15),
            "Shake notification should surface the 'Undo Mark Complete' alert"
        )

        let reopenMessage = alert.staticTexts["Reopen \u{201C}ShakeUndoSmokeTest\u{201D}?"]
        XCTAssertTrue(reopenMessage.exists, "Alert body must read 'Reopen \"…\"?'")

        attachScreenshot(name: "01-alert-visible", app: app)

        alert.buttons["Undo"].tap()

        // Wait for the alert to dismiss so the underlying list is interactive.
        let alertGone = NSPredicate(format: "exists == false")
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: alertGone, object: alert)],
                timeout: 3
            ),
            .completed
        )

        // Screenshot the list state at the moment the alert disappears — this
        // is what the user sees, and proves the optimistic local update fired.
        attachScreenshot(name: "02-immediately-after-undo", app: app)

        // The restored task lives in the "No Date" section, which is below
        // the fold in the inbox. Scroll into view, then assert.
        let restoredCheckbox = app
            .descendants(matching: .any)["Mark ShakeUndoSmokeTest as complete"]
        var swipes = 0
        while !restoredCheckbox.isHittable, swipes < 6 {
            app.swipeUp()
            swipes += 1
        }
        attachScreenshot(name: "03-after-scrolling", app: app)
        XCTAssertTrue(
            restoredCheckbox.exists,
            "Undo must restore the task to the active list"
        )
    }

    private func attachScreenshot(name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
