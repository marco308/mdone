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
        let allData = try MockURLProtocol.page(encoder.encode(all))
        let memberData = try MockURLProtocol.page(encoder.encode(members))
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
            // As on a real server, the edit stamps the task, which is what
            // the change check sees.
            changed.updated = Date()
            try serve(all: [original, changed], members: [])
            await state.refreshVisibleList(project: filter)
            XCTAssertTrue(state.tasksForProject(id).isEmpty)
            XCTAssertFalse(state.isLoading)
            XCTAssertTrue(MockURLProtocol.capturedRequests.allSatisfy { $0.httpMethod == "GET" })
        }
    }

    // MARK: - Change check

    private func task(_ id: Int64, _ title: String, updatedAt seconds: TimeInterval) -> VTask {
        var task = task(id, title)
        task.updated = Date(timeIntervalSince1970: seconds)
        return task
    }

    private func isProbe(_ request: URLRequest) -> Bool {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.contains(URLQueryItem(name: "per_page", value: "1"))
            && items.contains(URLQueryItem(name: "sort_by", value: "updated"))
    }

    /// The point of the check: a quiet tick costs one small request, not the
    /// whole list.
    func testQuietTickOnlyReadsTheChangeCheck() async throws {
        let state = await makeAppState()
        try serve(all: [task(1, "A", updatedAt: 100), task(2, "B", updatedAt: 200)])
        let first = await state.refreshVisibleList(project: nil)
        XCTAssertEqual(first, .changed)

        let before = MockURLProtocol.capturedRequests.count
        let second = await state.refreshVisibleList(project: nil)

        XCTAssertEqual(second, .unchanged)
        let tick = MockURLProtocol.capturedRequests.dropFirst(before)
        XCTAssertEqual(tick.count, 1)
        XCTAssertTrue(tick.allSatisfy(isProbe))
    }

    func testEditElsewhereMovesTheCheckAndIsDownloaded() async throws {
        let state = await makeAppState()
        try serve(all: [task(1, "A", updatedAt: 100), task(2, "B", updatedAt: 200)])
        await state.refreshVisibleList(project: nil)

        try serve(all: [task(1, "Renamed", updatedAt: 300), task(2, "B", updatedAt: 200)])
        let outcome = await state.refreshVisibleList(project: nil)

        XCTAssertEqual(outcome, .changed)
        XCTAssertEqual(state.tasks.first { $0.id == 1 }?.title, "Renamed")
    }

    /// A deleted task leaves nothing behind to stamp, but the count drops.
    func testDeletionElsewhereChangesTheCount() async throws {
        let state = await makeAppState()
        try serve(all: [task(1, "Deleted", updatedAt: 100), task(2, "Kept", updatedAt: 200)])
        await state.refreshVisibleList(project: nil)

        try serve(all: [task(2, "Kept", updatedAt: 200)])
        await state.refreshVisibleList(project: nil)

        XCTAssertEqual(state.tasks.map(\.id), [2])
    }

    /// A change that does not stamp the task (a reorder on a real server;
    /// here a label, with the stamp held still) is invisible to the check.
    /// A forced read (returning to the app) and the periodic full read see it.
    func testForcedAndPeriodicReadsCatchWhatTheCheckMisses() async throws {
        let state = await makeAppState()
        var clock = Date(timeIntervalSince1970: 1_000_000)
        state.now = { clock }
        try serve(all: [task(1, "A", updatedAt: 100)])
        await state.refreshVisibleList(project: nil)

        var relabelled = task(1, "A", updatedAt: 100)
        relabelled.labels = [VLabel(id: 9, title: "Urgent", hexColor: "ff0000")]
        try serve(all: [relabelled])
        await state.refreshVisibleList(project: nil)
        XCTAssertNil(state.tasks[0].labels, "the check alone cannot see an unstamped change")

        await state.refreshVisibleList(project: nil, force: true)
        XCTAssertEqual(state.tasks[0].labels?.map(\.id), [9])

        relabelled.labels = []
        try serve(all: [relabelled])
        clock += AppState.fullListReadInterval - 1
        await state.refreshVisibleList(project: nil)
        XCTAssertEqual(state.tasks[0].labels?.map(\.id), [9])
        clock += 1
        await state.refreshVisibleList(project: nil)
        XCTAssertEqual(state.tasks[0].labels?.map(\.id), [])
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
