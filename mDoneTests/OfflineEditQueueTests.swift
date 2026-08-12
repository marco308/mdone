import SwiftData
import XCTest
@testable import mDone

/// Issue #146: edits made offline used to go straight to the network, fail after
/// ~7s of retries, and vanish. They're now applied locally, queued as the user's
/// intent, and merged onto a freshly-read task when the connection returns.
@MainActor
final class OfflineEditQueueTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CachedTask.self,
            CachedProject.self,
            CachedLabel.self,
            PendingOperation.self,
            FocusRecord.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeSyncService(container: ModelContainer) async -> SyncService {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return SyncService(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            modelContainer: container,
            apiClient: client
        )
    }

    private func makeAppState(sync: SyncService, connected: Bool) async -> AppState {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let state = AppState(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            labelService: LabelService(apiClient: client)
        )
        state.configureSyncService(sync, networkMonitor: NetworkMonitor(stubbedConnection: connected))
        return state
    }

    private func sampleTask() -> VTask {
        VTask(
            id: 1,
            title: "Write quarterly report",
            description: "Focus on Q1 wins",
            done: false,
            priority: 5,
            projectId: 3,
            percentDone: 0.5
        )
    }

    // MARK: - Queueing

    func testTogglingDoneOfflineAppliesLocallyAndQueues() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        await state.toggleTaskDone(state.tasks[0])

        XCTAssertTrue(state.tasks[0].done, "the checkbox must tick immediately")
        XCTAssertEqual(sync.pendingOperationCount(), 1)
        XCTAssertTrue(state.hasPendingChanges(1))
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty, "offline must not hit the network")
    }

    /// The old behaviour: nothing visible for ~7s, then a vanishing error.
    func testOfflineEditSurvivesInTheCache() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        await state.toggleTaskDone(state.tasks[0])

        let cached = try sync.loadCachedTasks()
        XCTAssertEqual(cached.first?.done, true)
    }

    func testReschedulingOfflineQueuesAndAppliesTheDate() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]
        let newDate = Date(timeIntervalSince1970: 1_900_000_000)

        await state.rescheduleTask(state.tasks[0], to: newDate)

        XCTAssertEqual(state.tasks[0].dueDate, newDate)
        XCTAssertEqual(sync.pendingOperationCount(), 1)
    }

    func testSettingProgressOfflineQueues() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]

        await state.setProgress(state.tasks[0], percent: 0.9)

        XCTAssertEqual(state.tasks[0].percentDone, 0.9)
        XCTAssertEqual(sync.pendingOperationCount(), 1)
    }

    /// Repeated edits of one task collapse into a single queued operation, so
    /// ticking on and off five times replays once, at the final state.
    func testRepeatedOfflineEditsCoalesceIntoOneOperation() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]

        await state.toggleTaskDone(state.tasks[0])
        await state.toggleTaskDone(state.tasks[0])
        await state.toggleTaskDone(state.tasks[0])

        XCTAssertEqual(sync.pendingOperationCount(), 1)
        XCTAssertTrue(state.tasks[0].done)
    }

    func testDeletingOfflineQueuesAndDropsPendingEditsForThatTask() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]

        await state.setProgress(state.tasks[0], percent: 0.9)
        XCTAssertEqual(sync.pendingOperationCount(), 1)

        await state.deleteTask(VTask(id: 1, title: "Write quarterly report", done: false, priority: 5, projectId: 3))

        XCTAssertTrue(state.tasks.isEmpty)
        // The edit was superseded by the delete, leaving one operation, not two.
        XCTAssertEqual(sync.pendingOperationCount(), 1)
    }

    // MARK: - Replay merges rather than clobbers

    /// The whole point of storing intent: an edit made offline must not undo a
    /// change someone else made server-side while the device was away.
    func testReplayMergesOntoTheFreshServerCopy() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]

        // Offline, the user only changes priority.
        var edit = TaskUpdateRequest()
        edit.priority = 1
        await state.updateTask(id: 1, request: edit)
        XCTAssertEqual(sync.pendingOperationCount(), 1)

        // Meanwhile the title and due date changed on the server.
        let serverDue = "2026-09-01T10:00:00Z"
        var sentBody: [String: Any]?
        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            if request.httpMethod == "GET" {
                let task: [String: Any] = [
                    "id": 1,
                    "title": "Renamed on the web",
                    "description": "Edited elsewhere",
                    "done": false,
                    "priority": 5,
                    "project_id": 3,
                    "due_date": serverDue,
                    "percent_done": 0.5,
                ]
                return try (response, JSONSerialization.data(withJSONObject: task))
            }
            sentBody = request.decodedJSONBody
            let task: [String: Any] = [
                "id": 1,
                "title": "Renamed on the web",
                "done": false,
                "priority": 1,
                "project_id": 3,
            ]
            return try (response, JSONSerialization.data(withJSONObject: task))
        }

        await sync.processPendingOperations()

        let body = try XCTUnwrap(sentBody)
        XCTAssertEqual(body["priority"] as? Int, 1, "the user's offline edit must win")
        XCTAssertEqual(
            body["description"] as? String,
            "Edited elsewhere",
            "the description changed on the server must survive"
        )
        XCTAssertNotNil(body["due_date"], "the due date set on the server must survive")
        XCTAssertNil(body["title"], "title is never sent, so the server keeps its own")
        XCTAssertEqual(sync.pendingOperationCount(), 0)
    }

    func testSuccessfulReplayClearsTheQueue() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]
        await state.toggleTaskDone(state.tasks[0])

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            let task: [String: Any] = [
                "id": 1,
                "title": "Write quarterly report",
                "done": true,
                "priority": 5,
                "project_id": 3,
            ]
            return try (response, JSONSerialization.data(withJSONObject: task))
        }

        await sync.processPendingOperations()

        XCTAssertEqual(sync.pendingOperationCount(), 0)
        XCTAssertTrue(sync.failedOperations().isEmpty)
    }

    // MARK: - Failures are reported, not swallowed

    /// A task deleted elsewhere can never accept the edit. Abandon it at once
    /// and keep the reason, rather than retrying three times into the same wall.
    func testReplayAgainstADeletedTaskFailsImmediatelyWithAReason() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]
        await state.toggleTaskDone(state.tasks[0])

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 404, url: request.url)
            return (response, Data("{\"message\":\"task does not exist\"}".utf8))
        }

        await sync.processPendingOperations()

        let failed = sync.failedOperations()
        XCTAssertEqual(failed.count, 1)
        XCTAssertNotNil(failed.first?.failureReason)
        XCTAssertEqual(failed.first?.retryCount, 0, "a 404 should not burn retries")
    }

    func testTransientFailureKeepsTheOperationForAnotherAttempt() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask()]
        await state.toggleTaskDone(state.tasks[0])

        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        await sync.processPendingOperations()

        XCTAssertEqual(sync.pendingOperationCount(), 1, "still queued for a later attempt")
        XCTAssertTrue(sync.failedOperations().isEmpty)
    }

    /// An expired session is the app's problem, not the queued change's. The
    /// change must survive until the user signs back in rather than being
    /// abandoned, and the rest of the queue shouldn't be marched into the same
    /// 401 one at a time.
    func testExpiredSessionPausesTheQueueWithoutLosingAnything() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        state.tasks = [sampleTask(), VTask(id: 2, title: "Second", done: false, priority: 1, projectId: 3)]
        await state.toggleTaskDone(state.tasks[0])
        await state.toggleTaskDone(state.tasks[1])
        XCTAssertEqual(sync.pendingOperationCount(), 2)

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return (MockURLProtocol.makeResponse(statusCode: 401, url: request.url), Data())
        }

        await sync.processPendingOperations()

        XCTAssertEqual(sync.pendingOperationCount(), 2, "nothing may be dropped for an expired session")
        XCTAssertTrue(sync.failedOperations().isEmpty)
        XCTAssertEqual(requestCount, 1, "should stop after the first 401, not retry every operation")
    }

    // MARK: - Things that genuinely can't be done offline

    /// Creating offline isn't queueable (no server id to replay against), so it
    /// must say so at once instead of spending the retry budget finding out.
    func testCreatingATaskOfflineFailsFast() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: false)
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        let created = await state.createTask(title: "New", projectId: 1)

        XCTAssertNil(created)
        if case .networkUnavailable = try XCTUnwrap(state.activeError) {} else {
            XCTFail("expected a networkUnavailable error, got \(String(describing: state.activeError))")
        }
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    // MARK: - Online is unaffected

    func testOnlineEditsStillGoStraightToTheNetwork() async throws {
        let container = try makeContainer()
        let sync = await makeSyncService(container: container)
        let state = await makeAppState(sync: sync, connected: true)
        state.tasks = [sampleTask()]

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            let task: [String: Any] = [
                "id": 1,
                "title": "Write quarterly report",
                "done": true,
                "priority": 5,
                "project_id": 3,
            ]
            return try (response, JSONSerialization.data(withJSONObject: task))
        }

        await state.toggleTaskDone(state.tasks[0])

        XCTAssertFalse(MockURLProtocol.capturedRequests.isEmpty)
        XCTAssertEqual(sync.pendingOperationCount(), 0, "online edits are never queued")
    }
}
