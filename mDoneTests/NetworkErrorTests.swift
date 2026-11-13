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
        let description = try XCTUnwrap(error.errorDescription).lowercased()
        XCTAssertFalse(description.isEmpty)
        // Should tell the user their session is gone, in plain language.
        XCTAssertTrue(
            description.contains("session") || description.contains("log in") || description.contains("sign in"),
            "Expected an auth-related concept, got: \(description)"
        )
    }

    func testServerErrorDescriptionHidesRawServerMessage() throws {
        // Contract: we surface a user-friendly message, NOT the raw server response.
        // (Raw 500-class messages often leak internal detail.)
        let error = NetworkError.serverError(statusCode: 500, message: "Internal Server Error: panic in goroutine 42")
        let description = try XCTUnwrap(error.errorDescription)
        XCTAssertFalse(description.isEmpty)
        XCTAssertFalse(description.contains("goroutine"), "Raw server detail leaked: \(description)")
        XCTAssertFalse(description.contains("Internal Server Error"), "Raw server message leaked: \(description)")
    }

    func testServerErrorDescriptionWithoutMessage() throws {
        let error = NetworkError.serverError(statusCode: 503, message: nil)
        let description = try XCTUnwrap(error.errorDescription)
        XCTAssertFalse(description.isEmpty)
        // 5xx errors should suggest the issue is server-side and retryable.
        let lower = description.lowercased()
        XCTAssertTrue(
            lower.contains("server") || lower.contains("try again"),
            "Expected server / retry concept, got: \(description)"
        )
    }

    func testDecodingErrorDescription() throws {
        let underlyingError = NSError(domain: "Test", code: 0)
        let error = NetworkError.decodingError(underlyingError)
        let description = try XCTUnwrap(error.errorDescription).lowercased()
        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(
            description.contains("response") || description.contains("unexpected") || description.contains("parse")
                || description.contains("decod"),
            "Expected response / parse concept, got: \(description)"
        )
    }

    func testNetworkUnavailableDescription() throws {
        let error = NetworkError.networkUnavailable
        let description = try XCTUnwrap(error.errorDescription).lowercased()
        XCTAssertFalse(description.isEmpty)
        XCTAssertTrue(
            description.contains("offline") || description.contains("online") || description.contains("internet")
                || description.contains("connection") || description.contains("network"),
            "Expected connectivity concept, got: \(description)"
        )
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
            .invalidCredentials,
            .totpRequired,
            .invalidTOTPPasscode,
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
        // Omitted, not null: Vikunja treats an empty passcode as a wrong one,
        // and an account without two-factor should never see the field.
        XCTAssertNil(json?["totp_passcode"] ?? json?["totpPasscode"])
        XCTAssertEqual(json?.count, 2)
    }

    func testLoginRequestEncodesTOTPPasscodeInSnakeCase() throws {
        // The real client encodes with `convertToSnakeCase`; the field has to
        // land as `totp_passcode`, which is what Vikunja reads (issue #179).
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let request = LoginRequest(username: "testuser", password: "secret123", totpPasscode: "123456")
        let json = try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any]

        XCTAssertEqual(json?["totp_passcode"] as? String, "123456")
        XCTAssertNil(json?["totpPasscode"])
    }

    func testLoginResponseDecoding() throws {
        let json = """
        {"token": "eyJhbGciOiJIUzI1NiJ9.test.signature"}
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)
        XCTAssertEqual(response.token, "eyJhbGciOiJIUzI1NiJ9.test.signature")
    }

    // MARK: - Endpoint Tests

    // MARK: - Error bodies (#291)

    private func decodeAPIError(_ json: String) throws -> APIError {
        try JSONDecoder().decode(APIError.self, from: Data(json.utf8))
    }

    /// v2 refuses with RFC 9457 problem+json: the text is `detail`, and
    /// Vikunja's own number is still `code`. Body captured from 2.8.0.
    func testAPIErrorDecodesProblemJSON() throws {
        let error = try decodeAPIError(
            #"{"$schema":"https://x/api/v2/schemas/VikunjaErrorModel.json","title":"Not Found","status":404,"detail":"This task does not exist","code":4002}"#
        )
        XCTAssertEqual(error.code, 4002)
        XCTAssertEqual(error.message, "This task does not exist")
    }

    /// A validation failure is a 422 with no Vikunja code at all.
    func testAPIErrorDecodesProblemJSONWithoutACode() throws {
        let error = try decodeAPIError(
            #"{"title":"Unprocessable Entity","status":422,"detail":"validation failed","errors":[{"message":"expected length >= 1","location":"body.title","value":""}]}"#
        )
        XCTAssertNil(error.code)
        XCTAssertEqual(error.message, "validation failed")
    }

    /// The auth middleware's 401, and every v1 route, still answer in the
    /// older shape.
    func testAPIErrorDecodesTheOlderCodeAndMessageShape() throws {
        let error = try decodeAPIError(
            #"{"code": 11, "message": "missing, malformed, expired or otherwise invalid token provided"}"#
        )
        XCTAssertEqual(error.code, 11)
        XCTAssertEqual(error.message, "missing, malformed, expired or otherwise invalid token provided")
    }

    func testAPIErrorPrefersDetailWhenBothArePresent() throws {
        let error = try decodeAPIError(#"{"code": 1, "message": "old", "detail": "new"}"#)
        XCTAssertEqual(error.message, "new")
    }

    func testFromResponseMapsLoginRefusalsFromProblemJSON() throws {
        let wrongPassword = try decodeAPIError(
            #"{"title":"Forbidden","status":403,"detail":"Wrong username or password.","code":1011}"#
        )
        guard case .invalidCredentials = NetworkError.fromResponse(statusCode: 403, apiError: wrongPassword) else {
            return XCTFail("403 with code 1011 is a wrong username or password")
        }

        let passcode = try decodeAPIError(
            #"{"title":"Precondition Failed","status":412,"detail":"Invalid totp passcode.","code":1017}"#
        )
        guard case .invalidTOTPPasscode = NetworkError.fromResponse(statusCode: 412, apiError: passcode) else {
            return XCTFail("412 with code 1017 is a two-factor passcode problem")
        }

        let missing = try decodeAPIError(#"{"title":"Not Found","status":404,"detail":"This task does not exist","code":4002}"#)
        guard case let .serverError(status, message) = NetworkError.fromResponse(statusCode: 404, apiError: missing) else {
            return XCTFail("anything else stays a server error")
        }
        XCTAssertEqual(status, 404)
        XCTAssertEqual(message, "This task does not exist")
    }

    func testServerTooOldNamesTheVersionsAndIsCritical() throws {
        let known = NetworkError.serverTooOld(version: VikunjaVersion(major: 2, minor: 3, patch: 1))
        let knownText = try XCTUnwrap(known.errorDescription)
        XCTAssertTrue(knownText.contains("2.3.1"))
        XCTAssertTrue(knownText.contains("2.4.0"))

        let unknown = NetworkError.serverTooOld(version: nil)
        let unknownText = try XCTUnwrap(unknown.errorDescription)
        XCTAssertTrue(unknownText.contains("2.4.0"))
        XCTAssertNotEqual(unknownText, knownText)

        XCTAssertTrue(known.isCritical)
        XCTAssertFalse(known.isConnectivityFailure)
        XCTAssertNotNil(known.recoverySuggestion)
        XCTAssertEqual(known.iconName, "server.rack")
    }

    func testLoginEndpoint() {
        let endpoint = Endpoint.login
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/login"))
        XCTAssertEqual(endpoint.method, .POST)
    }

    func testLabelsEndpoint() {
        let endpoint = Endpoint.labels()
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/labels"))
        XCTAssertEqual(endpoint.method, .GET)
        XCTAssertNotNil(endpoint.queryItems)
    }

    func testNotificationsEndpoint() {
        let endpoint = Endpoint.notifications()
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/notifications"))
        XCTAssertEqual(endpoint.method, .GET)
    }

    func testMarkNotificationReadEndpoint() {
        let endpoint = Endpoint.markNotificationRead(id: 42)
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/notifications/42"))
        XCTAssertEqual(endpoint.method, .PUT)
    }

    func testMarkAllNotificationsReadEndpoint() {
        let endpoint = Endpoint.markAllNotificationsRead
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/notifications"))
        XCTAssertEqual(endpoint.method, .POST)
    }

    func testAllTasksEndpointWithFilter() {
        let endpoint = Endpoint.allTasks(filter: "done = false", sortBy: "due_date", orderBy: "asc")
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/tasks"))

        let queryNames = endpoint.queryItems?.map(\.name) ?? []
        XCTAssertTrue(queryNames.contains("filter"))
        XCTAssertTrue(queryNames.contains("sort_by"))
        XCTAssertTrue(queryNames.contains("order_by"))

        let filterValue = endpoint.queryItems?.first(where: { $0.name == "filter" })?.value
        XCTAssertEqual(filterValue, "done = false")
    }

    func testAllTasksEndpointWithSearch() {
        let endpoint = Endpoint.allTasks(search: "groceries")
        let searchValue = endpoint.queryItems?.first(where: { $0.name == "q" })?.value
        XCTAssertEqual(searchValue, "groceries")
        XCTAssertNil(endpoint.queryItems?.first(where: { $0.name == "s" }), "v1 called this parameter s")
    }

    func testProjectTasksEndpoint() {
        let endpoint = Endpoint.projectTasks(projectId: 3, viewId: 7, page: 2, perPage: 25)
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/projects/3/views/7/tasks"))
        XCTAssertEqual(endpoint.method, .GET)

        let pageValue = endpoint.queryItems?.first(where: { $0.name == "page" })?.value
        XCTAssertEqual(pageValue, "2")

        let perPageValue = endpoint.queryItems?.first(where: { $0.name == "per_page" })?.value
        XCTAssertEqual(perPageValue, "25")
    }

    func testProjectViewsEndpoint() {
        let endpoint = Endpoint.projectViews(projectId: 10)
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/projects/10/views"))
        XCTAssertEqual(endpoint.method, .GET)
    }

    func testUpdateTaskPositionEndpoint() {
        let endpoint = Endpoint.updateTaskPosition(taskId: 5)
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/tasks/5/position"))
        XCTAssertEqual(endpoint.method, .PUT)
    }

    func testTaskEndpoint() {
        let endpoint = Endpoint.task(id: 99)
        XCTAssertEqual(endpoint.path, VikunjaAPI.path("/tasks/99"))
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

    func testVTaskEqualityComparesAllFields() {
        // Regression for #84: id-only equality made SwiftUI treat description
        // (and every other field) edits as no-ops, so the task detail sheet
        // would not re-render after a save until a cold app launch.
        let task1 = VTask(id: 1, title: "First", done: false, priority: 0, projectId: 1)
        let task2 = VTask(id: 1, title: "Different", done: true, priority: 5, projectId: 2)
        let task3 = VTask(id: 2, title: "First", done: false, priority: 0, projectId: 1)
        let task4 = VTask(id: 1, title: "First", done: false, priority: 0, projectId: 1)

        XCTAssertNotEqual(task1, task2, "Tasks differing in any field must not be equal")
        XCTAssertNotEqual(task1, task3, "Tasks with different IDs are not equal")
        XCTAssertEqual(task1, task4, "Tasks with identical fields are equal")
    }

    func testVTaskDescriptionChangeBreaksEquality() {
        // Specific scenario from #84: edit a task to add a description, save,
        // re-open. The "before" and "after" VTask values must compare unequal
        // so SwiftUI re-evaluates views holding the task.
        let before = VTask(id: 1, title: "Task", description: nil, done: false, priority: 0, projectId: 1)
        let after = VTask(id: 1, title: "Task", description: "Added later", done: false, priority: 0, projectId: 1)

        XCTAssertNotEqual(before, after, "A description change must produce an unequal VTask (#84)")
    }

    func testVTaskHashable() {
        let task1 = VTask(id: 1, title: "First", done: false, priority: 0, projectId: 1)
        let task2 = VTask(id: 1, title: "Different", done: true, priority: 5, projectId: 2)
        let task1Copy = VTask(id: 1, title: "First", done: false, priority: 0, projectId: 1)

        var set: Set<VTask> = [task1]
        set.insert(task2)
        set.insert(task1Copy)

        XCTAssertEqual(set.count, 2, "Tasks differing in any field are distinct Set members; identical copies dedupe")
    }
}
