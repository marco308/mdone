import XCTest
@testable import mDone

/// Covers the Kanban board feature (#55): bucket decoding, the kanban-view
/// helper on `Project`, the bucket endpoints, and the service + `AppState`
/// move-to-bucket path.
final class KanbanTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func snakeCaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    // MARK: - Bucket model

    func testBucketDecodesWithEmbeddedTasks() throws {
        let json = """
        {
            "id": 5,
            "title": "In Progress",
            "project_view_id": 9,
            "limit": 3,
            "count": 2,
            "position": 2.0,
            "tasks": [
                {"id": 11, "title": "A", "done": false, "priority": 0, "project_id": 1},
                {"id": 12, "title": "B", "done": true, "priority": 2, "project_id": 1}
            ]
        }
        """.data(using: .utf8)!

        let bucket = try snakeCaseDecoder().decode(Bucket.self, from: json)
        XCTAssertEqual(bucket.id, 5)
        XCTAssertEqual(bucket.title, "In Progress")
        XCTAssertEqual(bucket.projectViewId, 9)
        XCTAssertEqual(bucket.limit, 3)
        XCTAssertEqual(bucket.tasks?.count, 2)
        // activeTasks hides the done task.
        XCTAssertEqual(bucket.activeTasks.map(\.id), [11])
    }

    func testBucketLimitHelpers() {
        let unlimited = Bucket(id: 1, title: "Todo", limit: 0)
        XCTAssertFalse(unlimited.hasLimit)
        XCTAssertFalse(unlimited.isOverLimit)

        var limited = Bucket(id: 2, title: "Doing", limit: 2)
        XCTAssertTrue(limited.hasLimit)
        XCTAssertFalse(limited.isOverLimit)

        limited.tasks = [
            VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1),
            VTask(id: 2, title: "y", done: false, priority: 0, projectId: 1)
        ]
        XCTAssertTrue(limited.isOverLimit)
    }

    func testTaskBucketRequestEncodesSnakeCase() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(TaskBucketRequest(taskId: 42))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["task_id"] as? Int, 42)
    }

    // MARK: - Project.kanbanViewId

    func testKanbanViewIdFindsKanbanView() {
        let project = Project(
            id: 1,
            title: "P",
            views: [
                ProjectView(id: 100, title: "List", projectId: 1, viewKind: "list"),
                ProjectView(id: 200, title: "Kanban", projectId: 1, viewKind: "kanban")
            ]
        )
        XCTAssertEqual(project.kanbanViewId, 200)
        XCTAssertEqual(project.listViewId, 100)
    }

    func testKanbanViewIdNilWhenAbsent() {
        let project = Project(
            id: 1,
            title: "P",
            views: [ProjectView(id: 100, title: "List", projectId: 1, viewKind: "list")]
        )
        XCTAssertNil(project.kanbanViewId)
    }

    // MARK: - Endpoints

    func testBucketEndpointPaths() {
        let read = Endpoint.projectBuckets(projectId: 7, viewId: 3)
        XCTAssertEqual(read.path, "/api/v1/projects/7/views/3/buckets")
        XCTAssertEqual(read.method, .GET)

        let move = Endpoint.moveTaskToBucket(projectId: 7, viewId: 3, bucketId: 9)
        XCTAssertEqual(move.path, "/api/v1/projects/7/views/3/buckets/9/tasks")
        XCTAssertEqual(move.method, .POST)
    }

    // MARK: - ProjectService.fetchBuckets

    func testFetchBucketsReturnsBuckets() async throws {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let service = ProjectService(apiClient: client)

        let bucketsJSON = """
        [
            {"id": 1, "title": "Backlog", "project_view_id": 3, "position": 1.0, "tasks": []},
            {"id": 2, "title": "Done", "project_view_id": 3, "position": 2.0, "tasks": [
                {"id": 50, "title": "Ship it", "done": false, "priority": 0, "project_id": 7}
            ]}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/projects/7/views/3/buckets")
            XCTAssertEqual(request.httpMethod, "GET")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), bucketsJSON)
        }

        let buckets = try await service.fetchBuckets(projectId: 7, viewId: 3)
        XCTAssertEqual(buckets.map(\.title), ["Backlog", "Done"])
        XCTAssertEqual(buckets[1].tasks?.first?.id, 50)
    }

    // MARK: - TaskService.moveTaskToBucket

    func testMoveTaskToBucketSendsTaskId() async throws {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let service = TaskService(apiClient: client)

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/projects/7/views/3/buckets/9/tasks")
            XCTAssertEqual(request.httpMethod, "POST")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        try await service.moveTaskToBucket(taskId: 42, projectId: 7, viewId: 3, bucketId: 9)

        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let body = try XCTUnwrap(request.bodyStreamData() ?? request.httpBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["task_id"] as? Int, 42)
    }

    // MARK: - AppState.moveTask(toBucket:)

    @MainActor
    func testAppStateMoveTaskUpdatesBucketLocally() async {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let appState = AppState(taskService: TaskService(apiClient: client))

        let project = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(id: 3, title: "Kanban", projectId: 7, viewKind: "kanban")]
        )
        var task = VTask(id: 42, title: "Move me", done: false, priority: 0, projectId: 7)
        task.bucketId = 1
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        let moved = await appState.moveTask(task, toBucket: 9, in: project)
        XCTAssertTrue(moved)
        XCTAssertEqual(appState.tasks.first?.bucketId, 9)
    }

    @MainActor
    func testAppStateMoveTaskInsertsMissingTask() async {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let appState = AppState(taskService: TaskService(apiClient: client))

        let project = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(id: 3, title: "Kanban", projectId: 7, viewKind: "kanban")]
        )
        // The board was loaded before the list, so the task isn't in `tasks` yet.
        var task = VTask(id: 42, title: "Board only", done: false, priority: 0, projectId: 7)
        task.bucketId = 1
        appState.tasks = []

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        let moved = await appState.moveTask(task, toBucket: 9, in: project)
        XCTAssertTrue(moved)
        XCTAssertEqual(appState.tasks.count, 1)
        XCTAssertEqual(appState.tasks.first?.id, 42)
        XCTAssertEqual(appState.tasks.first?.bucketId, 9)
    }

    @MainActor
    func testAppStateMoveTaskNoOpWhenSameBucket() async {
        let appState = AppState()
        let project = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(id: 3, title: "Kanban", projectId: 7, viewKind: "kanban")]
        )
        var task = VTask(id: 42, title: "Already here", done: false, priority: 0, projectId: 7)
        task.bucketId = 9
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { _ in
            XCTFail("Moving to the same bucket must not hit the network")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: nil), Data())
        }

        let moved = await appState.moveTask(task, toBucket: 9, in: project)
        XCTAssertTrue(moved)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }
}

private extension URLRequest {
    /// MockURLProtocol delivers the body as a stream — read it once into Data.
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data.isEmpty ? nil : data
    }
}
