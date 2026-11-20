import XCTest

/// Opt-in, disposable local-server acceptance. Never uses a personal instance.
/// Start/seed docker-compose.dev.yml, then set MDONE_TASK_LINK_UI=1.
@MainActor
final class TaskLinkUITests: XCTestCase {
    private let server = "http://localhost:3456"
    private var token = ""
    private var projectID: Int?
    private var scheme: String {
        ProcessInfo.processInfo.environment["MDONE_LINK_SCHEME"] ?? "mdone"
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        guard ProcessInfo.processInfo.environment["MDONE_TASK_LINK_UI"] == "1" else {
            throw XCTSkip("Opt in with MDONE_TASK_LINK_UI=1 and the local dev Vikunja.")
        }
        let login = try request("POST", "/login", ["username": "devuser", "password": "devpassword"])
        token = try XCTUnwrap(login["token"] as? String)
        let project = try request(
            "POST",
            "/projects",
            ["title": "Disposable task links \(UUID().uuidString.prefix(8))"]
        )
        projectID = try XCTUnwrap(project["id"] as? Int)
    }

    override func tearDownWithError() throws {
        if let projectID {
            _ = try? request("DELETE", "/projects/\(projectID)")
        }
        try super.tearDownWithError()
    }

    private func request(_ method: String, _ path: String, _ body: [String: Any]? = nil) throws -> [String: Any] {
        var request = URLRequest(url: URL(string: server + "/api/v2" + path)!)
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !token.isEmpty {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let finished = expectation(description: "Local fixture response")
        var responseResult: Result<(Data, URLResponse), Error>?
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                responseResult = .failure(error)
            } else if let data, let response {
                responseResult = .success((data, response))
            }
            finished.fulfill()
        }.resume()
        wait(for: [finished], timeout: 20)
        let (data, response) = try XCTUnwrap(responseResult).get()
        let status = try XCTUnwrap(response as? HTTPURLResponse).statusCode
        XCTAssertTrue((200 ..< 300).contains(status), "Local fixture request failed: \(method) \(path), \(status)")
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private func link(_ id: String, server: String? = nil) -> URL {
        var parts = URLComponents(string: "\(scheme)://task/\(id)")!
        parts.queryItems = [.init(name: "server", value: server ?? self.server)]
        return parts.url!
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testColdSignInUncachedBackgroundCompletionAndExistingCreate() throws {
        let app = XCUIApplication(bundleIdentifier: ProcessInfo.processInfo
            .environment["MDONE_APP_ID"] ?? "com.mdone.app.dev")
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let serverField = app.textFields["https://vikunja.example.com"]
        if !serverField.waitForExistence(timeout: 8) {
            if app.buttons["Cancel"].firstMatch.exists {
                app.buttons["Cancel"].firstMatch.tap()
            }
            app.buttons["gearshape.fill"].tap()
            for _ in 0 ..< 4 {
                if app.buttons["Disconnect"].isHittable {
                    break
                }
                app.swipeUp()
            }
            app.buttons["Disconnect"].tap()
            if app.alerts.buttons["Disconnect"].exists {
                app.alerts.buttons["Disconnect"].tap()
            }
        }
        XCTAssertTrue(serverField.waitForExistence(timeout: 10))
        let first = try request("POST", "/projects/\(projectID!)/tasks", ["title": "Cold link synthetic task"])
        let firstID = try XCTUnwrap(first["id"] as? Int)
        app.terminate()
        app.open(link(String(firstID)))
        XCTAssertTrue(app.staticTexts["Sign in to the task's Vikunja server to continue opening it."]
            .waitForExistence(timeout: 10))
        capture(app, "task-link-sign-in")
        serverField.tap()
        serverField.typeText(server)
        app.textFields["Username"].tap()
        app.textFields["Username"].typeText("devuser")
        app.secureTextFields["Password"].tap()
        app.secureTextFields["Password"].typeText("devpassword")
        app.buttons["Connect"].tap()
        let permissions = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Don’t Allow", "Don't Allow"] {
            let deny = permissions.buttons[label]
            if deny.waitForExistence(timeout: 2) {
                deny.tap()
            }
        }
        let title = app.textFields["Task title"]
        XCTAssertTrue(title.waitForExistence(timeout: 20))
        XCTAssertEqual(title.value as? String, "Cold link synthetic task")
        for owner in [app, permissions] where owner.buttons["Not Now"].exists {
            owner.buttons["Not Now"].tap()
        }
        capture(app, "task-link-open")
        let unchanged = try request("GET", "/tasks/\(firstID)")
        XCTAssertEqual(unchanged["done"] as? Bool, false)
        app.buttons["Cancel"].firstMatch.tap()

        // Create only after backgrounding, so it cannot already be in the app's list.
        XCUIDevice.shared.press(.home)
        let uncached = try request(
            "POST",
            "/projects/\(projectID!)/tasks",
            ["title": "Uncached link synthetic task"]
        )
        let secondID = try XCTUnwrap(uncached["id"] as? Int)
        app.open(link(String(secondID)))
        XCTAssertTrue(title.waitForExistence(timeout: 15))
        XCTAssertEqual(title.value as? String, "Uncached link synthetic task")
        capture(app, "task-link-uncached")
        title.tap()
        title.typeText(" edited")
        let editedTitle = try XCTUnwrap(title.value as? String)
        XCTAssertTrue(editedTitle.contains("edited"))
        XCTAssertFalse(app.buttons["Mark Done"].isEnabled)
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        let edited = try request("GET", "/tasks/\(secondID)")
        XCTAssertEqual(edited["title"] as? String, editedTitle)
        app.open(link(String(secondID)))
        XCTAssertTrue(app.buttons["Mark Done"].waitForExistence(timeout: 10))
        app.buttons["Mark Done"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        let completed = try request("GET", "/tasks/\(secondID)")
        XCTAssertEqual(completed["done"] as? Bool, true)

        // Reopening a cached task from a closed app still reads its authoritative state.
        app.terminate()
        app.open(link(String(secondID)))
        XCTAssertTrue(app.buttons["Mark Undone"].waitForExistence(timeout: 15))
        app.buttons["Cancel"].firstMatch.tap()
        app.open(link(String(firstID), server: "https://wrong.example.invalid/base"))
        XCTAssertTrue(app
            .staticTexts["This task belongs to a different Vikunja server. Your connection has not been changed."]
            .waitForExistence(timeout: 10))
        capture(app, "task-link-wrong-server")
        app.buttons["Cancel"].firstMatch.tap()
        app.open(link("nope"))
        XCTAssertTrue(app.staticTexts["This task link is invalid. It must include a server and a positive task ID."]
            .waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()
        _ = try request("DELETE", "/tasks/\(firstID)")
        app.open(link(String(firstID)))
        XCTAssertTrue(app.staticTexts["This task was deleted or your account cannot access it."]
            .waitForExistence(timeout: 10))
        app.buttons["Cancel"].firstMatch.tap()
        try app.open(XCTUnwrap(URL(string: "\(scheme)://create")))
        XCTAssertTrue(app.textFields["Add a task..."].waitForExistence(timeout: 10))
        capture(app, "task-link-create-preserved")
    }
}
