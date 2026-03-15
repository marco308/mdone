import XCTest

final class ScreenshotTests: XCTestCase {
    let app = XCUIApplication()
    var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-MDONE_SERVER_URL", "https://vikunja-test.marcuslab.uk"]
        app.launchArguments += ["-MDONE_TOKEN", "tk_911c079025eb3bf9e7f3008668ad0c7bbc091fc9"]
        app.launch()
    }

    func testCaptureScreenshots() throws {
        // Wait for login — look for "Inbox" anywhere (title or tab)
        let inboxText = app.staticTexts["Inbox"]
        guard inboxText.waitForExistence(timeout: 20) else {
            XCTFail("App did not log in — Inbox not found")
            return
        }
        sleep(5)

        // Dismiss any system notification banners
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.otherElements["NotificationShortLookView"]
        if banner.waitForExistence(timeout: 2) {
            banner.swipeUp()
            sleep(1)
        }

        // 1: Inbox
        saveScreenshot("01-Inbox")

        // 2: Projects — tap tab (works for both bottom bar and top floating bar)
        tapTab("Projects")
        sleep(3)
        saveScreenshot("02-Projects")

        // 3: Calendar
        tapTab("Calendar")
        sleep(3)
        saveScreenshot("03-Calendar")

        // 4: Task detail — go back to Inbox and open a task
        tapTab("Inbox")
        sleep(2)
        let task = app.staticTexts["Finalize Q1 report"]
        if task.waitForExistence(timeout: 5) {
            task.tap()
            sleep(2)
            saveScreenshot("04-TaskDetail")
        }
    }

    private func tapTab(_ name: String) {
        // Try bottom tab bar first (iPhone)
        let tabButton = app.tabBars.buttons[name]
        if tabButton.exists {
            tabButton.tap()
            return
        }
        // iPad floating tab bar — use firstMatch to avoid duplicate element errors
        let button = app.buttons.matching(identifier: name).firstMatch
        if button.waitForExistence(timeout: 3) {
            button.tap()
        }
    }

    private func saveScreenshot(_ name: String) {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
