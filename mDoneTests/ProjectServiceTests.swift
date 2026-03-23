import XCTest
@testable import mDone

final class ProjectServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    private func makeTestService() -> (ProjectService, APIClient) {
        let client = APIClient(session: MockURLProtocol.mockSession())
        let service = ProjectService(apiClient: client)
        return (service, client)
    }

    // MARK: - fetchProjects

    func testFetchProjectsReturnsProjects() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let projectsJSON = """
        [
            {"id": 1, "title": "Work", "hex_color": "#4772FA", "is_archived": false, "is_favorite": true, "position": 1.0, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"},
            {"id": 2, "title": "Personal", "hex_color": "#FF4444", "is_archived": false, "is_favorite": false, "position": 2.0, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/projects") == true)
            XCTAssertEqual(request.httpMethod, "GET")
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, projectsJSON)
        }

        let projects = try await service.fetchProjects()
        XCTAssertEqual(projects.count, 2)
        XCTAssertEqual(projects[0].title, "Work")
        XCTAssertEqual(projects[0].hexColor, "#4772FA")
        XCTAssertTrue(projects[0].isFavorite ?? false)
        XCTAssertEqual(projects[1].title, "Personal")
    }

    func testFetchProjectsEmpty() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, "[]".data(using: .utf8)!)
        }

        let projects = try await service.fetchProjects()
        XCTAssertTrue(projects.isEmpty)
    }

    // MARK: - fetchProject

    func testFetchProjectReturnsProject() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let projectJSON = """
        {"id": 5, "title": "Home", "description": "Home tasks", "hex_color": "#00AA00", "is_archived": false, "is_favorite": false, "position": 3.0, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/projects/5") == true)
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, projectJSON)
        }

        let project = try await service.fetchProject(id: 5)
        XCTAssertEqual(project.id, 5)
        XCTAssertEqual(project.title, "Home")
        XCTAssertEqual(project.description, "Home tasks")
    }

    // MARK: - fetchProjectViews

    func testFetchProjectViewsReturnsViews() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let viewsJSON = """
        [
            {"id": 1, "title": "List", "project_id": 5, "view_kind": "list", "position": 1.0},
            {"id": 2, "title": "Kanban", "project_id": 5, "view_kind": "kanban", "position": 2.0}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/projects/5/views") == true)
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, viewsJSON)
        }

        let views = try await service.fetchProjectViews(projectId: 5)
        XCTAssertEqual(views.count, 2)
        XCTAssertEqual(views[0].title, "List")
        XCTAssertEqual(views[0].viewKind, "list")
        XCTAssertEqual(views[1].viewKind, "kanban")
    }

    // MARK: - Error Handling

    func testFetchProjectsThrowsOnUnauthorized() async {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "expired-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 401, url: request.url)
            return (response, Data())
        }

        do {
            _ = try await service.fetchProjects()
            XCTFail("Expected unauthorized error")
        } catch let error as NetworkError {
            if case .unauthorized = error {
                // Expected
            } else {
                XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchProjectThrowsOnServerError() async {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let errorJSON = """
        {"code": 404, "message": "Project not found"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 404, url: request.url)
            return (response, errorJSON)
        }

        do {
            _ = try await service.fetchProject(id: 999)
            XCTFail("Expected server error")
        } catch let error as NetworkError {
            if case let .serverError(statusCode, message) = error {
                XCTAssertEqual(statusCode, 404)
                XCTAssertEqual(message, "Project not found")
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Project Model Tests

    func testProjectWithMinimalFields() {
        let project = Project(id: 1, title: "Minimal")
        XCTAssertEqual(project.id, 1)
        XCTAssertEqual(project.title, "Minimal")
        XCTAssertNil(project.description)
        XCTAssertNil(project.hexColor)
        XCTAssertNil(project.isArchived)
        XCTAssertNil(project.isFavorite)
        XCTAssertNil(project.position)
        XCTAssertNil(project.owner)
        XCTAssertNil(project.parentProjectId)
        XCTAssertNil(project.views)
    }

    func testProjectListViewId() {
        let views = [
            ProjectView(id: 10, title: "Kanban", projectId: 1, viewKind: "kanban"),
            ProjectView(id: 20, title: "List", projectId: 1, viewKind: "list"),
            ProjectView(id: 30, title: "Gantt", projectId: 1, viewKind: "gantt"),
        ]

        let project = Project(id: 1, title: "With Views", views: views)
        XCTAssertEqual(project.listViewId, 20)
    }

    func testProjectListViewIdNilWithNoListView() {
        let views = [
            ProjectView(id: 10, title: "Kanban", projectId: 1, viewKind: "kanban"),
        ]

        let project = Project(id: 1, title: "No List View", views: views)
        XCTAssertNil(project.listViewId)
    }

    func testProjectListViewIdNilWithNoViews() {
        let project = Project(id: 1, title: "No Views")
        XCTAssertNil(project.listViewId)
    }

    func testProjectEquality() {
        let project1 = Project(id: 1, title: "First")
        let project2 = Project(id: 1, title: "Different Name")
        let project3 = Project(id: 2, title: "First")

        XCTAssertEqual(project1, project2, "Projects with same ID should be equal")
        XCTAssertNotEqual(project1, project3, "Projects with different IDs should not be equal")
    }

    func testProjectHashable() {
        let project1 = Project(id: 1, title: "First")
        let project2 = Project(id: 1, title: "Different Name")

        var set: Set<Project> = [project1]
        set.insert(project2)

        XCTAssertEqual(set.count, 1, "Projects with same ID should hash equally")
    }
}
