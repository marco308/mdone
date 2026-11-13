import Foundation
import XCTest
@testable import mDone

/// Live-server checks for the parts of Vikunja's v2 API that mDone depends on
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
        let all: [Project] = try await freshClient.fetchList(Endpoint.projects())
        XCTAssertFalse(all.isEmpty, "The token from /login did not authorize a project read")
    }

    // MARK: - Creates are POST, updates are PUT

    /// v2 uses the usual REST convention, the reverse of v1. The scratch
    /// project in `setUp` already proves the create; this proves the update.
    func testProjectCreateIsPOSTAndUpdateIsPUT() async throws {
        XCTAssertEqual(Endpoint.createProject().method, .POST)
        XCTAssertEqual(Endpoint.updateProject(id: scratchProject.id).method, .PUT)

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

    /// The behaviour that caused #147: `PUT /tasks/{id}` replaces the whole
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

        let results: [VTask] = try await client.fetchList(
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

    /// The board renders from one fetch because `/buckets/tasks` embeds each
    /// bucket's tasks. The plain `/buckets` endpoint is metadata only.
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

    // MARK: - Manual order (issue #183)

    /// Dragging the last task of a project list to the top: the position
    /// endpoint takes the list view's id, and the list view reads back in the
    /// new order. The starting order is read, not assumed: v2.4.0 lists a
    /// fresh project's tasks newest first. The number sent is what
    /// `TaskPositioning` produces for "drop at the top", so a server that
    /// started repairing such values differently would show up here.
    func testTaskPositionReordersTheListView() async throws {
        for title in ["first", "second", "third"] {
            try await makeTask(TaskCreateRequest(title: title))
        }
        let listViewId = try await viewId(kind: "list")

        let before = try await tasks.fetchProjectTasks(projectId: scratchProject.id, viewId: listViewId)
        XCTAssertEqual(before.count, 3)
        XCTAssertTrue(before.allSatisfy { ($0.position ?? 0) > 0 }, "view tasks must carry positions")

        let move = try XCTUnwrap(TaskPositioning.move(before, fromOffsets: [before.count - 1], toOffset: 0))
        try await tasks.updatePosition(taskId: move.task.id, position: move.position, viewId: listViewId)

        let after = try await tasks.fetchProjectTasks(projectId: scratchProject.id, viewId: listViewId)
        XCTAssertEqual(after.map(\.id), move.reordered.map(\.id), "list view did not honour the position")
    }

    /// Positions are per view: a position sent with the kanban view's id
    /// reorders the cards inside their bucket and leaves the list view alone.
    func testTaskPositionOnTheKanbanViewReordersCardsWithinABucket() async throws {
        for title in ["first card", "second card"] {
            try await makeTask(TaskCreateRequest(title: title))
        }
        let kanbanViewId = try await viewId(kind: "kanban")
        let listViewId = try await viewId(kind: "list")

        func cardOrder() async throws -> [VTask] {
            let buckets = try await projects.fetchBuckets(projectId: scratchProject.id, viewId: kanbanViewId)
            let bucket = try XCTUnwrap(buckets.first { !$0.allTasks.isEmpty }, "no bucket holds the cards")
            return bucket.allTasks
        }

        let listBefore = try await tasks.fetchProjectTasks(projectId: scratchProject.id, viewId: listViewId)
        let cards = try await cardOrder()
        XCTAssertEqual(cards.count, 2, "both cards should sit in the default bucket")
        let last = try XCTUnwrap(cards.last)

        let position = TaskPositioning.position(forInserting: last, at: 0, into: cards)
        try await tasks.updatePosition(taskId: last.id, position: position, viewId: kanbanViewId)

        let reordered = try await cardOrder()
        XCTAssertEqual(
            reordered.map(\.id),
            [last.id] + cards.dropLast().map(\.id),
            "kanban view did not honour the position"
        )

        let listAfter = try await tasks.fetchProjectTasks(projectId: scratchProject.id, viewId: listViewId)
        XCTAssertEqual(listAfter.map(\.id), listBefore.map(\.id), "a kanban position leaked into the list view")
    }

    // MARK: - v2 wire format (#291)

    /// Lists arrive in an envelope whose `total_pages` drives `fetchAllPages`.
    /// With one task per page, three tasks must take three pages to collect.
    func testListEnvelopeReportsPagesThatFetchAllPagesFollows() async throws {
        var created: [Int64] = []
        for index in 1 ... 3 {
            try await created.append(makeTask(TaskCreateRequest(title: "page \(index)")).id)
        }
        let listViewId = try await viewId(kind: "list")

        let all: [VTask] = try await client.fetchAllPages({ page, perPage in
            Endpoint.projectTasks(
                projectId: self.scratchProject.id, viewId: listViewId, page: page, perPage: perPage
            )
        }, perPage: 1)

        XCTAssertEqual(
            Set(all.map(\.id)), Set(created),
            "Paging by the envelope's total_pages lost or repeated tasks"
        )
    }

    /// The kanban route is documented as not paginated, but still slices each
    /// bucket's tasks by `per_page`. `fetchBuckets` pages on the buckets' own
    /// `count`, so a full column must come back even one card per page.
    func testKanbanBucketsStillPageTheirTasks() async throws {
        var created: [Int64] = []
        for index in 1 ... 3 {
            try await created.append(makeTask(TaskCreateRequest(title: "card \(index)")).id)
        }
        let kanbanViewId = try await viewId(kind: "kanban")

        let buckets = try await projects.fetchBuckets(
            projectId: scratchProject.id, viewId: kanbanViewId, perPage: 1
        )

        let embedded = Set(buckets.flatMap { $0.tasks ?? [] }.map(\.id))
        XCTAssertTrue(embedded.isSuperset(of: created), "A column lost cards when read one per page")
    }

    /// Search moved from `s` to `q`.
    func testSearchUsesTheQParameter() async throws {
        let needle = "needle-\(UUID().uuidString.prefix(8))"
        let wanted = try await makeTask(TaskCreateRequest(title: "find the \(needle)"))
        let other = try await makeTask(TaskCreateRequest(title: "leave this one"))

        let results: [VTask] = try await client.fetchList(Endpoint.allTasks(perPage: 50, search: needle))

        XCTAssertTrue(results.contains { $0.id == wanted.id }, "Search did not find a task by its title")
        XCTAssertFalse(results.contains { $0.id == other.id }, "Search ignored the query and returned everything")
    }

    /// Refusals are `application/problem+json`: the text is in `detail` and
    /// Vikunja's own number is still in `code`. A missing task is 404 / 4002.
    func testErrorsCarryDetailAndCode() async throws {
        do {
            _ = try await tasks.fetchTask(id: 999_999_999)
            XCTFail("Fetching a task that does not exist should throw")
        } catch let NetworkError.serverError(statusCode, message) {
            XCTAssertEqual(statusCode, 404)
            XCTAssertFalse((message ?? "").isEmpty, "The error body no longer carries a readable `detail`")
        }
    }

    /// The assignee picker reads `/projects/{id}/users/search`. The owner of a
    /// project can always be assigned to its tasks.
    func testProjectUsersIncludesTheOwner() async throws {
        let users = try await UserService(apiClient: client).fetchProjectUsers(projectId: scratchProject.id)
        XCTAssertTrue(
            users.contains { $0.username == config.username },
            "The project's own user is missing from its assignable users"
        )
    }

    /// The widget ticks a task off by fetching it and sending the whole JSON
    /// back with `done` set, read-only fields included. The server has to take
    /// that body, and the task's other fields have to survive (#283).
    func testWidgetCompletionRoundTripKeepsTheTask() async throws {
        let created = try await makeTask(
            TaskCreateRequest(title: "tick me off in a widget", description: "keep me", priority: 3)
        )
        let token = try await IntegrationSession.shared.token(for: config)
        let url = try XCTUnwrap(URL(string: config.serverURL + Endpoint.task(id: created.id).path))

        var fetch = URLRequest(url: url)
        fetch.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (fetched, _) = try await URLSession.shared.data(for: fetch)

        var update = URLRequest(url: url)
        update.httpMethod = Endpoint.updateTask(id: created.id).method.rawValue
        update.setValue("application/json", forHTTPHeaderField: "Content-Type")
        update.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        update.httpBody = try WidgetDataProvider.completionBody(from: fetched)
        let (_, response) = try await URLSession.shared.data(for: update)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "The server refused a fetched task sent back whole")

        let after = try await tasks.fetchTask(id: created.id)
        XCTAssertTrue(after.done)
        XCTAssertEqual(after.priority, 3)
        XCTAssertFalse((after.description ?? "").isEmpty, "Completing from a widget wiped the description")
    }
}
