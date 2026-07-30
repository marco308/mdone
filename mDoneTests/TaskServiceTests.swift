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

    // MARK: - VTask date ranges

    func testEffectiveStartDateReturnsNilForVikunjaZeroDate() {
        let task = VTask(
            id: 1,
            title: "T",
            done: false,
            startDate: .distantPast,
            priority: 0,
            projectId: 1
        )

        XCTAssertNil(task.effectiveStartDate)
    }

    func testEffectiveEndDateReturnsNilForVikunjaZeroDate() {
        let task = VTask(
            id: 1,
            title: "T",
            done: false,
            endDate: .distantPast,
            priority: 0,
            projectId: 1
        )

        XCTAssertNil(task.effectiveEndDate)
    }

    func testTaskOccursOnEveryDayInInclusiveDateRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))

        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 9
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 26, hour: 17
        )))
        let task = VTask(
            id: 1,
            title: "Conference",
            done: false,
            startDate: start,
            endDate: end,
            priority: 0,
            projectId: 1
        )

        for day in 24 ... 26 {
            let date = try XCTUnwrap(calendar.date(from: DateComponents(
                year: 2026, month: 10, day: day, hour: 12
            )))
            XCTAssertTrue(task.occurs(on: date, calendar: calendar))
        }

        let dayAfter = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 27, hour: 12
        )))
        XCTAssertFalse(task.occurs(on: dayAfter, calendar: calendar))
    }

    func testTaskWithOnlyStartDateOccursOnStartDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 25, hour: 9
        )))
        let task = VTask(
            id: 1,
            title: "Kickoff",
            done: false,
            startDate: start,
            priority: 0,
            projectId: 1
        )

        XCTAssertTrue(task.occurs(on: start, calendar: calendar))
        let nextDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: start))
        XCTAssertFalse(task.occurs(on: nextDay, calendar: calendar))
    }

    func testTaskWithOnlyEndDateOccursOnEndDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 25, hour: 17
        )))
        let task = VTask(
            id: 1,
            title: "Deadline",
            done: false,
            endDate: end,
            priority: 0,
            projectId: 1
        )

        XCTAssertTrue(task.occurs(on: end, calendar: calendar))
        let previousDay = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: end))
        XCTAssertFalse(task.occurs(on: previousDay, calendar: calendar))
    }

    func testTaskWithOnlyDueDateOccursOnDueDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        let due = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 3, hour: 14
        )))
        let task = VTask(
            id: 1,
            title: "Submit",
            done: false,
            dueDate: due,
            priority: 0,
            projectId: 1
        )

        XCTAssertTrue(task.occurs(on: due, calendar: calendar))
    }

    func testDueDateAddsAnOccurrenceOutsideTheTaskRange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 24, hour: 9
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 26, hour: 17
        )))
        let due = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 30, hour: 12
        )))
        let between = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 28, hour: 12
        )))
        let task = VTask(
            id: 15,
            title: "Range plus due",
            done: false,
            dueDate: due,
            startDate: start,
            endDate: end,
            priority: 0,
            projectId: 1
        )

        XCTAssertTrue(task.occurs(on: start, calendar: calendar))
        XCTAssertTrue(task.occurs(on: due, calendar: calendar))
        XCTAssertFalse(task.occurs(on: between, calendar: calendar))
    }

    func testTaskWithReversedRangeStillOccursBetweenBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Zurich"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 5, hour: 9
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 3, hour: 17
        )))
        let middle = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 4, hour: 12
        )))
        let task = VTask(
            id: 1,
            title: "Imported invalid range",
            done: false,
            startDate: start,
            endDate: end,
            priority: 0,
            projectId: 1
        )

        XCTAssertTrue(task.occurs(on: middle, calendar: calendar))
    }

    func testTaskScheduleValidationRejectsEndBeforeStart() {
        let start = Date(timeIntervalSince1970: 200)
        let end = Date(timeIntervalSince1970: 100)

        XCTAssertFalse(TaskScheduleEditor.isValid(startDate: start, endDate: end))
        XCTAssertTrue(TaskScheduleEditor.isValid(startDate: start, endDate: nil))
        XCTAssertTrue(TaskScheduleEditor.isValid(startDate: nil, endDate: end))
        XCTAssertTrue(TaskScheduleEditor.isValid(startDate: start, endDate: start))
    }

    func testRepeatModeUsesFixedIntervalWhenEditorChangesInterval() {
        let task = VTask(
            id: 16,
            title: "Calendar monthly",
            done: false,
            priority: 0,
            projectId: 1,
            repeatAfter: 2_592_000,
            repeatMode: 1
        )

        XCTAssertEqual(task.repeatMode(forEditedRepeatAfter: 2_592_000), 1)
        XCTAssertEqual(task.repeatMode(forEditedRepeatAfter: 604_800), 0)
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

    // MARK: - VTask isOverdue end-of-day grace

    func testDateOnlyTaskDueTodayIsNotOverdue() throws {
        let calendar = Calendar.current
        let midnightToday = calendar.startOfDay(for: Date())
        let task = VTask(id: 1, title: "All-day today", done: false, dueDate: midnightToday, priority: 0, projectId: 1)
        XCTAssertFalse(task.isOverdue, "A date-only task due today should not show as overdue until tomorrow")
        XCTAssertTrue(task.isDueToday)
    }

    func testDateOnlyTaskFromYesterdayIsOverdue() throws {
        let calendar = Calendar.current
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: Date())))
        let task = VTask(id: 1, title: "All-day yesterday", done: false, dueDate: yesterday, priority: 0, projectId: 1)
        XCTAssertTrue(task.isOverdue)
    }

    func testTimedTaskOverdueLogicUnchanged() throws {
        let calendar = Calendar.current
        let pastNoon = try XCTUnwrap(calendar.date(bySettingHour: 12, minute: 30, second: 0, of: Date()))
        // If the test happens to run before 12:30 local time, push to yesterday so the task is definitively overdue.
        let dueDate = pastNoon < Date() ? pastNoon : try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: pastNoon))
        let task = VTask(id: 1, title: "Timed", done: false, dueDate: dueDate, priority: 0, projectId: 1)
        XCTAssertTrue(task.hasSpecificTime)
        XCTAssertTrue(task.isOverdue)
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

        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let start = Date(timeIntervalSince1970: 1_799_900_000)
        let end = Date(timeIntervalSince1970: 1_800_100_000)
        let originalTask = VTask(
            id: 7,
            title: "Toggle Me",
            done: false,
            dueDate: due,
            startDate: start,
            endDate: end,
            priority: 1,
            projectId: 1,
            repeatAfter: 86_400,
            repeatMode: 1
        )

        let responseJSON = """
        {"id": 7, "title": "Toggle Me", "done": true, "priority": 1, "project_id": 1, "created": "2026-03-15T08:00:00Z", "updated": "2026-03-20T10:00:00Z"}
        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { request in
            XCTAssertTrue(request.url?.path.contains("/api/v1/tasks/7") == true)
            XCTAssertEqual(request.httpMethod, "POST")

            // Verify the body contains done: true (toggled from false)
            guard let bodyJSON = request.decodedJSONBody else {
                XCTFail("Expected a JSON request body")
                return (MockURLProtocol.makeResponse(statusCode: 500, url: request.url), Data())
            }
            XCTAssertEqual(bodyJSON["done"] as? Bool, true)
            XCTAssertNotNil(bodyJSON["due_date"])
            XCTAssertNotNil(bodyJSON["start_date"])
            XCTAssertNotNil(bodyJSON["end_date"])
            XCTAssertEqual(bodyJSON["repeat_after"] as? Int, 86_400)
            XCTAssertEqual(bodyJSON["repeat_mode"] as? Int, 1)

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

    func testTaskUpdateRequestEncodesStartAndEndDates() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = Date(timeIntervalSince1970: 1_800_003_600)
        let request = TaskUpdateRequest(startDate: start, endDate: end)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["start_date"])
        XCTAssertNotNil(json?["end_date"])
    }

    func testTaskUpdateRequestClearsStartAndEndDates() throws {
        let request = TaskUpdateRequest(clearStartDate: true, clearEndDate: true)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertNotNil(json?["start_date"])
        XCTAssertNotNil(json?["end_date"])
    }

    func testTaskUpdateRequestPreservesExistingSchedule() {
        let due = Date(timeIntervalSince1970: 1_800_000_000)
        let start = Date(timeIntervalSince1970: 1_799_900_000)
        let end = Date(timeIntervalSince1970: 1_800_100_000)
        let reminder = TaskReminder(reminder: due, relativePeriod: nil, relativeTo: nil)
        let task = VTask(
            id: 1,
            title: "Scheduled",
            done: false,
            dueDate: due,
            startDate: start,
            endDate: end,
            priority: 0,
            projectId: 1,
            repeatAfter: 86_400,
            repeatMode: 1,
            reminders: [reminder]
        )

        let request = TaskUpdateRequest(done: true).preservingSchedule(from: task)

        XCTAssertEqual(request.dueDate, due)
        XCTAssertEqual(request.startDate, start)
        XCTAssertEqual(request.endDate, end)
        XCTAssertEqual(request.repeatAfter, 86_400)
        XCTAssertEqual(request.repeatMode, 1)
        XCTAssertEqual(request.reminders, [reminder])
    }
}

private extension URLRequest {
    /// MockURLProtocol commonly represents request bodies as streams.
    var decodedJSONBody: [String: Any]? {
        let data: Data?
        if let body = httpBody {
            data = body
        } else if let stream = httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = Data()
            let size = 1024
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { pointer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(pointer, maxLength: size)
                if count <= 0 { break }
                buffer.append(pointer, count: count)
            }
            data = buffer.isEmpty ? nil : buffer
        } else {
            data = nil
        }
        guard let data else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
