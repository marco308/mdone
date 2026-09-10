import SwiftData
import XCTest
@testable import mDone

/// Dragging a task to a new place (issue #183): the list must show the drop
/// straight away, send the position to the right view, take the server's
/// order back afterwards, and put things back if the request fails.
@MainActor
final class TaskReorderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private let project = Project(
        id: 7,
        title: "Work",
        views: [
            ProjectView(id: 100, title: "List", projectId: 7, viewKind: "list"),
            ProjectView(id: 200, title: "Kanban", projectId: 7, viewKind: "kanban", bucketConfigurationMode: "manual"),
        ]
    )

    private func task(_ id: Int64, position: Double, bucketId: Int64? = nil) -> VTask {
        var task = VTask(id: id, title: "Task \(id)", done: false, priority: 0, projectId: 7)
        task.position = position
        task.bucketId = bucketId
        return task
    }

    private func makeAppState() async -> AppState {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let state = AppState(taskService: TaskService(apiClient: client))
        state.projects = [project]
        state.tasks = [task(1, position: 100), task(2, position: 200), task(3, position: 300)]
        state.projectTaskCache[7] = state.tasks
        return state
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CachedTask.self, CachedProject.self, CachedLabel.self, PendingOperation.self, FocusRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func viewTasksJSON(ids: [Int64], projectId: Int64 = 7) -> Data {
        let objects: [[String: Any]] = ids.enumerated().map { index, id in
            [
                "id": id, "title": "Task \(id)", "done": false, "priority": 0,
                "project_id": projectId, "position": Double(index + 1) * 1000,
            ]
        }
        return (try? JSONSerialization.data(withJSONObject: objects)) ?? Data()
    }

    private static func body(of request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(MockURLProtocol.bodyData(from: request) ?? request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - List reorder

    func testMoveTaskSendsPositionToTheListViewAndShowsTheDropAtOnce() async throws {
        let state = await makeAppState()
        let moved = state.tasks[2]
        let newOrder = [moved, state.tasks[0], state.tasks[1]]

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            if request.httpMethod == "POST" {
                return (response, Data())
            }
            // The refetch answers with the same order the user made.
            return (response, Self.viewTasksJSON(ids: [3, 1, 2]))
        }

        let ok = await state.moveTask(moved, toPosition: 50, newOrder: newOrder)

        XCTAssertTrue(ok)
        let post = try XCTUnwrap(MockURLProtocol.capturedRequests.first { $0.httpMethod == "POST" })
        XCTAssertEqual(post.url?.path, "/api/v1/tasks/3/position")
        let body = try Self.body(of: post)
        XCTAssertEqual(body["position"] as? Double, 50)
        XCTAssertEqual(body["project_view_id"] as? Int, 100, "positions belong to the list view")
        XCTAssertEqual(state.tasksForProject(7).map(\.id), [3, 1, 2])
    }

    /// Vikunja may repair the position it was sent (collisions, values under
    /// 0.01), so the order shown afterwards is the server's, not the client's.
    func testMoveTaskTakesTheServersOrderAfterTheRefetch() async {
        let state = await makeAppState()
        let moved = state.tasks[2]

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            if request.httpMethod == "POST" {
                return (response, Data())
            }
            return (response, Self.viewTasksJSON(ids: [1, 3, 2]))
        }

        await state.moveTask(moved, toPosition: 50, newOrder: [moved, state.tasks[0], state.tasks[1]])

        XCTAssertEqual(state.tasksForProject(7).map(\.id), [1, 3, 2])
        XCTAssertEqual(
            MockURLProtocol.capturedRequests.filter { $0.httpMethod == "GET" }.first?.url?.path,
            "/api/v1/projects/7/views/100/tasks"
        )
    }

    func testMoveTaskRestoresTheOldOrderWhenTheServerRefuses() async {
        let state = await makeAppState()
        let moved = state.tasks[2]

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 500, url: request.url), Data())
        }

        let ok = await state.moveTask(moved, toPosition: 50, newOrder: [moved, state.tasks[0], state.tasks[1]])

        XCTAssertFalse(ok)
        XCTAssertEqual(state.tasksForProject(7).map(\.id), [1, 2, 3], "the drop must not stick")
        XCTAssertNotNil(state.errorMessage)
        XCTAssertTrue(MockURLProtocol.capturedRequests.allSatisfy { $0.httpMethod == "POST" }, "no refetch on failure")
    }

    func testMoveTaskWithoutAListViewDoesNothing() async {
        let state = await makeAppState()
        state.projects = [Project(id: 7, title: "No views")]

        MockURLProtocol.requestHandler = { _ in
            XCTFail("Nothing to send without a view id")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: nil), Data())
        }

        let ok = await state.moveTask(state.tasks[0], toPosition: 50)
        XCTAssertFalse(ok)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    /// A position replayed later against a list that has moved on would land
    /// the task somewhere random, so reordering is refused offline instead
    /// of queued.
    func testMoveTaskOfflineIsRefusedNotQueued() async throws {
        let container = try makeContainer()
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let sync = SyncService(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            modelContainer: container,
            apiClient: client
        )
        let state = AppState(taskService: TaskService(apiClient: client))
        state.configureSyncService(sync, networkMonitor: NetworkMonitor(stubbedConnection: false))
        state.projects = [project]
        state.tasks = [task(1, position: 100), task(2, position: 200)]
        state.projectTaskCache[7] = state.tasks

        MockURLProtocol.requestHandler = { _ in
            XCTFail("Offline reorder must not hit the network")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: nil), Data())
        }

        let ok = await state.moveTask(state.tasks[1], toPosition: 50, newOrder: [state.tasks[1], state.tasks[0]])

        XCTAssertFalse(ok)
        XCTAssertEqual(state.tasksForProject(7).map(\.id), [1, 2])
        guard case .networkUnavailable = state.activeError else {
            return XCTFail("expected the offline error, got \(String(describing: state.activeError))")
        }
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PendingOperation>()).count, 0)
    }

    // MARK: - Moving a task to another project (issue #185)

    /// Saving a task into a different project must read that project's
    /// order back, or the task sits at the bottom of a manually sorted list
    /// until the screen is reopened.
    func testMovingATaskToAnotherProjectRefetchesTheDestinationOrder() async {
        let state = await makeAppState()
        let destination = Project(
            id: 8,
            title: "Home",
            views: [ProjectView(id: 300, title: "List", projectId: 8, viewKind: "list")]
        )
        state.projects = [project, destination]
        var homeTask = task(9, position: 100)
        homeTask.projectId = 8
        state.tasks.append(homeTask)
        state.projectTaskCache[8] = [homeTask]

        let movedJSON = #"{"id": 1, "title": "Task 1", "done": false, "priority": 0, "project_id": 8}"#
            .data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            if request.httpMethod == "POST" {
                return (response, movedJSON)
            }
            // The server put the moved task first in Home's list view.
            return (response, Self.viewTasksJSON(ids: [1, 9], projectId: 8))
        }

        await state.updateTask(id: 1, request: TaskUpdateRequest(projectId: 8))

        let refetch = MockURLProtocol.capturedRequests.first { $0.httpMethod == "GET" }
        XCTAssertEqual(refetch?.url?.path, "/api/v1/projects/8/views/300/tasks", "destination list view read back")
        XCTAssertEqual(state.tasksForProject(8).map(\.id), [1, 9])
        XCTAssertEqual(state.tasksForProject(7).map(\.id), [2, 3], "the task left its old project")
    }

    /// An ordinary edit that keeps the project must not cost a refetch.
    func testEditingWithoutChangingProjectDoesNotRefetch() async {
        let state = await makeAppState()
        let editedJSON = #"{"id": 1, "title": "Renamed", "done": false, "priority": 0, "project_id": 7}"#
            .data(using: .utf8)!
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), editedJSON)
        }

        await state.updateTask(id: 1, request: TaskUpdateRequest(title: "Renamed"))

        XCTAssertEqual(MockURLProtocol.capturedRequests.map(\.httpMethod), ["POST"])
        XCTAssertEqual(state.tasks.first { $0.id == 1 }?.title, "Renamed")
    }

    // MARK: - Board placement

    func testPlaceTaskInSameBucketOnlySendsThePosition() async throws {
        let state = await makeAppState()
        let card = task(1, position: 100, bucketId: 5)

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        let ok = await state.placeTask(card, inBucket: 5, at: 250, in: project)

        XCTAssertTrue(ok)
        XCTAssertEqual(MockURLProtocol.capturedRequests.map { $0.url?.path }, ["/api/v1/tasks/1/position"])
        let body = try Self.body(of: MockURLProtocol.capturedRequests[0])
        XCTAssertEqual(body["position"] as? Double, 250)
        XCTAssertEqual(body["project_view_id"] as? Int, 200, "board positions belong to the kanban view")
    }

    func testPlaceTaskInAnotherBucketMovesItThenPositionsIt() async {
        let state = await makeAppState()
        let card = task(1, position: 100, bucketId: 5)
        state.tasks = [card]

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        let ok = await state.placeTask(card, inBucket: 6, at: 250, in: project)

        XCTAssertTrue(ok)
        XCTAssertEqual(
            MockURLProtocol.capturedRequests.map { $0.url?.path },
            ["/api/v1/projects/7/views/200/buckets/6/tasks", "/api/v1/tasks/1/position"]
        )
        XCTAssertEqual(state.tasks.first?.bucketId, 6)
    }

    func testPlaceTaskStopsWhenTheBucketMoveFails() async {
        let state = await makeAppState()
        let card = task(1, position: 100, bucketId: 5)
        state.tasks = [card]

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 403, url: request.url), Data())
        }

        let ok = await state.placeTask(card, inBucket: 6, at: 250, in: project)

        XCTAssertFalse(ok)
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1, "no position write after a failed move")
        XCTAssertEqual(state.tasks.first?.bucketId, 5)
    }

    func testPlaceTaskWithoutAKanbanViewDoesNothing() async {
        let state = await makeAppState()
        let listOnly = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(id: 100, title: "List", projectId: 7, viewKind: "list")]
        )

        let ok = await state.placeTask(task(1, position: 100, bucketId: 5), inBucket: 6, at: 1, in: listOnly)

        XCTAssertFalse(ok)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    // MARK: - Filter-mode boards

    func testBoardAllowsPlacementUnlessBucketsComeFromFilters() {
        XCTAssertTrue(project.boardAllowsManualPlacement)

        let filtered = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(
                id: 200,
                title: "Kanban",
                projectId: 7,
                viewKind: "kanban",
                bucketConfigurationMode: "filter"
            )]
        )
        XCTAssertFalse(filtered.boardAllowsManualPlacement)

        // Older servers report no mode at all; that is a plain manual board.
        let unspecified = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(id: 200, title: "Kanban", projectId: 7, viewKind: "kanban")]
        )
        XCTAssertTrue(unspecified.boardAllowsManualPlacement)

        // No kanban view at all: nothing to drag on.
        let listOnly = Project(
            id: 7,
            title: "Work",
            views: [ProjectView(id: 100, title: "List", projectId: 7, viewKind: "list")]
        )
        XCTAssertFalse(listOnly.boardAllowsManualPlacement)
        XCTAssertFalse(Project(id: 7, title: "Work").boardAllowsManualPlacement)
    }

    // MARK: - Board state

    /// The board keeps its buckets in `@State`, and SwiftUI drops an update
    /// whose new value equals the old. Bucket equality therefore has to see a
    /// reordered column as a different value, or a drag lands on the server
    /// and never on screen.
    func testBucketEqualitySeesAReorderedColumn() {
        let first = task(1, position: 100, bucketId: 5)
        let second = task(2, position: 200, bucketId: 5)
        let before = Bucket(id: 5, title: "To-Do", tasks: [first, second])
        let after = Bucket(id: 5, title: "To-Do", tasks: [second, first])

        XCTAssertNotEqual(before, after)
        XCTAssertEqual(before, Bucket(id: 5, title: "To-Do", tasks: [first, second]))
    }

    // MARK: - Drag payload

    func testBoardDragPayloadRoundTripsAndIgnoresStrayText() {
        XCTAssertEqual(BoardDragPayload.taskId(from: [BoardDragPayload.encode(42)]), 42)
        XCTAssertNil(BoardDragPayload.taskId(from: ["42"]))
        XCTAssertNil(BoardDragPayload.taskId(from: ["mdone-task:forty-two"]))
        XCTAssertNil(BoardDragPayload.taskId(from: []))
    }

    // MARK: - Sort preference through AppState

    func testSortPreferenceIsStoredPerListAndReadBack() {
        let state = AppState()
        let scope = TaskSortScope.project(Int64.random(in: 100_000 ... 999_999))
        defer { UserDefaults.standard.removeObject(forKey: scope.storageKey) }

        XCTAssertEqual(state.sortPreference(for: scope), .default)

        state.setSortPreference(TaskSortPreference(order: .manual, ascending: true), for: scope)

        XCTAssertEqual(state.sortPreference(for: scope).order, .manual)
        XCTAssertEqual(TaskSortPreference.load(for: scope).order, .manual, "written through to UserDefaults")
        XCTAssertEqual(AppState().sortPreference(for: scope).order, .manual, "a fresh AppState reads it back")
    }
}
