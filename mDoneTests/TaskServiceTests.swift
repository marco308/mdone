import XCTest
@testable import mDone

final class TaskServiceTests: XCTestCase {

    func testVTaskSmartListFiltering() {
        let now = Date()
        let calendar = Calendar.current

        let overdueTask = VTask(
            id: 1, title: "Overdue", done: false,
            dueDate: calendar.date(byAdding: .day, value: -2, to: now),
            priority: 3, projectId: 1
        )

        let todayEndOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
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
}
