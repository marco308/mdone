import XCTest
@testable import mDone

@MainActor
final class CurrentTasksTests: XCTestCase {
    private let currentLabelIdKey = "currentLabelId"

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: currentLabelIdKey)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: currentLabelIdKey)
        super.tearDown()
    }

    /// AppState whose task and label services both talk to `MockURLProtocol`.
    private func makeAppState() async -> AppState {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(
            taskService: TaskService(apiClient: client),
            labelService: LabelService(apiClient: client)
        )
    }

    private func currentLabel(id: Int64 = 3) -> VLabel {
        VLabel(id: id, title: "Current")
    }

    // MARK: - Resolution & queries (no network)

    func testCurrentLabelResolvesByTitleCaseInsensitively() {
        let appState = AppState()
        appState.labels = [VLabel(id: 4, title: "Other"), VLabel(id: 3, title: "current")]
        XCTAssertEqual(appState.currentLabel?.id, 3)
    }

    func testCurrentLabelNilWhenNoMatch() {
        let appState = AppState()
        appState.labels = [VLabel(id: 4, title: "Other")]
        XCTAssertNil(appState.currentLabel)
    }

    func testIsCurrentReflectsLabelPresence() {
        let appState = AppState()
        appState.labels = [currentLabel()]
        var marked = VTask(id: 1, title: "Marked", done: false, priority: 0, projectId: 1)
        marked.labels = [currentLabel()]
        let unmarked = VTask(id: 2, title: "Unmarked", done: false, priority: 0, projectId: 1)

        XCTAssertTrue(appState.isCurrent(marked))
        XCTAssertFalse(appState.isCurrent(unmarked))
    }

    func testCurrentTasksExcludesDoneAndUnlabeledAndSortsByUpdatedDescending() {
        let appState = AppState()
        appState.labels = [currentLabel()]

        var older = VTask(id: 1, title: "Older", done: false, priority: 0, projectId: 1)
        older.labels = [currentLabel()]
        older.updated = Date(timeIntervalSince1970: 100)

        var newer = VTask(id: 2, title: "Newer", done: false, priority: 0, projectId: 1)
        newer.labels = [currentLabel()]
        newer.updated = Date(timeIntervalSince1970: 200)

        var done = VTask(id: 3, title: "Done", done: true, priority: 0, projectId: 1)
        done.labels = [currentLabel()]

        let unlabeled = VTask(id: 4, title: "Unlabeled", done: false, priority: 0, projectId: 1)

        appState.tasks = [older, newer, done, unlabeled]

        XCTAssertEqual(appState.currentTasks.map(\.id), [2, 1], "Current tasks: not-done, labeled, newest first")
    }

    func testCurrentTasksEmptyWhenNoLabelExists() {
        let appState = AppState()
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.labels = [VLabel(id: 9, title: "Current")] // label not in appState.labels
        appState.tasks = [task]
        XCTAssertTrue(appState.currentTasks.isEmpty)
    }

    // MARK: - toggleCurrent

    func testToggleCurrentAddsLabelOptimistically() async {
        let appState = await makeAppState()
        appState.labels = [currentLabel()]
        let task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), #"{"label_id": 3}"#.data(using: .utf8)!)
        }

        await appState.toggleCurrent(task)

        XCTAssertTrue(appState.isCurrent(appState.tasks[0]))
        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.url?.path, "/api/v1/tasks/1/labels")
        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.httpMethod, "PUT")
    }

    func testToggleCurrentRemovesLabel() async {
        let appState = await makeAppState()
        appState.labels = [currentLabel()]
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.labels = [currentLabel()]
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), #"{"message": "ok"}"#.data(using: .utf8)!)
        }

        await appState.toggleCurrent(task)

        XCTAssertFalse(appState.isCurrent(appState.tasks[0]))
        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.httpMethod, "DELETE")
    }

    func testToggleCurrentRevertsOnFailure() async {
        let appState = await makeAppState()
        appState.labels = [currentLabel()]
        let task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        appState.tasks = [task]

        // 400 fails fast (no retry/backoff).
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 400, url: request.url),
                #"{"message": "bad"}"#.data(using: .utf8)!
            )
        }

        await appState.toggleCurrent(task)

        XCTAssertFalse(appState.isCurrent(appState.tasks[0]), "A failed add must revert the optimistic label")
    }

    func testToggleCurrentCreatesLabelWhenMissing() async {
        let appState = await makeAppState()
        appState.labels = [] // no Current label yet
        let task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/api/v1/labels" {
                let json = #"{"id": 9, "title": "Current"}"#.data(using: .utf8)!
                return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), json)
            }
            return (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                #"{"label_id": 9}"#.data(using: .utf8)!
            )
        }

        await appState.toggleCurrent(task)

        XCTAssertNotNil(appState.labels.first(where: { $0.id == 9 }), "The Current label is created and cached")
        XCTAssertTrue(appState.isCurrent(appState.tasks[0]))
        XCTAssertEqual(
            UserDefaults.standard.object(forKey: currentLabelIdKey) as? NSNumber,
            NSNumber(value: 9),
            "The created label id is persisted"
        )
    }

    // MARK: - setProgress

    func testSetProgressUpdatesAndClamps() async {
        let appState = await makeAppState()
        let task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            let json = #"{"id": 1, "title": "x", "done": false, "priority": 0, "project_id": 1}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        await appState.setProgress(task, percent: 1.5)

        XCTAssertEqual(appState.tasks[0].percentDone, 1.0, "Progress is clamped to 0...1")
    }

    func testSetProgressRevertsOnFailure() async {
        let appState = await makeAppState()
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.percentDone = 0.2
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 400, url: request.url),
                #"{"message": "bad"}"#.data(using: .utf8)!
            )
        }

        await appState.setProgress(task, percent: 0.8)

        XCTAssertEqual(appState.tasks[0].percentDone, 0.2, "A failed progress update reverts to the prior value")
    }

    func testSetProgressPreservesCurrentLabel() async {
        // The Current label must survive a progress update so the task doesn't
        // vanish from the Current section after a quick percentage bump.
        let appState = await makeAppState()
        appState.labels = [currentLabel()]
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.labels = [currentLabel()]
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            // Server response omits labels entirely.
            let json = #"{"id": 1, "title": "x", "done": false, "priority": 0, "project_id": 1}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        await appState.setProgress(task, percent: 0.5)

        XCTAssertEqual(appState.tasks[0].percentDone, 0.5)
        XCTAssertTrue(appState.isCurrent(appState.tasks[0]), "Progress update must not drop the Current label")
    }

    // MARK: - Request encoding

    func testTaskUpdateRequestEncodesPercentDoneAsSnakeCase() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(TaskUpdateRequest(percentDone: 0.5))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertTrue(json.contains("\"percent_done\":0.5"), "percentDone encodes as percent_done")
        XCTAssertFalse(json.contains("\"title\""), "Unset fields stay omitted")
    }

    // MARK: - Label-drop regression (edit makes a Current task vanish)

    func testPreservingRelationsCarriesLabelsForwardWhenResponseNil() {
        var existing = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        existing.labels = [currentLabel()]
        var response = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        response.labels = nil

        let merged = AppState.preservingRelations(existing: existing, response: response)
        XCTAssertEqual(merged.labels?.map(\.id), [3], "Nil response labels are filled from the existing task")
    }

    func testPreservingRelationsKeepsNonNilResponseLabels() {
        var existing = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        existing.labels = [currentLabel()]
        var response = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        response.labels = []

        let merged = AppState.preservingRelations(existing: existing, response: response)
        XCTAssertEqual(merged.labels?.count, 0, "A non-nil response value is authoritative")
    }

    /// Regression: Vikunja's update response returns labels:null, so editing a
    /// Current task (e.g. its progress) used to drop the Current label locally,
    /// making the task vanish from the Current section until the next refresh.
    func testUpdateTaskKeepsTaskInCurrentSection() async {
        let appState = await makeAppState()
        appState.labels = [currentLabel()]
        var task = VTask(id: 1, title: "Roadmap", done: false, priority: 0, projectId: 1)
        task.labels = [currentLabel()]
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            // Vikunja echoes percent_done but returns labels: null.
            let json = #"{"id": 1, "title": "Roadmap", "done": false, "priority": 0, "project_id": 1, "percent_done": 0.5, "labels": null}"#
                .data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        await appState.updateTask(id: 1, request: TaskUpdateRequest(percentDone: 0.5))

        XCTAssertEqual(appState.tasks[0].percentDone, 0.5, "Progress is applied")
        XCTAssertTrue(appState.isCurrent(appState.tasks[0]), "The Current label survives the edit")
        XCTAssertEqual(appState.currentTasks.map(\.id), [1], "Task stays in the Current section after editing")
    }
}
