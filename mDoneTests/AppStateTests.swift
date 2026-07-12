import XCTest
@testable import mDone

@MainActor
final class AppStateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    /// Builds an `AppState` whose `TaskService` talks to `MockURLProtocol`,
    /// so tests can drive `undoLastCompletion()`'s network path deterministically.
    private func makeMockedAppState() async -> AppState {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(taskService: TaskService(apiClient: client))
    }

    /// Builds an `AppState` whose `ProjectService` talks to `MockURLProtocol`,
    /// so project create/edit/archive/delete paths can be driven deterministically.
    private func makeProjectMockedAppState() async -> AppState {
        let client = APIClient(session: MockURLProtocol.mockSession())
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(projectService: ProjectService(apiClient: client))
    }

    // MARK: - Project Collapse State

    func testProjectsExpandedByDefault() async {
        UserDefaults.standard.removeObject(forKey: "collapsedProjectIDs")
        let appState = await makeProjectMockedAppState()
        XCTAssertTrue(appState.isProjectExpanded(42))
    }

    func testCollapseAndExpandProjectPersists() async {
        UserDefaults.standard.removeObject(forKey: "collapsedProjectIDs")
        let appState = await makeProjectMockedAppState()

        appState.setProjectExpanded(false, for: 42)
        XCTAssertFalse(appState.isProjectExpanded(42))
        XCTAssertTrue(appState.collapsedProjectIDs.contains(42))

        // A fresh AppState reads the persisted collapse set back.
        let reloaded = await makeProjectMockedAppState()
        XCTAssertFalse(reloaded.isProjectExpanded(42))

        appState.setProjectExpanded(true, for: 42)
        XCTAssertTrue(appState.isProjectExpanded(42))
        XCTAssertFalse(appState.collapsedProjectIDs.contains(42))
        UserDefaults.standard.removeObject(forKey: "collapsedProjectIDs")
    }

    // MARK: - Project Mutations

    func testCreateProjectAppendsToProjects() async {
        let appState = await makeProjectMockedAppState()
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id": 100, "title": "New", "is_archived": false, "is_favorite": false}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), json)
        }

        await appState.createProject(title: "New")
        XCTAssertEqual(appState.projects.map(\.id), [100])
        XCTAssertEqual(appState.projects.first?.title, "New")
    }

    func testCreateProjectIgnoresBlankTitle() async {
        let appState = await makeProjectMockedAppState()
        MockURLProtocol.requestHandler = { request in
            XCTFail("Blank title must not hit the network")
            return (MockURLProtocol.makeResponse(statusCode: 201, url: request.url), Data())
        }

        await appState.createProject(title: "   ")
        XCTAssertTrue(appState.projects.isEmpty)
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testUpdateProjectReplacesInPlace() async {
        let appState = await makeProjectMockedAppState()
        appState.projects = [Project(id: 5, title: "Old", isArchived: false, isFavorite: false)]
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id": 5, "title": "Updated", "is_archived": false, "is_favorite": true}"#.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        await appState.updateProject(
            appState.projects[0], title: "Updated", description: "", hexColor: "", isFavorite: true
        )
        XCTAssertEqual(appState.projects.count, 1)
        XCTAssertEqual(appState.projects.first?.title, "Updated")
        XCTAssertEqual(appState.projects.first?.isFavorite, true)
    }

    func testArchiveProjectMovesToArchivedList() async {
        let appState = await makeProjectMockedAppState()
        appState.projects = [Project(id: 8, title: "ToArchive", isArchived: false, isFavorite: false)]
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id": 8, "title": "ToArchive", "is_archived": true, "is_favorite": false}"#
                .data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        await appState.archiveProject(appState.projects[0])
        XCTAssertTrue(appState.projects.isEmpty, "Archived project should leave the active list")
        XCTAssertEqual(appState.archivedProjects.map(\.id), [8])
    }

    func testUnarchiveProjectMovesToActiveList() async {
        let appState = await makeProjectMockedAppState()
        appState.archivedProjects = [Project(id: 8, title: "Archived", isArchived: true, isFavorite: false)]
        // Server may echo is_archived inconsistently; AppState trusts the requested state.
        MockURLProtocol.requestHandler = { request in
            let json = #"{"id": 8, "title": "Archived", "is_archived": false, "is_favorite": false}"#
                .data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        await appState.unarchiveProject(appState.archivedProjects[0])
        XCTAssertTrue(appState.archivedProjects.isEmpty)
        XCTAssertEqual(appState.projects.map(\.id), [8])
    }

    func testDeleteProjectRemovesProjectAndItsTasks() async {
        let appState = await makeProjectMockedAppState()
        appState.projects = [Project(id: 3, title: "Doomed", isArchived: false, isFavorite: false)]
        appState.tasks = [
            VTask(id: 1, title: "T1", done: false, priority: 0, projectId: 3),
            VTask(id: 2, title: "T2", done: false, priority: 0, projectId: 99),
        ]
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), #"{"message":"ok"}"#.data(using: .utf8)!)
        }

        await appState.deleteProject(appState.projects[0])
        XCTAssertTrue(appState.projects.isEmpty)
        XCTAssertEqual(appState.tasks.map(\.id), [2], "Only the deleted project's tasks are removed locally")
    }

    func testDeleteProjectCascadesToDescendantSubprojects() async {
        let appState = await makeProjectMockedAppState()
        // 3 (parent) -> 4 (child) -> 5 (grandchild); 9 is unrelated.
        appState.projects = [
            Project(id: 3, title: "Parent"),
            Project(id: 4, title: "Child", parentProjectId: 3),
            Project(id: 5, title: "Grandchild", parentProjectId: 4),
            Project(id: 9, title: "Unrelated"),
        ]
        appState.tasks = [
            VTask(id: 1, title: "t-parent", done: false, priority: 0, projectId: 3),
            VTask(id: 2, title: "t-grandchild", done: false, priority: 0, projectId: 5),
            VTask(id: 3, title: "t-unrelated", done: false, priority: 0, projectId: 9),
        ]
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), #"{"message":"ok"}"#.data(using: .utf8)!)
        }

        await appState.deleteProject(appState.projects[0]) // delete Parent (3)
        XCTAssertEqual(
            appState.projects.map(\.id).sorted(),
            [9],
            "Parent and all descendants are removed; unrelated kept"
        )
        XCTAssertEqual(appState.tasks.map(\.id).sorted(), [3], "Tasks of the parent and its descendants are removed")
    }

    func testDeleteProjectGuardsPseudoProject() async {
        let appState = await makeProjectMockedAppState()
        let pseudo = Project(id: -1, title: "Favorites")
        appState.projects = [pseudo]
        MockURLProtocol.requestHandler = { request in
            XCTFail("Pseudo-projects (id <= 0) must never hit the delete endpoint")
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data())
        }

        await appState.deleteProject(pseudo)
        XCTAssertEqual(appState.projects.count, 1, "Pseudo-project should remain")
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testFetchArchivedProjectsKeepsOnlyArchived() async {
        let appState = await makeProjectMockedAppState()
        MockURLProtocol.requestHandler = { request in
            // Vikunja returns active AND archived projects when include-archived is set.
            let json = """
            [
                {"id": 1, "title": "Active", "is_archived": false},
                {"id": 2, "title": "Archived", "is_archived": true}
            ]
            """.data(using: .utf8)!
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), json)
        }

        await appState.fetchArchivedProjects()
        XCTAssertEqual(appState.archivedProjects.map(\.id), [2])
    }

    // MARK: - uniquedById

    func testUniquedByIdRemovesDuplicates() {
        let tasks = [
            VTask(id: 1, title: "First", done: false, priority: 0, projectId: 10),
            VTask(id: 2, title: "Second", done: false, priority: 0, projectId: 10),
            VTask(id: 1, title: "First (dup)", done: false, priority: 0, projectId: 10),
            VTask(id: 3, title: "Third", done: false, priority: 0, projectId: 10),
        ]

        let unique = AppState.uniquedById(tasks)

        XCTAssertEqual(unique.map(\.id), [1, 2, 3], "Should preserve order and keep the first occurrence")
        XCTAssertEqual(unique[0].title, "First", "Should keep the first occurrence, not a later duplicate")
    }

    func testUniquedByIdPreservesOrderWhenAllUnique() {
        let tasks = [
            VTask(id: 5, title: "A", done: false, priority: 0, projectId: 10),
            VTask(id: 3, title: "B", done: false, priority: 0, projectId: 10),
            VTask(id: 7, title: "C", done: false, priority: 0, projectId: 10),
        ]

        let unique = AppState.uniquedById(tasks)

        XCTAssertEqual(unique.map(\.id), [5, 3, 7])
    }

    func testUniquedByIdEmpty() {
        XCTAssertEqual(AppState.uniquedById([]).count, 0)
    }

    // MARK: - Calendar selection (#69)

    func testCalendarSelectionDidChangeBumpsFilterToken() async {
        let appState = AppState()
        let before = appState.calendarFilterToken
        await appState.calendarSelectionDidChange()
        XCTAssertNotEqual(
            appState.calendarFilterToken,
            before,
            "Toggling a calendar must change the token so calendar views re-query"
        )
    }

    func testCalendarSelectionTokenChangesEachCall() async {
        let appState = AppState()
        await appState.calendarSelectionDidChange()
        let first = appState.calendarFilterToken
        await appState.calendarSelectionDidChange()
        XCTAssertNotEqual(appState.calendarFilterToken, first)
    }

    // MARK: - tasksForProject with duplicate-cache regression (issue #54)

    /// Reproduces the crash that issue #54 reported. Before the fix, `tasksForProject`
    /// fed the cached task list (which can contain duplicate ids when Vikunja's
    /// view-tasks endpoint returns the same task more than once) into
    /// `Dictionary(uniqueKeysWithValues:)`, which traps with a `_MergeError` and
    /// brings down the whole UI.
    func testTasksForProjectDoesNotCrashWithDuplicateCache() {
        let projectId: Int64 = 99
        let appState = AppState()

        appState.tasks = [
            VTask(id: 1, title: "A", done: false, priority: 0, projectId: projectId),
            VTask(id: 2, title: "B", done: false, priority: 0, projectId: projectId),
            VTask(id: 3, title: "C", done: false, priority: 0, projectId: projectId),
        ]

        // Simulate the bad cache state Vikunja can produce: id 1 appears twice.
        appState.projectTaskCache[projectId] = [
            VTask(id: 1, title: "A", done: false, priority: 0, projectId: projectId),
            VTask(id: 2, title: "B", done: false, priority: 0, projectId: projectId),
            VTask(id: 3, title: "C", done: false, priority: 0, projectId: projectId),
            VTask(id: 1, title: "A (dup row)", done: false, priority: 0, projectId: projectId),
        ]

        // Before the fix this call traps. After the fix it returns the three tasks
        // ordered by their first appearance in the cache.
        let result = appState.tasksForProject(projectId)

        XCTAssertEqual(result.map(\.id), [1, 2, 3])
    }

    func testTasksForProjectOrdersFromCachePosition() {
        let projectId: Int64 = 42
        let appState = AppState()

        appState.tasks = [
            VTask(id: 10, title: "A", done: false, priority: 0, projectId: projectId),
            VTask(id: 20, title: "B", done: false, priority: 0, projectId: projectId),
            VTask(id: 30, title: "C", done: false, priority: 0, projectId: projectId),
        ]

        // Cache order is reversed compared to the canonical tasks array.
        appState.projectTaskCache[projectId] = [
            VTask(id: 30, title: "C", done: false, priority: 0, projectId: projectId),
            VTask(id: 20, title: "B", done: false, priority: 0, projectId: projectId),
            VTask(id: 10, title: "A", done: false, priority: 0, projectId: projectId),
        ]

        XCTAssertEqual(appState.tasksForProject(projectId).map(\.id), [30, 20, 10])
    }

    func testTasksForProjectExcludesDoneTasks() {
        let projectId: Int64 = 7
        let appState = AppState()

        appState.tasks = [
            VTask(id: 1, title: "Open", done: false, priority: 0, projectId: projectId),
            VTask(id: 2, title: "Done", done: true, priority: 0, projectId: projectId),
            VTask(id: 3, title: "Other project", done: false, priority: 0, projectId: 999),
        ]

        XCTAssertEqual(appState.tasksForProject(projectId).map(\.id), [1])
    }

    // MARK: - Session expiry vs logout (issue #80)

    func testExpireSessionKeepsServerURL() async {
        let auth = AuthService.shared
        auth.clearAll()
        defer { auth.clearAll() }

        auth.saveServerURL("https://vikunja.example.com")
        auth.saveToken("jwt-old")
        auth.saveRefreshToken("refresh-old")

        let appState = AppState()
        appState.isAuthenticated = true
        appState.tasks = [VTask(id: 1, title: "x", done: false, priority: 0, projectId: 1)]

        await appState.expireSession()

        XCTAssertFalse(appState.isAuthenticated, "Session expiry must flip auth state back to logged-out")
        XCTAssertTrue(appState.tasks.isEmpty, "Session expiry should wipe in-memory data")
        XCTAssertEqual(
            auth.getServerURL(),
            "https://vikunja.example.com",
            "Server URL must survive session expiry so the login screen can prefill it (issue #80)"
        )
        XCTAssertNil(auth.getToken(), "Stale access token must be removed")
        XCTAssertNil(auth.getRefreshToken(), "Stale refresh token must be removed")
    }

    func testRegisterAPIClientHandlersIsIdempotent() async {
        let appState = AppState()
        // Should be safe to call multiple times — second pass becomes a no-op.
        await appState.registerAPIClientHandlers()
        await appState.registerAPIClientHandlers()
        await appState.registerAPIClientHandlers()
        // If this hangs or crashes the test fails; the contract is just that
        // repeated calls don't accumulate handlers or block.
    }

    func testLogoutWipesEverything() async {
        let auth = AuthService.shared
        auth.clearAll()
        defer { auth.clearAll() }

        auth.saveServerURL("https://vikunja.example.com")
        auth.saveToken("jwt-old")
        auth.saveRefreshToken("refresh-old")

        let appState = AppState()
        appState.isAuthenticated = true

        await appState.logout()

        XCTAssertFalse(appState.isAuthenticated)
        XCTAssertNil(
            auth.getServerURL(),
            "Explicit logout is a deliberate sign-out: server URL goes too"
        )
        XCTAssertNil(auth.getToken())
        XCTAssertNil(auth.getRefreshToken())
    }

    // MARK: - Shake-to-undo completion tracking (#82)

    func testNoUndoTargetByDefault() {
        let appState = AppState()
        XCTAssertFalse(appState.canUndoLastCompletion)
        XCTAssertNil(appState.undoableCompletionTitle)
    }

    func testRecordingCompletionMakesItUndoable() {
        let appState = AppState()
        let task = VTask(id: 7, title: "Walk the dog", done: false, priority: 0, projectId: 10)

        appState.recordCompletionForUndo(task)

        XCTAssertTrue(appState.canUndoLastCompletion)
        XCTAssertEqual(appState.undoableCompletionTitle, "Walk the dog")
        XCTAssertEqual(appState.undoableCompletion?.id, 7)
    }

    func testRecordingNewerCompletionReplacesPrevious() {
        let appState = AppState()
        appState.recordCompletionForUndo(VTask(id: 1, title: "First", done: false, priority: 0, projectId: 10))
        appState.recordCompletionForUndo(VTask(id: 2, title: "Second", done: false, priority: 0, projectId: 10))

        XCTAssertEqual(
            appState.undoableCompletion?.id,
            2,
            "Only the most recent completion is undoable"
        )
        XCTAssertEqual(appState.undoableCompletionTitle, "Second")
    }

    func testClearUndoMatchingIdResets() {
        let appState = AppState()
        appState.recordCompletionForUndo(VTask(id: 5, title: "Task", done: false, priority: 0, projectId: 10))

        appState.clearUndoIfMatches(id: 5)

        XCTAssertFalse(
            appState.canUndoLastCompletion,
            "Un-completing the same task by other means clears the undo target"
        )
    }

    func testClearUndoNonMatchingIdKeepsTarget() {
        let appState = AppState()
        appState.recordCompletionForUndo(VTask(id: 5, title: "Task", done: false, priority: 0, projectId: 10))

        appState.clearUndoIfMatches(id: 99)

        XCTAssertTrue(
            appState.canUndoLastCompletion,
            "A different task changing state must not clear the pending undo"
        )
        XCTAssertEqual(appState.undoableCompletion?.id, 5)
    }

    // MARK: - Shake-to-undo network path: undoLastCompletion() (#82)

    func testUndoRestoresTaskInPlaceOnSuccess() async {
        let appState = await makeMockedAppState()
        let task = VTask(id: 42, title: "Buy milk", done: true, priority: 1, projectId: 3)
        appState.tasks = [task]
        appState.recordCompletionForUndo(task)

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url!)
            let json = """
            {"id": 42, "title": "Buy milk", "done": false, "priority": 1, "project_id": 3}
            """
            return (response, Data(json.utf8))
        }

        await appState.undoLastCompletion()

        XCTAssertEqual(appState.tasks.count, 1, "Undo must not duplicate the already-present task")
        XCTAssertEqual(appState.tasks.first?.id, 42)
        XCTAssertEqual(appState.tasks.first?.done, false, "Undo must mark the task not-done locally")
        XCTAssertFalse(appState.canUndoLastCompletion, "A successful undo consumes the pending target")
    }

    func testUndoReinsertsTaskWhenMissingFromList() async {
        let appState = await makeMockedAppState()
        // The completed task was dropped from `tasks` by an all-tasks refresh
        // (that endpoint returns only undone tasks), so it's no longer present.
        let task = VTask(id: 7, title: "Walk the dog", done: true, priority: 0, projectId: 10)
        appState.tasks = []
        appState.recordCompletionForUndo(task)

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url!)
            let json = """
            {"id": 7, "title": "Walk the dog", "done": false, "priority": 0, "project_id": 10}
            """
            return (response, Data(json.utf8))
        }

        await appState.undoLastCompletion()

        XCTAssertEqual(appState.tasks.map(\.id), [7], "A missing task must be re-inserted, not silently lost")
        XCTAssertEqual(appState.tasks.first?.done, false)
    }

    func testUndoPreservesDueDateFromSnapshotWhenResponseOmitsIt() async {
        let appState = await makeMockedAppState()
        let due = Date(timeIntervalSince1970: 1_750_000_000)
        var task = VTask(id: 99, title: "Pay rent", done: true, priority: 2, projectId: 5)
        task.dueDate = due
        appState.tasks = [task]
        appState.recordCompletionForUndo(task)

        // The un-complete response omits due_date — the bug that put the task in
        // the wrong Inbox section. The restore must rebuild from the snapshot.
        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url!)
            let json = """
            {"id": 99, "title": "Pay rent", "done": false, "priority": 2, "project_id": 5}
            """
            return (response, Data(json.utf8))
        }

        await appState.undoLastCompletion()

        XCTAssertEqual(
            appState.tasks.first?.effectiveDueDate,
            due,
            "Undo must preserve the original due date so the task returns to its Inbox section"
        )
    }

    func testUndoKeepsTargetWhenRequestFails() async {
        let appState = await makeMockedAppState()
        let task = VTask(id: 11, title: "Flaky", done: true, priority: 0, projectId: 1)
        appState.tasks = [task]
        appState.recordCompletionForUndo(task)

        // 400 (not 5xx) so APIClient fails fast instead of retrying with backoff.
        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 400, url: request.url!)
            return (response, Data("{\"message\": \"bad request\"}".utf8))
        }

        await appState.undoLastCompletion()

        XCTAssertTrue(
            appState.canUndoLastCompletion,
            "A failed undo must keep the pending target so the user can retry"
        )
        XCTAssertEqual(appState.undoableCompletion?.id, 11)
    }

    // MARK: - Reschedule (#67)

    func testRescheduleTaskUpdatesDueDateOnSuccess() async throws {
        let appState = await makeMockedAppState()
        var task = VTask(id: 50, title: "Renew passport", done: false, priority: 1, projectId: 4)
        task.dueDate = Date(timeIntervalSince1970: 1_700_000_000)
        appState.tasks = [task]
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url!)
            // Vikunja echoes the new due date back as ISO8601.
            let iso = ISO8601DateFormatter().string(from: newDate)
            let json = """
            {"id": 50, "title": "Renew passport", "done": false, "priority": 1, \
            "project_id": 4, "due_date": "\(iso)"}
            """
            return (response, Data(json.utf8))
        }

        await appState.rescheduleTask(task, to: newDate)

        XCTAssertEqual(appState.tasks.count, 1, "Reschedule must not duplicate the task")
        XCTAssertEqual(appState.tasks.first?.id, 50)
        let resolved = try XCTUnwrap(appState.tasks.first?.effectiveDueDate)
        XCTAssertEqual(
            resolved.timeIntervalSince1970,
            newDate.timeIntervalSince1970,
            accuracy: 1,
            "Reschedule must adopt the new due date returned by the server"
        )
    }

    func testRescheduleTaskRollsBackOnFailure() async {
        let appState = await makeMockedAppState()
        let original = Date(timeIntervalSince1970: 1_700_000_000)
        var task = VTask(id: 51, title: "Book dentist", done: false, priority: 0, projectId: 2)
        task.dueDate = original
        appState.tasks = [task]
        let newDate = Date(timeIntervalSince1970: 1_760_000_000)

        // 400 (not 5xx) so APIClient fails fast instead of retrying with backoff.
        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 400, url: request.url!)
            return (response, Data("{\"message\": \"bad request\"}".utf8))
        }

        await appState.rescheduleTask(task, to: newDate)

        XCTAssertEqual(
            appState.tasks.first?.dueDate,
            original,
            "A failed reschedule must restore the original due date"
        )
    }

    // MARK: - Calm Mode (#68)

    /// Seeds a deterministic spread of due dates: overdue, due-today,
    /// upcoming, no-date, and a done-but-overdue task.
    private func seedCalmModeTasks(_ appState: AppState) throws {
        let now = Date()
        let cal = Calendar.current
        let todayEndOfDay = try XCTUnwrap(cal.date(bySettingHour: 23, minute: 59, second: 59, of: now))
        appState.tasks = [
            VTask(
                id: 1,
                title: "Overdue",
                done: false,
                dueDate: cal.date(byAdding: .day, value: -2, to: now),
                priority: 0,
                projectId: 1
            ),
            VTask(
                id: 2,
                title: "Today",
                done: false,
                dueDate: todayEndOfDay,
                priority: 0,
                projectId: 1
            ),
            VTask(
                id: 3,
                title: "Upcoming",
                done: false,
                dueDate: cal.date(byAdding: .day, value: 3, to: now),
                priority: 0,
                projectId: 1
            ),
            VTask(id: 4, title: "No date", done: false, priority: 0, projectId: 1),
            VTask(
                id: 5,
                title: "Done overdue",
                done: true,
                dueDate: cal.date(byAdding: .day, value: -3, to: now),
                priority: 0,
                projectId: 1
            ),
        ]
    }

    func testCalmModeTodayTasksUnionsOverdueAndToday() async throws {
        let appState = await makeMockedAppState()
        try seedCalmModeTasks(appState)

        let ids = appState.calmModeTodayTasks.map(\.id)
        XCTAssertEqual(ids, [1, 2], "Calm Mode's Today list is overdue + today, overdue first")
    }

    func testCalmModeTodayTasksExcludesUpcomingNoDateAndDone() async throws {
        let appState = await makeMockedAppState()
        try seedCalmModeTasks(appState)

        let ids = Set(appState.calmModeTodayTasks.map(\.id))
        XCTAssertFalse(ids.contains(3), "Upcoming tasks stay out of Today")
        XCTAssertFalse(ids.contains(4), "No-date tasks stay out of Today")
        XCTAssertFalse(ids.contains(5), "Completed tasks are never overdue/today")
    }

    func testOverdueAndTodayAreDisjointSoCalmModeHasNoDuplicates() async throws {
        let appState = await makeMockedAppState()
        try seedCalmModeTasks(appState)

        // The union relies on these two sets never overlapping.
        let overdue = Set(appState.overdueTasks.map(\.id))
        let today = Set(appState.todayTasks.map(\.id))
        XCTAssertTrue(overdue.isDisjoint(with: today), "Overdue and Today must not overlap")

        let calmIds = appState.calmModeTodayTasks.map(\.id)
        XCTAssertEqual(calmIds.count, Set(calmIds).count, "Calm Mode list has no duplicates")
        XCTAssertEqual(calmIds.count, appState.overdueTasks.count + appState.todayTasks.count)
    }

    func testCalmModeKeyDefaultsOff() {
        // Default OFF is the contract the widget extension relies on.
        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.calmModeKey)
        XCTAssertFalse(SharedKeys.sharedDefaults.bool(forKey: SharedKeys.calmModeKey))
    }

    func testCalmModeKeyRoundTripsThroughAppGroup() {
        SharedKeys.sharedDefaults.set(true, forKey: SharedKeys.calmModeKey)
        XCTAssertTrue(SharedKeys.sharedDefaults.bool(forKey: SharedKeys.calmModeKey))
        SharedKeys.sharedDefaults.removeObject(forKey: SharedKeys.calmModeKey)
    }
}
