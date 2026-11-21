import XCTest
@testable import mDone

/// Starring tasks (#16): the PATCH that sends it, and the Favorites list,
/// which comes from the tasks themselves because Vikunja's Favorites
/// pseudo-project has no views in the v2 API.
final class TaskFavoriteTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private static func taskJSON(id: Int64, isFavorite: Bool) -> Data {
        Data("""
        {"id": \(id), "title": "Task", "done": false, "priority": 0, "project_id": 1,
         "due_date": "0001-01-01T00:00:00Z", "labels": null, "assignees": null, "reactions": null,
         "attachments": null, "identifier": "", "index": \(id), "percent_done": 0,
         "is_favorite": \(isFavorite), "created": "2026-11-21T21:18:56Z",
         "updated": "2026-11-21T21:18:56Z", "created_by": null, "related_tasks": null}
        """.utf8)
    }

    @MainActor
    private func makeMockedAppState() async -> AppState {
        let client = MockURLProtocol.mockClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        return AppState(taskService: TaskService(apiClient: client))
    }

    @MainActor
    func testFavoritesListHoldsOpenStarredTasksFromEveryProject() async {
        let appState = await makeMockedAppState()
        var starredDone = VTask(id: 3, title: "Starred, done", done: true, priority: 0, projectId: 1)
        starredDone.isFavorite = true
        var starredOther = VTask(id: 2, title: "Starred elsewhere", done: false, priority: 0, projectId: 7)
        starredOther.isFavorite = true
        var starred = VTask(id: 1, title: "Starred", done: false, priority: 0, projectId: 1)
        starred.isFavorite = true
        appState.tasks = [
            starred,
            VTask(id: 4, title: "Plain", done: false, priority: 0, projectId: 1),
            starredOther,
            starredDone
        ]

        XCTAssertEqual(appState.tasksForProject(Project.favoritesId).map(\.id), [1, 2])
    }

    @MainActor
    func testStarringSendsOnlyTheFlagAndShowsFavoritesList() async throws {
        let appState = await makeMockedAppState()
        appState.tasks = [VTask(id: 5, title: "Task", done: false, priority: 0, projectId: 1)]
        appState.projects = [Project(id: 1, title: "Inbox")]

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, VikunjaAPI.path("/tasks/5"))
            return (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Self.taskJSON(id: 5, isFavorite: true))
        }

        await appState.setFavorite(try XCTUnwrap(appState.tasks.first), true)

        XCTAssertEqual(appState.tasks.first?.isFavorite, true)
        XCTAssertEqual(appState.projects.map(\.id), [1, Project.favoritesId])
        XCTAssertEqual(appState.tasksForProject(Project.favoritesId).map(\.id), [5])

        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let body = try XCTUnwrap(MockURLProtocol.bodyData(from: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json.keys.sorted(), ["is_favorite"])
        XCTAssertEqual(json["is_favorite"] as? Bool, true)
    }

    @MainActor
    func testUnstarringKeepsTheServersFavoritesEntry() async throws {
        let appState = await makeMockedAppState()
        var task = VTask(id: 5, title: "Task", done: false, priority: 0, projectId: 1)
        task.isFavorite = true
        appState.tasks = [task]
        appState.projects = [Project(id: Project.favoritesId, title: "Favorites", isFavorite: true)]

        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Self.taskJSON(id: 5, isFavorite: false))
        }

        await appState.setFavorite(task, false)

        XCTAssertEqual(appState.tasks.first?.isFavorite, false)
        XCTAssertTrue(appState.tasksForProject(Project.favoritesId).isEmpty)
        XCTAssertEqual(appState.projects.map(\.id), [Project.favoritesId])
    }

    @MainActor
    func testFailedStarIsRolledBack() async throws {
        let appState = await makeMockedAppState()
        appState.tasks = [VTask(id: 5, title: "Task", done: false, priority: 0, projectId: 1)]

        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(
                    statusCode: 403, url: request.url,
                    headers: ["Content-Type": "application/problem+json"]
                ),
                Data(#"{"title": "Forbidden", "status": 403, "detail": "No.", "code": 0}"#.utf8)
            )
        }

        await appState.setFavorite(try XCTUnwrap(appState.tasks.first), true)

        XCTAssertNotEqual(appState.tasks.first?.isFavorite, true)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertFalse(appState.projects.contains { $0.id == Project.favoritesId })
    }

    @MainActor
    func testStarringAnAlreadyStarredTaskSendsNothing() async throws {
        let appState = await makeMockedAppState()
        var task = VTask(id: 5, title: "Task", done: false, priority: 0, projectId: 1)
        task.isFavorite = true
        appState.tasks = [task]

        MockURLProtocol.requestHandler = { request in
            XCTFail("Unexpected request: \(request.httpMethod ?? "?") \(request.url?.path ?? "")")
            return (MockURLProtocol.makeResponse(statusCode: 500, url: request.url), Data())
        }

        await appState.setFavorite(task, true)

        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }
}
