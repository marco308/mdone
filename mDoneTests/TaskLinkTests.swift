import XCTest
@testable import mDone

/// `TaskLink` is what an agent follows to find a shared task, so the shape of
/// the URL matters more than it looks.
final class TaskLinkTests: XCTestCase {
    func testBuildsTheWebAppTaskPath() {
        XCTAssertEqual(
            TaskLink.url(forTaskId: 42, serverURL: "https://vikunja.example.com")?.absoluteString,
            "https://vikunja.example.com/tasks/42"
        )
    }

    func testTrailingSlashDoesNotDoubleUp() {
        XCTAssertEqual(
            TaskLink.url(forTaskId: 7, serverURL: "https://vikunja.example.com/")?.absoluteString,
            "https://vikunja.example.com/tasks/7"
        )
    }

    func testKeepsASubpathInstall() {
        XCTAssertEqual(
            TaskLink.url(forTaskId: 7, serverURL: "https://example.com/vikunja")?.absoluteString,
            "https://example.com/vikunja/tasks/7"
        )
    }

    func testKeepsPortAndPlainHTTP() {
        XCTAssertEqual(
            TaskLink.url(forTaskId: 1, serverURL: "http://localhost:3456")?.absoluteString,
            "http://localhost:3456/tasks/1"
        )
    }

    func testMissingOrUnusableServerGivesNoLink() {
        XCTAssertNil(TaskLink.url(forTaskId: 1, serverURL: nil))
        XCTAssertNil(TaskLink.url(forTaskId: 1, serverURL: ""))
        XCTAssertNil(TaskLink.url(forTaskId: 1, serverURL: "not a url"))
    }

    // MARK: - Signed-in server

    /// The task overload is what the share buttons call, so check it reads the
    /// stored server URL and goes quiet once there is none.
    func testTaskLinkUsesTheSignedInServer() {
        let auth = AuthService.shared
        let saved = auth.getServerURL()
        defer {
            if let saved {
                auth.saveServerURL(saved)
            } else {
                auth.clearServerURL()
            }
        }
        let task = VTask(id: 2268, title: "Share me", done: false, priority: 0, projectId: 1)

        auth.saveServerURL("https://vikunja.example.com")
        XCTAssertEqual(TaskLink.url(for: task)?.absoluteString, "https://vikunja.example.com/tasks/2268")

        auth.clearServerURL()
        XCTAssertNil(TaskLink.url(for: task))
    }
}
