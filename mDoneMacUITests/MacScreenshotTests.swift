import XCTest

final class MacScreenshotTests: XCTestCase {
    let app = XCUIApplication()

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
        // Wait for login
        let inboxText = app.staticTexts["Inbox"]
        guard inboxText.waitForExistence(timeout: 20) else {
            XCTFail("App did not log in — Inbox not found")
            return
        }
        sleep(5)

        // 1: Inbox (smart list view with grouped sections)
        tapSidebar("Inbox")
        sleep(2)
        saveScreenshot("01-Inbox")

        // 2: Today
        tapSidebar("Today")
        sleep(2)
        saveScreenshot("02-Today")

        // 3: Calendar
        tapSidebar("Calendar")
        sleep(2)
        saveScreenshot("03-Calendar")

        // 4: Project view — tap first project in sidebar
        let generalProject = app.staticTexts["General"]
        if generalProject.waitForExistence(timeout: 5) {
            generalProject.tap()
            sleep(2)
            saveScreenshot("04-Project")
        }

        // 5: Task detail — go back to Inbox and select a task
        tapSidebar("Inbox")
        sleep(2)
        let taskCell = app.staticTexts.element(boundBy: 10)
        if taskCell.waitForExistence(timeout: 5) {
            taskCell.tap()
            sleep(2)
            saveScreenshot("05-TaskDetail")
        }
    }

    private func tapSidebar(_ name: String) {
        let sidebarItem = app.staticTexts[name].firstMatch
        if sidebarItem.waitForExistence(timeout: 5) {
            sidebarItem.tap()
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
