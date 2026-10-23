import XCTest
@testable import mDone

/// Team features (#272): assigning people to tasks, keeping assignees set
/// elsewhere, and the "Assigned to me" filter.
@MainActor
final class TaskAssigneeTests: XCTestCase {
    private let alice = User(id: 3, username: "alice", name: "Alice Smith")
    private let bob = User(id: 4, username: "bob", name: "")

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: TeamFeaturesPreference.storageKey)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        UserDefaults.standard.removeObject(forKey: TeamFeaturesPreference.storageKey)
        super.tearDown()
    }

    private func makeAppState() async -> AppState {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(
            taskService: TaskService(apiClient: client),
            labelService: LabelService(apiClient: client),
            userService: UserService(apiClient: client)
        )
    }

    private func jsonBody(of request: URLRequest?) throws -> [String: Any] {
        let data = try XCTUnwrap(request.flatMap { MockURLProtocol.bodyData(from: $0) })
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func assigneeIds(in body: [String: Any]) -> [Int]? {
        (body["assignees"] as? [[String: Any]])?.compactMap { $0["id"] as? Int }
    }

    // MARK: - The setting

    func testTeamFeaturesAreOffByDefault() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: #function))
        defaults.removePersistentDomain(forName: #function)
        XCTAssertFalse(TeamFeaturesPreference.isEnabled(defaults: defaults))
        defaults.set(true, forKey: TeamFeaturesPreference.storageKey)
        XCTAssertTrue(TeamFeaturesPreference.isEnabled(defaults: defaults))
    }

    func testCurrentUserIsNotFetchedWhileTeamFeaturesAreOff() async {
        let appState = await makeAppState()
        appState.isAuthenticated = true
        MockURLProtocol.requestHandler = { _ in
            XCTFail("Personal use must not cost a request")
            return (MockURLProtocol.makeResponse(statusCode: 200), Data())
        }

        await appState.loadCurrentUserIfNeeded()

        XCTAssertNil(appState.currentUser)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testCurrentUserIsFetchedOnceTeamFeaturesAreOn() async {
        UserDefaults.standard.set(true, forKey: TeamFeaturesPreference.storageKey)
        let appState = await makeAppState()
        appState.isAuthenticated = true
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                #"{"id": 4, "username": "bob", "name": ""}"#.data(using: .utf8)!
            )
        }

        await appState.teamFeaturesDidChange(enabled: true)
        await appState.loadCurrentUserIfNeeded()

        XCTAssertEqual(appState.currentUser?.id, 4)
        XCTAssertEqual(MockURLProtocol.capturedRequests.map(\.url?.path), ["/api/v1/user"])
    }

    func testTurningTeamFeaturesOffClearsTheAssigneeFilter() async {
        let appState = await makeAppState()
        appState.advancedFilter.assigneeId = 4

        await appState.teamFeaturesDidChange(enabled: false)

        XCTAssertNil(appState.advancedFilter.assigneeId)
        XCTAssertFalse(appState.advancedFilter.isActive)
    }

    // MARK: - Keeping assignees through updates

    func testUpdatesCarryTheTasksAssigneesForward() {
        // Vikunja's task update removes every assignee the body leaves out,
        // so completing a task used to unassign it for the whole team.
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.assignees = [alice, bob]

        let request = TaskUpdateRequest(done: true).preservingExistingValues(from: task)

        XCTAssertEqual(request.assignees, [alice, bob])
    }

    func testAnExplicitAssigneeListWinsOverTheTasks() {
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.assignees = [alice, bob]

        let request = TaskUpdateRequest(assignees: []).preservingExistingValues(from: task)

        XCTAssertEqual(request.assignees, [])
    }

    func testAssigneesAreEncodedAsIdsOnly() throws {
        let request = TaskUpdateRequest(assignees: [alice, bob])
        let data = try JSONEncoder().encode(request)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let assignees = try XCTUnwrap(body["assignees"] as? [[String: Any]])
        XCTAssertEqual(assignees.compactMap { $0["id"] as? Int }, [3, 4])
        XCTAssertEqual(assignees.map(\.keys.count), [1, 1], "Names and emails stay off the wire")
    }

    func testARequestWithoutAssigneesLeavesTheKeyOut() throws {
        let data = try JSONEncoder().encode(TaskUpdateRequest(done: true))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(body["assignees"])
    }

    func testCompletingATaskKeepsItsAssigneesOnTheServerAndOnScreen() async throws {
        let appState = await makeAppState()
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.assignees = [alice, bob]
        appState.tasks = [task]
        // What Vikunja really echoes: the ids with blank names.
        let response = #"""
        {"id": 1, "title": "x", "done": true, "priority": 0, "project_id": 1,
         "assignees": [{"id": 3, "username": "", "name": ""}, {"id": 4, "username": "", "name": ""}]}
        """#
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), response.data(using: .utf8)!)
        }

        await appState.toggleTaskDone(task)

        let body = try jsonBody(of: MockURLProtocol.capturedRequests.last)
        XCTAssertEqual(assigneeIds(in: body), [3, 4])
        XCTAssertTrue(appState.tasks[0].done)
        XCTAssertEqual(appState.tasks[0].assignees?.map(\.displayName), ["Alice Smith", "bob"])
    }

    func testMergeRestoresTheUsersThatWereSent() {
        var existing = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        existing.assignees = [alice]
        var response = existing
        response.assignees = [User(id: 3, username: "", name: "")]

        let merged = AppState.preservingSchedule(
            existing: existing,
            response: response,
            request: TaskUpdateRequest(assignees: [alice])
        )

        XCTAssertEqual(merged.assignees?.first?.displayName, "Alice Smith")
    }

    // MARK: - Setting assignees

    func testSetAssigneesReplacesThemThroughTheBulkEndpoint() async throws {
        let appState = await makeAppState()
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.assignees = [bob]
        appState.tasks = [task]
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                #"{"assignees": [{"id": 3}]}"#.data(using: .utf8)!
            )
        }

        let saved = await appState.setAssignees([alice], on: task)

        XCTAssertTrue(saved)
        let request = MockURLProtocol.capturedRequests.last
        XCTAssertEqual(request?.url?.path, "/api/v1/tasks/1/assignees/bulk")
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(try assigneeIds(in: jsonBody(of: request)), [3])
        XCTAssertEqual(appState.tasks[0].assignees, [alice])
        XCTAssertEqual(appState.tasks[0].assignees?.first?.displayName, "Alice Smith")
    }

    func testAFailedAssignmentLeavesTheTaskAsItWas() async {
        let appState = await makeAppState()
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.assignees = [bob]
        appState.tasks = [task]
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 400, url: request.url),
                #"{"code": 7003, "message": "This user does not have access to the project."}"#.data(using: .utf8)!
            )
        }

        let saved = await appState.setAssignees([alice], on: task)

        XCTAssertFalse(saved)
        XCTAssertEqual(appState.tasks[0].assignees, [bob])
        XCTAssertNotNil(appState.activeError)
    }

    func testCreateAssignsAfterTheTaskExists() async throws {
        let appState = await makeAppState()
        MockURLProtocol.requestHandler = { request in
            let body = request.url?.path == "/api/v1/projects/1/tasks"
                ? #"{"id": 9, "title": "New", "done": false, "priority": 0, "project_id": 1}"#
                : #"{"assignees": [{"id": 3}]}"#
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), body.data(using: .utf8)!)
        }

        let created = await appState.createTask(title: "New", projectId: 1, assignees: [alice])

        let requests = MockURLProtocol.capturedRequests
        XCTAssertEqual(requests.map(\.url?.path), ["/api/v1/projects/1/tasks", "/api/v1/tasks/9/assignees/bulk"])
        XCTAssertNil(try jsonBody(of: requests.first)["assignees"], "One inaccessible user would refuse the create")
        XCTAssertEqual(try assigneeIds(in: jsonBody(of: requests.last)), [3])
        XCTAssertEqual(created?.assignees, [alice])
        XCTAssertEqual(appState.tasks.first?.assignees, [alice])
    }

    func testCreateWithoutAssigneesMakesNoAssignRequest() async {
        let appState = await makeAppState()
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                #"{"id": 9, "title": "New", "done": false, "priority": 0, "project_id": 1}"#.data(using: .utf8)!
            )
        }

        await appState.createTask(title: "New", projectId: 1)

        XCTAssertEqual(MockURLProtocol.capturedRequests.map(\.url?.path), ["/api/v1/projects/1/tasks"])
    }

    func testAssignableUsersComeFromTheProjectUsersEndpointSortedByName() async {
        let appState = await makeAppState()
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                #"[{"id": 4, "username": "zed", "name": ""}, {"id": 3, "username": "amy", "name": "Amy"}]"#
                    .data(using: .utf8)!
            )
        }

        let users = await appState.loadAssignableUsers(projectId: 12)

        XCTAssertEqual(MockURLProtocol.capturedRequests.last?.url?.path, "/api/v1/projects/12/projectusers")
        XCTAssertEqual(users.map(\.displayName), ["Amy", "zed"])
        XCTAssertEqual(appState.assignableUsers[12]?.map(\.id), [3, 4])
    }

    // MARK: - Offline queue

    func testQueuedEditKeepsAssigneesAndOlderRowsStillDecode() throws {
        let edit = QueuedTaskEdit(from: TaskUpdateRequest(assignees: [alice]))
        XCTAssertEqual(edit.request.assignees, [alice])

        let task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        XCTAssertEqual(edit.applied(to: task).assignees, [alice])

        let newer = QueuedTaskEdit(from: TaskUpdateRequest(assignees: [bob]))
        XCTAssertEqual(edit.coalesced(with: newer).assignees, [bob])
        XCTAssertEqual(edit.coalesced(with: QueuedTaskEdit(from: TaskUpdateRequest(done: true))).assignees, [alice])

        let legacy = try JSONDecoder().decode(
            QueuedTaskEdit.self,
            from: XCTUnwrap(#"{"done": true}"#.data(using: .utf8))
        )
        XCTAssertNil(legacy.assignees)
    }

    func testCacheRoundTripsAssignees() {
        var task = VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)
        task.assignees = [alice]
        XCTAssertEqual(CachedTask(from: task).toVTask().assignees?.first?.displayName, "Alice Smith")
    }

    // MARK: - Filter

    func testAssignedToMeFilter() {
        var mine = VTask(id: 1, title: "mine", done: false, priority: 0, projectId: 1)
        mine.assignees = [alice, bob]
        var theirs = VTask(id: 2, title: "theirs", done: false, priority: 0, projectId: 1)
        theirs.assignees = [alice]
        let nobody = VTask(id: 3, title: "nobody", done: false, priority: 0, projectId: 1)

        var filter = AdvancedTaskFilter()
        XCTAssertFalse(filter.isActive)
        filter.assigneeId = bob.id

        XCTAssertTrue(filter.isActive)
        XCTAssertEqual(filter.apply(to: [mine, theirs, nobody]).map(\.id), [1])
    }

    // MARK: - Display

    func testDisplayNameSkipsVikunjasEmptyName() {
        XCTAssertEqual(bob.displayName, "bob")
        XCTAssertEqual(alice.displayName, "Alice Smith")
        XCTAssertEqual(User(id: 9, username: "", name: "").displayName, String(localized: "Unknown"))
    }

    func testInitials() {
        XCTAssertEqual(alice.initials, "AS")
        XCTAssertEqual(bob.initials, "B")
        XCTAssertEqual(User(id: 9, username: "jane.doe").initials, "JD")
    }
}
