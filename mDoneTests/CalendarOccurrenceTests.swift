import XCTest
@testable import mDone

/// Issue #35: a repeating task used to appear on its current due date and
/// nowhere else, so a daily habit was invisible on tomorrow's calendar. These
/// tests cover the layer that turns `AppState.tasks` into what the calendar
/// draws: which days a task appears on, and which of those appearances are
/// projections the app worked out rather than dates the server scheduled.
///
/// Dates are built with `Calendar.current`, because that is what `AppState`
/// uses, so the day keys line up whatever time zone the tests run in. The
/// recurrence arithmetic itself is pinned against a fixed calendar in
/// `TaskRecurrenceTests`.
@MainActor
final class CalendarOccurrenceTests: XCTestCase {
    private let calendar = Calendar.current

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
    }

    private func repeatingTask(
        id: Int64 = 1,
        due: Date?,
        repeatAfter: Int64?,
        repeatMode: Int64? = nil,
        done: Bool = false
    ) -> VTask {
        VTask(
            id: id,
            title: "Water the plants",
            done: done,
            dueDate: due,
            priority: 0,
            projectId: 1,
            repeatAfter: repeatAfter,
            repeatMode: repeatMode
        )
    }

    // MARK: - The reported bug

    func testADailyTaskAppearsOnEveryRemainingDayOfTheMonth() throws {
        let appState = AppState()
        let due = try date(2026, 5, 5)
        appState.tasks = [repeatingTask(due: due, repeatAfter: 86400)]

        let byDay = appState.occurrencesByDay(in: due)

        // The 5th through the 31st.
        XCTAssertEqual(byDay.count, 27)
        XCTAssertEqual(byDay[calendar.startOfDay(for: due)]?.map(\.isProjected), [false])
        for day in 6 ... 31 {
            let key = try calendar.startOfDay(for: date(2026, 5, day))
            XCTAssertEqual(byDay[key]?.map(\.isProjected), [true], "day \(day)")
        }
    }

    func testADailyTaskAppearsOnTomorrowsDayList() throws {
        let appState = AppState()
        let due = try date(2026, 5, 5)
        appState.tasks = [repeatingTask(due: due, repeatAfter: 86400)]

        let tomorrow = appState.occurrences(on: try date(2026, 5, 6))

        XCTAssertEqual(tomorrow.count, 1)
        XCTAssertEqual(tomorrow.first?.isProjected, true)
        XCTAssertEqual(tomorrow.first?.projectedDueDate, try date(2026, 5, 6))
    }

    /// The whole point of the design. A projection carries the real task rather
    /// than a synthesized stand-in with an invented id, so nothing that resolves
    /// a task by id can be pointed at a row the server does not have.
    func testAProjectionCarriesTheRealTask() throws {
        let appState = AppState()
        let due = try date(2026, 5, 5)
        let task = repeatingTask(id: 4242, due: due, repeatAfter: 86400)
        appState.tasks = [task]

        let laterDay = try date(2026, 5, 9)
        let projected = try XCTUnwrap(appState.occurrences(on: laterDay).first)

        XCTAssertTrue(projected.isProjected)
        XCTAssertEqual(projected.task.id, 4242)
        XCTAssertEqual(projected.task, task)
    }

    /// Projections are computed on read and never stored. This is what keeps
    /// them out of the SwiftData cache, the offline operation queue, the
    /// widget's shared data and notification identifiers, all of which are fed
    /// from `tasks`.
    func testProjectingDoesNotChangeTheTaskList() throws {
        let appState = AppState()
        let due = try date(2026, 5, 5)
        appState.tasks = [repeatingTask(due: due, repeatAfter: 86400)]
        let before = appState.tasks

        let laterDay = try date(2026, 5, 9)
        _ = appState.occurrencesByDay(in: due)
        _ = appState.occurrences(on: laterDay)

        XCTAssertEqual(appState.tasks, before)
    }

    // MARK: - A real placement always wins

    /// A task repeating every hour has a projection due later on its own due
    /// date. The real placement is the one that renders, so the row stays
    /// interactive on the day the task is actually due.
    func testARealPlacementIsNotDisplacedByAProjectionOnTheSameDay() throws {
        let appState = AppState()
        let due = try date(2026, 5, 5)
        appState.tasks = [repeatingTask(due: due, repeatAfter: 3600)]

        let onTheDueDate = appState.occurrencesByDay(in: due)[calendar.startOfDay(for: due)]

        XCTAssertEqual(onTheDueDate?.count, 1)
        XCTAssertEqual(onTheDueDate?.first?.isProjected, false)
    }

    // MARK: - Monthly repeats

    func testAMonthlyTaskWithNoIntervalIsStillProjected() throws {
        let appState = AppState()
        let due = try date(2026, 1, 31)
        appState.tasks = [repeatingTask(due: due, repeatAfter: 0, repeatMode: 1)]

        let february = try appState.occurrencesByDay(in: date(2026, 2, 15))
        let monthEndKey = try calendar.startOfDay(for: date(2026, 2, 28))

        XCTAssertEqual(february.count, 1)
        XCTAssertEqual(february[monthEndKey]?.map(\.isProjected), [true])
    }

    // MARK: - What is deliberately not projected

    func testATaskRepeatingFromItsCompletionTimeIsNotProjected() throws {
        let appState = AppState()
        let due = try date(2026, 5, 5)
        appState.tasks = [repeatingTask(due: due, repeatAfter: 86400, repeatMode: 2)]

        let byDay = appState.occurrencesByDay(in: due)

        XCTAssertEqual(byDay.count, 1)
        XCTAssertEqual(byDay[calendar.startOfDay(for: due)]?.map(\.isProjected), [false])
    }

    func testACompletedTaskIsNotProjected() throws {
        let appState = AppState()
        let due = try date(2026, 5, 5)
        appState.tasks = [repeatingTask(due: due, repeatAfter: 86400, done: true)]

        XCTAssertEqual(appState.occurrencesByDay(in: due).count, 1)
    }

    func testATaskWithNoDueDateIsNotProjected() throws {
        let appState = AppState()
        appState.tasks = [repeatingTask(due: nil, repeatAfter: 86400)]
        let anyMonth = try date(2026, 5, 15)

        XCTAssertTrue(appState.occurrencesByDay(in: anyMonth).isEmpty)
    }

    func testANonRepeatingTaskAppearsOnlyOnItsDueDate() throws {
        let appState = AppState()
        let due = try date(2026, 5, 5)
        appState.tasks = [repeatingTask(due: due, repeatAfter: nil)]

        let byDay = appState.occurrencesByDay(in: due)

        XCTAssertEqual(byDay.count, 1)
        XCTAssertEqual(byDay[calendar.startOfDay(for: due)]?.map(\.isProjected), [false])
        let nextDay = try date(2026, 5, 6)
        XCTAssertTrue(appState.occurrences(on: nextDay).isEmpty)
    }
}
