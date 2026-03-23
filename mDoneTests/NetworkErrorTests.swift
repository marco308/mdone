import XCTest
@testable import mDone

final class NetworkErrorTests: XCTestCase {
    // MARK: - Error Descriptions

    func testInvalidURLDescription() throws {
        let error = NetworkError.invalidURL
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(try XCTUnwrap(error.errorDescription?.isEmpty))
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.lowercased().contains("url")))
    }

    func testUnauthorizedDescription() throws {
        let error = NetworkError.unauthorized
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(try XCTUnwrap(error.errorDescription?.isEmpty))
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.lowercased().contains("auth")))
    }

    func testServerErrorDescriptionWithMessage() {
        let error = NetworkError.serverError(statusCode: 500, message: "Internal Server Error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertEqual(error.errorDescription, "Internal Server Error")
    }

    func testServerErrorDescriptionWithoutMessage() throws {
        let error = NetworkError.serverError(statusCode: 503, message: nil)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.contains("503")))
    }

    func testDecodingErrorDescription() throws {
        let underlyingError = NSError(domain: "Test", code: 0)
        let error = NetworkError.decodingError(underlyingError)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(try XCTUnwrap(error.errorDescription?.isEmpty))
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.lowercased().contains("parse")) || error.errorDescription!
            .lowercased().contains("decod"))
    }

    func testNetworkUnavailableDescription() throws {
        let error = NetworkError.networkUnavailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(try XCTUnwrap(error.errorDescription?.isEmpty))
        XCTAssertTrue(try XCTUnwrap(error.errorDescription?.lowercased().contains("internet")) || error
            .errorDescription!.lowercased().contains("connection") || error.errorDescription!.lowercased()
            .contains("network"))
    }

    func testUnknownErrorDescription() throws {
        let underlying = URLError(.timedOut)
        let error = NetworkError.unknown(underlying)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(try XCTUnwrap(error.errorDescription?.isEmpty))
    }

    // MARK: - All Error Cases Have Descriptions

    func testAllNetworkErrorCasesHaveDescriptions() throws {
        let errors: [NetworkError] = [
            .invalidURL,
            .unauthorized,
            .serverError(statusCode: 400, message: "Bad Request"),
            .serverError(statusCode: 500, message: nil),
            .decodingError(NSError(domain: "Test", code: 0)),
            .networkUnavailable,
            .unknown(URLError(.notConnectedToInternet)),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(
                try XCTUnwrap(error.errorDescription?.isEmpty),
                "Error \(error) description should not be empty"
            )
        }
    }

    // MARK: - APIError Model

    func testAPIErrorDecoding() throws {
        let json = """
        {"code": 404, "message": "Not found"}
        """.data(using: .utf8)!

        let error = try JSONDecoder().decode(APIError.self, from: json)
        XCTAssertEqual(error.code, 404)
        XCTAssertEqual(error.message, "Not found")
    }

    func testAPIErrorPartialDecoding() throws {
        let json = """
        {"message": "Something went wrong"}
        """.data(using: .utf8)!

        let error = try JSONDecoder().decode(APIError.self, from: json)
        XCTAssertNil(error.code)
        XCTAssertEqual(error.message, "Something went wrong")
    }

    func testAPIErrorEmptyDecoding() throws {
        let json = "{}".data(using: .utf8)!

        let error = try JSONDecoder().decode(APIError.self, from: json)
        XCTAssertNil(error.code)
        XCTAssertNil(error.message)
    }

    // MARK: - LoginRequest / LoginResponse

    func testLoginRequestEncoding() throws {
        let request = LoginRequest(username: "testuser", password: "secret123")
        let data = try JSONEncoder().encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["username"] as? String, "testuser")
        XCTAssertEqual(json?["password"] as? String, "secret123")
    }

    func testLoginResponseDecoding() throws {
        let json = """
        {"token": "eyJhbGciOiJIUzI1NiJ9.test.signature"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)
        XCTAssertEqual(response.token, "eyJhbGciOiJIUzI1NiJ9.test.signature")
    }

    // MARK: - Endpoint Tests

    func testLoginEndpoint() {
        let endpoint = Endpoint.login
        XCTAssertEqual(endpoint.path, "/api/v1/login")
        XCTAssertEqual(endpoint.method, .POST)
    }

    func testLabelsEndpoint() {
        let endpoint = Endpoint.labels()
        XCTAssertEqual(endpoint.path, "/api/v1/labels")
        XCTAssertEqual(endpoint.method, .GET)
        XCTAssertNotNil(endpoint.queryItems)
    }

    func testNotificationsEndpoint() {
        let endpoint = Endpoint.notifications()
        XCTAssertEqual(endpoint.path, "/api/v1/notifications")
        XCTAssertEqual(endpoint.method, .GET)
    }

    func testMarkNotificationReadEndpoint() {
        let endpoint = Endpoint.markNotificationRead(id: 42)
        XCTAssertEqual(endpoint.path, "/api/v1/notifications/42")
        XCTAssertEqual(endpoint.method, .POST)
    }

    func testMarkAllNotificationsReadEndpoint() {
        let endpoint = Endpoint.markAllNotificationsRead
        XCTAssertEqual(endpoint.path, "/api/v1/notifications")
        XCTAssertEqual(endpoint.method, .POST)
    }

    func testAllTasksEndpointWithFilter() {
        let endpoint = Endpoint.allTasks(filter: "done = false", sortBy: "due_date", orderBy: "asc")
        XCTAssertEqual(endpoint.path, "/api/v1/tasks")

        let queryNames = endpoint.queryItems?.map(\.name) ?? []
        XCTAssertTrue(queryNames.contains("filter"))
        XCTAssertTrue(queryNames.contains("sort_by"))
        XCTAssertTrue(queryNames.contains("order_by"))

        let filterValue = endpoint.queryItems?.first(where: { $0.name == "filter" })?.value
        XCTAssertEqual(filterValue, "done = false")
    }

    func testAllTasksEndpointWithSearch() {
        let endpoint = Endpoint.allTasks(search: "groceries")
        let searchValue = endpoint.queryItems?.first(where: { $0.name == "s" })?.value
        XCTAssertEqual(searchValue, "groceries")
    }

    func testProjectTasksEndpoint() {
        let endpoint = Endpoint.projectTasks(projectId: 3, viewId: 7, page: 2, perPage: 25)
        XCTAssertEqual(endpoint.path, "/api/v1/projects/3/views/7/tasks")
        XCTAssertEqual(endpoint.method, .GET)

        let pageValue = endpoint.queryItems?.first(where: { $0.name == "page" })?.value
        XCTAssertEqual(pageValue, "2")

        let perPageValue = endpoint.queryItems?.first(where: { $0.name == "per_page" })?.value
        XCTAssertEqual(perPageValue, "25")
    }

    func testProjectViewsEndpoint() {
        let endpoint = Endpoint.projectViews(projectId: 10)
        XCTAssertEqual(endpoint.path, "/api/v1/projects/10/views")
        XCTAssertEqual(endpoint.method, .GET)
    }

    func testUpdateTaskPositionEndpoint() {
        let endpoint = Endpoint.updateTaskPosition(taskId: 5)
        XCTAssertEqual(endpoint.path, "/api/v1/tasks/5/position")
        XCTAssertEqual(endpoint.method, .POST)
    }

    func testTaskEndpoint() {
        let endpoint = Endpoint.task(id: 99)
        XCTAssertEqual(endpoint.path, "/api/v1/tasks/99")
        XCTAssertEqual(endpoint.method, .GET)
    }

    // MARK: - HTTPMethod

    func testHTTPMethodRawValues() {
        XCTAssertEqual(HTTPMethod.GET.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.POST.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.PUT.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.DELETE.rawValue, "DELETE")
    }

    // MARK: - PriorityLevel

    func testPriorityLevelLabels() {
        XCTAssertEqual(PriorityLevel.none.label, "None")
        XCTAssertEqual(PriorityLevel.low.label, "Low")
        XCTAssertEqual(PriorityLevel.medium.label, "Medium")
        XCTAssertEqual(PriorityLevel.high.label, "High")
        XCTAssertEqual(PriorityLevel.urgent.label, "Urgent")
        XCTAssertEqual(PriorityLevel.critical.label, "Critical")
    }

    func testPriorityLevelAllCases() {
        XCTAssertEqual(PriorityLevel.allCases.count, 6)
        XCTAssertEqual(PriorityLevel.allCases.first, PriorityLevel.none)
        XCTAssertEqual(PriorityLevel.allCases.last, .critical)
    }

    func testPriorityLevelInvalidRawValue() {
        XCTAssertNil(PriorityLevel(rawValue: -1))
        XCTAssertNil(PriorityLevel(rawValue: 6))
        XCTAssertNil(PriorityLevel(rawValue: 100))
    }

    // MARK: - User Model

    func testUserDisplayNameWithName() {
        let user = User(id: 1, username: "john", name: "John Doe")
        XCTAssertEqual(user.displayName, "John Doe")
    }

    func testUserDisplayNameFallsBackToUsername() {
        let user = User(id: 1, username: "john")
        XCTAssertEqual(user.displayName, "john")
    }

    func testUserDisplayNameFallsBackToUnknown() {
        let user = User(id: 1)
        XCTAssertEqual(user.displayName, "Unknown")
    }

    func testUserEquality() {
        let user1 = User(id: 1, username: "john")
        let user2 = User(id: 1, username: "different")
        let user3 = User(id: 2, username: "john")

        XCTAssertEqual(user1, user2)
        XCTAssertNotEqual(user1, user3)
    }

    // MARK: - VTask Equality and Hashing

    func testVTaskEquality() {
        let task1 = VTask(id: 1, title: "First", done: false, priority: 0, projectId: 1)
        let task2 = VTask(id: 1, title: "Different", done: true, priority: 5, projectId: 2)
        let task3 = VTask(id: 2, title: "First", done: false, priority: 0, projectId: 1)

        XCTAssertEqual(task1, task2, "Tasks with same ID should be equal")
        XCTAssertNotEqual(task1, task3, "Tasks with different IDs should not be equal")
    }

    func testVTaskHashable() {
        let task1 = VTask(id: 1, title: "First", done: false, priority: 0, projectId: 1)
        let task2 = VTask(id: 1, title: "Different", done: true, priority: 5, projectId: 2)

        var set: Set<VTask> = [task1]
        set.insert(task2)

        XCTAssertEqual(set.count, 1, "Tasks with same ID should hash equally")
    }
}
