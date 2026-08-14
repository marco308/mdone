import XCTest
@testable import mDone

@MainActor
final class LabelAssignmentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: "currentLabelId")
    }

    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: "currentLabelId")
        super.tearDown()
    }

    private func makeAppState() async -> AppState {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(
            taskService: TaskService(apiClient: client),
            labelService: LabelService(apiClient: client)
        )
    }

    private func task(labels: [VLabel]? = nil) -> VTask {
        var task = VTask(id: 1, title: "Task", done: false, priority: 0, projectId: 2)
        task.labels = labels
        return task
    }

    func testAssignExistingLabelIsOptimisticAndPersistsOnSuccess() async throws {
        let appState = await makeAppState()
        let label = VLabel(id: 7, title: "Home")
        let originalTask = task()
        appState.labels = [label]
        appState.tasks = [originalTask]

        let requestStarted = expectation(description: "Add request started")
        var pendingProtocol: MockURLProtocol?
        MockURLProtocol.asynchronousRequestHandler = { _, protocolInstance in
            pendingProtocol = protocolInstance
            requestStarted.fulfill()
        }

        let mutation = Task {
            await appState.setLabel(label, on: originalTask, present: true)
        }
        await fulfillment(of: [requestStarted], timeout: 1)

        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [7], "The label is visible before the request finishes")
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.last)
        XCTAssertEqual(request.url?.path, "/api/v1/tasks/1/labels")
        XCTAssertEqual(request.httpMethod, "PUT")

        let response = MockURLProtocol.makeResponse(statusCode: 201, url: request.url)
        let protocolInstance = try XCTUnwrap(pendingProtocol)
        try protocolInstance.complete(response: response, data: XCTUnwrap(#"{"label_id":7}"#.data(using: .utf8)))
        let succeeded = await mutation.value
        XCTAssertTrue(succeeded)
        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [7])
    }

    func testRemoveExistingLabelPersistsOnSuccess() async {
        let appState = await makeAppState()
        let label = VLabel(id: 7, title: "Home")
        let originalTask = task(labels: [label])
        appState.tasks = [originalTask]
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                #"{"message":"ok"}"#.data(using: .utf8)!
            )
        }

        let succeeded = await appState.setLabel(label, on: originalTask, present: false)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(appState.tasks[0].labels, [])
        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.url?.path, "/api/v1/tasks/1/labels/7")
        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.httpMethod, "DELETE")
    }

    func testFailedAddRollsBack() async {
        let appState = await makeAppState()
        let label = VLabel(id: 7, title: "Home")
        let originalTask = task()
        appState.tasks = [originalTask]
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 400, url: request.url),
                #"{"message":"bad"}"#.data(using: .utf8)!
            )
        }

        let succeeded = await appState.setLabel(label, on: originalTask, present: true)

        XCTAssertFalse(succeeded)
        XCTAssertNil(appState.tasks[0].labels)
    }

    func testFailedRemoveRollsBack() async {
        let appState = await makeAppState()
        let label = VLabel(id: 7, title: "Home")
        let originalTask = task(labels: [label])
        appState.tasks = [originalTask]
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 400, url: request.url),
                #"{"message":"bad"}"#.data(using: .utf8)!
            )
        }

        let succeeded = await appState.setLabel(label, on: originalTask, present: false)

        XCTAssertFalse(succeeded)
        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [7])
    }

    func testFailedAddPreservesNewerUpdatedTimestamp() async throws {
        let appState = await makeAppState()
        let label = VLabel(id: 7, title: "Home")
        var originalTask = task()
        originalTask.updated = Date(timeIntervalSince1970: 100)
        appState.tasks = [originalTask]

        let requestStarted = expectation(description: "Add request started")
        var pendingProtocol: MockURLProtocol?
        MockURLProtocol.asynchronousRequestHandler = { _, protocolInstance in
            pendingProtocol = protocolInstance
            requestStarted.fulfill()
        }

        let mutation = Task {
            await appState.setLabel(label, on: originalTask, present: true)
        }
        await fulfillment(of: [requestStarted], timeout: 1)

        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [7], "The label is applied optimistically")
        let optimisticUpdated = try XCTUnwrap(appState.tasks[0].updated)
        let newerUpdated = optimisticUpdated.addingTimeInterval(60)
        appState.tasks[0].updated = newerUpdated

        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.last)
        let response = MockURLProtocol.makeResponse(statusCode: 400, url: request.url)
        let protocolInstance = try XCTUnwrap(pendingProtocol)
        try protocolInstance.complete(response: response, data: XCTUnwrap(#"{"message":"bad"}"#.data(using: .utf8)))

        let succeeded = await mutation.value
        XCTAssertFalse(succeeded)
        XCTAssertNil(appState.tasks[0].labels, "The failed optimistic label is removed")
        XCTAssertEqual(appState.tasks[0].updated, newerUpdated, "Rollback keeps the newer task timestamp")
    }

    func testAssigningPresentLabelRemovesLocalDuplicatesWithoutAnotherRequest() async {
        let appState = await makeAppState()
        let label = VLabel(id: 7, title: "Home")
        let originalTask = task(labels: [label, label])
        appState.tasks = [originalTask]

        let succeeded = await appState.setLabel(label, on: originalTask, present: true)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [7])
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testCreateLabelCachesItAndAssignsItToTask() async {
        let appState = await makeAppState()
        let originalTask = task()
        appState.tasks = [originalTask]
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v1/labels" {
                let body = try XCTUnwrap(request.decodedJSONBody)
                XCTAssertEqual(body["title"] as? String, "Errands")
                XCTAssertFalse((body["hex_color"] as? String ?? "").isEmpty)
                return (
                    MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                    #"{"id":12,"title":"Errands","hex_color":"3498db"}"#.data(using: .utf8)!
                )
            }
            return (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                #"{"label_id":12}"#.data(using: .utf8)!
            )
        }

        let created = await appState.createAndAssignLabel(title: "  Errands  ", to: originalTask)

        XCTAssertEqual(created?.id, 12)
        XCTAssertEqual(appState.labels.map(\.id), [12])
        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [12])
        XCTAssertEqual(MockURLProtocol.capturedRequests.map { $0.url?.path }, [
            "/api/v1/labels",
            "/api/v1/tasks/1/labels",
        ])
    }

    func testCreateAndAssignReusesExistingLabelCaseInsensitively() async {
        let appState = await makeAppState()
        let existing = VLabel(id: 12, title: "Errands")
        let originalTask = task()
        appState.labels = [existing]
        appState.tasks = [originalTask]
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                #"{"label_id":12}"#.data(using: .utf8)!
            )
        }

        let resolved = await appState.createAndAssignLabel(title: "errands", to: originalTask)

        XCTAssertEqual(resolved?.id, existing.id)
        XCTAssertEqual(appState.labels.map(\.id), [existing.id])
        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [existing.id])
        XCTAssertEqual(MockURLProtocol.capturedRequests.map { $0.url?.path }, ["/api/v1/tasks/1/labels"])
    }

    func testGeneralLabelMutationPreservesCurrentBehavior() async {
        let appState = await makeAppState()
        let current = VLabel(id: 3, title: "Current")
        let other = VLabel(id: 7, title: "Home")
        let originalTask = task(labels: [current])
        appState.labels = [current, other]
        appState.tasks = [originalTask]
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                #"{"label_id":7}"#.data(using: .utf8)!
            )
        }

        let succeeded = await appState.setLabel(other, on: originalTask, present: true)

        XCTAssertTrue(succeeded)
        XCTAssertTrue(appState.isCurrent(appState.tasks[0]))
        XCTAssertEqual(appState.currentTasks.map(\.id), [1])
        XCTAssertEqual(Set(appState.tasks[0].labels?.map(\.id) ?? []), Set([3, 7]))
    }

    func testLabelMutationUpdatesEmbeddedTaskSnapshots() async {
        let appState = await makeAppState()
        let label = VLabel(id: 7, title: "Home")
        let child = task()
        var parent = VTask(id: 2, title: "Parent", done: false, priority: 0, projectId: 2)
        parent.relatedTasks = [RelationKind.subtask.rawValue: [child]]
        appState.tasks = [child, parent]
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 201, url: request.url),
                #"{"label_id":7}"#.data(using: .utf8)!
            )
        }

        let succeeded = await appState.setLabel(label, on: child, present: true)

        XCTAssertTrue(succeeded)
        XCTAssertEqual(appState.tasks[1].subtasks.first?.labels?.map(\.id), [7])
    }
}
