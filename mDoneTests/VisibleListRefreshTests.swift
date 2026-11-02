import Observation
import XCTest
@testable import mDone

/// `AppState.refreshVisibleList` against a mocked server: changes made by
/// another client reach the Inbox and saved filters while they stay open
/// (#241).
@MainActor
final class VisibleListRefreshTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeAppState() async -> AppState {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let state = AppState(taskService: TaskService(apiClient: client))
        state.isAuthenticated = true
        return state
    }

    private func task(_ id: Int64, _ title: String, projectId: Int64 = 5) -> VTask {
        VTask(id: id, title: title, done: false, priority: 0, projectId: projectId)
    }

    /// Serves `all` from the all-tasks endpoint and `members` from any
    /// project view.
    private func serve(all: [VTask], members: [VTask] = []) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let allData = try encoder.encode(all)
        let memberData = try encoder.encode(members)
        MockURLProtocol.requestHandler = { request in
            let data = request.url!.path.contains("/projects/") ? memberData : allData
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), data)
        }
    }

    func testSavedFiltersFollowServerMembershipAndKeepRealProjects() async throws {
        for id: Int64 in [-2, -3] {
            MockURLProtocol.reset()
            let state = await makeAppState()
            let filter = Project(id: id, title: "Saved filter", views: [
                ProjectView(id: 25, title: "List", projectId: id, viewKind: "list"),
            ])
            let original = task(1, "Old member")
            let added = task(2, "Added elsewhere", projectId: 6)
            state.tasks = [original]
            state.projectTaskCache[id] = [original]

            try serve(all: [original, added], members: [added])
            await state.refreshVisibleList(project: filter)
            XCTAssertEqual(state.tasksForProject(id).map(\.id), [2])
            XCTAssertEqual(state.tasksForProject(id).first?.projectId, 6)

            // A due date set on a "No date" task, or a "Today" task completed
            // elsewhere, takes it out of the filter. Empty is a real answer.
            var changed = added
            changed.dueDate = Date()
            changed.done = id == -2
            try serve(all: [original, changed], members: [])
            await state.refreshVisibleList(project: filter)
            XCTAssertTrue(state.tasksForProject(id).isEmpty)
            XCTAssertFalse(state.isLoading)
            XCTAssertTrue(MockURLProtocol.capturedRequests.allSatisfy { $0.httpMethod == "GET" })
        }
    }

    func testInboxPicksUpEditsAndDeletionsFromElsewhere() async throws {
        let state = await makeAppState()
        state.tasks = [task(1, "Deleted elsewhere"), task(2, "Old title")]

        try serve(all: [task(2, "Renamed elsewhere")])
        await state.refreshVisibleList(project: nil)

        XCTAssertEqual(state.tasks.map(\.title), ["Renamed elsewhere"])
    }

    /// Most ticks find nothing new. Those must not write `tasks` at all, or
    /// every open list would re-render (and rewrite the cache) every tick.
    func testUnchangedServerLeavesTheListsUntouched() async throws {
        let state = await makeAppState()
        let filter = Project(id: -2, title: "Saved filter", views: [
            ProjectView(id: 25, title: "List", projectId: -2, viewKind: "list"),
        ])
        let member = task(1, "Same as before")
        try serve(all: [member, task(2, "Other")], members: [member])
        await state.refreshVisibleList(project: filter)
        XCTAssertEqual(state.tasksForProject(-2).map(\.id), [1])

        var tasksWritten = false
        withObservationTracking {
            _ = state.tasks
            _ = state.projectTaskCache
        } onChange: {
            tasksWritten = true
        }
        let requestsBefore = MockURLProtocol.capturedRequests.count
        await state.refreshVisibleList(project: filter)

        XCTAssertGreaterThan(MockURLProtocol.capturedRequests.count, requestsBefore)
        XCTAssertFalse(tasksWritten)
    }

    func testFailedReadKeepsTheRows() async {
        let state = await makeAppState()
        state.tasks = [task(1, "Kept")]
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 404, url: request.url), Data())
        }

        await state.refreshVisibleList(project: nil)

        XCTAssertEqual(state.tasks.map(\.id), [1])
        XCTAssertNil(state.activeError)
        XCTAssertFalse(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testBusyOrSignedOutStateSkipsTheRead() async {
        let state = await makeAppState()
        state.isLoading = true
        await state.refreshVisibleList(project: nil)
        state.isLoading = false

        state.pendingOperationsCount = 1
        await state.refreshVisibleList(project: nil)
        state.pendingOperationsCount = 0

        await state.refreshVisibleList(project: nil) { false }

        state.isAuthenticated = false
        await state.refreshVisibleList(project: nil)

        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }
}
