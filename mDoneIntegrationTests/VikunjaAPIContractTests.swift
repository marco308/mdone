import Foundation
import XCTest
@testable import mDone

/// Live-server checks for the parts of Vikunja's v1 API that mDone depends on
/// in ways a release could quietly change. Each test states the assumption the
/// app makes, so a failure names the assumption rather than a status code.
///
/// See `docs/vikunja-api-inventory.md` for the hand-verified snapshot these
/// keep honest.
final class VikunjaAPIContractTests: VikunjaIntegrationCase {
    // MARK: - Auth

    /// Password login still returns a JWT (not an opaque token) and that JWT
    /// authorizes ordinary reads. `JWTHelpers.isJWT` decides whether the client
    /// arms refresh-on-401, so the token *shape* is load-bearing.
    func testPasswordLoginReturnsAJWTThatAuthorizesRequests() async throws {
        // A genuine login rather than the shared token, so this path is covered.
        let token = try await IntegrationSession.login(config)
        XCTAssertTrue(
            JWTHelpers.isJWT(token),
            "Login returned something that isn't a JWT: refresh handling would break"
        )

        let freshClient = APIClient()
        await freshClient.configure(serverURL: config.serverURL, token: token)
        let all: [Project] = try await freshClient.fetch(Endpoint.projects())
        XCTAssertFalse(all.isEmpty, "The token from /login did not authorize a project read")
    }

    // MARK: - Creates are PUT, updates are POST

    /// Vikunja inverts the usual REST convention. If a release ever "fixes"
    /// that, every create in the app starts 404ing or 405ing.
    func testProjectCreateIsPUTAndUpdateIsPOST() async throws {
        XCTAssertEqual(Endpoint.createProject().method, .PUT)
        XCTAssertEqual(Endpoint.updateProject(id: scratchProject.id).method, .POST)

        let renamed = try await projects.updateProject(
            id: scratchProject.id,
            request: ProjectUpdateRequest(from: scratchProject, title: "renamed by integration test")
        )
        XCTAssertEqual(renamed.title, "renamed by integration test")

        let refetched = try await projects.fetchProject(id: scratchProject.id)
        XCTAssertEqual(refetched.title, "renamed by integration test")
    }

    /// `fetchProjects` pages and then de-duplicates, because Vikunja repeats
    /// its negative-id pseudo-projects on every page (issue #139).
    func testProjectListHasNoDuplicateIDs() async throws {
        let all = try await projects.fetchProjects()
        let ids = all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate project ids would break the sidebar's ForEach")
    }

    // MARK: - View indirection

    /// Per-project tasks and buckets are only reachable through a view id, and
    /// the app assumes every project is born with a list view and a kanban one.
    func testNewProjectGetsListAndKanbanViews() async throws {
        let views = try await projects.fetchProjectViews(projectId: scratchProject.id)
        let kinds = views.compactMap(\.viewKind)
        XCTAssertTrue(kinds.contains("list"), "No list view on a fresh project, got \(kinds)")
        XCTAssertTrue(kinds.contains("kanban"), "No kanban view on a fresh project, got \(kinds)")
    }

    func testTaskCreatedInProjectAppearsInItsListView() async throws {
        let created = try await makeTask(TaskCreateRequest(title: "appears in the list view"))
        let listViewId = try await viewId(kind: "list")

        let viewTasks = try await tasks.fetchProjectTasks(projectId: scratchProject.id, viewId: listViewId)
        XCTAssertTrue(viewTasks.contains { $0.id == created.id }, "Created task missing from the project's list view")
    }

    // MARK: - Full-replace update semantics (issue #147)

    /// The behaviour that caused #147: `POST /tasks/{id}` replaces the whole
    /// task, so a body that omits a field resets it. A failure here is not
    /// automatically bad news, it means the server switched to partial updates
    /// and `preservingExistingValues(from:)` may no longer be needed.
    func testUpdateWithoutMergeStillWipesOmittedFields() async throws {
        let created = try await makeTask(
            TaskCreateRequest(title: "full replace", description: "carry me", priority: 4)
        )
        XCTAssertEqual(created.description, "carry me")

        let updated = try await tasks.updateTask(id: created.id, request: TaskUpdateRequest(done: true))

        XCTAssertTrue(updated.done)
        XCTAssertTrue(
            (updated.description ?? "").isEmpty,
            "Server kept the description through a partial update: semantics changed, revisit the #147 workaround"
        )
        XCTAssertEqual(updated.priority, 0, "Server kept the priority through a partial update: semantics changed")
    }

    /// And the fix: merging the existing task in first survives the replace.
    func testMergedUpdateKeepsDescriptionPriorityAndProgress() async throws {
        let created = try await makeTask(
            TaskCreateRequest(title: "merged update", description: "keep me", priority: 4)
        )
        let withProgress = try await tasks.updateTask(
            id: created.id,
            request: TaskUpdateRequest(percentDone: 0.5).preservingExistingValues(from: created)
        )
        XCTAssertEqual(withProgress.percentDone, 0.5)

        let completed = try await tasks.updateTask(
            id: created.id,
            request: TaskUpdateRequest(done: true).preservingExistingValues(from: withProgress)
        )

        XCTAssertTrue(completed.done)
        XCTAssertEqual(completed.description, "keep me")
        XCTAssertEqual(completed.priority, 4)
        XCTAssertEqual(completed.percentDone, 0.5)
    }

    // MARK: - Dates

    /// Vikunja returns `0001-01-01T00:00:00Z` for unset dates rather than null,
    /// and `APIClient` maps that to `.distantPast`. Everything downstream tests
    /// against `.distantPast`, so a switch to null would silently change
    /// meaning rather than fail to decode.
    func testUnsetDueDateComesBackAsTheZeroDate() async throws {
        let created = try await makeTask(TaskCreateRequest(title: "no due date"))
        XCTAssertEqual(created.dueDate, .distantPast, "Unset due date is no longer Vikunja's zero date")
    }

    /// Round-trips a due date, then clears it the way the app does: by sending
    /// the zero date back.
    func testDueDateSetThenClearedWithTheZeroDate() async throws {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let created = try await makeTask(TaskCreateRequest(title: "has a due date", dueDate: due))
        XCTAssertEqual(
            try XCTUnwrap(created.dueDate).timeIntervalSince1970,
            due.timeIntervalSince1970,
            accuracy: 1,
            "Due date did not survive the round trip"
        )

        let cleared = try await tasks.updateTask(
            id: created.id,
            request: TaskUpdateRequest(clearDueDate: true).preservingExistingValues(from: created)
        )
        XCTAssertEqual(cleared.dueDate, .distantPast, "Sending the zero date no longer clears a due date")
    }

    // MARK: - Filter DSL

    /// The advanced filter screen sends Vikunja's own filter syntax straight
    /// through. A parser change upstream turns that into a 400 for every user
    /// who saved a filter.
    func testFilterDSLIsAcceptedAndApplied() async throws {
        let done = try await makeTask(TaskCreateRequest(title: "filter: already done"))
        _ = try await tasks.updateTask(
            id: done.id,
            request: TaskUpdateRequest(done: true).preservingExistingValues(from: done)
        )
        let open = try await makeTask(TaskCreateRequest(title: "filter: still open", priority: 3))

        let results: [VTask] = try await client.fetch(
            Endpoint.allTasks(perPage: 200, filter: "done = false && priority >= 3")
        )

        XCTAssertTrue(results.contains { $0.id == open.id }, "Filter dropped a task that matches it")
        XCTAssertFalse(results.contains { $0.id == done.id }, "Filter returned a done task for `done = false`")
    }

    // MARK: - Relations

    /// Relation kinds go over the wire as lowercase with no underscores, which
    /// is what lets them survive `convertToSnakeCase` untouched. The server
    /// also owns creating the inverse relation on the other task.
    func testSubtaskRelationRoundTripsAndCreatesTheInverse() async throws {
        let parent = try await makeTask(TaskCreateRequest(title: "parent"))
        let child = try await makeTask(TaskCreateRequest(title: "child"))

        try await tasks.createRelation(taskId: parent.id, otherTaskId: child.id, kind: .subtask)

        let refetchedParent = try await tasks.fetchTask(id: parent.id)
        XCTAssertEqual(refetchedParent.subtasks.map(\.id), [child.id], "Subtask relation missing on the parent")

        let refetchedChild = try await tasks.fetchTask(id: child.id)
        XCTAssertEqual(
            refetchedChild.parentTasks.map(\.id),
            [parent.id],
            "Server no longer creates the inverse parenttask relation"
        )

        try await tasks.deleteRelation(taskId: parent.id, otherTaskId: child.id, kind: .subtask)
        let afterDelete = try await tasks.fetchTask(id: parent.id)
        XCTAssertTrue(afterDelete.subtasks.isEmpty, "Relation survived its DELETE")
    }

    // MARK: - Labels

    func testLabelCreateAttachAndDetach() async throws {
        let label = try await labels.createLabel(
            LabelCreateRequest(title: "integration \(UUID().uuidString.prefix(6))", hexColor: "4287f5")
        )
        let task = try await makeTask(TaskCreateRequest(title: "gets a label"))

        try await labels.addLabel(taskId: task.id, labelId: label.id)
        let labelled = try await tasks.fetchTask(id: task.id)
        XCTAssertEqual(labelled.labels?.map(\.id), [label.id], "Label did not attach to the task")

        try await labels.removeLabel(taskId: task.id, labelId: label.id)
        let unlabelled = try await tasks.fetchTask(id: task.id)
        XCTAssertTrue((unlabelled.labels ?? []).isEmpty, "Label survived its DELETE")
    }

    // MARK: - Kanban

    /// The board renders from one fetch because the view-tasks endpoint embeds
    /// each bucket's tasks. The plain `/buckets` endpoint stopped doing that in
    /// v0.24, so this is the assumption most likely to move again.
    func testKanbanViewEmbedsTasksInTheirBuckets() async throws {
        let created = try await makeTask(TaskCreateRequest(title: "on the board"))
        let kanbanViewId = try await viewId(kind: "kanban")

        let buckets = try await projects.fetchBuckets(projectId: scratchProject.id, viewId: kanbanViewId)
        XCTAssertFalse(buckets.isEmpty, "A kanban view with no buckets")

        let embedded = buckets.flatMap { $0.tasks ?? [] }
        XCTAssertTrue(
            embedded.contains { $0.id == created.id },
            "Kanban view no longer embeds tasks in buckets, the board would render empty"
        )
    }

    /// Moving a card between columns, and the empty-body response the client
    /// expects back from it.
    func testMoveTaskBetweenKanbanBuckets() async throws {
        let created = try await makeTask(TaskCreateRequest(title: "moves columns"))
        let kanbanViewId = try await viewId(kind: "kanban")
        let buckets = try await projects.fetchBuckets(projectId: scratchProject.id, viewId: kanbanViewId)

        guard let destination = buckets.last, buckets.count > 1 else {
            throw XCTSkip("Project has fewer than two buckets, nothing to move between")
        }

        try await tasks.moveTaskToBucket(
            taskId: created.id,
            projectId: scratchProject.id,
            viewId: kanbanViewId,
            bucketId: destination.id
        )

        let after = try await projects.fetchBuckets(projectId: scratchProject.id, viewId: kanbanViewId)
        let landed = after.first { ($0.tasks ?? []).contains { task in task.id == created.id } }
        XCTAssertEqual(landed?.id, destination.id, "Task did not land in the destination bucket")
    }
}
