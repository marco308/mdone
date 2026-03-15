import XCTest
@testable import mDone

final class APIClientTests: XCTestCase {
    func testVTaskDecoding() throws {
        let json = """
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
        """.data(using: .utf8)!

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
        let json = """
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
        """.data(using: .utf8)!

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
        let json = """
        {
            "id": 5,
            "title": "Bug",
            "hex_color": "#FF0000",
            "description": "Bug reports",
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """.data(using: .utf8)!

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
        let json = """
        {
            "id": 1,
            "username": "testuser",
            "name": "Test User",
            "email": "test@example.com",
            "created": "2026-03-15T08:00:00Z",
            "updated": "2026-03-15T08:00:00Z"
        }
        """.data(using: .utf8)!

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
        XCTAssertNotNil(NetworkError.serverError(statusCode: 500, message: "Internal error").errorDescription)
    }

    func testEndpointPaths() {
        XCTAssertEqual(Endpoint.currentUser.path, "/api/v1/user")
        XCTAssertEqual(Endpoint.currentUser.method, .GET)

        let projectsEndpoint = Endpoint.projects()
        XCTAssertEqual(projectsEndpoint.path, "/api/v1/projects")

        let createTask = Endpoint.createTask(projectId: 5)
        XCTAssertEqual(createTask.path, "/api/v1/projects/5/tasks")
        XCTAssertEqual(createTask.method, .PUT)

        let updateTask = Endpoint.updateTask(id: 10)
        XCTAssertEqual(updateTask.path, "/api/v1/tasks/10")
        XCTAssertEqual(updateTask.method, .POST)

        let deleteTask = Endpoint.deleteTask(id: 3)
        XCTAssertEqual(deleteTask.path, "/api/v1/tasks/3")
        XCTAssertEqual(deleteTask.method, .DELETE)
    }
}
