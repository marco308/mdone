import XCTest
@testable import mDone

/// Duplicating a task (#22): the endpoint, and the AppState flow that reads
/// both tasks back so the copy shows its labels and the original its new
/// `copiedto` relation.
final class TaskDuplicateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    /// Task JSON in the shape Vikunja 2.4.0 returns.
    private static func taskJSON(
        id: Int64,
        title: String,
        labels: String = "null",
        relatedTasks: String = "null"
    ) -> String {
        """
        {"id": \(id), "title": "\(title)", "done": false, "priority": 3, "project_id": 9,
         "due_date": "2026-10-24T09:00:00Z", "labels": \(labels), "assignees": null, "reactions": null,
         "attachments": null, "identifier": "#\(id)", "index": \(id), "percent_done": 0, "is_favorite": false,
         "created": "2026-11-21T21:18:56Z", "updated": "2026-11-21T21:18:56Z", "created_by": null,
         "related_tasks": \(relatedTasks)}
        """
    }

    private static let urgentLabel = """
    [{"id": 4, "title": "urgent", "hex_color": "e8445a", "created": "2026-10-23T05:42:07Z",
      "updated": "2026-10-23T05:42:07Z"}]
    """

    @MainActor
    private func makeMockedAppState() async -> AppState {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(taskService: TaskService(apiClient: client))
    }

    func testDuplicateEndpoint() {
        let endpoint = Endpoint.duplicateTask(id: 12)
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/tasks/12/duplicate"))
        XCTAssertEqual(endpoint.method, .POST)
    }

    @MainActor
    func testDuplicateAddsCopyWithLabelsAndRelatesOriginal() async throws {
        let appState = await makeMockedAppState()
        appState.tasks = [VTask(id: 12, title: "Write report", done: false, priority: 3, projectId: 9)]

        let copiedFrom = "{\"copiedfrom\": [\(Self.taskJSON(id: 12, title: "Write report"))]}"
        // The duplicate answer, as the server sends it: no labels on the copy.
        let duplicatedTask = Self.taskJSON(id: 182, title: "Write report", relatedTasks: copiedFrom)
        let duplicateResponse = try XCTUnwrap("{\"duplicated_task\": \(duplicatedTask)}".data(using: .utf8))
        let copyResponse = try XCTUnwrap(Self.taskJSON(
            id: 182, title: "Write report", labels: Self.urgentLabel, relatedTasks: copiedFrom
        ).data(using: .utf8))
        let originalResponse = try XCTUnwrap(Self.taskJSON(
            id: 12, title: "Write report",
            relatedTasks: "{\"copiedto\": [\(Self.taskJSON(id: 182, title: "Write report"))]}"
        ).data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod, path) {
            case ("POST", VikunjaAPI.path("/tasks/12/duplicate")):
                return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), duplicateResponse)
            case ("GET", VikunjaAPI.path("/tasks/182")):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), copyResponse)
            case ("GET", VikunjaAPI.path("/tasks/12")):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), originalResponse)
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "?") \(path)")
                return (MockURLProtocol.makeResponse(statusCode: 404, url: request.url), Data())
            }
        }

        let copy = await appState.duplicateTask(try XCTUnwrap(appState.tasks.first))

        XCTAssertEqual(copy?.id, 182)
        XCTAssertEqual(copy?.labels?.map(\.title), ["urgent"])
        XCTAssertEqual(appState.tasks.map(\.id).sorted(), [12, 182])
        XCTAssertEqual(
            appState.tasks.first { $0.id == 12 }?.relatedTasks?["copiedto"]?.map(\.id),
            [182]
        )
        XCTAssertNil(appState.errorMessage)

        let duplicateRequest = try XCTUnwrap(MockURLProtocol.capturedRequests.first {
            $0.url?.path == VikunjaAPI.path("/tasks/12/duplicate")
        })
        let body = try XCTUnwrap(MockURLProtocol.bodyData(from: duplicateRequest))
        XCTAssertEqual(String(data: body, encoding: .utf8), "{}")
    }

    @MainActor
    func testDuplicateFailureLeavesTasksAlone() async throws {
        let appState = await makeMockedAppState()
        appState.tasks = [VTask(id: 12, title: "Write report", done: false, priority: 3, projectId: 9)]

        let problem = try XCTUnwrap("""
        {"title": "Forbidden", "status": 403, "detail": "You don't have the permission to do this.", "code": 0}
        """.data(using: .utf8))
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(
                    statusCode: 403, url: request.url,
                    headers: ["Content-Type": "application/problem+json"]
                ),
                problem
            )
        }

        let copy = await appState.duplicateTask(try XCTUnwrap(appState.tasks.first))

        XCTAssertNil(copy)
        XCTAssertEqual(appState.tasks.map(\.id), [12])
        XCTAssertNotNil(appState.errorMessage)
    }
}
