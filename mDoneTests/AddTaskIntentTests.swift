import AppIntents
import SwiftData
import XCTest
@testable import mDone

/// "Hey Siri, add a task in mDone" runs `AddTaskIntent` in the background,
/// possibly from a cold launch and possibly in a car with no signal. These
/// tests cover the `AppState` path it calls and the intent's own plumbing.
@MainActor
final class AddTaskIntentTests: XCTestCase {
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

    /// A signed-in `AppState` on the mock client, with an in-memory queue and
    /// a monitor pinned to `connected`.
    private func makeAppState(connected: Bool = true) async throws -> (AppState, ModelContainer) {
        let container = try makeContainer()
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let sync = SyncService(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            modelContainer: container,
            apiClient: client
        )
        let state = AppState(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            labelService: LabelService(apiClient: client)
        )
        state.configureSyncService(sync, networkMonitor: NetworkMonitor(stubbedConnection: connected))
        state.isAuthenticated = true
        state.projects = [
            Project(id: 7, title: "Inbox"),
            Project(id: 8, title: "Home"),
        ]
        return (state, container)
    }

    private func pendingOperations(in container: ModelContainer) throws -> [PendingOperation] {
        try container.mainContext.fetch(FetchDescriptor<PendingOperation>())
    }

    private static func createdTaskJSON(id: Int64, title: String, projectId: Int64) -> Data {
        #"{"id": \#(id), "title": "\#(title)", "done": false, "priority": 0, "project_id": \#(projectId), "created": "2026-09-03T08:00:00Z", "updated": "2026-09-03T08:00:00Z"}"#
            .data(using: .utf8)!
    }

    // MARK: - Online

    func testCreatesTaskInNamedProject() async throws {
        let (state, _) = try await makeAppState()
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                Self.createdTaskJSON(id: 100, title: "Buy milk", projectId: 8)
            )
        }

        let outcome = try await state.createTaskFromIntent(title: "Buy milk", projectId: 8)

        XCTAssertEqual(outcome, .created(taskTitle: "Buy milk", projectTitle: "Home"))
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/api/v1/projects/8/tasks")
        let body = try XCTUnwrap(MockURLProtocol.bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Buy milk")
        XCTAssertEqual(state.tasks.map(\.id), [100], "the new task joins the live list")
    }

    func testFallsBackToTheDefaultProject() async throws {
        let (state, _) = try await makeAppState()
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                Self.createdTaskJSON(id: 101, title: "Call the dentist", projectId: 7)
            )
        }

        let outcome = try await state.createTaskFromIntent(title: "  Call the dentist \n", projectId: nil)

        XCTAssertEqual(outcome, .created(taskTitle: "Call the dentist", projectTitle: "Inbox"))
        XCTAssertEqual(MockURLProtocol.capturedRequests.first?.url?.path, "/api/v1/projects/7/tasks")
    }

    func testFetchesProjectsWhenNothingIsLoaded() async throws {
        // A cold background launch from Siri: no projects in memory or cache.
        let (state, _) = try await makeAppState()
        state.projects = []
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v1/projects" {
                let json = #"[{"id": 3, "title": "Work", "is_archived": false, "is_favorite": false}]"#
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json.data(using: .utf8)!)
            }
            return (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                Self.createdTaskJSON(id: 102, title: "Send invoice", projectId: 3)
            )
        }

        let outcome = try await state.createTaskFromIntent(title: "Send invoice", projectId: nil)

        XCTAssertEqual(outcome, .created(taskTitle: "Send invoice", projectTitle: "Work"))
        XCTAssertEqual(state.projects.map(\.id), [3])
        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.url?.path, "/api/v1/projects/3/tasks")
    }

    func testServerRejectionIsReportedNotQueued() async throws {
        let (state, container) = try await makeAppState()
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 403, url: request.url), Data())
        }

        do {
            _ = try await state.createTaskFromIntent(title: "Nope", projectId: 8)
            XCTFail("a 403 must surface as an error")
        } catch let error as IntentTaskError {
            guard case .failed = error else { return XCTFail("expected .failed, got \(error)") }
        }
        XCTAssertTrue(try pendingOperations(in: container).isEmpty, "a refusal is not a connectivity failure")
    }

    // MARK: - Offline

    func testQueuesTheCreateWhenOffline() async throws {
        let (state, container) = try await makeAppState(connected: false)
        MockURLProtocol.requestHandler = { _ in
            XCTFail("offline must not touch the network")
            throw URLError(.notConnectedToInternet)
        }

        let outcome = try await state.createTaskFromIntent(title: "Buy milk", projectId: 8)

        XCTAssertEqual(outcome, .queued(taskTitle: "Buy milk", projectTitle: "Home"))
        let queued = try pendingOperations(in: container)
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.first?.method, "PUT")
        XCTAssertEqual(queued.first?.endpointPath, "/api/v1/projects/8/tasks")
        let body = try XCTUnwrap(queued.first?.bodyData)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["title"] as? String, "Buy milk")
        XCTAssertEqual(state.pendingOperationsCount, 1, "the offline banner counts a queued create")
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testQueuesTheCreateWhenTheServerIsUnreachable() async throws {
        // The monitor says online, the server says otherwise: a tunnel.
        let (state, container) = try await makeAppState(connected: true)
        MockURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }

        let outcome = try await state.createTaskFromIntent(title: "Buy milk", projectId: 8)

        XCTAssertEqual(outcome, .queued(taskTitle: "Buy milk", projectTitle: "Home"))
        XCTAssertEqual(try pendingOperations(in: container).count, 1)
    }

    func testQueuedCreateReplaysWhenTheConnectionReturns() async throws {
        let (state, container) = try await makeAppState(connected: false)
        _ = try await state.createTaskFromIntent(title: "Buy milk", projectId: 8)

        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                Self.createdTaskJSON(id: 103, title: "Buy milk", projectId: 8)
            )
        }
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        let sync = SyncService(
            taskService: TaskService(apiClient: client),
            projectService: ProjectService(apiClient: client),
            modelContainer: container,
            apiClient: client
        )
        await sync.processPendingOperations()

        XCTAssertTrue(try pendingOperations(in: container).isEmpty, "the replayed create leaves the queue")
        let replay = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(replay.httpMethod, "PUT")
        XCTAssertEqual(replay.url?.path, "/api/v1/projects/8/tasks")
    }

    // MARK: - Refusals

    func testRejectsABlankTitle() async throws {
        let (state, _) = try await makeAppState()
        MockURLProtocol.requestHandler = { request in
            XCTFail("a blank title must not hit the network")
            return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), Data())
        }

        do {
            _ = try await state.createTaskFromIntent(title: "   ", projectId: nil)
            XCTFail("expected emptyTitle")
        } catch let error as IntentTaskError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    func testRefusesWhenNotSignedIn() async throws {
        let (state, _) = try await makeAppState()
        state.isAuthenticated = false
        AuthService.shared.clearAll()
        defer { AuthService.shared.clearAll() }

        do {
            _ = try await state.createTaskFromIntent(title: "Buy milk", projectId: nil)
            XCTFail("expected notSignedIn")
        } catch let error as IntentTaskError {
            XCTAssertEqual(error, .notSignedIn)
        }
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testRefusesWhenThereIsNoProject() async throws {
        let (state, _) = try await makeAppState(connected: false)
        state.projects = []

        do {
            _ = try await state.createTaskFromIntent(title: "Buy milk", projectId: nil)
            XCTFail("expected noProject")
        } catch let error as IntentTaskError {
            XCTAssertEqual(error, .noProject)
        }
    }

    // MARK: - The intent itself

    func testPerformGoesThroughTheSharedAppState() async throws {
        let (state, _) = try await makeAppState()
        XCTAssertTrue(AppState.shared === state)
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                Self.createdTaskJSON(id: 104, title: "Buy milk", projectId: 8)
            )
        }

        var intent = AddTaskIntent()
        intent.taskTitle = "Buy milk"
        intent.project = ProjectEntity(project: Project(id: 8, title: "Home"))
        _ = try await intent.perform()

        XCTAssertEqual(MockURLProtocol.capturedRequests.first?.url?.path, "/api/v1/projects/8/tasks")
        XCTAssertEqual(state.tasks.map(\.id), [104])
    }

    func testPerformWithoutSharedStateReportsNotSignedIn() async throws {
        let previous = AppState.shared
        defer { AppState.shared = previous }
        AppState.shared = nil
        var intent = AddTaskIntent()
        intent.taskTitle = "Buy milk"

        do {
            _ = try await intent.perform()
            XCTFail("expected notSignedIn")
        } catch let error as IntentTaskError {
            XCTAssertEqual(error, .notSignedIn)
        }
    }

    func testDialogNamesTheTaskAndProject() {
        XCTAssertEqual(
            AddTaskIntent.dialog(for: .created(taskTitle: "Buy milk", projectTitle: "Home")),
            "Added \"Buy milk\" to Home."
        )
        XCTAssertEqual(
            AddTaskIntent.dialog(for: .queued(taskTitle: "Buy milk", projectTitle: "Home")),
            "Added \"Buy milk\" to Home. It will sync when you're back online."
        )
    }

    // MARK: - Project entity

    func testProjectQueryReadsTheSharedProjectList() async throws {
        let (state, _) = try await makeAppState()
        state.projects.append(Project(id: 9, title: "Archive", isArchived: true))
        let query = ProjectEntityQuery()

        let suggested = try await query.suggestedEntities()
        XCTAssertEqual(suggested.map(\.title), ["Inbox", "Home"], "archived projects are not offered")

        let byId = try await query.entities(for: ["8", "not-a-number"])
        XCTAssertEqual(byId.map(\.projectId), [8])

        let matching = try await query.entities(matching: "hom")
        XCTAssertEqual(matching.map(\.title), ["Home"])
    }

    func testProjectQueryFallsBackToTheCache() async throws {
        // Cold launch: nothing in memory, but the last sync left projects on disk.
        let (state, container) = try await makeAppState()
        let cached = state.projects
        state.projects = []
        let sync = SyncService(
            taskService: TaskService(apiClient: MockURLProtocol.mockClient()),
            projectService: ProjectService(apiClient: MockURLProtocol.mockClient()),
            modelContainer: container
        )
        try sync.cacheProjects(cached)

        let suggested = try await ProjectEntityQuery().suggestedEntities()

        XCTAssertEqual(Set(suggested.map(\.title)), ["Inbox", "Home"])
    }
}
