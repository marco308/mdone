import XCTest
@testable import mDone

final class TaskServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - VTask Computed Properties

    func testVTaskSmartListFiltering() throws {
        let now = Date()
        let calendar = Calendar.current

        let overdueTask = VTask(
            id: 1, title: "Overdue", done: false,
            dueDate: calendar.date(byAdding: .day, value: -2, to: now),
            priority: 3, projectId: 1
        )

        let todayEndOfDay = try XCTUnwrap(calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now))
        let todayTask = VTask(
            id: 2, title: "Today", done: false,
            dueDate: todayEndOfDay,
            priority: 2, projectId: 1
        )

        let upcomingTask = VTask(
            id: 3, title: "Upcoming", done: false,
            dueDate: calendar.date(byAdding: .day, value: 3, to: now),
            priority: 1, projectId: 1
        )

        let noDateTask = VTask(
            id: 4, title: "No Date", done: false,
            priority: 0, projectId: 1
        )

        let doneTask = VTask(
            id: 5, title: "Done", done: true,
            dueDate: now,
            priority: 1, projectId: 1
        )

        XCTAssertTrue(overdueTask.isOverdue)
        XCTAssertFalse(todayTask.isOverdue)
        XCTAssertTrue(todayTask.isDueToday)
        XCTAssertFalse(overdueTask.isDueToday)
        XCTAssertTrue(upcomingTask.isDueThisWeek)
        XCTAssertFalse(doneTask.isDueToday)
        XCTAssertFalse(doneTask.isOverdue)
        XCTAssertNil(noDateTask.dueDate)
    }

    func testVTaskPriorityMapping() {
        let task0 = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1)
        let task1 = VTask(id: 2, title: "T", done: false, priority: 1, projectId: 1)
        let task3 = VTask(id: 3, title: "T", done: false, priority: 3, projectId: 1)
        let task5 = VTask(id: 4, title: "T", done: false, priority: 5, projectId: 1)

        XCTAssertEqual(task0.priorityLevel, .none)
        XCTAssertEqual(task1.priorityLevel, .low)
        XCTAssertEqual(task3.priorityLevel, .high)
        XCTAssertEqual(task5.priorityLevel, .critical)
    }

    func testTaskCreateRequestEncoding() throws {
        let request = TaskCreateRequest(
            title: "New task",
            dueDate: nil,
            priority: 3
        )

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["title"] as? String, "New task")
        XCTAssertEqual(json?["priority"] as? Int, 3)
    }

    // MARK: - VTask isDueTomorrow

    func testIsDueTomorrow() throws {
        let calendar = Calendar.current
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        let tomorrowNoon = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow))

        let task = VTask(id: 1, title: "Tomorrow Task", done: false, dueDate: tomorrowNoon, priority: 0, projectId: 1)
        XCTAssertTrue(task.isDueTomorrow)
        XCTAssertFalse(task.isDueToday)
        XCTAssertFalse(task.isOverdue)
    }

    func testDoneTaskIsNotDueTomorrow() throws {
        let calendar = Calendar.current
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: Date()))
        let tomorrowNoon = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow))

        let task = VTask(id: 1, title: "Done Tomorrow", done: true, dueDate: tomorrowNoon, priority: 0, projectId: 1)
        XCTAssertFalse(task.isDueTomorrow)
    }

    // MARK: - VTask effectiveDueDate

    func testEffectiveDueDateReturnsNilForDistantPast() {
        let task = VTask(id: 1, title: "T", done: false, dueDate: Date.distantPast, priority: 0, projectId: 1)
        XCTAssertNil(task.effectiveDueDate)
    }

    func testEffectiveDueDateReturnsDateForNormalDate() {
        let dueDate = Date()
        let task = VTask(id: 1, title: "T", done: false, dueDate: dueDate, priority: 0, projectId: 1)
        XCTAssertEqual(task.effectiveDueDate, dueDate)
    }

    func testEffectiveDueDateReturnsNilWhenNoDueDate() {
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1)
        XCTAssertNil(task.effectiveDueDate)
    }

    // MARK: - VTask isRepeating

    func testIsRepeatingTrue() {
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1, repeatAfter: 86400)
        XCTAssertTrue(task.isRepeating)
    }

    func testIsRepeatingFalseWhenZero() {
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1, repeatAfter: 0)
        XCTAssertFalse(task.isRepeating)
    }

    func testIsRepeatingFalseWhenNil() {
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1)
        XCTAssertFalse(task.isRepeating)
    }

    // MARK: - VTask repeatDescription

    func testRepeatDescriptionDaily() {
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1, repeatAfter: 86400)
        XCTAssertEqual(task.repeatDescription, "Daily")
    }

    func testRepeatDescriptionWeekly() {
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1, repeatAfter: 604_800)
        XCTAssertEqual(task.repeatDescription, "Weekly")
    }

    func testRepeatDescriptionMonthly() {
        // 30 days = 2592000 seconds
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1, repeatAfter: 2_592_000)
        XCTAssertEqual(task.repeatDescription, "Monthly")
    }

    func testRepeatDescriptionYearly() {
        // 365 days = 31536000 seconds
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1, repeatAfter: 31_536_000)
        XCTAssertEqual(task.repeatDescription, "Yearly")
    }

    func testRepeatDescriptionNilWhenNoRepeat() {
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1)
        XCTAssertNil(task.repeatDescription)
    }

    func testRepeatDescriptionCustomDays() {
        // 3 days = 259200 seconds
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1, repeatAfter: 259_200)
        XCTAssertEqual(task.repeatDescription, "Every 3 days")
    }

    func testRepeatDescriptionCustomHours() {
        // 2 hours = 7200 seconds
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1, repeatAfter: 7200)
        XCTAssertEqual(task.repeatDescription, "Every 2 hours")
    }

    // MARK: - VTask hasSpecificTime

    func testHasSpecificTimeTrue() throws {
        let calendar = Calendar.current
        let dateWithTime = try XCTUnwrap(calendar.date(bySettingHour: 14, minute: 30, second: 0, of: Date()))
        let task = VTask(id: 1, title: "T", done: false, dueDate: dateWithTime, priority: 0, projectId: 1)
        XCTAssertTrue(task.hasSpecificTime)
    }

    func testHasSpecificTimeFalseAtMidnight() {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: Date())
        let task = VTask(id: 1, title: "T", done: false, dueDate: midnight, priority: 0, projectId: 1)
        XCTAssertFalse(task.hasSpecificTime)
    }

    func testHasSpecificTimeFalseWhenNoDueDate() {
        let task = VTask(id: 1, title: "T", done: false, priority: 0, projectId: 1)
        XCTAssertFalse(task.hasSpecificTime)
    }

    // MARK: - VTask with nil optional fields

    func testTaskWithMinimalFields() {
        let task = VTask(id: 1, title: "Minimal", done: false, priority: 0, projectId: 1)
        XCTAssertNil(task.description)
        XCTAssertNil(task.dueDate)
        XCTAssertNil(task.hexColor)
        XCTAssertNil(task.percentDone)
        XCTAssertNil(task.labels)
        XCTAssertNil(task.assignees)
        XCTAssertNil(task.reminders)
        XCTAssertNil(task.isFavorite)
        XCTAssertNil(task.uid)
        XCTAssertNil(task.startDate)
        XCTAssertNil(task.endDate)
        XCTAssertNil(task.repeatAfter)
        XCTAssertNil(task.repeatMode)
        XCTAssertNil(task.createdBy)
        XCTAssertNil(task.created)
        XCTAssertNil(task.updated)
    }

    // MARK: - TaskService Network Tests

    private func makeTestService() -> (TaskService, APIClient) {
        let client = APIClient(session: MockURLProtocol.mockSession())
        let service = TaskService(apiClient: client)
        return (service, client)
    }

    func testFetchAllTasksReturnsTasks() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let tasksJSON = """
        [
            {"id": 1, "title": "Task A", "done": false, "priority": 1, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"},
            {"id": 2, "title": "Task B", "done": true, "priority": 3, "project_id": 2, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        ]
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(
                statusCode: 200,
                url: request.url,
                headers: ["x-pagination-total-pages": "1"]
            )
            return (response, tasksJSON)
        }

        let tasks = try await service.fetchAllTasks()
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].title, "Task A")
        XCTAssertEqual(tasks[1].title, "Task B")
        XCTAssertTrue(tasks[1].done)
    }

    func testFetchTaskReturnsTask() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let taskJSON = """
        {"id": 42, "title": "Specific Task", "done": false, "priority": 2, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-15T08:00:00Z"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/tasks/42") == true)
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, taskJSON)
        }

        let task = try await service.fetchTask(id: 42)
        XCTAssertEqual(task.id, 42)
        XCTAssertEqual(task.title, "Specific Task")
    }

    func testCreateTaskSendsCorrectEndpoint() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let responseJSON = """
        {"id": 100, "title": "New Task", "done": false, "priority": 2, "project_id": 5, "created": "2026-03-20T10:00:00Z", "updated": "2026-03-20T10:00:00Z"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/projects/5/tasks") == true)
            XCTAssertEqual(request.httpMethod, "PUT")
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, responseJSON)
        }

        let createRequest = TaskCreateRequest(title: "New Task", priority: 2)
        let task = try await service.createTask(projectId: 5, request: createRequest)
        XCTAssertEqual(task.id, 100)
        XCTAssertEqual(task.title, "New Task")
        XCTAssertEqual(task.projectId, 5)
    }

    func testUpdateTaskSendsCorrectEndpoint() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let responseJSON = """
        {"id": 10, "title": "Updated Task", "done": false, "priority": 4, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-20T10:00:00Z"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/tasks/10") == true)
            XCTAssertEqual(request.httpMethod, "POST")
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, responseJSON)
        }

        let updateRequest = TaskUpdateRequest(title: "Updated Task", priority: 4)
        let task = try await service.updateTask(id: 10, request: updateRequest)
        XCTAssertEqual(task.id, 10)
        XCTAssertEqual(task.title, "Updated Task")
    }

    func testToggleDoneFlipsState() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let originalTask = VTask(id: 7, title: "Toggle Me", done: false, priority: 1, projectId: 1)

        let responseJSON = """
        {"id": 7, "title": "Toggle Me", "done": true, "priority": 1, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-20T10:00:00Z"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/tasks/7") == true)
            XCTAssertEqual(request.httpMethod, "POST")

            // Verify the body contains done: true (toggled from false)
            if let bodyData = request.httpBody,
               let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            {
                XCTAssertEqual(bodyJSON["done"] as? Bool, true)
            }

            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, responseJSON)
        }

        let toggled = try await service.toggleDone(task: originalTask)
        XCTAssertTrue(toggled.done)
    }

    func testToggleDoneFlipsFromDoneToUndone() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let originalTask = VTask(id: 8, title: "Undone Me", done: true, priority: 1, projectId: 1)

        let responseJSON = """
        {"id": 8, "title": "Undone Me", "done": false, "priority": 1, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-20T10:00:00Z"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            if let bodyData = request.httpBody,
               let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
            {
                XCTAssertEqual(bodyJSON["done"] as? Bool, false)
            }

            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, responseJSON)
        }

        let toggled = try await service.toggleDone(task: originalTask)
        XCTAssertFalse(toggled.done)
    }

    func testDeleteTaskCallsDeleteEndpoint() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/tasks/42") == true)
            XCTAssertEqual(request.httpMethod, "DELETE")
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, Data())
        }

        try await service.deleteTask(id: 42)
        // Success if no error thrown
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    func testUpdatePositionSendsCorrectEndpoint() async throws {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/tasks/5/position") == true)
            XCTAssertEqual(request.httpMethod, "POST")
            let response = MockURLProtocol.makeResponse(statusCode: 200, url: request.url)
            return (response, Data())
        }

        try await service.updatePosition(taskId: 5, position: 3.0, viewId: 1)
        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 1)
    }

    // MARK: - TaskService Error Handling

    func testFetchAllTasksThrowsOnUnauthorized() async {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "expired-token")

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 401, url: request.url)
            return (response, Data())
        }

        do {
            _ = try await service.fetchAllTasks()
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

    func testCreateTaskThrowsOnServerError() async {
        let (service, client) = makeTestService()
        await client.configure(serverURL: "https://mock.vikunja.io", token: "test-token")

        let errorJSON = """
        {"code": 500, "message": "Internal Server Error"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            let response = MockURLProtocol.makeResponse(statusCode: 500, url: request.url)
            return (response, errorJSON)
        }

        do {
            _ = try await service.createTask(
                projectId: 1,
                request: TaskCreateRequest(title: "Will Fail", priority: 1)
            )
            XCTFail("Expected server error")
        } catch let error as NetworkError {
            if case let .serverError(statusCode, _) = error {
                XCTAssertEqual(statusCode, 500)
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - TaskUpdateRequest Encoding

    func testTaskUpdateRequestEncodesOnlyNonNilFields() throws {
        let request = TaskUpdateRequest(done: true)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["done"] as? Bool, true)
        // title, description, priority should not be present
        XCTAssertNil(json?["title"])
        XCTAssertNil(json?["description"])
        XCTAssertNil(json?["priority"])
    }

    func testTaskUpdateRequestClearDueDate() throws {
        let request = TaskUpdateRequest(clearDueDate: true)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // When clearDueDate is true, due_date should be encoded as distantPast
        XCTAssertNotNil(json?["due_date"])
    }
}
