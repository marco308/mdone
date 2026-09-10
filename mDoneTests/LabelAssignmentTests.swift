import XCTest
@testable import mDone

/// Assigning and removing arbitrary labels from the task detail picker, and
/// creating labels from it (issue #4). The "Current" label has its own tests
/// in `CurrentTasksTests`; these cover the general path it now shares.
@MainActor
final class LabelAssignmentTests: XCTestCase {
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
        return AppState(
            taskService: TaskService(apiClient: client),
            labelService: LabelService(apiClient: client)
        )
    }

    private let urgent = VLabel(id: 7, title: "Urgent", hexColor: "ff4444")
    private let home = VLabel(id: 8, title: "Home", hexColor: "4772fa")

    private func respondOK(_ body: String = #"{"message": "ok"}"#) {
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), body.data(using: .utf8)!)
        }
    }

    private func respondBadRequest() {
        // 400 fails fast (no retry/backoff).
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 400, url: request.url),
                #"{"message": "bad"}"#.data(using: .utf8)!
            )
        }
    }

    private func jsonBody(of request: URLRequest?) throws -> [String: Any] {
        let data = try XCTUnwrap(request.flatMap { MockURLProtocol.bodyData(from: $0) })
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - toggleLabel

    func testToggleLabelAddsThroughTheTaskLabelsEndpoint() async throws {
        let appState = await makeAppState()
        appState.labels = [urgent]
        let task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        appState.tasks = [task]
        respondOK(#"{"label_id": 7}"#)

        let stuck = await appState.toggleLabel(urgent, on: task)

        XCTAssertTrue(stuck)
        XCTAssertTrue(appState.hasLabel(urgent, on: task))
        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [7])
        let request = MockURLProtocol.capturedRequests.last
        XCTAssertEqual(request?.url?.path, "/api/v1/tasks/1/labels")
        XCTAssertEqual(request?.httpMethod, "PUT")
        XCTAssertEqual(try jsonBody(of: request)["label_id"] as? Int, 7)
    }

    func testToggleLabelRemovesThroughTheDeleteEndpoint() async {
        let appState = await makeAppState()
        appState.labels = [urgent]
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.labels = [urgent]
        appState.tasks = [task]
        respondOK()

        let stuck = await appState.toggleLabel(urgent, on: task)

        XCTAssertTrue(stuck)
        XCTAssertFalse(appState.hasLabel(urgent, on: task))
        XCTAssertEqual(appState.tasks[0].labels, [])
        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.url?.path, "/api/v1/tasks/1/labels/7")
        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.httpMethod, "DELETE")
    }

    func testToggleLabelJudgesPresenceFromTheLiveCopyNotTheSnapshot() async {
        // A detail sheet holds the task as it was when opened. If the label
        // was added since (say, from the picker moments ago), toggling from
        // that stale snapshot must remove it, not add it a second time.
        let appState = await makeAppState()
        appState.labels = [urgent]
        let snapshot = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        var live = snapshot
        live.labels = [urgent]
        appState.tasks = [live]
        respondOK()

        await appState.toggleLabel(urgent, on: snapshot)

        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.httpMethod, "DELETE")
        XCTAssertFalse(appState.hasLabel(urgent, on: snapshot))
    }

    func testToggleLabelLeavesOtherLabelsAlone() async {
        let appState = await makeAppState()
        appState.labels = [urgent, home]
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.labels = [home]
        appState.tasks = [task]
        respondOK(#"{"label_id": 7}"#)

        await appState.toggleLabel(urgent, on: task)
        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [8, 7], "Adding appends, keeping what was there")

        respondOK()
        await appState.toggleLabel(urgent, on: task)
        XCTAssertEqual(appState.tasks[0].labels?.map(\.id), [8], "Removing takes only the toggled label")
    }

    func testToggleLabelRevertsAndReportsAFailure() async {
        let appState = await makeAppState()
        appState.labels = [urgent]
        let task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        appState.tasks = [task]
        respondBadRequest()

        let stuck = await appState.toggleLabel(urgent, on: task)

        XCTAssertFalse(stuck)
        XCTAssertFalse(appState.hasLabel(urgent, on: task), "A failed add must revert the optimistic label")
        XCTAssertNotNil(appState.errorMessage, "The failure is surfaced to the user")
    }

    func testToggleLabelRevertsAFailedRemoval() async {
        let appState = await makeAppState()
        appState.labels = [urgent]
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.labels = [urgent]
        appState.tasks = [task]
        respondBadRequest()

        let stuck = await appState.toggleLabel(urgent, on: task)

        XCTAssertFalse(stuck)
        XCTAssertTrue(appState.hasLabel(urgent, on: task), "A failed removal must put the label back")
    }

    // MARK: - createLabel

    func testCreateLabelPutsToLabelsAndKeepsTheResult() async throws {
        let appState = await makeAppState()
        appState.labels = [urgent]
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id": 11, "title": "Home", "hex_color": "4772FA"}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), json)
        }

        let created = await appState.createLabel(title: "  Home ", hexColor: "#4772FA")

        XCTAssertEqual(created?.id, 11)
        XCTAssertEqual(appState.labels.map(\.id), [7, 11], "The new label joins the loaded list for the picker")
        let request = MockURLProtocol.capturedRequests.last
        XCTAssertEqual(request?.url?.path, "/api/v1/labels")
        XCTAssertEqual(request?.httpMethod, "PUT")
        let body = try jsonBody(of: request)
        XCTAssertEqual(body["title"] as? String, "Home", "The title is trimmed")
        XCTAssertEqual(body["hex_color"] as? String, "4772FA", "The colour is sent without the leading #")
    }

    func testCreateLabelSendsNoColourWhenNoneWasChosen() async throws {
        let appState = await makeAppState()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id": 12, "title": "Plain"}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), json)
        }

        _ = await appState.createLabel(title: "Plain", hexColor: "")

        let body = try jsonBody(of: MockURLProtocol.capturedRequests.last)
        XCTAssertNil(body["hex_color"], "An empty swatch choice is omitted, not sent as an empty string")
    }

    func testCreateLabelRejectsABlankTitleWithoutARequest() async {
        let appState = await makeAppState()
        respondOK()

        let created = await appState.createLabel(title: "   ")

        XCTAssertNil(created)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testCreateLabelReturnsNilAndReportsAFailure() async {
        let appState = await makeAppState()
        respondBadRequest()

        let created = await appState.createLabel(title: "Home")

        XCTAssertNil(created)
        XCTAssertTrue(appState.labels.isEmpty)
        XCTAssertNotNil(appState.errorMessage)
    }
}
