import XCTest
@testable import mDone

final class APIClientTests: XCTestCase {
    // MARK: - Model Decoding Tests

    func testVTaskDecoding() throws {
        let json = try XCTUnwrap("""
        {
            "id": 1,
            "title": "Buy groceries",
            "description": "Milk, eggs, bread",
            "done": false,
            "due_date": "2026-03-16T10:00:00Z",
            "priority": 3,
            "project_id": 1,
            "hex_color": "#FF4444",
            "percent_done": 0.5,
            "is_favorite": false,
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """.data(using: .utf8))

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        let task = try decoder.decode(VTask.self, from: json)
        XCTAssertEqual(task.id, 1)
        XCTAssertEqual(task.title, "Buy groceries")
        XCTAssertEqual(task.description, "Milk, eggs, bread")
        XCTAssertFalse(task.done)
        XCTAssertEqual(task.priority, 3)
        XCTAssertEqual(task.projectId, 1)
        XCTAssertNotNil(task.dueDate)
        XCTAssertEqual(task.hexColor, "#FF4444")
        XCTAssertEqual(task.percentDone, 0.5)
    }

    func testProjectDecoding() throws {
        let json = try XCTUnwrap("""
        {
            "id": 1,
            "title": "Work",
            "description": "Work tasks",
            "hex_color": "#4772FA",
            "is_archived": false,
            "is_favorite": true,
            "position": 1.0,
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """.data(using: .utf8))

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        let project = try decoder.decode(Project.self, from: json)
        XCTAssertEqual(project.id, 1)
        XCTAssertEqual(project.title, "Work")
        XCTAssertEqual(project.hexColor, "#4772FA")
        XCTAssertTrue(project.isFavorite ?? false)
        XCTAssertFalse(project.isArchived ?? false)
    }

    func testLabelDecoding() throws {
        let json = try XCTUnwrap("""
        {
            "id": 5,
            "title": "Bug",
            "hex_color": "#FF0000",
            "description": "Bug reports",
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """.data(using: .utf8))

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        let label = try decoder.decode(VLabel.self, from: json)
        XCTAssertEqual(label.id, 5)
        XCTAssertEqual(label.title, "Bug")
        XCTAssertEqual(label.hexColor, "#FF0000")
    }

    func testUserDecoding() throws {
        let json = try XCTUnwrap("""
        {
            "id": 1,
            "username": "testuser",
            "name": "Test User",
            "email": "test@example.com",
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """.data(using: .utf8))

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = isoFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }

        let user = try decoder.decode(User.self, from: json)
        XCTAssertEqual(user.id, 1)
        XCTAssertEqual(user.username, "testuser")
        XCTAssertEqual(user.name, "Test User")
        XCTAssertEqual(user.displayName, "Test User")
    }

    func testPriorityLevels() {
        XCTAssertEqual(PriorityLevel(rawValue: 0), PriorityLevel.none)
        XCTAssertEqual(PriorityLevel(rawValue: 1), PriorityLevel.low)
        XCTAssertEqual(PriorityLevel(rawValue: 2), PriorityLevel.medium)
        XCTAssertEqual(PriorityLevel(rawValue: 3), PriorityLevel.high)
        XCTAssertEqual(PriorityLevel(rawValue: 4), PriorityLevel.urgent)
        XCTAssertEqual(PriorityLevel(rawValue: 5), PriorityLevel.critical)
    }

    func testNetworkErrorDescriptions() {
        XCTAssertNotNil(NetworkError.invalidURL.errorDescription)
        XCTAssertNotNil(NetworkError.unauthorized.errorDescription)
        XCTAssertNotNil(NetworkError.networkUnavailable.errorDescription)
        XCTAssertNotNil(NetworkError.rateLimited.errorDescription)
        XCTAssertNotNil(NetworkError.serverError(statusCode: 500, message: "Internal error").errorDescription)
    }

    func testRateLimitedErrorDescription() {
        let error = NetworkError.rateLimited
        XCTAssertEqual(error.errorDescription, "Server is busy. Please try again later.")
    }

    func testEndpointPaths() {
        XCTAssertEqual(Endpoint.currentUser.path, VikunjaAPI.path("/user"))
        XCTAssertEqual(Endpoint.currentUser.method, .GET)

        let projectsEndpoint = Endpoint.projects()
        XCTAssertEqual(projectsEndpoint.path, VikunjaAPI.path("/projects"))

        let createTask = Endpoint.createTask(projectId: 5)
        XCTAssertEqual(createTask.path, VikunjaAPI.path("/projects/5/tasks"))
        XCTAssertEqual(createTask.method, .POST)

        let updateTask = Endpoint.updateTask(id: 10)
        XCTAssertEqual(updateTask.path, VikunjaAPI.path("/tasks/10"))
        XCTAssertEqual(updateTask.method, .PUT)

        let deleteTask = Endpoint.deleteTask(id: 3)
        XCTAssertEqual(deleteTask.path, VikunjaAPI.path("/tasks/3"))
        XCTAssertEqual(deleteTask.method, .DELETE)
    }

    /// The one place the API version is named. Every other test builds paths
    /// through `VikunjaAPI.path`, so this is what pins the version (#290, #291).
    func testAPIVersionPrefix() {
        XCTAssertEqual(VikunjaAPI.basePath, "/api/v2")
        XCTAssertEqual(VikunjaAPI.path("/tasks/1"), "/api/v2/tasks/1")
        XCTAssertEqual(Endpoint(api: "/tasks/1", method: .PATCH).path, "/api/v2/tasks/1")
        XCTAssertEqual(HTTPMethod.PATCH.rawValue, "PATCH")
    }

    /// v1 is kept for exactly two requests: the OIDC callback, which v2 does
    /// not have, and the `/info` fallback for a server too old for v2.
    func testLegacyPrefixIsV1AndOnlyTheOIDCCallbackAndInfoFallbackUseIt() {
        XCTAssertEqual(VikunjaAPI.legacyBasePath, "/api/v1")
        XCTAssertEqual(VikunjaAPI.legacyPath("/info"), "/api/v1/info")
        XCTAssertEqual(Endpoint.legacyInfo.path, "/api/v1/info")
        XCTAssertEqual(Endpoint.legacyInfo.method, .GET)
        XCTAssertEqual(Endpoint.info.path, "/api/v2/info")
        XCTAssertEqual(Endpoint.openIDCallback(provider: "authelia").path, "/api/v1/auth/openid/authelia/callback")
        XCTAssertEqual(Endpoint.login.path, "/api/v2/login")
        XCTAssertEqual(Endpoint.refreshToken.path, "/api/v2/user/token/refresh")
    }

    // MARK: - APIClient Network Tests (using MockURLProtocol)

    private func makeTestClient() -> APIClient {
        MockURLProtocol.mockClient()
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - fetch() Tests

    func testFetchSucceedsWithValidJSON() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let taskJSON = try XCTUnwrap("""
        {
            "id": 42,
            "title": "Test Task",
            "done": false,
            "priority": 2,
            "project_id": 1,
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, taskJSON)
        }

        let task: VTask = try await client.fetch(Endpoint.task(id: 42))
        XCTAssertEqual(task.id, 42)
        XCTAssertEqual(task.title, "Test Task")
        XCTAssertFalse(task.done)
        XCTAssertEqual(task.priority, 2)
    }

    func testFetchThrowsUnauthorizedOn401() async {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "bad-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 401, url: request.url)
            return (response, Data())
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
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

    func testFetchThrowsServerErrorOn500() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let errorJSON = try XCTUnwrap("""
        {"code": 500, "message": "Internal Server Error"}
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 500, url: request.url)
            return (response, errorJSON)
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected server error")
        } catch let error as NetworkError {
            if case let .serverError(statusCode, message) = error {
                XCTAssertEqual(statusCode, 500)
                XCTAssertEqual(message, "Internal Server Error")
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchThrowsDecodingErrorOnMalformedJSON() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let malformedJSON = try XCTUnwrap("{ not valid json }".data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, malformedJSON)
        }

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected decoding error")
        } catch let error as NetworkError {
            if case .decodingError = error {
                // Expected
            } else {
                XCTFail("Expected .decodingError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testFetchThrowsInvalidURLWithoutConfiguration() async {
        let client = makeTestClient()
        // Do NOT configure serverURL — should throw invalidURL

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected invalidURL error")
        } catch let error as NetworkError {
            if case .invalidURL = error {
                // Expected
            } else {
                XCTFail("Expected .invalidURL, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - send() Tests

    func testSendWithBodyReturnsDecodedResponse() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let responseJSON = try XCTUnwrap("""
        {
            "id": 99,
            "title": "Created Task",
            "done": false,
            "priority": 3,
            "project_id": 5,
            "created": "2026-03-20T10:00:00Z",
            "updated": "2026-03-20T10:00:00Z"
        }
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            // Verify the request has a body
            XCTAssertNotNil(request.httpBody ?? request.httpBodyStream.flatMap { _ in Data() })
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, responseJSON)
        }

        let createRequest = TaskCreateRequest(title: "Created Task", priority: 3)
        let task: VTask = try await client.send(Endpoint.createTask(projectId: 5), body: createRequest)
        XCTAssertEqual(task.id, 99)
        XCTAssertEqual(task.title, "Created Task")
        XCTAssertEqual(task.priority, 3)
    }

    func testSendThrowsUnauthorizedOn401() async {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "expired-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 401, url: request.url)
            return (response, Data())
        }

        do {
            let _: VTask = try await client.send(
                Endpoint.updateTask(id: 1),
                body: TaskUpdateRequest(done: true)
            )
            XCTFail("Expected unauthorized error")
        } catch let error as NetworkError {
            if case .unauthorized = error {
                // Expected — simulates token expiry
            } else {
                XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - delete() Tests

    func testDeleteSucceeds() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, Data())
        }

        try await client.delete(Endpoint.deleteTask(id: 42))
        // If no error is thrown, the test passes
    }

    func testDeleteThrowsOn401() async {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "bad-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 401, url: request.url)
            return (response, Data())
        }

        do {
            try await client.delete(Endpoint.deleteTask(id: 1))
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

    func testDeleteThrowsServerErrorOn500() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let errorJSON = try XCTUnwrap("""
        {"code": 500, "message": "Delete failed"}
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 500, url: request.url)
            return (response, errorJSON)
        }

        do {
            try await client.delete(Endpoint.deleteTask(id: 1))
            XCTFail("Expected server error")
        } catch let error as NetworkError {
            if case let .serverError(statusCode, message) = error {
                XCTAssertEqual(statusCode, 500)
                XCTAssertEqual(message, "Delete failed")
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - fetchAllPages() Tests

    func testFetchAllPagesSinglePage() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let tasksJSON = try XCTUnwrap("""
        [
            {"id": 1, "title": "Task 1", "done": false, "priority": 0, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"},
            {"id": 2, "title": "Task 2", "done": true, "priority": 1, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        ]
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, MockURLProtocol.page(tasksJSON))
        }

        let tasks: [VTask] = try await client.fetchAllPages({ page, perPage in
            Endpoint.allTasks(page: page, perPage: perPage)
        }, perPage: 50)

        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].title, "Task 1")
        XCTAssertEqual(tasks[1].title, "Task 2")
    }

    func testFetchAllPagesMultiplePages() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let page1JSON = try XCTUnwrap("""
        [
            {"id": 1, "title": "Task 1", "done": false, "priority": 0, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"},
            {"id": 2, "title": "Task 2", "done": false, "priority": 0, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        ]
        """.data(using: .utf8))

        let page2JSON = try XCTUnwrap("""
        [
            {"id": 3, "title": "Task 3", "done": false, "priority": 0, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        ]
        """.data(using: .utf8))

        var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            if requestCount == 1 {
                let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
                return (response, MockURLProtocol.page(page1JSON, totalPages: 2))
            } else {
                let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
                return (response, MockURLProtocol.page(page2JSON, totalPages: 2, page: 2))
            }
        }

        let tasks: [VTask] = try await client.fetchAllPages({ page, perPage in
            Endpoint.allTasks(page: page, perPage: perPage)
        }, perPage: 2)

        XCTAssertEqual(tasks.count, 3)
        XCTAssertEqual(tasks[0].id, 1)
        XCTAssertEqual(tasks[1].id, 2)
        XCTAssertEqual(tasks[2].id, 3)
        XCTAssertEqual(requestCount, 2)
    }

    // MARK: - List envelope (#291)

    private func decodePage(_ json: String) throws -> ListPage<VTask> {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(ListPage<VTask>.self, from: Data(json.utf8))
    }

    func testListPageDecodesItemsAndTotalPages() throws {
        let page = try decodePage(
            #"{"$schema": "https://x/api/v2/schemas/PaginatedTask.json", "items": [{"id": 1, "title": "A", "done": false, "priority": 0, "project_id": 1}], "total": 120, "page": 1, "per_page": 50, "total_pages": 3}"#
        )
        XCTAssertEqual(page.items?.map(\.id), [1])
        XCTAssertEqual(page.totalPages, 3)
    }

    /// Vikunja sends `null`, not `[]`, for some empty lists.
    func testListPageDecodesNullItems() throws {
        let page = try decodePage(#"{"items": null, "total": 0, "page": 1, "per_page": 50, "total_pages": 0}"#)
        XCTAssertNil(page.items)
        XCTAssertEqual(page.totalPages, 0)
    }

    /// The kanban buckets route sends `total` and no page count.
    func testListPageDecodesWithoutTotalPages() throws {
        let page = try decodePage(#"{"items": [], "total": 0}"#)
        XCTAssertEqual(page.items?.count, 0)
        XCTAssertNil(page.totalPages)
    }

    func testFetchListUnwrapsItems() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                MockURLProtocol.page(#"[{"id": 1, "title": "List", "project_id": 5, "view_kind": "list"}]"#)
            )
        }

        let views: [ProjectView] = try await client.fetchList(Endpoint.projectViews(projectId: 5))

        XCTAssertEqual(views.map(\.id), [1])
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    func testFetchListTreatsNullItemsAsEmpty() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        MockURLProtocol.requestHandler = { request in
            (
                MockURLProtocol.makeResponse(statusCode: 200, url: request.url),
                Data(#"{"items": null, "total": 0}"#.utf8)
            )
        }

        let users: [User] = try await client.fetchList(Endpoint.projectUsers(projectId: 5))

        XCTAssertTrue(users.isEmpty)
    }

    /// A v1 server answers a list with a bare array. That must fail loudly as
    /// a decoding error, not read as an empty list.
    func testFetchListRejectsABareArray() async {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        MockURLProtocol.requestHandler = { request in
            (MockURLProtocol.makeResponse(statusCode: 200, url: request.url), Data("[]".utf8))
        }

        do {
            let _: [ProjectView] = try await client.fetchList(Endpoint.projectViews(projectId: 5))
            XCTFail("a bare array is not the v2 envelope")
        } catch NetworkError.decodingError {
            // expected
        } catch {
            XCTFail("expected a decoding error, got \(error)")
        }
    }

    func testFetchAllPagesEmptyResponse() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, MockURLProtocol.page("[]", totalPages: 0))
        }

        let tasks: [VTask] = try await client.fetchAllPages { page, perPage in
            Endpoint.allTasks(page: page, perPage: perPage)
        }

        XCTAssertTrue(tasks.isEmpty)
    }

    func testFetchAllPagesThrowsUnauthorized() async {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "bad-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 401, url: request.url)
            return (response, Data())
        }

        do {
            let _: [VTask] = try await client.fetchAllPages { page, perPage in
                Endpoint.allTasks(page: page, perPage: perPage)
            }
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

    // MARK: - Date Decoding Tests

    func testZeroDateDecodingToDistantPast() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let taskJSON = try XCTUnwrap("""
        {
            "id": 1,
            "title": "No Due Date",
            "done": false,
            "priority": 0,
            "project_id": 1,
            "due_date": "0001-01-01T00:00:00Z",
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, taskJSON)
        }

        let task: VTask = try await client.fetch(Endpoint.task(id: 1))
        XCTAssertEqual(task.id, 1)
        // Vikunja zero-date should decode to Date.distantPast
        XCTAssertEqual(task.dueDate, Date.distantPast)
        // And effectiveDueDate should treat it as nil
        XCTAssertNil(task.effectiveDueDate)
    }

    func testISO8601WithFractionalSeconds() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let taskJSON = try XCTUnwrap("""
        {
            "id": 2,
            "title": "Fractional",
            "done": false,
            "priority": 0,
            "project_id": 1,
            "created": "2026-03-15T08:30:45.123Z",
            "updated": "2026-03-15T08:30:45.456Z"
        }
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, taskJSON)
        }

        let task: VTask = try await client.fetch(Endpoint.task(id: 2))
        XCTAssertEqual(task.id, 2)
        XCTAssertNotNil(task.created)
        XCTAssertNotNil(task.updated)
    }

    func testISO8601WithoutFractionalSeconds() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let taskJSON = try XCTUnwrap("""
        {
            "id": 3,
            "title": "No Fractional",
            "done": false,
            "priority": 0,
            "project_id": 1,
            "created": "2026-03-15T08:30:45Z",
            "updated": "2026-03-15T08:30:45Z"
        }
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, taskJSON)
        }

        let task: VTask = try await client.fetch(Endpoint.task(id: 3))
        XCTAssertEqual(task.id, 3)
        XCTAssertNotNil(task.created)
        XCTAssertNotNil(task.updated)
    }

    // MARK: - Request Verification Tests

    func testFetchSetsAuthorizationHeader() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "my-secret-token")

        let taskJSON = try XCTUnwrap("""
        {"id": 1, "title": "T", "done": false, "priority": 0, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, taskJSON)
        }

        let _: VTask = try await client.fetch(Endpoint.task(id: 1))

        let capturedRequest = MockURLProtocol.capturedRequests.first
        XCTAssertNotNil(capturedRequest)
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer my-secret-token")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
    }

    func testFetchUsesCorrectHTTPMethod() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let responseJSON = try XCTUnwrap("""
        {"id": 1, "title": "T", "done": false, "priority": 0, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, responseJSON)
        }

        let _: VTask = try await client.fetch(Endpoint.task(id: 1))

        let capturedRequest = MockURLProtocol.capturedRequests.first
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
    }

    func testClearCredentialsPreventsRequests() async {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")
        await client.clearCredentials()

        do {
            let _: VTask = try await client.fetch(Endpoint.task(id: 1))
            XCTFail("Expected invalidURL error after clearing credentials")
        } catch let error as NetworkError {
            if case .invalidURL = error {
                // Expected — serverURL is nil after clearing
            } else {
                XCTFail("Expected .invalidURL, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - sendExpectingEmpty() Tests

    func testSendExpectingEmptySucceeds() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, Data())
        }

        try await client.sendExpectingEmpty(
            Endpoint.updateTaskPosition(taskId: 1),
            body: TaskPositionRequest(position: 2.0, projectViewId: 1)
        )
        // Success if no error thrown
    }

    func testSendExpectingEmptyThrowsOn401() async {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "bad-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 401, url: request.url)
            return (response, Data())
        }

        do {
            try await client.sendExpectingEmpty(
                Endpoint.updateTaskPosition(taskId: 1),
                body: TaskPositionRequest(position: 1.0, projectViewId: 1)
            )
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

    // MARK: - sendRawData() Tests

    func testSendRawDataSucceeds() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, Data())
        }

        let bodyData = "{\"title\": \"test\"}".data(using: .utf8)
        try await client.sendRawData(Endpoint.updateTask(id: 1), bodyData: bodyData)
        // Success if no error thrown
    }

    func testSendRawDataThrowsServerError() async throws {
        let client = makeTestClient()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let errorJSON = try XCTUnwrap("""
        {"code": 503, "message": "Service Unavailable"}
        """.data(using: .utf8))

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 503, url: request.url)
            return (response, errorJSON)
        }

        do {
            try await client.sendRawData(Endpoint.updateTask(id: 1), bodyData: nil)
            XCTFail("Expected server error")
        } catch let error as NetworkError {
            if case let .serverError(statusCode, message) = error {
                XCTAssertEqual(statusCode, 503)
                XCTAssertEqual(message, "Service Unavailable")
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
