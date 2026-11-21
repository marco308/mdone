import XCTest
@testable import mDone

/// Task comments (#2): the endpoints, reading every page, writing the
/// description markup as HTML, and the per-task counts behind row badges.
final class TaskCommentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private static func commentJSON(id: Int64, html: String, created: String = "2026-11-21T21:28:17Z") -> String {
        """
        {"id": \(id), "comment": "\(html)", "reactions": null,
         "author": {"id": 4, "name": "", "username": "devuser", "created": "2026-10-23T05:42:07Z",
                    "updated": "2026-10-23T05:42:07Z"},
         "created": "\(created)", "updated": "\(created)"}
        """
    }

    @MainActor
    private func makeMockedAppState() async -> AppState {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(
            taskService: TaskService(apiClient: client),
            commentService: CommentService(apiClient: client)
        )
    }

    func testCommentEndpoints() {
        XCTAssertEqual(Endpoint.taskComments(taskId: 12).path, VikunjaAPI.path("/tasks/12/comments"))
        XCTAssertEqual(Endpoint.taskComments(taskId: 12).method, .GET)
        XCTAssertEqual(Endpoint.createTaskComment(taskId: 12).method, .POST)
        XCTAssertEqual(
            Endpoint.updateTaskComment(taskId: 12, commentId: 3).path,
            VikunjaAPI.path("/tasks/12/comments/3")
        )
        XCTAssertEqual(Endpoint.updateTaskComment(taskId: 12, commentId: 3).method, .PATCH)
        XCTAssertEqual(Endpoint.deleteTaskComment(taskId: 12, commentId: 3).method, .DELETE)
    }

    func testTaskListsAskForCommentCounts() {
        let expand = URLQueryItem(name: "expand", value: "comment_count")
        XCTAssertTrue(Endpoint.allTasks().queryItems?.contains(expand) == true)
        XCTAssertTrue(Endpoint.projectTasks(projectId: 1, viewId: 2).queryItems?.contains(expand) == true)
    }

    func testEditedOnlyWhenUpdatedASecondOrMoreLater() {
        let created = Date(timeIntervalSince1970: 1_000)
        var comment = TaskComment(id: 1, comment: "<p>Hi</p>", created: created, updated: created.addingTimeInterval(0.00001))
        XCTAssertFalse(comment.isEdited)
        comment.updated = created.addingTimeInterval(60)
        XCTAssertTrue(comment.isEdited)
    }

    @MainActor
    func testLoadReadsEveryPageOldestFirstAndRecordsTheCount() async throws {
        let appState = await makeMockedAppState()
        let first = MockURLProtocol.page(
            "[\(Self.commentJSON(id: 2, html: "<p>Second</p>", created: "2026-11-21T22:00:00Z"))]",
            totalPages: 2, page: 1
        )
        let second = MockURLProtocol.page(
            "[\(Self.commentJSON(id: 1, html: "<p>First</p>", created: "2026-11-21T21:00:00Z"))]",
            totalPages: 2, page: 2
        )
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, VikunjaAPI.path("/tasks/12/comments"))
            let page = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "page" }?.value
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), page == "2" ? second : first)
        }

        let comments = await appState.loadComments(taskId: 12)

        XCTAssertEqual(comments?.map(\.id), [1, 2])
        XCTAssertEqual(comments?.first?.author?.displayName, "devuser")
        XCTAssertEqual(appState.commentCount(for: 12), 2)
    }

    @MainActor
    func testLoadFailureReturnsNil() async {
        let appState = await makeMockedAppState()
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 500, url: request.url), Data())
        }

        let comments = await appState.loadComments(taskId: 12)

        XCTAssertNil(comments)
    }

    @MainActor
    func testAddingPostsMarkupAsHTMLAndCountsIt() async throws {
        let appState = await makeMockedAppState()
        let created = Data(Self.commentJSON(id: 9, html: "<p>Done <strong>today</strong></p>").utf8)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, VikunjaAPI.path("/tasks/12/comments"))
            return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), created)
        }

        let comment = await appState.addComment(taskId: 12, text: "  Done **today**\n")

        XCTAssertEqual(comment?.id, 9)
        XCTAssertEqual(appState.commentCount(for: 12), 1)
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let body = try XCTUnwrap(MockURLProtocol.bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["comment"] as? String, DescriptionMarkup.html(fromEditableText: "Done **today**"))
        XCTAssertEqual(json.keys.sorted(), ["comment"])
    }

    @MainActor
    func testBlankCommentSendsNothing() async {
        let appState = await makeMockedAppState()
        MockURLProtocol.requestHandler = { request in
            XCTFail("Unexpected request: \(request.url?.path ?? "")")
            return (MockURLProtocol.makeResponse(statusCode: 500, url: request.url), Data())
        }

        let comment = await appState.addComment(taskId: 12, text: " \n ")

        XCTAssertNil(comment)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    @MainActor
    func testEditingRawHTMLSendsItUnchanged() async throws {
        let appState = await makeMockedAppState()
        let html = "<table><tr><td>x</td></tr></table>"
        let updated = Data(Self.commentJSON(id: 3, html: html).utf8)
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, VikunjaAPI.path("/tasks/12/comments/3"))
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), updated)
        }

        let comment = await appState.editComment(taskId: 12, commentId: 3, text: html, isHTML: true)

        XCTAssertEqual(comment?.comment, html)
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let body = try XCTUnwrap(MockURLProtocol.bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["comment"] as? String, html)
    }

    @MainActor
    func testDeletingLowersTheCount() async throws {
        let appState = await makeMockedAppState()
        let page = MockURLProtocol.page(
            "[\(Self.commentJSON(id: 1, html: "<p>a</p>")), \(Self.commentJSON(id: 2, html: "<p>b</p>"))]"
        )
        MockURLProtocol.requestHandler = { request in
            if request.httpMethod == "DELETE" {
                XCTAssertEqual(request.url?.path, VikunjaAPI.path("/tasks/12/comments/2"))
                return (MockURLProtocol.makeResponse(statusCode: 204, url: request.url), Data())
            }
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), page)
        }
        _ = await appState.loadComments(taskId: 12)

        let deleted = await appState.deleteComment(taskId: 12, commentId: 2)

        XCTAssertTrue(deleted)
        XCTAssertEqual(appState.commentCount(for: 12), 1)
    }

    @MainActor
    func testCountsSurviveATaskReadWithoutOne() async throws {
        let appState = await makeMockedAppState()
        var listed = VTask(id: 12, title: "Task", done: false, priority: 0, projectId: 1)
        listed.commentCount = 3
        let task = Data("""
        {"id": 12, "title": "Task", "done": false, "priority": 0, "project_id": 1,
         "due_date": "0001-01-01T00:00:00Z", "labels": null, "assignees": null,
         "created": "2026-11-21T21:18:56Z", "updated": "2026-11-21T21:18:56Z", "related_tasks": null}
        """.utf8)
        let fullPage = MockURLProtocol.page("""
        [{"id": 12, "title": "Task", "done": false, "priority": 0, "project_id": 1,
          "due_date": "0001-01-01T00:00:00Z", "labels": null, "assignees": null, "comment_count": 3,
          "created": "2026-11-21T21:18:56Z", "updated": "2026-11-21T21:18:56Z", "related_tasks": null}]
        """)
        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            if path == VikunjaAPI.path("/tasks") {
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), fullPage)
            }
            if path == VikunjaAPI.path("/tasks/12") {
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), task)
            }
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), MockURLProtocol.page("[]"))
        }

        await appState.refreshAll()
        XCTAssertEqual(appState.commentCount(for: 12), 3)

        // A progress change answers with the task alone, with no count in it.
        await appState.setProgress(listed, percent: 0.5)
        XCTAssertEqual(appState.commentCount(for: 12), 3)
    }
}
