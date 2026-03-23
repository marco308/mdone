import XCTest

final class ScreenshotTests: XCTestCase {
    let app = XCUIApplication()
    var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false

        let env = Self.loadEnvFile()
        guard let serverURL = ProcessInfo.processInfo.environment["MDONE_SERVER_URL"] ?? env["MDONE_SERVER_URL"],
              let token = ProcessInfo.processInfo.environment["MDONE_TOKEN"] ?? env["MDONE_TOKEN"]
        else {
            XCTFail("Set MDONE_SERVER_URL and MDONE_TOKEN in environment or .env.screenshot")
            return
        }

        app.launchArguments += ["-MDONE_SERVER_URL", serverURL]
        app.launchArguments += ["-MDONE_TOKEN", token]
        app.launch()
    }

    private static func loadEnvFile() -> [String: String] {
        // Walk up from the test bundle to find the repo root .env.screenshot
        var dir = URL(fileURLWithPath: #file).deletingLastPathComponent()
        for _ in 0 ..< 5 {
            let envURL = dir.appendingPathComponent(".env.screenshot")
            if let contents = try? String(contentsOf: envURL, encoding: .utf8) {
                var result: [String: String] = [:]
                for line in contents.components(separatedBy: .newlines) {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
                    let parts = trimmed.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    result[String(parts[0])] = String(parts[1])
                }
                return result
            }
            dir = dir.deletingLastPathComponent()
        }
        return [:]
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
