import XCTest
@testable import mDone

/// Covers the task-relations feature (issue #1): the `related_tasks` model,
/// relation endpoints/service calls, nesting order for list display, and the
/// AppState flows that keep relation snapshots fresh.
final class TaskRelationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Fixtures

    /// Task JSON in the server's snake_case shape, matching what Vikunja
    /// v2.4.0 returns (null-able fields, zero-dates, created_by).
    private static func taskJSON(
        id: Int64,
        title: String,
        done: Bool = false,
        projectId: Int64 = 1,
        relatedTasks: String = "null"
    ) -> String {
        """
        {"id": \(id), "title": "\(title)", "done": \(done), "priority": 0, "project_id": \(projectId),
         "due_date": "0001-01-01T00:00:00Z", "labels": null, "assignees": null, "reactions": null,
         "attachments": null, "identifier": "", "index": \(id), "percent_done": 0, "is_favorite": false,
         "created": "2026-07-19T21:47:37Z", "updated": "2026-07-19T21:47:37Z", "created_by": null,
         "related_tasks": \(relatedTasks)}
        """
    }

    private func makeConfiguredService() async -> TaskService {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return TaskService(apiClient: client)
    }

    @MainActor
    private func makeMockedAppState() async -> AppState {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(taskService: TaskService(apiClient: client))
    }

    private func makeTask(
        id: Int64,
        title: String = "Task",
        done: Bool = false,
        projectId: Int64 = 1,
        relatedTasks: [String: [VTask]]? = nil
    ) -> VTask {
        VTask(id: id, title: title, done: done, priority: 0, projectId: projectId, relatedTasks: relatedTasks)
    }

    // MARK: - Decoding

    func testFetchTaskDecodesRelatedTasks() async throws {
        let service = await makeConfiguredService()
        // The exact shape Vikunja v2.4.0 returns from GET /api/v1/tasks/{id}
        // for a parent with three subtasks, one of them done.
        let json = try XCTUnwrap(Self.taskJSON(
            id: 1, title: "Parent task",
            relatedTasks: """
            {"subtask": [
                \(Self.taskJSON(id: 2, title: "Child one", done: true)),
                \(Self.taskJSON(id: 3, title: "Child two")),
                \(Self.taskJSON(id: 4, title: "Child three"))
            ]}
            """
        ).data(using: .utf8))
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        let task = try await service.fetchTask(id: 1)
        XCTAssertEqual(task.subtasks.map(\.id), [2, 3, 4])
        XCTAssertEqual(task.subtasks.filter(\.done).map(\.id), [2])
        let counts = try XCTUnwrap(task.subtaskCounts)
        XCTAssertEqual(counts.done, 1)
        XCTAssertEqual(counts.total, 3)
        // Zero-dates inside embedded tasks map to distantPast -> no effective due date.
        XCTAssertNil(task.subtasks[0].effectiveDueDate)
        // Embedded tasks carry no relations of their own (server doesn't recurse).
        XCTAssertNil(task.subtasks[0].relatedTasks)
    }

    func testFetchTaskDecodesParenttaskDirection() async throws {
        let service = await makeConfiguredService()
        let json = try XCTUnwrap(Self.taskJSON(
            id: 3, title: "Child two",
            relatedTasks: "{\"parenttask\": [\(Self.taskJSON(id: 1, title: "Parent task"))]}"
        ).data(using: .utf8))
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        let task = try await service.fetchTask(id: 3)
        XCTAssertTrue(task.hasParentTask)
        XCTAssertEqual(task.parentTasks.map(\.id), [1])
        XCTAssertNil(task.subtaskCounts, "A task with no subtasks has no counts")
    }

    func testUnknownRelationKindStillDecodes() async throws {
        let service = await makeConfiguredService()
        let json = try XCTUnwrap(Self.taskJSON(
            id: 5, title: "Future",
            relatedTasks: "{\"somefuturekind\": [\(Self.taskJSON(id: 6, title: "Other"))]}"
        ).data(using: .utf8))
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        let task = try await service.fetchTask(id: 5)
        XCTAssertEqual(task.relatedTasks?["somefuturekind"]?.map(\.id), [6])
        XCTAssertTrue(task.subtasks.isEmpty)
    }

    // MARK: - RelationKind

    func testRelationKindLabels() {
        XCTAssertEqual(RelationKind.subtask.label, "Subtask")
        XCTAssertEqual(RelationKind.parenttask.label, "Parent Task")
        XCTAssertEqual(RelationKind.blocked.label, "Blocked By")
        XCTAssertEqual(RelationKind.label(forRawKind: "duplicateof"), "Duplicate Of")
        XCTAssertEqual(RelationKind.label(forRawKind: "somefuturekind"), "Somefuturekind")
    }

    func testRelationKindCoversVikunjaKinds() {
        let expected: Set = [
            "unknown", "subtask", "parenttask", "related", "duplicateof", "duplicates",
            "blocking", "blocked", "precedes", "follows", "copiedfrom", "copiedto",
        ]
        XCTAssertEqual(Set(RelationKind.allCases.map(\.rawValue)), expected)
    }

    func testTaskRelationRequestEncoding() throws {
        let request = TaskRelationRequest(otherTaskId: 9, relationKind: .subtask)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]

        XCTAssertEqual(json?["other_task_id"] as? Int, 9)
        XCTAssertEqual(json?["relation_kind"] as? String, "subtask")
    }

    // MARK: - Endpoints

    func testRelationEndpoints() {
        let create = Endpoint.createTaskRelation(taskId: 7)
        XCTAssertEqual(create.path, "/api/v1/tasks/7/relations")
        XCTAssertEqual(create.method, .PUT)

        let delete = Endpoint.deleteTaskRelation(taskId: 7, relationKind: "subtask", otherTaskId: 9)
        XCTAssertEqual(delete.path, "/api/v1/tasks/7/relations/subtask/9")
        XCTAssertEqual(delete.method, .DELETE)
    }

    func testTaskListEndpointsRequestSubtaskExpansion() {
        let all = Endpoint.allTasks()
        XCTAssertTrue(all.queryItems?.contains(URLQueryItem(name: "expand", value: "subtasks")) == true)

        let project = Endpoint.projectTasks(projectId: 1, viewId: 2)
        XCTAssertTrue(project.queryItems?.contains(URLQueryItem(name: "expand", value: "subtasks")) == true)
    }

    // MARK: - TaskService

    func testCreateRelationSendsCorrectRequest() async throws {
        let service = await makeConfiguredService()
        let responseJSON = """
        {"task_id": 1, "other_task_id": 2, "relation_kind": "subtask",
         "created_by": {"id": 1, "username": "probe"}, "created": "2026-07-19T21:48:02.120342215Z"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/tasks/1/relations")
            XCTAssertEqual(request.httpMethod, "PUT")
            if let body = MockURLProtocol.bodyData(from: request),
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            {
                XCTAssertEqual(json["other_task_id"] as? Int, 2)
                XCTAssertEqual(json["relation_kind"] as? String, "subtask")
            } else {
                XCTFail("Missing request body")
            }
            return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), responseJSON)
        }

        let relation = try await service.createRelation(taskId: 1, otherTaskId: 2, kind: .subtask)
        XCTAssertEqual(relation.taskId, 1)
        XCTAssertEqual(relation.otherTaskId, 2)
        XCTAssertEqual(relation.relationKind, "subtask")
    }

    func testDeleteRelationCallsDeleteEndpoint() async throws {
        let service = await makeConfiguredService()
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/tasks/1/relations/subtask/2")
            XCTAssertEqual(request.httpMethod, "DELETE")
            let body = #"{"message":"Successfully deleted."}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), body)
        }

        try await service.deleteRelation(taskId: 1, otherTaskId: 2, kind: .subtask)
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    func testCreateRelationSurfacesConflictError() async {
        let service = await makeConfiguredService()
        MockURLProtocol.requestHandler = { request in
            let body = #"{"code": 4008, "message": "The task relation already exists."}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 409, url: request.url), body)
        }

        do {
            _ = try await service.createRelation(taskId: 1, otherTaskId: 2, kind: .subtask)
            XCTFail("Expected serverError")
        } catch let NetworkError.serverError(statusCode, message) {
            XCTAssertEqual(statusCode, 409)
            XCTAssertEqual(message, "The task relation already exists.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - TaskNesting

    func testNestingKeepsFlatListOrderWhenNoRelations() {
        let tasks = [makeTask(id: 1), makeTask(id: 2), makeTask(id: 3)]
        let rows = TaskNesting.rows(for: tasks)
        XCTAssertEqual(rows.map(\.id), [1, 2, 3])
        XCTAssertTrue(rows.allSatisfy { $0.depth == 0 })
    }

    func testNestingPlacesSubtaskUnderParent() {
        let tasks = [
            makeTask(id: 2, title: "Unrelated"),
            makeTask(id: 3, title: "Child", relatedTasks: ["parenttask": [makeTask(id: 1)]]),
            makeTask(id: 1, title: "Parent"),
        ]
        let rows = TaskNesting.rows(for: tasks)
        XCTAssertEqual(rows.map(\.id), [2, 1, 3], "Child moves directly beneath its parent")
        XCTAssertEqual(rows.map(\.depth), [0, 0, 1])
    }

    func testNestingSupportsGrandchildren() {
        let tasks = [
            makeTask(id: 1, title: "Parent"),
            makeTask(id: 2, title: "Child", relatedTasks: ["parenttask": [makeTask(id: 1)]]),
            makeTask(id: 3, title: "Grandchild", relatedTasks: ["parenttask": [makeTask(id: 2)]]),
        ]
        let rows = TaskNesting.rows(for: tasks)
        XCTAssertEqual(rows.map(\.id), [1, 2, 3])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2])
    }

    func testNestingLeavesOrphanedSubtaskAtTopLevel() {
        // Parent (id 9) is not in the visible list — e.g. filtered into another
        // smart section — so the subtask must not disappear.
        let tasks = [
            makeTask(id: 2, title: "Child", relatedTasks: ["parenttask": [makeTask(id: 9)]]),
            makeTask(id: 3),
        ]
        let rows = TaskNesting.rows(for: tasks)
        XCTAssertEqual(rows.map(\.id), [2, 3])
        XCTAssertTrue(rows.allSatisfy { $0.depth == 0 })
    }

    func testNestingEmitsEveryTaskExactlyOnceWithRelationCycle() {
        // A <-> B parent cycle (representable server-side) must not hang or
        // drop tasks.
        let tasks = [
            makeTask(id: 1, relatedTasks: ["parenttask": [makeTask(id: 2)]]),
            makeTask(id: 2, relatedTasks: ["parenttask": [makeTask(id: 1)]]),
            makeTask(id: 3),
        ]
        let rows = TaskNesting.rows(for: tasks)
        XCTAssertEqual(Set(rows.map(\.id)), [1, 2, 3])
        XCTAssertEqual(rows.count, 3)
    }

    func testNestingEmitsMultiParentChildOnce() {
        let tasks = [
            makeTask(id: 1, title: "Parent A"),
            makeTask(id: 2, title: "Parent B"),
            makeTask(id: 3, title: "Shared child", relatedTasks: ["parenttask": [makeTask(id: 1), makeTask(id: 2)]]),
        ]
        let rows = TaskNesting.rows(for: tasks)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.filter { $0.id == 3 }.count, 1)
        XCTAssertEqual(rows.map(\.id), [1, 3, 2], "Child nests under the first parent encountered")
    }

    // MARK: - preservingRelations

    func testPreservingRelationsCarriesRelatedTasksForward() {
        let existing = makeTask(
            id: 1, relatedTasks: ["subtask": [makeTask(id: 2, done: true), makeTask(id: 3)]]
        )
        // Server update responses null out labels and related_tasks.
        let response = makeTask(id: 1, title: "Edited")

        let merged = AppState.preservingRelations(existing: existing, response: response)
        XCTAssertEqual(merged.title, "Edited")
        XCTAssertEqual(merged.subtasks.map(\.id), [2, 3])
        XCTAssertEqual(merged.subtaskCounts?.done, 1)
    }

    func testPreservingRelationsPrefersResponseWhenPresent() {
        let existing = makeTask(id: 1, relatedTasks: ["subtask": [makeTask(id: 2)]])
        let response = makeTask(id: 1, relatedTasks: ["subtask": [makeTask(id: 2), makeTask(id: 3)]])

        let merged = AppState.preservingRelations(existing: existing, response: response)
        XCTAssertEqual(merged.subtasks.map(\.id), [2, 3])
    }

    // MARK: - AppState flows

    @MainActor
    func testToggleSubtaskDoneUpdatesParentCounts() async throws {
        let appState = await makeMockedAppState()
        let child = makeTask(id: 2, title: "Child")
        let parent = makeTask(id: 1, title: "Parent", relatedTasks: ["subtask": [child]])
        appState.tasks = [parent, child]

        let toggleResponse = try XCTUnwrap(Self.taskJSON(id: 2, title: "Child", done: true).data(using: .utf8))
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/tasks/2")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), toggleResponse)
        }

        await appState.toggleTaskDone(child)

        let updatedParent = appState.tasks.first { $0.id == 1 }
        XCTAssertEqual(updatedParent?.subtaskCounts?.done, 1)
        XCTAssertEqual(updatedParent?.subtaskCounts?.total, 1)
        XCTAssertEqual(appState.tasks.first { $0.id == 2 }?.done, true)
    }

    @MainActor
    func testDeleteTaskStripsEmbeddedRelationCopies() async {
        let appState = await makeMockedAppState()
        let child = makeTask(id: 2, title: "Child")
        let parent = makeTask(id: 1, title: "Parent", relatedTasks: ["subtask": [child]])
        appState.tasks = [parent, child]

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        await appState.deleteTask(child)

        XCTAssertNil(appState.tasks.first { $0.id == 1 }?.subtaskCounts)
        XCTAssertNil(appState.tasks.first { $0.id == 1 }?.relatedTasks)
        XCTAssertFalse(appState.tasks.contains { $0.id == 2 })
    }

    @MainActor
    func testAddSubtaskRelationLinksAndRefreshesBothTasks() async throws {
        let appState = await makeMockedAppState()
        appState.tasks = [makeTask(id: 1, title: "Parent"), makeTask(id: 2, title: "Child")]

        let relationResponse = #"{"task_id": 1, "other_task_id": 2, "relation_kind": "subtask"}"#
            .data(using: .utf8)!
        let parentResponse = try XCTUnwrap(Self.taskJSON(
            id: 1, title: "Parent",
            relatedTasks: "{\"subtask\": [\(Self.taskJSON(id: 2, title: "Child"))]}"
        ).data(using: .utf8))
        let childResponse = try XCTUnwrap(Self.taskJSON(
            id: 2, title: "Child",
            relatedTasks: "{\"parenttask\": [\(Self.taskJSON(id: 1, title: "Parent"))]}"
        ).data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod, path) {
            case ("PUT", "/api/v1/tasks/1/relations"):
                return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), relationResponse)
            case ("GET", "/api/v1/tasks/1"):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), parentResponse)
            case ("GET", "/api/v1/tasks/2"):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), childResponse)
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "?") \(path)")
                return (MockURLProtocol.makeResponse(statusCode: 404, url: request.url), Data())
            }
        }

        let success = await appState.addSubtaskRelation(parentId: 1, childId: 2)

        XCTAssertTrue(success)
        XCTAssertEqual(appState.tasks.first { $0.id == 1 }?.subtasks.map(\.id), [2])
        XCTAssertEqual(appState.tasks.first { $0.id == 2 }?.parentTasks.map(\.id), [1])
    }

    @MainActor
    func testRemoveRelationUnlinksBothTasks() async throws {
        let appState = await makeMockedAppState()
        let child = makeTask(id: 2, title: "Child", relatedTasks: ["parenttask": [makeTask(id: 1)]])
        let parent = makeTask(id: 1, title: "Parent", relatedTasks: ["subtask": [makeTask(id: 2)]])
        appState.tasks = [parent, child]

        let deleteResponse = #"{"message":"Successfully deleted."}"#.data(using: .utf8)!
        let parentResponse = try XCTUnwrap(Self.taskJSON(id: 1, title: "Parent").data(using: .utf8))
        let childResponse = try XCTUnwrap(Self.taskJSON(id: 2, title: "Child").data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod, path) {
            case ("DELETE", "/api/v1/tasks/1/relations/subtask/2"):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), deleteResponse)
            case ("GET", "/api/v1/tasks/1"):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), parentResponse)
            case ("GET", "/api/v1/tasks/2"):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), childResponse)
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "?") \(path)")
                return (MockURLProtocol.makeResponse(statusCode: 404, url: request.url), Data())
            }
        }

        await appState.removeRelation(taskId: 1, otherTaskId: 2, kind: .subtask)

        XCTAssertNil(appState.tasks.first { $0.id == 1 }?.subtaskCounts)
        XCTAssertFalse(appState.tasks.first { $0.id == 2 }?.hasParentTask ?? true)
    }

    @MainActor
    func testCreateSubtaskCreatesTaskThenLinksIt() async throws {
        let appState = await makeMockedAppState()
        let parent = makeTask(id: 1, title: "Parent", projectId: 5)
        appState.tasks = [parent]

        let newTaskResponse = try XCTUnwrap(Self.taskJSON(id: 99, title: "New subtask", projectId: 5)
            .data(using: .utf8))
        let relationResponse = #"{"task_id": 1, "other_task_id": 99, "relation_kind": "subtask"}"#
            .data(using: .utf8)!
        let parentResponse = try XCTUnwrap(Self.taskJSON(
            id: 1, title: "Parent", projectId: 5,
            relatedTasks: "{\"subtask\": [\(Self.taskJSON(id: 99, title: "New subtask", projectId: 5))]}"
        ).data(using: .utf8))
        let childResponse = try XCTUnwrap(Self.taskJSON(
            id: 99, title: "New subtask", projectId: 5,
            relatedTasks: "{\"parenttask\": [\(Self.taskJSON(id: 1, title: "Parent", projectId: 5))]}"
        ).data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let path = request.url?.path ?? ""
            switch (request.httpMethod, path) {
            case ("PUT", "/api/v1/projects/5/tasks"):
                return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), newTaskResponse)
            case ("PUT", "/api/v1/tasks/1/relations"):
                if let requestBody = MockURLProtocol.bodyData(from: request),
                   let json = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
                {
                    XCTAssertEqual(json["other_task_id"] as? Int, 99)
                    XCTAssertEqual(json["relation_kind"] as? String, "subtask")
                } else {
                    XCTFail("Missing relation request body")
                }
                return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), relationResponse)
            case ("GET", "/api/v1/tasks/1"):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), parentResponse)
            case ("GET", "/api/v1/tasks/99"):
                return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), childResponse)
            default:
                XCTFail("Unexpected request: \(request.httpMethod ?? "?") \(path)")
                return (MockURLProtocol.makeResponse(statusCode: 404, url: request.url), Data())
            }
        }

        let success = await appState.createSubtask(title: "New subtask", parent: parent)

        XCTAssertTrue(success)
        XCTAssertEqual(appState.tasks.first { $0.id == 1 }?.subtasks.map(\.id), [99])
        XCTAssertEqual(appState.tasks.first { $0.id == 99 }?.parentTasks.map(\.id), [1])
    }

    @MainActor
    func testCreateSubtaskRejectsBlankTitle() async {
        let appState = await makeMockedAppState()
        MockURLProtocol.requestHandler = { request in
            XCTFail("Blank subtask title must not hit the network")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        let success = await appState.createSubtask(title: "   ", parent: makeTask(id: 1))
        XCTAssertFalse(success)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }
}
