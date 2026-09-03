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
        // Regression for #130: buckets with tasks come from the view *tasks*
        // endpoint. `/views/{view}/buckets` returns metadata only since
        // Vikunja v0.24, which left every board column empty.
        let read = Endpoint.kanbanBuckets(projectId: 7, viewId: 3)
        XCTAssertEqual(read.path, "/api/v1/projects/7/views/3/tasks")
        XCTAssertEqual(read.method, .GET)

        let move = Endpoint.moveTaskToBucket(projectId: 7, viewId: 3, bucketId: 9)
        XCTAssertEqual(move.path, "/api/v1/projects/7/views/3/buckets/9/tasks")
        XCTAssertEqual(move.method, .POST)
    }

    // MARK: - ProjectService.fetchBuckets

    func testFetchBucketsReturnsBuckets() async throws {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let service = ProjectService(apiClient: client)

        // Shaped like a real v2.x kanban view-tasks response: `tasks` is
        // omitted for empty buckets, and `count`/`limit` are always present.
        let bucketsJSON = """
        [
            {"id": 1, "title": "Backlog", "project_view_id": 3, "limit": 0, "count": 0, "position": 1.0},
            {"id": 2, "title": "Done", "project_view_id": 3, "limit": 0, "count": 1, "position": 2.0, "tasks": [
                {"id": 50, "title": "Ship it", "done": false, "priority": 0, "project_id": 7, "bucket_id": 2}
            ]}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            // Must be the view-tasks endpoint: the buckets endpoint stopped
            // embedding tasks in Vikunja v0.24 (#130).
            XCTAssertEqual(request.url?.path, "/api/v1/projects/7/views/3/tasks")
            XCTAssertEqual(request.httpMethod, "GET")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), bucketsJSON)
        }

        let buckets = try await service.fetchBuckets(projectId: 7, viewId: 3)
        XCTAssertEqual(buckets.map(\.title), ["Backlog", "Done"])
        XCTAssertNil(buckets[0].tasks)
        XCTAssertTrue(buckets[0].activeTasks.isEmpty)
        XCTAssertEqual(buckets[1].tasks?.first?.id, 50)
        XCTAssertEqual(buckets[1].tasks?.first?.bucketId, 2)
    }

    // MARK: - fetchBuckets Task Pagination (issue #141)

    private struct BucketSpec {
        let id: Int
        let title: String
        let count: Int?
        let taskIds: [Int]
    }

    /// A kanban view-tasks response. `tasks` is omitted for empty buckets and
    /// `count` can be left out, matching what the server actually sends.
    private static func bucketsJSON(_ specs: [BucketSpec]) throws -> Data {
        let objects: [[String: Any]] = specs.map { spec in
            var bucket: [String: Any] = [
                "id": spec.id,
                "title": spec.title,
                "project_view_id": 3,
                "limit": 0,
                "position": Double(spec.id),
            ]
            if let count = spec.count {
                bucket["count"] = count
            }
            if !spec.taskIds.isEmpty {
                bucket["tasks"] = spec.taskIds.map { id in
                    [
                        "id": id, "title": "Task \(id)", "done": false,
                        "priority": 0, "project_id": 7, "bucket_id": spec.id,
                    ] as [String: Any]
                }
            }
            return bucket
        }
        return try JSONSerialization.data(withJSONObject: objects)
    }

    private static func pageParam(of request: URLRequest) -> Int {
        guard let url = request.url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "page" })?.value,
              let page = Int(raw)
        else { return 1 }
        return page
    }

    private func makeBucketService() async -> ProjectService {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return ProjectService(apiClient: client)
    }

    /// The board capped every column at one page of cards. `x-pagination-total-pages`
    /// cannot drive this loop: it counts buckets, so it says `1` even while a
    /// bucket still has tasks on later pages. The bucket's own `count` does.
    func testFetchBucketsPagesUntilEveryBucketReachesItsCount() async throws {
        let service = await makeBucketService()
        let page1 = try Self.bucketsJSON([BucketSpec(id: 2, title: "To-Do", count: 60, taskIds: Array(1 ... 50))])
        let page2 = try Self.bucketsJSON([BucketSpec(id: 2, title: "To-Do", count: 60, taskIds: Array(51 ... 60))])

        MockURLProtocol.requestHandler = { request in
            // The header lies about task pages, exactly as the server sends it.
            let response = MockURLProtocol.makeResponse(
                statusCode: 200,
                url: request.url,
                headers: ["x-pagination-total-pages": "1"]
            )
            return (response, Self.pageParam(of: request) == 1 ? page1 : page2)
        }

        let buckets = try await service.fetchBuckets(projectId: 7, viewId: 3)

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 2)
        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(buckets.first?.tasks?.count, 60)
        XCTAssertEqual(buckets.first?.tasks?.last?.id, 60, "later pages must append, not replace")
    }

    func testFetchBucketsRoutesLaterPagesIntoTheMatchingBucket() async throws {
        let service = await makeBucketService()
        let page1 = try Self.bucketsJSON([
            BucketSpec(id: 2, title: "To-Do", count: 3, taskIds: [1, 2]),
            BucketSpec(id: 3, title: "Doing", count: 2, taskIds: [10]),
        ])
        let page2 = try Self.bucketsJSON([
            BucketSpec(id: 2, title: "To-Do", count: 3, taskIds: [3]),
            BucketSpec(id: 3, title: "Doing", count: 2, taskIds: [11]),
        ])

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, Self.pageParam(of: request) == 1 ? page1 : page2)
        }

        let buckets = try await service.fetchBuckets(projectId: 7, viewId: 3)

        XCTAssertEqual(buckets.first(where: { $0.id == 2 })?.tasks?.map(\.id), [1, 2, 3])
        XCTAssertEqual(buckets.first(where: { $0.id == 3 })?.tasks?.map(\.id), [10, 11])
    }

    /// Small boards are the common case, so a complete first page must not
    /// cost a second request.
    func testFetchBucketsMakesOneRequestWhenTheFirstPageIsComplete() async throws {
        let service = await makeBucketService()
        let page = try Self.bucketsJSON([
            BucketSpec(id: 2, title: "To-Do", count: 2, taskIds: [1, 2]),
            BucketSpec(id: 3, title: "Done", count: 0, taskIds: []),
        ])

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), page)
        }

        let buckets = try await service.fetchBuckets(projectId: 7, viewId: 3)

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
        XCTAssertEqual(buckets.count, 2)
    }

    /// A server that ignores `page` (or reports a `count` it never delivers)
    /// keeps handing back the same tasks. Give up instead of looping forever.
    func testFetchBucketsStopsWhenAPageRepeatsTasksItAlreadyHas() async throws {
        let service = await makeBucketService()
        let page = try Self.bucketsJSON([BucketSpec(id: 2, title: "To-Do", count: 60, taskIds: Array(1 ... 50))])

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), page)
        }

        let buckets = try await service.fetchBuckets(projectId: 7, viewId: 3)

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 2, "must give up after a page adds nothing")
        XCTAssertEqual(buckets.first?.tasks?.count, 50)
    }

    /// Older servers may omit `count`. Treat that as "might have more", then
    /// stop on the empty page.
    func testFetchBucketsWithoutCountStopsAfterAPageWithNoTasks() async throws {
        let service = await makeBucketService()
        let page1 = try Self.bucketsJSON([BucketSpec(id: 2, title: "To-Do", count: nil, taskIds: [1, 2])])
        let page2 = try Self.bucketsJSON([BucketSpec(id: 2, title: "To-Do", count: nil, taskIds: [])])

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, Self.pageParam(of: request) == 1 ? page1 : page2)
        }

        let buckets = try await service.fetchBuckets(projectId: 7, viewId: 3)

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 2)
        XCTAssertEqual(buckets.first?.tasks?.count, 2)
    }

    // MARK: - TaskService.moveTaskToBucket

    func testMoveTaskToBucketSendsTaskId() async throws {
        let client = MockURLProtocol.mockClient()
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

    // MARK: - AppState.fetchBuckets

    @MainActor
    func testAppStateFetchBucketsSortsAndMergesTasks() async {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let appState = AppState(projectService: ProjectService(apiClient: client))

        let project = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(id: 3, title: "Kanban", projectId: 7, viewKind: "kanban")]
        )

        let bucketsJSON = """
        [
            {"id": 2, "title": "Doing", "project_view_id": 3, "limit": 0, "count": 1, "position": 2.0, "tasks": [
                {"id": 50, "title": "Ship it", "done": false, "priority": 0, "project_id": 7, "bucket_id": 2}
            ]},
            {"id": 1, "title": "Backlog", "project_view_id": 3, "limit": 0, "count": 0, "position": 1.0}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/projects/7/views/3/tasks")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), bucketsJSON)
        }

        let buckets = await appState.fetchBuckets(project: project)
        XCTAssertEqual(buckets.map(\.title), ["Backlog", "Doing"])
        // Embedded tasks are merged into the global task list.
        XCTAssertEqual(appState.tasks.map(\.id), [50])
    }

    @MainActor
    func testAppStateFetchBucketsWithoutKanbanViewReturnsEmpty() async {
        let appState = AppState()
        let project = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(id: 100, title: "List", projectId: 7, viewKind: "list")]
        )

        MockURLProtocol.requestHandler = { _ in
            XCTFail("A project without a kanban view must not hit the network")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: nil), Data())
        }

        let buckets = await appState.fetchBuckets(project: project)
        XCTAssertTrue(buckets.isEmpty)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    // MARK: - AppState.moveTask(toBucket:)

    @MainActor
    func testAppStateMoveTaskUpdatesBucketLocally() async {
        let client = MockURLProtocol.mockClient()
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
        let client = MockURLProtocol.mockClient()
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
